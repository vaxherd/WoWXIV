local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local SplashFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(SplashFrameHandler)

function SplashFrameHandler:__constructor()
    self:__super(SplashFrame)
end

function SplashFrameHandler:OnShow()
    -- If we're going straight into a cinematic (as for a new expansion or
    -- major patch), the frame won't be visible yet, so wait until the
    -- cinematic is done.
    if not self.frame:IsVisible() then
        -- Make sure we weren't dismissed in the meantime.
        if self.frame:IsShown() then
            RunNextFrame(function() self:OnShow() end)
        end
        return
    end
    MenuCursor.CoreMenuFrame.OnShow(self)
end

function SplashFrameHandler:SetTargets()
    self.targets = {}
    self:OnUpdate()
end

local CoreMenuFrame_OnUpdate = MenuCursor.CoreMenuFrame.OnUpdate
function SplashFrameHandler:OnUpdate(target_frame)
    CoreMenuFrame_OnUpdate(self, target_frame)
    local StartQuestButton = SplashFrame.RightFeature.StartQuestButton
    local BottomCloseButton = SplashFrame.BottomCloseButton
    if not self.targets[StartQuestButton] and StartQuestButton:IsVisible() then
        self.targets[StartQuestButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, is_default = true}
        if self.targets[BottomCloseButton] then
            self.targets[BottomCloseButton].is_default = false
            self.targets[BottomCloseButton].down = StartQuestButton
            self.targets[StartQuestButton].up = BottomCloseButton
        end
        self:SetTarget(StartQuestButton)
    end
    if not self.targets[BottomCloseButton] and BottomCloseButton:IsVisible() then
        self.targets[BottomCloseButton] =
            {can_activate = true, lock_highlight = true}
        if self.targets[StartQuestButton] then
            self.targets[BottomCloseButton].down = StartQuestButton
            self.targets[StartQuestButton].up = BottomCloseButton
        else
            self.targets[BottomCloseButton].is_default = true
            self:SetTarget(BottomCloseButton)
        end
    end
end
