local WoWXIV = WoWXIV
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI
UI.AuraBar = {}

local GameTooltip = GameTooltip

------------------------------------------------------------------------

local Aura = {}
Aura.__index = Aura

function Aura:New(parent)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.parent = parent
    new.tooltip_anchor = "ANCHOR_BOTTOMRIGHT"
    new.unit = nil
    new.aura_index = nil
    new.aura_index_filter = nil
    new.icon_id = nil
    new.is_helpful = nil
    new.stacks = nil
    new.time_str = nil
    new.expires = nil

    local f = CreateFrame("Frame", nil, parent)
    new.frame = f
    f:Hide()
    f:SetSize(24, 40)
    f:SetScript("OnEnter", function() new:OnEnter() end)
    f:SetScript("OnLeave", function() new:OnLeave() end)

    new.icon = f:CreateTexture(nil, "ARTWORK")
    new.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
    new.icon:SetSize(24, 24)

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

    return new
end

function Aura:SetAnchor(anchor, x, y, tooltip_anchor)
    self.frame:SetPoint(anchor, self.parent, anchor, x, y)
    self.tooltip_anchor = tooltip_anchor
end

function Aura:OnEnter()
    if GameTooltip:IsForbidden() then return end
    if not self.frame:IsVisible() then return end
    GameTooltip:SetOwner(self.frame, self.tooltip_anchor)
    self:UpdateTooltip()
end

function Aura:OnLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

function Aura:UpdateTooltip()
    if GameTooltip:IsForbidden() then return end
    if self.unit then
        GameTooltip:SetUnitAura(self.unit, self.aura_index, self.aura_index_filter)
    else
        GameTooltip:Hide()
    end
end

function Aura:UpdateTimeLeft()
    local time_str
    local time_left
    if self.expires then
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
    else
        time_str = math.floor(time_rounded/3600) .. "h"
    end
    if time_str ~= self.time_str then
        self.timer:SetText(time_str)
        self.time_str = time_str
    end

    if GameTooltip:GetOwner() == self.frame and GameTooltip:IsShown() then
        self:UpdateTooltip()
    end
end

-- Use unit = nil (or omitted) to hide the icon.
function Aura:Update(unit, aura_index, aura_index_filter, aura_data)
    if not unit then
        if self.unit then
            self.frame:Hide()
            self.unit = nil
            self.icon_id = nil
            self.is_helpful = nil
            self.stacks = nil
            self.stack_label:SetText("")
            self.time_left = nil
            self.timer:SetText("")
        end
        return
    end

    self.unit = unit
    self.aura_index = aura_index
    self.aura_index_filter = aura_index_filter

    local icon_id = aura_data.icon
    local is_helpful = aura_data.isHelpful
    local is_mine = aura_data.isFromPlayerOrPlayerPet
    local stacks = aura_data.applications
    local expires = aura_data.expirationTime

    if icon_id ~= self.icon_id or is_helpful ~= self.is_helpful then
        if is_helpful then
            self.icon:SetMask("Interface\\Addons\\WowXIV\\textures\\buff-mask.png")
            self.border:SetTexCoord(99/256.0, 121/256.0, 14/256.0, 40/256.0)
        else
            self.icon:SetMask("Interface\\Addons\\WowXIV\\textures\\debuff-mask.png")
            self.border:SetTexCoord(99/256.0, 121/256.0, 40/256.0, 14/256.0)
        end
        self.icon:SetTexture(icon_id)  -- Must come _after_ SetMask()!
        if not self.icon_id then
            self.frame:Show()
        end
        self.icon_id = icon_id
        self.is_helpful = is_helpful
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
    else
        self.expires = nil
    end

    self:UpdateTimeLeft()  -- also updates tooltip by side effect
end

------------------------------------------------------------------------

local AuraBar = UI.AuraBar
AuraBar.__index = AuraBar

-- type is one of: "HELPFUL", "HARMFUL", "MISC" (like XIV food/FC buffs),
--     or "ALL" (for party list)
-- align is either "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", or "BOTTOMRIGHT"
function AuraBar:New(unit, type, align, cols, rows, parent, anchor_x, anchor_y)
    local new = {}
    setmetatable(new, self)
    new.__index = self

if not unit then print "null unit!" end --FIXME temp - why does this happen?
    new.unit = unit
    new.type = type
    new.leftalign = (align == "TOPLEFT" or align == "BOTTOMLEFT")
    new.topalign = (align == "TOPLEFT" or align == "TOPRIGHT")
    new.max = cols * rows

    local inv_align = (new.topalign and "BOTTOM" or "TOP") .. (new.leftalign and "RIGHT" or "LEFT")

    local f = CreateFrame("Frame", nil, parent)
    new.frame = f
    f:SetSize(24*cols, 40*rows)
    f:SetPoint(align, parent, align, anchor_x, anchor_y)

    new.auras = {}
    local dx = new.leftalign and 24 or -24
    local dy = new.topalign and -40 or 40
    for r = 1, rows do
        local y = (r-1)*dy
        for c = 1, cols do
            local aura = Aura:New(f)
            table.insert(new.auras, aura)
            local x = (c-1)*dx
            aura:SetAnchor(align, x, y, inv_align)
        end
    end

    f:SetScript("OnUpdate", function(self) new:OnUpdate() end)
    f:SetScript("OnEvent", function(self) new:OnUnitAura() end)
    f:RegisterUnitEvent("UNIT_AURA", unit)

    new:OnUnitAura("PLAYER_ENTERING_WORLD")  -- get the initial aura list
    f:Show()
    return new
end

function AuraBar:Delete()
    WoWXIV.DestroyFrame(self.frame)
    self.frame = nil
end

function AuraBar:OnUpdate()
    for _, aura in ipairs(self.auras) do
        if aura.time_str ~= "" then
            aura:UpdateTimeLeft()
        end
    end
end

-- FIXME: look into optimizing vis-a-vis https://us.forums.blizzard.com/en/wow/t/new-unitaura-processing-optimizations/1205007
function AuraBar:OnUnitAura(event, ...)
if not self.unit then return end --FIXME temp
    local aura_list = {}
    if self.type ~= "HELPFUL" then
        for i = 1, self.max do
            local data = C_UnitAuras.GetAuraDataByIndex(self.unit, i, "HARMFUL")
            if not data then break end
            table.insert(aura_list, {i, "HARMFUL", data})
        end
    end
    if self.type ~= "HARMFUL" then
        for i = 1, self.max do
            local data = C_UnitAuras.GetAuraDataByIndex(self.unit, i, "HELPFUL")
            if not data then break end
            table.insert(aura_list, {i, "HELPFUL", data})
        end
    end
    table.sort(aura_list, function(a,b)
        if a[3].isHelpful ~= b[3].isHelpful then
            return not a[3].isHelpful
        elseif (a[3].expirationTime ~= 0) ~= (b[3].expirationTime ~= 0) then
            return a[3].expirationTime ~= 0
        elseif a[3].expirationTime ~= 0 then
            return a[3].expirationTime < b[3].expirationTime
        else
            return a[3].spellId < b[3].spellId
        end
    end)
    for i = 1, self.max do
        if aura_list[i] then
            self.auras[i]:Update(self.unit, unpack(aura_list[i]))
        else
            self.auras[i]:Update(nil)
        end
    end
end
