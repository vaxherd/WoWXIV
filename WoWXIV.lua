-- The WoW API seems to provide each addon an empty table to use as a
-- module structure, so we take advantage of that to avoid requiring
-- this module to be loaded first.  We still export the table under a
-- global name for external scripting convenience.  (The first argument
-- is just the addon name, which we have no need of except when checking
-- against an ADDON_LOADED event.)
local module_name
module_name, WoWXIV = ...

WoWXIV.VERSION = "0.1+"

WoWXIV.startup_frame = CreateFrame("Frame", "WoWXIV_StartupFrame")
WoWXIV.startup_frame:RegisterEvent("ADDON_LOADED")
WoWXIV.startup_frame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == module_name then
        WoWXIV.Config.Create()

        WoWXIV.CombatLogManager.Create()
        WoWXIV.Gamepad.Init()

        WoWXIV.BuffBar.Create()
        WoWXIV.FlyText.CreateManager()
        WoWXIV.HateList.Create()
        WoWXIV.LogWindow.Create()
        WoWXIV.Map.Init()
        WoWXIV.PartyList.Create()
        WoWXIV.SlashCmd.Init()
        WoWXIV.TargetBar.Create()
    end
end)
