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
    new.instance = nil
    new.spell_id = nil
    new.icon_id = nil
    new.is_helpful = nil
    new.is_mine = nil
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

function Aura:OnUpdate()
    self:UpdateTimeLeft()
    if not self.time_str or self.time_str == "" then
        self.frame:SetScript("OnUpdate", nil)
    end
end

function Aura:UpdateTooltip()
    if GameTooltip:IsForbidden() then return end
    if self.unit then
        if self.is_helpful then
            GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.instance)
        else
            GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.instance)
        end
    else
        GameTooltip:Hide()
    end
end

function Aura:UpdateTimeLeft()
    local time_str
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
function Aura:Update(unit, aura_data)
    if unit then
        self:InternalUpdate(
            unit, aura_data.auraInstanceID, aura_data.spellId, aura_data.icon,
            aura_data.isHelpful, aura_data.isFromPlayerOrPlayerPet,
            aura_data.applications, aura_data.expirationTime)
    else
        self:InternalUpdate(nil)
    end
end

function Aura:CopyFrom(other)
    self:InternalUpdate(
        other.unit, other.instance, other.spell_id, other.icon_id,
        other.is_helpful, other.is_mine, other.stacks, other.expires)
end

function Aura:InternalUpdate(unit, instance, spell_id, icon_id, is_helpful, is_mine, stacks, expires)
    if not unit then
        if self.unit then
            self.frame:Hide()
            self.unit = nil
            self.instance = nil
            self.spell_id = nil
            self.icon_id = nil
            self.is_helpful = nil
            self.is_mine = nil
            self.stacks = 0
            self.stack_label:SetText("")
            self.expires = 0
            self.timer:SetText("")
        end
        return
    end

    self.unit = unit
    self.instance = instance
    self.spell_id = spell_id
    self.is_mine = is_mine

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
        self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)
    else
        self.expires = 0
    end

    self:UpdateTimeLeft()  -- also updates tooltip by side effect
end

------------------------------------------------------------------------

local AuraBar = UI.AuraBar
AuraBar.__index = AuraBar

-- Returns 1 if {id1,helpful1,expires1} < {id2,helpful2,expires2}
local function CompareAuras(id1, helpful1, expires1, id2, helpful2, expires2)
    -- We could potentially sort player-source auras first (like XIV),
    -- but WoW nameplates already filter those out for us, so probably
    -- better to keep a strict expiration time order.
    if helpful1 ~= helpful2 then
        return not helpful1
    elseif (expires1 ~= 0) ~= (expires2 ~= 0) then
        return expires1 ~= 0
    elseif expires1 ~= 0 then
        return expires1 < expires2
    else
        return id1 < id2
    end
end

-- type is one of: "HELPFUL", "HARMFUL", "MISC" (like XIV food/FC buffs),
--     or "ALL" (for party list)
-- align is either "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", or "BOTTOMRIGHT"
function AuraBar:New(type, align, cols, rows, parent, anchor_x, anchor_y)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.unit = null
    new.type = type
    new.leftalign = (align == "TOPLEFT" or align == "BOTTOMLEFT")
    new.topalign = (align == "TOPLEFT" or align == "TOPRIGHT")
    new.max = cols * rows
    new.instance_map = {}  -- map from aura instance ID to self.auras[] index

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

    f:SetScript("OnEvent", function(self, event, ...) new:OnUnitAura(...) end)

    f:Hide()
    return new
end

function AuraBar:Delete()
    WoWXIV.DestroyFrame(self.frame)
    self.frame = nil
end

function AuraBar:SetUnit(unit)
    self.unit = unit
    if unit then
        self.frame:RegisterUnitEvent("UNIT_AURA", unit)
    else
        self.frame:UnregisterEvent("UNIT_AURA")
    end
    self:Refresh()
end

function AuraBar:Refresh()
    if not self.unit or not UnitGUID(self.unit) then
        self.frame:Hide()
        return
    end
    self.frame:Show()

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
        return CompareAuras(a[3].spellId, a[3].isHelpful, a[3].expirationTime,
                            b[3].spellId, b[3].isHelpful, b[3].expirationTime)
    end)

    self.instance_map = {}
    for i = 1, self.max do
        if aura_list[i] then
            self.auras[i]:Update(self.unit, aura_list[i][3])
            self.instance_map[aura_list[i][3].auraInstanceID] = i
        else
            self.auras[i]:Update(nil)
        end
    end
end

-- For debugging:
local function DumpUpdateInfo(info)
    local s
    if not info then
        s = " no update info"
    elseif info.isFullUpdate then
        s = " full update"
    else
        s = ""
        local function print_table(t)
            local ss = ""
            local first = true
            for _, v in ipairs(t) do
                if first then first = false else ss = ss .. "," end
                if type(v) == "table" then  -- for addedAuras
                    v = v.auraInstanceID .. ':"' .. v.name .. '"'
                end
                ss = ss .. v
            end
            return ss
        end
        if info.addedAuras then
            s = s .. " added={"..print_table(info.addedAuras).."}"
        end
        if info.removedAuraInstanceIDs then
            s = s .. " removed={"..print_table(info.removedAuraInstanceIDs).."}"
        end
        if info.updatedAuraInstanceIDs then
            s = s .. " updated={"..print_table(info.updatedAuraInstanceIDs).."}"
        end
    end
    print("UNIT_AURA:" .. s)
end

function AuraBar:OnUnitAura(unit, update_info)
    if not update_info or update_info.isFullUpdate then
        self:Refresh()
        return
    end
    -- If removing from a full bar, we need a full refresh because there
    -- may be auras we discarded due to overflow.
    if update_info.removedAuraInstanceIDs and update_info.removedAuraInstanceIDs[1] then
        if self.auras[self.max].instance then
            self:Refresh()
            return
        end
    end

    if update_info.addedAuras then
        for _, aura_data in ipairs(update_info.addedAuras) do
            local function is_wanted(self, aura_data)
                if aura_data.isHelpful then
                    return self.type ~= "HARMFUL"
                elseif aura_data.isHarmful then
                    return self.type ~= "HELPFUL"
                else
                    return self.type == "MISC" or self.type == "ALL"
                end
            end
            if is_wanted(self, aura_data) then
                local function insertBefore(new_data, aura)
                    if not aura.instance then
                        return true
                    else
                        return CompareAuras(new_data.spellId, new_data.isHelpful, new_data.expirationTime,
                                            aura.spell_id, aura.is_helpful, aura.expires)
                    end
                end
                for i = 1, self.max do
                    if insertBefore(aura_data, self.auras[i]) then
                        for j = self.max, i+1, -1 do
                            local prev = self.auras[j-1]
                            if prev.instance then
                                self.auras[j]:CopyFrom(prev)
                                self.instance_map[prev.instance] = j
                            end
                        end
                        self.auras[i]:Update(self.unit, aura_data)
                        self.instance_map[aura_data.auraInstanceID] = i
                        break
                    end
                end
            end
        end
    end

    if update_info.removedAuraInstanceIDs then
        for _, instance in ipairs(update_info.removedAuraInstanceIDs) do
            local index = self.instance_map[instance]
            if index then
                for i = index, self.max do
                    local next = self.auras[i+1]
                    if not next or not next.instance then
                        self.auras[i]:Update(nil)
                        break
                    end
                    self.auras[i]:CopyFrom(next)
                    self.instance_map[next.instance] = i
                end
            end
            self.instance_map[instance] = nil
        end
    end

    if update_info.updatedAuraInstanceIDs then
        for _, instance in ipairs(update_info.updatedAuraInstanceIDs) do
            local index = self.instance_map[instance]
            if index then
                aura_data = C_UnitAuras.GetAuraDataByAuraInstanceID(self.unit, instance)
                if aura_data then  -- sanity check
                    self.auras[index]:Update(self.unit, aura_data)
                end
            end
        end
    end
end
