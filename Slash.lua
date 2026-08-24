-- GuildDoodle Slash: /doodle and /gd command surface.

local ADDON, ns = ...

SLASH_GUILDDOODLE1 = "/doodle"
SLASH_GUILDDOODLE2 = "/gd"

local function usage()
  ns.Print("commands:")
  ns.Print("  /doodle              - open/close the canvas")
  ns.Print("  /doodle color <1-15> - select paint color (0 = erase)")
  ns.Print("  /doodle config       - show current config")
  ns.Print("  /doodle cooldown <s> - set placement cooldown (officer)")
  ns.Print("  /doodle clear        - clear canvas (officer)")
end

local function handleConfig()
  local db = GuildDoodleDB
  ns.Print(("grid: %dx%d | cooldown: %ds | selected color: %d"):format(
    db.gridSize, db.gridSize, db.cooldown, db.ui.selectedColor or 0))
  local painted = 0
  for _ in pairs(db.pixels) do painted = painted + 1 end
  ns.Print(("painted cells: %d / %d | officer: %s"):format(
    painted, db.gridSize * db.gridSize, tostring(ns.IsOfficer())))
end

SlashCmdList["GUILDDOODLE"] = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  if msg == "" then
    ns.UI.Toggle()
    return
  end

  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = (cmd or ""):lower()

  if cmd == "help" or cmd == "?" then
    usage()

  elseif cmd == "config" or cmd == "status" then
    handleConfig()

  elseif cmd == "color" then
    local c = tonumber(rest)
    if not c or c < 0 or c > 15 then
      ns.Print("usage: /doodle color <0-15> (0 = erase)")
      return
    end
    GuildDoodleDB.ui.selectedColor = c
    ns.Print(("selected color %d"):format(c))
    if ns.UI.UpdateSelectedSwatch then ns.UI.UpdateSelectedSwatch() end

  elseif cmd == "cooldown" then
    if not ns.IsOfficer() then
      ns.Print("cooldown is officer-only")
      return
    end
    local s = tonumber(rest)
    if not s or s < 0 or s > 3600 then
      ns.Print("usage: /doodle cooldown <seconds 0-3600>")
      return
    end
    GuildDoodleDB.cooldown = s
    ns.Print(("cooldown set to %ds"):format(s))

  elseif cmd == "clear" then
    if not ns.IsOfficer() then
      ns.Print("clear is officer-only")
      return
    end
    ns.ClearGrid(time(), ns.PlayerName())
    ns.Comm.SendClear()
    ns.Print("canvas cleared and broadcast to guild")

  elseif cmd == "hello" then
    -- Manual snapshot pull, for debugging
    ns.Comm.SendHello()
    ns.Print("sent HELLO")

  else
    ns.Print("unknown command: " .. cmd)
    usage()
  end
end
