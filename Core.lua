-- GuildDoodle Core: shared namespace, SavedVariables, palette, constants,
-- hex codec, idempotency, and central event dispatcher.
--
-- Non-goals: nothing here touches protected APIs or Blizzard dispatchers.
-- We register our own frame's OnEvent and route through ns.events.

local ADDON, ns = ...
_G.GuildDoodle = ns

------------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------------

ns.ADDON_PREFIX   = "DOODLE"          -- MUST stay 6 chars, non-negotiable
ns.PROTO_VERSION  = 1
ns.GRID_SIZE      = 32                -- 32x32 for MVP; 64x64 is post-MVP
ns.DEFAULT_COOLDOWN = 30              -- seconds between placements per player
ns.MSG_MAX        = 240               -- keep some headroom under 255 hard cap
ns.SNAPSHOT_CHUNK = 200               -- hex payload chars per SNAP chunk

-- 16 safe-on-WoW-UI colors. RGB 0-255. Index 0 = "empty" (background).
ns.PALETTE = {
  [0]  = { 0.10, 0.10, 0.12, 0.85 }, -- empty / background
  [1]  = { 1.00, 1.00, 1.00, 1.00 }, -- white
  [2]  = { 0.75, 0.75, 0.75, 1.00 }, -- light gray
  [3]  = { 0.40, 0.40, 0.40, 1.00 }, -- dark gray
  [4]  = { 0.00, 0.00, 0.00, 1.00 }, -- black
  [5]  = { 0.90, 0.20, 0.20, 1.00 }, -- red
  [6]  = { 1.00, 0.55, 0.15, 1.00 }, -- orange
  [7]  = { 1.00, 0.85, 0.20, 1.00 }, -- yellow
  [8]  = { 0.40, 0.80, 0.25, 1.00 }, -- green
  [9]  = { 0.10, 0.55, 0.30, 1.00 }, -- dark green
  [10] = { 0.20, 0.75, 0.90, 1.00 }, -- cyan
  [11] = { 0.20, 0.40, 0.90, 1.00 }, -- blue
  [12] = { 0.30, 0.20, 0.60, 1.00 }, -- indigo
  [13] = { 0.75, 0.35, 0.85, 1.00 }, -- magenta
  [14] = { 0.85, 0.55, 0.75, 1.00 }, -- pink
  [15] = { 0.55, 0.35, 0.20, 1.00 }, -- brown
}
ns.PALETTE_MAX = 15 -- valid painted color indices are 1..15; 0 = empty/erase

------------------------------------------------------------------------------
-- SavedVariables defaults
------------------------------------------------------------------------------

local function defaultDB()
  return {
    version   = ns.PROTO_VERSION,
    gridSize  = ns.GRID_SIZE,
    cooldown  = ns.DEFAULT_COOLDOWN,
    -- pixels: flat map keyed by "x,y" -> { c = colorIdx, t = ts, p = player }
    pixels    = {},
    -- lastPlace: per-player last placement epoch, for personal cooldown
    lastPlace = {},
    -- appliedTs: idempotency ledger. Key "x,y" -> last accepted timestamp.
    appliedTs = {},
    ui = {
      point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
      shown = false,
      selectedColor = 5, -- default red
    },
  }
end

function ns.EnsureDB()
  if type(GuildDoodleDB) ~= "table" then GuildDoodleDB = defaultDB() end
  local d = defaultDB()
  for k, v in pairs(d) do
    if GuildDoodleDB[k] == nil then GuildDoodleDB[k] = v end
  end
  if type(GuildDoodleDB.ui) ~= "table" then GuildDoodleDB.ui = d.ui end
  for k, v in pairs(d.ui) do
    if GuildDoodleDB.ui[k] == nil then GuildDoodleDB.ui[k] = v end
  end
  return GuildDoodleDB
end

------------------------------------------------------------------------------
-- Utility
------------------------------------------------------------------------------

function ns.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffdc5078[GuildDoodle]|r " .. tostring(msg))
end

function ns.Key(x, y) return x .. "," .. y end

function ns.PlayerName()
  local n, r = UnitFullName("player")
  if not n then return UnitName("player") or "?" end
  if r and r ~= "" then return n .. "-" .. r end
  return n
end

-- Officer soft-check per spec. Never trust for security; UI gate only.
function ns.IsOfficer()
  if IsGuildLeader and IsGuildLeader() then return true end
  if CanEditOfficerNote and CanEditOfficerNote() then return true end
  return false
end

------------------------------------------------------------------------------
-- Hex codec for snapshot payloads.
-- Grid is encoded as 32*32 = 1024 nibbles (0..15) => 512 hex chars.
-- Empty cell -> nibble 0. Painted cells -> colorIdx (1..15).
------------------------------------------------------------------------------

local HEX = "0123456789abcdef"
local HEX_LOOKUP = {}
for i = 0, 15 do HEX_LOOKUP[HEX:sub(i+1, i+1)] = i end

function ns.EncodeGridHex()
  local db = GuildDoodleDB
  local n = db.gridSize or ns.GRID_SIZE
  local out = {}
  local i = 1
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local p = db.pixels[ns.Key(x, y)]
      local c = (p and p.c) or 0
      if c < 0 or c > 15 then c = 0 end
      out[i] = HEX:sub(c + 1, c + 1)
      i = i + 1
    end
  end
  return table.concat(out)
end

function ns.DecodeGridHex(hex)
  local db = GuildDoodleDB
  local n = db.gridSize or ns.GRID_SIZE
  local expected = n * n
  if #hex ~= expected then
    ns.Print(("snapshot size mismatch: got %d hex chars, expected %d"):format(#hex, expected))
    -- Best-effort: pad or truncate.
    if #hex < expected then hex = hex .. string.rep("0", expected - #hex)
    else hex = hex:sub(1, expected) end
  end
  local now = time()
  local applied = 0
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local ch = hex:sub(y * n + x + 1, y * n + x + 1)
      local c = HEX_LOOKUP[ch] or 0
      local key = ns.Key(x, y)
      if c > 0 then
        db.pixels[key] = { c = c, t = now, p = "<snap>" }
        db.appliedTs[key] = now
        applied = applied + 1
      else
        -- respect erase: nil out only if we don't have a local painted cell
        -- (we do the safe thing and accept snapshot as authoritative)
        db.pixels[key] = nil
        db.appliedTs[key] = now
      end
    end
  end
  return applied
end

------------------------------------------------------------------------------
-- Pixel application (shared by local click + remote receive)
------------------------------------------------------------------------------

-- Returns true if applied (state changed), false if rejected/duplicate.
function ns.ApplyPixel(x, y, c, player, ts)
  local db = GuildDoodleDB
  local n = db.gridSize or ns.GRID_SIZE
  if x < 0 or y < 0 or x >= n or y >= n then return false end
  if type(c) ~= "number" or c < 0 or c > 15 then return false end
  local key = ns.Key(x, y)
  local prevTs = db.appliedTs[key]
  if prevTs and ts and ts <= prevTs then
    return false -- duplicate / older
  end
  if c == 0 then
    db.pixels[key] = nil
  else
    db.pixels[key] = { c = c, t = ts or time(), p = player or "?" }
  end
  db.appliedTs[key] = ts or time()
  if ns.UI and ns.UI.PaintCell then ns.UI.PaintCell(x, y, c) end
  return true
end

------------------------------------------------------------------------------
-- Event dispatcher (our own frame; no Blizzard-dispatcher injection)
------------------------------------------------------------------------------

ns.events = ns.events or {}
local dispatcher = CreateFrame("Frame", "GuildDoodleEventFrame")
ns.eventFrame = dispatcher

function ns.RegisterEvent(evt, handler)
  ns.events[evt] = ns.events[evt] or {}
  table.insert(ns.events[evt], handler)
  dispatcher:RegisterEvent(evt)
end

dispatcher:SetScript("OnEvent", function(self, event, ...)
  local list = ns.events[event]
  if not list then return end
  for _, h in ipairs(list) do
    -- pcall so one bad handler doesn't nuke the others
    local ok, err = pcall(h, event, ...)
    if not ok then ns.Print("handler error in " .. event .. ": " .. tostring(err)) end
  end
end)

ns.RegisterEvent("ADDON_LOADED", function(_, addonName)
  if addonName ~= ADDON then return end
  ns.EnsureDB()
  ns.Print(("v0.2.0 loaded. /doodle to open (%dx%d canvas)."):format(
    GuildDoodleDB.gridSize, GuildDoodleDB.gridSize))
end)
