local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

local GossipFrameHandler = class(MenuFrame)
Cursor.RegisterFrameHandler(GossipFrameHandler)

function GossipFrameHandler.Initialize(class, cursor)
    local instance = class()
    class.instance = instance
    instance:RegisterEvent("GOSSIP_CLOSED")
    instance:RegisterEvent("GOSSIP_CONFIRM_CANCEL")
    instance:RegisterEvent("GOSSIP_SHOW")
end

function GossipFrameHandler:__constructor()
    self:__super(GossipFrame)
    self.cancel_func = MenuFrame.CancelUIFrame
end

function GossipFrameHandler:GOSSIP_SHOW()
    if not GossipFrame:IsVisible() then
        return  -- Flight map, etc.
    end
    local initial_target = self:SetTargets()
    self:Enable(initial_target)
end

function GossipFrameHandler:GOSSIP_CONFIRM_CANCEL()
    -- Clear all targets to prevent further inputs until the next event
    -- (typically GOSSIP_SHOW or GOSSIP_CLOSED).
    self:ClearTarget()
    self.targets = {}
end

function GossipFrameHandler:GOSSIP_CLOSED()
    self:Disable()
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
    local first = nil
    local last = up_target
    -- Avoid errors in Blizzard code if the list is empty.
    if GossipScroll:GetDataProvider() then
        local index = 0
        GossipScroll:ForEachElementData(function(data)
            index = index + 1
            if (data.availableQuestButton or
                data.activeQuestButton or
                data.titleOptionButton)
            then
                local pseudo_frame =
                    MenuFrame.PseudoFrameForScrollElement(GossipScroll, index)
                self.targets[pseudo_frame] = {
                    is_scroll_box = true, can_activate = true,
                    lock_highlight = true, up = last, down = down_target}
                self.targets[last].down = pseudo_frame
                if not first then first = pseudo_frame end
                last = pseudo_frame
            end
        end)
    end
    self.targets[last].down = goodbye
    self.targets[goodbye].up = last

    -- If the frame is scrollable and also has selectable options, default
    -- to the "goodbye" button to ensure that we start at the top of the
    -- scrollable text (rather than automatically scrolling to the bottom
    -- where the options are).  But we treat an extremely tiny scroll range
    -- as zero, as for the right stick scrolling logic.
    if GossipScroll:GetDerivedScrollRange() > 0.01 then
        first = nil
    end

    local default_target = first or goodbye
    self.targets[default_target].is_default = true
    return default_target
end
