local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

-- FIXME: currently just a minimal implementation for use by ItemUpgradeFrame

---------------------------------------------------------------------------

local cache_TokenFilterDropdown = {}
local cache_CurrencySourceDropdown = {}

local CharacterFrameHandler = class(MenuCursor.MenuFrame)
MenuCursor.CharacterFrameHandler = CharacterFrameHandler  -- For exports.
MenuCursor.Cursor.RegisterFrameHandler(CharacterFrameHandler)
local PaperDollFrameHandler = class(MenuCursor.StandardMenuFrame)
local ReputationFrameHandler = class(MenuCursor.StandardMenuFrame)
local ReputationDetailFrameHandler = class(MenuCursor.StandardMenuFrame)
local TokenFrameHandler = class(MenuCursor.StandardMenuFrame)
local TokenFramePopupHandler = class(MenuCursor.StandardMenuFrame)
local CurrencyTransferLogHandler = class(MenuCursor.StandardMenuFrame)
local CurrencyTransferMenuHandler = class(MenuCursor.StandardMenuFrame)


function CharacterFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
    class.instance_PaperDollFrame = PaperDollFrameHandler()
    class.instance_ReputationFrame = ReputationFrameHandler()
    class.instance_ReputationDetailFrame = ReputationDetailFrameHandler()
    class.instance_TokenFrame = TokenFrameHandler()
    class.instance_TokenFramePopup = TokenFramePopupHandler()
    class.instance_CurrencyTransferLog = CurrencyTransferLogHandler()
    class.instance_CurrencyTransferMenu = CurrencyTransferMenuHandler()
end

function CharacterFrameHandler:__constructor()
    self:__super(CharacterFrame)
    -- ProfessionsFrame itself is just a holder for the tabs and the
    -- individual tab content pages, so we don't have any menu behavior
    -- of our own.  We still HookShow() because the current tab page
    -- remains shown even while this frame is closed.
    -- FIXME: find a good way to share this logic with similar frames
    --    (AuctionHouseFrame, ProfessionsFrame, more?) - probably needs
    --    a more descriptive DSL to deal with pattern differences
    self:HookShow(CharacterFrame)
    -- This is never called because this frame is never set active,
    -- but subframe handler classes reference it.
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function CharacterFrameHandler.CancelMenu()  -- Static method.
    HideUIPanel(CharacterFrame)
end

function CharacterFrameHandler:OnShow()
    if PaperDollFrame:IsShown() then
        CharacterFrameHandler.instance_PaperDollFrame:OnShow()
    elseif ReputationFrame:IsShown() then
        CharacterFrameHandler.instance_ReputationFrame:OnShow()
    elseif TokenFrame:IsShown() then
        CharacterFrameHandler.instance_TokenFrame:OnShow()
    end
end

function CharacterFrameHandler:OnHide()
    if PaperDollFrame:IsShown() then
        CharacterFrameHandler.instance_PaperDollFrame:OnHide()
    elseif ReputationFrame:IsShown() then
        CharacterFrameHandler.instance_ReputationFrame:OnHide()
    elseif TokenFrame:IsShown() then
        CharacterFrameHandler.instance_TokenFrame:OnHide()
    end
end

function CharacterFrameHandler:OnTabCycle(direction)
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = #self.frame.Tabs
    elseif new_index > #self.frame.Tabs then
        new_index = 1
    end
    self.frame.Tabs[new_index]:OnClick("LeftButton", true)
end


function PaperDollFrameHandler:__constructor()
    self:__super(PaperDollFrame)
    self.cancel_func = CharacterFrameHandler.CancelMenu
    self.tab_handler = CharacterFrameHandler.instance.tab_handler

    local left = {CharacterHeadSlot, CharacterNeckSlot,
                  CharacterShoulderSlot, CharacterBackSlot,
                  CharacterChestSlot, CharacterShirtSlot,
                  CharacterTabardSlot, CharacterWristSlot}
    local right = {CharacterHandsSlot, CharacterWaistSlot,
                   CharacterLegsSlot, CharacterFeetSlot,
                   CharacterFinger0Slot, CharacterFinger1Slot,
                   CharacterTrinket0Slot, CharacterTrinket1Slot}
    local bottom = {CharacterMainHandSlot, CharacterSecondaryHandSlot}
    local function OnClickSlot(slot)
        self:OnClickSlot(slot)
    end

    for i = 0, 7 do
        local l = left[i+1]
        local r = right[i+1]
        self.targets[l] = {
            on_click = OnClickSlot, lock_highlight = true,
            send_enter_leave = true, left = r, right = r,
            up = left[(i+7)%8+1], down = left[(i+1)%8+1]}
        self.targets[r] = {
            on_click = OnClickSlot, lock_highlight = true,
            send_enter_leave = true, left = l, right = l,
            up = right[(i+7)%8+1], down = right[(i+1)%8+1]}
    end
    self.targets[bottom[1]] = {
        on_click = OnClickSlot, lock_highlight = true, send_enter_leave = true,
        left = left[8], right = bottom[2], up = false, down = false}
    self.targets[bottom[2]] = {
        on_click = OnClickSlot, lock_highlight = true, send_enter_leave = true,
        left = bottom[1], right = right[8], up = false, down = false}
    self.targets[left[8]].right = bottom[1]
    self.targets[right[8]].left = bottom[2]
    self.targets[left[1]].is_default = true
end

function PaperDollFrameHandler:OnClickSlot(slot)
    if slot.itemContextMatchResult == ItemButtonUtil.ItemContextMatchResult.Match then
        PaperDollItemSlotButton_OnClick(slot, "RightButton")
        HideUIPanel(CharacterFrame)
    end
end


function ReputationFrameHandler:__constructor()
    self:__super(ReputationFrame)
    self.cancel_func = CharacterFrameHandler.CancelMenu
    self.tab_handler = CharacterFrameHandler.instance.tab_handler
    self.has_Button4 = true
    hooksecurefunc(self.frame, "Update", function() self:RefreshTargets() end)
end

function ReputationFrameHandler:OnHide()
    -- Blizzard code seems to preserve the open/closed state of the detail
    -- frame, but that's awkward, so always hide it when closing the
    -- reputation frame.
    self.frame.ReputationDetailFrame:Hide()
    MenuCursor.StandardMenuFrame.OnHide(self)
end

function ReputationFrameHandler:RefreshTargets()
    local target = self:GetTarget()
    if target and self.targets[target].is_scroll_box then
        target = target.index
    end
    self:ClearTarget()
    self:SetTarget(self:SetTargets(target))
end

function ReputationFrameHandler:SetTargets(last_target)
    self.targets = {}
    local function ClickCollapseButton(target)
        local button = self:GetTargetFrame(target).ToggleCollapseButton
        assert(button)
        button:GetScript("OnClick")(button, "LeftButton", true)
    end
    local top, bottom, initial = self:AddScrollBoxTargets(
        self.frame.ScrollBox, function(elementdata, index)
            local header_type = (elementdata.isHeaderWithRep and 2 or
                                 elementdata.isHeader and 1 or 0)
            return {header_type = header_type,  -- For Button4 reference.
                    can_activate = header_type==1,
                    on_click = header_type==2 and ClickCollapseButton or nil,
                    send_enter_leave = true,
                    left = false, right = false}, index == last_target
        end)
    return initial or top
end

function ReputationFrameHandler:OnAction(button)
    assert(button == "Button4")
    local target = self:GetTarget()
    if target and self.targets[target].header_type ~= 1 then
        local frame = self:GetTargetFrame(target)
        frame:GetScript("OnClick")(frame, "LeftButton", true)
    end
end


function ReputationDetailFrameHandler:__constructor()
    self:__super(ReputationFrame.ReputationDetailFrame)
    self.cancel_func = MenuCursor.MenuFrame.CancelFrame
    self.has_Button4 = true

    local f = self.frame
    self.targets = {
        [f.AtWarCheckbox] = {
            can_activate = true, lock_highlight = true,
            left = f.MakeInactiveCheckbox, right = f.MakeInactiveCheckbox,
            up = f.WatchFactionCheckbox, down = f.WatchFactionCheckbox},
        [f.MakeInactiveCheckbox] = {
            can_activate = true, lock_highlight = true,
            left = f.AtWarCheckbox, right = f.AtWarCheckbox,
            up = f.WatchFactionCheckbox, down = f.WatchFactionCheckbox},
        [f.WatchFactionCheckbox] = {
            can_activate = true, lock_highlight = true,
            left = false, right = false,
            up = f.AtWarCheckbox, down = f.AtWarCheckbox},
    }
end

function ReputationDetailFrameHandler:SetTargets()
    local f = self.frame
    if f.ViewRenownButton:IsShown() then
        self.targets[f.ViewRenownButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            left = false, right = false,
            up = f.WatchFactionCheckbox, down = f.AtWarCheckbox}
        self.targets[f.AtWarCheckbox].is_default = false
        self.targets[f.AtWarCheckbox].up = f.ViewRenownButton
        self.targets[f.MakeInactiveCheckbox].up = f.ViewRenownButton
        self.targets[f.WatchFactionCheckbox].down = f.ViewRenownButton
    else
        self.targets[f.ViewRenownButton] = nil
        self.targets[f.AtWarCheckbox].is_default = true
        self.targets[f.AtWarCheckbox].up = f.WatchFactionCheckbox
        self.targets[f.MakeInactiveCheckbox].up = f.WatchFactionCheckbox
        self.targets[f.WatchFactionCheckbox].down = f.AtWarCheckbox
    end
    -- One would think this shouldn't be necessary, but...
    self.targets[f.AtWarCheckbox].can_activate = f.AtWarCheckbox:IsEnabled()
end

function ReputationDetailFrameHandler:OnAction(button)
    assert(button == "Button4")
    self:cancel_func()
end


function TokenFrameHandler:__constructor()
    self:__super(TokenFrame)
    self.cancel_func = CharacterFrameHandler.CancelMenu
    self.tab_handler = CharacterFrameHandler.instance.tab_handler
    self.has_Button4 = true
    hooksecurefunc(self.frame, "Update", function() self:RefreshTargets() end)
end

function TokenFrameHandler:RefreshTargets()
    local target = self:GetTarget()
    if target and self.targets[target].is_scroll_box then
        target = target.index
    end
    self:ClearTarget()
    self:SetTarget(self:SetTargets(target))
end

function TokenFrameHandler:SetTargets(last_target)
    local f = self.frame
    self.targets = {
        [f.filterDropdown] = {
            on_click = function() self:OnClickDropdown() end,
            send_enter_leave = true,
            up = false, down = false},
        [f.CurrencyTransferLogToggleButton] = {
            can_activate = true, send_enter_leave = true,
            up = false, down = false},
    }
    local function ClickCollapseButton(target)
        local button = self:GetTargetFrame(target).ToggleCollapseButton
        assert(button)
        button:GetScript("OnClick")(button, "LeftButton", true)
    end
    local top, bottom, initial = self:AddScrollBoxTargets(
        f.ScrollBox, function(elementdata, index)
            local header_type = elementdata.isHeader and (elementdata.currencyListDepth > 0 and 2 or 1) or 0
            return {header_type = header_type,  -- For Button4 reference.
                    can_activate = header_type==1,
                    on_click = header_type==2 and ClickCollapseButton or nil,
                    send_enter_leave = true,
                    left = false, right = false}, index == last_target
        end)
    if top then
        self.targets[top].up = f.filterDropdown
        self.targets[bottom].down = f.filterDropdown
        self.targets[f.filterDropdown].up = bottom
        self.targets[f.filterDropdown].down = top
        self.targets[f.CurrencyTransferLogToggleButton].up = bottom
        self.targets[f.CurrencyTransferLogToggleButton].down = top
    end
    return initial or top
end

function TokenFrameHandler:OnClickDropdown()
    local f = self.frame
    local dropdown = f.filterDropdown
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local menu, initial_target = self.SetupDropdownMenu(
            dropdown, cache_TokenFilterDropdown, nil,
            function() self:RefreshTargets() end)
        menu:Enable(initial_target)
    end
end

function TokenFrameHandler:OnAction(button)
    assert(button == "Button4")
    local target = self:GetTarget()
    if target and self.targets[target].header_type ~= 1 then
        local frame = self:GetTargetFrame(target)
        frame:GetScript("OnClick")(frame, "LeftButton", true)
    end
end


function TokenFramePopupHandler:__constructor()
    self:__super(TokenFramePopup)
    self.cancel_func = MenuCursor.MenuFrame.CancelFrame
    self.has_Button4 = true
    hooksecurefunc(self.frame.CurrencyTransferToggleButton, "SetEnabled",
                   function() self:UpdateTransferEnabled() end)
end

function TokenFramePopupHandler:SetTargets()
    local f = self.frame
    local initial
    self.targets = {}
    if f.InactiveCheckbox:IsShown() then
        self.targets[f.InactiveCheckbox] = {
            can_activate = true, lock_highlight = true,
            left = false, right = false,
            up = f.BackpackCheckbox, down = f.BackpackCheckbox}
        self.targets[f.BackpackCheckbox] = {
            can_activate = true, lock_highlight = true,
            left = false, right = false,
            up = f.InactiveCheckbox, down = f.InactiveCheckbox}
        initial = f.InactiveCheckbox
    end
    if f.CurrencyTransferToggleButton:IsShown() then
        local up, down
        if f.InactiveCheckbox:IsShown() then
            up = f.BackpackCheckbox
            down = f.InactiveCheckbox
            self.targets[up].down = f.CurrencyTransferToggleButton
            self.targets[down].up = f.CurrencyTransferToggleButton
        end
        self.targets[f.CurrencyTransferToggleButton] = {
            can_activate = f.CurrencyTransferToggleButton:IsEnabled(),
            lock_highlight = true,
            left = false, right = false, up = up, down = down}
        initial = f.CurrencyTransferToggleButton
    end
    return initial
end

function TokenFramePopupHandler:UpdateTransferEnabled()
    local button = self.frame.CurrencyTransferToggleButton
    local params = self.targets[button]
    if params then
        params.can_activate = button:IsEnabled()
    end
end

function TokenFramePopupHandler:OnAction(button)
    assert(button == "Button4")
    self:cancel_func()
end


function CurrencyTransferLogHandler:__constructor()
    self:__super(CurrencyTransferLog)
    self.cancel_func = nil
    self.cancel_button = self.frame.CloseButton
end

function CurrencyTransferLogHandler:SetTargets()
    local f = self.frame
    self.targets = {}
    local top, bottom = self:AddScrollBoxTargets(
        f.ScrollBox, function(elementdata, index)
            return {send_enter_leave = true, left = false, right = false}
        end)
    -- The log entry frames explicitly check IsMouseOver() to set the
    -- highlight state, so we have to override that.
    local function IsMouseOverOverride(frame)
        local target = self:GetTarget()
        return target and self:GetTargetFrame(target) == frame
    end
    for entry, _ in pairs(self.targets) do
        self:GetTargetFrame(entry).IsMouseOver = IsMouseOverOverride
    end
    return top
end


function CurrencyTransferMenuHandler:__constructor()
    self:__super(CurrencyTransferMenu)
    local f = self.frame
    self.cancel_func = nil
    self.cancel_button = f.CloseButton
    self.targets = {
        [f.SourceSelector.Dropdown] = {
            on_click = function() self:OnClickDropdown() end,
            lock_highlight = true, is_default = true,
            up = f.ConfirmButton, down = f.AmountSelector.InputBox},
        [f.AmountSelector.MaxQuantityButton] = {
            can_activate = true, lock_highlight = true,
            up = f.SourceSelector.Dropdown, down = f.ConfirmButton,
            left = false},
        [f.AmountSelector.InputBox] = {
            on_click = function() self:EditQuantity() end,
            up = f.SourceSelector.Dropdown, down = f.ConfirmButton},
        [f.ConfirmButton] = {
            -- NOTE: This currently fails due to taint (despite our best
            -- efforts), so currency transfer needs to be done with the
            -- addon disabled.
            can_activate = false, lock_highlight = true,
            up = f.AmountSelector.MaxQuantityButton,
            down = f.SourceSelector.DropDown, left = false},
        [f.CancelButton] = {
            can_activate = true, lock_highlight = true,
            up = f.AmountSelector.MaxQuantityButton,
            down = f.SourceSelector.DropDown, right = false},
    }
    self.quantity_input = MenuCursor.NumberInput(
        f.AmountSelector.InputBox, function() self:OnQuantityChanged() end)
    self.quantity_input:SetTextScale(0.64)
end

function CurrencyTransferMenuHandler:OnClickDropdown()
    local dropdown = self.frame.SourceSelector.Dropdown
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local menu, initial_target = self.SetupDropdownMenu(
            dropdown, cache_CurrencySourceDropdown)
        menu:Enable(initial_target)
    end
end

function CurrencyTransferMenuHandler:EditQuantity()
    local InputBox = self.frame.AmountSelector.InputBox
    local limit = InputBox:GetClampedInputAmount(999999999)
    if limit and limit > 0 then
        self.quantity_input:Edit(0, limit)
    end
end

function CurrencyTransferMenuHandler:OnQuantityChanged()
    local InputBox = self.frame.AmountSelector.InputBox
    InputBox:ValidateAndSetValue()
end

---------------------------------------------------------------------------

-- Exported function, called by ItemUpgradeFrame.  (FIXME: this is a bit
-- sloppy, revisit when PaperDollFrame is more fully implemented)
function CharacterFrameHandler.OpenForItemUpgrade()
    ToggleCharacter("PaperDollFrame", true)
    CharacterFrameHandler.instance_PaperDollFrame:Enable()  -- In case it was already open.
end
