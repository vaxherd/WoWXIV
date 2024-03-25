local WoWXIV = WoWXIV
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI
UI.AuraBar = {}

local GameTooltip = GameTooltip

-- Maximum number of auras that can be applied to a unit.  This seems to
-- be hardcoded in the game, but using a named constant anyway for
-- readability and in case of a TOP incident leading to an increase.
local MAX_AURAS = 40

-- Utility routine for debugging:
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

------------------------------------------------------------------------

local Aura = {}
Aura.__index = Aura

function Aura:New(parent)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.parent = parent
    new.tooltip_anchor = "BOTTOMRIGHT"
    new.unit = nil
    new.data = nil
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
    GameTooltip:SetOwner(self.frame, "ANCHOR_"..self.tooltip_anchor)
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
    if GameTooltip:IsForbidden() or GameTooltip:GetOwner() ~= self.frame then
        return
    end
    if self.unit then
        if self.is_helpful then
            GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.instance)
        else
            GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.instance)
        end
        GameTooltip:Show()
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
    elseif time_rounded < 86400 then
        time_str = math.floor(time_rounded/3600) .. "h"
    else
        time_str = math.floor(time_rounded/86400) .. "d"
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
        self:InternalUpdate(unit, aura_data)
    else
        self:InternalUpdate(nil)
    end
end

function Aura:CopyFrom(other)
    self:InternalUpdate(other.unit, other.data)
end

function Aura:InternalUpdate(unit, data)
    if not unit then
        if self.unit then
            self.frame:Hide()
            self.unit = nil
            self.data = nil
            self.instance = nil
            self.spell_id = nil
            self.icon_id = nil
            self.is_helpful = nil
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
        end
        return
    end

    local instance = data.auraInstanceID
    local spell_id = data.spellId
    local icon_id = data.icon
    local is_helpful = data.isHelpful
    local is_mine = data.isFromPlayerOrPlayerPet
    local stacks = data.applications
    local expires = data.expirationTime

    self.unit = unit
    self.data = data
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

-- Returns 1 if AuraData a < AuraData b
local function CompareAuras(a, b)
    if a.isFromPlayerOrPlayerPet ~= b.isFromPlayerOrPlayerPet then
        return a.isFromPlayerOrPlayerPet
    elseif a.isHelpful ~= b.isHelpful then
        return not a.isHelpful
    elseif (a.expirationTime ~= 0) ~= (b.expirationTime ~= 0) then
        return a.expirationTime ~= 0
    elseif a.expirationTime ~= 0 then
        return a.expirationTime < b.expirationTime
    else
        return a.spellId < b.spellId
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
    new.align = align
    new.leftalign = (align == "TOPLEFT" or align == "BOTTOMLEFT")
    new.topalign = (align == "TOPLEFT" or align == "TOPRIGHT")
    -- Always anchor tooltips to bottom because we display the bars at the
    -- top of the screen (so top anchor would overlap the icon itself).
    local inv_align = ("BOTTOM"
                       .. (new.leftalign and "RIGHT" or "LEFT"))
    new.inv_align = inv_align
    new.cols = cols
    new.max = cols * rows
    new.instance_map = {}  -- map from aura instance ID to self.auras[] index
    new.log_events = false  -- set with AuraBar:LogEvents()

    local f = CreateFrame("Frame", nil, parent)
    new.frame = f
    f:SetSize(24*cols, 40*rows)
    f:SetPoint(align, parent, align, anchor_x, anchor_y)

    new.auras = {}
    local dx = new.leftalign and 24 or -24
    local dy = new.topalign and -40 or 40
    new.dx, new.dy = dx, dy
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

    new:Refresh()
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
    table.sort(aura_list, function(a,b) return CompareAuras(a[3],b[3]) end)

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

function AuraBar:OnUnitAura(unit, update_info)
    if self.log_events then
        DumpUpdateInfo(update_info)
    end

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
                        return CompareAuras(new_data, aura.data)
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


-- For debugging:

function AuraBar:LogEvents(enable)
    self.log_events = enable
end

function AuraBar:Dump(unit, update_info)
    print("AuraBar <", self, ">:", self.type)
    print("    unit: ", self.unit)
    for i, aura in ipairs(self.auras) do
        if aura.instance then
            local name, _ = GetSpellInfo(aura.spell_id)
            local position
            print("    aura "..i..": "..aura.spell_id.." ("..name..")")
        end
    end
    self:Verify(true)
end

function AuraBar:Verify(no_header)
    local mine = {}
    for i, aura in ipairs(self.auras) do
        if aura.instance then mine[aura.instance] = aura.spell_id end
    end
    local actual = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(self.unit, i, "HELPFUL")
        if aura then actual[aura.auraInstanceID] = aura.spellId end
        aura = C_UnitAuras.GetAuraDataByIndex(self.unit, i, "HARMFUL")
        if aura then actual[aura.auraInstanceID] = aura.spellId end
    end
    local function report(is_extra, instance, spell_id)
        if not no_header then
            print("AuraBar <", self, "> verify FAILED!")
            no_header = true
        end
        local name, _ = GetSpellInfo(spell_id)
        print("    "..(extra and "EXTRA" or "MISSING").." "..instance..": "..spell_id.." ("..name..")")
    end
    for instance, spell_id in pairs(mine) do
        if not actual[instance] then report(true, instance, spell_id) end
    end
    for instance, spell_id in pairs(actual) do
        if not mine[instance] then report(false, instance, spell_id) end
    end
end
