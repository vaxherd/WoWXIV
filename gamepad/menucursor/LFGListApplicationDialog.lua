local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local LFGListApplicationDialogHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(LFGListApplicationDialogHandler)

function LFGListApplicationDialogHandler:__constructor()
    __super(self, LFGListApplicationDialog, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
    self.cancel_button = self.frame.CancelButton
end

function LFGListApplicationDialogHandler:SetTargets()
    local f = self.frame
    self.targets = {
        [f.Description] = {
            on_click = MenuCursor.MenuFrame.ClickToMouseDown,
            down = f.SignUpButton, left = false, right = false},
        [f.SignUpButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            up = f.Description, left = f.CancelButton, right = f.CancelButton},
        [f.CancelButton] = {
            can_activate = true, lock_highlight = true,
            up = f.Description, left = f.SignUpButton, right = f.SignUpButton},
    }
    local role_buttons = {f.HealerButton, f.TankButton, f.DamagerButton}
    local first_role, prev_role
    for _, button in ipairs(role_buttons) do
        if button:IsShown() then
            button = button.CheckButton
            self.targets[button] = {
                can_activate = true,
                up = f.SignUpButton, down = f.Description, left = prev_role}
            if prev_role then
                self.targets[prev_role].right = button
            end
            first_role = first_role or button
            prev_role = button
        end
    end
    if first_role then
        self.targets[first_role].left = prev_role
        self.targets[prev_role].right = first_role
        self.targets[f.SignUpButton].down = first_role
        self.targets[f.CancelButton].down = prev_role
        if prev_role ~= first_role then
            self.targets[prev_role].up = f.CancelButton
        end
    end
end
