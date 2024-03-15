local WoWXIV = WoWXIV
WoWXIV.SlashCmd = {}

------------------------------------------------------------------------

function WoWXIV.SlashCmd.Init()
    SLASH_WOWXIV1, SLASH_WOWXIV2 = "/wowxiv", "/xiv"
    SlashCmdList["WOWXIV"] = function(arg)
        if not arg or arg == "" then
            WoWXIV.Config.Open()
        elseif arg == "ally" then
            WoWXIV.PartyList.ClearAllies(id)
            local id = UnitGUID("target")
            if id then WoWXIV.PartyList.AddAlly(id) end
        else
            print("Usage:")
            print("   /wowxiv - open addon settings window")
            print("   /wowxiv ally - mark current target as an ally for party list (clear ally if no target)")
        end
    end
end
