local _, WoWXIV = ...
WoWXIV.LogWindow = {}

local class = WoWXIV.class
local Frame = WoWXIV.Frame

-- FIXME: temp for Midnight
local ChatFrame_ConfigEventHandler =
    ChatFrame_ConfigEventHandler or ChatFrameMixin.ConfigEventHandler
local ChatFrame_RegisterForChannels =
    ChatFrame_RegisterForChannels or ChatFrameMixin.RegisterForChannels
local ChatFrame_MessageEventHandler =
    ChatFrame_MessageEventHandler or ChatFrameMixin.MessageEventHandler
local ChatFrame_SystemEventHandler =
    ChatFrame_SystemEventHandler or ChatFrameMixin.SystemEventHandler

local CLM = WoWXIV.CombatLogManager
local band = bit.band
local bor = bit.bor
local strfind = string.find
local strgsub = string.gsub
local strlower = string.lower
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub
local tinsert = tinsert

local AFFILIATION_MINE = CLM.UnitFlags.AFFILIATION_MINE
local AFFILIATION_PARTY_OR_RAID = bor(CLM.UnitFlags.AFFILIATION_PARTY,
                                      CLM.UnitFlags.AFFILIATION_RAID)
local AFFILIATION_ALLY = bor(CLM.UnitFlags.AFFILIATION_MINE,
                             AFFILIATION_PARTY_OR_RAID)
local CONTROL_NPC = CLM.UnitFlags.CONTROL_NPC
local REACTION_HOSTILE = CLM.UnitFlags.REACTION_HOSTILE
local TYPE_PLAYER = CLM.UnitFlags.TYPE_PLAYER
local TYPE_PET = CLM.UnitFlags.TYPE_PET
local TYPE_OBJECT = CLM.UnitFlags.TYPE_OBJECT

-- Mapping from logical event types (as passed to the Tab constructor) to
-- raw event names.  This is similar to, though orgainzed differently than,
-- the ChatTypeGroup mapping in Blizzard's ChatFrameBase module.
local MESSAGE_TYPES = {

    -------- Non-combat messages (event names are WoW events)

    System = {"CHAT_MSG_SYSTEM",
              "-",
              "CHARACTER_POINTS_CHANGED",
              "DISPLAY_EVENT_TOAST_LINK",
              "GUILD_MOTD",
              "PLAYER_LEVEL_CHANGED",
              "PLAYER_REPORT_SUBMITTED",
              "TIME_PLAYED_MSG",
              "UNIT_LEVEL",
              "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE"},

    Error = {"CHAT_MSG_RESTRICTED",
             "CHAT_MSG_FILTERED"},

    Ping = {"CHAT_MSG_PING"},

    Channel = {"CHAT_MSG_CHANNEL_JOIN",
               "CHAT_MSG_CHANNEL_LEAVE",
               "CHAT_MSG_CHANNEL_NOTICE",
               "CHAT_MSG_CHANNEL_NOTICE_USER",
               "CHAT_MSG_CHANNEL_LIST",
               "CHAT_MSG_COMMUNITIES_CHANNEL"},

    Chat_Channel = {"CHAT_MSG_CHANNEL"},

    Chat_Say = {"CHAT_MSG_SAY"},

    Chat_Emote = {"CHAT_MSG_EMOTE",
                  "CHAT_MSG_TEXT_EMOTE"},

    Chat_Yell = {"CHAT_MSG_YELL"},

    Chat_Whisper = {"CHAT_MSG_WHISPER",
                    "CHAT_MSG_WHISPER_INFORM",
                    "CHAT_MSG_AFK",
                    "CHAT_MSG_DND",
                    "CHAT_MSG_IGNORED"},

    Chat_NPC = {"CHAT_MSG_MONSTER_SAY",
                "CHAT_MSG_MONSTER_YELL",
                "CHAT_MSG_MONSTER_EMOTE",
                "CHAT_MSG_MONSTER_WHISPER",
                "CHAT_MSG_RAID_BOSS_EMOTE",
                "CHAT_MSG_RAID_BOSS_WHISPER"},

    Chat_Party = {"CHAT_MSG_PARTY",
                  "CHAT_MSG_PARTY_LEADER",
                  "CHAT_MSG_MONSTER_PARTY"},

    Chat_Raid = {"CHAT_MSG_RAID",
                 "CHAT_MSG_RAID_LEADER",
                 "CHAT_MSG_RAID_WARNING"},

    Chat_Instance = {"CHAT_MSG_INSTANCE_CHAT",
                     "CHAT_MSG_INSTANCE_CHAT_LEADER"},

    Chat_Guild = {"CHAT_MSG_GUILD"},

    Chat_GuildOfficer = {"CHAT_MSG_OFFICER"},

    BNWhisper = {"CHAT_MSG_BN_WHISPER",
                 "CHAT_MSG_BN_WHISPER_INFORM"},

    BNInlineToast = {"CHAT_MSG_BN_INLINE_TOAST_ALERT",
                     "CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
                     "CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM"},

    Combat_Reward = {"CHAT_MSG_COMBAT_XP_GAIN",
                     "CHAT_MSG_COMBAT_HONOR_GAIN"},

    Combat_Faction = {"CHAT_MSG_COMBAT_FACTION_CHANGE"},

    Combat_Misc = {"CHAT_MSG_COMBAT_MISC_INFO"},

    TargetIcon = {"CHAT_MSG_TARGETICONS"},

    BG_Alliance = {"CHAT_MSG_BG_SYSTEM_ALLIANCE"},

    BG_Horde = {"CHAT_MSG_BG_SYSTEM_HORDE"},

    BG_Neutral = {"CHAT_MSG_BG_SYSTEM_NEUTRAL"},

    Skill = {"CHAT_MSG_SKILL"},

    Loot = {"CHAT_MSG_LOOT",
            "CHAT_MSG_CURRENCY",
            "CHAT_MSG_MONEY"},

    Gathering = {"CHAT_MSG_OPENING"},

    TradeSkill = {"CHAT_MSG_TRADESKILLS"},

    PetInfo = {"CHAT_MSG_PET_INFO"},

    Achievement = {"CHAT_MSG_ACHIEVEMENT"},

    Guild = {"GUILD_MOTD"},

    Guild_Achievement = {"CHAT_MSG_GUILD_ACHIEVEMENT",
                         "CHAT_MSG_GUILD_ITEM_LOOTED"},

    PetBattle = {"CHAT_MSG_PET_BATTLE_COMBAT_LOG",
                 "CHAT_MSG_PET_BATTLE_INFO"},

    VoiceText = {"CHAT_MSG_VOICE_TEXT"},

    Debug = {"WOWXIV_DEBUG"},

    -------- Combat messages
    -- Event ID format: "CLM_<event>.<source>:<target>"
    -- <event> is the combat event name (e.g. "SPELL_DAMAGE")
    -- <source> is the event source, one of:
    --    - "*" (any target)
    --    - "self" (the current player)
    --    - "enemy" (an enemy engaged in combat with the player)
    --    - "party" (another player in the same party or raid)
    --    - "pet" (a pet under self or party control)
    --    - "npc" (an allied character under server control)
    --    - "object" (non-character objects such as traps)
    --    - "env" (environmental effects)
    -- <target> is the event target, as above (except for no "env").
    -- A trailing ":*" or ".*:*" may be omitted.

    Combat_Attack_Self = {"CLM_SWING_DAMAGE.self",
                          "CLM_SWING_MISSED.self",
                          "CLM_RANGE_DAMAGE.self",
                          "CLM_RANGE_MISSED.self",
                          "CLM_SPELL_DAMAGE.self",
                          "CLM_SPELL_MISSED.self",
                          "CLM_SPELL_DRAIN.self",
                          "CLM_SPELL_LEECH.self",
                          "CLM_SPELL_BUILDING_DAMAGE.self",
                          "CLM_SPELL_INSTAKILL.self"},


    Combat_Attack_ToSelf = {"CLM_SWING_DAMAGE.*:self",
                            "CLM_SWING_MISSED.*:self",
                            "CLM_RANGE_DAMAGE.*:self",
                            "CLM_RANGE_MISSED.*:self",
                            "CLM_SPELL_DAMAGE.*:self",
                            "CLM_SPELL_MISSED.*:self",
                            "CLM_SPELL_DRAIN.*:self",
                            "CLM_SPELL_LEECH.*:self",
                            "CLM_SPELL_INSTAKILL.*:self"},

    Combat_Attack_Party = {"CLM_SWING_DAMAGE.party",
                           "CLM_SWING_MISSED.party",
                           "CLM_RANGE_DAMAGE.party",
                           "CLM_RANGE_MISSED.party",
                           "CLM_SPELL_DAMAGE.party",
                           "CLM_SPELL_MISSED.party",
                           "CLM_SPELL_DRAIN.party",
                           "CLM_SPELL_LEECH.party",
                           "CLM_SPELL_BUILDING_DAMAGE.party",
                           "CLM_SPELL_INSTAKILL.party"},


    Combat_Attack_ToParty = {"CLM_SWING_DAMAGE.*:party",
                             "CLM_SWING_MISSED.*:party",
                             "CLM_RANGE_DAMAGE.*:party",
                             "CLM_RANGE_MISSED.*:party",
                             "CLM_SPELL_DAMAGE.*:party",
                             "CLM_SPELL_MISSED.*:party",
                             "CLM_SPELL_DRAIN.*:party",
                             "CLM_SPELL_LEECH.*:party",
                             "CLM_SPELL_INSTAKILL.*:party"},


    Combat_Attack_Pet = {"CLM_SWING_DAMAGE.pet",
                         "CLM_SWING_MISSED.pet",
                         "CLM_RANGE_DAMAGE.pet",
                         "CLM_RANGE_MISSED.pet",
                         "CLM_SPELL_DAMAGE.pet",
                         "CLM_SPELL_MISSED.pet",
                         "CLM_SPELL_DRAIN.pet",
                         "CLM_SPELL_LEECH.pet",
                         "CLM_SPELL_BUILDING_DAMAGE.pet",
                         "CLM_SPELL_INSTAKILL.pet"},

    Combat_Attack_ToPet = {"CLM_SWING_DAMAGE.*:pet",
                           "CLM_SWING_MISSED.*:pet",
                           "CLM_RANGE_DAMAGE.*:pet",
                           "CLM_RANGE_MISSED.*:pet",
                           "CLM_SPELL_DAMAGE.*:pet",
                           "CLM_SPELL_MISSED.*:pet",
                           "CLM_SPELL_DRAIN.*:pet",
                           "CLM_SPELL_LEECH.*:pet",
                           "CLM_SPELL_INSTAKILL.*:pet"},

    Combat_Attack_Enemy = {"CLM_SWING_DAMAGE:enemy",
                           "CLM_SWING_MISSED:enemy",
                           "CLM_RANGE_DAMAGE:enemy",
                           "CLM_RANGE_MISSED:enemy",
                           "CLM_SPELL_DAMAGE:enemy",
                           "CLM_SPELL_MISSED:enemy",
                           "CLM_SPELL_DRAIN:enemy",
                           "CLM_SPELL_LEECH:enemy",
                           "CLM_SPELL_INSTAKILL:enemy"},

    Combat_Attack_ToEnemy = {"CLM_SWING_DAMAGE.*:enemy",
                             "CLM_SWING_MISSED.*:enemy",
                             "CLM_RANGE_DAMAGE.*:enemy",
                             "CLM_RANGE_MISSED.*:enemy",
                             "CLM_SPELL_DAMAGE.*:enemy",
                             "CLM_SPELL_MISSED.*:enemy",
                             "CLM_SPELL_DRAIN.*:enemy",
                             "CLM_SPELL_LEECH.*:enemy",
                             "CLM_SPELL_INSTAKILL.*:enemy"},

    Combat_DoT_Self = {"CLM_SPELL_PERIODIC_DAMAGE.self"},

    Combat_DoT_ToSelf = {"CLM_SPELL_PERIODIC_DAMAGE.*:self"},

    Combat_DoT_Party = {"CLM_SPELL_PERIODIC_DAMAGE.party"},

    Combat_DoT_ToParty = {"CLM_SPELL_PERIODIC_DAMAGE.*:party"},

    Combat_DoT_Pet = {"CLM_SPELL_PERIODIC_DAMAGE.pet"},

    Combat_DoT_ToPet = {"CLM_SPELL_PERIODIC_DAMAGE.*:pet"},

    Combat_DoT_Enemy = {"CLM_SPELL_PERIODIC_DAMAGE.enemy"},

    Combat_DoT_ToEnemy = {"CLM_SPELL_PERIODIC_DAMAGE.*:enemy"},

    Combat_Heal_Self = {"CLM_SPELL_HEAL.self",
                        "CLM_SPELL_HEAL_ABSORBED.self",
                        "CLM_SPELL_ENERGIZE.self"},

    Combat_Heal_ToSelf = {"CLM_SPELL_HEAL.*:self",
                          "CLM_SPELL_HEAL_ABSORBED.*:self",
                          "CLM_SPELL_ENERGIZE.self"},

    Combat_Heal_Party = {"CLM_SPELL_HEAL.party",
                         "CLM_SPELL_HEAL_ABSORBED.party",
                         "CLM_SPELL_ENERGIZE.party"},

    Combat_Heal_ToParty = {"CLM_SPELL_HEAL.*:party",
                          "CLM_SPELL_HEAL_ABSORBED.*:party",
                          "CLM_SPELL_ENERGIZE.party"},

    Combat_Heal_Pet = {"CLM_SPELL_HEAL.pet",
                       "CLM_SPELL_HEAL_ABSORBED.pet",
                       "CLM_SPELL_ENERGIZE.pet"},

    Combat_Heal_ToPet = {"CLM_SPELL_HEAL.*:pet",
                         "CLM_SPELL_HEAL_ABSORBED.*:pet",
                         "CLM_SPELL_ENERGIZE.pet"},

    Combat_Heal_Enemy = {"CLM_SPELL_HEAL.enemy",
                         "CLM_SPELL_HEAL_ABSORBED.enemy",
                         "CLM_SPELL_ENERGIZE.enemy"},

    Combat_Heal_ToEnemy = {"CLM_SPELL_HEAL.*:enemy",
                           "CLM_SPELL_HEAL_ABSORBED.*:enemy",
                           "CLM_SPELL_ENERGIZE.enemy"},

    Combat_HoT_Self = {"CLM_SPELL_PERIODIC_HEAL.self"},

    Combat_HoT_ToSelf = {"CLM_SPELL_PERIODIC_HEAL.*:self"},

    Combat_HoT_Party = {"CLM_SPELL_PERIODIC_HEAL.party"},

    Combat_HoT_ToParty = {"CLM_SPELL_PERIODIC_HEAL.*:party"},

    Combat_HoT_Pet = {"CLM_SPELL_PERIODIC_HEAL.pet"},

    Combat_HoT_ToPet = {"CLM_SPELL_PERIODIC_HEAL.*:pet"},

    Combat_HoT_Enemy = {"CLM_SPELL_PERIODIC_HEAL.enemy"},

    Combat_HoT_ToEnemy = {"CLM_SPELL_PERIODIC_HEAL.*:enemy"},

    Combat_Aura_Self = {"CLM_SPELL_AURA_APPLIED.self",
                        "CLM_SPELL_AURA_REMOVED.self",
                        "CLM_SPELL_AURA_APPLIED_DOSE.self",
                        "CLM_SPELL_AURA_REMOVED_DOSE.self",
                        "CLM_SPELL_AURA_REFRESH.self",
                        "CLM_SPELL_AURA_BROKEN.self",
                        "CLM_SPELL_AURA_BROKEN_SPELL.self",
                        "CLM_SPELL_DISPEL.self",
                        "CLM_SPELL_DISPEL_FAILED.self"},

    Combat_Aura_ToSelf = {"CLM_SPELL_AURA_APPLIED.*:self",
                          "CLM_SPELL_AURA_REMOVED.*:self",
                          "CLM_SPELL_AURA_APPLIED_DOSE.*:self",
                          "CLM_SPELL_AURA_REMOVED_DOSE.*:self",
                          "CLM_SPELL_AURA_REFRESH.*:self",
                          "CLM_SPELL_AURA_BROKEN.*:self",
                          "CLM_SPELL_AURA_BROKEN_SPELL.*:self",
                          "CLM_SPELL_DISPEL.*:self",
                          "CLM_SPELL_DISPEL_FAILED.*:self"},

    Combat_Aura_Party = {"CLM_SPELL_AURA_APPLIED.party",
                         "CLM_SPELL_AURA_REMOVED.party",
                         "CLM_SPELL_AURA_APPLIED_DOSE.party",
                         "CLM_SPELL_AURA_REMOVED_DOSE.party",
                         "CLM_SPELL_AURA_REFRESH.party",
                         "CLM_SPELL_AURA_BROKEN.party",
                         "CLM_SPELL_AURA_BROKEN_SPELL.party",
                         "CLM_SPELL_DISPEL.party",
                         "CLM_SPELL_DISPEL_FAILED.party"},

    Combat_Aura_ToParty = {"CLM_SPELL_AURA_APPLIED.*:party",
                           "CLM_SPELL_AURA_REMOVED.*:party",
                           "CLM_SPELL_AURA_APPLIED_DOSE.*:party",
                           "CLM_SPELL_AURA_REMOVED_DOSE.*:party",
                           "CLM_SPELL_AURA_REFRESH.*:party",
                           "CLM_SPELL_AURA_BROKEN.*:party",
                           "CLM_SPELL_AURA_BROKEN_SPELL.*:party",
                           "CLM_SPELL_DISPEL.*:party",
                           "CLM_SPELL_DISPEL_FAILED.*:party"},

    Combat_Aura_Pet = {"CLM_SPELL_AURA_APPLIED.pet",
                        "CLM_SPELL_AURA_REMOVED.pet",
                        "CLM_SPELL_AURA_APPLIED_DOSE.pet",
                        "CLM_SPELL_AURA_REMOVED_DOSE.pet",
                        "CLM_SPELL_AURA_REFRESH.pet",
                        "CLM_SPELL_AURA_BROKEN.pet",
                        "CLM_SPELL_AURA_BROKEN_SPELL.pet",
                        "CLM_SPELL_DISPEL.pet",
                        "CLM_SPELL_DISPEL_FAILED.pet"},

    Combat_Aura_ToPet = {"CLM_SPELL_AURA_APPLIED.*:pet",
                         "CLM_SPELL_AURA_REMOVED.*:pet",
                         "CLM_SPELL_AURA_APPLIED_DOSE.*:pet",
                         "CLM_SPELL_AURA_REMOVED_DOSE.*:pet",
                         "CLM_SPELL_AURA_REFRESH.*:pet",
                         "CLM_SPELL_AURA_BROKEN.*:pet",
                         "CLM_SPELL_AURA_BROKEN_SPELL.*:pet",
                         "CLM_SPELL_DISPEL.*:pet",
                         "CLM_SPELL_DISPEL_FAILED.*:pet"},

    Combat_Aura_Enemy = {"CLM_SPELL_AURA_APPLIED.enemy",
                         "CLM_SPELL_AURA_REMOVED.enemy",
                         "CLM_SPELL_AURA_APPLIED_DOSE.enemy",
                         "CLM_SPELL_AURA_REMOVED_DOSE.enemy",
                         "CLM_SPELL_AURA_REFRESH.enemy",
                         "CLM_SPELL_AURA_BROKEN.enemy",
                         "CLM_SPELL_AURA_BROKEN_SPELL.enemy",
                         "CLM_SPELL_DISPEL.enemy",
                         "CLM_SPELL_DISPEL_FAILED.enemy"},

    Combat_Aura_ToEnemy = {"CLM_SPELL_AURA_APPLIED.*:enemy",
                           "CLM_SPELL_AURA_REMOVED.*:enemy",
                           "CLM_SPELL_AURA_APPLIED_DOSE.*:enemy",
                           "CLM_SPELL_AURA_REMOVED_DOSE.*:enemy",
                           "CLM_SPELL_AURA_REFRESH.*:enemy",
                           "CLM_SPELL_AURA_BROKEN.*:enemy",
                           "CLM_SPELL_AURA_BROKEN_SPELL.*:enemy",
                           "CLM_SPELL_DISPEL.*:enemy",
                           "CLM_SPELL_DISPEL_FAILED.*:enemy"},

    Combat_Cast_Self = {"CLM_SPELL_CAST_START.self",
                        "CLM_SPELL_CAST_SUCCESS.self",
                        "CLM_SPELL_SUMMON.self",
                        "CLM_SPELL_INTERRUPT.*:self"},

    Combat_CastFail_Self = {"CLM_SPELL_CAST_FAILED.self"},

    Combat_Cast_Party = {"CLM_SPELL_CAST_START.party",
                         "CLM_SPELL_CAST_SUCCESS.party",
                         "CLM_SPELL_SUMMON.party",
                         "CLM_SPELL_INTERRUPT.*:party"},

    Combat_CastFail_Party = {"CLM_SPELL_CAST_FAILED.party"},

    Combat_Cast_Pet = {"CLM_SPELL_CAST_START.pet",
                       "CLM_SPELL_CAST_SUCCESS.pet",
                       "CLM_SPELL_INTERRUPT.*:pet"},

    Combat_CastFail_Pet = {"CLM_SPELL_CAST_FAILED.pet"},

    Combat_Cast_Enemy = {"CLM_SPELL_CAST_START.enemy",
                         "CLM_SPELL_CAST_SUCCESS.enemy",
                         "CLM_SPELL_CAST_FAILED.enemy",
                         "CLM_SPELL_INTERRUPT.*:enemy"},

    Combat_CastFail_Enemy = {"CLM_SPELL_CAST_FAILED.enemy"},

}

-- For testing: set to true to keep the native chat frame visible.
local KEEP_NATIVE_FRAME = false

--------------------------------------------------------------------------

-- Combat event handling (collected here to avoid cluttering LogWindow).


-- Color mapping for combat events, indexed by subtype.
-- As a special case, AURA_* events are rewritten to BUFF_ or DEBUFF_
-- depending on whether the effect is marked as helpful or harmful,
-- and DISPEL (but not DISPEL_FAILED) is likewise rewritten to
-- DISPEL_BUFF or DISPEL_DEBUFF.
local COMBAT_EVENT_COLORS = {
    DAMAGE              = {1, 0.3, 0.3},
    PERIODIC_DAMAGE     = {1, 0.3, 0.3},
    BUILDING_DAMAGE     = {1, 0.3, 0.3},
    DRAIN               = {1, 0.3, 0.3},
    LEECH               = {1, 0.3, 0.3},
    INSTAKILL           = {1, 0.3, 0.3},
    MISSED              = {0.8, 0.8, 0.8},
    DISPEL_FAILED       = {0.8, 0.8, 0.8},
    HEAL                = {0.82, 1, 0.3},
    PERIODIC_HEAL       = {0.82, 1, 0.3},
    ENERGIZE            = {0.82, 1, 0.3},
    CAST_START          = {1, 1, 0.67},
    CAST_SUCCESS        = {1, 1, 0.67},
    CAST_FAILED         = {1, 0, 0},
    INTERRUPT           = {1, 1, 0.67},
    BUFF_APPLIED        = {0.55, 0.75, 1},
    BUFF_REMOVED        = {0.55, 0.75, 1},
    BUFF_APPLIED_DOSE   = {0.55, 0.75, 1},
    BUFF_REMOVED_DOSE   = {0.55, 0.75, 1},
    BUFF_RERFESH        = {0.55, 0.75, 1},
    BUFF_BROKEN         = {0.55, 0.75, 1},
    DISPEL_BUFF         = {0.55, 0.75, 1},
    DEBUFF_APPLIED      = {1, 0.55, 0.75},
    DEBUFF_REMOVED      = {1, 0.55, 0.75},
    DEBUFF_APPLIED_DOSE = {1, 0.55, 0.75},
    DEBUFF_REMOVED_DOSE = {1, 0.55, 0.75},
    DEBUFF_RERFESH      = {1, 0.55, 0.75},
    DEBUFF_BROKEN       = {1, 0.55, 0.75},
    DISPEL_DEBUFF       = {1, 0.55, 0.75},
    -- FIXME: when does AURA_BROKEN_SPELL fire?
}

-- Text formats for combat events.  Indexed by either an underscore-prefixed
-- subtype (rewritten as for colors above) or a complete event name.
-- See below for token details.
local COMBAT_EVENT_FORMATS = {
    SWING_DAMAGE         = "$(source:N) $(source:#:attack:attacks) $(target:n) for $(amount) $(school) damage$(damageinfo).",
    RANGE_DAMAGE         = "$(source:N) $(source:#:attack:attacks) $(target:n) for $(amount) $(school) damage$(damageinfo).",
    SPELL_DAMAGE         = "$(source:P)$(spell) hits $(target:n) for $(amount) $(school) damage$(damageinfo).",
    ENVIRONMENTAL_DAMAGE = "$(source:N) $(source:#:take:takes) $(amount) damage from $(env)$(damageinfo).",
    _PERIODIC_DAMAGE     = "$(source:P)$(spell) effect hits $(target:n) for $(amount) $(school) damage$(damageinfo).",
    _BUILDING_DAMAGE     = "$(source:P)$(spell) hits $(target:n) for $(amount) $(school) damage$(damageinfo).",
    _DRAIN               = "$(source:P)$(spell) drains $(amount) $(power) from $(target:n).",
    _LEECH               = "$(source:P)$(spell) leeches $(amount) $(power) from $(target:n).",
    _INSTAKILL           = "$(source:P)$(spell) kills $(target:n).",
    SWING_MISSED         = "$(source:N) $(source:#:attack:attacks) $(target:n) and misses$(missinfo).",
    RANGE_MISSED         = "$(source:N) $(source:#:attack:attacks) $(target:n) and misses$(missinfo).",
    SPELL_MISSED         = "$(source:P)$(spell) misses $(target:n)$(missinfo).",
    _DISPEL_FAILED       = "$(source:P)$(spell) fails to dispel $(target:p)$(extraspell).",
    _HEAL                = "$(source:P)$(spell) heals $(target:n) for $(amount)$(healinfo).",
    _PERIODIC_HEAL       = "$(source:P)$(spell) effect heals $(target:n) for $(amount)$(healinfo).",
    _ENERGIZE            = "$(source:P)$(spell) restores $(amount) $(power) to $(target:n)$(healinfo).",
    _CAST_START          = "$(source:N) $(source:#:start:starts) casting $(spell).",
    _CAST_SUCCESS        = "$(source:N) $(source:#:cast:casts) $(spell).",
    _CAST_FAILED         = "$(source:P)cast of $(spell) failed: $(failinfo).",
    _INTERRUPT           = "$(source:N) $(source:#:interrupt:interrupts) $(target:p)cast of $(spell).",
    _BUFF_APPLIED        = "$(target:N) $(target:#:gain:gains) $(spell).",
    _BUFF_REMOVED        = "$(target:P)$(spell) fades.",
    _BUFF_APPLIED_DOSE   = "$(target:N) $(target:#:gain:gains) a stack of $(spell).",
    _BUFF_REMOVED_DOSE   = "$(target:N) $(target:#:lose:loses) a stack of $(spell).",
    _BUFF_RERFESH        = "$(target:P)$(spell) is refreshed.",
    _BUFF_BROKEN         = "$(target:P)$(spell) is broken.",
    _DISPEL_BUFF         = "$(source:P)$(spell) dispels $(target:p)$(extraspell).",
    _DEBUFF_APPLIED      = "$(target:N) $(target:#:are:is) inflicted with $(spell).",
    _DEBUFF_REMOVED      = "$(target:P)$(spell) fades.",
    _DEBUFF_APPLIED_DOSE = "$(target:N) $(target:#:gain:gains) a stack of $(spell).",
    _DEBUFF_REMOVED_DOSE = "$(target:N) $(target:#:lose:loses) a stack of $(spell).",
    _DEBUFF_RERFESH      = "$(target:P)$(spell) is refreshed.",
    _DEBUFF_BROKEN       = "$(target:P)$(spell) is broken.",
    _DISPEL_DEBUFF       = "$(source:P)$(spell) dispels $(target:p)$(extraspell).",
    _SUMMON              = "$(source:N) $(source:#:summon:summons) $(target:N) with $(spell).",
}

-- Descriptive strings for miss types.
local COMBAT_MISS_TEXT = {
    ABSORB  = " (absorbed)",
    BLOCK   = " (blocked)",
    DEFLECT = " (deflected)",
    DODGE   = " (dodged)",
    EVADE   = " (evaded)",
    IMMUNE  = " (immune)",
    MISS    = "",
    PARRY   = " (parried)",
    REFLECT = " (reflected)",
    RESIST  = " (resisted)",
}

-- Descriptive strings for power types.
local COMBAT_POWER_TEXT = {
    [Enum.PowerType.Mana] = MANA,
    [Enum.PowerType.Rage] = RAGE,
    [Enum.PowerType.Focus] = FOCUS,
    [Enum.PowerType.Energy] = ENERGY,
    [Enum.PowerType.ComboPoints] = COMBO_POINTS,
    [Enum.PowerType.Runes] = RUNES,
    [Enum.PowerType.RunicPower] = RUNIC_POWER,
    [Enum.PowerType.SoulShards] = SOUL_SHARDS,
    [Enum.PowerType.LunarPower] = LUNAR_POWER,
    [Enum.PowerType.HolyPower] = HOLY_POWER,
    [Enum.PowerType.Alternate] = ALTERNATE,
    [Enum.PowerType.Maelstrom] = MAELSTROM,
    [Enum.PowerType.Chi] = CHI_POWER,
    [Enum.PowerType.Insanity] = INSANITY,
    [Enum.PowerType.ArcaneCharges] = ARCANE_CHARGES,
    [Enum.PowerType.Fury] = FURY,
    [Enum.PowerType.Pain] = PAIN,
    -- Not in Blizzard code:
    [Enum.PowerType.AlternateMount] = "Vigor",
}


-- Return the replacement text for a combat message format token.
-- |extra| holds extra data relevant to formatting (see ReplaceCombatTokens()).
local function ReplaceCombatToken(token, event, extra)
    local result
    if strsub(token,1,9) == "source:#:" or strsub(token,1,9) == "target:#:" then
        local selector = extra[strsub(token, 1, 8)]
        local sep = strstr(token, ":", 10)
        if sep then
            if selector == 1 then
                result = strsub(token, 10, sep-1)
            elseif selector == 2 then
                result = strsub(token, sep+1)
            end
        end
    else
        result = extra[token]
    end
    return result
        or WoWXIV.FormatColoredText("<invalid token $("..token..")>", 1, 0, 0)
end

-- Replace all tokens in a combat message format string, and return the
-- formatted string.
local function ReplaceCombatTokens(format, event)
    local damageinfo = ""
    local healinfo = ""
    local is_heal = (strsub(event.subtype, 1, 4) == "HEAL")
    if event.critical then
        if is_heal then
            healinfo = healinfo.." (critical)"
        else
            damageinfo = damageinfo.." (critical)"
        end
    end
    if event.resisted and event.resisted > 0 then
        damageinfo = damageinfo.." ("..event.resisted.." resisted)"
    end
    if event.blocked and event.blocked > 0 then
        damageinfo = damageinfo.." ("..event.blocked.." blocked)"
    end
    if event.absorbed and event.absorbed > 0 then
        if is_heal then
            healinfo = healinfo.." ("..event.absorbed.." absorbed)"
        else
            damageinfo = damageinfo.." ("..event.absorbed.." absorbed)"
        end
    end
    if event.overkill and event.overkill > 0 then
        damageinfo = damageinfo.." (overkill by "..event.overkill..")"
    end
    if event.overheal and event.overheal > 0 then
        healinfo = healinfo.." (overheal by "..event.overheal..")"
    end
    local extra = {
        amount = event.amount,
        damageinfo = damageinfo,
        env = event.env_type and strlower(event.env_type),
        failinfo = event.failed_type,
        healinfo = healinfo,
        missinfo = event.miss_type and COMBAT_MISS_TEXT[event.miss_type],
        power = event.power_type and (COMBAT_POWER_TEXT[event.power_type] or WoWXIV.FormatColoredText("<unknown power type $("..event.power_type..")>", 1, 0, 0)),
        school = event.spell_school and GetSchoolString(event.spell_school),
        spell = event.spell_id and C_Spell.GetSpellLink(event.spell_id)
                                or event.spell_name,
        extraspell = event.extra_spell_id
                         and C_Spell.GetSpellLink(event.extra_spell_id)
                         or event.extra_spell_name,
    }
    if not event.source_name then
        extra["source:n"] = ""
        extra["source:N"] = ""
        extra["source:p"] = ""
        extra["source:P"] = ""
        extra["source:#"] = 0
    elseif band(event.source_flags, AFFILIATION_MINE) ~= 0 and band(event.source_flags, TYPE_PLAYER) ~= 0 then
        extra["source:n"] = "you"
        extra["source:N"] = "You"
        extra["source:p"] = "your "
        extra["source:P"] = "Your "
        extra["source:#"] = 1
    else
        extra["source:n"] = event.source_name
        extra["source:N"] = event.source_name
        extra["source:p"] = event.source_name.."'s "
        extra["source:P"] = event.source_name.."'s "
        extra["source:#"] = 2
    end
    if not event.dest_name then
        extra["target:n"] = ""
        extra["target:N"] = ""
        extra["target:p"] = ""
        extra["target:P"] = ""
        extra["target:#"] = 0
    elseif band(event.dest_flags, AFFILIATION_MINE) ~= 0 and band(event.dest_flags, TYPE_PLAYER) ~= 0 then
        extra["target:n"] = "you"
        extra["target:N"] = "You"
        extra["target:p"] = "your "
        extra["target:P"] = "Your "
        extra["target:#"] = 1
    else
        extra["target:n"] = event.dest_name
        extra["target:N"] = event.dest_name
        extra["target:p"] = event.dest_name.."'s "
        extra["target:P"] = event.dest_name.."'s "
        extra["target:#"] = 2
    end
    return strgsub(format, "$%(([^)]+)%)",
                   function(token)
                       return ReplaceCombatToken(token, event, extra)
                   end)
end

-- Return the unit type for the given unit, for use in the returned event ID.
local function CombatUnitType(event, unit, flags)
    local unit_token = UnitTokenFromGUID(unit)
    if not unit then
        return "other"
    elseif band(flags, TYPE_OBJECT) ~= 0 then
        return "object"
    elseif band(flags, AFFILIATION_ALLY) ~= 0 and band(flags, TYPE_PET) ~= 0 then
        return "pet"
    elseif band(flags, AFFILIATION_MINE) ~= 0 then
        return "self"
    elseif band(flags, AFFILIATION_PARTY_OR_RAID) ~= 0 then
        return "party"
    elseif unit_token and select(2, UnitDetailedThreatSituation("player", unit_token)) then
        return "enemy"
    elseif band(flags, AFFILIATION_ALLY) ~= 0 and band(flags, CONTROL_NPC) ~= 0 then
        return "npc"
    else
        return "other"
    end
end

-- Return a formatted log message for the given combat event.
-- Returns 5 values: event ID (string), text, and 3 color components (RGB),
-- which can be passed directly to LogWindow:AddMessage().
-- Returns no values if the event cannot be parsed.
local function FormatCombatEvent(event)
    -- Adjust the subtype to account for the buff/debuff split.  Note that
    -- we don't expose this split in the returned event ID.
    local subtype = event.subtype
    if strsub(subtype, 1, 5) == "AURA_" then
        subtype = event.aura_type .. "_" .. strsub(subtype, 6)
    elseif subtype == "DISPEL" then
        subtype = subtype .. "_" .. event.aura_type
    end

    local format = (COMBAT_EVENT_FORMATS[event.type]
                    or COMBAT_EVENT_FORMATS["_"..subtype])
    if not format then
        return
    end
    local text = ReplaceCombatTokens(format, event)
    local color = COMBAT_EVENT_COLORS[subtype] or {1,1,1}

    local source_type = event.category=="ENVIRONMENT" and "env"
        or CombatUnitType(event, event.source, event.source_flags)
    local dest_type = CombatUnitType(event, event.dest, event.dest_flags)
    local event_id = "CLM_"..event.type.."."..source_type..":"..dest_type

    return event_id, text, unpack(color)
end

--------------------------------------------------------------------------

local Tab = class()

function Tab:__constructor(name, message_types)
    self.name = name
    self:SetMessageTypes(message_types)
end

function Tab:SetMessageTypes(message_types)
    assert(type(message_types) == "table")
    assert(#message_types > 0)
    for i, msg_type in ipairs(message_types) do
        assert(type(msg_type) == "string",
               "wrong element type at message_types["..i.."]")
        assert(MESSAGE_TYPES[msg_type],
               msg_type.." is not a recognized message type")
    end

    self.message_types = {}
    self.event_lookup = {}
    self.wildcard_events = {}
    for _, msg_type in ipairs(message_types) do
        tinsert(self.message_types, msg_type)
        for _, event in ipairs(MESSAGE_TYPES[msg_type]) do
            if strsub(event, 1, 4) == "CLM_" then
                local sep1 = strstr(event, ".", 5)
                local sep2, source
                if sep1 then
                    sep2 = strstr(event, ":", sep1+1)
                    source = strsub(event, sep1+1, sep2 and sep2-1)
                else
                    source = "*"
                    sep2 = strstr(event, ":", 5)
                end
                local target = sep2 and strsub(event, sep2+1) or "*"
                if source == "*" or target == "*" then
                    local sep = sep1 or sep2
                    local base_event = sep and strsub(event, 1, sep-1) or event
                    tinsert(self.wildcard_events, {base_event, source, target})
                else
                    self.event_lookup[event] = true
                end
            else
                self.event_lookup[event] = true
            end
        end
    end
end

function Tab:GetName()
    return self.name
end

-- Returns true if the given message should be displayed in this tab.
function Tab:Filter(event, text)
    if self.event_lookup[event] then return true end
    if strsub(event, 1, 4) == "CLM_" then
        local sep1 = strstr(event, ".", 5)
        assert(sep1)
        local sep2 = strstr(event, ":", sep1+1)
        assert(sep2)
        local base_event = strsub(event, 1, sep1-1)
        local source = strsub(event, sep1+1, sep2-1)
        local target = strsub(event, sep2+1)
        for _, match in ipairs(self.wildcard_events) do
            if (match[1] == base_event
                and (match[2] == "*" or match[2] == source)
                and (match[3] == "*" or match[3] == target))
            then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------

local TabBar = class(Frame)

function TabBar:__allocator(parent)
    return __super("Frame", nil, parent)
end

function TabBar:__constructor(parent)
    self.tabs = {}
    self.active_tab = nil
    self.size_scale = 5/6  -- gives the right size at 2560x1440 with default UI scaling

    self:SetHeight(26*self.size_scale)

    local left = self:CreateTexture(nil, "BACKGROUND")
    self.left = left
    WoWXIV.SetUITexture(left, 0, 21, 52, 78)
    left:SetSize(21*self.size_scale, self:GetHeight())
    left:SetPoint("TOPLEFT")

    local right = self:CreateTexture(nil, "BACKGROUND")
    self.right = right
    WoWXIV.SetUITexture(right, 72, 96, 52, 78)
    right:SetSize(24*self.size_scale, self:GetHeight())
    right:SetPoint("LEFT", left, "RIGHT")

    self:SetScript("OnMouseDown", function(frame) self:OnClick() end)

    self:AddTab(Tab("General", {
        "System", "Error", "Ping",
        "Channel", "Chat_Channel",
        "Chat_Say", "Chat_Emote", "Chat_Yell", "Chat_Whisper",
        -- FF14 puts NPC dialogue in a separate "Event" tab, but we leave
        -- this in the main tab both to stick with WoW defaults and because
        -- many world events are announced via NPC chats.
        "Chat_NPC",
        "Chat_Party", "Chat_Raid", "Chat_Instance",
        "Chat_Guild", "Chat_GuildOfficer",
        "BNWhisper", "BNInlineToast",
        "Combat_Reward", "Combat_Faction", "Combat_Misc", "TargetIcon",
        "BG_Alliance", "BG_Horde", "BG_Neutral",
        "Skill", "Loot", "Achievement",
        "Guild", "Guild_Achievement",
        "VoiceText"}))
    self:AddTab(Tab("Battle", {
        "PetBattle",
        "Combat_Attack_Self", "Combat_Attack_ToSelf",
        "Combat_Attack_Party", "Combat_Attack_ToParty",
        "Combat_Attack_Pet", "Combat_Attack_ToPet",
        "Combat_Attack_Enemy", "Combat_Attack_ToEnemy",
        "Combat_Heal_Self", "Combat_Heal_ToSelf",
        "Combat_Heal_Party", "Combat_Heal_ToParty",
        "Combat_Heal_Pet", "Combat_Heal_ToPet",
        "Combat_Heal_Enemy", "Combat_Heal_ToEnemy",
        "Combat_Aura_Self", "Combat_Aura_ToSelf",
        "Combat_Aura_Party", "Combat_Aura_ToParty",
        "Combat_Aura_Pet", "Combat_Aura_ToPet",
        "Combat_Aura_Enemy", "Combat_Aura_ToEnemy",
        "Combat_Cast_Self", "Combat_Cast_Pet", "Combat_Cast_Enemy"}))
    -- FIXME: temporary tab to check that all events are caught
    self:AddTab(Tab("Other", {"Gathering", "TradeSkill", "PetInfo", "Debug"}))

    self:SetActiveTab(1)
    self:Show()
end

function TabBar:AddTab(tab)
    local name = tab:GetName()
    local last = #self.tabs > 0 and self.tabs[#self.tabs].frame or self.left
    local index = #self.tabs + 1

    local tab_frame = CreateFrame("Frame", nil, self)
    tab_frame:SetHeight(self:GetHeight())
    tab_frame:SetPoint("LEFT", last, "RIGHT")

    local header = tab_frame:CreateTexture(nil, "BACKGROUND")
    header:SetWidth(16*self.size_scale)
    header:SetPoint("TOPLEFT")
    header:SetPoint("BOTTOMLEFT")
    WoWXIV.SetUITexture(header, 46, 62, 52, 78)

    local bg = tab_frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", header, "TOPRIGHT")
    bg:SetPoint("BOTTOMRIGHT")
    WoWXIV.SetUITexture(bg, 62, 70, 52, 78)

    local label = tab_frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", bg)
    label:SetTextColor(WHITE_FONT_COLOR:GetRGB())
    label:SetText(name)

    tab_frame:SetWidth(header:GetWidth()
                       + label:GetStringWidth() + 14*self.size_scale)

    self.right:ClearAllPoints()
    self.right:SetPoint("LEFT", tab_frame, "RIGHT")

    self.tabs[index] = {tab = tab, frame = tab_frame,
                        label = label, header = header, bg = bg}
end

function TabBar:SetActiveTab(index)
    self.active_tab = index
    for i, tab_info in ipairs(self.tabs) do
        local u0 = (i == index) and 21 or 46
        WoWXIV.SetUITexCoord(tab_info.header, u0, u0+16, 52, 78)
    end
    EventRegistry:TriggerEvent("WoWXIV.LogWindow.OnActiveTabChanged", index)
end

function TabBar:GetActiveTab()
    return self.active_tab and self.tabs[self.active_tab].tab
end

function TabBar:NextTab()
    local index = (self.active_tab or 0) + 1
    self:SetActiveTab(index > #self.tabs and 1 or index)
end

function TabBar:PrevTab()
    local index = (self.active_tab or 0) - 1
    self:SetActiveTab(index < 1 and #self.tabs or index)
end

function TabBar:OnClick(button, down)
    for index, tab_info in ipairs(self.tabs) do
        if tab_info.frame:IsMouseOver() then
            self:SetActiveTab(index)
            return
        end
    end
end

-- Returns true if any tab accepts the given message.  Mainly for debugging.
function TabBar:FilterAnyTab(event, text)
    for _, tab in ipairs(self.tabs) do
        if tab.tab:Filter(event, text) then return true end
    end
    return false
end

--------------------------------------------------------------------------

-- ScrollingMessageWindow overrides for the log window.
local FadeLimiterMixin = {}

-- Set the final alpha value for faded lines (0 = transparent, 1 = opaque).
function FadeLimiterMixin:SetFadeFloor(alpha_floor)
    self.alpha_floor = alpha_floor
end

function FadeLimiterMixin:CalculateLineAlphaValueFromTimestamp(now, timestamp)
    local alpha =
        ScrollingMessageFrameMixin.CalculateLineAlphaValueFromTimestamp(
            self, now, timestamp)
    local alpha_floor = self.alpha_floor or 0
    return alpha_floor + (alpha * (1 - alpha_floor))
end

--------------------------------------------------------------------------

-- We unfortunately can't make this class inherit from ScrollingMessageFrame
-- because that causes taint to block CopyToClipboard().
local LogWindow = class()

function LogWindow:__constructor()
    -- ID of the event currently being processed.  This is used to fill in
    -- the event field in history entries, since most messages will come
    -- from Blizzard code which does not pass down the event ID.
    self.current_event = nil

    local frame = Mixin(
        CreateFrame("ScrollingMessageFrame", "WoWXIV_LogWindow", UIParent),
        FadeLimiterMixin)
    self.frame = frame
    self:InternalSetFullscreen(false)

    frame:SetTimeVisible(2*60)
    frame:SetFadeDuration(2)
    frame:SetFadeFloor(1/3)
    frame:SetMaxLines(WoWXIV_config["logwindow_history"])
    frame:SetFontObject(ChatFontNormal)
    frame:SetIndentedWordWrap(true)
    frame:SetJustifyH("LEFT")
    frame:SetTextCopyable(true)
    frame:EnableMouse(true)

    frame:SetScript("OnHyperlinkClick",
                    function(frame, link, text, button)
                        SetItemRef(link, text, button, frame)
                    end)
    frame:SetHyperlinksEnabled(true)

    -- Stuff needed by the common chat code
    self.channelList = {}
    self.zoneChannelList = {}
    ChatFrame_RegisterForChannels(self, GetChatWindowChannels(1))

    frame:SetScript("OnEvent", function(frame, event, ...)
                                   if self[event] then
                                       self[event](self, event, ...)
                                   end
                               end)
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHAT_MSG_CHANNEL")
    frame:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
    frame:RegisterEvent("CLUB_REMOVED")
    frame:RegisterEvent("UPDATE_INSTANCE_INFO")
    frame:RegisterEvent("UPDATE_CHAT_COLOR")
    frame:RegisterEvent("UPDATE_CHAT_COLOR_NAME_BY_CLASS")
    frame:RegisterEvent("CHAT_SERVER_DISCONNECTED")
    frame:RegisterEvent("CHAT_SERVER_RECONNECTED")
    frame:RegisterEvent("BN_CONNECTED")
    frame:RegisterEvent("BN_DISCONNECTED")
    frame:RegisterEvent("PLAYER_REPORT_SUBMITTED")
    frame:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
    frame:RegisterEvent("ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED")
    frame:RegisterEvent("NEWCOMER_GRADUATION")
    frame:RegisterEvent("CHAT_REGIONAL_STATUS_CHANGED")
    frame:RegisterEvent("CHAT_REGIONAL_SEND_FAILED")
    frame:RegisterEvent("NOTIFY_CHAT_SUPPRESSED")

    local OnChatMsg = self.OnChatMsg
    local OnNonChatMsg = self.OnNonChatMsg
    self.CHAT_MSG_CHANNEL = OnChatMsg
    self.CHAT_MSG_COMMUNITIES_CHANNEL = OnChatMsg
    self.CLUB_REMOVED = OnNonChatMsg
    self.UPDATE_INSTANCE_INFO = OnNonChatMsg
    self.CHAT_SERVER_DISCONNECTED = OnNonChatMsg
    self.CHAT_SERVER_RECONNECTED = OnNonChatMsg
    self.BN_CONNECTED = OnNonChatMsg
    self.BN_DISCONNECTED = OnNonChatMsg
    self.PLAYER_REPORT_SUBMITTED = OnNonChatMsg
    self.CHAT_REGIONAL_STATUS_CHANGED = OnNonChatMsg
    self.CHAT_REGIONAL_SEND_FAILED = OnNonChatMsg
    self.NOTIFY_CHAT_SUPPRESSED = OnNonChatMsg
    local VALID_EVENT_TYPES = {  -- For sanity checking, see below.
        TIME_PLAYED_MSG = true,
        PLAYER_LEVEL_CHANGED = true,
        UNIT_LEVEL = true,
        CHARACTER_POINTS_CHANGED = true,
        DISPLAY_EVENT_TOAST_LINK = true,
        GUILD_MOTD = true,
    }
    for group, events in pairs(ChatTypeGroup) do
        for _, event in ipairs(events) do
            if event:sub(1, 9) == "CHAT_MSG_" then
                if not self[event] then self[event] = OnChatMsg end
            else
                assert(VALID_EVENT_TYPES[event])
                if not self[event] then self[event] = OnNonChatMsg end
            end
            frame:RegisterEvent(event)
        end
    end

    CLM.RegisterAnyEvent(self, self.OnCombatEvent)

    local scrollbar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    self.scrollbar = scrollbar
    scrollbar:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -6, 0)
    ScrollUtil.InitScrollingMessageFrameWithScrollBar(frame, scrollbar)
    scrollbar:Show()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    self.background = bg
    bg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 3, 3)
    -- HACK: scrollbar frame is smaller than the actual visuals
    bg:SetPoint("BOTTOMLEFT", scrollbar, "BOTTOMLEFT", -5, -3)
    bg:SetColorTexture(0, 0, 0, 0.25)

    local tab_bar = TabBar(frame)
    self.tab_bar = tab_bar
    tab_bar:SetPoint("TOPLEFT", bg, "BOTTOMLEFT")
    tab_bar:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT")
    EventRegistry:RegisterCallback(
        "WoWXIV.LogWindow.OnActiveTabChanged",
        function(_, index) self:OnActiveTabChanged(index) end)

    local tab = tab_bar:GetActiveTab()
    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histindex = WoWXIV_logwindow_hist_top
    for i = 1, histlen do
        local ts, event, text, r, g, b = unpack(history[histindex])
        if tab:Filter(event, text) then
            frame:AddMessage(text, r, g, b, 0.5)
        end
        histindex = (histindex == histlen) and 1 or histindex+1
    end

    -- Copy various things into the frame table for external access (e.g.
    -- menu cursor).
    frame.tab_bar = self.tab_bar
    -- Careful here - "function frame:..." would override self!
    function frame.ToggleFullscreen(_,...) return self:ToggleFullscreen(...) end

    if not KEEP_NATIVE_FRAME then
        ChatFrame1EditBox:ClearAllPoints()
        ChatFrame1EditBox:SetPoint("LEFT", scrollbar, "LEFT", -5, 0)
        ChatFrame1EditBox:SetPoint("TOPRIGHT", tab_bar, "BOTTOMRIGHT", 8, 0)
    end
end

-- Toggle the window between normal and fullscreen sizes.
-- With a boolean argument, sets the fullscreen state to the given value.
function LogWindow:ToggleFullscreen(optional_state)
    local new_state
    if optional_state ~= nil then
        new_state = not not optional_state
    else
        new_state = not self.fullscreen
    end
    self:InternalSetFullscreen(new_state)
end

function LogWindow:InternalSetFullscreen(state)
    self.fullscreen = state
    local frame = self.frame
    if state then
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(0)
        frame:SetSize(UIParent:GetWidth()*0.8, UIParent:GetHeight()*0.8)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
        frame:SetFading(false)
    else
        frame:SetFrameStrata("MEDIUM")
        frame:SetFrameLevel(UIParent:GetFrameLevel() + 1)
        frame:SetSize(430, 120)
        frame:ClearAllPoints()
        if not KEEP_NATIVE_FRAME then
            frame:SetPoint("BOTTOMLEFT", 49, 72)
        else
            frame:SetPoint("BOTTOMLEFT", GeneralDockManager, "TOPLEFT", 0, 67)
        end
        frame:ResetAllFadeTimes()
        frame:SetFading(true)
    end
end

function LogWindow:PLAYER_ENTERING_WORLD(event)
    self.lang_default = GetDefaultLanguage()
    self.lang_alt = GetAlternativeDefaultLanguage()
    self.current_event = event
    ChatFrame_ConfigEventHandler(self, event)
    self.current_event = nil
end

function LogWindow:ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED(event)
    self.lang_alt = GetAlternativeDefaultLanguage()
    self.current_event = event
    ChatFrame_ConfigEventHandler(self, event)
    self.current_event = nil
end

function LogWindow:UPDATE_CHAT_COLOR(event, ...)
    self.current_event = event
    ChatFrame_ConfigEventHandler(self, event, ...)
    self.current_event = nil
end

function LogWindow:UPDATE_CHAT_COLOR_NAME_BY_CLASS(event, ...)
    self.current_event = event
    ChatFrame_ConfigEventHandler(self, event, ...)
    self.current_event = nil
end

function LogWindow:CHAT_MSG_CHANNEL_NOTICE(event, type, _, _, link_text, _, _, id, index, name)
    local link = "|Hchannel:CHANNEL:" .. index .. "|h[" .. link_text .. "]|h"
    local text
    if type == "YOU_JOINED" then
        self.channelList[index] = name
        self.zoneChannelList[index] = id
        text = "Joined Channel: " .. link
    elseif type == "YOU_CHANGED" then
        self.channelList[index] = name
        self.zoneChannelList[index] = id
        text = "Changed Channel: " .. link
    elseif type == "YOU_LEFT" or type == "SUSPENDED" then
        self.channelList[index] = nil
        self.zoneChannelList[index] = nil
        text = "Left Channel: " .. link
    else
        error("unknown type " .. type)
    end
    local chat_type = "CHANNEL" .. index
    local info = ChatTypeInfo[chat_type] or {r=1, g=1, b=1}
    self:AddMessage(event, text, info.r, info.g, info.b)
end

function LogWindow:OnChatMsg(event, ...)
    self.current_event = event
    ChatFrame_MessageEventHandler(self, event, ...)
    self.current_event = nil
end

function LogWindow:OnNonChatMsg(event, ...)
    self.current_event = event
    ChatFrame_SystemEventHandler(self, event, ...)
    self.current_event = nil
end

function LogWindow:OnCombatEvent(event)
    local event_name, text, r, g, b = FormatCombatEvent(event)
    if event_name then
        self:AddMessage(event_name, text, r, g, b)
    end
end

function LogWindow:AddHistoryEntry(event, text, r, g, b)
    local record = {WoWXIV.timePrecise(), event, text, r, g, b}
    local histsize = WoWXIV_config["logwindow_history"]
    if #WoWXIV_logwindow_history < histsize then
        assert(WoWXIV_logwindow_hist_top == 1)
        tinsert(WoWXIV_logwindow_history, record)
    else
        local histindex = WoWXIV_logwindow_hist_top
        WoWXIV_logwindow_history[histindex] = record
        if histindex == histsize then
            WoWXIV_logwindow_hist_top = 1
        else
            WoWXIV_logwindow_hist_top = histindex + 1
        end
    end
end

function LogWindow:OnActiveTabChanged(index)
    local tab = self.tab_bar:GetActiveTab()
    local frame = self.frame
    frame:RemoveMessagesByPredicate(function() return true end)
    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histindex = WoWXIV_logwindow_hist_top
    for i = 1, histlen do
        local ts, event, text, r, g, b = unpack(history[histindex])
        if not tab or tab:Filter(event, text) then
            frame:AddMessage(text, r, g, b)
        end
        histindex = (histindex == histlen) and 1 or histindex+1
    end
end

function LogWindow:AddMessage(event, text, r, g, b)
    if type(text) ~= "string" then  -- event omitted (as from Blizzard code)
        event, text, r, g, b = (self.current_event or "-"), event, text, r, g
    end
    r = r or 1
    g = g or 1
    b = b or 1
    if not KEEP_NATIVE_FRAME then
        self.last_message = self.last_message or {0, 0, 0, 0, 0}
        self.saved_message = self.saved_message or {0, 0, 0, 0, 0}
        if event ~= "_" and text == self.saved_message[2] and r == self.saved_message[3] and g == self.saved_message[4] and b == self.saved_message[5] then
            self.saved_message[2] = 0
        end
        if self.saved_message[2] ~= 0 then
            local saved_event, saved_text, saved_r, saved_g, saved_b = unpack(self.saved_message)
            if saved_event == "_" then saved_event = "-" end
            self.saved_message[2] = 0
            self:AddMessage(saved_event, saved_text, saved_r, saved_g, saved_b)
        end
        if event == nil then return end  -- from RunNextFrame call below
        if event == "_" then
            if not (text == self.last_message[2] and r == self.last_message[3] and g == self.last_message[4] and b == self.last_message[5]) then
                self.saved_message[1] = event
                self.saved_message[2] = text
                self.saved_message[3] = r
                self.saved_message[4] = g
                self.saved_message[5] = b
                RunNextFrame(function() self:AddMessage(nil, text=="" and "-" or "") end)
            end
            return
        end
        self.last_message[1] = event
        self.last_message[2] = text
        self.last_message[3] = r
        self.last_message[4] = g
        self.last_message[5] = b
        RunNextFrame(function() self.last_message[2] = 0 end)
    end  -- if not KEEP_NATIVE_FRAME
    if self:FilterOut(event, text) then
        -- Ignore
    elseif self.tab_bar:GetActiveTab():Filter(event, text) then
        self:InternalAddMessage(true, true, event, text, r, g, b)
    elseif self.tab_bar:FilterAnyTab(event, text) then
        self:InternalAddMessage(false, true, event, text, r, g, b)
    elseif strsub(event,1,4) ~= "CLM_" then
        self.frame:AddMessage("[WoWXIV.LogWindow] Event not taken by any tab: ["..event.."] "..text, 1, 1, 1)
    end
end

function LogWindow:FilterOut(event, text)
    if (strsub(event,1,17)  == "CHAT_MSG_MONSTER_" or event == "CHAT_MSG_TEXT_EMOTE") and strsub(text,1,17) == "Brann Bronzebeard" then return true end  -- Suppress messages from wiseass delve companion.
    return false
end

function LogWindow:InternalAddMessage(show, save, event, text, r, g, b)
    if show then
        self.frame:AddMessage(text, r, g, b)
        if WoWXIV_config["logwindow_auto_show_new"] then
            self.frame:ScrollToBottom()
        end
    end
    if save then
        self:AddHistoryEntry(event, text, r, g, b)
    end
end

-- Various methods called by the ChatFrame message handlers we borrow.
function LogWindow:AdjustMessageColors(func) end
function LogWindow:GetFont() return self.frame:GetFontObject() end
function LogWindow:GetID() return 1 end
function LogWindow:IsShown() return true end
function LogWindow:SetHyperlinksEnabled(enable) end
function LogWindow:UpdateColorByID() end
-- This is only meaningfully called from FCF_RemoveAllMessagesFromChanSender(),
-- which in turn is only called in response to PLAYER_REPORT_SUBMITTED.
-- We take the position that no messages should be removed except upon
-- explicit action by the player.  (We don't have that explicit action yet
-- due to lack of desire to implement.)
function LogWindow:RemoveMessagesByPredicate(func) end

--------------------------------------------------------------------------

-- Create the global log window object.
function WoWXIV.LogWindow.Create()
    if not WoWXIV_config["logwindow_enable"] then return end

    WoWXIV_logwindow_history = WoWXIV_logwindow_history or {}
    WoWXIV_logwindow_hist_top = WoWXIV_logwindow_hist_top or 1
    WoWXIV.LogWindow.PruneHistory()

    WoWXIV.LogWindow.window = LogWindow()
    if not KEEP_NATIVE_FRAME then
        WoWXIV.HideBlizzardFrame(GeneralDockManager)
        local index = 1
        while _G["ChatFrame"..index] do
            local frame = _G["ChatFrame"..index]
            WoWXIV.HideBlizzardFrame(frame)
            index = index + 1
        end
    end
    hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(frame, ...)
                       WoWXIV.LogWindow.window:AddMessage(...)
                   end)
end

-- Discard any log window history entries older than the current limit.
-- Also reorders the history buffer if needed for limit changes.
function WoWXIV.LogWindow.PruneHistory()
    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histsize = WoWXIV_config["logwindow_history"]
    if histlen > histsize or (histlen < histsize and WoWXIV_logwindow_hist_top ~= 1) then
        local new_history = {}
        local histindex = WoWXIV_logwindow_hist_top
        for i = 1, histsize do
            tinsert(new_history, history[histindex])
            histindex = (histindex == histlen) and 1 or histindex+1
        end
        WoWXIV_logwindow_history = new_history
        WoWXIV_logwindow_hist_top = 1
    end
end

-- Display a log message, optionally with an associated event tag.
-- Call as: LogWindow.AddMessage([event,] text [, color_r, color_g, color_b])
function WoWXIV.LogWindow.AddMessage(event, text, color_r, color_g, color_b)
    -- LogWindow:AddMessage() will take care of inserting a dummy event tag
    -- if needed.
    local window = WoWXIV.LogWindow.window
    if window then
        window:AddMessage(event, text, color_r, color_g, color_b)
    end
end
