local _, WoWXIV = ...
WoWXIV.CombatLogManager = {}

local class = WoWXIV.class

local CLM = WoWXIV.CombatLogManager
local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo
local strsub = string.sub
local strfind = string.find

------------------------------------------------------------------------

-- Unit flags used in combat events.
CLM.UnitFlags = {}

-- Affiliation of the unit relative to the player:
CLM.UnitFlags.AFFILIATION_MASK     = 0x0000000F
CLM.UnitFlags.AFFILIATION_MINE     = 0x00000001
CLM.UnitFlags.AFFILIATION_PARTY    = 0x00000002
CLM.UnitFlags.AFFILIATION_RAID     = 0x00000004
CLM.UnitFlags.AFFILIATION_OUTSIDER = 0x00000008

-- Reaction (hostility) toward the player:
CLM.UnitFlags.REACTION_MASK        = 0x000000F0
CLM.UnitFlags.REACTION_FRIENDLY    = 0x00000010
CLM.UnitFlags.REACTION_NEUTRAL     = 0x00000020
CLM.UnitFlags.REACTION_HOSTILE     = 0x00000040

-- Controller (player-controlled or server-controlled):
CLM.UnitFlags.CONTROL_MASK         = 0x00000300
CLM.UnitFlags.CONTROL_PLAYER       = 0x00000100
CLM.UnitFlags.CONTROL_NPC          = 0x00000200

-- Type of unit:
CLM.UnitFlags.TYPE_MASK            = 0x0000FC00
CLM.UnitFlags.TYPE_PLAYER          = 0x00000400  -- Actual player, not NPC ally
CLM.UnitFlags.TYPE_NPC             = 0x00000800
CLM.UnitFlags.TYPE_PET             = 0x00001000  -- NPC under player control
CLM.UnitFlags.TYPE_GUARDIAN        = 0x00002000  -- NPC under server control
CLM.UnitFlags.TYPE_OBJECT          = 0x00004000  -- Non-character (traps, etc.)

-- Additional flags:
CLM.UnitFlags.TARGET               = 0x00010000  -- Current target of player
CLM.UnitFlags.FOCUS                = 0x00020000  -- Current focus target
CLM.UnitFlags.MAINTANK             = 0x00040000  -- Flagged as main tank
CLM.UnitFlags.MAINASSIST           = 0x00080000  -- Flagged as main assist

-- Flag indicating that no unit is present, used (for example) in the
-- source unit field for environmental damage:
CLM.UnitFlags.NONE                 = 0x80000000

------------------------------------------------------------------------

local CombatEvent = class()

function CombatEvent:__constructor(...)
    self.event = {...}
    self:ParseEvent()
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
        self.spell_id = nil
        self.spell_name = nil
        self.spell_school = 1  -- Physical
    elseif category == "RANGE" or category == "SPELL" then
        self.spell_id = event[argi]
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
        self.extra_spell_school = event[argi+2]
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

--------------------------------------------------------------------------

local Manager = {}
Manager.__index = Manager

-- CombatLogManager is a singleton, so we store its data in local variables
-- to reduce access time.

local Manager_frame = nil

-- Tables of registered handlers, mapping value (type/category/subtype) to
-- a subtable mapping object to handler for each registered object.  For
-- "all", the first level is omitted and the table is just a mapping from
-- objects to handlers.
local Manager_handlers_type = {}
local Manager_handlers_category = {}
local Manager_handlers_subtype = {}
local Manager_handlers_all = {}

local function Manager_OnEvent()
    local event = CombatEvent(CombatLogGetCurrentEventInfo())

    -- This may be premature optimization, but since measuring performance
    -- of a single addon can be a bit of a challenge, we assume it's worth
    -- the readability cost to unroll what could be a function call for
    -- each table type.
    local handlers
    handlers = Manager_handlers_type[event.type]
    if handlers then
        for object, func in pairs(handlers) do
            func(object, event)
        end
    end
    handlers = Manager_handlers_category[event.category]
    if handlers then
        for object, func in pairs(handlers) do
            func(object, event)
        end
    end
    handlers = (event.subtype ~= "" and Manager_handlers_subtype[event.subtype]
                or nil)
    if handlers then
        for object, func in pairs(handlers) do
            func(object, event)
        end
    end
    handlers = Manager_handlers_all
    for object, func in pairs(handlers) do
        func(object, event)
    end
end

function Manager.Start()
    local f = CreateFrame("Frame", "WoWXIV_CombatLogManager")
    Manager_frame = f
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:SetScript("OnEvent", Manager_OnEvent)
end

function Manager.Register(object, func, reg_type, reg_value)
    local function AddHandler(handler_map, key, object, func)
        handler_map[key] = handler_map[key] or {}
        handler_map[key][object] = func
    end
    if reg_type == "type" then
        AddHandler(Manager_handlers_type, reg_value, object, func)
    elseif reg_type == "category" then
        AddHandler(Manager_handlers_category, reg_value, object, func)
    elseif reg_type == "subtype" then
        AddHandler(Manager_handlers_subtype, reg_value, object, func)
    else
        assert(reg_type == nil)
        Manager_handlers_all[object] = func
    end
end

function Manager.Unregister(object)
    -- We assume unregistering will be a rare occurrence, so we don't
    -- bother trying to optimize reverse lookup by object.
    local function RemoveObject(handlers, object)
        if handlers[object] then
            handlers[object] = nil
        end
    end
    for _, handlers in pairs(Manager_handlers_type) do
        RemoveObject(handlers, object)
    end
    for _, handlers in pairs(Manager_handlers_category) do
        RemoveObject(handlers, object)
    end
    for _, handlers in pairs(Manager_handlers_subtype) do
        RemoveObject(handlers, object)
    end
    RemoveObject(Manager_handlers_all, object)
end

--------------------------------------------------------------------------

-- Create the combat log manager.  Called at addon initialization time.
function WoWXIV.CombatLogManager.Create()
    Manager.Start()
end

-- Register a function to be called for a specific combat event.  The
-- function |func| receives |object| as its first argument and a CombatEvent
-- table as the second argument.  CombatEvent contains the following fields:
--    timestamp (number): Event timestamp, based on Unix epoch (not GetTime())
--    type (string): Raw event type, e.g. "SPELL_DAMAGE"
--    category (string): Event category, e.g. "SPELL"
--    subtype (string): Event subtype, e.g. "DAMAGE"
--    hidden_source (boolean): Whether the source should be hidden from display
--    source (string): GUID of source unit (i.e., the unit causing the event)
--    source_name (string): Display name of source unit
--    source_flags (number): Bitmask of flags indicating source unit state
--        (see CombatLogManager.UnitFlags_*)
--    source_raid_flags (number): Bitmask of raid target flags for source unit
--        1<<0: raid target 1 (yellow star)
--        1<<1: raid target 2 (orange circle)
--        1<<2: raid target 3 (purple diamond)
--        1<<3: raid target 4 (green triangle)
--        1<<4: raid target 5 (silver moon)
--        1<<5: raid target 6 (blue square)
--        1<<6: raid target 7 (red cross)
--        1<<7: raid target 8 (white skull)
--    dest (string): GUID of target unit (unit to which event's effect applies)
--    dest_name (string): Display name of target unit
--    dest_flags (number): Bitmask of flags indicating target unit state
--    dest_raid_flags (number): Bitmask of raid target flags for target unit
--    spell_id (number): Spell ID (only for categories RANGE and SPELL)
--    spell_name (string): Spell name (only for categories RANGE, SPELL, and
--        ENCHANT)
--    spell_school (number): Spell school (only for categories RANGE and SPELL)
--    amount (number): General numeric amount (damage, heal, absorb, etc.).
--        For DAMAGE/HEAL, this includes any overkill or overheal amount
--        but does not include any absorbed amount
--    overkill (number): Amount of overkill damage (only for subtype DAMAGE)
--    overheal (number): Amount of overheal (only for subtype HEAL)
--    school (number): Elemental school of damage (only for subtype DAMAGE)
--    resisted (number): Amount of damage resisted (only for subtype DAMAGE)
--    blocked (number): Amount of damage blocked (only for subtype DAMAGE)
--    miss_type (string): Cause of a MISS event ("MISS", "ABSORB" etc.)
--        (only for subtype MISS)
--    failed_type (string): Cause of a FAILED event ("No target", etc.)
--        (only for subtype FAILED)
--    power_type (string): Type of power ("Mana" etc.) (only for subtype
--        ENERGIZE)
--    extra_amount (number): Additional numeric argument for subtype ENERGIZE
--        (possibly maximum value of relevant power type)
--    aura_type (string): Either "BUFF" or "DEBUFF" (for AURA_*, DISPEL, and
--        STOLEN subtypes)
--    extra_spell_id (number): Spell ID of interrupted action (for subtype
--        INTERRUPT) or relevant aura (for subtypes DISPEL, DISPEL_FAILED,
--        STOLEN, and AURA_BROKEN_SPELL)
--    extra_spell_name (string): Spell name for extra_spell_id
--    extra_spell_school (number): Spell school for extra_spell_id
--    item_id (number): Item ID of enchanted item (only for category ENCHANT)
--    item_name (number): Name of enchanted item (only for category ENCHANT)
--    env_type (string): Type of environmental damage (only for category
--        ENVIRONMENTAL)
function WoWXIV.CombatLogManager.RegisterEvent(object, func, type)
    Manager.Register(object, func, "type", type)
end

-- Register a function to be called for any event in the given category.
function WoWXIV.CombatLogManager.RegisterEventCategory(object, func, category)
    Manager.Register(object, func, "category", category)
end

-- Register a function to be called for any event of the given subtype.
function WoWXIV.CombatLogManager.RegisterEventSubtype(object, func, subtype)
    Manager.Register(object, func, "subtype", subtype)
end

-- Register a function to be called for all combat events.
function WoWXIV.CombatLogManager.RegisterAnyEvent(object, func)
    Manager.Register(object, func)
end

-- Unregister all registered handlers using the given object.
function WoWXIV.CombatLogManager.UnregisterAllEvents(object)
    Manager.Unregister(object)
end
