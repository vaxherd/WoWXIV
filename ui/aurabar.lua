local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
UI.Aura = class()
UI.AuraBar = class()

local GameTooltip = GameTooltip

-- Maximum number of auras that can be applied to a unit.  This seems to
-- be hardcoded in the game, but we use a named constant anyway for
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

-- Spell ID of Withered Commander buff, for Suramar scenario.
local SPELL_WITHERED_COMMANDER = 227261

-- File ID of Dragon Glyph Resonance aura icon.  We have to match by
-- aura icon rather than spell ID because each token has a unique ID
-- (e.g. 394546 for Algeth'era Court, 394551 for Vault of the Incarnates).
local ICON_DRAGON_GLYPH_RESONANCE = 4728198

------------------------------------------------------------------------

local Aura = UI.Aura

-- Constructor takes two forms, to handle secure aura frames for
-- player buffs:
--     Aura(parent)  -- normal instance; pass the parent frame
--     Aura(secure_frame, true)  -- secure aura frame: pass the secure frame
--                               -- and set the second argument to true
function Aura:__constructor(frame, is_secure_player_aura)
    local f
    if is_secure_player_aura then
        f = frame
    else
        f = CreateFrame("Frame", nil, frame)
        f:Hide()
        f:SetSize(24, 37)
    end

    self.frame = f
    self.is_secure_player_aura = is_secure_player_aura
    self.parent = f:GetParent()
    self.tooltip_anchor = "BOTTOMRIGHT"
    self.unit = nil
    self.data = nil
    self.instance = nil
    self.spell_id = nil
    self.icon_id = nil
    self.is_helpful = nil
    self.is_mine = nil
    self.stacks = 0
    self.time_str = ""
    self.expires = 0
    self.timer_special = false -- Is timer repurposed as something else?

    local icon = f:CreateTexture(nil, "ARTWORK")
    self.icon = icon
    icon:SetSize(24, 24)

    local border = f:CreateTexture(nil, "OVERLAY")
    self.border = border
    border:SetSize(22, 26)
    WoWXIV.SetUITexture(border)

    local dispel = f:CreateTexture(nil, "OVERLAY", nil, 1)
    self.dispel = dispel
    dispel:SetSize(28, 9)
    WoWXIV.SetUITexture(dispel, 96, 124, 91, 100)

    local stack_label = f:CreateFontString(nil, "OVERLAY", "NumberFont_Shadow_Med")
    self.stack_label = stack_label
    stack_label:SetTextScale(1)
    stack_label:SetText("")

    local timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.timer = timer
    timer:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    timer:SetTextScale(1)
    timer:SetText("")

    -- Use HookScript instead of SetScript in case the frame is a secure frame.
    f:HookScript("OnEnter", function() self:OnEnter() end)
    f:HookScript("OnLeave", function() self:OnLeave() end)
end

function Aura:SetAnchor(anchor, x, y, tooltip_anchor)
    self.frame:SetPoint(anchor, self.parent, anchor, x, y)
    self:SetTooltipAnchor(tooltip_anchor)
end

function Aura:SetTooltipAnchor(tooltip_anchor)
    self.tooltip_anchor = "ANCHOR_" .. tooltip_anchor
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
    if self.time_str == "" then
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

local DRAGON_GLYPH_DIRECTION = {
    [ 2] = "Up",
    [ 3] = "Down",
    [ 4] = "N",
    [ 5] = "NW",
    [ 6] = "W",
    [ 7] = "SW",
    [ 8] = "S",
    [ 9] = "SE",
    [10] = "E",
    [11] = "NE",
}
function Aura:UpdateTimeLeft()
    local time_str, timer_special
    if self.icon_id == ICON_DRAGON_GLYPH_RESONANCE and WoWXIV_config["buffbar_dragon_glyph_distance"] then
        timer_special = true
        local value = self.data.points[1]
        if self.spell_id < 440000 then  -- DF value gives distance in yards.
            time_str = value .. "y"
        else  -- TWW value gives direction as a table index.
            time_str = DRAGON_GLYPH_DIRECTION[value] or ""
        end
    elseif self.spell_id == SPELL_WITHERED_COMMANDER then
        timer_special = true
        local withered_health = self.data.points[1]
        time_str = withered_health .. "%"
    else
        timer_special = false
        local time_left
        if self.expires > 0 then
            time_left = self.expires - GetTime()
        else
            time_left = 0
        end
        time_left = time_left / self.time_rate
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

    if timer_special ~= self.timer_special then
        self.timer_special = timer_special
        self.timer:SetTextScale(timer_special and 0.9 or 1.0)
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

function Aura:SwapWith(other)
    local unit = self.unit
    local data = self.data
    self:InternalUpdate(other.unit, other.data)
    other:InternalUpdate(unit, data)
end

function Aura:InternalUpdate(unit, data)
    if not unit then
        if self.unit then
            if not self.is_secure_player_aura then
                self.frame:Hide()
            end
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
            self.time_str = ""
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
    local is_mine = (data.sourceUnit == "player")
    local stacks = data.applications
    local expires = data.expirationTime

    -- Work around a bug in Withered Commander (count sometimes out of date).
    if spell_id == SPELL_WITHERED_COMMANDER then
        stacks = data.points[2]
    end

    self.unit = unit
    self.data = data
    self.instance = instance
    self.spell_id = spell_id
    self.is_mine = is_mine

    local f = self.frame
    local icon = self.icon
    local border = self.border
    local dispel = self.dispel
    local stack_label = self.stack_label
    local timer = self.timer

    if icon_id ~= self.icon_id or is_helpful ~= self.is_helpful then
        if is_helpful then
            icon:SetMask(WoWXIV.makepath("textures/buff-mask.png"))
            WoWXIV.SetUITexCoord(border, 99, 121, 14, 40)
            icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -3)
            border:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -2)
            dispel:SetPoint("TOPLEFT", f, "TOPLEFT", -2, -22)
            stack_label:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -1)
        else
            icon:SetMask(WoWXIV.makepath("textures/debuff-mask.png"))
            WoWXIV.SetUITexCoord(border, 99, 121, 40, 14)
            icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -7)
            border:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -6)
            dispel:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 0)
            stack_label:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -1)
        end
        icon:SetTexture(icon_id)  -- Must come _after_ SetMask()!
        if not self.icon_id and not self.is_secure_player_aura then
            f:Show()
        end
        self.icon_id = icon_id
        self.is_helpful = is_helpful
    end

    -- Some auras (e.g. the Enrage used by Emerald Dream rare mob Ristar
    -- the Rabid, spell ID 374898) have dispelName set to "", at least
    -- from the point of view of a Priest.  It's not clear if this is
    -- just how enrages work, or if an empty-string dispelName indicates
    -- "this aura is dispellable but not by you".  For now, we suppress
    -- the indicator for empty strings pending further information.
    -- (FIXME: more information needed)
    local can_dispel = data.dispelName and data.dispelName ~= ""
    if (data.dispelName and ((UnitIsFriend("player", unit) and not is_helpful)
                             or (UnitIsEnemy("player", unit) and is_helpful)))
    then
        dispel:Show()
    else
        dispel:Hide()
    end

    if stacks ~= self.stacks then
        if stacks > 0 then
            stack_label:SetText(stacks)
        else
            stack_label:SetText("")
        end
        self.stacks = stacks
    end

    if expires > 0 then
        self.expires = expires
        -- timeMod has some interesting uses, e.g. in Elisande (Nighthold)
        -- to preserve the user-visible time remaining on Ablating Explosion
        -- while the actual aura timer is lengthened by 100x to effectively
        -- pause it during Time Stop.
        self.time_rate = data.timeMod
        if is_mine then
            timer:SetTextColor(0.56, 1, 0.78)
        else
            timer:SetTextColor(1, 1, 1)
        end
        f:SetScript("OnUpdate", function() self:OnUpdate() end)
    else
        self.expires = 0
        self.time_rate = 1
        if self.icon_id == ICON_DRAGON_GLYPH_RESONANCE then
            f:SetScript("OnUpdate", function() self:OnUpdate() end)
        end
    end

    self:UpdateTimeLeft()  -- also updates tooltip by side effect
end

------------------------------------------------------------------------

local AuraBar = UI.AuraBar
AuraBar.__index = AuraBar

-- Returns 1 if AuraData a < AuraData b
local function CompareAuras(a, b)
    if a.isHelpful ~= b.isHelpful then
        return not a.isHelpful
    elseif (a.sourceUnit=="player") ~= (b.sourceUnit=="player") then
        return a.sourceUnit=="player"
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
function AuraBar:__constructor(type, align, cols, rows, parent, rel_x, rel_y)
    self.unit = null
    self.type = type
    self.align = align
    self.leftalign = (align == "TOPLEFT" or align == "BOTTOMLEFT")
    self.topalign = (align == "TOPLEFT" or align == "TOPRIGHT")
    -- Always anchor tooltips to bottom because we display the bars at the
    -- top of the screen (so top anchor would overlap the icon itself).
    local inv_align = ("BOTTOM"
                       .. (self.leftalign and "RIGHT" or "LEFT"))
    self.inv_align = inv_align
    self.cols = cols
    self.max = cols * rows
    self.parent = parent
    self.instance_map = {}  -- map from aura instance ID to self.auras[] index
    self.log_events = false  -- set with AuraBar:LogEvents()

    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    f:SetSize(24*cols, 40*rows)
    self:SetRelPosition(rel_x, rel_y)

    self.auras = {}
    local dx = self.leftalign and 24 or -24
    local dy = self.topalign and -40 or 40
    self.dx, self.dy = dx, dy
    for r = 1, rows do
        local y = (r-1)*dy
        for c = 1, cols do
            local aura = Aura(f)
            table.insert(self.auras, aura)
            local x = (c-1)*dx
            aura:SetAnchor(align, x, y, inv_align)
        end
    end

    f:SetScript("OnEvent", function(frame,event,...) self:OnUnitAura(...) end)

    self:Refresh()
end

function AuraBar:SetRelPosition(rel_x, rel_y)
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint(self.align, self.parent, self.align, rel_x, rel_y)
end

function AuraBar:Show()
    self.frame:Show()
end

function AuraBar:Hide()
    self.frame:Hide()
end

function AuraBar:SetSize(cols, rows)
    self.max = cols * rows
    local f, align, inv_align = self.frame, self.align, self.inv_align
    local dx, dy = self.dx, self.dy
    local index = 0
    for r = 1, rows do
        local y = (r-1)*dy
        for c = 1, cols do
            index = index+1
            local aura
            if index <= #self.auras then
                aura = self.auras[index]
            else
                aura = Aura(f)
                table.insert(self.auras, aura)
            end
            local x = (c-1)*dx
            aura:SetAnchor(align, x, y, inv_align)
        end
    end
    while index < #self.auras do
        index = index+1
        self.auras[index]:Update(nil)
    end
end

function AuraBar:SetOwnDebuffsOnly(enable)
    self.own_debuffs_only = enable
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
        for i = 1, MAX_AURAS do
            local data = C_UnitAuras.GetAuraDataByIndex(self.unit, i, "HARMFUL")
            if not data then break end
            if not (self.own_debuffs_only and data.sourceUnit ~= "player") then
                table.insert(aura_list, {i, "HARMFUL", data})
            end
        end
    end
    if self.type ~= "HARMFUL" then
        for i = 1, MAX_AURAS do
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
                    return (self.type ~= "HELPFUL"
                            and not (self.own_debuffs_only
                                     and aura_data.sourceUnit ~= "player"))
                else
                    return self.type == "MISC" or self.type == "ALL"
                end
            end
            if is_wanted(self, aura_data) then
                local function InsertBefore(new_data, aura)
                    if not aura.instance then
                        return true
                    else
                        return CompareAuras(new_data, aura.data)
                    end
                end
                for i = 1, self.max do
                    if InsertBefore(aura_data, self.auras[i]) then
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
                local aura_data = C_UnitAuras.GetAuraDataByAuraInstanceID(
                    self.unit, instance)
                if aura_data then  -- sanity check
                    local aura = self.auras[index]
                    local old_expires = aura.expires
                    aura:Update(self.unit, aura_data)
                    -- If duration changed, then we need to re-sort the aura.
                    -- We assume it won't move by a large amount so the swap
                    -- costs here are less than the cost to refresh the bar
                    -- as a whole.  But as for removed auras, if the bar is
                    -- full then we need to do a refresh instead.
                    if aura.expires ~= old_expires then
                        if self.auras[self.max].instance then
                            self:Refresh()
                            return
                        end
                        local new_expires = aura.expires
                        while index > 1 do
                            local prev = self.auras[index-1]
                            if not CompareAuras(aura.data, prev.data) then break end
                            aura:SwapWith(prev)
                            -- |aura| now points to the aura we swapped with.
                            self.instance_map[aura.instance] = index
                            aura, index = prev, index-1
                        end
                        local max = self.max
                        while index < max do
                            local next = self.auras[index+1]
                            if not next.instance or not CompareAuras(next.data, aura.data) then break end
                            aura:SwapWith(next)
                            self.instance_map[aura.instance] = index
                            aura, index = next, index+1
                        end
                        self.instance_map[aura_data.auraInstanceID] = index
                    end
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
            local name = C_Spell.GetSpellInfo(aura.spell_id).name
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
        local name = C_Spell.GetSpellInfo(spell_id).name
        print("    "..(extra and "EXTRA" or "MISSING").." "..instance..": "..spell_id.." ("..name..")")
    end
    for instance, spell_id in pairs(mine) do
        if not actual[instance] then report(true, instance, spell_id) end
    end
    for instance, spell_id in pairs(actual) do
        if not mine[instance] then report(false, instance, spell_id) end
    end
end
