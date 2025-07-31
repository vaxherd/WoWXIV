local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local MajorFactionRenownFrameHandler = class(MenuCursor.AddOnMenuFrame)
MajorFactionRenownFrameHandler.ADDON_NAME = "Blizzard_MajorFactions"
MenuCursor.Cursor.RegisterFrameHandler(MajorFactionRenownFrameHandler)

function MajorFactionRenownFrameHandler:__constructor()
    __super(self, MajorFactionRenownFrame)
    self.cancel_func = nil
    self.cancel_button = self.frame.CloseButton
    hooksecurefunc(self.frame, "SetRewards",
                   function() self:RefreshTargets() end)
end

function MajorFactionRenownFrameHandler:RefreshTargets()
    local target = self:GetTarget()
    assert(not target or target == self.frame.TrackFrame)
    self:SetTargets()
end

function MajorFactionRenownFrameHandler:SetTargets()
    local f = self.frame
    self.targets = {
        [f.TrackFrame] = {is_default = true, dpad_override = true}
    }
    -- Prevent moving to the rewards during level-up animations to preserve
    -- the invariant that the cursor is always on the reward track frame
    -- when the reward list changes.
    if f.displayLevel < f.actualLevel then
        return
    end
    local top, bottom
    for reward in f.rewardsPool:EnumerateActive() do
        self.targets[reward] = {send_enter_leave = true}
        if not top or reward:GetTop() > top:GetTop() or (reward:GetTop() == top:GetTop() and reward:GetLeft() < top:GetLeft()) then
            top = reward
        end
        if not bottom or reward:GetTop() < bottom:GetTop() or (reward:GetTop() == bottom:GetTop() and reward:GetLeft() < bottom:GetLeft()) then
            bottom = reward
        end
    end
    self.targets[f.TrackFrame].down = top
    self.targets[f.TrackFrame].up = bottom
    if bottom then
        for target, params in pairs(self.targets) do
            if target:GetTop() == bottom:GetTop() then
                params.down = f.TrackFrame
            end
        end
    end
end

function MajorFactionRenownFrameHandler:OnDPad(dir)
    local f = self.frame
    assert(self:GetTarget() == f.TrackFrame)
    if f.displayLevel < f.actualLevel then
        f.LevelSkipButton:OnClick()
    elseif dir == "left" then
        f:OnMouseWheel(1)
    elseif dir == "right" then
        f:OnMouseWheel(-1)
    else
        self:SetTarget(self.targets[f.TrackFrame][dir])
    end
end
