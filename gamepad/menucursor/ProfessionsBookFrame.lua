local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local SPELL_FISHING_CAST = 131474
local SPELL_FISHING_AURA = 131476

---------------------------------------------------------------------------

local ProfessionsBookFrameHandler = class(MenuCursor.AddOnMenuFrame)
ProfessionsBookFrameHandler.ADDON_NAME = "Blizzard_ProfessionsBook"
MenuCursor.Cursor.RegisterFrameHandler(ProfessionsBookFrameHandler)

function ProfessionsBookFrameHandler:__constructor()
    __super(self, ProfessionsBookFrame)

    -- For suspending the menu cursor while fishing, to allow a confirm
    -- button press to hook a fish.
    self.paused_for_fishing = true
    -- NOTE: The aura applied while fishing (SPELL_FISHING_AURA) seems
    -- to be unavailable via C_UnitAuras, and can only be obtained via
    -- combat log events.
    --self:RegisterUnitEvent("UNIT_AURA", "player")
    WoWXIV.CombatLogManager.RegisterEvent(self, self.SPELL_AURA_APPLIED,
                                          "SPELL_AURA_APPLIED")
    WoWXIV.CombatLogManager.RegisterEvent(self, self.SPELL_AURA_REMOVED,
                                          "SPELL_AURA_REMOVED")
end

-- Helper for SetTargets(), since the profession buttons for e.g. fishing
-- (which is the particular one we're interested in) don't directly
-- include their respective spell IDs in the frame object.
function GetButtonSpellID(button)
    local slot = ProfessionsBook_GetSpellBookItemSlot(button)
    if slot then
        local type, _, spell = C_SpellBook.GetSpellBookItemType(
            slot, Enum.SpellBookSpellBank.Player)
        if type == Enum.SpellBookItemType.Spell then
            return spell
        end
    end
    return nil
end

local PROFESSION_BUTTONS_P = {
    "PrimaryProfession1SpellButtonTop",
    "PrimaryProfession1SpellButtonBottom",
    "PrimaryProfession2SpellButtonTop",
    "PrimaryProfession2SpellButtonBottom",
}
local PROFESSION_BUTTONS_S = {
    "SecondaryProfession1SpellButtonLeft",
    "SecondaryProfession1SpellButtonRight",
    "SecondaryProfession2SpellButtonLeft",
    "SecondaryProfession2SpellButtonRight",
    "SecondaryProfession3SpellButtonLeft",
    "SecondaryProfession3SpellButtonRight",
}
function ProfessionsBookFrameHandler:SetTargets()
    self.targets = {}
    local initial, top_l, top_r, bottom_l, bottom_r
    for _, bname in ipairs(PROFESSION_BUTTONS_P) do
        local button = _G[bname]
        assert(button)
        if button:IsShown() then
            self.targets[button] = {can_activate = true, lock_highlight = true,
                                    left = false, right = false,
                                    spell_id = GetButtonSpellID(button)}
            if not initial then
                self.targets[button].is_default = true
                initial = button
                top_l = button
                top_r = button
            end
            bottom_l = button
            bottom_r = button
        end
    end
    local bottom_primary = bottom_l
    local first_secondary = nil
    for _, bname in ipairs(PROFESSION_BUTTONS_S) do
        local button = _G[bname]
        assert(button)
        if button:IsShown() then
            self.targets[button] = {can_activate = true, lock_highlight = true,
                                    spell_id = GetButtonSpellID(button)}
            if not initial then
                self.targets[button].is_default = true
                initial = button
            end
            if not first_secondary then
                first_secondary = button
            end
            if button:GetTop() == first_secondary:GetTop() then
                self.targets[button].up = bottom_primary
            end
            if not bottom_l or button:GetTop() < bottom_l:GetTop() then
                bottom_l = button
            end
            if not bottom_r or button:GetTop() == bottom_l:GetTop() then
                bottom_r = button
            end
        end
    end
    if top_l then
        self.targets[top_l].up = bottom_l
        self.targets[top_r].up = bottom_r
        self.targets[bottom_l].down = top_l
        self.targets[bottom_r].down = top_r
    end
end

function ProfessionsBookFrameHandler:OnFocus()
    self.paused_for_fishing = false
end

function ProfessionsBookFrameHandler:SPELL_AURA_APPLIED(event)
    if event.source == UnitGUID("player")
    and event.spell_id == SPELL_FISHING_AURA
    then
        self.cursor:SetFocus(nil)
        self.paused_for_fishing = true
    end
end

function ProfessionsBookFrameHandler:SPELL_AURA_REMOVED(event)
    if self.paused_for_fishing
    and event.source == UnitGUID("player")
    and event.spell_id == SPELL_FISHING_AURA
    then
        self.paused_for_fishing = false
        self.cursor:SetFocus(self)
    end
end

-- NOTE: currently unused (see notes in constructor).  Kept in case we
-- can use this check in the future (or have to, post-12.0.0).
function ProfessionsBookFrameHandler:UNIT_AURA(info)
    if self.paused_for_fishing then

        local is_fishing = false
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i)
            if not aura then break end
            if aura.spellId == SPELL_FISHING_AURA then
                is_fishing = true
                break
            end
        end
        if not is_fishing then
            self.paused_for_fishing = false
            self.cursor:SetFocus(self)
        end

    else  -- not paused for fishing

        if not self:HasFocus() then return end
        local target = self:GetTarget()
        if not target then return end
        if self.targets[target].spell_id ~= SPELL_FISHING_CAST then return end

        local started_fishing
        if not info or info.isFullUpdate then
            for i = 1, 40 do
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i)
                if not aura then break end
                if aura.spellId == SPELL_FISHING_AURA then
                    started_fishing = true
                    break
                end
            end
        elseif info.addedAuras then
            for _, aura in ipairs(info.addedAuras) do
                if aura.spellId == SPELL_FISHING_AURA then
                    started_fishing = true
                    break
                end
            end
        end
        if started_fishing then
            self.cursor:SetFocus(nil)
            self.paused_for_fishing = true
        end

    end  -- if paused for fishing
end
