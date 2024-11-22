local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local LFGListInviteDialogHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(LFGListInviteDialogHandler)

function LFGListInviteDialogHandler:__constructor()
    self:__super(LFGListInviteDialog, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
end

function LFGListInviteDialogHandler:SetTargets()
    if LFGListInviteDialog.AcknowledgeButton:IsShown() then
        self.targets = {
            [LFGListInviteDialog.AcknowledgeButton] = {
                can_activate = true, lock_highlight = true, is_default = true},
        }
    else
        self.targets = {
            [LFGListInviteDialog.AcceptButton] = {
                can_activate = true, lock_highlight = true, is_default = true},
            [LFGListInviteDialog.DeclineButton] = {
                can_activate = true, lock_highlight = true},
        }
    end
end
