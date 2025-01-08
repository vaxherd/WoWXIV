local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local OrderHallMissionFrameHandler = class(MenuCursor.AddOnMenuFrame)
OrderHallMissionFrameHandler.ADDON_NAME = "Blizzard_GarrisonUI"
MenuCursor.Cursor.RegisterFrameHandler(OrderHallMissionFrameHandler)
local OrderHallMissionFrameMissionsHandler = class(MenuCursor.StandardMenuFrame)
local OrderHallMissionFrameFollowersHandler = class(MenuCursor.StandardMenuFrame)
local FollowerTabHandler = class(MenuCursor.MenuFrame)
local MissionPageHandler = class(MenuCursor.MenuFrame)
local ZoneSupportMissionPageHandler = class(MenuCursor.MenuFrame)
local CompleteDialogHandler = class(MenuCursor.StandardMenuFrame)
local MissionCompleteHandler = class(MenuCursor.StandardMenuFrame)

function OrderHallMissionFrameHandler.OnAddOnLoaded(class)
    local instance = class()
    class.instance = instance
    class.instance_Missions = OrderHallMissionFrameMissionsHandler()
    class.instance_Followers = OrderHallMissionFrameFollowersHandler()
    class.instance_FollowerTab = FollowerTabHandler()
    class.instance_MissionPage = MissionPageHandler()
    class.instance_ZoneSupport = ZoneSupportMissionPageHandler()
    class.instance_CompleteDialog = CompleteDialogHandler()
    class.instance_MissionComplete = MissionCompleteHandler()
end

function OrderHallMissionFrameHandler:__constructor()
    self:__super(OrderHallMissionFrame)
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function OrderHallMissionFrameHandler:OnTabCycle(direction)
    local f = self.frame
    local target = f.selectedTab + direction
    if target > f.numTabs then target = 1 end
    if target < 1 then target = f.numTabs end
    f:SelectTab(target)
end

function OrderHallMissionFrameHandler:OnShow()
    if OrderHallMissionFrameMissions:IsVisible() then
        OrderHallMissionFrameHandler.instance_Missions:OnShow()
    elseif OrderHallMissionFrameFollowers:IsVisible() then
        OrderHallMissionFrameHandler.instance_Followers:OnShow()
    end
end

function OrderHallMissionFrameHandler:OnHide()
    OrderHallMissionFrameHandler.instance_Missions:OnHide()
    OrderHallMissionFrameHandler.instance_Followers:OnHide()
    MenuCursor.AddOnMenuFrame:OnHide(self)
end


function OrderHallMissionFrameMissionsHandler:__constructor()
    self:__super(OrderHallMissionFrameMissions)
    self.cancel_func = function() HideUIPanel(OrderHallMissionFrame) end
    self.on_prev_page = function() self:ChangePage() end
    self.on_next_page = self.on_prev_page
    self.tab_handler = OrderHallMissionFrameHandler.instance.tab_handler
    self.ally_state = nil  -- Used by RefreshCombatAlly().
    self:HookShow(OrderHallMissionFrameMissions.CombatAllyUI.Available,
                  self.RefreshCombatAlly, self.RefreshCombatAlly)
    self:HookShow(OrderHallMissionFrameMissions.CombatAllyUI.InProgress,
                  self.RefreshCombatAlly, self.RefreshCombatAlly)
end

function OrderHallMissionFrameMissionsHandler:ChangePage()
    if self.frame.showInProgress then
        OrderHallMissionFrameMissionsTab1:Click("LeftButton", true)
    else
        OrderHallMissionFrameMissionsTab2:Click("LeftButton", true)
    end
    self:ClearTarget()
    self:RefreshTargets()
end

function OrderHallMissionFrameMissionsHandler:RefreshTargets()
    local target = self:GetTarget()
    if target and self.targets[target].is_scroll_box then
        target = target.index
    end
    self:ClearTarget()
    self:SetTarget(self:SetTargets(target))
end

function OrderHallMissionFrameMissionsHandler:RefreshCombatAlly()
    -- This is called every frame, so we have to filter it out to avoid
    -- unnecessary refresh load.
    local ally_state = ""
    if OrderHallMissionFrameMissions.CombatAllyUI.Available:IsShown() then
        ally_state = ally_state.."a"
    end
    if OrderHallMissionFrameMissions.CombatAllyUI.InProgress:IsShown() then
        ally_state = ally_state.."i"
    end
    if self.frame:IsShown() and ally_state ~= self.ally_state then
        self:RefreshTargets()
    end
    self.ally_state = ally_state
end

function OrderHallMissionFrameMissionsHandler:SetTargets(last_target)
    local f = self.frame
    self.targets = {}

    local function ClickMission(target)
        local button = self:GetTargetFrame(target)
        button:Click("LeftButton", true)
    end
    local function OnEnterMission(target)
        -- We have two sets of information to display for available
        -- missions: the mission info and the reward.  In both cases, the
        -- tooltip is shown in an awkward place (mission info relative to
        -- the mouse pointer, reward info relative to the upper-right
        -- corner so it looks like it belongs to the line above), so we
        -- roll our own tooltip instead.
        local button = self:GetTargetFrame(target)
        GameTooltip:SetOwner(button, "ANCHOR_NONE")  -- ANCHOR_RIGHT doesn't do what you'd expect...
        GameTooltip:SetPoint("LEFT", button, "RIGHT")
        local info = button.info
        GameTooltip:SetText(info.name)
        if info.inProgress then
            -- from GarrisonMissionButton_SetInProgressTooltip()
            if (GarrisonFollowerOptions[info.followerTypeID].showILevelOnMission
                and info.isMaxLevel and info.iLevel > 0)
            then
                GameTooltip:AddLine(
                    format(GARRISON_MISSION_LEVEL_ITEMLEVEL_TOOLTIP,
                           info.level, info.iLevel), 1, 1, 1)
            else
                GameTooltip:AddLine(format(GARRISON_MISSION_LEVEL_TOOLTIP,
                                           info.level), 1, 1, 1)
            end
            if info.isComplete then
                GameTooltip:AddLine(COMPLETE, 1, 1, 1)
            end
            local chance = C_Garrison.GetMissionSuccessChance(info.missionID)
            if chance and info.followerTypeID ~= Enum.GarrisonFollowerType.FollowerType_9_0_GarrisonFollower then
                GameTooltip:AddLine(format(GARRISON_MISSION_PERCENT_CHANCE,
                                           chance), 1, 1, 1)
            end
            if info.followers then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(GarrisonFollowerOptions[info.followerTypeID].strings.FOLLOWER_NAME)
                for _, follower in ipairs(info.followers) do
                    GameTooltip:AddLine(C_Garrison.GetFollowerName(follower),
                                        1, 1, 1)
                end
            end
        else
            -- from GarrisonMissionButton_OnEnter()
            GameTooltip:AddLine(
                string.format(GARRISON_MISSION_TOOLTIP_NUM_REQUIRED_FOLLOWERS,
                              info.numFollowers), 1, 1, 1)
            local mission_frame = GarrisonMissionButton_GetMissionFrame(button)
            GarrisonMissionButton_AddThreatsToTooltip(
                info.missionID, mission_frame.followerTypeID, false,
                mission_frame.abilityCountersForMechanicTypes)
            if info.isRare then
                GameTooltip:AddLine(GARRISON_MISSION_AVAILABILITY)
                GameTooltip:AddLine(info.offerTimeRemaining, 1, 1, 1)
            end
            if not C_Garrison.IsPlayerInGarrison(GarrisonFollowerOptions[mission_frame.followerTypeID].garrisonType) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(GarrisonFollowerOptions[mission_frame.followerTypeID].strings.RETURN_TO_START, nil, nil, nil, 1);
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(REWARDS)
        for id, reward in pairs(info.rewards) do
            if reward.quality then
                GameTooltip:AddLine(ITEM_QUALITY_COLORS[reward.quality+1].hex .. reward.title .. FONT_COLOR_CODE_CLOSE)
            elseif reward.itemID then
                local name, _, rarity, _, _, _, _, _, _, texture =
                    C_Item.GetItemInfo(reward.itemID)
                if name then
                    GameTooltip:AddLine(ITEM_QUALITY_COLORS[rarity].hex .. name .. FONT_COLOR_CODE_CLOSE)
                end
            elseif reward.currencyID and reward.currencyID ~= 0 and reward.currencyQuantity then
                local name, texture, quantity, quality = CurrencyContainerUtil.GetCurrencyContainerInfo(reward.currencyID, reward.quantity)
                if name then
                    GameTooltip:AddLine(ITEM_QUALITY_COLORS[quality].hex .. name .. FONT_COLOR_CODE_CLOSE)
                end
            elseif reward.title then
                GameTooltip:AddLine(reward.title)
            end
        end
        GameTooltip:Show()
    end
    local function AddTarget(elementdata, index)
        return {on_click = ClickMission,
                on_enter = OnEnterMission, on_leave = self.HideTooltip,
                left = false, right = false}, index == last_target
    end
    local top, bottom, initial =
        self:AddScrollBoxTargets(f.ScrollBox, AddTarget)

    if f.CombatAllyUI.Available:IsShown() then
        local afb = f.CombatAllyUI.Available.AddFollowerButton
        self.targets[afb] = {can_activate = true, lock_highlight = true,
                             up = bottom, down = top}
        if top then
            self.targets[top].up = afb
            self.targets[bottom].down = afb
        else
            top = afb
        end
    end

    if f.CombatAllyUI.InProgress:IsShown() then
        local spell = f.CombatAllyUI.InProgress.CombatAllySpell
        local unassign = f.CombatAllyUI.InProgress.Unassign
        self.targets[spell] = {send_enter_leave = true,
                               up = bottom, down = top,
                               left = unassign, right = unassign}
        self.targets[unassign] = {can_activate = true, lock_highlight = true,
                                  up = bottom, down = top,
                                  left = spell, right = spell}
        if top then
            self.targets[top].up = spell
            self.targets[bottom].down = spell
        else
            top = spell
        end
    end

    if not initial and last_target and self.targets[last_target] then
        initial = last_target  -- One of the combat ally buttons.
    end
    return initial or top
end


function OrderHallMissionFrameFollowersHandler:__constructor()
    self:__super(OrderHallMissionFrameFollowers)
    self.cancel_func = function() self:OnCancel() end
    self.has_Button4 = true  -- Used to remove followers from missions.
    self.tab_handler = OrderHallMissionFrameHandler.instance.tab_handler
end

function OrderHallMissionFrameFollowersHandler:OnCancel()
    -- The followers frame is also used when showing the follower list to
    -- add to a mission or set as combat ally, so we have to make sure not
    -- to back too far out.
    if OrderHallMissionFrame.MissionTab.MissionPage:IsVisible() then
        OrderHallMissionFrame.MissionTab.MissionPage.CloseButton:Click()
    elseif OrderHallMissionFrame.MissionTab.ZoneSupportMissionPage:IsVisible() then
        OrderHallMissionFrame.MissionTab.ZoneSupportMissionPage.CloseButton:Click()
    else
        HideUIPanel(OrderHallMissionFrame)
    end
end

function OrderHallMissionFrameFollowersHandler:SetTargets(redo)
    self.targets = {}
    -- Hack to deal with list sometimes not being initialized on the first
    -- frame.
    if not redo then
        RunNextFrame(function() self:SetTarget(self:SetTargets(true)) end)
        return nil
    end
    local function ClickFollower(target)
        local button = self:GetTargetFrame(target).Follower
        local is_mission = OrderHallMissionFrame.MissionTab:IsVisible()
        -- Deliberately not :Click() because the button's OnClick script
        -- calls _OnUserClick(), which checks IsModifiedClick() (which is
        -- invalid in this context).
        GarrisonFollowerListButton_OnClick(
            button, is_mission and "RightButton" or "LeftButton")
        if is_mission then
            local page = OrderHallMissionFrame:GetMissionPage()
            if page.Followers[#page.Followers].info then
                if page == OrderHallMissionFrameHandler.instance_ZoneSupport.frame then
                    OrderHallMissionFrameHandler.instance_ZoneSupport:Activate()
                else
                    OrderHallMissionFrameHandler.instance_MissionPage:Activate()
                end
            end
        else
            OrderHallMissionFrameHandler.instance_FollowerTab:Activate()
        end
    end
    local function AddTarget(elementdata, index)
        if not elementdata.follower then return nil end
        return {on_click = ClickFollower, send_enter_leave = true,
                left = false, right = false, info = elementdata.follower}
    end
    local top, bottom =
        self:AddScrollBoxTargets(self.frame.ScrollBox, AddTarget)
    return top
end

function OrderHallMissionFrameFollowersHandler:OnAction(button)
    assert(button == "Button4")
    if OrderHallMissionFrame.MissionTab:IsVisible() then
        local followers = OrderHallMissionFrame:GetMissionPage().Followers
        for i = #followers, 1, -1 do
            local frame = followers[i]
            if frame.info then
                OrderHallMissionFrame:RemoveFollowerFromMission(frame, true)
                return
            end
        end
    end
end


function MissionPageHandler:__constructor()
    self:__super(OrderHallMissionFrame.MissionTab.MissionPage)
    self.cancel_func = function() self:Disable() end
end

function MissionPageHandler:Activate()
    self:ClearTarget()
    self:Enable(self:SetTargets())
end

function MissionPageHandler:SetTargets()
    local f = self.frame
    self.targets = {
        [f.Follower1] = {
            send_enter_leave = true,
            up = f.StartMissionButton, down = f.RewardsFrame.Reward1,
            left = false, right = false},
        [f.RewardsFrame.Reward1] = {
            send_enter_leave = true,
            up = f.Follower1, down = f.StartMissionButton,
            left = false, right = false},
        [f.StartMissionButton] = {
            can_activate = true, is_default = true, lock_highlight = true,
            up = f.RewardsFrame.Reward1, down = f.Follower1,
            left = false, right = false},
    }
    local prev = f.Follower1
    for i = 2, #f.Followers do
        local follower = f.Followers[i]
        self.targets[follower] = {
            send_enter_leave = true,
            up = f.StartMissionButton, down = f.RewardsFrame.Reward1,
            left = prev, right = f.Follower1}
        self.targets[prev].right = follower
        prev = follower
    end
    self.targets[f.Follower1].left = prev
    if f.RewardsFrame.OvermaxItem:IsShown() then
        self.targets[f.RewardsFrame.OvermaxItem] = {
            send_enter_leave = true,
            up = f.Follower1, down = f.RewardsFrame.Reward1,
            left = false, right = false}
        self.targets[f.Follower1].down = f.RewardsFrame.OvermaxItem
        self.targets[f.RewardsFrame.Reward1].up = f.RewardsFrame.OvermaxItem
    end
end


function ZoneSupportMissionPageHandler:__constructor()
    self:__super(OrderHallMissionFrame.MissionTab.ZoneSupportMissionPage)
    self.cancel_func = function() self:Disable() end
end

function ZoneSupportMissionPageHandler:Activate()
    self:ClearTarget()
    self:Enable(self:SetTargets())
end

function ZoneSupportMissionPageHandler:SetTargets()
    local f = self.frame
    self.targets = {
        [f.Follower1] = {
            send_enter_leave = true,
            up = f.StartMissionButton, down = f.StartMissionButton,
            left = f.CombatAllySpell, right = f.CombatAllySpell},
        [f.CombatAllySpell] = {
            send_enter_leave = true,
            up = f.StartMissionButton, down = f.StartMissionButton,
            left = f.Follower1, right = f.Follower1},
        [f.StartMissionButton] = {
            can_activate = true, is_default = true, lock_highlight = true,
            up = f.CombatAllySpell, down = f.CombatAllySpell,
            left = false, right = false},
    }
end


function FollowerTabHandler:__constructor()
    self:__super(OrderHallMissionFrame.FollowerTab)
    self.cancel_func = function() self:Disable() end
end

function FollowerTabHandler:Activate()
    self:ClearTarget()
    self:Enable(self:SetTargets())
end

function FollowerTabHandler:SetTargets()
    local f = self.frame
    self.targets = {}

    local abilities = {}
    for button in f.abilitiesPool:EnumerateActive() do
        tinsert(abilities, button.IconButton)
    end
    for button in f.countersPool:EnumerateActive() do
        tinsert(abilities, button.IconButton)
    end
    for button in f.autoSpellPool:EnumerateActive() do
        tinsert(abilities, button.IconButton)
    end
    for button in f.autoCombatStatsPool:EnumerateActive() do
        tinsert(abilities, button.IconButton)
    end
    for _, button in ipairs(f.AbilitiesFrame.CombatAllySpell) do
        if button:IsShown() then
            tinsert(abilities, button)
        end
    end
    table.sort(abilities, function(a,b) return a:GetTop() > b:GetTop() end)
    local top, bottom
    for _, button in ipairs(abilities) do
        self.targets[button] = {send_enter_leave = true, up = bottom,
                                left = false, right = false}
        if bottom then
            self.targets[bottom].down = button
        end
        top = top or button
        bottom = button
    end
    if top then
        self.targets[top].up = bottom
        self.targets[bottom].down = up
    end

    local equipment = {}
    for button in f.equipmentPool:EnumerateActive() do
        tinsert(equipment, button)
    end
    table.sort(equipment, function(a,b) return a:GetLeft() < b:GetLeft() end)
    local left, right
    for _, button in ipairs(equipment) do
        self.targets[button] = {send_enter_leave = true, left = right,
                                up = bottom, down = top}
        if right then
            self.targets[right].right = button
        end
        left = left or button
        right = button
    end
    if left then
        self.targets[left].left = right
        self.targets[right].right = left
        if top then
            self.targets[top].up = left
            self.targets[bottom].down = left
        end
    end

    return top or left
end


function CompleteDialogHandler:__constructor()
    self:__super(OrderHallMissionFrameMissions.CompleteDialog,
                 MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
end

function CompleteDialogHandler:SetTargets()
    self.targets = {
        [self.frame.BorderFrame.ViewButton] =
            {can_activate = true, lock_highlight = true, is_default = true},
    }
end


function MissionCompleteHandler:__constructor()
    self:__super(OrderHallMissionFrame.MissionComplete,
                 MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
    self:HookShow(self.frame.BonusRewards.ChestModel.ClickFrame,
                  self.RefreshTargets, self.RefreshTargets)
end

function MissionCompleteHandler:RefreshTargets()
    self:ClearTarget()
    self:SetTarget(self:SetTargets() or self:GetDefaultTarget())
end

function MissionCompleteHandler:SetTargets()
    local f = self.frame
    local nmb = f.NextMissionButton
    self.targets = {
        [nmb] = {can_activate = true, lock_highlight = true, is_default = true,
                 left = false, right = false}
    }

    local ChestButton = f.BonusRewards.ChestModel.ClickFrame
    if ChestButton:IsShown() then
        local function ClickChest(frame)
            frame:GetScript("OnMouseDown")(frame, "LeftButton", true)
        end
        self.targets[ChestButton] =
            {on_click = ClickChest, send_enter_leave = true,
             left = false, right = false}
        return ChestButton
    end
end
