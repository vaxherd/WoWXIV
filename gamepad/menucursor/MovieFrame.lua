local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local MovieFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(MovieFrameHandler)
local MovieFrameCloseDialogHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(MovieFrameCloseDialogHandler)


-- We need this "wrapper" handler because Blizzard code doesn't know
-- what to do with gamepad button inputs, and if we press the cancel
-- button we can actually get the UI displayed again.
function MovieFrameHandler:__constructor()
    self:__super(MovieFrame, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = function() self.frame.CloseDialog:Show() end
end


function MovieFrameCloseDialogHandler:__constructor()
    self:__super(MovieFrame.CloseDialog, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
    self.cancel_button = MovieFrame.CloseDialog.ResumeButton
    self.cursor_parent_override = MovieFrame
    self.targets = {
        [MovieFrame.CloseDialog.ConfirmButton] =
            {can_activate = true, lock_highlight = true, is_default = true,
             left = MovieFrame.CloseDialog.ResumeButton,
             right = MovieFrame.CloseDialog.ResumeButton},
        [MovieFrame.CloseDialog.ResumeButton] =
            {can_activate = true, lock_highlight = true,
             left = MovieFrame.CloseDialog.ConfirmButton,
             right = MovieFrame.CloseDialog.ConfirmButton},
    }
end
