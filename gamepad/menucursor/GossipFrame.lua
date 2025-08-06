local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local GossipFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(GossipFrameHandler)

function GossipFrameHandler:__constructor()
    __super(self, GossipFrame)
    self.allow_repeat_show = true
    self:RegisterEvent("GOSSIP_SHOW")
    self:RegisterEvent("GOSSIP_CONFIRM_CANCEL")
end

-- Rather than responding to Show calls, we use this event to ensure that
-- we appropriately update targets each time the content changes.
function GossipFrameHandler:OnShow()
    -- No-op.
end
function GossipFrameHandler:GOSSIP_SHOW()
    MenuCursor.CoreMenuFrame.OnShow(self)
end

function GossipFrameHandler:GOSSIP_CONFIRM_CANCEL()
    -- Clear all targets to prevent further inputs until the next event
    -- (typically GOSSIP_SHOW or GOSSIP_CLOSED).
    self:ClearTarget()
    self.targets = {}
end

function GossipFrameHandler:SetTargets()
    self:ClearTarget() -- In case the frame is already open.

    local goodbye = GossipFrame.GreetingPanel.GoodbyeButton
    self.targets = {[goodbye] = {can_activate = true,
                                 lock_highlight = true}}
    local up_target, down_target = goodbye, goodbye
    if GossipFrame.FriendshipStatusBar:IsShown() then
        up_target = GossipFrame.FriendshipStatusBar
        self.targets[GossipFrame.FriendshipStatusBar] =
            {send_enter_leave = true, up = goodbye}
        self.targets[goodbye].down = GossipFrame.FriendshipStatusBar
    end

    local GossipScroll = GossipFrame.GreetingPanel.ScrollBox
    local top, bottom = self:AddScrollBoxTargets(GossipScroll, function(data)
        if data.availableQuestButton or data.activeQuestButton
                                     or data.titleOptionButton then
            return {can_activate = true, lock_highlight = true}
        end
    end)
    if top then
        self.targets[top].up = up_target
        self.targets[up_target].down = top
    else
        bottom = up_target
    end
    self.targets[bottom].down = goodbye
    self.targets[goodbye].up = bottom

    -- If the frame is scrollable and also has selectable options, default
    -- to the "goodbye" button to ensure that we start at the top of the
    -- scrollable text (rather than automatically scrolling to the bottom
    -- where the options are).  But we treat an extremely tiny scroll range
    -- as zero, as for the right stick scrolling logic.
    if GossipScroll:GetDerivedScrollRange() > 0.01 then
        top = nil
    end

    local default_target = top or goodbye
    self.targets[default_target].is_default = true
    return default_target
end
