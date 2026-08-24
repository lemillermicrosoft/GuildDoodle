-- GuildDoodle Comm: guild addon channel wire protocol.
--
-- Messages (all fit under 255 chars):
--   PIXEL:<x>:<y>:<c>:<ts>:<player>
--   HELLO:<player>
--   OFFER:<player>                    -- "I will send the snapshot"
--   SNAP:<seq>/<total>:<hexpayload>
--   CLEAR:<player>:<ts>
--
-- Late-join flow:
--   1. On PLAYER_ENTERING_WORLD (login only, not zone) -> send HELLO.
--   2. Every online addon user rolls random 0.5-2.5s delay.
--   3. First one to fire OFFER "wins"; others cancel their timer.
--   4. Winner encodes grid to hex and sends SNAP:1/N .. SNAP:N/N.
--
-- All incoming messages are validated. Bad ones are dropped silently
-- (not printed, to avoid channel-spam-driven log noise).

local ADDON, ns = ...
ns.Comm = ns.Comm or {}
local Comm = ns.Comm

local PREFIX = ns.ADDON_PREFIX

-- Suppression state for HELLO handling
local pendingHelloOffer = nil   -- timer handle if we've scheduled an OFFER
local recentHellos      = {}    -- player -> ts, to avoid loops

-- Snapshot receive buffers, keyed by sender
local snapBuffers = {}

------------------------------------------------------------------------------
-- Send helpers
------------------------------------------------------------------------------

local function send(msg)
  if #msg > 250 then
    ns.Print(("WARN: outgoing msg %d chars, may be truncated"):format(#msg))
  end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
  elseif SendAddonMessage then
    SendAddonMessage(PREFIX, msg, "GUILD")
  end
end

function Comm.RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
  end
end

function Comm.SendPixel(x, y, c, ts)
  local player = ns.PlayerName()
  send(("PIXEL:%d:%d:%d:%d:%s"):format(x, y, c, ts, player))
end

function Comm.SendHello()
  local player = ns.PlayerName()
  send("HELLO:" .. player)
end

function Comm.SendClear()
  local player = ns.PlayerName()
  send(("CLEAR:%s:%d"):format(player, time()))
end

------------------------------------------------------------------------------
-- Snapshot sender: chunk hex payload with SNAP:<seq>/<total>:<hex>
------------------------------------------------------------------------------

local function sendSnapshotNow()
  local hex = ns.EncodeGridHex()
  local chunkSize = ns.SNAPSHOT_CHUNK
  local total = math.ceil(#hex / chunkSize)
  if total == 0 then total = 1; hex = "" end
  -- Space out chunks so we don't blow addon-channel throttling
  for i = 1, total do
    local slice = hex:sub((i - 1) * chunkSize + 1, i * chunkSize)
    local msg = ("SNAP:%d/%d:%s"):format(i, total, slice)
    if C_Timer and C_Timer.After then
      C_Timer.After(0.15 * (i - 1), function() send(msg) end)
    else
      send(msg)
    end
  end
end

------------------------------------------------------------------------------
-- HELLO handling with random-delay election
------------------------------------------------------------------------------

local function scheduleOfferAndSnapshot()
  if pendingHelloOffer then return end
  -- Only respond if we have any pixels or the DB has been loaded (i.e. we
  -- have SOMETHING to offer). Empty grids are fine too — snapshot syncs
  -- the "known empty" state.
  local delay = 0.5 + math.random() * 2.0
  pendingHelloOffer = true
  C_Timer.After(delay, function()
    if not pendingHelloOffer then return end -- cancelled by someone else's OFFER
    pendingHelloOffer = nil
    send("OFFER:" .. ns.PlayerName())
    -- small gap before first SNAP to let OFFER propagate
    C_Timer.After(0.25, sendSnapshotNow)
  end)
end

------------------------------------------------------------------------------
-- Incoming dispatcher
------------------------------------------------------------------------------

local function onChatMsgAddon(_, prefix, message, channel, sender)
  if prefix ~= PREFIX then return end
  if channel ~= "GUILD" then return end
  if type(message) ~= "string" or #message == 0 then return end

  local head, rest = message:match("^([A-Z]+):(.*)$")
  if not head then return end

  if head == "PIXEL" then
    local sx, sy, sc, sts, sp = rest:match("^(%-?%d+):(%-?%d+):(%d+):(%d+):(.+)$")
    if not sx then return end
    local x, y, c, ts = tonumber(sx), tonumber(sy), tonumber(sc), tonumber(sts)
    if not (x and y and c and ts) then return end
    ns.ApplyPixel(x, y, c, sp, ts)

  elseif head == "HELLO" then
    local who = rest
    if who == ns.PlayerName() then return end -- ignore our own
    recentHellos[who] = time()
    scheduleOfferAndSnapshot()

  elseif head == "OFFER" then
    -- Someone else claimed the HELLO first; suppress our pending response.
    if rest ~= ns.PlayerName() and pendingHelloOffer then
      pendingHelloOffer = nil
    end

  elseif head == "SNAP" then
    local seqStr, totalStr, payload = rest:match("^(%d+)/(%d+):(.*)$")
    if not seqStr then return end
    local seq, total = tonumber(seqStr), tonumber(totalStr)
    if not (seq and total) then return end
    if sender == ns.PlayerName() then return end -- ignore our own snapshot
    local buf = snapBuffers[sender]
    if not buf or buf.total ~= total then
      buf = { total = total, parts = {}, started = time() }
      snapBuffers[sender] = buf
    end
    buf.parts[seq] = payload or ""
    -- Have we got them all?
    local complete = true
    for i = 1, total do
      if buf.parts[i] == nil then complete = false; break end
    end
    if complete then
      local full = table.concat(buf.parts)
      snapBuffers[sender] = nil
      local applied = ns.DecodeGridHex(full)
      ns.Print(("snapshot from %s applied (%d chunks, %d hex chars, %d painted)"):format(
        sender, total, #full, applied))
      if ns.UI and ns.UI.Repaint then ns.UI.Repaint() end
    end

  elseif head == "CLEAR" then
    -- Officer clear from remote. Trust sender at protocol level;
    -- SavedVariables is per-client anyway.
    local who, tsStr = rest:match("^(.-):(%d+)$")
    if not who then return end
    local ts = tonumber(tsStr) or time()
    ns.ClearGrid(ts, who)
    ns.Print(("canvas cleared by %s"):format(who))
    if ns.UI and ns.UI.Repaint then ns.UI.Repaint() end
  end
end

------------------------------------------------------------------------------
-- Local grid clear (used by /doodle clear and by remote CLEAR)
------------------------------------------------------------------------------

function ns.ClearGrid(ts, who)
  local db = GuildDoodleDB
  db.pixels = {}
  db.appliedTs = {}
  local n = db.gridSize or ns.GRID_SIZE
  local stamp = ts or time()
  -- Mark all cells as applied so late PIXELs from before ts are rejected
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      db.appliedTs[ns.Key(x, y)] = stamp
    end
  end
  if ns.UI and ns.UI.Repaint then ns.UI.Repaint() end
end

------------------------------------------------------------------------------
-- Wire up events
------------------------------------------------------------------------------

ns.RegisterEvent("PLAYER_LOGIN", function()
  Comm.RegisterPrefix()
  math.randomseed(time() + (tonumber(tostring({}):match("0x(%x+)"), 16) or 0))
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  -- On login or /reload, ask the guild for the current canvas.
  if isLogin or isReload then
    -- Small delay to let addon channels settle after zone-in.
    C_Timer.After(2.0, function()
      if IsInGuild and IsInGuild() then Comm.SendHello() end
    end)
  end
end)

ns.RegisterEvent("CHAT_MSG_ADDON", onChatMsgAddon)
