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

local ProfessionsFrameHandler = class(MenuFrame)
Cursor.RegisterFrameHandler(ProfessionsFrameHandler)
-- These are technically addon frames, but we add the addon watch in
-- ProfessionsFrameHandler and don't create these instances until it's
-- loaded.  We inherit CoreMenuFrame for its other conveniences.
local CraftingPageHandler = class(CoreMenuFrame)
local SchematicFormHandler = class(MenuFrame)
local QualityDialogHandler = class(CoreMenuFrame)
local ItemFlyoutHandler = class(CoreMenuFrame)
local SpecPageHandler = class(CoreMenuFrame)
local DetailedViewHandler = class(MenuFrame)
local OrderListHandler = class(CoreMenuFrame)
local OrderViewHandler = class(CoreMenuFrame)


-------- Top-level frame

function ProfessionsFrameHandler.Initialize(class, cursor)
    class:RegisterAddOnWatch("Blizzard_Professions")
end

function ProfessionsFrameHandler.OnAddOnLoaded(class)
    local instance = class()
    class.instance = instance
    class.instance_CraftingPage = CraftingPageHandler()
    class.instance_SchematicForm = SchematicFormHandler()
    class.instance_QualityDialog = QualityDialogHandler()
    class.instance_ItemFlyout = ItemFlyoutHandler()
    class.instance_SpecPage = SpecPageHandler()
    class.instance_DetailedView = DetailedViewHandler()
    class.instance_OrderList = OrderListHandler()
    class.instance_OrderView = OrderViewHandler()
end

function ProfessionsFrameHandler:__constructor()
    self:__super(ProfessionsFrame)
    -- ProfessionsFrame itself is just a holder for the tabs and the
    -- individual tab content pages, so we don't have any menu behavior
    -- of our own.  We still HookShow() because the current tab page
    -- remains shown even while this frame is closed.
    self:HookShow(ProfessionsFrame)
end

function ProfessionsFrameHandler.CancelMenu()  -- Static method.
    HideUIPanel(ProfessionsFrame)
end

function ProfessionsFrameHandler:OnShow()
    if ProfessionsFrame.CraftingPage:IsShown() then
        ProfessionsFrameHandler.instance_CraftingPage:OnShow()
    elseif ProfessionsFrame.SpecPage:IsShown() then
        ProfessionsFrameHandler.instance_SpecPage:OnShow()
    elseif ProfessionsFrame.OrdersPage:IsShown() then
        if ProfessionsFrame.OrdersPage.BrowseFrame:IsShown() then
            ProfessionsFrameHandler.instance_OrderList:OnShow()
        elseif ProfessionsFrame.OrdersPage.OrderView:IsShown() then
            ProfessionsFrameHandler.instance_OrderView:OnShow()
        end
    end
end

function ProfessionsFrameHandler:OnHide()
    if ProfessionsFrame.CraftingPage:IsShown() then
        ProfessionsFrameHandler.instance_CraftingPage:OnHide()
    elseif ProfessionsFrame.SpecPage:IsShown() then
        ProfessionsFrameHandler.instance_SpecPage:OnHide()
    elseif ProfessionsFrame.OrdersPage.BrowseFrame:IsShown() then
        ProfessionsFrameHandler.instance_OrderList:OnHide()
    elseif ProfessionsFrame.OrdersPage:IsShown() then
        if ProfessionsFrame.OrdersPage.BrowseFrame:IsShown() then
            ProfessionsFrameHandler.instance_OrderList:OnHide()
        elseif ProfessionsFrame.OrdersPage.OrderView:IsShown() then
            ProfessionsFrameHandler.instance_OrderView:OnHide()
        end
    end
end


-------- Crafting wrapper frame and recipe list

function CraftingPageHandler:__constructor()
    self:__super(ProfessionsFrame.CraftingPage)
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    self.cancel_func = ProfessionsFrameHandler.CancelMenu
    self.tab_system = ProfessionsFrame.TabSystem
end

function CraftingPageHandler:TRADE_SKILL_LIST_UPDATE()
    if self.need_refresh then
        -- The list itself apparently isn't ready until the next frame.
        RunNextFrame(function()
            self:SetTarget(self:RefreshTargets())
        end)
    end
end

function CraftingPageHandler:OnShow()
    assert(ProfessionsFrame:IsShown())
    self.need_refresh = true
    self.targets = {}
    self:Enable()
    RunNextFrame(function()
        self:SetTarget(self:RefreshTargets())
    end)
end

function CraftingPageHandler:OnHide()
    self:Disable()
    ProfessionsFrameHandler.instance_SchematicForm:Disable()
end

function CraftingPageHandler:FocusRecipe(tries)
    local CraftingPage = ProfessionsFrame.CraftingPage
    local SchematicForm = CraftingPage.SchematicForm
    assert(SchematicForm:IsShown())
    if not (CraftingPage.CreateButton:IsShown()
            or SchematicForm.recraftSlot:IsShown()) then
        -- Recipe data is still loading, or recipe is not learned.
        tries = tries or 10
        if tries > 0 then
            RunNextFrame(function() self:FocusRecipe(tries-1) end)
        end
        return
    end
    local form = ProfessionsFrameHandler.instance_SchematicForm
    local initial_target = form:SetTargets()
    form:Enable(initial_target)
end

local PROFESSION_GEAR_SLOTS = {
    "Prof0ToolSlot",
    "Prof0Gear0Slot",
    "Prof0Gear1Slot",
    "Prof1ToolSlot",
    "Prof1Gear0Slot",
    "Prof1Gear1Slot",
    "CookingToolSlot",
    "CookingGear0Slot",
    "FishingToolSlot",
}
function CraftingPageHandler:RefreshTargets(initial_element)
    local CraftingPage = ProfessionsFrame.CraftingPage

    self:ClearTarget()
    self.targets = {}
    local top, bottom, initial = nil, nil, nil

    self.targets[CraftingPage.LinkButton] = {
        can_activate = true, lock_highlight = true,
        up = false, down = false}
    for _, slot_id in ipairs(PROFESSION_GEAR_SLOTS) do
        local slot = CraftingPage[slot_id]
        if slot:IsShown() then
            self.targets[slot] = {
                lock_highlight = true, send_enter_leave = true,
                up = false, down = false}
        end
    end
    local RecipeScroll = CraftingPage.RecipeList.ScrollBox
    local index = 0
    RecipeScroll:ForEachElementData(function(element)
        self.need_refresh = false
        index = index + 1
        local data = element:GetData()
        if data.categoryInfo or data.recipeInfo then
            local pseudo_frame =
                MenuFrame.PseudoFrameForScrollElement(RecipeScroll, index)
            self.targets[pseudo_frame] = {
                is_scroll_box = true, can_activate = true,
                up = bottom or false, down = false,
                left = false, right = CraftingPage.LinkButton}
            if data.recipeInfo then
                self.targets[pseudo_frame].on_click = function()
                    self:FocusRecipe()
                end
            else  -- is a category header
                self.targets[pseudo_frame].on_click = function()
                    local target = self:RefreshTargets(element)
                    self:SetTarget(target)
                end
            end
            if bottom then
                self.targets[bottom].down = pseudo_frame
            end
            if not top then
                top = pseudo_frame
                self.targets[CraftingPage.LinkButton].left = pseudo_frame
            end
            bottom = pseudo_frame
            if initial_element then
                if initial_element == element then
                    initial = pseudo_frame
                end
            else
                if not initial and self:GetTargetFrame(pseudo_frame) then
                    initial = pseudo_frame
                end
            end
        end
    end)
    if top then
        self.targets[top].up = bottom
        self.targets[bottom].down = top
    end

    return initial or top
end


-------- Recipe details frame

function SchematicFormHandler:__constructor()
    self:__super(ProfessionsFrame.CraftingPage.SchematicForm)
    self:HookShow(ProfessionsFrame.CraftingPage.CreateAllButton,
                  self.OnShowCreateAllButton, self.OnHideCreateAllButton)
    self:HookShow(
        ProfessionsFrame.CraftingPage.SchematicForm.recraftSlot.OutputSlot,
        self.OnShowRecraftOutputSlot, false)
    self.cancel_func = function(self)
        self:Disable()
        self.targets = {}  -- suppress update calls from CreateAllButton:Show() hook
    end
    self.tab_system = ProfessionsFrame.TabSystem
end

function SchematicFormHandler:OnShowCreateAllButton()
    -- FIXME: this gets called every second, avoid update calls if no change
    if self.targets[ProfessionsFrame.CraftingPage.CreateButton] then
        self:UpdateMovement()
    end
end

function SchematicFormHandler:OnHideCreateAllButton()
    if self.targets[ProfessionsFrame.CraftingPage.CreateButton] then
        local CraftingPage = ProfessionsFrame.CraftingPage
        local cur_target = self:GetTarget()
        if (cur_target == CraftingPage.CreateAllButton
         or cur_target == CraftingPage.CreateMultipleInputBox.DecrementButton
         or cur_target == CraftingPage.CreateMultipleInputBox.IncrementButton)
        then
            self:SetTarget(CraftingPage.CreateButton)
        end
        self:UpdateMovement()
    end
end

function SchematicFormHandler:OnShowRecraftOutputSlot()
    local SchematicForm = ProfessionsFrame.CraftingPage.SchematicForm
    if SchematicForm:IsShown() then
        if not self.targets[SchematicForm.recraftSlot.OutputSlot] then
            RunNextFrame(function()
                local target = self:GetTarget()
                self:SetTargets()  -- Should not invalidate any existing targets.
                assert(not target or self.targets[target])
            end)
        end
    end
end

local function SchematicForm_ClickItemButton(button)
    local onMouseDown = button:GetScript("OnMouseDown")
    assert(onMouseDown)
    -- We pass down=true for completeness, but all current implementations
    -- ignore that parameter and don't register for button-up events.
    onMouseDown(button, "LeftButton", true)
end

function SchematicFormHandler:SetTargets()
    local CraftingPage = ProfessionsFrame.CraftingPage
    local SchematicForm = CraftingPage.SchematicForm

    self.targets = {}

    local top_icon, top_icon2
    local rs = SchematicForm.recraftSlot
    if rs:IsShown() then
        self.targets[rs.InputSlot] = {
            on_click = SchematicForm_ClickItemButton, send_enter_leave = true,
            left = false, right = false}
        if rs.OutputSlot:IsShown() then
            self.targets[rs.InputSlot].right = rs.OutputSlot
            self.targets[rs.OutputSlot] = {
                send_enter_leave = true, left = rs.InputSlot, right = false}
            top_icon2 = rs.OutputSlot
        end
        top_icon = rs.InputSlot
    else
        self.targets[SchematicForm.OutputIcon] = {send_enter_leave = true}
        top_icon = SchematicForm.OutputIcon
    end

    -- We add these unconditionally, and then exclude buttons that aren't
    -- shown from the cursor movement logic in UpdateMovement().
    self.targets[CraftingPage.CreateAllButton] = {
        can_activate = true, lock_highlight = true,
        down = top_icon, left = false}
    self.targets[CraftingPage.CreateMultipleInputBox.DecrementButton] = {
        on_click = MenuFrame.ClickNumericSpinnerButton, lock_highlight = true,
        down = top_icon}
    self.targets[CraftingPage.CreateMultipleInputBox.IncrementButton] = {
        on_click = MenuFrame.ClickNumericSpinnerButton, lock_highlight = true,
        down = top_icon}
    self.targets[CraftingPage.CreateButton] = {
        can_activate = true, lock_highlight = true, send_enter_leave = true,
        down = top_icon, right = false}

    local r_left, r_right = false, false
    local frsc = SchematicForm.Details.CraftingChoicesContainer.FinishingReagentSlotContainer
    if frsc and frsc:IsVisible() then
        for _, frame in ipairs({frsc:GetChildren()}) do
            local button = frame:GetChildren()
            self.targets[button] = {
                on_click = SchematicForm_ClickItemButton,
                lock_highlight = true, send_enter_leave = true,
                up = false, down = CraftingPage.CreateButton}
            if not r_left or button:GetLeft() < r_left:GetLeft() then
                r_left = button
            end
            if not r_right or button:GetLeft() > r_right:GetLeft() then
                r_right = button
            end
        end
    end
    local ctb = SchematicForm.Details.CraftingChoicesContainer.ConcentrateContainer.ConcentrateToggleButton
    if ctb and ctb:IsVisible() then
        self.targets[ctb] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true,
            up = false, down = CraftingPage.CreateButton}
        if not r_left or ctb:GetLeft() < r_left:GetLeft() then
            r_left = ctb
        end
        if not r_right or ctb:GetLeft() > r_right:GetLeft() then
            r_right = ctb
        end
    end

    local r_top, r_top2, r_bottom, r_bottom2 = false, false, false, false
    if SchematicForm.Reagents:IsShown() then
        local reagents = {}
        for _, frame in ipairs({SchematicForm.Reagents:GetChildren()}) do
            local button = frame:GetChildren()
            if button:IsVisible() then
                self.targets[button] = {
                    lock_highlight = true, send_enter_leave = true,
                    left = false, right = r_left}
                if button:GetScript("OnMouseDown") then
                    self.targets[button].on_click = SchematicForm_ClickItemButton
                elseif button:GetScript("OnClick") then
                    self.targets[button].can_activate = true
                end
                tinsert(reagents, button)
            end
        end
        reagents = MenuFrame.SortTargetGrid(reagents)
        for _, row in ipairs(reagents) do
            assert(#row <= 2, "Too many reagents in row")
            local left, right = unpack(row)
            self.targets[left].up = r_bottom or top_icon
            self.targets[left].left = false
            self.targets[left].right = r_left
            if r_bottom then
                self.targets[r_bottom].down = left
            end
            if right then
                self.targets[left].right = right
                self.targets[right].up = r_bottom2 or top_icon2 or top_icon
                self.targets[right].left = left
                self.targets[right].right = r_left
                if r_bottom2 then
                    self.targets[r_bottom2].down = right
                end
            end
            r_top = r_top or left
            r_top2 = r_top2 or right or false
            r_bottom = left
            r_bottom2 = right or false
        end
        if r_bottom and r_left then
            self.targets[r_left].left = r_bottom2 or r_bottom
        end
    elseif rs:IsShown() then
        r_top = rs.InputSlot
        r_bottom = rs.InputSlot
    end

    if SchematicForm.OptionalReagents:IsShown() then
        local or_left, or_right
        for _, frame in ipairs({SchematicForm.OptionalReagents:GetChildren()}) do
            local button = frame:GetChildren()
            if button:IsVisible() then
                self.targets[button] = {
                    on_click = SchematicForm_ClickItemButton,
                    lock_highlight = true, send_enter_leave = true,
                    up = r_bottom, down = CraftingPage.CreateAllButton}
                if not or_left or button:GetLeft() < or_left:GetLeft() then
                    or_left = button
                end
                if not or_right or button:GetLeft() > or_right:GetLeft() then
                    or_right = button
                end
            end
        end
        if or_left then
            self.targets[or_left].left = false
            r_bottom = or_left
        end
        if or_right then
            self.targets[or_right].right = r_left
            if r_left then
                self.targets[r_left].left = or_right
            end
        end
    end

    local create_left_up = r_left or r_bottom or top_icon
    local create_right_up = r_right or r_bottom or top_icon
    self.targets[CraftingPage.CreateAllButton].up = create_left_up
    self.targets[CraftingPage.CreateMultipleInputBox.DecrementButton].up = create_left_up
    self.targets[CraftingPage.CreateMultipleInputBox.IncrementButton].up = create_left_up
    self.targets[CraftingPage.CreateButton].up = create_right_up
    self.r_bottom = r_bottom
    self.r_bottom2 = r_bottom2

    self:UpdateMovement()
    return r_top
end

function SchematicFormHandler:UpdateMovement()
    local CraftingPage = ProfessionsFrame.CraftingPage
    local SchematicForm = CraftingPage.SchematicForm

    local create_left
    if CraftingPage.CreateAllButton:IsShown() then
        self.targets[CraftingPage.CreateButton].left = nil
        create_left = CraftingPage.CreateAllButton
    elseif CraftingPage.CreateButton:IsShown() then
        self.targets[CraftingPage.CreateButton].left = false
        create_left = CraftingPage.CreateButton
    else
        create_left = false
    end

    if self.targets[SchematicForm.OutputIcon] then
        self.targets[SchematicForm.OutputIcon].up = create_left
    end
    if self.targets[SchematicForm.recraftSlot.InputSlot] then
        self.targets[SchematicForm.recraftSlot.InputSlot].up = create_left
    end
    if self.targets[SchematicForm.recraftSlot.OutputSlot] then
        self.targets[SchematicForm.recraftSlot.OutputSlot].up = create_left
    end

    local r_bottom, r_bottom2 = self.r_bottom, self.r_bottom2
    if r_bottom then
        self.targets[r_bottom].down = create_left
    end
    if r_bottom2 then
        self.targets[r_bottom2].down = create_left
    end
    local SchematicForm = CraftingPage.SchematicForm
    local frsc = SchematicForm.Details.CraftingChoicesContainer.FinishingReagentSlotContainer
    if frsc and frsc:IsVisible() then
        for _, frame in ipairs({frsc:GetChildren()}) do
            local button = frame:GetChildren()
            if self.targets[button] then
                self.targets[button].down = create_left
            end
        end
    end
    if SchematicForm.OptionalReagents:IsShown() then
        for _, frame in ipairs({SchematicForm.OptionalReagents:GetChildren()}) do
            local button = frame:GetChildren()
            if self.targets[button] then
                self.targets[button].down = create_left
            end
        end
    end
end


-------- Reagent quality selection dialog

function QualityDialogHandler:__constructor()
    local QualityDialog = ProfessionsFrame.CraftingPage.SchematicForm.QualityDialog
    self:__super(QualityDialog)
    self.cancel_func = nil
    self.cancel_button = QualityDialog.CancelButton
    self.targets = {
        [QualityDialog.Container1.EditBox.DecrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container1.EditBox.IncrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container2.EditBox.DecrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container2.EditBox.IncrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container3.EditBox.DecrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container3.EditBox.IncrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.AcceptButton] = {
            can_activate = true, lock_highlight = true, is_default = true},
        [QualityDialog.CancelButton] = {
            can_activate = true, lock_highlight = true},
    }
end


-------- Item selection dialog

function ItemFlyoutHandler:__constructor()
    -- The item selector popup doesn't have a global reference, so we need
    -- this hack to get the frame.
    local ItemFlyout = OpenProfessionsItemFlyout(UIParent, UIParent)
    CloseProfessionsItemFlyout()
    self:__super(ItemFlyout)
    self.cancel_func = CloseProfessionsItemFlyout  -- Blizzard function.
end

function ItemFlyoutHandler:OnShow()
    self.targets = {}
    self:Enable()
    -- FIXME: this still isn't good enough to get the list after a /reload
    RunNextFrame(function() self:RefreshTargets() end)
end

function ItemFlyoutHandler:RefreshTargets()
    local frame = self.frame
    local ItemScroll = frame.ScrollBox
    local checkbox = frame.HideUnownedCheckbox
    self.targets = {
        [checkbox] = {can_activate = true, lock_highlight = true,
                      on_click = function()
                          -- We have to wait a frame for button layout.
                          -- Ensure that a D-pad press during that frame
                          -- doesn't leave us on a vanished button.
                          self.targets = {[checkbox] = self.targets[checkbox]}
                          RunNextFrame(function() self:RefreshTargets() end)
                      end},
    }
    local default = nil
    local last_y = nil
    local rows = {}
    -- Avoid errors in Blizzard code if the list is empty.
    if ItemScroll:GetDataProvider() then
        local index = 0
        ItemScroll:ForEachElementData(function(element)
            index = index + 1
            local button = ItemScroll:FindFrame(ItemScroll:FindElementData(index))
            if button then  -- FIXME: need to deal with overflowing lists (e.g. embellishments)
                local pseudo_frame =
                    MenuFrame.PseudoFrameForScrollElement(ItemScroll, index)
                self.targets[pseudo_frame] = {
                    is_scroll_box = true, can_activate = true,
                    up = false, down = false, left = false, right = false}
                default = default or pseudo_frame
                assert(self:GetTargetFrame(pseudo_frame) == button)
                assert(button:IsShown())
                assert(button:GetTop() ~= nil)
                local y = button:GetTop()
                if y == last_y then
                    tinsert(rows[#rows], pseudo_frame)
                else
                    last_y = y
                    tinsert(rows, {pseudo_frame})
                end
            end
        end)
        local first_row = rows[1]
        local last_row = rows[#rows]
        for i, row in ipairs(rows) do
            local prev_row = i > 1 and rows[i-1]
            local next_row = i < #rows and rows[i+1]
            for j, pseudo_frame in ipairs(row) do
                local target_info = self.targets[pseudo_frame]
                target_info.up = prev_row and prev_row[j] or checkbox
                target_info.down = next_row and (next_row[j] or next_row[#next_row]) or checkbox
                if j > 1 then
                    target_info.left = row[j-1]
                elseif prev_row then
                    target_info.left = prev_row[#prev_row]
                else
                    target_info.left = last_row[#last_row]
                end
                if j < #row then
                    target_info.right = row[j+1]
                elseif next_row then
                    target_info.right = next_row[1]
                else
                    target_info.right = first_row[1]
                end
            end
        end
        self.targets[checkbox].up = last_row[1]
        self.targets[checkbox].down = first_row[1]
    end
    local cur_target = self:GetTarget()
    self:SetTarget(cur_target or default or checkbox)
end


-------- Skill line frame

function SpecPageHandler:__constructor()
    local SpecPage = ProfessionsFrame.SpecPage
    self:__super(SpecPage)
    self.cancel_func = ProfessionsFrameHandler.CancelMenu
    self.tab_system = ProfessionsFrame.TabSystem
    self.on_prev_page = function() self:CycleTabs(-1) end
    self.on_next_page = function() self:CycleTabs(1) end
    self:HookShow(SpecPage.TreePreview, self.RefreshTargets,
                                        self.RefreshTargets)
    self:HookShow(SpecPage.UndoButton, self.RefreshTargets,
                                       self.RefreshTargetsForUndoOff)
    EventRegistry:RegisterCallback("ProfessionsSpecializations.TabSelected",
                                   function() self:RefreshTargets() end)

    -- Set to true on on tab cycling.  Causes SetTargets() to try and
    -- preserve the previous cursor position if possible.
    self.refresh_is_tab_cycle = false
    -- Set to true o switching between tree and summary views.  Causes
    -- SetTargets() to set the cursor position to the view-switch button
    -- instead of the usual default.
    self.refresh_is_view_toggle = false
    -- Used to prevent repeated calls in a single frame (see RefreshTargets()).
    self.refresh_pending = false
end

function SpecPageHandler:OnHide()
    self:Disable()
    ProfessionsFrameHandler.instance_DetailedView:Disable()
end

function SpecPageHandler:CycleTabs(dir)
    local SpecPage = ProfessionsFrame.SpecPage
    local tabs = {}
    for tab in SpecPage.tabsPool:EnumerateActive() do
        tinsert(tabs, {tab, tab:GetLeft()})
    end
    table.sort(tabs, function(a, b) return a[2] < b[2] end)
    local first, prev, cur, target
    for _, v in ipairs(tabs) do
        local tab = v[1]
        if tab.isSelected then
            cur = tab
            if dir < 0 and prev then
                target = prev
                break
            end
        else
            if dir > 0 and cur then
                target = tab
                break
            end
        end
        first = first or tab
        prev = tab
    end
    if not target then
        target = dir > 0 and first or prev
    end
    self.refresh_is_tab_cycle = true
    target:GetScript("OnClick")(target, "LeftButton", true)
end

function SpecPageHandler:SetTargets(prev_target, is_tab_cycle, is_view_toggle)
    local SpecPage = ProfessionsFrame.SpecPage
    if not SpecPage:IsVisible() then
        return nil
    end

    local new_target = nil
    self:ClearTarget()
    self.targets = {}

    if SpecPage.ApplyButton:IsVisible() then
        self.targets[SpecPage.ApplyButton] =
            {can_activate = true, lock_highlight = true,
             left = SpecPage.ViewPreviewButton, right = false}
        if SpecPage.UndoButton:IsShown() then
            self.targets[SpecPage.ApplyButton].right = SpecPage.UndoButton
            self.targets[SpecPage.UndoButton] =
                {can_activate = true, lock_highlight = true,
                 left = SpecPage.ApplyButton, right = false}
        end
        self.targets[SpecPage.ViewPreviewButton] =
            {on_click = function(frame) self:ClickViewToggleButton(frame) end,
             lock_highlight = true,
             left = false, right = SpecPage.ApplyButton}
        local root = self:AddSpecTreeTargets(true)
        self.targets[root].up = SpecPage.ApplyButton
        self.targets[SpecPage.ApplyButton].down = root
        self.targets[SpecPage.ViewPreviewButton].down = root
        if is_tab_cycle and (prev_target == SpecPage.ApplyButton or
                             prev_target == SpecPage.UndoButton or
                             prev_target == SpecPage.ViewPreviewButton) then
            new_target = prev_target
        elseif is_tab_cycle and prev_target == SpecPage.UnlockTabButton then
            new_target = SpecPage.ApplyButton
        elseif is_tab_cycle and (prev_target == SpecPage.BackToPreviewButton or
                                 prev_target == SpecPage.ViewTreeButton) then
            new_target = SpecPage.ViewPreviewButton
        else
            new_target = is_view_toggle and SpecPage.ViewPreviewButton or root
        end

    elseif SpecPage.BackToFullTreeButton:IsVisible() then
        self.targets[SpecPage.BackToFullTreeButton] =
            {on_click = function(frame) self:ClickViewToggleButton(frame) end,
             lock_highlight = true}
        new_target = SpecPage.BackToFullTreeButton

    elseif SpecPage.ViewTreeButton:IsVisible() then
        self.targets[SpecPage.ViewTreeButton] =
            {on_click = function(frame) self:ClickViewToggleButton(frame) end,
             lock_highlight = true}
        self.targets[SpecPage.UnlockTabButton] =
            {can_activate = true, lock_highlight = true}
        if is_tab_cycle and (prev_target == SpecPage.BackToFullTreeButton or
                             prev_target == SpecPage.ViewPreviewButton) then
            new_target = SpecPage.ViewTreeButton
        else
            new_target = (is_view_toggle and SpecPage.ViewTreeButton
                          or SpecPage.UnlockTabButton)
        end

    elseif SpecPage.BackToPreviewButton:IsVisible() then
        self.targets[SpecPage.BackToPreviewButton] =
            {on_click = function(frame) self:ClickViewToggleButton(frame) end,
             lock_highlight = true}
        self.targets[SpecPage.UnlockTabButton] =
            {can_activate = true, lock_highlight = true}
        local root = self:AddSpecTreeTargets(false)
        self.targets[root].up = SpecPage.UnlockTabButton
        self.targets[SpecPage.UnlockTabButton].down = root
        self.targets[SpecPage.BackToPreviewButton].down = root
        new_target = (is_view_toggle and SpecPage.BackToPreviewButton
                      or SpecPage.UnlockTabButton)

    else
        error("Unknown spec page state")
    end

    return new_target
end

function SpecPageHandler:AddSpecTreeTargets(clickable)
    local SpecPage = ProfessionsFrame.SpecPage
    local parent = {}  -- FIXME: Any way to get the root node directly?
    local buttons = {}
    for button in SpecPage:EnumerateAllTalentButtons() do
        local info = button:GetNodeInfo()
        buttons[info.ID] = button
        for _, edge in ipairs(info.visibleEdges) do
            assert(not parent[edge.targetNode])
            parent[edge.targetNode] = info.ID
        end
        self.targets[button] = {
            lock_highlight = true,
            -- ProfessionsSpecPathMixin:OnEnter() has an explicit
            -- IsMouseMotionFocus() check, so we have to override that.
            on_enter = function(frame)
                local saved_IsMouseMotionFocus = button.IsMouseMotionFocus
                button.IsMouseMotionFocus = function() return true end
                frame:OnEnter()
                button.IsMouseMotionFocus = saved_IsMouseMotionFocus
            end,
            on_leave = function(frame) frame:OnLeave() end,
        }
        if clickable then
            self.targets[button].on_click =
                function(frame) self:OnClickTalent(frame) end
        end
    end
    local root
    for id, button in pairs(buttons) do
        if not parent[id] then
            assert(not root, "Multiple root tree nodes found")
            root = button
        end
    end
    assert(root, "Root tree node not found")
    return root
end

function SpecPageHandler:ClickViewToggleButton(button)
    self.refresh_is_view_toggle = true
    local script = button:GetScript("OnClick")
    assert(script)
    script(button, "LeftButton", true)
end

function SpecPageHandler:RefreshTargets()
    -- We can get multiple refresh calls in a single frame, such as when
    -- switching from a locked to an unlocked tab, and refreshing on every
    -- call can lead to seeing inconsistent UI states in SetTargets(), so
    -- we delay the actual refresh until the next frame.
    if not self.refresh_pending then
        self.refresh_pending = true
        RunNextFrame(function()
            self.refresh_pending = false
            local is_tab_cycle = self.refresh_is_tab_cycle
            self.refresh_is_tab_cycle = false
            local is_view_toggle = self.refresh_is_view_toggle
            self.refresh_is_view_toggle = false
            local target = self:GetTarget()
            local new_target =
                self:SetTargets(target, is_tab_cycle, is_view_toggle)
            self:SetTarget(new_target)
        end)
    end
end

function SpecPageHandler:RefreshTargetsForUndoOff()
    local SpecPage = ProfessionsFrame.SpecPage
    if self:GetTarget() == SpecPage.UndoButton then
        self:SetTarget(SpecPage.ApplyButton)
    end
    self:RefreshTargets()
end

function SpecPageHandler:OnClickTalent(button)
    if button:IsEnabled() then
        button:OnClick("LeftButton", true)
        ProfessionsFrameHandler.instance_DetailedView:Enable()
    end
end


-------- Skill point allocation frame

function DetailedViewHandler:__constructor()
    local DetailedView = ProfessionsFrame.SpecPage.DetailedView
    self:__super(DetailedView)
    -- We need to hook both show and hide events to ensure we end up in
    -- the proper state regardless of the show/hide order.
    self:HookShow(DetailedView.UnlockPathButton,
                  self.RefreshTargets, self.RefreshTargets)
    self:HookShow(DetailedView.SpendPointsButton,
                  self.RefreshTargets, self.RefreshTargets)
    self.cancel_func = function() self:Disable() end
    self.on_prev_page = function() self:CycleTabs(-1) end
    self.on_next_page = function() self:CycleTabs(1) end
    self.targets = {}
end

function DetailedViewHandler:CycleTabs(dir)
    self:Disable()
    ProfessionsFrameHandler.instance_SpecPage:CycleTabs(dir)
end

function DetailedViewHandler:SetTargets()
    local DetailedView = ProfessionsFrame.SpecPage.DetailedView
    self:ClearTarget()
    self.targets = {}
    local target
    if DetailedView.UnlockPathButton:IsShown() then
        target = DetailedView.UnlockPathButton
    elseif DetailedView.SpendPointsButton:IsShown() then
        target = DetailedView.SpendPointsButton
    end
    if target then
        self.targets[target] = {can_activate = true, lock_highlight = true,
                                is_default = true}
    end
    return target
end

function DetailedViewHandler:RefreshTargets()
    local new_target = self:SetTargets()
    self:SetTarget(new_target)
end


-------- Order list frame

function OrderListHandler:__constructor()
    self:__super(ProfessionsFrame.OrdersPage.BrowseFrame)
    self.cancel_func = ProfessionsFrameHandler.CancelMenu
    self.tab_system = ProfessionsFrame.TabSystem
    self.on_prev_page = function() self:CycleTabs(-1) end
    self.on_next_page = function() self:CycleTabs(1) end
    self:HookShow(ProfessionsFrame.OrdersPage.BrowseFrame.OrderList.ScrollBox,
                  self.OnOrderListUpdate, self.OnOrderListUpdate)
end

function OrderListHandler:CycleTabs(dir)
    local bf = ProfessionsFrame.OrdersPage.BrowseFrame
    local tabs = {bf.PublicOrdersButton,
                  bf.NpcOrdersButton,
                  bf.PersonalOrdersButton}
    local first, prev, found_cur, target
    for _, tab in ipairs(tabs) do
        if tab.isSelected then
            if dir < 0 and prev then
                target = prev
                break
            end
            found_cur = true
        else
            if dir > 0 and found_cur then
                target = tab
                break
            end
        end
        first = first or tab
        prev = tab
    end
    if not target then
        target = dir > 0 and first or prev
    end
    self:SetTarget(target)
    target:GetScript("OnClick")(target, "LeftButton", true)
end

function OrderListHandler:OnOrderListUpdate()
    RunNextFrame(function()  -- Frame is shown before it's ready...
        local prev_target = self:GetTarget()
        self:SetTarget(self:SetTargets(prev_target))
    end)
end

function OrderListHandler:OnClickOrderTab(button)
    self.saved_index = 1
    button:GetScript("OnClick")(button, "LeftButton", true)
end

function OrderListHandler:OnClickOrder(button)
    assert(self.targets[button].is_scroll_box)
    assert(type(button.index) == "number")
    self.saved_index = button.index
    local frame = self:GetTargetFrame(button)
    frame:GetScript("OnClick")(frame, "LeftButton", true)
end

function OrderListHandler:SetTargets(initial_target)
    local bf = ProfessionsFrame.OrdersPage.BrowseFrame

    if type(initial_target) == "table" then
        if not self.targets[initial_target] then
            initial_target = nil
        elseif self.targets[initial_target].is_scroll_box then
            assert(type(initial_target.index) == "number")
            initial_target = initial_target.index
        else
            assert(initial_target == bf.PublicOrdersButton
                   or initial_target == bf.NpcOrdersButton
                   or initial_target == bf.PersonalOrdersButton)
        end
    end

    -- Click helpers to save the position in the order list, since the
    -- list disappears every time we move away from it.
    function ClickTab(button) self:OnClickOrderTab(button) end
    function ClickOrder(button) self:OnClickOrder(button) end

    self:ClearTarget()
    -- We deliberately ignore the recipe list since the public order system
    -- is so grossly misdesigned as to be useless.  We still include the
    -- public order tab to avoid user confusion, so orders for recipes
    -- marked as favorites (via mouse control, naturally) will still show up.
    self.targets = {
        [bf.PublicOrdersButton] = {
            on_click = ClickTab, lock_highlight = true,
            left = false, right = bf.NpcOrdersButton},
        [bf.NpcOrdersButton] = {
            on_click = ClickTab, lock_highlight = true,
            left = bf.PublicOrdersButton, right = bf.PersonalOrdersButton},
        [bf.PersonalOrdersButton] = {
            on_click = ClickTab, lock_highlight = true,
            left = bf.NpcOrdersButton, right = false},
    }
    local first, last
    local OrderScroll = bf.OrderList.ScrollBox
    if OrderScroll:IsVisible() and OrderScroll:GetDataProvider() then
        local index = 0
        OrderScroll:ForEachElementData(function(element)
            index = index + 1
            local button = OrderScroll:FindFrame(OrderScroll:FindElementData(index))
            if button then  -- FIXME: scroll handling not yet implemented
                local pseudo_frame =
                    MenuFrame.PseudoFrameForScrollElement(OrderScroll, index)
                self.targets[pseudo_frame] = {
                    is_scroll_box = true, on_click = ClickOrder,
                    up = false, down = false, left = false, right = false}
                -- FIXME: can we safely assume elements are in display order?
                if last then
                    self.targets[pseudo_frame].up = last
                    self.targets[last].down = pseudo_frame
                end
                first = first or pseudo_frame
                last = pseudo_frame
                if self.saved_index == index then
                    initial_target = pseudo_frame
                    self.saved_index = nil
                elseif initial_target == index then
                    initial_target = pseudo_frame
                end
            end
        end)
    end
    if not self.saved_index and type(initial_target) == "number" then
        -- The cursor was previously on an order which disappeared from
        -- the list.  This typically happens when returning from viewing
        -- an order's details, because the frame immediately refreshes the
        -- order list and displays 0 orders until the refresh completes.
        -- Save the desired target for the next refresh, so we can properly
        -- restore the cursor position.
        self.saved_index = initial_target
    elseif self.saved_index and last then
        -- We had a desired target position and a non-empty list, but we
        -- didn't find the desired target.  This probably means that the
        -- player just completed the last order in the list, so position
        -- the cursor at the new last order.
        initial_target = last
        self.saved_index = nil
    end
    local cur_tab
    for _, button in ipairs({bf.PublicOrdersButton, bf.NpcOrdersButton,
                             bf.PersonalOrdersButton}) do
        self.targets[button].down = first
        self.targets[button].up = last
        if button.isSelected then cur_tab = button end
    end
    cur_tab = cur_tab or bf.PublicOrdersButton  -- Sanity check.
    if first then
        self.targets[first].up = cur_tab
        self.targets[last].down = cur_tab
    end

    if initial_target and type(initial_target) == "table" then
        return initial_target
    end
    return cur_tab
end

function OrderListHandler:OnMove(old_target, new_target)
    self.saved_index = nil
end


-------- Order details frame

function OrderViewHandler:__constructor()
    self:__super(ProfessionsFrame.OrdersPage.OrderView)
    self.cancel_func = nil
    self.tab_system = ProfessionsFrame.TabSystem
    -- Use button show events to handle order progression.
    local ov = ProfessionsFrame.OrdersPage.OrderView
    self:HookShow(ov.OrderInfo.StartOrderButton, self.RefreshTargets, false)
    self:HookShow(ov.OrderInfo.ReleaseOrderButton, self.RefreshTargets, false)
    self:HookShow(ov.CompleteOrderButton, self.RefreshTargets, false)
end

function OrderViewHandler:SetTargets()
    local ov = ProfessionsFrame.OrdersPage.OrderView
    local oi = ov.OrderInfo

    local reward_u, reward_d, reward_l, reward_r = false, false, false, false

    self:ClearTarget()

    if oi.StartOrderButton:IsShown() then
        -- Order not yet started
        self.cancel_func = nil
        self.cancel_button = oi.BackButton
        self.targets = {
            [oi.BackButton] = {
                can_activate = true, lock_highlight = true,
                up = oi.StartOrderButton, down = oi.StartOrderButton,
                left = false, right = false},
            [oi.StartOrderButton] = {
                can_activate = true, lock_highlight = true, is_default = true,
                up = oi.BackButton, down = oi.BackButton,
                left = false, right = false},
        }
        local rsb = ov.OrderDetails.SchematicForm.RecipeSourceButton
        if rsb:IsShown() then
            self.targets[rsb] = {
                send_enter_leave = true, up = false, down = false,
                left = oi.BackButton, right = oi.BackButton}
            self.targets[oi.BackButton].left = rsb
            self.targets[oi.BackButton].right = rsb
            self.targets[oi.StartOrderButton].left = rsb
            self.targets[oi.StartOrderButton].right = rsb
        end
        reward_u = oi.BackButton
        reward_d = oi.StartOrderButton

    elseif oi.ReleaseOrderButton:IsShown() then
        -- Order in progress
        self.cancel_func = ProfessionsFrameHandler.CancelMenu
        self.cancel_button = nil
        local bqc = ov.OrderDetails.SchematicForm.AllocateBestQualityCheckbox
        local ctb = (ProfessionsFrame
                     .OrdersPage
                     .OrderView
                     .OrderDetails
                     .SchematicForm
                     .Details
                     .CraftingChoicesContainer
                     .ConcentrateContainer
                     .ConcentrateToggleButton)  -- sheesh, enough layers?
        self.targets = {
            [oi.ReleaseOrderButton] = {
                can_activate = true, lock_highlight = true,
                up = false, down = false,
                left = ov.CreateButton, right = bqc},
            [bqc] = {
                can_activate = true, lock_highlight = true,
                up = false, down = false,
                left = oi.ReleaseOrderButton, right = ov.CreateButton},
            [ov.CreateButton] = {
                can_activate = true, lock_highlight = true, is_default = true,
                send_enter_leave = true, up = ctb, down = ctb,
                left = bqc, right = oi.ReleaseOrderButton},
            [ctb] = {
                can_activate = true, lock_highlight = true,
                send_enter_leave = true,
                up = ov.CreateButton, down = ov.CreateButton,
                left = false, right = false}
        }
        -- FIXME: reagent selection not yet implemented
        reward_u = oi.ReleaseOrderButton
        reward_d = oi.ReleaseOrderButton

    elseif ov.CompleteOrderButton:IsShown() then
        -- Order crafted, waiting for completion click
        self.cancel_func = ProfessionsFrameHandler.CancelMenu
        self.cancel_button = nil
        self.targets = {
            [ov.CompleteOrderButton] = {
                can_activate = true, lock_highlight = true, is_default = true,
                up = false, down = false, left = false, right = false},
        }
        reward_l = ov.CompleteOrderButton
        reward_r = ov.CompleteOrderButton

    else
        error("Unknown OrderView frame state")
    end

    -- FIXME: these are missing immediately after a /reload while visible
    local reward1 = ProfessionsCrafterOrderRewardItem1
    if oi.NPCRewardsFrame:IsShown() and reward1:IsShown() then
        self.targets[reward1] = {send_enter_leave = true,
                                 up = reward_u, down = reward_d,
                                 left = reward_l, right = reward_r}
        local reward2 = ProfessionsCrafterOrderRewardItem2
        if reward2:IsShown() then
            self.targets[reward2] = {send_enter_leave = true,
                                     up = reward_u, down = reward_d,
                                     left = reward1, right = reward_r}
            self.targets[reward1].right = reward2
            if not reward_l then
                self.targets[reward1].left = reward2
            end
            if not reward_r then
                self.targets[reward2].right = reward1
            end
        else
            reward2 = reward1  -- for simplicity below
        end
        if reward_u then self.targets[reward_u].down = reward1 end
        if reward_d then self.targets[reward_d].up = reward1 end
        if reward_l then self.targets[reward_l].right = reward1 end
        if reward_r then self.targets[reward_r].left = reward2 end
    end
end

function OrderViewHandler:RefreshTargets()
    self:SetTargets()
    self:SetTarget(self:GetDefaultTarget())
end
