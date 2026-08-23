-- GuildDoodle: shared pixel canvas synced over the guild addon channel.
local ADDON, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addonName)
  if event == "ADDON_LOADED" and addonName == ADDON then
    GuildDoodleDB = GuildDoodleDB or { pixels = {} }
    print("|cffdc5078[GuildDoodle]|r loaded. /doodle to open the canvas (coming soon).")
  end
end)

SLASH_GUILDDOODLE1 = "/doodle"
SLASH_GUILDDOODLE2 = "/gd"
SlashCmdList["GUILDDOODLE"] = function(msg)
  print("|cffdc5078[GuildDoodle]|r Hello! Canvas UI coming soon.")
end
