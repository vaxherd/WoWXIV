local _, WoWXIV = ...
WoWXIV.SlashCmd = {}

------------------------------------------------------------------------

function WoWXIV.SlashCmd.Init()
    SLASH_WOWXIV1, SLASH_WOWXIV2 = "/wowxiv", "/xiv"
    SlashCmdList["WOWXIV"] = function(arg)
        if not arg or arg == "" then
            WoWXIV.Config.Open()
        else
            print("Usage:")
            print("   /wowxiv - open addon settings window")
        end
    end
end
