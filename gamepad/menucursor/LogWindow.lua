local module_name, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local LogWindowHandler = class(MenuCursor.StandardMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(LogWindowHandler)

function LogWindowHandler.Initialize(class, cursor)
    class.cursor = cursor
    -- This is one of our own windows, so we know that if it's enabled, it
    -- will be available next frame.
    RunNextFrame(function()
        if WoWXIV_LogWindow then
            class.instance = class()
        end
    end)
end

function LogWindowHandler:__constructor()
    self:__super(WoWXIV_LogWindow)
    self.has_Button3 = true  -- Used to toggle fullscreen mode.
    -- HACK: the instance currently isn't a native frame
    self.targets = {[WoWXIV.LogWindow.window.tab_bar] = {is_default = true}}

    assert(self.frame:IsShown())
    self:EnableBackground()
end

function LogWindowHandler:OnAction(button)
    assert(button == "Button3")
    WoWXIV.LogWindow.window:ToggleFullscreen()
end
