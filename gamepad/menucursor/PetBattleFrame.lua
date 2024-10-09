local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local PetBattleFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(PetBattleFrameHandler)
local PetBattlePetSelectionFrameHandler = class(MenuCursor.StandardMenuFrame)

function PetBattleFrameHandler.Initialize(class, cursor)
    MenuCursor.CoreMenuFrame.Initialize(class, cursor)
    class.instance_PetSelection = PetBattlePetSelectionFrameHandler()
    -- If we're in the middle of a pet battle, these might already be active!
    if PetBattleFrame:IsVisible() then
        class.instance:OnShow()
    end
    if PetBattleFrame.BottomFrame.PetSelectionFrame:IsVisible() then
        class.instance_PetSelection:OnShow()
    end
end

function PetBattleFrameHandler:__constructor()
    self:__super(PetBattleFrame)
    self.cancel_func = function()
        self:SetTarget(PetBattleFrame.BottomFrame.ForfeitButton)
    end
end

function PetBattleFrameHandler:OnShow()
    -- Buttons may not be available immediately, so wait if necessary.
    -- The pet swap button is shown before the first pet is loaded, so
    -- wait for one of the primary action buttons instead of just any button.
    local bf = PetBattleFrame.BottomFrame
    if (bf.abilityButtons and bf.abilityButtons[3]
        and (bf.abilityButtons[1]:IsVisible() or
             bf.abilityButtons[2]:IsVisible() or
             bf.abilityButtons[3]:IsVisible()))
    then
        local initial_target = self:SetTargets(nil)
        self:Enable(initial_target)
    else
        RunNextFrame(function() self:OnShow() end)
    end
end

-- FIXME: For a short time when switching a new pet in, the new pet's
-- action buttons are not shown but the cursor can still move across them.
-- Should suppress input for that interval.

function PetBattleFrameHandler:SetTargets(initial_target)
    local bf = PetBattleFrame.BottomFrame

    local button1 = bf.abilityButtons[1]
    local button2 = bf.abilityButtons[2]
    local button3 = bf.abilityButtons[3]
    local button4 = bf.SwitchPetButton
    local button5 = bf.CatchButton
    local button6 = bf.ForfeitButton
    local button_pass = bf.TurnTimer.SkipButton
    if button1 and not button1:IsVisible() then print("foo") button1 = nil end
    if button2 and not button2:IsVisible() then button2 = nil end
    if button3 and not button3:IsVisible() then button3 = nil end

    local first_action = button1 or button2 or button3 or button4
    local last_action = button3 or button2 or button1 or button6
    self.targets = {
        [button4] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = last_action, right = button5},
        [button5] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button4, right = button6},
        [button6] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button5, right = first_action},
        [button_pass] = {
            can_activate = true, lock_highlight = true,
            up = first_action, down = first_action,
            left = false, right = false},
    }
    if button1 then
        self.targets[button1] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button6, right = button2 or button3 or button4}
    end
    if button2 then
        self.targets[button2] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button1 or button6, right = button3 or button4}
    end
    if button3 then
        self.targets[button3] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button2 or button1 or button6, right = button4}
    end

    if self.targets[initial_target] then
        return initial_target
    else
        return first_action
    end
end


function PetBattlePetSelectionFrameHandler:__constructor()
    local psf = PetBattleFrame.BottomFrame.PetSelectionFrame
    self:__super(psf, self.MODAL)
    self.cancel_func = nil
end

function PetBattlePetSelectionFrameHandler:OnShow()
    local initial_target = self:SetTargets()
    self:Enable(initial_target)
end

function PetBattlePetSelectionFrameHandler:SetTargets()
    self.targets = {}
    local psf = PetBattleFrame.BottomFrame.PetSelectionFrame
    local first, last, initial
    for _, button in ipairs({psf.Pet1, psf.Pet2, psf.Pet3}) do
        if button:IsShown() then
            self.targets[button] =
                {can_activate = true, send_enter_leave = true,
                 up = false, down = false}
            first = first or button
            last = button
            if not initial and C_PetBattles.CanPetSwapIn(button.petIndex) then
                initial = button
            end
        end
    end
    if first then
        self.targets[first].left = last
        self.targets[last].right = first
    end
    return initial or first
end
