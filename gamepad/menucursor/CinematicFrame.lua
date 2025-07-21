local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local CinematicFrameHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(CinematicFrameHandler)
local CinematicFrameCloseDialogHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(CinematicFrameCloseDialogHandler)


function CinematicFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
end

function CinematicFrameHandler:__constructor()
    self:__super(CinematicFrame, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = function() self:OnCancel() end
    self.cursor_parent_override = CinematicFrame
    self:RegisterEvent("CINEMATIC_START")
    self:RegisterEvent("CINEMATIC_STOP")
    -- It seems that the game client blocks events to all other frames
    -- at a lower level than we can access while CinematicFrame is active
    -- (unlike MovieFrame, with which cursor control works normally).
    -- In order to get the cursor working here, we have to hook into
    -- CinematicFrame and forward relevant input events to the cursor
    -- manually.  We don't bother with the full set of actions because
    -- we only need a few for this particular dialog.
    self.frame:HookScript("OnGamePadButtonDown", function(_, button)
        local action
        if button == "PADDLEFT" then
            action = "DPadLeft"
        elseif button == "PADDRIGHT" then
            action = "DPadRight"
        elseif button == WoWXIV.Config.GamePadConfirmButton() then
            action = "LeftButton"
        elseif button == WoWXIV.Config.GamePadCancelButton() then
            action = "Cancel"
        end
        if action then
            self.cursor:OnClick(action, true)
            self.cursor:OnClick(action, false)
        end
    end)
end

function CinematicFrameHandler:CINEMATIC_START()
    self:Enable()
end

function CinematicFrameHandler:CINEMATIC_STOP()
    self:Disable()
end

function CinematicFrameHandler:OnCancel()
    -- This is a bit of a hack because the logic to check whether to show
    -- the cancel dialog is encapsulated inside the OnKeyDown handler, and
    -- that handler checks for the TOGGLEGAMEMENU action rather than a
    -- literal ESCAPE or other key.  We pass ESCAPE anyway just on principle.
    local env = {GetBindingFromClick = function() return "TOGGLEGAMEMENU" end}
    setmetatable(env, {__index = _G})
    WoWXIV.envcall(env, CinematicFrame_OnKeyDown, self.frame, "ESCAPE")
end


function CinematicFrameCloseDialogHandler:__constructor()
    self:__super(CinematicFrameCloseDialog, MenuCursor.MenuFrame.MODAL)
    -- Ideally we'd use confirm/cancel passthrough on these buttons, but
    -- since we have to (insecurely) send events to the cursor manually
    -- (see notes above), we're forced to use on_click and cancel_func
    -- instead.
    self.cancel_func = function()
        CinematicFrameCloseDialogResumeButton:Click("LeftButton")
    end
    self.cursor_parent_override = CinematicFrame
    self.targets = {
        [CinematicFrameCloseDialogConfirmButton] =
            {on_click = function(button) button:Click("LeftButton") end,
             lock_highlight = true, is_default = true,
             left = CinematicFrameCloseDialogResumeButton,
             right = CinematicFrameCloseDialogResumeButton},
        [CinematicFrameCloseDialogResumeButton] =
            {on_click = function(button) button:Click("LeftButton") end,
             lock_highlight = true,
             left = CinematicFrameCloseDialogConfirmButton,
             right = CinematicFrameCloseDialogConfirmButton}
    }
end
