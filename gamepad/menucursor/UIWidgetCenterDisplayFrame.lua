local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

-- This is the info popup frame for things like "Campaign Complete!"
-- notifications. (FIXME: untested)

local UIWidgetCenterDisplayFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(UIWidgetCenterDisplayFrameHandler)

function UIWidgetCenterDisplayFrameHandler:__constructor()
    __super(self, UIWidgetCenterDisplayFrame)
    self.targets = {
        [UIWidgetCenterDisplayFrame.CloseButton] = {
            can_activate = true, lock_highlight = true, is_default = true},
    }
end
