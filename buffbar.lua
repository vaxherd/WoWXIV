local WoWXIV = WoWXIV
WoWXIV.BuffBar = {}

------------------------------------------------------------------------

-- Create the player buff/debuff bars, and hide the default UI's buff frame.
function WoWXIV.BuffBar.Create()
    WoWXIV.HideBlizzardFrame(BuffFrame)
    WoWXIV.HideBlizzardFrame(DebuffFrame)

    local f = WoWXIV.CreateEventFrame("WoWXIV_BuffBar", UIParent)
    WoWXIV.BuffBar.frame = f
    f:SetWidth(24*40)
    f:SetHeight(40*3)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -250, -10)

    local x = UIParent:GetWidth() - 250
    WoWXIV.BuffBar.buff_bar = WoWXIV.UI.AuraBar:New("player", "HELPFUL", "RIGHT", 40, f, 0, 0)
    WoWXIV.BuffBar.debuff_bar = WoWXIV.UI.AuraBar:New("player", "HARMFUL", "RIGHT", 40, f, 0, -40)
    -- FIXME: not sure how to separate out misc buffs from others
    --WoWXIV.BuffBar.misc_bar = WoWXIV.UI.AuraBar:New("player", "MISC", "RIGHT", 40, f, 0, -80)
end
