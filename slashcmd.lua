function WoWXIV_SlashCmd_Init()
    SLASH_WOWXIV1, SLASH_WOWXIV2 = "/wowxiv", "/xiv"
    SlashCmdList["WOWXIV"] = function(arg)
        if not arg or arg == "" then
            WoWXIV_OpenConfig()
        elseif arg == "ally" then
            local id = UnitGUID("target")
            if id then
                WoWXIV_PartyList_AddAlly(id)
            else
                print("No target selected!")
            end
        elseif arg == "noally" then
                WoWXIV_PartyList_ClearAllies(id)
        else
            print("Usage:")
            print("   /wowxiv - open addon settings window")
            print("   /wowxiv ally - mark current target as an ally for party list")
            print("   /wowxiv noally - clear all allies from party list")
        end
    end
end
