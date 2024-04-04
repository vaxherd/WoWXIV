local WoWXIV = WoWXIV
WoWXIV.BuffBar = {}

-- File ID of Dragon Glyph Resonance aura icon.  We have to match by
-- aura icon rather than spell ID because each token has a unique ID
-- (e.g. 394546 for Algeth'era Court, 394551 for Vault of the Incarnates).
local ICON_DRAGON_GLYPH_RESONANCE = 4728198

------------------------------------------------------------------------

-- We need this separate implementation from the shared AuraBar because
-- (1) we have to use SecureActionButton for buffs to be clickable during
-- combat and (2) we can't show/hide or rearrange those buttons from
-- user code during combat.  I guess there's some security reason for
-- that restriction, but it seems a bit excessive...

local PlayerBuffBar = {}
PlayerBuffBar.__index = PlayerBuffBar

function PlayerBuffBar:New(parent, x, y)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.parent = parent

    local f = CreateFrame("Frame", nil, parent, "SecureAuraHeaderTemplate")
    new.frame = f
    f:SetAttribute("template", "PlayerBuffTemplate")
    f:SetAttribute("unit", "player")
    f:SetAttribute("filter", "HELPFUL")
    f:SetAttribute("sortMethod", "TIME")
    f:SetAttribute("sortDirection", "+")
    f:SetAttribute("separateOwn", 1)
    --f:SetAttribute("includeWeapons", 1)  -- FIXME: figure out what these are before deciding what to do with them
    f:SetAttribute("consolidateDuration", 999)
    f:SetAttribute("point", "BOTTOMRIGHT")
    f:SetAttribute("minWidth", 480)
    f:SetAttribute("minHeight", 80)
    f:SetAttribute("xOffset", -24)
    f:SetAttribute("yOffset", 0)
    f:SetAttribute("wrapAfter", 20)
    f:SetAttribute("wrapXOffset", 0)
    f:SetAttribute("wrapYOffset", 40)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", x, y)
    f:Show()

    f:HookScript("OnEvent", function(self,...) new:OnEvent(...) end)
    f:RegisterUnitEvent("UNIT_AURA", "player")
    if UnitGUID("player") then  -- e.g. after a /reload
        new:OnEvent("UNIT_AURA")
    end

    return new
end

function PlayerBuffBar:OnEvent(event, ...)
    if event ~= "UNIT_AURA" then return end
    local f = self.frame
    for i = 1, 40 do
        local child = f:GetAttribute("child"..i)
        if child then
            if not child.xiv_aura then
                child.xiv_aura = WoWXIV.UI.Aura:NewWithFrame(child, true)
                child.xiv_aura:SetTooltipAnchor("BOTTOMLEFT")
            end
            local data = child:IsVisible()
                and C_UnitAuras.GetAuraDataByIndex("player", child:GetID(), "HELPFUL")
                or nil
            child.xiv_aura:Update(data and "player" or nil, data)
        end
    end
end

------------------------------------------------------------------------

-- Create the player buff/debuff bars, and hide the default UI's buff frame.
function WoWXIV.BuffBar.Create()
    WoWXIV.HideBlizzardFrame(BuffFrame)
    WoWXIV.HideBlizzardFrame(DebuffFrame)

    local f = WoWXIV.CreateEventFrame("WoWXIV_BuffBar", UIParent)
    WoWXIV.BuffBar.frame = f
    f:SetWidth(24*20)
    f:SetHeight(40*4)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -250, -10)

    local x = UIParent:GetWidth() - 250
    --WoWXIV.BuffBar.buff_bar = WoWXIV.UI.AuraBar:New(
    --    "HELPFUL", "BOTTOMRIGHT", 20, 2, f, 0, 80)
    WoWXIV.BuffBar.buff_bar = PlayerBuffBar:New(f, 0, 80)
    WoWXIV.BuffBar.debuff_bar = WoWXIV.UI.AuraBar:New(
        "HARMFUL", "TOPRIGHT", 20, 1, f, 0, -80)
    WoWXIV.BuffBar.debuff_bar:SetUnit("player")
    -- FIXME: not sure how to separate out misc buffs from others
    --WoWXIV.BuffBar.misc_bar = WoWXIV.UI.AuraBar:New(
    --    "MISC", "TOPRIGHT", 20, 1, f, 0, -120)
end
