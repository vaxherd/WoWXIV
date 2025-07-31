local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local LFGDungeonReadyDialogHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(LFGDungeonReadyDialogHandler)

function LFGDungeonReadyDialogHandler:__constructor()
    __super(self, LFGDungeonReadyDialog, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
    self.cancel_button = LFGDungeonReadyDialogCloseButton
    self.targets = {
        [LFGDungeonReadyDialogEnterDungeonButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            left = LFGDungeonReadyDialogLeaveQueueButton,
            right = LFGDungeonReadyDialogLeaveQueueButton},
        [LFGDungeonReadyDialogLeaveQueueButton] = {
            can_activate = true, lock_highlight = true,
            left = LFGDungeonReadyDialogEnterDungeonButton,
            right = LFGDungeonReadyDialogEnterDungeonButton},
    }

    -- This is implemented as a subframe of a higher-level dialog frame
    -- (LFGDungeonReadyPopup, which also shows the player ready state),
    -- and this subframe can be shown before the parent, so we need to
    -- catch OnShow() for both.
    self:HookShow(LFGDungeonReadyPopup)
end

function LFGDungeonReadyDialogHandler:OnShow() --FIXME needed?
    if self.frame:IsVisible() then  -- See note in constructor.
        __super(self)
    end
end
