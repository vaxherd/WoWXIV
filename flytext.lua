local _, WoWXIV = ...
WoWXIV.FlyText = {}

local class = WoWXIV.class
local list = WoWXIV.list
local set = WoWXIV.set
local Frame = WoWXIV.Frame
local FramePool = WoWXIV.FramePool

local CLM = WoWXIV.CombatLogManager
local GetItemInfo = C_Item.GetItemInfo
local abs = math.abs
local max = math.max
local min = math.min
local random = math.random
local randrange = function(x) return x*(2*random()-1) end  -- random in [-x,+x)
local strfind = string.find
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub
local tinsert = tinsert

local typeof = type  -- Renamed so we can use "type" as an ordinary name.


-- Flying text behavior types.  Fields are:
--     time: Length of time the text is displayed (seconds).
--     dy: Movement per second on the Y axis.
--     x: Initial X position.
--     random: Maximum random adjustment to initial X and Y positions.
-- All position values are offset from the unit's notional origin (the
-- center of the screen for the player, the nameplate frame for other
-- units) and are scaled relative to the screen size.
local BEHAVIOR_DOWN = {time = 4.5, dy = -0.066, x = 0.05, random = 0}
local BEHAVIOR_HEAL = {time = 4.5, dy = -0.066, x = -0.01, random = 0}
local BEHAVIOR_UP   = {time = 2.0, dy = 0.066, x = 0.05, random = 0}
local BEHAVIOR_STAY = {time = 1.6, dy = 0, x = 0, random = 0.02}

-- Text colors used in flying text.
local COLOR_RED      = {1.000, 0.753, 0.761}
local COLOR_GREEN    = {0.929, 1.000, 0.906}
local COLOR_BLUE     = {0.790, 0.931, 0.970}
local COLOR_ORANGE   = {1.000, 0.882, 0.800}
local COLOR_LAVENDER = {0.792, 0.795, 0.871}  -- FIXME: for other->other damage (not yet implemented)
local COLOR_WHITE    = {1, 1, 1}
local COLOR_GRAY     = {0.7, 0.7, 0.7}

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

-- Color and behavior for each type, when attached to the player or to
-- another unit.
local FLYTEXT_INFO_PLAYER = {
    [FLYTEXT_DAMAGE_DIRECT]   = {BEHAVIOR_DOWN, COLOR_RED},
    [FLYTEXT_DAMAGE_PASSIVE]  = {BEHAVIOR_DOWN, COLOR_RED},
    [FLYTEXT_HEAL_DIRECT]     = {BEHAVIOR_HEAL, COLOR_GREEN},
    [FLYTEXT_HEAL_PASSIVE]    = {BEHAVIOR_HEAL, COLOR_GREEN},
    [FLYTEXT_BUFF_ADD]        = {BEHAVIOR_DOWN, COLOR_GREEN},
    [FLYTEXT_BUFF_REMOVE]     = {BEHAVIOR_DOWN, COLOR_GRAY},
    [FLYTEXT_DEBUFF_ADD]      = {BEHAVIOR_DOWN, COLOR_RED},
    [FLYTEXT_DEBUFF_REMOVE]   = {BEHAVIOR_DOWN, COLOR_GRAY},
    [FLYTEXT_LOOT_MONEY]      = {BEHAVIOR_DOWN, COLOR_WHITE},
    [FLYTEXT_LOOT_ITEM]       = {BEHAVIOR_DOWN, COLOR_WHITE},
}
local FLYTEXT_INFO_OTHER = {
    [FLYTEXT_DAMAGE_DIRECT]   = {BEHAVIOR_UP,   COLOR_ORANGE},
    [FLYTEXT_DAMAGE_PASSIVE]  = {BEHAVIOR_STAY, COLOR_RED},
    [FLYTEXT_HEAL_DIRECT]     = {BEHAVIOR_STAY, COLOR_GREEN},
    [FLYTEXT_HEAL_PASSIVE]    = {BEHAVIOR_STAY, COLOR_GREEN},
    [FLYTEXT_BUFF_ADD]        = {BEHAVIOR_STAY, COLOR_GREEN},
    [FLYTEXT_BUFF_REMOVE]     = {BEHAVIOR_STAY, COLOR_GRAY},
    [FLYTEXT_DEBUFF_ADD]      = {BEHAVIOR_UP,   COLOR_ORANGE},
    [FLYTEXT_DEBUFF_REMOVE]   = {BEHAVIOR_STAY, COLOR_GRAY},
    -- Loot types are not used for non-player units.
}

-- Minimum spacing between consecutive instances of scrolling text
-- (as a fraction of screen height).
local FLYTEXT_MIN_SPACING = 0.015

------------------------------------------------------------------------

local FlyText = class(Frame)

function FlyText:__allocator()
    return __super("Frame", nil, UIParent)
end

function FlyText:__constructor()
    self:SetFrameStrata("BACKGROUND")

    local name = self:CreateFontString(nil, "ARTWORK")
    self.name = name
    name:SetPoint("RIGHT", self, "CENTER")
    WoWXIV.SetFont(name, "FLYTEXT_DEFAULT")

    local icon = self:CreateTexture(nil, "ARTWORK")
    self.icon = icon
    icon:SetPoint("LEFT", self, "CENTER")

    local value = self:CreateFontString(nil, "ARTWORK")
    self.value = value
    value:SetPoint("LEFT", icon, "RIGHT")
    WoWXIV.SetFont(value, "FLYTEXT_DAMAGE")

    -- Use a separate text instance with an alternate font ID for the
    -- "!" critical indicator because it looks too much like a "1" in
    -- the game font.
    local exclam = self:CreateFontString(nil, "ARTWORK")
    self.exclam = exclam
    WoWXIV.SetFont(exclam, "FLYTEXT_EXCLAM")
    local exclam_font = exclam:GetFont()
    exclam:SetPoint("LEFT", value, "RIGHT")
    -- If this font is different from the value font, assume it's an
    -- explicit italic font; otherwise, apply a slight rotation to
    -- help differentiate the character from a "1".
    if exclam_font == value:GetFont() then
        exclam:SetRotation(math.rad(-10))
    end
    exclam:SetText("!")
    exclam:Hide()

    local border = self:CreateTexture(nil, "OVERLAY")
    self.border = border
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, 1)
    border:Hide()

    local stacks = self:CreateFontString(nil, "OVERLAY")
    self.stacks = stacks
    stacks:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 2)
    WoWXIV.SetFont(stacks, "AURA_STACKS")
    stacks:Hide()
end

-- Invariants on acquisition: name/icon/value are shown; value font is
-- set to FLYTEXT_DAMAGE; other elements are hidden; contents of all
-- elements are unspecified.
function FlyText:OnAcquire()
    self.name:Show()
    self.icon:Show()
    WoWXIV.SetFont(self.value, "FLYTEXT_DAMAGE")
    self.value:Show()
    self.exclam:Hide()
    self.border:Hide()
    self.stacks:Hide()
end

-- Initialize a newly acquired FlyText instance.  |unit| gives the target
-- unit with which the flying text is associated.  Additional arguments
-- vary by type:
--     - Direct damage/heal: spell_id, school, amount, is_crit
--     - Passive damage/heal: amount
--     - Buff/debuff: spell_id, school, stacks
--     - Loot money: amount
--     - Loot item: item_icon, item_name, name_color, count [default 1]
function FlyText:Init(type, unit, ...)
    self.start = GetTime()
    self.tag = nil
    self.type = type
    self.unit = unit
    if type == FLYTEXT_DAMAGE_PASSIVE or type == FLYTEXT_HEAL_PASSIVE then
        self.amount = ...
    elseif type >= FLYTEXT_DAMAGE_DIRECT and type <= FLYTEXT_DEBUFF_REMOVE then
        self.spell_id, self.school, self.amount, self.is_crit = ...
    elseif type == FLYTEXT_LOOT_MONEY then
        self.amount = ...
    elseif type == FLYTEXT_LOOT_ITEM then
        self.item_icon, self.item_name, self.item_quality_or_color,
            self.amount = ...
    else
        error("Invalid type: "..tostring(type))
    end

    local info_table = (self.unit == "player"
                        and FLYTEXT_INFO_PLAYER or FLYTEXT_INFO_OTHER)
    local behavior, colors = unpack(info_table[type])
    self.time = behavior.time
    self.dy = behavior.dy * UIParent:GetHeight()
    self.x = (behavior.x + randrange(behavior.random)) * UIParent:GetWidth()
    self.y = randrange(behavior.random) * UIParent:GetHeight()

    if self.unit == "player" then
        self.nameplate = nil
    else
        -- Because we can't get the screen position of a unit directly,
        -- we have to position text relative to its nameplate.  If the
        -- unit has no associated (or perhaps no visible) nameplate, we
        -- thus can't do anything, so discard the event.
        self.nameplate = C_NamePlate.GetNamePlateForUnit(self.unit)
        if not self.nameplate then
            self.type = nil
            return
        end
    end

    self:ClearAllPoints()
    self:SetPoint("CENTER", self.nameplate, "CENTER", self.x, self.y)
    self:SetSize(100, 20)  -- Arbitrary, but required in order to be rendered.
    self:SetAlpha(0)

    local name = self.name
    local icon = self.icon
    local value = self.value
    local r, g, b = unpack(colors)
    name:SetTextColor(r, g, b)
    value:SetTextColor(r, g, b)

    if type == FLYTEXT_DAMAGE_DIRECT or type == FLYTEXT_HEAL_DIRECT then
        local spell_info = (self.spell_id
                            and C_Spell.GetSpellInfo(self.spell_id) or nil)
        if spell_info and spell_info.name then
            name:SetText(spell_info.name)
        else
            name:Hide()
        end
        if false then
            -- FIXME: set magic school icon
        else
            icon:Hide()
            value:ClearAllPoints()
            value:SetPoint("LEFT", self, "CENTER", 10, 0)
        end
        local amount = self.amount
        if not amount then
            WoWXIV.SetFont(value, "FLYTEXT_MISS")
            amount = "Miss"
        elseif self.is_crit then
            WoWXIV.SetFont(value, "FLYTEXT_CRIT")
            local exclam = self.exclam
            exclam:SetTextColor(r, g, b)
            exclam:Show()
        end
        value:SetText(amount)

    elseif type == FLYTEXT_DAMAGE_PASSIVE or type == FLYTEXT_HEAL_PASSIVE then
        name:Hide()
        icon:Hide()
        value:ClearAllPoints()
        value:SetPoint("LEFT", self, "CENTER", 10, 0)
        value:SetText(self.amount)

    elseif type >= FLYTEXT_BUFF_ADD and type <= FLYTEXT_DEBUFF_REMOVE then
        WoWXIV.SetFont(value, "FLYTEXT_DEFAULT")
        name:Hide()
        local spell_info = C_Spell.GetSpellInfo(self.spell_id)
        icon:SetSize(24, 24)
        local border = self.border
        border:SetSize(22, 26)
        if type == FLYTEXT_BUFF_ADD or type == FLYTEXT_BUFF_REMOVE then
            icon:SetMask(WoWXIV.makepath("textures/buff-mask.png"))
            WoWXIV.SetUITexture(border, 99, 121, 14, 40)
        else
            icon:SetMask(WoWXIV.makepath("textures/debuff-mask.png"))
            WoWXIV.SetUITexture(border, 99, 121, 40, 14)
        end
        icon:SetTexture(spell_info.iconID)
        if self.amount and self.amount > 0 then
            local stacks = self.stacks
            stacks:Show()
            stacks:SetText(self.amount)
        end
        value:ClearAllPoints()
        value:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        WoWXIV.SetFont(value, "FLYTEXT_DEFAULT")
        if type == FLYTEXT_BUFF_ADD or type == FLYTEXT_DEBUFF_ADD then
            value:SetText("+" .. spell_info.name)
        else
            value:SetText("-" .. spell_info.name)
        end

    elseif type == FLYTEXT_LOOT_MONEY then
        name:Hide()
        icon:Hide()
        value:ClearAllPoints()
        value:SetPoint("LEFT", self, "CENTER")
        WoWXIV.SetFont(value, "FLYTEXT_DEFAULT")
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
        local quality_or_color = self.item_quality_or_color
        local text
        if typeof(quality_or_color) == "number" then
            text = WoWXIV.FormatItemColor(self.item_name, quality_or_color)
        else
            text = WoWXIV.FormatColoredText(self.item_name, quality_or_color)
        end
        if self.amount and self.amount > 1 then
            text = text .. "×" .. self.amount
        end
        value:ClearAllPoints()
        value:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        WoWXIV.SetFont(value, "FLYTEXT_DEFAULT")
        value:SetTextColor(unpack(COLOR_BLUE))
        value:SetText(text)

    else
        error("unreachable")
    end
end

-- Returns true if text is still displayed, false if it has disappeared.
function FlyText:OnUpdate()
    if not self.type then
        return false
    end

    -- Check for expiration.
    local now = GetTime()
    local t = now - self.start
    local left = (self.time - t) / self.time
    if left <= 0 then
        self.type = nil
        return false
    end

    -- Apply scrolling over time.
    if self.dy ~= 0 then
        self:SetPointsOffset(self.x, self.y + self.dy*t)
    end

    -- Handle fade-in/out.
    if self.dy == 0 then
        -- In FFXIV, these animate in one digit at a time (every 0.1 sec),
        -- with each digit fading over ~0.02 sec and bouncing up slightly.
        -- That's a bit more effort than it's worth, so we just fade the
        -- whole string in at once.  (FIXME: maybe get around to it?)
        local alpha
        if t < 0.1 then
            alpha = t/0.1
        elseif left < 0.1 then
            alpha = left/0.1
        else
            alpha = 1
        end
        self:SetAlpha(max(0, alpha-0.25))
    else
        -- FFXIV applies a "whitening" effect during the fade-in which we
        -- can't replicate in the WoW engine, so we just do a regular
        -- alpha fade.
        local alpha
        if t < 0.1 then
            self:SetAlpha(t/0.1)
        elseif left > 1/3 then
            self:SetAlpha(1)
        else
            self:SetAlpha(left/(1/3))
        end
    end

    -- Handle the "bounce" scaling for player critical hits.
    if self.dy ~= 0 and self.is_crit then
        if t < 0.01 then
            self:SetScale(0.9)
        elseif t < 0.1 then
            self:SetScale(0.9 + (t - 0.01)/0.09 * 0.2)
        elseif t < 0.125 then
            self:SetScale(1.1 - (t - 0.1)/0.025 * 0.1)
        else
            self:SetScale(1.0)
        end
    end

    return true
end

-- Return the unit with which this instance is associated.
function FlyText:GetUnit()
    return self.unit
end

-- Set a tag on the instance, which can be retrieved with GetTag().
function FlyText:SetTag(tag)
    self.tag = tag
end

-- Return the tag set on this instance with SetTag(), or nil if no tag
-- has been set since the instance was acquired.
function FlyText:GetTag()
    return self.tag
end

-- Return the distance this instance has scrolled since it was created.
function FlyText:GetScrollDistance()
    return abs(self.y)  -- Base Y for scrolling text is currently always 0.
end

-- Push scrolling text by the given distance in its scroll direction.
function FlyText:Push(dy)
    if self.dy < 0 then
        self.y = self.y - dy
    elseif self.dy > 0 then
        self.y = self.y + dy
    end
end

------------------------------------------------------------------------

local FlyTextManager = class(Frame)

function FlyTextManager:__allocator()
    return __super("Frame", "WoWXIV_FlyTextManager", nil)
end

function FlyTextManager:__constructor()
    self.enabled = true
    self.pool = FramePool(FlyText)
    self.dot = {}
    self.hot = {}
    self.zone_entered = 0
    self.last_money = GetMoney()
    self.last_item_icon = nil
    self.last_aura_set = nil
    self.last_currency = nil

    self.eventmap = {
        CHAT_MSG_LOOT = FlyTextManager.OnLootItem,
        CURRENCY_DISPLAY_UPDATE = FlyTextManager.OnCurrencyUpdate,
        PLAYER_MONEY = FlyTextManager.OnPlayerMoney,
        -- Suppress aura events for the first 0.5 sec after entering a zone
        -- to avoid spam from permanent buffs (which are reapplied on
        -- entering each self zone).
        PLAYER_ENTERING_WORLD = FlyTextManager.OnEnterZone,
    }
    self:SetScript("OnEvent", function(frame, event, ...)
        local handler = frame.eventmap[event]
        if handler then handler(self, event, ...) end
    end)
    self:SetScript("OnUpdate", function() self:OnUpdate() end)
end

function FlyTextManager:NewText(...)
    local instance = self.pool:Acquire()
    instance:Init(...)
    return instance
end

function FlyTextManager:Enable(enable)
    self.enabled = enable
    if enable then
        for event, _ in pairs(self.eventmap) do
            self:RegisterEvent(event)
        end
        CLM.RegisterAnyEvent(self, self.OnCombatLogEvent)
    else
        self:UnregisterAllEvents()
        CLM.UnregisterAllEvents(self)
    end
end

function FlyTextManager:OnEnterZone()
    self.zone_entered = GetTime()
    self.last_money = GetMoney()
end

function FlyTextManager:OnCombatLogEvent(event)
    if GetTime() < self.zone_entered + 0.5 and strsub(event.subtype, 1, 5) == "AURA_" then
        return  -- Suppress aura spam on entering a zone.
    end

    -- Determine which unit this event belongs to.
    local source = event.source
    local dest = event.dest
    local unit
    if dest == UnitGUID("player") or (UnitInVehicle("player")
                                      and dest == UnitGUID("vehicle")) then
        -- If the player is in a vehicle and the event targets the vehicle,
        -- we treat that as player text.  Note that this can cause
        -- surprising effects if the player is grabbed by a boss, because
        -- the boss is then treated as a "vehicle" and the player will see
        -- all the boss damage events as their own.
        -- (FIXME: find a workaround?)
        unit = "player"
    else
        -- For events affecting other units, we only draw text if the
        -- event was initiated by the player.  (FIXME: consider also
        -- "ally -> in-combat enemy" and "any -> ally")
        if source == UnitGUID("player") then
            unit = UnitTokenFromGUID(dest)
        end
        if not unit then
            return  -- Filtered, or unit has no associated token.
        end
    end

    local args = nil
    local is_aura = false
    if event.subtype == "DAMAGE" then
        args = {FLYTEXT_DAMAGE_DIRECT, unit, event.spell_id,
                event.spell_school, event.amount, event.critical}
    elseif event.subtype == "PERIODIC_DAMAGE" then
        self.dot = self.dot or {}
        self.dot[unit] = (self.dot[unit] or 0) + event.amount
    elseif event.subtype == "MISSED" then
        -- Note that absorbed heals are reported as "heal for 0" with the
        -- amount absorbed in event.absorbed, so we don't have to worry
        -- about separating them out here to get our desired behavior.
        args = {FLYTEXT_DAMAGE_DIRECT, unit, event.spell_id,
                event.spell_school, event.amount and 0 or nil}
    elseif event.subtype == "HEAL" then
        args = {FLYTEXT_HEAL_DIRECT, unit, event.spell_id,
                event.spell_school, event.amount, event.critical}
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
    if not is_aura and self.last_aura_set then
        for aura_args in self.last_aura_set do
            self:AddText(aura_args)
        end
        self.last_aura_set = nil
    end
    if args then
        self:AddText(args)
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
function FlyTextManager:DoAura(type, unit, spell_id, ...)
    local args = {type, unit, spell_id, ...}
    local last = self.last_aura_set
    local filter_this = false
    if last then
        for last_args in last do
            if last_args[2] == unit and last_args[3] == spell_id then
                local filter_last = false
                if last_args[1] == FLYTEXT_BUFF_REMOVE and type == FLYTEXT_BUFF_ADD then
                    filter_last = true
                    filter_this = true
                elseif last_args[1] == FLYTEXT_BUFF_ADD and type == FLYTEXT_BUFF_ADD then
                    filter_last = true
                end
                if filter_last then
                    last:remove(last_args)
                end
                break
            end
        end
    end
    if not filter_this then
        if not last then last = set() end
        last:add(args)
    end
    self.last_aura_set = last
end

-- Returns: type, id, quality_or_color, count [, name]
-- quality_or_color is a number (item quality) or string (hex RRGGBB).
local function ParseLootMsg(msg)
    local color = strstr(msg, "|c")
    if color then
        if strsub(msg, color+2, color+4) == "nIQ" then
            local colon = strstr(msg, ":", color)
            if colon then
                color = tonumber(strsub(msg, color+5, colon-1))
                if color == nil then
                    -- These fallback color codes are all approximately
                    -- white, but they also indicate where a problem
                    -- occurred without throwing up an error dialog.
                    color = "fffffe"
                end
            else
                color = "fffeff"
            end
        else
            color = strsub(msg, color+4, color+9)
        end
    else
        color = "feffff"
    end
    local link = strstr(msg, "|H")
    if link then
        local colon1 = strstr(msg, ":", link+2)
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
        self:AddText({FLYTEXT_LOOT_ITEM, "player", icon, name, color, count})
    end
end

-- For duplicate currency event check (see below).
local CURRENCY_PAIRS = list(
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
    {3284, 3285},  -- Weathered Ethereal Crest
    {3286, 3287},  -- Carved Ethereal Crest
    {3288, 3289},  -- Runed Ethereal Crest
    {3290, 3291},  -- Gilded Ethereal Crest
    {3252, 3372}   -- Bronze (Legion Remix)
)
local CURRENCY_PAIR_MAP = {}
for pair in CURRENCY_PAIRS do
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

    self:AddText({FLYTEXT_LOOT_ITEM, "player",
                  info.iconFileID, name, info.quality, change})
    if CURRENCY_PAIR_MAP[id] then
        self.last_currency = {id, change}
    end
end

function FlyTextManager:OnPlayerMoney()
    local money = GetMoney()
    local diff = money - self.last_money
    self.last_money = money
    if diff > 0 then
        self:AddText({FLYTEXT_LOOT_MONEY, "player", diff})
    end
end

function FlyTextManager:AddText(args)
    -- For scrolling text, if we have events in rapid sequence on the same
    -- target, push preceding events away to avoid overlap.
    local type, unit = unpack(args)
    local behavior, tag
    if unit == "player" then
        behavior = FLYTEXT_INFO_PLAYER[type][1]
        if behavior.x < 0 then
            tag = "player_left"
        else
            tag = "player_right"
        end
    else
        behavior = FLYTEXT_INFO_OTHER[type][1]
        tag = unit
    end
    if behavior.dy ~= 0 then
        local min_spacing = UIParent:GetHeight() * FLYTEXT_MIN_SPACING
        local min_scroll = min_spacing
        for text in self.pool do
            if text:GetTag() == tag then
                min_scroll = min(min_scroll, text:GetScrollDistance())
            end
        end
        if min_scroll < min_spacing then
            local dy = min_spacing - min_scroll
            for text in self.pool do
                -- For player events (which are split into two columns),
                -- if either column has to be pushed, we push both to
                -- maintain visual consistency.
                if text:GetUnit() == unit then
                    text:Push(dy)
                end
            end
        end
    end

    local text = self:NewText(unpack(args))
    text:SetTag(tag)
    -- We don't need to save the instance separately; we only reference it
    -- via pool iteration.
end

function FlyTextManager:OnUpdate()
    if self.last_aura_set then
        for aura_args in self.last_aura_set do
            self:AddText(aura_args)
        end
        self.last_aura_set = nil
    end

    if self.dot then
        for unit, amount in pairs(self.dot) do
            self:AddText({FLYTEXT_DAMAGE_PASSIVE, unit, amount})
        end
        self.dot = nil
    end

    if self.hot then
        for unit, amount in pairs(self.hot) do
            self:AddText({FLYTEXT_HEAL_PASSIVE, unit, amount})
        end
        self.hot = nil
    end

    for text in self.pool do
        if not text:OnUpdate() then
            self.pool:Release(text)
        end
    end
end

------------------------------------------------------------------------

local LootHandler = class(Frame)

function LootHandler:__allocator()
    return __super("Frame", "WoWXIV_LootHandler", nil)
end

function LootHandler:__constructor()
    -- Is a loot operation in progress?
    self.looting = false
    -- Is the loot operation an autoloot (whether bugged or not?)
    self.autolooting = false
    -- State of each loot slot in the active loot operation, used with
    -- manual autolooting.  Values of each array entry:
    --    0: loot collected, slot is empty
    --    1: loot available, not yet manually looted with LootSlot()
    --    2: loot available, LootSlot() already performed
    self.loot_slots = nil

    self:Hide()
    self:SetScript("OnEvent", self.OnEvent)
    self:RegisterEvent("LOOT_READY")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("LOOT_SLOT_CHANGED")
    self:RegisterEvent("LOOT_SLOT_CLEARED")

    EventRegistry:RegisterCallback(
        "WoWXIV.AutolootFixTriggered",
        function(_, type)
            WoWXIV.LogWindow.AddMessage("WOWXIV_DEBUG",
                                        "*** Autoloot fix "..type)
        end)
end

function LootHandler:OnEvent(event, ...)
    local hide_autoloot = (WoWXIV_config["flytext_enable"]
                           and WoWXIV_config["flytext_hide_autoloot"])

    if event == "LOOT_READY" then
        local autoloot = ...
        -- The engine fires two LOOT_READY events, one before and one
        -- after LOOT_OPENED.
        if not self.looting then
            self.looting = true
            -- The autoloot flag is (by all appearances) a signal that
            -- the game _will_ automatically take all loot, not that the
            -- loot frame _should_ automatically LootSlot() each slot,
            -- so we don't need to do anything more than hide the frame
            -- if the corresponding setting is enabled.
            if autoloot then
                self.autolooting = true
                if hide_autoloot then
                    LootFrame:UnregisterEvent("LOOT_OPENED")
                end
                self:UpdateLootSlots()
            end
        else  -- second (or later) LOOT_READY event
            -- There is (since at least 11.0, still present in 11.2.0) a
            -- bug in the engine which seems to "forget" the autoloot state
            -- in certain cases, possibly when a loot item is added to the
            -- table after the first LOOT_READY but before LOOT_OPENED (or
            -- perhaps "before the processing which generates LOOT_OPENED
            -- completes", since the erroneous LOOT_READY can also follow
            -- LOOT_OPENED).  We can detect that here by comparing against
            -- the original autoloot flag; if the bug occurs, we work
            -- around it by performing the autoloot operation ourselves.
            if self.autolooting and not autoloot then
                EventRegistry:TriggerEvent("WoWXIV.AutolootFixTriggered", 1)
                self:UpdateLootSlots()  -- Add any new slots.
                self:DoManualAutoloot()
            end
        end

    elseif event == "LOOT_OPENED" then
        local autoloot = ...
        -- On rare occasions, we can get LOOT_OPENED _without_ LOOT_READY;
        -- this has been observed in delves when opening a reward chest,
        -- though there doesn't seem to be any consistency of conditions
        -- for when it occurs.  In this case, we seem to correctly get
        -- autoloot=true for the autoloot case, but the game doesn't
        -- actually perform looting, so we treat it the same as the "lost
        -- autoloot flag" case above and loot manually, trusting that if
        -- the game does decide to autoloot (or this bug is fixed), it can
        -- properly resolve our manual LootSlot() calls with the autoloot
        -- processing.
        if not self.looting then
            self.looting = true
            if autoloot then
                self.autolooting = true
                if hide_autoloot then
                    LootFrame:UnregisterEvent("LOOT_OPENED")
                    LootFrame:Hide()  -- In case it saw this event before us.
                end
                EventRegistry:TriggerEvent("WoWXIV.AutolootFixTriggered", 2)
                self:UpdateLootSlots()
                self:DoManualAutoloot()
            end
        else
            -- In yet another failure mode (though possibly one provoked
            -- by our LOOT_READY autoloot fix), we can receive LOOT_OPENED
            -- well after a manual autoloot indicating that some items
            -- were not successfully looted, which has been observed when
            -- looting a very large number of corpses at once.  We treat
            -- this as equivalent to a LOOT_READY and perform another
            -- manual autoloot pass.
            if self.autolooting and not autoloot then
                EventRegistry:TriggerEvent("WoWXIV.AutolootFixTriggered", 3)
                self:UpdateLootSlots()
                self:DoManualAutoloot()
            end
        end

    elseif event == "LOOT_SLOT_CHANGED" then
        local slot = ...
        -- It's not clear that we need to worry about this, but we
        -- include it anyway for completeness.
        if self.loot_slots then
            self.loot_slots[slot] = 1
        end

    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        if self.loot_slots then
            self.loot_slots[slot] = 0
        end

    elseif event == "LOOT_CLOSED" then
        if self.autolooting then
            LootFrame:RegisterEvent("LOOT_OPENED")
        end
        self.looting = false
        self.autolooting = false
        self.loot_slots = nil
    end
end

function LootHandler:UpdateLootSlots()
    local slots = self.loot_slots or {}
    -- Preserve any 0 entries (indicating cleared slots with no subsequent
    -- changes), but force any 2 entries to 1 on the assumption that the
    -- event indicates there's uncollected loot there (confirmed to be
    -- necessary in 11.1.7: LOOT_READY(num=4) -> LootSlot(4) -> no events
    -- for slot 4 -> LOOT_OPENED(num=4) with loot remaining in slot 4).
    self.loot_slots = WoWXIV.maptn(
        function(i) return min(slots[i] or 1, 1) end, GetNumLootItems())
end

function LootHandler:DoManualAutoloot(event, ...)
    -- This behavior is slightly different from native autoloot in that
    -- it loots everything instantly rather than inserting a small delay
    -- between each item.  We don't worry about that for the moment.
    local slots = self.loot_slots
    for i = 1, #slots do
        if slots[i] == 1 then
            LootSlot(i)
            slots[i] = 2
        end
    end
end

-- For debugging / game behavior analysis:
if false then
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(frame, event, ...)
        if event == "LOOT_READY" or event == "LOOT_OPENED" then
            event = event.." num="..GetNumLootItems()
        end
        print(event, ...)
    end)
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

-- Test all flying text types.  Non-player flying text require a unit with
-- a nameplate to be targeted.
function WoWXIV.FlyText.Test()
    local combat_texts = list(
        {FLYTEXT_DAMAGE_DIRECT, nil, 1, 12345, false},
        {FLYTEXT_DAMAGE_DIRECT, 585, 2, 56789, true},
        {FLYTEXT_DAMAGE_PASSIVE, 1234},
        {FLYTEXT_HEAL_DIRECT, 439, 2, 23456, false},
        {FLYTEXT_HEAL_DIRECT, 2061, 2, 45678, true},
        {FLYTEXT_HEAL_PASSIVE, 4321},
        {FLYTEXT_BUFF_ADD, 17, 2},
        {FLYTEXT_BUFF_REMOVE, 17, 2},
        {FLYTEXT_DEBUFF_ADD, 246, 32, 1},
        {FLYTEXT_DEBUFF_ADD, 246, 32, 2},
        {FLYTEXT_DEBUFF_ADD, 246, 32, 3},
        {FLYTEXT_DEBUFF_REMOVE, 246, 32}
    )
    local loot_texts = list(
        {FLYTEXT_LOOT_MONEY, 123456789},
        {FLYTEXT_LOOT_ITEM, 134414, "Hearthstone", 1, 999}
    )

    for args in combat_texts do
        WoWXIV.FlyText.manager:AddText({args[1], "player",
                                        select(2, unpack(args))})
    end
    for args in loot_texts do
        WoWXIV.FlyText.manager:AddText({args[1], "player",
                                        select(2, unpack(args))})
    end

    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    if nameplate then
        for args in combat_texts do
            WoWXIV.FlyText.manager:AddText({args[1], "target",
                                            select(2, unpack(args))})
        end
    end
end
