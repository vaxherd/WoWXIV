local _, WoWXIV = ...
WoWXIV.FlyText = {}

local class = WoWXIV.class

local CLM = WoWXIV.CombatLogManager
local GetItemInfo = C_Item.GetItemInfo
local strfind = string.find
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub
local tinsert = tinsert

------------------------------------------------------------------------

local FlyText = class()

-- Length of time a flying text string will be displayed (seconds).
local FLYTEXT_TIME = 4.5

-- Default scale factor for text.
local FLYTEXT_FONT_SCALE = 1.1
-- Scale factor for critical hits.
local FLYTEXT_CRIT_SCALE = FLYTEXT_FONT_SCALE * 2
-- Scale factor for "Miss" text.
local FLYTEXT_MISS_SCALE = FLYTEXT_FONT_SCALE * 0.9

-- Damage types for type argument to constructor.
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

-- Corresponding text colors.
local COLOR_RED   = {1, 0.753, 0.761}
local COLOR_GREEN = {0.929, 1, 0.906}
local COLOR_BLUE  = {0.790, 0.931, 0.970}
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
-- The frame returned from this function has name/icon/value elements shown
-- with unspecified contents and the value text scale set to the default;
-- other elements are either hidden or empty, so the caller does not need
-- to explicitly hide them if not needed.
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
        w.exclam:Hide()
        w.border:Hide()
        w.stacks:Hide()
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
        -- Use a separate text instance with a larger font size for the
        -- "!" critical indicator because it looks too much like a "1"
        -- in the game font.
        local exclam = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        w.exclam = exclam
        exclam:SetPoint("LEFT", value, "RIGHT")
        exclam:SetTextScale(FLYTEXT_CRIT_SCALE * 1.15)
        exclam:SetText("!")
        exclam:Hide()
        return f
    end
end

function FlyText:FreePooledFrame(f)
    f:Hide()
    tinsert(self.frame_pool, f)
end

-- Static method: Return scroll offset per second for flying text.
function FlyText:GetDY()
    return -(UIParent:GetHeight()*0.3 / FLYTEXT_TIME)
end

-- Direct damage/heal: (type, unit, spell_id, school, amount, crit_flag)
-- Passive damage/heal: (type, unit, amount)
-- Buff/debuff: (type, unit, spell_id, school, stacks)
-- Loot money: (type, amount)
-- Loot item: (type, item_icon, item_name, name_color, count [default 1])
function FlyText:__constructor(type, ...)
    self.type = type
    if type == FLYTEXT_DAMAGE_PASSIVE or type == FLYTEXT_HEAL_PASSIVE then
        self.unit, self.amount = ...
    elseif type >= FLYTEXT_DAMAGE_DIRECT and type <= FLYTEXT_DEBUFF_REMOVE then
        self.unit, self.spell_id, self.school, self.amount, self.crit_flag = ...
    elseif type == FLYTEXT_LOOT_MONEY then
        self.unit = "player"
        self.amount = ...
    elseif type == FLYTEXT_LOOT_ITEM then
        self.unit = "player"
        self.item_icon, self.item_name, self.item_color, self.amount = ...
    else
        print("FlyText error: invalid type", type)
        self.frame = nil
        return self
    end

    -- There seems to be no API for getting the screen position of a unit,
    -- so we can't draw anything for units other than the player.
    if self.unit ~= "player" then
        self.frame = nil
        return self
    end

    self.time = FLYTEXT_TIME
    self.start = GetTime()
    if type == FLYTEXT_HEAL_DIRECT or type == FLYTEXT_HEAL_PASSIVE then
        self.x = -(UIParent:GetWidth()*0.01)
    else
        self.x = UIParent:GetWidth()*0.05
    end
    self.y = 0
    self.dy = FlyText:GetDY()

    local f = FlyText:AllocPooledFrame()
    self.frame = f
    f:ClearAllPoints()
    f:SetPoint("CENTER", nil, "CENTER", self.x, 0)
    f:SetSize(100, 20)
    f:SetAlpha(0)

    local w = f.WoWXIV
    local name = w.name
    local icon = w.icon
    local value = w.value

    local r, g, b = unpack(FLYTEXT_COLORS[type])
    name:SetTextColor(r, g, b)
    value:SetTextColor(r, g, b)

    if type == FLYTEXT_DAMAGE_DIRECT or type == FLYTEXT_HEAL_DIRECT then
        local spell_info = self.spell_id and C_Spell.GetSpellInfo(self.spell_id) or nil
        if spell_info and spell_info.name then
            name:SetText(spell_info.name)
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
        local amount = self.amount
        if not amount then
            value:SetTextScale(FLYTEXT_MISS_SCALE)
            amount = "Miss"
        elseif self.crit_flag then
            value:SetTextScale(FLYTEXT_CRIT_SCALE)
            local exclam = w.exclam
            exclam:SetTextColor(r, g, b)
            exclam:Show()
        end
        value:SetText(amount)

    elseif type == FLYTEXT_DAMAGE_PASSIVE or type == FLYTEXT_HEAL_PASSIVE then
        name:Hide()
        icon:Hide()
        value:ClearAllPoints()
        value:SetPoint("LEFT", f, "CENTER", 10, 0)
        value:SetText(self.amount)

    elseif type >= FLYTEXT_BUFF_ADD and type <= FLYTEXT_DEBUFF_REMOVE then
        name:Hide()
        local spell_info = C_Spell.GetSpellInfo(self.spell_id)
        icon:SetSize(24, 24)
        local border = w.border
        border:SetSize(22, 26)
        if type == FLYTEXT_BUFF_ADD or type == FLYTEXT_BUFF_REMOVE then
            icon:SetMask("Interface/Addons/WowXIV/textures/buff-mask.png")
            WoWXIV.SetUITexture(border, 99, 121, 14, 40)
        else
            icon:SetMask("Interface/Addons/WowXIV/textures/debuff-mask.png")
            WoWXIV.SetUITexture(border, 99, 121, 40, 14)
        end
        icon:SetTexture(spell_info.iconID)
        if self.amount and self.amount > 0 then
            local stacks = w.stacks
            stacks:Show()
            stacks:SetText(self.amount)
        end
        value:ClearAllPoints()
        value:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        if type == FLYTEXT_BUFF_ADD or type == FLYTEXT_DEBUFF_ADD then
            value:SetText("+" .. spell_info.name)
        else
            value:SetText("-" .. spell_info.name)
        end

    elseif type == FLYTEXT_LOOT_MONEY then
        name:Hide()
        icon:Hide()
        value:ClearAllPoints()
        value:SetPoint("LEFT", f, "CENTER")
        -- GetMoneyString() is a Blizzard API function, defined in
        -- Interface/SharedXML/FormattingUtil.lua, which creates a
        -- gold/silver/copper money string with embedded icons.
        -- The function takes an optional second boolean argument which
        -- (if true) adds thousands separators, but we leave it at the
        -- default of false for consistency with the rest of our UI.
        value:SetText(GetMoneyString(self.amount))

    elseif type == FLYTEXT_LOOT_ITEM then
        name:Hide()
        icon:SetSize(24, 24)
        icon:SetMask("")
        icon:SetTexture(self.item_icon)
        local color = self.item_color
        local r = tonumber("0x"..strsub(color, 1, 2)) / 255
        local g = tonumber("0x"..strsub(color, 3, 4)) / 255
        local b = tonumber("0x"..strsub(color, 5, 6)) / 255
        local text = self.item_name
        if self.amount and self.amount > 1 then
            text = text .. WoWXIV.FormatColoredText("×"..self.amount, COLOR_BLUE)
        end
        value:ClearAllPoints()
        value:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        value:SetTextColor(r, g, b)
        value:SetText(text)

    end
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

local FlyTextManager = class()

function FlyTextManager:__constructor(parent)
    self.enabled = true
    self.texts = {}
    self.dot = {}
    self.hot = {}
    self.last_left = 0
    self.last_right = 0
    self.zone_entered = 0
    self.last_money = GetMoney()
    self.last_item_icon = nil
    self.last_aura_list = nil
    self.last_currency = nil

    local f = CreateFrame("Frame", "WoWXIV_FlyTextManager", nil)
    self.frame = f
    f.xiv_eventmap = {
        CHAT_MSG_LOOT = FlyTextManager.OnLootItem,
        CURRENCY_DISPLAY_UPDATE = FlyTextManager.OnCurrencyUpdate,
        PLAYER_MONEY = FlyTextManager.OnPlayerMoney,
        -- Suppress aura events for the first 0.5 sec after entering a zone
        -- to avoid spam from permanent buffs (which are reapplied on
        -- entering each self zone).
        PLAYER_ENTERING_WORLD = FlyTextManager.OnEnterZone,
    }
    f:SetScript("OnEvent", function(frame, event, ...)
        local handler = frame.xiv_eventmap[event]
        if handler then handler(self, event, ...) end
    end)
    f:SetScript("OnUpdate", function() self:OnUpdate() end)
end

function FlyTextManager:Enable(enable)
    self.enabled = enable
    if enable then
        local f = self.frame
        for event, _ in pairs(f.xiv_eventmap) do
            f:RegisterEvent(event)
        end
        CLM.RegisterAnyEvent(self, self.OnCombatLogEvent)
    else
        self.frame:UnregisterAllEvents()
        CLM.UnregisterAllEvents(self)
    end
end

function FlyTextManager:OnEnterZone()
    self.zone_entered = GetTime()
    self.last_money = GetMoney()
end

function FlyTextManager:OnCombatLogEvent(event)
    if GetTime() < self.zone_entered + 0.5 and strsub(event.subtype, 1, 5) == "AURA_" then
        return  -- suppress aura spam
    end

    local unit = event.dest
    if unit == UnitGUID("player") or (UnitInVehicle("player") and unit == UnitGUID("vehicle")) then
        unit = "player"
    else
        return  -- Can't draw flying text for non-player units.
    end

    local text = nil
    local left_side = false
    local is_aura = false
    if event.subtype == "DAMAGE" then
        text = FlyText(FLYTEXT_DAMAGE_DIRECT, unit, event.spell_id,
                       event.spell_school, event.amount, event.critical)
    elseif event.subtype == "PERIODIC_DAMAGE" then
        self.dot = self.dot or {}
        self.dot[unit] = (self.dot[unit] or 0) + event.amount
    elseif event.subtype == "MISSED" then
        -- Note: absorbed heals are reported as "heal for 0" with the
        -- amount absorbed in event.absorbed, so we don't have to worry
        -- about separating them out here.
        text = FlyText(FLYTEXT_DAMAGE_DIRECT, unit, event.spell_id,
                       event.spell_school, event.amount and 0 or nil)
    elseif event.subtype == "HEAL" then
        left_side = true
        text = FlyText(FLYTEXT_HEAL_DIRECT, unit, event.spell_id,
                       event.spell_school, event.amount, event.critical)
    elseif event.subtype == "PERIODIC_HEAL" then
        self.hot = self.hot or {}
        self.hot[unit] = (self.hot[unit] or 0) + event.amount
    elseif event.subtype == "AURA_APPLIED" then
        is_aura = true
        self:DoAura((event.aura_type=="BUFF" and FLYTEXT_BUFF_ADD
                                             or FLYTEXT_DEBUFF_ADD),
                    unit, event.spell_id, event.spell_school)
    elseif event.subtype == "AURA_APPLIED_DOSE" then
        is_aura = true
        self:DoAura((event.aura_type=="BUFF" and FLYTEXT_BUFF_ADD
                                             or FLYTEXT_DEBUFF_ADD),
                    unit, event.spell_id, event.spell_school, event.amount)
    elseif event.subtype == "AURA_REMOVED" then
        is_aura = true
        self:DoAura((event.aura_type=="BUFF" and FLYTEXT_BUFF_REMOVE
                                             or FLYTEXT_DEBUFF_REMOVE),
                    unit, event.spell_id, event.spell_school)
    end
    if not is_aura and self.last_aura_list then
        for aura_text, _ in pairs(self.last_aura_list) do
            self:AddText(aura_text, false)
        end
        self.last_aura_list = nil
    end
    if text then
        self:AddText(text, left_side)
    end
end

-- Helper to filter out redundant aura events.  We particularly check for
-- two patterns:
--    1) Removal of buff followed immediately by reapplication.  This
--       often occurs on zone or subzone transitions - the "Sign of
--       Awakened Storms" reputation bonus buff in Dragonflight season 4
--       is a particularly egregious example, being cycled like this
--       frequently and even multiple times at once when entering the
--       Zskera Vault.
--    2) Repeated APPLIED_DOSE events on the same buff.  This is notably
--       seen with the "Feral Awakening" buff in the Superbloom event,
--       where the application counter is used to show the amount of Bloom
--       obtained by the player.  Bloom is typically gained in increments
--       of 5 or 10 at a time, for which the game triggers a +1 dose event
--       immediately followed by an event which adds the remaining amount.
function FlyTextManager:DoAura(...)
    local text = FlyText(...)
    local last = self.last_aura_list
    local filter_this = false
    if last then
        for last_text, _ in pairs(last) do
            if last_text.unit == text.unit and last_text.spell_id == text.spell_id then
                local filter_last = false
                if last_text.type == FLYTEXT_BUFF_REMOVE and text.type == FLYTEXT_BUFF_ADD then
                    filter_last = true
                    filter_this = true
                elseif last_text.type == FLYTEXT_BUFF_ADD and text.type == FLYTEXT_BUFF_ADD then
                    filter_last = true
                end
                if filter_last then
                    last[last_text] = nil
                end
                break
            end
        end
    end
    if not filter_this then
        if not last then last = {} end
        last[text] = true
    end
    self.last_aura_list = last
end

-- Returns: type, id, color, count [, name]
local function ParseLootMsg(msg)
    local color = strstr(msg, "|c")
    if color then
        color = strsub(msg, color+4, color+9)
    else
        color = "ffffff"
    end
    local link = strstr(msg, "|H")
    if link then
        colon1 = strstr(msg, ":", link+2)
        if colon1 then
            local type = strsub(msg, link+2, colon1-1)
            local colon2 = strstr(msg, ":", colon1+1)
            if colon2 then
                local id = strsub(msg, colon1+1, colon2-1)
                local name, count
                local link_end = strstr(msg, "|h|r", colon2+1)
                if link_end then
                    if strsub(msg, link_end-1, link_end-1) == "]" then
                        local name_start = strstr(msg, "[", colon2+1)
                        if name_start then
                            name = strsub(msg, name_start+1, link_end-2)
                        end
                    end
                    if strsub(msg, link_end+4, link_end+4) == "x" then
                        count = tonumber(strsub(msg, link_end+5, -1))
                    else
                        count = 1
                    end
                end
                return type, id, color, count, name
            end
        end
    end
    return nil
end

function FlyTextManager:OnLootItem(event, msg)
    -- Filter out loot from other party members.
    -- FIXME: locale-dependent, is there a better way?
    if strsub(msg, 1, 11) ~= "You receive" and strsub(msg, 1, 10) ~= "You create" then
        return
    end

    local type, id, color, count, name = ParseLootMsg(msg)
    if type ~= "item" then return end
    local base_name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    if not name then name = base_name end
    if name and icon then
        self:AddText(FlyText(FLYTEXT_LOOT_ITEM, icon, name, color, count))
    end
end

-- For duplicate currency event check, see below.
local CURRENCY_PAIRS = {
    {2805, 2806},  -- Whelpling's Awakened Crest
    {2807, 2808},  -- Drake's Awakened Crest
    {2810, 2809},  -- Wyrm's Awakened Crest
    {2811, 2812},  -- Aspect's Awakened Crest
    {2914, 2918},  -- Weathered Harbinger Crest
    {2915, 2919},  -- Carved Harbinger Crest
    {2916, 2920},  -- Runed Harbinger Crest
    {2917, 2921},  -- Gilded Harbinger Crest
    {3107, 3111},  -- Weathered Undermine Crest
    {3108, 3112},  -- Carved Undermine Crest
    {3109, 3113},  -- Runed Undermine Crest
    {3110, 3114},  -- Gilded Undermine Crest
}
local CURRENCY_PAIR_MAP = {}
for _, pair in ipairs(CURRENCY_PAIRS) do
    CURRENCY_PAIR_MAP[pair[1]] = pair[2]
    CURRENCY_PAIR_MAP[pair[2]] = pair[1]
end

function FlyTextManager:OnCurrencyUpdate(event, id, total, change)
    -- We seem to get an empty event on startup.
    if not id then return end
    -- Only report gains of currency, since losses are usually due to
    -- explicit player action.
    if change <= 0 then return end

    -- Omit duplicates which arise from receiving upgrade currency that
    -- doesn't count against weekly limits (e.g., the Drake's Crests
    -- awarded from completing Blue Dragonflight campaign questlines).
    if self.last_currency then
        local last_id, last_change = unpack(self.last_currency)
        self.last_currency = nil
        if id == CURRENCY_PAIR_MAP[last_id] and change == last_change then
            return
        end
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not info then return end  -- Sanity check.

    -- Many non-item stats/collectables (both actual currencies like
    -- Nazjatar manapearls or Dragon Isles supplies, and more stat-like
    -- values such as talent points) are internally tracked as
    -- "currencies"; notably, the player's time in a dragon race is
    -- recorded using four "currencies", for the whole number, tenths,
    -- hundredths, and thousands of seconds.  We only want to show flying
    -- text for things the game would normally report with a log message,
    -- so we exclude anything without an icon or with a "hidden" notation
    -- in the name; there unfortunately doesn't seem to be an explicit
    -- "hidden" flag we can check.  (We don't just parse CHAT_MSG_CURRENCY
    -- because that's significantly delayed relative to the actual currency
    -- gain in many cases.)
    local icon = info.iconFileID
    local name = info.name
    WoWXIV.LogWindow.AddMessage("WOWXIV_DEBUG", id.." "..name.." "..total)
    if (not icon or not name
        or strstr(name, "Hidden")
        or strstr(name, "DNT")
        or strstr(name, "Delves - System")  -- affix event trackers (3103/3104)
    ) then
        return
    end

    -- Strip the faction from Shadowlands covenant and DF+ Renown currencies
    -- (which are internally named e.g. "Reservoir Anima-Night Fae" or
    -- "Renown - Council of Dornogal").  The Shadowlands currencies are the
    -- only ones that don't have a space around the dash, and we now have
    -- currencies with hyphenated names (e.g. 3090 Flame-Blessed Iron), so
    -- we need to detect those specially.
    local dash = (strstr(name, " - ")
                  or strstr(name, "-Kyrian")
                  or strstr(name, "-Venthyr")
                  or strstr(name, "-Night Fae")
                  or strstr(name, "-Necrolord"))
    if dash then
        name = strsub(name, 1, dash-1)
    elseif strsub(name, 1, 7) == "Renown-" then
        name = "Renown"
    end

    local color = ITEM_QUALITY_COLORS[info.quality].hex or "|cff000000"
    color = strsub(color, 5, 10)
    self:AddText(FlyText(FLYTEXT_LOOT_ITEM,
                         info.iconFileID, name, color, change))
    if CURRENCY_PAIR_MAP[id] then
        self.last_currency = {id, change}
    end
end

function FlyTextManager:OnPlayerMoney()
    local money = GetMoney()
    local diff = money - self.last_money
    self.last_money = money
    if diff > 0 then
        self:AddText(FlyText(FLYTEXT_LOOT_MONEY, diff))
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
    if self.last_aura_list then
        for aura_text, _ in pairs(self.last_aura_list) do
            self:AddText(aura_text, false)
        end
        self.last_aura_list = nil
    end

    if self.dot then
        for unit, amount in pairs(self.dot) do
            text = FlyText(FLYTEXT_DAMAGE_PASSIVE, unit, amount)
            self:AddText(text, false)
        end
        self.dot = nil
    end

    if self.hot then
        for unit, amount in pairs(self.hot) do
            text = FlyText(FLYTEXT_HEAL_PASSIVE, unit, amount)
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

local LootHandler = class()

function LootHandler:__constructor()
    self.looting = false
    self.autolooted = false

    local f = CreateFrame("Frame", "WoWXIV_LootHandler", nil)
    self.frame = f
    f:Hide()
    f:SetScript("OnEvent", function(frame,...) self:OnEvent(...) end)
    f:RegisterEvent("LOOT_READY")
    f:RegisterEvent("LOOT_CLOSED")

    -- For debugging/reverse-engineering:
    if false then
        f:SetScript("OnEvent", function(frame,...) print(...) end)
        f:RegisterEvent("BONUS_ROLL_ACTIVATE")
        f:RegisterEvent("BONUS_ROLL_DEACTIVATE")
        f:RegisterEvent("BONUS_ROLL_FAILED")
        f:RegisterEvent("BONUS_ROLL_RESULT")
        f:RegisterEvent("BONUS_ROLL_STARTED")
        f:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
        f:RegisterEvent("CANCEL_LOOT_ROLL")
        f:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
        f:RegisterEvent("CONFIRM_LOOT_ROLL")
        f:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
        f:RegisterEvent("GARRISON_MISSION_BONUS_ROLL_LOOT")
        f:RegisterEvent("ITEM_PUSH")
        f:RegisterEvent("LOOT_BIND_CONFIRM")
        f:RegisterEvent("LOOT_CLOSED")
        f:RegisterEvent("LOOT_ITEM_AVAILABLE")
        f:RegisterEvent("LOOT_ITEM_ROLL_WON")
        f:RegisterEvent("LOOT_OPENED")
        f:RegisterEvent("LOOT_READY")
        f:RegisterEvent("LOOT_ROLLS_COMPLETE")
        f:RegisterEvent("LOOT_SLOT_CHANGED")
        f:RegisterEvent("LOOT_SLOT_CLEARED")
        f:RegisterEvent("MAIN_SPEC_NEED_ROLL")
        f:RegisterEvent("OPEN_MASTER_LOOT_LIST")
        f:RegisterEvent("PET_BATTLE_LOOT_RECEIVED")
        f:RegisterEvent("QUEST_CURRENCY_LOOT_RECEIVED")
        f:RegisterEvent("QUEST_LOOT_RECEIVED")
        f:RegisterEvent("START_LOOT_ROLL")
        hooksecurefunc("LootSlot", function(...) print("LootSlot",...) end)
    end
end

function LootHandler:OnEvent(event, ...)
    if event == "LOOT_READY" then
        -- The engine fires two LOOT_READY events, one before and one
        -- after LOOT_OPENED.
        if not self.looting then
            self.looting = true
            local autoloot = ...
            -- The autoloot flag is (by all appearances) a signal that
            -- the game _will_ automatically take all loot, not that the
            -- loot frame _should_ automatically LootSlot() each slot,
            -- so we don't need to do anything more than hide the frame.
            if autoloot and WoWXIV_config["flytext_enable"] and WoWXIV_config["flytext_hide_autoloot"] then
                self.autolooted = true
                LootFrame:UnregisterEvent("LOOT_OPENED")
                -- FIXME: the top half of the frame sometimes appears anyway
                -- (presumably from LootFrame.NineSlice); why is this?
            end
        end
    elseif event == "LOOT_CLOSED" then
        if self.autolooted then
            LootFrame:RegisterEvent("LOOT_OPENED")
        end
        self.looting = false
        self.autolooted = false
    end
end

------------------------------------------------------------------------

-- Create the flying text manager.
function WoWXIV.FlyText.CreateManager()
    WoWXIV.FlyText.manager = FlyTextManager()
    WoWXIV.FlyText.loot_handler = LootHandler()
    WoWXIV.FlyText.Enable(WoWXIV_config["flytext_enable"])
end

-- Enable or disable flying text display.
function WoWXIV.FlyText.Enable(enable)
    if WoWXIV.FlyText.manager then
        WoWXIV.FlyText.manager:Enable(enable)
    end
end
