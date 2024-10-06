local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local WeeklyRewardsFrameHandler = class(AddOnMenuFrame)
WeeklyRewardsFrameHandler.ADDON_NAME = "Blizzard_WeeklyRewards"
Cursor.RegisterFrameHandler(WeeklyRewardsFrameHandler)

function WeeklyRewardsFrameHandler:__constructor()
    self:__super(WeeklyRewardsFrame)
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE")
end

function WeeklyRewardsFrameHandler:WEEKLY_REWARDS_UPDATE()
    -- The first time the player opens the vault in a week, CanClaimRewards()
    -- returns false when the frame is opened, and we receive this event a
    -- short time later when the reward data is updated.  We assume the
    -- player will not have moved the cursor in that time, and just refresh
    -- the target list from scratch.
    self:SetTargets()
    self:SetTarget(self:GetDefaultTarget())
end

function WeeklyRewardsFrameHandler:SetTargets()
    self.targets = {}
    if WeeklyRewardsFrame.Overlay and WeeklyRewardsFrame.Overlay:IsShown() then
        return  -- Prevent any menu input if the blocking overlay is up.
    end
    local can_claim = C_WeeklyRewards.CanClaimRewards()
    local row_y = {}
    local rows = {}
    for _, info in ipairs(C_WeeklyRewards.GetActivities()) do
        local frame = WeeklyRewardsFrame:GetActivityFrame(info.type, info.index)
        if frame and frame ~= WeeklyRewardsFrame.ConcessionFrame then
            local unlocked = can_claim and #info.rewards > 0
            local x = frame:GetLeft()
            local y = frame:GetTop()
            -- If a reward is available, we want to target the item itself
            -- rather than the activity box, but the activity box is still
            -- the frame that needs to get the click on activation.
            local target
            if unlocked then
                target = frame.ItemFrame
                self.targets[target] = {
                    send_enter_leave = true,
                    on_click = function()
                        frame:GetScript("OnMouseUp")(frame, "LeftButton", true)
                    end,
                }
            else
                target = frame
                self.targets[target] = {send_enter_leave = true}
            end
            if not rows[y] then
                rows[y] = {}
                tinsert(row_y, y)
            end
            tinsert(rows[y], {x, target})
        end
    end
    table.sort(row_y, function(a,b) return a > b end)
    local top_row = rows[row_y[1]]
    local bottom_row = rows[row_y[#row_y]]
    local n_columns = #top_row
    for _, row in pairs(rows) do
        assert(#row == n_columns)
        table.sort(row, function(a,b) return a[1] < b[1] end)
        local left = row[1][2]
        local right = row[n_columns][2]
        self.targets[left].left = right
        self.targets[right].right = left
    end
    local first = top_row[1][2]
    local bottom = bottom_row[1][2]
    self.targets[first].is_default = true
    if can_claim then
        local cf = WeeklyRewardsFrame.ConcessionFrame
        self.targets[cf] = {
            -- This is a bit awkward/hackish because the OnEnter/OnLeave
            -- handlers are attached to ConcessionFrame, but instead of
            -- just toggling the tooltip on and off, they set up an
            -- OnUpdate script which explicitly checks whether the mouse
            -- cursor is over RewardsFrame.
            on_enter = function()
                assert(self.CFRewardsFrame_IsMouseOver == nil)
                assert(cf.RewardsFrame.IsMouseOver)
                self.CFRewardsFrame_IsMouseOver = cf.RewardsFrame.IsMouseOver
                cf.RewardsFrame.IsMouseOver = function() return true end
                cf:GetScript("OnEnter")(cf)
            end,
            on_leave = function()
                assert(self.CFRewardsFrame_IsMouseOver)
                cf:GetScript("OnLeave")(cf)
                cf.RewardsFrame.IsMouseOver = self.CFRewardsFrame_IsMouseOver
                self.CFRewardsFrame_IsMouseOver = nil
            end,
            on_click = function()
                cf:GetScript("OnMouseDown")(cf)
            end,
            left = false, right = false, up = bottom}
        self.targets[WeeklyRewardsFrame.SelectRewardButton] = {
            can_activate = true, lock_highlight = true,
            left = false, right = false, down = first}
        for _, activity in ipairs(top_row) do
            local target = activity[2]
            self.targets[target].up = WeeklyRewardsFrame.SelectRewardButton
        end
    else
        for i = 1, n_columns do
            local top = top_row[i][2]
            local bottom = bottom_row[i][2]
            self.targets[top].up = bottom
            self.targets[bottom].down = top
        end
    end
end
