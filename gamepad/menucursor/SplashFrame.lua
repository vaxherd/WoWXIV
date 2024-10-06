local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

local SplashFrameHandler = class(CoreMenuFrame)
Cursor.RegisterFrameHandler(SplashFrameHandler)

function SplashFrameHandler:__constructor()
    self:__super(SplashFrame)
end

function SplashFrameHandler:SetTargets()
    self.targets = {}
    local StartQuestButton = SplashFrame.RightFeature.StartQuestButton
    if StartQuestButton:IsVisible() then
        self.targets[StartQuestButton] =
            {can_activate = true, send_enter_leave = true, is_default = true}
    end
end
