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

local QuestFrameHandler = class(CoreMenuFrame)
Cursor.RegisterFrameHandler(QuestFrameHandler)

function QuestFrameHandler:__constructor()
    self:__super(QuestFrame)
    self.cancel_func = CloseQuest
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_DETAIL")
    self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")
end

-- Suppress the normal show callback in favor of event-specific versions.
function QuestFrameHandler:OnShow()
    -- No-op.
end

function QuestFrameHandler:QUEST_GREETING()
    assert(QuestFrame:IsVisible())  -- FIXME: might be false if previous quest turn-in started a cutscene (e.g. The Underking Comes in the Legion Highmountain scenario)
    self:SetTargets("QUEST_GREETING")
    self:Enable()
end

function QuestFrameHandler:QUEST_DETAIL()
    -- FIXME: some map-based quests (e.g. Blue Dragonflight campaign)
    -- start a quest directly from the map; we should support those too
    if not QuestFrame:IsVisible() then return end
    self:SetTargets("QUEST_DETAIL")
    self:Enable()
end

function QuestFrameHandler:QUEST_PROGRESS()
    assert(QuestFrame:IsVisible())
    self:SetTargets("QUEST_PROGRESS")
    self:Enable()
end

function QuestFrameHandler:QUEST_COMPLETE()
    -- Quest frame can fail to open under some conditions?
    if not QuestFrame:IsVisible() then return end
    self:SetTargets("QUEST_COMPLETE")
    self:Enable()
end

function QuestFrameHandler:SetTargets(event)
    if event == "QUEST_GREETING" then
        local goodbye = QuestFrameGreetingGoodbyeButton
        self.targets = {[goodbye] = {can_activate = true,
                                     lock_highlight = true}}
        local first_button, last_button, first_avail
        local avail_y = (AvailableQuestsText:IsShown()
                         and AvailableQuestsText:GetTop())
        for button in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            local y = button:GetTop()
            if not first_button then
                first_button = button
                last_button = button
            else
                if y > first_button:GetTop() then first_button = button end
                if y < last_button:GetTop() then last_button = button end
            end
            if avail_y and y < avail_y then
                if not first_avail or y > first_avail:GetTop() then
                    first_avail = button
                end
            end
        end
        self.targets[first_avail or first_button or goodbye].is_default = true

    elseif event == "QUEST_PROGRESS" then
        local can_complete = QuestFrameCompleteButton:IsEnabled()
        self.targets = {
            [QuestFrameCompleteButton] = {can_activate = true,
                                          lock_highlight = true,
                                          is_default = can_complete},
            [QuestFrameGoodbyeButton] = {can_activate = true,
                                         lock_highlight = true,
                                         is_default = not can_complete},
        }
        for i = 1, 99 do
            local name = "QuestProgressItem" .. i
            local item_frame = _G[name]
            if not item_frame or not item_frame:IsShown() then break end
            self.targets[item_frame] = {send_enter_leave = true}
        end

    else  -- DETAIL or COMPLETE
        local is_complete = (event == "QUEST_COMPLETE")
        local button1, button2
        if is_complete then
            self.targets = {
                [QuestFrameCompleteQuestButton] = {
                    up = false, down = false, left = false, right = false,
                    can_activate = true, lock_highlight = true,
                    is_default = true}
            }
            button1 = QuestFrameCompleteQuestButton
            button2 = nil
        else
            self.targets = {
                [QuestFrameAcceptButton] = {
                    up = false, down = false, left = false,
                    right = QuestFrameDeclineButton,
                    can_activate = true, lock_highlight = true,
                    is_default = true},
                [QuestFrameDeclineButton] = {
                    up = false, down = false, right = false,
                    left = QuestFrameAcceptButton,
                    can_activate = true, lock_highlight = true},
            }
            button1 = QuestFrameAcceptButton
            button2 = QuestFrameDeclineButton
        end
        local rewards = {}
        if QuestInfoSkillPointFrame:IsVisible() then
            tinsert(rewards, {QuestInfoSkillPointFrame, false})
        end
        for i = 1, 99 do
            local name = "QuestInfoRewardsFrameQuestInfoItem" .. i
            local reward_frame = _G[name]
            if not reward_frame or not reward_frame:IsShown() then break end
            tinsert(rewards, {reward_frame, true})
        end
        for reward_frame in QuestInfoRewardsFrame.spellRewardPool:EnumerateActive() do
            tinsert(rewards, {reward_frame, false})
        end
        for reward_frame in QuestInfoRewardsFrame.reputationRewardPool:EnumerateActive() do
            tinsert(rewards, {reward_frame, false})
        end
        for i, v in ipairs(rewards) do
            local frame = v[1]
            tinsert(rewards[i], frame:GetLeft())
            tinsert(rewards[i], frame:GetTop())
        end
        table.sort(rewards, function(a, b)
            return a[4] > b[4] or (a[4] == b[4] and a[3] < b[3])
        end)
        local last_l, last_r, this_l
        for _, v in ipairs(rewards) do
            local reward_frame, is_item = unpack(v)
            self.targets[reward_frame] = {
                up = false, down = false, left = false, right = false,
                can_activate = is_item, send_enter_leave = true,
                scroll_frame = (is_complete and QuestRewardScrollFrame
                                             or QuestDetailScrollFrame),
            }
            if this_l and reward_frame:GetTop() == this_l:GetTop() then
                -- Item is in the right column.
                if last_r then
                    self.targets[last_r].down = reward_frame
                    self.targets[reward_frame].up = last_r
                elseif last_l then
                    self.targets[reward_frame].up = last_l
                end
                self.targets[this_l].right = reward_frame
                self.targets[reward_frame].left = this_l
                last_l, last_r = this_l, reward_frame
                this_l = nil
            else
                -- Item is in the left column.
                if this_l then
                    last_l, last_r = this_l, nil
                end
                if last_l then
                    self.targets[last_l].down = reward_frame
                    self.targets[reward_frame].up = last_l
                end
                if last_r then
                    -- This will be overwritten if we find another item
                    -- on the same line.
                    self.targets[last_r].down = reward_frame
                end
                this_l = reward_frame
            end
        end
        if this_l then
            last_l, last_r = this_l, nil
        end
        if last_l then
            self.targets[last_l].down = button1
            self.targets[button1].up = last_l
            if button2 then
                self.targets[button2].up = last_l
            end
        end
        if last_r then
            self.targets[last_r].down = button2 or button1
            if button2 then
                self.targets[button2].up = last_r
            end
        end
    end
end
