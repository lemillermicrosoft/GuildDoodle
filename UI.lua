-- GuildDoodle UI: canvas frame, palette, click-to-paint.
--
-- Design notes:
--   * Single unprotected top-level frame ("GuildDoodleFrame") -> safe with ElvUI.
--   * Grid cells are unnamed Frames with a solid Texture backdrop (cheap;
--     avoids CreateFrame("Button") x1024 taint surface).
--   * We put a single transparent capture Frame OVER the grid to route clicks
--     via OnMouseDown -> hit-test to (x,y). This keeps per-cell frames light.
--   * Nothing here is protected. No SecureActionButton, no SetAttribute, no
--     dispatcher hooks. Combat-safe.

local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

local CELL_PX      = 14        -- pixel size per cell (32 * 14 = 448 canvas)
local PALETTE_H    = 28
local PADDING      = 8
local HEADER_H     = 22

local frame, canvas, capture, cooldownText, statusText
local cellTex = {}             -- [y][x] -> texture
local paletteSwatches = {}     -- [idx] -> frame
local selectedHighlight

------------------------------------------------------------------------------
-- Build UI (lazy: only when first opened)
------------------------------------------------------------------------------

local function paletteFrame(parent, idx, color, x, y, size)
  local sw = CreateFrame("Frame", nil, parent)
  sw:SetSize(size, size)
  sw:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local t = sw:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints(sw)
  t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  sw.tex = t

  local border = sw:CreateTexture(nil, "OVERLAY")
  border:SetPoint("TOPLEFT", sw, "TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0, 0, 0, 0.6)
  border:SetDrawLayer("OVERLAY", -1)

  sw:EnableMouse(true)
  sw:SetScript("OnMouseDown", function()
    GuildDoodleDB.ui.selectedColor = idx
    UI.UpdateSelectedSwatch()
  end)
  sw:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(("Color %d"):format(idx))
    GameTooltip:Show()
  end)
  sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return sw
end

function UI.UpdateSelectedSwatch()
  if not selectedHighlight then return end
  local idx = (GuildDoodleDB and GuildDoodleDB.ui.selectedColor) or 5
  local target = paletteSwatches[idx]
  if not target then return end
  selectedHighlight:ClearAllPoints()
  selectedHighlight:SetPoint("TOPLEFT", target, "TOPLEFT", -3, 3)
  selectedHighlight:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 3, -3)
  selectedHighlight:Show()
end

local function buildFrame()
  local db = GuildDoodleDB
  local n = db.gridSize or ns.GRID_SIZE
  local canvasPx = n * CELL_PX
  local w = canvasPx + PADDING * 2
  local h = HEADER_H + canvasPx + PALETTE_H + PADDING * 3

  frame = CreateFrame("Frame", "GuildDoodleFrame", UIParent, "BackdropTemplate")
  frame:SetSize(w, h)
  frame:SetPoint(db.ui.point or "CENTER", UIParent, db.ui.relPoint or "CENTER",
    db.ui.x or 0, db.ui.y or 0)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("MEDIUM")
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.ui.point, db.ui.relPoint, db.ui.x, db.ui.y = point, relPoint, x, y
  end)

  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end

  -- Header
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", frame, "TOP", 0, -6)
  title:SetText("|cffdc5078GuildDoodle|r")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() UI.Hide() end)

  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -6)
  statusText:SetText("")

  cooldownText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cooldownText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
  cooldownText:SetText("")

  -- Canvas
  canvas = CreateFrame("Frame", nil, frame)
  canvas:SetSize(canvasPx, canvasPx)
  canvas:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(HEADER_H))

  local bg = canvas:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(canvas)
  bg:SetColorTexture(0.05, 0.05, 0.07, 1)

  for y = 0, n - 1 do
    cellTex[y] = {}
    for x = 0, n - 1 do
      local t = canvas:CreateTexture(nil, "ARTWORK")
      t:SetSize(CELL_PX - 1, CELL_PX - 1)
      t:SetPoint("TOPLEFT", canvas, "TOPLEFT",
        x * CELL_PX, -(y * CELL_PX))
      local col = ns.PALETTE[0]
      t:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
      cellTex[y][x] = t
    end
  end

  -- Click capture (single frame over canvas, hit-tests to cell)
  capture = CreateFrame("Frame", nil, canvas)
  capture:SetAllPoints(canvas)
  capture:EnableMouse(true)
  capture:SetScript("OnMouseDown", function(self, button)
    if InCombatLockdown and InCombatLockdown() then
      ns.Print("no painting during combat")
      return
    end
    local cx, cy = GetCursorPosition()
    local scale = self:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local left, bottom = self:GetLeft(), self:GetBottom()
    local top = self:GetTop()
    if not left or not top then return end
    local gx = math.floor((cx - left) / CELL_PX)
    local gy = math.floor((top - cy) / CELL_PX)
    if gx < 0 or gy < 0 or gx >= n or gy >= n then return end
    local color = GuildDoodleDB.ui.selectedColor or 5
    if button == "RightButton" then color = 0 end -- right-click erase
    UI.TryPlace(gx, gy, color)
  end)

  -- Palette
  local paletteY = -(HEADER_H + canvasPx + PADDING)
  local swSize = 20
  local swGap  = 4
  local totalSwW = 16 * swSize + 15 * swGap -- 1..15 plus empty(0) = 16 swatches
  local startX = (w - totalSwW) / 2
  for idx = 0, 15 do
    local col = ns.PALETTE[idx]
    local xoff = startX + idx * (swSize + swGap)
    local sw = paletteFrame(frame, idx, col, xoff, paletteY, swSize)
    paletteSwatches[idx] = sw
  end

  selectedHighlight = frame:CreateTexture(nil, "OVERLAY")
  selectedHighlight:SetColorTexture(1, 1, 1, 0.9)
  selectedHighlight:SetDrawLayer("OVERLAY", 2)
  selectedHighlight:SetBlendMode("ADD")
  -- We only want a border effect; texture full alpha would cover the swatch.
  -- Trick: use a small alpha and let the swatch under shine through.
  selectedHighlight:SetAlpha(0.35)
  UI.UpdateSelectedSwatch()

  UI.Repaint()
  UI.UpdateCooldownText()
end

------------------------------------------------------------------------------
-- Painting
------------------------------------------------------------------------------

function UI.PaintCell(x, y, c)
  if not cellTex[y] or not cellTex[y][x] then return end
  local col = ns.PALETTE[c] or ns.PALETTE[0]
  cellTex[y][x]:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
end

function UI.Repaint()
  if not canvas then return end
  local db = GuildDoodleDB
  local n = db.gridSize or ns.GRID_SIZE
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local p = db.pixels[ns.Key(x, y)]
      UI.PaintCell(x, y, (p and p.c) or 0)
    end
  end
end

------------------------------------------------------------------------------
-- Placement + cooldown
------------------------------------------------------------------------------

function UI.CooldownRemaining()
  local db = GuildDoodleDB
  local last = db.lastPlace[ns.PlayerName()] or 0
  local rem = (last + (db.cooldown or ns.DEFAULT_COOLDOWN)) - time()
  if rem < 0 then rem = 0 end
  return rem
end

function UI.UpdateCooldownText()
  if not cooldownText then return end
  local rem = UI.CooldownRemaining()
  if rem > 0 then
    cooldownText:SetText(("|cffaaaaaacooldown:|r %ds"):format(rem))
  else
    cooldownText:SetText("|cff77dd77ready|r")
  end
end

function UI.TryPlace(x, y, c)
  local db = GuildDoodleDB
  local rem = UI.CooldownRemaining()
  if rem > 0 then
    ns.Print(("cooldown: %ds remaining"):format(rem))
    return
  end
  local ts = time()
  local ok = ns.ApplyPixel(x, y, c, ns.PlayerName(), ts)
  if not ok then return end
  db.lastPlace[ns.PlayerName()] = ts
  ns.Comm.SendPixel(x, y, c, ts)
  UI.UpdateCooldownText()
end

------------------------------------------------------------------------------
-- Show / Hide
------------------------------------------------------------------------------

function UI.Toggle()
  if not frame then buildFrame() end
  if frame:IsShown() then UI.Hide() else UI.Show() end
end

function UI.Show()
  if not frame then buildFrame() end
  frame:Show()
  GuildDoodleDB.ui.shown = true
  UI.Repaint()
  UI.UpdateCooldownText()
end

function UI.Hide()
  if frame then frame:Hide() end
  if GuildDoodleDB and GuildDoodleDB.ui then GuildDoodleDB.ui.shown = false end
end

-- Cooldown ticker
local tickerFrame = CreateFrame("Frame")
local acc = 0
tickerFrame:SetScript("OnUpdate", function(self, elapsed)
  acc = acc + elapsed
  if acc >= 1 then
    acc = 0
    if frame and frame:IsShown() then UI.UpdateCooldownText() end
  end
end)

-- Restore visibility after ADDON_LOADED
ns.RegisterEvent("PLAYER_LOGIN", function()
  if GuildDoodleDB and GuildDoodleDB.ui and GuildDoodleDB.ui.shown then
    UI.Show()
  end
end)
