local WoWXIV = WoWXIV
WoWXIV.FlyText = {}

local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo
local strsub = string.sub
local strfind = string.find

------------------------------------------------------------------------

local FlyText = {}
FlyText.__index = FlyText

-- Length of time a fly text will be displayed (seconds):
local FLYTEXT_TIME = 4.5

-- Default scale factor for text.
local FLYTEXT_FONT_SCALE = 1.1

-- Damage types for type argument to New():
local FLYTEXT_DAMAGE_DIRECT  = 1  -- direct damage, or DoT from channeling
local FLYTEXT_DAMAGE_PASSIVE = 2  -- DoT from auras
local FLYTEXT_HEAL_DIRECT    = 3
local FLYTEXT_HEAL_PASSIVE   = 4
local FLYTEXT_BUFF_ADD       = 5
local FLYTEXT_BUFF_REMOVE    = 6
local FLYTEXT_DEBUFF_ADD     = 7
local FLYTEXT_DEBUFF_REMOVE  = 8
local FLYTEXT_LOOT_MONEY     = 9
local FLYTEXT_LOOT_ITEM      = 10

-- Corresponding text colors:
local COLOR_RED   = {1, 0.753, 0.761}
local COLOR_GREEN = {0.929, 1, 0.906}
local COLOR_WHITE = {1, 1, 1}
local COLOR_GRAY  = {0.7, 0.7, 0.7}
local FLYTEXT_COLORS = {
    [FLYTEXT_DAMAGE_DIRECT]  = COLOR_RED,
    [FLYTEXT_DAMAGE_PASSIVE] = COLOR_RED,
    [FLYTEXT_HEAL_DIRECT]    = COLOR_GREEN,
    [FLYTEXT_HEAL_PASSIVE]   = COLOR_GREEN,
    [FLYTEXT_BUFF_ADD]       = COLOR_GREEN,
    [FLYTEXT_BUFF_REMOVE]    = COLOR_GRAY,
    [FLYTEXT_DEBUFF_ADD]     = COLOR_RED,
    [FLYTEXT_DEBUFF_REMOVE]  = COLOR_GRAY,
    [FLYTEXT_LOOT_MONEY]     = COLOR_WHITE,
    [FLYTEXT_LOOT_ITEM]      = COLOR_WHITE,
}

-- Internal helpers to pool frames (since we can't explicitly delete them).
function FlyText:AllocPooledFrame()
    self.frame_pool = self.frame_pool or {}
    local pool = self.frame_pool
    if pool[1] then
        local f = tremove(pool, 1)
        local w = f.WoWXIV
        -- name/icon/value are shown but contents are unspecified; other
        -- elements are either hidden or empty.
        w.name:Show()
        w.icon:Show()
        w.value:SetTextScale(FLYTEXT_FONT_SCALE)
        w.value:Show()
        w.border:Hide()
        w.stacks:Hide()
        w.icon_s:Hide()
        w.value_s:Hide()
        w.icon_c:Hide()
        w.value_c:Hide()
        f:Show()
        return f
    else
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("BACKGROUND")
        f.WoWXIV = {}
        local w = f.WoWXIV
        local name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        w.name = name
        name:SetPoint("RIGHT", f, "CENTER")
        name:SetTextScale(FLYTEXT_FONT_SCALE)
        local icon = f:CreateTexture(nil, "ARTWORK")
        w.icon = icon
        icon:SetPoint("LEFT", f, "CENTER")
        local border = f:CreateTexture(nil, "OVERLAY")
        w.border = border
        border:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, 1)
        local stacks = f:CreateFontString(nil, "OVERLAY", "NumberFont_Shadow_Med")
        w.stacks = stacks
        stacks:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 2)
        local value = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        w.value = value
        value:SetPoint("LEFT", icon, "RIGHT")
        value:SetTextScale(FLYTEXT_FONT_SCALE)
        local icon_s = f:CreateTexture(nil, "ARTWORK")
        w.icon_s = icon_s
        icon_s:SetPoint("LEFT", value, "RIGHT")
        icon_s:SetSize(16, 16)
        icon_s:SetTexture(237620)  -- Interface/MONEYFRAME/UI-SilverIcon.blp
        icon_s:Hide()
        local value_s = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        w.value_s = value_s
        value_s:SetPoint("LEFT", icon_s, "RIGHT")
        value_s:SetTextScale(FLYTEXT_FONT_SCALE)
        value_s:SetTextColor(1, 1, 1)
        local icon_c = f:CreateTexture(nil, "ARTWORK")
        w.icon_c = icon_c
        icon_c:SetPoint("LEFT", value_s, "RIGHT")
        icon_c:SetSize(16, 16)
        icon_c:SetTexture(237617)  -- Interface/MONEYFRAME/UI-CopperIcon.blp
        icon_c:Hide()
        local value_c = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        w.value_c = value_c
        value_c:SetPoint("LEFT", icon_c, "RIGHT")
        value_c:SetTextScale(FLYTEXT_FONT_SCALE)
        value_c:SetTextColor(1, 1, 1)
        return f
    end
end

function FlyText:FreePooledFrame(f)
    f:Hide()
    tinsert(self.frame_pool, f)
end

-- Static method: Return scroll offset per second for fly text.
function FlyText:GetDY()
    return -(UIParent:GetHeight()*0.3 / FLYTEXT_TIME)
end

-- Direct damage/heal: (type, unit, spell_id, school, amount, crit_flag)
-- Passive damage/heal: (type, unit, amount)
-- Buff/debuff: (type, unit, spell_id, school, stacks)
-- Loot money: (type, amount)
-- Loot item: (type, item_icon, item_name, name_color, count [default 1])
function FlyText:New(type, ...)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.type = type
    if type == FLYTEXT_DAMAGE_PASSIVE or type == FLYTEXT_HEAL_PASSIVE then
        new.unit, new.amount = ...
    elseif type >= FLYTEXT_DAMAGE_DIRECT and type <= FLYTEXT_DEBUFF_REMOVE then
        new.unit, new.spell_id, new.school, new.amount, new.crit_flag = ...
    elseif type == FLYTEXT_LOOT_MONEY then
        new.unit = "player"
        new.amount = ...
    elseif type == FLYTEXT_LOOT_ITEM then
        new.unit = "player"
        new.item_icon, new.item_name, new.item_color, new.amount = ...
    else
        print("FlyText error: invalid type", type)
        new.frame = nil
        return new
    end

    -- There seems to be no API for getting the screen position of a unit,
    -- so we can't draw anything for units other than the player.
    if new.unit ~= "player" then
        new.frame = nil
        return new
    end

    new.time = FLYTEXT_TIME
    new.start = GetTime()
    if type == FLYTEXT_HEAL_DIRECT or type == FLYTEXT_HEAL_PASSIVE then
        new.x = -(UIParent:GetWidth()*0.01)
    else
        new.x = UIParent:GetWidth()*0.05
    end
    new.y = 0
    new.dy = FlyText:GetDY()

    local f = FlyText:AllocPooledFrame()
    new.frame = f
    f:ClearAllPoints()
    f:SetPoint("CENTER", nil, "CENTER", new.x, 0)
    f:SetSize(100, 20)
    f:SetAlpha(0)

    local r, g, b = unpack(FLYTEXT_COLORS[type])

    local w = f.WoWXIV
    local name = w.name
    name:SetTextColor(r, g, b)
    local icon = w.icon
    local value = w.value
    value:SetTextColor(r, g, b)

    if type == FLYTEXT_DAMAGE_DIRECT or type == FLYTEXT_HEAL_DIRECT then
        local spell_name, _ = GetSpellInfo(new.spell_id)
        if spell_name then
            name:SetText(spell_name)
        else
            name:Hide()
        end
        if false then
            -- FIXME: school icon
        else
            icon:Hide()
            value:ClearAllPoints()
            value:SetPoint("LEFT", f, "CENTER", 10, 0)
        end
        local amount = new.amount
        if not amount then
            value:SetTextScale(0.9*FLYTEXT_FONT_SCALE)
            amount = "Miss"
        elseif new.crit_flag then
            value:SetTextScale(2*FLYTEXT_FONT_SCALE)
            amount = amount .. "!"
        end
        value:SetText(amount)

    elseif type == FLYTEXT_DAMAGE_PASSIVE or type == FLYTEXT_HEAL_PASSIVE then
        name:Hide()
        icon:Hide()
        value:ClearAllPoints()
        value:SetPoint("LEFT", f, "CENTER", 10, 0)
        value:SetText(new.amount)

    elseif type >= FLYTEXT_BUFF_ADD and type <= FLYTEXT_DEBUFF_REMOVE then
        name:Hide()
        local spell_name, _, spell_icon = GetSpellInfo(new.spell_id)
        icon:SetSize(24, 24)
        local border = w.border
        border:SetSize(22, 26)
        border:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
        if type == FLYTEXT_BUFF_ADD then
            icon:SetMask("Interface\\Addons\\WowXIV\\textures\\buff-mask.png")
            border:SetTexCoord(99/256.0, 121/256.0, 14/256.0, 40/256.0)
        else
            icon:SetMask("Interface\\Addons\\WowXIV\\textures\\buff-mask.png")
            border:SetTexCoord(99/256.0, 121/256.0, 40/256.0, 14/256.0)
        end
        icon:SetTexture(spell_icon)
        if new.amount and new.amount > 0 then
            local stacks = w.stacks
            stacks:SetText(new.amount)
        end
        value:ClearAllPoints()
        value:SetPoint("LEFT", icon, "RIGHT")
        if type == FLYTEXT_BUFF_ADD or type == FLYTEXT_DEBUFF_ADD then
            value:SetText("+" .. spell_name)
        else
            value:SetText("-" .. spell_name)
        end

    elseif type == FLYTEXT_LOOT_MONEY then
        name:Hide()
        local amount = new.amount
        local g = math.floor(amount / 10000)
        local s = math.floor(amount / 100) % 100
        local c = amount % 100
        if g > 0 then
            icon:SetSize(16, 16)
            icon:SetMask("")
            icon:SetTexture(237618)  -- Interface/MONEYFRAME/UI-GoldIcon.blp
            value:ClearAllPoints()
            value:SetPoint("LEFT", icon, "RIGHT")
            value:SetText(g)
        else
            icon:Hide()
            value:Hide()
        end
        if s > 0 then
            icon = w.icon_s
            icon:ClearAllPoints()
            if g > 0 then
                icon:SetPoint("LEFT", value, "RIGHT")
            else
                icon:SetPoint("LEFT", f, "CENTER")
            end
            icon:Show()
            value = w.value_s
            value:ClearAllPoints()
            value:SetPoint("LEFT", icon, "RIGHT")
            value:SetText(s)
            value:Show()
        end
        if c > 0 then
            icon = w.icon_c
            icon:ClearAllPoints()
            if g > 0 or s > 0 then
                icon:SetPoint("LEFT", value, "RIGHT")
            else
                icon:SetPoint("LEFT", f, "CENTER")
            end
            icon:Show()
            value = w.value_c
            value:SetText(c)
            value:Show()
        end

    elseif type == FLYTEXT_LOOT_ITEM then
        name:Hide()
        icon:SetSize(24, 24)
        icon:SetMask("")
        icon:SetTexture(new.item_icon)
        local color = new.item_color
        local r = tonumber("0x"..strsub(color, 1, 2)) / 255
        local g = tonumber("0x"..strsub(color, 3, 4)) / 255
        local b = tonumber("0x"..strsub(color, 5, 6)) / 255
        local text = new.item_name
        value:ClearAllPoints()
        value:SetPoint("LEFT", icon, "RIGHT")
        value:SetTextColor(r, g, b)
        value:SetText(new.item_name)
        if new.amount and new.amount > 1 then
            local value_s = w.value_s
            value_s:ClearAllPoints()
            value_s:SetPoint("LEFT", value, "RIGHT")
            value_s:SetText("×"..new.amount)
            value_s:Show()
        end

    end

    return new
end

-- Returns true if text is still displayed, false if deleted.
function FlyText:OnUpdate()
    local f = self.frame
    if not f then return false end

    local now = GetTime()
    local t = now - self.start
    if t >= self.time then
        FlyText:FreePooledFrame(f)
        self.frame = nil
        return false
    end

    if t < 0.25 then
        f:SetAlpha(t/0.25)
    elseif t > self.time - 0.5 then
        local left = self.time - t
        f:SetAlpha(left/0.5)
    else
        f:SetAlpha(1)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", nil, "CENTER", self.x, self.y + self.dy*t)
    return true
end

-- Push text forward by the given number of seconds.
function FlyText:Push(dt)
    self.y = self.y + dt * self.dy
end

------------------------------------------------------------------------

local CombatEvent = {}
CombatEvent.__index = CombatEvent

function CombatEvent:New(...)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.event = {...}
    new:ParseEvent()
    return new
end

function CombatEvent:ParseEvent()
    local event = self.event
    self.timestamp = event[1]
    self.type = event[2]
    self.hidden_source = event[3]  -- e.g. for fall damage
    self.source = event[4]
    self.source_name = event[5]
    self.source_flags = event[6]
    self.source_raid_flags = event[7]
    self.dest = event[8]
    self.dest_name = event[9]
    self.dest_flags = event[10]
    self.dest_raid_flags = event[11]
    local argi = 12

    local type = self.type
    local rawtype = type

    -- Special cases first.
    if strsub(type, 1, 8) == "ENCHANT_" then
        self.category = "ENCHANT"
        self.subtype = strsub(type, 9, -1)
        self.spell_name = event[argi]
        self.item_id = event[argi+1]
        self.item_name = event[argi+2]
        return
    elseif type == "PARTY_KILL" then
        self.category = "PARTY"
        self.subtype = strsub(type, 7, -1)
        return  -- No extra arguments.
    elseif type == "UNIT_DIED" or type == "UNIT_DESTROYED" then
        self.category = "UNIT"
        self.subtype = strsub(type, 6, -1)
        return  -- No extra arguments.
    elseif type == "DAMAGE_SPLIT" or type == "DAMAGE_SHIELD" then
        type = "SPELL_DAMAGE"
    elseif type == "DAMAGE_SHIELD_MISSED" then
        type = "SPELL_MISSED"
    end

    local sep = strfind(type, "_")
    if not sep then
        print("Unhandled combat event:", rawtype)
        self.category = type
        self.subtype = ""
        return
    end
    local category = strsub(type, 1, sep-1)
    local subtype = strsub(type, sep+1, -1)
    if category == "SWING" then
        self.spell = nil
        self.spell_name = nil
        self.spell_school = 1  -- Physical
    elseif category == "RANGE" or category == "SPELL" then
        self.spell = event[argi]
        self.spell_name = event[argi+1]
        self.spell_school = event[argi+2]
        argi = argi + 3
    elseif category == "ENVIRONMENTAL" then
        self.env_type = event[argi]
        argi = argi + 1
    else
        print("Unhandled combat event:", rawtype)
        return
    end
    self.category = category
    self.subtype = subtype

    if subtype == "DAMAGE" or subtype == "PERIODIC_DAMAGE" or subtype == "BUILDING_DAMAGE" then
        self.amount = event[argi]
        self.overkill = event[argi+1]
        self.school = event[argi+2]
        self.resisted = event[argi+3]
        self.blocked = event[argi+4]
        self.absorbed = event[argi+5]
        self.critical = event[argi+6]
        self.glancing = event[argi+7]
        self.crushing = event[argi+8]
    elseif subtype == "MISSED" then
        self.miss_type = event[argi]
        self.is_offhand = event[argi+1]
        self.amount = event[argi+2]
    elseif subtype == "HEAL" or subtype == "PERIODIC_HEAL" then
        self.amount = event[argi]
        self.overheal = event[argi+1]
        self.absorbed = event[argi+2]
        self.critical = event[argi+3]
    elseif subtype == "ENERGIZE" then
        self.amount = event[argi]
        self.power_type = event[argi+1]
    elseif subtype == "DRAIN" or subtype == "LEECH" then
        self.amount = event[argi]
        self.power_type = event[argi+1]
        self.extra_amount = event[argi+2]
    elseif subtype == "INTERRUPT" or subtype == "DISPEL_FAILED" then
        self.extra_spell_id = event[argi]
        self.extra_spell_name = event[argi+1]
        self.extra_school = event[argi+2]
    elseif subtype == "DISPEL" or subtype == "STOLEN" or subtype == "AURA_BROKEN_SPELL" then
        self.extra_spell_id = event[argi]
        self.extra_spell_name = event[argi+1]
        self.extra_school = event[argi+2]
        self.aura_type = event[argi+3]
    elseif subtype == "EXTRA_ATTACKS" then
        self.amount = event[argi]
    elseif strsub(subtype, 1, 5) == "AURA_" then
        self.aura_type = event[argi]
        self.amount = event[argi+1]
    elseif subtype == "CAST_FAILED" then
        self.failed_type = event[argi]
    end
end

------------------------------------------------------------------------

local FlyTextManager = {}
FlyTextManager.__index = FlyTextManager

function FlyTextManager:New(parent)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.enabled = true
    new.texts = {}
    new.dot = {}
    new.hot = {}
    new.last_left = 0
    new.last_right = 0
    new.zone_entered = 0
    new.last_money = GetMoney()
    new.last_item_icon = nil

    local f = CreateFrame("Frame", "WoWXIV_FlyTextManager", nil)
    new.frame = f
    f.xiv_eventmap = {
        COMBAT_LOG_EVENT_UNFILTERED = FlyTextManager.OnCombatLogEvent,
        PLAYER_MONEY = FlyTextManager.OnPlayerMoney,
        CHAT_MSG_LOOT = FlyTextManager.OnLootItem,
        CHAT_MSG_CURRENCY = FlyTextManager.OnLootCurrency,
        -- Suppress aura events for the first 0.5 sec after entering a zone
        -- to avoid spam from permanent buffs (which are reapplied on
        -- entering each new zone).
        PLAYER_ENTERING_WORLD = FlyTextManager.OnEnterZone,
    }
    for event, _ in pairs(f.xiv_eventmap) do
        f:RegisterEvent(event)
    end
    f:SetScript("OnEvent", function(self, event, ...)
        local handler = self.xiv_eventmap[event]
        if handler then handler(new, event, ...) end
    end)
    f:SetScript("OnUpdate", function() new:OnUpdate() end)

    return new
end

function FlyTextManager:Enable(enable)
    self.enabled = enable
    if enable then
        local f = self.frame
        for event, _ in pairs(f.xiv_eventmap) do
            f:RegisterEvent(event)
        end
    else
        self.frame:UnregisterAllEvents()
    end
end

function FlyTextManager:OnEnterZone()
    self.zone_entered = GetTime()
    self.last_money = GetMoney()
end

function FlyTextManager:OnCombatLogEvent()
    local event = CombatEvent:New(CombatLogGetCurrentEventInfo())

    if GetTime() < self.zone_entered + 0.5 and strsub(event.subtype, 1, 5) == "AURA_" then
        return  -- suppress aura spam
    end

    local unit = event.dest
    if unit == UnitGUID("player") then
        unit = "player"
    else
        return  -- Can't draw fly text for non-player units.
    end

    local text = nil
    local left_side = false
    if event.subtype == "DAMAGE" then
        text = FlyText:New(FLYTEXT_DAMAGE_DIRECT, unit, event.spell,
                           event.spell_school, event.amount, event.critical)
    elseif event.subtype == "PERIODIC_DAMAGE" then
        self.dot = self.dot or {}
        self.dot[unit] = (self.dot[unit] or 0) + event.amount
    elseif event.subtype == "MISSED" then
        -- Note: absorbed heals are reported as "heal for 0" with the
        -- amount absorbed in event.absorbed, so we don't have to worry
        -- about separating them out here.
        text = FlyText:New(FLYTEXT_DAMAGE_DIRECT, unit, event.spell,
                           event.spell_school, event.amount and 0 or nil)
    elseif event.subtype == "HEAL" then
        left_side = true
        text = FlyText:New(FLYTEXT_HEAL_DIRECT, unit, event.spell,
                           event.spell_school, event.amount, event.critical)
    elseif event.subtype == "PERIODIC_HEAL" then
        self.hot = self.hot or {}
        self.hot[unit] = (self.hot[unit] or 0) + event.amount
    elseif event.subtype == "AURA_APPLIED" then
        -- It doesn't look like APPLIED_DOSE is used for stacking buffs?
        -- (and so we can't actually get the stack count)
        text = FlyText:New(
            event.aura_type=="BUFF" and FLYTEXT_BUFF_ADD or FLYTEXT_DEBUFF_ADD,
            unit, event.spell, event.spell_school)
    elseif event.subtype == "AURA_REMOVED" then
        text = FlyText:New(
            event.aura_type=="BUFF" and FLYTEXT_BUFF_REMOVE or FLYTEXT_DEBUFF_REMOVE,
            unit, event.spell, event.spell_school)
    end
    if text then
        self:AddText(text, left_side)
    end
end

function FlyTextManager:OnPlayerMoney()
    local money = GetMoney()
    local diff = money - self.last_money
    self.last_money = money
    if diff > 0 then
        self:AddText(FlyText:New(FLYTEXT_LOOT_MONEY, diff))
    end
end

-- Returns: type, id, color, count
local function ParseLootMsg(msg)
    local color = strfind(msg, "|c")
    if color then
        color = strsub(msg, color+4, color+9)
    else
        color = "ffffff"
    end
    local link = strfind(msg, "|H")
    if link then
        colon1 = strfind(msg, ":", link+2)
        if colon1 then
            local colon2 = strfind(msg, ":", colon1+1)
            if colon2 then
                local count
                local link_end = strfind(msg, "|h|r", colon2+1)
                if link_end and strsub(msg, link_end+4, link_end+4) == "x" then
                    count = tonumber(strsub(msg, link_end+5, -1))
                else
                    count = 1
                end
                return strsub(msg, link+2, colon1-1),
                       strsub(msg, colon1+1, colon2-1),
                       color,
                       count
            end
        end
    end
    return nil
end

function FlyTextManager:OnLootItem(event, msg)
    local type, id, color, count = ParseLootMsg(msg)
    if type ~= "item" then return end
    local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    if name and icon then
        self:AddText(FlyText:New(FLYTEXT_LOOT_ITEM, icon, name, color, count))
    end
end

function FlyTextManager:OnLootCurrency(event, msg)
    local type, id, color, count = ParseLootMsg(msg)
    if type ~= "currency" then return end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if info and info.name and info.iconFileID then
        local name = info.name
        local dash = strfind(name, "-")
        if dash then
            name = strsub(name, 1, dash-1)  -- strip covenant
        end
        self:AddText(FlyText:New(FLYTEXT_LOOT_ITEM,
                                 info.iconFileID, name, color, count))
    end
end

function FlyTextManager:AddText(text, left_side)
    local now = GetTime()
    local dt
    if left_side then
        dt = now - self.last_left
        self.last_left = now
    else
        dt = now - self.last_right
        self.last_right = now
    end
    local dy = math.abs(FlyText:GetDY())
    local min_offset = 16
    if dt*dy < min_offset then
        local time_offset = (min_offset - dt*dy) / dy
        for _, t in ipairs(self.texts) do
            t:Push(time_offset)
        end
    end
    tinsert(self.texts, text)
end

function FlyTextManager:OnUpdate()
    if self.dot then
        for unit, amount in pairs(self.dot) do
            text = FlyText:New(FLYTEXT_DAMAGE_PASSIVE, unit, amount)
            tinsert(self.texts, text)
        end
        self.dot = nil
    end

    if self.hot then
        for unit, amount in pairs(self.hot) do
            text = FlyText:New(FLYTEXT_HEAL_PASSIVE, unit, amount)
            tinsert(self.texts, text)
        end
        self.hot = nil
    end

    local texts = self.texts
    local i = 1
    while i <= #texts do
        if texts[i]:OnUpdate() then
            i = i + 1
        else
            tremove(texts, i)
        end
    end
end

------------------------------------------------------------------------

-- Create the fly-text manager.
function WoWXIV.FlyText.CreateManager()
    WoWXIV.FlyText.manager = FlyTextManager:New()
    WoWXIV.FlyText.Enable(WoWXIV_config["flytext_enable"])
end

-- Enable or disable fly-text dispaly.
function WoWXIV.FlyText.Enable(enable)
    if WoWXIV.FlyText.manager then
        WoWXIV.FlyText.manager:Enable(enable)
    end
end
