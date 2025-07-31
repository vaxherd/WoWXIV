local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local ContributionCollectionFrameHandler = class(MenuCursor.AddOnMenuFrame)
ContributionCollectionFrameHandler.ADDON_NAME = "Blizzard_Contribution"
MenuCursor.Cursor.RegisterFrameHandler(ContributionCollectionFrameHandler)

function ContributionCollectionFrameHandler:__constructor()
    __super(self, ContributionCollectionFrame)
    -- We need to hook each contribution option's UpdateRewards() to
    -- refresh our target list because that method uses a release/recreate
    -- strategy which can change the order of reward icons.  This table
    -- saved which contribution options have been hooked so we don't add
    -- multiple hooks for a single frame.
    self.hooked_rewards = {}
end

function ContributionCollectionFrameHandler:SetTargets()
    local options = {}
    for option in ContributionCollectionFrame.contributionPool:EnumerateActive() do
        if not self.hooked_rewards[option] then
            self.hooked_rewards[option] = true
            hooksecurefunc(option, "UpdateRewards",
                           function() self:RefreshTargets() end)
        end
        local rewards = {}
        for _, icon in pairs(option.rewards) do
            tinsert(rewards, icon)
        end
        table.sort(rewards, function(a,b) return a:GetTop() > b:GetTop() end)
        tinsert(options, {frame = option,
                          rewards = rewards,
                          status = option.Status,
                          button = option.ContributeButton})
    end
    table.sort(options, function(a,b)
                            return a.button:GetLeft() < b.button:GetLeft()
                        end)

    self.targets = {}
    for i, option in ipairs(options) do
        local prev = i==1 and #options or i-1
        local next = i==#options and 1 or i+1
        prev = options[prev]
        next = options[next]
        self.targets[option.button] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true, is_default = i==1,
            up = option.status, down = option.status,
            left = prev.button, right = next.button}
        self.targets[option.status] = {
            send_enter_leave = true,
            up = option.button, down = option.button,
            left = prev.status, right = next.status}
        local reward_up = option.button
        for j, reward in ipairs(option.rewards) do
            self.targets[reward_up].down = reward
            self.targets[reward] = {
                -- Save option frame and reward index for RefreshTargets().
                _reward_option = option.frame, _reward_index = j,
                -- Uses a separate frame for enter/leave.
                on_enter = function(f)
                    f.MouseOver:GetScript("OnEnter")(f.MouseOver)
                end,
                on_leave = function(f)
                    f.MouseOver:GetScript("OnLeave")(f.MouseOver)
                end,
                up = reward_up, down = option.status,
                left = prev.rewards[j] or prev.rewards[1] or prev.status,
                right = next.rewards[j] or next.rewards[1] or next.status}
            self.targets[option.status].up = reward;
            reward_up = reward
        end
    end
end

function ContributionCollectionFrameHandler:RefreshTargets()
    local target = self:GetTarget()
    local reward_option = target and self.targets[target]._reward_option
    local reward_index = target and self.targets[target]._reward_index
    self:SetTargets()
    if reward_option then
        for target, params in pairs(self.targets) do
            if (params._reward_option == reward_option
                and params._reward_index == reward_index)
            then
                self:SetTarget(target)
                break
            end
        end
    end
end
