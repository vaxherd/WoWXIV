WoWXIV = {}

WoWXIV.startup_frame = CreateFrame("Frame", "WoWXIV_StartupFrame")
WoWXIV.startup_frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        WoWXIV.Config.Create()
        WoWXIV.Gamepad.Init()

        WoWXIV.BuffBar.Create()
        --WoWXIV.HateList.Create() --FIXME semi-broken, needs to deal with unaggroed mobs and mobs going out of range among other things
        WoWXIV.PartyList.Create()
        WoWXIV.SlashCmd.Init()
    end
end)
WoWXIV.startup_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
