local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local ProfessionsBookFrameHandler = class(MenuCursor.AddOnMenuFrame)
ProfessionsBookFrameHandler.ADDON_NAME = "Blizzard_ProfessionsBook"
MenuCursor.Cursor.RegisterFrameHandler(ProfessionsBookFrameHandler)

function ProfessionsBookFrameHandler:__constructor()
    __super(self, ProfessionsBookFrame)
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
                                    left = false, right = false}
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
            self.targets[button] = {can_activate = true, lock_highlight = true}
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
