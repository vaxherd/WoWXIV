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
    __super(self, WoWXIV_LogWindow, MenuCursor.MenuFrame.NOAUTOFOCUS)
    self.cancel_func = function() self:OnCancel() end
    self.on_prev_page = function() self.frame.tab_bar:PrevTab() end
    self.on_next_page = function() self.frame.tab_bar:NextTab() end
    self.has_Button3 = true  -- Used to toggle fullscreen mode.
    self.targets = {[self.frame.tab_bar] = {is_default = true}}

    assert(self.frame:IsShown())
    self:EnableBackground()
end

function LogWindowHandler:OnCancel()
    self:Unfocus()
end

function LogWindowHandler:OnUnfocus()
    self.frame:ToggleFullscreen(false)
end

function LogWindowHandler:OnAction(button)
    assert(button == "Button3")
    self.frame:ToggleFullscreen()
end
