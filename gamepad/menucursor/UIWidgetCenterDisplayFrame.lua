local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

-- This is the info popup frame for things like "Campaign Complete!"
-- notifications. (FIXME: untested)

local UIWidgetCenterDisplayFrameHandler = class(CoreMenuFrame)
Cursor.RegisterFrameHandler(UIWidgetCenterDisplayFrameHandler)

function UIWidgetCenterDisplayFrameHandler:__constructor()
    self:__super(UIWidgetCenterDisplayFrame)
    self.targets = {
        [UIWidgetCenterDisplayFrame.CloseButton] = {
            can_activate = true, lock_highlight = true, is_default = true},
    }
end
