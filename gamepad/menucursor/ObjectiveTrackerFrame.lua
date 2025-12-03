local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

assert(WoWXIV.UI.ContextMenu)  -- Ensure proper load order.

---------------------------------------------------------------------------

local ObjectiveTrackerFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(ObjectiveTrackerFrameHandler)

local QuestContextMenu = class(WoWXIV.UI.ContextMenu)

function ObjectiveTrackerFrameHandler:__constructor()
    __super(self, ObjectiveTrackerFrame, MenuCursor.MenuFrame.NOAUTOFOCUS)
    self.cancel_func = function() self:Unfocus() end
    self.has_Button3 = true  -- Used to toggle quest tracking.
    self.has_Button4 = true  -- Used to open objective submenus.
    hooksecurefunc(self.frame, "Update", function() self:RefreshTargets() end)
    hooksecurefunc(self.frame, "ForceExpand", function() self:RefreshTargets() end)
    -- Watch for any bags being opened and disable ourselves while we're
    -- covered up.
    self.is_covered = false
    local function CheckContainerFrames() self:CheckContainerFrames() end
    EventRegistry:RegisterCallback("ContainerFrame.OpenBag",
                                   CheckContainerFrames)
    EventRegistry:RegisterCallback("ContainerFrame.CloseBag",
                                   CheckContainerFrames)

    self.context_menu = QuestContextMenu()
    self.context_menu_handler = MenuCursor.ContextMenuHandler(self.context_menu)
end

local BAGS = WoWXIV.maptn("ContainerFrame%n", 6)
function ObjectiveTrackerFrameHandler:CheckContainerFrames()
    local function IsShown(name) return _G[name]:IsShown() end
    self.is_covered = WoWXIV.any(IsShown, unpack(BAGS))
    if self.is_covered then
        self:Disable()
    elseif self.frame:IsShown() then
        if not self:IsEnabled() then
            self:OnShow()
        end
    end
end

function ObjectiveTrackerFrameHandler:OnShow()
    -- Deliberately IsShown() rather than IsVisible() to avoid edge cases
    -- when a cinematic or other fullscreen frame is hiding the tracker.
    assert(self.frame:IsShown())  -- Should never get called otherwise.
    if self.is_covered then return end
    if self:IsEnabled() then
        -- This must be a redundant Show() with the frame already visible,
        -- so don't change current state.
        -- (FIXME: we should probably handle this case at a lower level)
        return
    end
    -- We never take input focus on our own.
    self:EnableBackground(self:SetTargets())
end

function ObjectiveTrackerFrameHandler:OnFocus()
    -- Always reset to the top when receiving focus.
    self:SetTarget(self:GetDefaultTarget())
end

function ObjectiveTrackerFrameHandler:RefreshTargets()
    local target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets(target))
end

local function ClickHeaderButton(block)
    -- Unfocus because the player probably doesn't want to come back afterward.
    ObjectiveTrackerFrameHandler.instance:Unfocus()
    local button = block.HeaderButton
    button:GetScript("OnClick")(button, "LeftButton")
end

local function ClickAutoQuest(block)
    ObjectiveTrackerFrameHandler.instance:Unfocus()  -- As above.
    block:OnMouseUp("LeftButton", true)
end


local function ClickPOIButton(block)
    local button = block.poiButton
    button:GetScript("OnClick")(button, "LeftButton")
end

function ObjectiveTrackerFrameHandler:SetTargets(old_target)
    local function OpenContextMenu(block)
        -- FIXME: it would be nice if we could reuse the native context menu
        -- directly (see QuestObjectiveTrackerMixin:OnBlockHeaderClick() in
        -- Blizzard_QuestObjectiveTracker.lua)
        self.context_menu:Open(block.HeaderButton, block.id)
    end

    self.targets = {}
    -- Modules are ObjectiveTrackerModuleTemplate instances,
    -- e.g. ScenarioObjectiveTracker.
    if not self.frame.modules then return end  -- work around Blizzard bug
    local blocks = {}
    self.frame:ForEachModule(function(module)
        -- module:EnumerateActiveBlocks() is not useful because it doesn't
        -- give the blocks in order, so we iterate manually.
        local block = module.firstBlock
        while block do
            if block:IsVisible() then
               -- Exclude unclickable blocks. FIXME: are there any other types?
                if block.parentModule ~= ScenarioObjectiveTracker then
                    tinsert(blocks, {block, module})
                end
            end
            block = block.nextBlock
        end
    end)
    for i, entry in ipairs(blocks) do
        local block, module = unpack(entry)
        local params =
            {on_click = ClickHeaderButton, is_default = (i==1),
             send_enter_leave = true, left = false, right = false,
             up = blocks[i==1 and #blocks or i-1][1],
             down = blocks[i==#blocks and 1 or i+1][1]}
        self.targets[block] = params
        -- For quests, position the cursor at the PoI button
        -- rather than the middle of the block (which ends up
        -- being under the PoI button and a bit confusing).
        if block.poiButton and block.poiButton:IsVisible() then
            params.on_button3 = ClickPOIButton
            params.on_button4 = OpenContextMenu
            local bx, by, _, bh = block:GetRect()
            local px, py, _, ph = block.poiButton:GetRect()
            by = by + bh/2
            py = py + ph/2
            params.x_offset = px - bx
            params.y_offset = py - by
        end
        -- If there's a quest item button, add it in as well.
        local function GetItemButton(b)
            return b.ItemButton      -- quests
                or b.rightEdgeFrame  -- bonus objectives, world quests
        end
	local item = GetItemButton(block)
        if item then
            params.left = item
            params.right = item
            local item_params =
                {can_activate = true, --lock_highlight = true,
                 send_enter_leave = true, left = block, right = block}
            local up = blocks[i==1 and #blocks or i-1][1]
            local down = blocks[i==#blocks and 1 or i+1][1]
            item_params.up = GetItemButton(up) or up
            item_params.down = GetItemButton(down) or down
            self.targets[item] = item_params
        end
        -- Quest popups in the objective tracker need their own
        -- button handling.
        if block.template == "AutoQuestPopUpBlockTemplate" then
            params.on_click = ClickAutoQuest
            params.on_button4 = nil
        end
        -- Tweak cursor position for various block types.
        if module == QuestObjectiveTracker then
            if block.poiButton then
                params.x_offset = params.x_offset - 4
            elseif block.template == "AutoQuestPopUpBlockTemplate" then
                params.x_offset = 9
            end
        end
    end
    if old_target and not self.targets[old_target] then
        old_target = nil
    end
    return old_target or (blocks[1] and blocks[1][1])
end

function ObjectiveTrackerFrameHandler:OnAction(button)
    local target = self:GetTarget()
    assert(target)
    local handler = self.targets[target]["on_"..button:lower()]
    if handler then handler(target) end
end


function QuestContextMenu:__constructor()
    __super(self)

    self.menuitem_focus = self:CreateButton(SUPER_TRACK_QUEST,
        function() C_SuperTrack.SetSuperTrackedQuestID(self.quest_id) end)
    self.menuitem_unfocus = self:CreateButton(STOP_SUPER_TRACK_QUEST,
        function() C_SuperTrack.SetSuperTrackedQuestID(0) end)

    self.menuitem_show_details = self:CreateButton(OBJECTIVES_VIEW_IN_QUESTLOG,
        function() QuestUtil.OpenQuestDetails(self.quest_id) end)
    self.menuitem_hide_details = self:CreateButton(OBJECTIVES_VIEW_IN_QUESTLOG,
        function() QuestUtil.OpenQuestDetails(self.quest_id) end)

    self.menuitem_show_map = self:CreateButton(OBJECTIVES_SHOW_QUEST_MAP,
        function() QuestMapFrame_OpenToQuestDetails(self.quest_id) end)

    self.menuitem_untrack = self:CreateButton(OBJECTIVES_STOP_TRACKING,
        function() C_QuestLog.RemoveQuestWatch(self.quest_id) end)

    self.menuitem_share = self:CreateButton(SHARE_QUEST,
        function() QuestUtil.ShareQuest(self.quest_id) end)

    self.menuitem_abandon = self:CreateButton(ABANDON_QUEST_ABBREV,
        function() QuestMapQuestOptions_AbandonQuest(self.quest_id) end)
end

function QuestContextMenu:Configure(header, quest_id)
    self.quest_id = quest_id

    if C_SuperTrack.GetSuperTrackedQuestID() ~= self.quest_id then
        self:AppendButton(self.menuitem_focus)
    else
        self:AppendButton(self.menuitem_unfocus)
    end

    if QuestUtil.IsShowingQuestDetails(self.quest_id) then
        self:AppendButton(self.menuitem_show_details)
    else
        self:AppendButton(self.menuitem_hide_details)
    end

    self:AppendButton(self.menuitem_show_map)

    if QuestUtil.CanRemoveQuestWatch() then
        self:AppendButton(self.menuitem_untrack)
    end

    if C_QuestLog.IsPushableQuest(self.quest_id) and IsInGroup() then
        self:AppendButton(self.menuitem_share)
    end

    self:AppendButton(self.menuitem_abandon)
end
