local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local SplashFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(SplashFrameHandler)

function SplashFrameHandler:__constructor()
    __super(self, SplashFrame)
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
    __super(self)
end

function SplashFrameHandler:OnHide()
    __super(self)
    -- Suppress the default behavior of (re)opening the game menu after
    -- closing the splash frame, since we don't use that menu with gamepad.
    -- (Properly speaking, this ought to be part of the command menu, but
    -- we don't worry about that for now.)
    HideUIPanel(GameMenuFrame)
end

function SplashFrameHandler:SetTargets()
    self.targets = {}
    self:OnUpdate()
end

function SplashFrameHandler:OnUpdate(target_frame)
    __super(self, target_frame)
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
