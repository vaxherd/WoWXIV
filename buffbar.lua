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

-- Class for individual buttons.  Essentially identical to Aura from
-- ui/aurabar.lua.
local PlayerBuff = {}
PlayerBuff.__index = PlayerBuff

function PlayerBuff:New(f)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.frame = f
    new.tooltip_anchor = "BOTTOMLEFT"
    new.data = nil
    new.instance = nil
    new.spell_id = nil
    new.icon_id = nil
    new.is_mine = nil
    new.stacks = nil
    new.time_str = nil
    new.expires = nil

    new.icon = f:CreateTexture(nil, "ARTWORK")
    new.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
    new.icon:SetSize(24, 24)
    new.icon:SetMask("Interface\\Addons\\WowXIV\\textures\\buff-mask.png")

    new.border = f:CreateTexture(nil, "OVERLAY")
    new.border:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -3)
    new.border:SetSize(22, 26)
    new.border:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.border:SetTexCoord(99/256.0, 121/256.0, 14/256.0, 40/256.0)

    new.stack_label = f:CreateFontString(nil, "OVERLAY", "NumberFont_Shadow_Med")
    new.stack_label:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
    new.stack_label:SetTextScale(1)
    new.stack_label:SetText("")

    new.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    new.timer:SetPoint("BOTTOM", f, "BOTTOM", 0, 3)
    new.timer:SetTextScale(1)
    new.timer:SetText("")
    new.is_glyph_dist = false  -- Is timer repurposed as dragon glyph distance?

    f:HookScript("OnEnter", function() new:OnEnter() end)
    f:HookScript("OnLeave", function() new:OnLeave() end)

    return new
end

function PlayerBuff:OnEnter()
    if GameTooltip:IsForbidden() then return end
    if not self.frame:IsVisible() then return end
    GameTooltip:SetOwner(self.frame, "ANCHOR_"..self.tooltip_anchor)
    self:UpdateTooltip()
end

function PlayerBuff:OnLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

function PlayerBuff:OnUpdate()
    self:UpdateTimeLeft()
    if not self.time_str or self.time_str == "" then
        self.frame:SetScript("OnUpdate", nil)
    end
end

function PlayerBuff:UpdateTooltip()
    if GameTooltip:IsForbidden() or GameTooltip:GetOwner() ~= self.frame then
        return
    end
    GameTooltip:SetUnitBuffByAuraInstanceID("player", self.instance)
end

function PlayerBuff:UpdateTimeLeft()
    local time_str, is_glyph_dist
    if self.icon_id == ICON_DRAGON_GLYPH_RESONANCE and WoWXIV_config["buffbar_dragon_glyph_distance"] then
        is_glyph_dist = true
        time_str = self.data.points[1] .. "y"
    else
        is_glyph_dist = false
        local time_left
        if self.expires > 0 then
            time_left = self.expires - GetTime()
        else
            time_left = 0
        end
        local time_rounded = math.floor(time_left + 0.5)
        if time_left < 0.5 then
            time_str = nil
        elseif time_rounded < 60 then
            time_str = time_rounded
        elseif time_rounded < 3600 then
            time_str = math.floor(time_rounded/60) .. "m"
        elseif time_rounded < 86400 then
            time_str = math.floor(time_rounded/3600) .. "h"
        else
            time_str = math.floor(time_rounded/86400) .. "d"
        end
    end

    if is_glyph_dist ~= self.is_glyph_dist then
        self.is_glyph_dist = is_glyph_dist
        self.timer:SetTextScale(is_glyph_dist and 0.9 or 1.0)
    end
    if time_str ~= self.time_str then
        self.timer:SetText(time_str)
        self.time_str = time_str
    end

    if GameTooltip:GetOwner() == self.frame and GameTooltip:IsShown() then
        self:UpdateTooltip()
    end
end

function PlayerBuff:Update(data)
    if not data then
        self.data = nil
        self.instance = nil
        self.spell_id = nil
        self.icon_id = nil
        self.is_mine = nil
        self.stacks = 0
        self.stack_label:SetText("")
        self.expires = 0
        self.timer:SetText("")
        if not GameTooltip:IsForbidden() then
            if GameTooltip:GetOwner() == self.frame and GameTooltip:IsShown() then
                GameTooltip:Hide()
            end
        end
        return
    end

    local instance = data.auraInstanceID
    local spell_id = data.spellId
    local icon_id = data.icon
    local is_mine = data.isFromPlayerOrPlayerPet
    local stacks = data.applications
    local expires = data.expirationTime

    self.data = data
    self.instance = instance
    self.spell_id = spell_id
    self.is_mine = is_mine

    if icon_id ~= self.icon_id then
        self.icon:SetTexture(icon_id)
        self.icon_id = icon_id
    end

    if stacks ~= self.stacks then
        if stacks > 0 then
            self.stack_label:SetText(stacks)
        else
            self.stack_label:SetText("")
        end
        self.stacks = stacks
    end

    if expires > 0 then
        self.expires = expires
        if is_mine then
            self.timer:SetTextColor(0.78, 0.89, 1)
        else
            self.timer:SetTextColor(1, 1, 1)
        end
        self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)
    else
        self.expires = 0
        if self.icon_id == ICON_DRAGON_GLYPH_RESONANCE then
            self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)
        end
    end

    self:UpdateTimeLeft()  -- also updates tooltip by side effect
end


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
            if not child.xiv_buff then
                child.xiv_buff = PlayerBuff:New(child)
            end
            local data = child:IsVisible()
                and C_UnitAuras.GetAuraDataByIndex("player", child:GetID(), "HELPFUL")
                or nil
            child.xiv_buff:Update(data)
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
