local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

-- HousingDashboardFrame is a tabbed container, which we implement roughly
-- following the pattern of CollectionsJournal.  Bizarrely, the container
-- sports two different sets of tabs, one on the top and one on the right;
-- we treat them as a single tab set and cycle through them appropriately.

local HousingDashboardFrameHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(HousingDashboardFrameHandler)
local HouseUpgradeFrameHandler = class(MenuCursor.StandardMenuFrame)
local CatalogContentHandler = class(MenuCursor.StandardMenuFrame)


function HousingDashboardFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch("Blizzard_HousingDashboard")
end

function HousingDashboardFrameHandler.OnAddOnLoaded(class, cursor)
    class.instance = class()
    class.instance_HouseUpgrade = HouseUpgradeFrameHandler()
    class.instance_CatalogContent = CatalogContentHandler()
    class.panel_instances = {class.instance_HouseUpgrade,
                             -- Endeavors tab is "Coming Soon!" as of 11.2.7
                             class.instance_CatalogContent}
end

function HousingDashboardFrameHandler:__constructor()
    __super(self, HousingDashboardFrame)
    self.cancel_func = nil
    self.cancel_button = self.frame.CloseButton
    self:HookShow(self.frame)
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function HousingDashboardFrameHandler:OnShow()
    local HouseContentFrame = self.frame.HouseInfoContent.ContentFrame
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            local parent = panel_instance.frame:GetParent()
            if parent ~= HouseContentFrame or parent:GetParent():IsShown() then
                panel_instance:OnShow()
                return
            end
        end
    end
end

function HousingDashboardFrameHandler:OnHide()
    local HouseContentFrame = self.frame.HouseInfoContent.ContentFrame
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            local parent = panel_instance.frame:GetParent()
            if parent ~= HouseContentFrame or parent:GetParent():IsShown() then
                panel_instance:OnHide()
                return
            end
        end
    end
end

function HousingDashboardFrameHandler:OnTabCycle(direction)
    local f = self.frame
    local tabsys = f.HouseInfoContent.ContentFrame.TabSystem
    local max_index = 1
    local index
    while tabsys:GetTabButton(max_index) do
        -- See notes in MenuFrame:SetTabSystem() about breaking encapsulation.
        if tabsys:GetTabButton(max_index).isSelected then
            index = max_index
        end
        max_index = max_index + 1
    end
    -- HACK: The side tab button doesn't have a GetChecked method (it isn't
    -- even a Button!) so we have to key off the visibility of the panel.
    local catalog_selected = (f.CatalogContent:IsVisible())
    if catalog_selected then
        index = max_index
    end
    local new_index = index or 0
    repeat
        new_index = new_index + direction
        if new_index < 1 then
            new_index = max_index
        elseif new_index > max_index then
            new_index = 1
        end
        -- Here again, we have to break encapsulation to get tab enable state.
    until not (new_index < max_index
               and tabsys:GetTabButton(new_index).forceDisabled)
    if new_index == max_index then
        f.CatalogTabButton:OnMouseUp("LeftButton", true)
    else
        f.HouseInfoTabButton:OnMouseUp("LeftButton", true)
        tabsys:SetTab(new_index)
    end
end

---------------------------------------------------------------------------

-- Basically a MajorFactionRenownFrame.

function HouseUpgradeFrameHandler:__constructor()
    __super(self, HousingDashboardFrame.HouseInfoContent.ContentFrame.HouseUpgradeFrame)
    self.cancel_func = nil
    self.cancel_button = HousingDashboardFrameHandler.instance.cancel_button
    self.tab_handler = HousingDashboardFrameHandler.instance.tab_handler
    self.has_Button3 = true  -- Used to move to the teleport button.
    -- Have to wait a frame before rewards are laid out.
    hooksecurefunc(self.frame, "SetRewards", function()
        RunNextFrame(function() self:RefreshTargets() end)
    end)
end

function HouseUpgradeFrameHandler:RefreshTargets()
    if self.frame:IsVisible() then
        local target = self:GetTarget()
        assert(not target or target == self.frame.TrackFrame)
        self:SetTargets()
    end
end

function HouseUpgradeFrameHandler:SetTargets()
    local f = self.frame
    local bar = f.CurrentLevelFrame.HouseBarFrame
    local tele = f.TeleportToHouseButton
    local track = f.TrackFrame
    self.targets = {
        [bar] = {on_enter = self.OnEnterBar, on_leave = self.OnLeaveBar,
                 up = false, down = track, left = tele, right = tele},
        [tele] = {can_activate = true, send_enter_leave = true,
                  up = false, down = track, left = bar, right = bar},
        [track] = {is_default = true, dpad_override = true,
                   x_offset = 296,
                   up = bar, down = false, left = false, right = false},
    }
    -- Prevent moving to the rewards during level-up animations to preserve
    -- the invariant that the cursor is always on the reward track frame
    -- when the reward list changes.
    if f.displayLevel and f.displayLevel < f.actualLevel then
        self.targets[bar] = nil
        self.targets[tele] = nil
        self.targets[track].up = false
        return
    end
    local top, bottom, bottom_right
    for reward in f.rewardPoolLarge:EnumerateActive() do
        self.targets[reward] = {send_enter_leave = true}
        if not top or reward:GetTop() > top:GetTop() or (reward:GetTop() == top:GetTop() and reward:GetLeft() < top:GetLeft()) then
            top = reward
        end
        if not bottom or reward:GetTop() < bottom:GetTop() or (reward:GetTop() == bottom:GetTop() and reward:GetLeft() < bottom:GetLeft()) then
            bottom = reward
        end
        if not bottom_right or reward:GetTop() < bottom_right:GetTop() or (reward:GetTop() == bottom_right:GetTop() and reward:GetLeft() > bottom_right:GetLeft()) then
            bottom_right = reward
        end
    end
    if top then
        self.targets[track].down = top
        self.targets[bar].up = bottom
        self.targets[tele].up = bottom_right
        if bottom then
            for target, params in pairs(self.targets) do
                if target:GetTop() == bottom:GetTop() then
                    params.down = bar
                end
            end
        end
    else
        self.targets[track].down = bar
        self.targets[bar].up = track
        self.targets[tele].up = track
    end
end

function HouseUpgradeFrameHandler:OnDPad(dir)
    local f = self.frame
    local track = f.TrackFrame
    assert(self:GetTarget() == f.TrackFrame)
    if dir == "left" then
        -- This TrackFrame doesn't support mouse scrolling (bug?)
        -- so we have to implement it manually.
        local index = track:GetCenterIndex()
        if index > 1 then
            track:SetSelection(index - 1)
        end
    elseif dir == "right" then
        local index = track:GetCenterIndex()
        if index < #track:GetElements() then
            track:SetSelection(index + 1)
        end
    else
        self:SetTarget(self.targets[f.TrackFrame][dir])
    end
end

function HouseUpgradeFrameHandler:OnAction(button)
    assert(button == "Button3")
    self:SetTarget(self.frame.TeleportToHouseButton)
end

function HouseUpgradeFrameHandler.OnEnterBar(bar)
    -- The default implementation forces the tooltip to the (mouse) cursor,
    -- so we have to roll our own.  See also OnEnterItemButton() in
    -- MerchantFrame.lua.
    GameTooltip:SetOwner(bar, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("LEFT", bar, "RIGHT", 10, 0)
    local parent = bar:GetParent():GetParent()
    GameTooltip_AddNormalLine(GameTooltip, string.format(HOUSING_DASHBOARD_HOUSE_LEVEL, parent.actualLevel));
    GameTooltip_AddHighlightLine(GameTooltip, string.format(HOUSING_DASHBOARD_NEIGHBORHOOD_FAVOR, parent.houseFavor, parent.houseFavorNeeded));
    GameTooltip_AddHighlightLine(GameTooltip, HOUSING_DASHBOARD_NEIGHBORHOOD_FAVOR_TOOLTIP);
    GameTooltip:Show();
end

function HouseUpgradeFrameHandler.OnLeaveBar(bar)
    bar:GetParent():OnLeave()
end

---------------------------------------------------------------------------

function CatalogContentHandler:__constructor()
    __super(self, HousingDashboardFrame.CatalogContent)
    self.cancel_func = nil
    self.cancel_button = HousingDashboardFrameHandler.instance.cancel_button
    self.on_prev_page = function() self:OnCycleCategory(-1) end
    self.on_next_page = function() self:OnCycleCategory(1) end
    self.tab_handler = HousingDashboardFrameHandler.instance.tab_handler
    self.has_Button3 = true  -- Used to swap between categories and items.
    self.has_Button4 = true  -- Used to toggle the filter dropdown.

    hooksecurefunc(self.frame, "UpdateCatalogData",
                   function() self:OnItemListUpdated() end)

    -- Current list of category buttons, sorted by position.  Effectively
    -- a sorted cache of Categories.categoryPool:EnumerateFrames().
    self.categories = {}
    -- Is the current target a category button (true) or item button (false)?
    self.is_categories = nil
    -- Index of the current cursor position in the category list.
    -- As a special case, the"back" category button is given index 0.
    self.category_index = nil
    -- {isSubcategory, ID} pair of the currently targeted category.
    -- Used to detect when the category list has changed.
    self.category_id = {}
    -- ID (entryID.recordID) of the currently targeted item.
    self.item_id = nil
    -- Cache table for the filter dropdown handler.
    self.filter_dropdown_cache = {}
    -- Flag and retry counter for dealing with delayed loads.
    self.refresh_pending = false
    self.refresh_retries = 0
end

function CatalogContentHandler:RefreshTargets(is_retry)
    if is_retry then
        self.refresh_retries = self.refresh_retries + 1
        if self.refresh_retries > 100 then
            error("Failed to refresh menu targets")
        end
    else
        -- Always reset the retry counter even if we have a refresh already
        -- pending; we effectively merge the two into a single call.
        self.refresh_retries = 0
        if self.refresh_pending then
            return
        end
    end
    self:SetTarget(nil)
    local target = self:SetTargets()
    if target == "retry" then
        RunNextFrame(function() self:RefreshTargets(true) end)
    else
        self:SetTarget(target)
    end
end

function CatalogContentHandler:SetTargets()
    self.targets = {}
    local target

    if self.is_categories then

        local function PostClickCategory(button)
            self:RefreshTargets()
        end
        -- The housing buttons use a custom highlight implementation that
        -- relies explicitly on IsMouseMotionFocus(), so we have to
        -- manually override that.  We use slightly roundabout logic to
        -- try and minimize taint to the button itself.
        local function CallEnterLeaveWithWrap(button, is_enter)
            local func = button:GetScript(is_enter and "OnEnter" or "OnLeave")
            local saved_metatable = getmetatable(button)
            local override = {
                IsMouseMotionFocus = function() return is_enter end,
            }
            setmetatable(override, saved_metatable)
            local metatable = {__index = override}
            setmetatable(button, metatable)
            func(button)
            setmetatable(button, saved_metatable)
        end
        local function OnEnterCategory(button)
            CallEnterLeaveWithWrap(button, true)
        end
        local function OnLeaveCategory(button)
            CallEnterLeaveWithWrap(button, false)
        end

        local Categories = self.frame.Categories
        local BackButton = Categories.BackButton
        local AllSubcategoriesStandIn = Categories.AllSubcategoriesStandIn

        local buttons = {}
        self.categories = {}
        -- The Categories frame doesn't seem to store any explicit flag for
        -- whether the current list is a category or subcategory list, and
        -- it uses separate frame pools for each, so we have to check both.
        for button in Categories.categoryPool:EnumerateActive() do
            local y = button:GetTop()
            assert(y)
            tinsert(buttons, {button, y})
        end
        if #buttons == 0 then
            assert(AllSubcategoriesStandIn:IsShown())
            local y = AllSubcategoriesStandIn:GetTop()
            assert(y)
            tinsert(buttons, {AllSubcategoriesStandIn, y})
            for button in Categories.subcategoryPool:EnumerateActive() do
                local y = button:GetTop()
                assert(y)
                tinsert(buttons, {button, y})
            end
        end
        if #buttons == 0 then
            return "retry"
        end
        table.sort(buttons, function(a,b) return a[2] > b[2] end)
        for index, button_y in ipairs(buttons) do
            self.categories[index] = button_y[1]
        end

        local first, last
        if BackButton:IsShown() then
            self.targets[BackButton] =
                {can_activate = true, on_click = PostClickCategory,
                 on_enter = OnEnterCategory, on_leave = OnLeaveCategory,
                 left = false, right = false}
            first = BackButton
            last = BackButton
            if self.category_index == 0 then
                target = BackButton
            end
        end
        for index, button in ipairs(self.categories) do
            self.targets[button] =
                {can_activate = true, on_click = PostClickCategory,
                 on_enter = OnEnterCategory, on_leave = OnLeaveCategory,
                 up = last, left = false, right = false}
            if last then
                self.targets[last].down = button
            end
            first = first or button
            last = button
            if self.category_index == index then
                local cat_issub, cat_id
                if button == AllSubcategoriesStandIn then
                    cat_issub, cat_id = true, nil
                else
                    cat_issub, cat_id = button.isSubcategory, button.ID
                end
                if self.category_id[1] == cat_issub and self.category_id[2] == cat_id then
                    target = button
                end
            end
        end
        assert(first)
        self.targets[first].up = last
        self.targets[last].down = first
        target = target or self.categories[1]

    else  -- cursor is in the item list

        local function Filter(element, index)
            local id = element.entryID.recordID
            local attrib = {id = id, can_activate = true,
                            send_enter_leave = true}
            return attrib, (id == self.item_id)
        end
        local list, match = self:AddScrollBoxTargets_3Column(
            self.frame.OptionsContainer.ScrollBox, Filter)
        target = match or list[1]

    end  -- if self.categories

    return target
end

function CatalogContentHandler:OnShow()
    self.is_categories = true
    self.category_index = nil
    self.category_id = {}
    self.item_id = nil
    __super(self)
end

function CatalogContentHandler:EnterTarget(target)
    __super(self, target)
    if self.is_categories then
        local f = self.frame
        if target == f.Categories.BackButton then
            self.category_index = 0
            self.category_id = {}
        else
            local index
            for i, button in ipairs(self.categories) do
                if target == button then
                    index = i
                    break
                end
            end
            assert(index)
            self.category_index = index
            if button == f.Categories.AllSubcategoriesStandIn then
                self.category_id = {true, nil}
            else
                self.category_id = {target.isSubcategory, target.ID}
            end
        end
    else
        self.item_id = self.targets[target].id
    end
end

function CatalogContentHandler:OnCycleCategory(direction)
    -- The "back" button is a separate button outside the category list,
    -- so we don't have to explicitly avoid it.
    local new_index = self.category_index + direction
    if new_index < 1 then
        new_index = max_index
    elseif new_index > max_index then
        new_index = 1
    end
    self.frame.Categories:OnCategoryClicked(self.categories[new_index])
    self:RefreshTargets()
end

function CatalogContentHandler:OnAction(button)
    if button == "Button3" then
        self.is_categories = not self.is_categories
        self:RefreshTargets()
    else
        assert(button == "Button4")
        local filter_button = self.frame.Filters.FilterDropdown
        filter_button:SetMenuOpen(true)
        if filter_button:IsMenuOpen() then
            local dropdown = self.SetupDropdownMenu(
                filter_button, self.filter_dropdown_cache, nil,
                function()
                    self:RefreshTargets()
                    -- FIXME: need handling for submenus
                end)
            dropdown.has_Button4 = true
            function dropdown:OnAction(button)
                assert(button == "Button4")
                filter_button:SetMenuOpen(false)
            end
            dropdown:Enable()
        end
    end
end

function CatalogContentHandler:OnItemListUpdated()
    if self:IsEnabled() and not self.is_category then
        self:RefreshTargets()
    end
end
