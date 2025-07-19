local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

-- Just different enough from OrderHallMissionFrame that it's hard to
-- merge the two... (sigh)

---------------------------------------------------------------------------

local CovenantMissionFrameHandler = class(MenuCursor.AddOnMenuFrame)
CovenantMissionFrameHandler.ADDON_NAME = "Blizzard_GarrisonUI"
MenuCursor.Cursor.RegisterFrameHandler(CovenantMissionFrameHandler)
local CovenantMissionFrameMissionsHandler = class(MenuCursor.StandardMenuFrame)
local CovenantMissionFrameFollowersHandler = class(MenuCursor.StandardMenuFrame)
local MissionTabHandler = class(MenuCursor.MenuFrame)
local FollowerTabHandler = class(MenuCursor.MenuFrame)
local CompleteDialogHandler = class(MenuCursor.StandardMenuFrame)
local MissionCompleteHandler = class(MenuCursor.StandardMenuFrame)
local MapTabHandler = class(MenuCursor.StandardMenuFrame)

function CovenantMissionFrameHandler.OnAddOnLoaded(class)
    local instance = class()
    class.instance = instance
    class.instance_Missions = CovenantMissionFrameMissionsHandler()
    class.instance_Followers = CovenantMissionFrameFollowersHandler()
    class.instance_MissionTab = MissionTabHandler()
    class.instance_FollowerTab = FollowerTabHandler()
    class.instance_CompleteDialog = CompleteDialogHandler()
    class.instance_MissionComplete = MissionCompleteHandler()
    class.instance_MapTab = MapTabHandler()
end

function CovenantMissionFrameHandler:__constructor()
    self:__super(CovenantMissionFrame)
end

function CovenantMissionFrameHandler:__constructor()
    self:__super(CovenantMissionFrame)
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function CovenantMissionFrameHandler:OnTabCycle(direction)
    local f = self.frame
    local target = f.selectedTab + direction
    if target > f.numTabs then target = 1 end
    if target < 1 then target = f.numTabs end
    f:SelectTab(target)
    -- Hack for missions list not getting activated if we started with
    -- the followers tab selected.
    local missions = CovenantMissionFrameHandler.instance_Missions
    if missions.frame:IsVisible() and not missions:HasFocus() then
        missions:OnShow()
    end
end

function CovenantMissionFrameHandler:OnShow()
    CovenantMissionFrameHandler.instance_Missions:Reset()
    CovenantMissionFrameHandler.instance_Followers:Reset()
    if CovenantMissionFrameMissions:IsVisible() then
        CovenantMissionFrameHandler.instance_Missions:OnShow()
    elseif CovenantMissionFrameFollowers:IsVisible() then
        CovenantMissionFrameHandler.instance_Followers:OnShow()
    elseif CovenantMissionFrame.MapTab:IsVisible() then
        CovenantMissionFrameHandler.instance_MapTab:OnShow()
    end
end

function CovenantMissionFrameHandler:OnHide()
    CovenantMissionFrameHandler.instance_Missions:OnHide()
    CovenantMissionFrameHandler.instance_Followers:OnHide()
    CovenantMissionFrameHandler.instance_MapTab:OnHide()
    MenuCursor.AddOnMenuFrame:OnHide(self)
end


function CovenantMissionFrameMissionsHandler:__constructor()
    self:__super(CovenantMissionFrameMissions)
    self.cancel_func = function() HideUIPanel(CovenantMissionFrame) end
    self.tab_handler = CovenantMissionFrameHandler.instance.tab_handler
    hooksecurefunc(self.frame, "UpdateMissions",
                   function() self:MaybeRefreshTargets() end)

    -- Currently selected mission's ID.  Used to preserve cursor position
    -- across tab changes.
    self.current = nil
end

-- Call when the wrapper frame is first shown to reset the current selection.
function CovenantMissionFrameMissionsHandler:Reset()
    self.current = nil
end

function CovenantMissionFrameMissionsHandler:MaybeRefreshTargets()
    -- Blizzard code refreshes the mission list every frame (which that code
    -- acknowledges is suboptimal, see CovenantMissionListMixin:Update()).
    -- If we blindly RefreshTargets() in response, we block cursor repeat,
    -- so we mimic Blizzard code behavior and check whether there has in
    -- fact been any change in the mission list before refreshing the
    -- target set.
    local missions = {}
    local index = 0
    self.frame.ScrollBox:ForEachElementData(function(data)
        index = index + 1
        missions[index] = data
    end)
    local all_match = true
    for target, params in pairs(self.targets) do
        if params.is_scroll_box then
            if missions[target.index] then
                missions[target.index] = false
            else
                all_match = false
                break
            end
        end
    end
    if not all_match then
        for k, v in pairs(missions) do
            if v then
                all_match = false
                break
            end
        end
    end
    if not all_match then
        self:RefreshTargets()
    end
end

function CovenantMissionFrameMissionsHandler:RefreshTargets()
    local target = self:GetTarget()
    if self.targets[target].is_scroll_box then
        target = self.targets[target].id
    end
    self:ClearTarget()
    self:SetTarget(self:SetTargets(target))
end

function CovenantMissionFrameMissionsHandler:SetTargets(last_target)
    local f = self.frame
    self.targets = {}

    if not last_target then
        last_target = self.current
    end

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
                GameTooltip:AddLine(WoWXIV.FormatItemColor(reward.title, reward.quality+1))
            elseif reward.itemID then
                local name, _, rarity, _, _, _, _, _, _, texture =
                    C_Item.GetItemInfo(reward.itemID)
                if name then
                    GameTooltip:AddLine(WoWXIV.FormatItemColor(name, rarity))
                end
            elseif reward.currencyID and reward.currencyID ~= 0 and reward.currencyQuantity then
                local name, texture, quantity, quality = CurrencyContainerUtil.GetCurrencyContainerInfo(reward.currencyID, reward.quantity)
                if name then
                    GameTooltip:AddLine(WoWXIV.FormatItemColor(name, quality))
                end
            elseif reward.title then
                GameTooltip:AddLine(reward.title)
            end
        end
        GameTooltip:Show()
    end
    local function AddTarget(elementdata, index)
        local attr = {on_click = ClickMission,
                      on_enter = OnEnterMission, on_leave = self.HideTooltip,
                      left = false, right = false, id = elementdata.missionID}
        return attr, last_target == attr.id
    end
    local top, bottom, initial =
        self:AddScrollBoxTargets(f.ScrollBox, AddTarget)
    return initial or top
end

function CovenantMissionFrameMissionsHandler:EnterTarget(target)
    MenuCursor.StandardMenuFrame.EnterTarget(self, target)
    local param = self.targets[target]
    if param.is_scroll_box then
        self.current = param.id
    else
        self.current = nil
    end
end


function CovenantMissionFrameFollowersHandler:__constructor()
    self:__super(CovenantMissionFrameFollowers)
    self.cancel_func = function() self:OnCancel() end
    self.has_Button3 = true  -- Used to switch to the mission tab.
    self.has_Button4 = true  -- Used to add followers to missions.
    self.tab_handler = CovenantMissionFrameHandler.instance.tab_handler

    -- Currently selected follower's ID.  Used to preserve cursor position
    -- across tab changes.
    self.current = nil
end

-- Call when the wrapper frame is first shown to reset the current selection.
function CovenantMissionFrameFollowersHandler:Reset()
    self.current = nil
end

function CovenantMissionFrameFollowersHandler:OnCancel()
    -- The followers frame is also used when showing the follower list to
    -- add to a mission, so we have to make sure not to back too far out.
    if CovenantMissionFrame.MissionTab.MissionPage:IsVisible() then
        CovenantMissionFrame.MissionTab.MissionPage.CloseButton:Click()
    else
        HideUIPanel(CovenantMissionFrame)
    end
end

function CovenantMissionFrameFollowersHandler:SetTargets(redo)
    -- Hack to deal with list sometimes not being initialized on the first
    -- frame.
    if not redo then
        RunNextFrame(function() self:SetTarget(self:SetTargets(true)) end)
        return nil
    end
    local last_target = self:GetTarget()
    self:SetTarget(nil)
    local last_id
    if not last_target then
        last_id = self.current
    elseif self.targets[last_target].is_scroll_box then
        last_id = self.targets[last_target].id
        last_target = nil
    end
    self.targets = {
        [self.frame.HealAllButton] = {can_activate = true,
                                      lock_highlight = true}
    }
    local function ClickFollower(target)
        local button = self:GetTargetFrame(target).Follower
        local is_mission = CovenantMissionFrame.MissionTab:IsVisible()
        -- Deliberately not :Click() because the button's OnClick script
        -- calls _OnUserClick(), which checks IsModifiedClick() (which is
        -- invalid in this context).  Note that the SL covenant UI shares
        -- this "Garrison" function with other mission boards.
        GarrisonFollowerListButton_OnClick(button, "LeftButton")
        if is_mission then
            CovenantMissionFrameHandler.instance_MissionTab:Activate(true)
        else
            CovenantMissionFrameHandler.instance_FollowerTab:Activate()
        end
    end
    local function AddTarget(elementdata, index)
        if not elementdata.follower then return nil end
        local attr = {on_click = ClickFollower, send_enter_leave = true,
                      left = false, right = false,
                      id = elementdata.follower.followerID}
        return attr, last_id == attr.id
    end
    local top, bottom, initial =
        self:AddScrollBoxTargets(self.frame.ScrollBox, AddTarget)
    local healall = self.frame.HealAllButton
    if top then
        self.targets[top].up = healall
        self.targets[bottom].down = healall
        self.targets[healall].up = bottom
        self.targets[healall].down = top
    end
    return last_target or initial or top or healall
end

function CovenantMissionFrameFollowersHandler:OnAction(button)
    local is_mission = CovenantMissionFrame.MissionTab:IsVisible()
    if button == "Button3" then
        if is_mission then
            CovenantMissionFrameHandler.instance_MissionTab:Activate()
        end
    elseif button == "Button4" then
        local target = self:GetTarget()
        if target ~= self.frame.HealAllButton and is_mission then
            GarrisonFollowerListButton_OnClick(
                self:GetTargetFrame(target).Follower, "RightButton")
            local info = CovenantMissionFrame:GetMissionPage().missionInfo
            if C_Garrison.GetNumFollowersOnMission(info.missionID) >= info.numFollowers then
                CovenantMissionFrameHandler.instance_MissionTab:Activate()
            end
        end
    end
end

function CovenantMissionFrameFollowersHandler:EnterTarget(target)
    MenuCursor.StandardMenuFrame.EnterTarget(self, target)
    local param = self.targets[target]
    if param.is_scroll_box then
        self.current = param.id
    else
        self.current = nil
    end
end


function MissionTabHandler:__constructor()
    self:__super(CovenantMissionFrame.MissionTab)
    self.cancel_func = function()
        -- Avoid Disable() to preserve cursor position.
        CovenantMissionFrameHandler.instance_Followers:Enable()
    end
    self.has_Button3 = true  -- Used to switch to the follower list.
    self.has_Button4 = true  -- Used to remove followers from missions.
    self.followers = {}  -- List of follower slots, for convenience.
end

-- Pass true for is_follower_placement when activating the frame for
-- placing a follower in the party; this forces the cursor to a party slot
-- if it wasn't there already.
function MissionTabHandler:Activate(is_follower_placement)
    local cur_target = self:GetTarget()
    self:ClearTarget()
    self:Enable(self:SetTargets(cur_target, is_follower_placement))
end

function MissionTabHandler:SetTargets(prev_target, is_follower_placement)
    local page = self.frame.MissionPage
    self.targets = {
        [page.StartMissionButton] = {
            can_activate = true, lock_highlight = true,
            left = false, right = false},
    }
    if is_follower_placement and prev_target == page.StartMissionButton then
        prev_target = nil
    end

    local left_x, right_x, top_y
    for enemy in page.Board:EnumerateEnemies() do
        self.targets[enemy] = {send_enter_leave = enemy:IsShown()}
        local x, y = enemy:GetLeft(), enemy:GetTop()
        if not left_x or x < left_x then
            left_x = x
        end
        if not right_x or x > right_x then
            right_x = x
        end
        if not top_y or y > top_y then
            top_y = y
        end
        if is_follower_placement and prev_target == enemy then
            prev_target = nil
        end
    end
    local e11, e14, e21, e24
    for enemy in page.Board:EnumerateEnemies() do
        local x, y = enemy:GetLeft(), enemy:GetTop()
        if y == top_y then
            self.targets[enemy].up = page.StartMissionButton
            if x == left_x then
                e11 = enemy
            elseif x == right_x then
                e14 = enemy
            end
        else
            if x == left_x then
                e21 = enemy
            elseif x == right_x then
                e24 = enemy
            end
        end
    end
    self.targets[page.StartMissionButton].down = e11
    self.targets[e11].left = e14
    self.targets[e14].right = e11
    self.targets[e21].left = e24
    self.targets[e24].right = e21

    local f11, f12, f13, f21, f22
    for follower in page.Board:EnumerateFollowers() do
        self.targets[follower] = {
            send_enter_leave = true, is_follower = true,
            on_click = function() self:ClickFollowerSlot(follower) end}
        local x, y = follower:GetLeft(), follower:GetTop()
        if not f11 then
            f11 = follower
        elseif y > f11:GetTop() then
            assert(not f13)
            f21, f22 = f11, f12
            f11, f12 = follower, nil
        elseif y < f11:GetTop() then
            if not f21 then
                f21 = follower
            else
                assert(not f22)
                assert(y == f21:GetTop())
                if x > f21:GetLeft() then
                    f22 = follower
                else
                    f21, f22 = follower, f21
                end
            end
        elseif not f12 then
            if x > f11:GetLeft() then
                f12 = follower
            else
                f11, f12 = follower, f11
            end
        else
            assert(not f13)
            if x > f12:GetLeft() then
                f13 = follower
            elseif x > f11:GetLeft() then
                f12, f13 = follower, f12
            else
                f11, f12, f13 = follower, f11, f12
            end
        end
    end
    self.followers = {f11, f12, f13, f21, f22}
    for i, follower in ipairs(self.followers) do
        self.targets[follower].left = self.followers[i==1 and 5 or i-1]
        self.targets[follower].right = self.followers[i==5 and 1 or i+1]
    end

    return prev_target or self.followers[1] or page.StartMissionButton
end

function MissionTabHandler:ClickFollowerSlot(follower)
    local followerFrame = CovenantMissionFrameFollowers.ScrollBox.followerFrame
    local selected = followerFrame.selectedFollower
    if selected and follower:GetFollowerGUID() ~= selected then
        local info
        CovenantMissionFrameFollowers.ScrollBox:ForEachElementData(
            function(data)
                if data.follower and data.follower.followerID == selected then
                    assert(not info)
                    info = data.follower
                end
            end)
        assert(info)
        self:LeaveTarget(follower)
        -- We have to explicitly remove the follower from their current
        -- slot if they're already in the party.  (Mouse control avoids
        -- this by making the follower not draggable from the list if in
        -- the party.  We could potentially implement our own floating
        -- icon for a closer match to mouse behavior.)
        for _, f in ipairs(self.followers) do
            if f:GetFollowerGUID() == selected then
                CovenantMissionFrame:RemoveFollowerFromMission(f)
            end
        end
        CovenantMissionFrame:AssignFollowerToMission(follower, info)
        self:EnterTarget(follower)
        followerFrame.selectedFollower = nil
        CovenantMissionFrameFollowers:UpdateData()
        local full = WoWXIV.all(function(f) return f:GetFollowerGUID() end,
                                unpack(self.followers))
        if full then
            self:SetTarget(self.frame.MissionPage.StartMissionButton)
        else
            CovenantMissionFrameHandler.instance_Followers:Enable()
        end
    end
end

function MissionTabHandler:OnAction(button)
    if button == "Button3" then
        CovenantMissionFrameHandler.instance_Followers:Enable()
    else
        assert(button == "Button4")
        local target = self:GetTarget()
        if target and self.targets[target].is_follower then
            self:LeaveTarget(target)
            CovenantMissionFrame:RemoveFollowerFromMission(target)
            self:EnterTarget(target)
            PlaySound(SOUNDKIT.UI_ADVENTURES_ADVENTURER_UNSLOTTED)
        end
    end
end


function FollowerTabHandler:__constructor()
    self:__super(CovenantMissionFrame.FollowerTab)
    self.cancel_func = function() self:Disable() end
end

function FollowerTabHandler:Activate()
    self:ClearTarget()
    self:Enable(self:SetTargets())
end

-- We use a custom click handler for the heal button to acknowledge the
-- heal button help tip in case it's shown.  As of 11.1.7, the heal
-- operation is not protected, so it's safe to taint the click (this
-- transiently taints the StaticPopup used for the confirmation, but
-- only until it's reused in a secure call).
local function OnHealFollower(button)
    button:Click("LeftButton", true)
    -- See CovenantFollowerTabMixin:ShowHealFollowerTutorial() for the
    -- bitfield reference.
    C_CVar.SetCVarBitfield("covenantMissionTutorial",
                           Enum.GarrAutoCombatTutorial.HealCompanion, true)
end

function FollowerTabHandler:SetTargets()
    local f = self.frame
    local heal = self.frame.HealFollowerFrame.HealFollowerButton
    self.targets = {
        [heal] = {on_click = OnHealFollower, lock_highlight = true,
                  send_enter_leave = true, is_default = true},
    }
    local left
    for button in f.autoSpellPool:EnumerateActive() do
        self.targets[button] = {send_enter_leave = true, up = heal}
        if not left or button:GetLeft() < left:GetLeft() then
            left = button
        end
    end
    self.targets[heal].up = left
    self.targets[heal].down = left
    return left
end


function CompleteDialogHandler:__constructor()
    self:__super(CovenantMissionFrameMissions.CompleteDialog,
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
    self:__super(CovenantMissionFrame.MissionComplete,
                 MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
    self:HookShow(self.frame.RewardsScreen.FinalRewardsPanel,
                  self.RefreshTargets, self.RefreshTargets)
end

function MissionCompleteHandler:RefreshTargets()
    self:ClearTarget()
    self:SetTarget(self:SetTargets() or self:GetDefaultTarget())
end

function MissionCompleteHandler:SetTargets()
    local f = self.frame
    local button
    if f.RewardsScreen.FinalRewardsPanel.ContinueButton:IsVisible() then
        button = f.RewardsScreen.FinalRewardsPanel.ContinueButton
    else
        button = f.CompleteFrame.ContinueButton
    end
    self.targets = {
        [button] = {can_activate = true, lock_highlight = true,
                    is_default = true, left = false, right = false}
    }
end


function MapTabHandler:__constructor()
    self:__super(CovenantMissionFrame.MapTab)
    self.cancel_func = function() HideUIPanel(CovenantMissionFrame) end
end

function MapTabHandler:SetTargets()
    self.targets = {}
    -- Pin load is delayed, so wait for data to show up.
    self:AddTargets()
end

function MapTabHandler:AddTargets()
    local pool = self.frame.pinPools.AdventureMap_QuestChoicePinTemplate
    if pool then
        local pins = {}
        for pin in pool:EnumerateActive() do
            tinsert(pins, pin)
        end
        if #pins > 0 then
            local function OnEnterPin(pin) self:OnEnterPin(pin) end
            local function OnLeavePin(pin) self:OnLeavePin(pin) end
            local function OnClickPin(pin) self:OnClickPin(pin) end
            local top
            for _, pin in ipairs(pins) do
                -- Pins aren't true buttons and don't have IsEnabled(), so
                -- we can't use lock_highlight and have to roll our own.
                self.targets[pin] = {on_click = OnClickPin,
                                     on_enter = OnEnterPin,
                                     on_leave = OnLeavePin}
                if not top or pin.normalizedY < top.normalizedY then
                    top = pin
                end
            end
            self:SetTarget(top)
            return
        end
    end
    -- Pins are not yet loaded, so try again next frame.
    RunNextFrame(function() self:AddTargets() end)
end

function MapTabHandler:OnEnterPin(pin)
    pin:OnMouseEnter()
    pin:LockHighlight()
end

function MapTabHandler:OnLeavePin(pin)
    pin:UnlockHighlight()
    pin:OnMouseLeave()
end

function MapTabHandler:OnClickPin(pin)
    pin:OnClick("LeftButton", true)
end
