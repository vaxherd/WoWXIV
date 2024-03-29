WoWXIV = {}

WoWXIV.startup_frame = CreateFrame("Frame", "WoWXIV_StartupFrame")
WoWXIV.startup_frame:RegisterEvent("ADDON_LOADED")
WoWXIV.startup_frame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "WoWXIV" then
        WoWXIV.Config.Create()

        WoWXIV.CombatLogManager.Create()
        WoWXIV.Gamepad.Init()

        WoWXIV.BuffBar.Create()
        WoWXIV.FlyText.CreateManager()
        WoWXIV.HateList.Create()
        WoWXIV.PartyList.Create()
        WoWXIV.SlashCmd.Init()
        WoWXIV.TargetBar.Create()
    end
end)
