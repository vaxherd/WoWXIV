local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local BonusRollFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(BonusRollFrameHandler)

function BonusRollFrameHandler:__constructor()
    self:__super(BonusRollFrame)
    local f = self.frame.PromptFrame
    self.cancel_button = f.PassButton
    local function DisableSelf() self:Disable() end
    self.targets = {
        [f.RollButton] = {can_activate = true, on_click = DisableSelf,
                          lock_highlight = true,
                          send_enter_leave = true},
        [f.PassButton] = {can_activate = true, on_click = DisableSelf,
                          lock_highlight = true, send_enter_leave = true,
                          is_default = true},
    }
end
