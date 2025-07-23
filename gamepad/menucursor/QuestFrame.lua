local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local QuestFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(QuestFrameHandler)

function QuestFrameHandler:__constructor()
    self:__super(QuestFrame)
    self.cancel_func = CloseQuest
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_DETAIL")
    self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")
    -- QuestFrame uses QUEST_LOG_UPDATE to refresh the quest list in the
    -- greeting panel; if multiple quests are listed, this can cause
    -- different subframes to be reallocated to each quest even if the
    -- list itself is unchanged, which would result in the cursor
    -- spontaneously changing position.  We could catch the same event,
    -- but the order of operations would be undefined with respect to
    -- QuestFrame itself, so instead we hook into the update function.
    hooksecurefunc("QuestFrameGreetingPanel_OnShow",
                   function() self:RefreshGreeting() end)
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

function QuestFrameHandler:RefreshGreeting()
    local saved_id = self.cur_id
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets("QUEST_GREETING", saved_id))
end

function QuestFrameHandler:EnterTarget(target)
    MenuCursor.CoreMenuFrame.EnterTarget(self, target)
    -- If in the greeting frame, save the ID of the currently selected quest
    -- so we can preserve it across subframe reallocation (see notes in
    -- constructor).
    if QuestFrameGreetingPanel:IsVisible() then
        self.cur_id = target:GetID()
    end
end

function QuestFrameHandler:QUEST_DETAIL()
    -- Some map-based quests (e.g. Blue Dragonflight campaign) start a
    -- quest directly from the map without opening QuestFrame, so don't
    -- blindly assume the frame is open.
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

function QuestFrameHandler:SetTargets(event, initial_id)
    if event == "QUEST_GREETING" then
        local goodbye = QuestFrameGreetingGoodbyeButton
        self.targets = {[goodbye] = {can_activate = true,
                                     lock_highlight = true}}
        local first_button, last_button, first_avail, initial
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
            if initial_id and button:GetID() == initial_id then
                initial = button
            end
        end
        return initial or first_avail or first_button or goodbye

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
