local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local floor = math.floor

---------------------------------------------------------------------------

local MerchantFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(MerchantFrameHandler)

function MerchantFrameHandler:__constructor()
    self:__super(MerchantFrame)
    self.has_Button4 = true  -- Used to purchase multiple of an item.
    self.on_prev_page = "MerchantPrevPageButton"
    self.on_next_page = "MerchantNextPageButton"
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
    -- We use the "sell all junk" button (which is always displayed on the
    -- "buy" tab and never displayed on the "sell" tab) as a proxy for tab
    -- change detection.
    self:HookShow(MerchantSellAllJunkButton,
                  self.OnTabChange, self.OnTabChange)
    for i = 1, 12 do
        local frame_name = "MerchantItem" .. i .. "ItemButton"
        local frame = _G[frame_name]
        assert(frame)
        self:HookShow(frame, self.OnShowItemButton,
                             self.OnHideItemButton)
    end
end

function MerchantFrameHandler:SetTargets()
    assert(MerchantFrame.selectedTab == 1)
    self:UpdateTargets()
    self:UpdateMovement()
    return (self.targets[MerchantItem1ItemButton]
            and MerchantItem1ItemButton
            or MerchantSellAllJunkButton)
end

function MerchantFrameHandler:OnAction(button)
    assert(button == "Button4")

    local target = self:GetTarget()
    local id
    for i = 1, 12 do
        local frame_name = "MerchantItem" .. i .. "ItemButton"
        local frame = _G[frame_name]
        if target == frame then
            id = frame:GetID()
            break
        end
    end
    if not id then return end

    --[[
        This is essentially a reimplementation of
        MerchantItemButton_OnModifiedClick().  We unfortunately can't
        just call into that code because it explicitly checks
        IsModifiedClick("SPLITSTACK"), which we can't affect.

        Note a possible bug in Blizzard code, which calculates the limit
        for alternate currencies as the number of individual items
        purchasable; this doesn't match the test for regular money, which
        counts the number of purchasable stacks instead).  It's not clear
        whether there are any stacked items sold by merchants for non-money
        currency, so it may only be a theoretical problem, but we avoid it
        anyway.
    ]]--
    local info = C_MerchantFrame.GetItemInfo(id)
    local limit = GetMerchantItemMaxStack(id)  -- Undocumented function.
    if not limit or limit <= 1 then return end  -- Can't buy multiple.
    if info.price and info.price > 0 then
        local can_afford = floor(GetMoney() / info.price)
        if can_afford < limit then limit = can_afford end
    end
    if info.hasExtendedCost then
        for i = 1, GetMerchantItemCostInfo(id) do  -- Undocumented function.
            local _, cost, link, currency_name = GetMerchantItemCostItem(id, i)  -- Undocumented function.
            if link and not currency_name then
                local owned = C_Item.GetItemCount(link, false, false, true)
                local can_afford = floor(owned / cost)
                if can_afford < limit then limit = can_afford end
            end
        end
    end
    StackSplitFrame:OpenStackSplitFrame(
        limit, target, "BOTTOMLEFT", "TOPLEFT", info.stackCount)
end

function MerchantFrameHandler:OnTabCycle(direction)
    -- We have only two tabs, so we can just unconditionally click the
    -- currently unselected one.
    if MerchantFrame.selectedTab == 1 then
        MerchantFrameTab2:Click()
    else
        MerchantFrameTab1:Click()
    end
end

function MerchantFrameHandler:OnTabChange()
    self:UpdateTargets()
    self:UpdateMovement()
end

function MerchantFrameHandler:OnShowItemButton(frame, skip_update)
    self.targets[frame] = {
        lock_highlight = true, send_enter_leave = true,
        -- Pass a confirm action down as a right click because left-click
        -- activates the item drag functionality.  (On the buyback tab,
        -- right and left click do the same thing, so we don't need a
        -- special case for that.)
        on_click = function()
            MerchantItemButton_OnClick(frame, "RightButton")
        end,
    }
    -- Suppress updates when called from UpdateBuybackInfo().
    if MerchantSellAllJunkButton:IsShown() ~= (MerchantFrame.selectedTab==1) then
        skip_update = true
    end
    if not skip_update then
        self:UpdateMovement()
    end
end

function MerchantFrameHandler:OnHideItemButton(frame)
    if self:GetTarget() == frame then
        local prev_id = frame:GetID() - 1
        local prev_frame = _G["MerchantItem" .. prev_id .. "ItemButton"]
        if prev_frame and prev_frame:IsShown() then
            self:SetTarget(prev_frame)
        else
            self:MoveCursor("down")
        end
    end
    self.targets[frame] = nil
    if MerchantSellAllJunkButton:IsShown() == (MerchantFrame.selectedTab==1) then
        self:UpdateMovement()
    end
end

function MerchantFrameHandler:UpdateTargets()
    self.targets = {}
    if MerchantFrame.selectedTab == 1 then
        if MerchantPrevPageButton:IsShown() then
            self.targets[MerchantPrevPageButton] = {
                can_activate = true, lock_highlight = true,
                left = MerchantNextPageButton, right = MerchantNextPageButton}
            self.targets[MerchantNextPageButton] = {
                can_activate = true, lock_highlight = true,
                left = MerchantPrevPageButton, right = MerchantPrevPageButton}
        end
        self.targets[MerchantSellAllJunkButton] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true, down = false,
            left = MerchantBuyBackItemItemButton,
            right = MerchantBuyBackItemItemButton}
        self.targets[MerchantBuyBackItemItemButton] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true,
            left = MerchantSellAllJunkButton,
            right = MerchantSellAllJunkButton}
        if MerchantRepairItemButton:IsShown() then
            self.targets[MerchantRepairItemButton] = {
                lock_highlight = true, send_enter_leave = true,
                left = MerchantBuyBackItemItemButton,
                right = MerchantRepairAllButton}
            self.targets[MerchantRepairAllButton] = {
                can_activate = true, lock_highlight = true,
                send_enter_leave = true,
                left = MerchantRepairItemButton,
                right = MerchantSellAllJunkButton}
            self.targets[MerchantSellAllJunkButton].left =
                MerchantRepairAllButton
            self.targets[MerchantBuyBackItemItemButton].right =
                MerchantRepairItemButton
        end
    end
    local initial = nil
    for i = 1, 12 do
        local holder = _G["MerchantItem"..i]
        local button = _G["MerchantItem"..i.."ItemButton"]
        assert(button)
        if holder:IsShown() and button:IsShown() then
            self:OnShowItemButton(button, true)
            if not initial then
                initial = button
            end
        end
    end
end

function MerchantFrameHandler:UpdateMovement()
    -- FIXME: is this check still needed?
    if not self:HasFocus() then
        return  -- Deal with calls during frame setup on UI reload.
    end
    -- Ensure correct up/down behavior, as for mail inbox.  Also allow
    -- left/right to move through all items in sequence.  We assume the
    -- buttons are numbered in display order and that there are no holes
    -- in the sequence, which should be guaranteed by core game code.
    local function ItemButton(n)
        return _G["MerchantItem"..n.."ItemButton"]
    end
    local last_item = 1
    while last_item <= 12 do
        if not ItemButton(last_item):IsVisible() then
            break
        end
        last_item = last_item + 1
    end
    last_item = last_item - 1
    local first_left, first_right, last_left, last_right =
        false, false, false, false
    if last_item > 0 then
        first_left = ItemButton(1)
        first_right = ItemButton(last_item==1 and 1 or 2)
        local prev = ItemButton(last_item)
        for i = 1, last_item do
            local button = ItemButton(i)
            local next = ItemButton(i==last_item and 1 or i+1)
            self.targets[button].left = prev
            self.targets[button].right = next
            if i%2 == 0 then
                last_right = button
            else
                last_left = button
            end
            prev = button
        end
    end
    if MerchantPrevPageButton:IsShown() then
        assert(last_left)  -- Should never have page buttons without items.
        self.targets[last_left].down = MerchantPrevPageButton
        if last_right ~= last_left then
            self.targets[last_right].down = MerchantNextPageButton
        end
        self.targets[MerchantPrevPageButton].up = last_left
        self.targets[MerchantNextPageButton].up = last_right
        last_left = MerchantPrevPageButton
        last_right = MerchantNextPageButton
        first_left = first_left or last_left
        first_right = first_right or last_right
    end
    if MerchantSellAllJunkButton:IsShown() then
        local left_button
        if MerchantRepairItemButton:IsShown() then
            left_button = MerchantRepairItemButton
        else
            left_button = MerchantSellAllJunkButton
        end
        if last_left then
            self.targets[last_left].down = left_button
        end
        if last_right and last_right ~= last_left then
            self.targets[last_right].down = MerchantBuyBackItemItemButton
        end
        if MerchantRepairItemButton:IsShown() then
            self.targets[MerchantRepairItemButton].up = last_left
            self.targets[MerchantRepairAllButton].up = last_left
        end
        self.targets[MerchantSellAllJunkButton].up = last_left
        self.targets[MerchantBuyBackItemItemButton].up = last_right
        last_left = left_button
        last_right = MerchantBuyBackItemItemButton
        first_left = first_left or last_left
        first_right = first_right or last_right
    end
    if first_left then
        self.targets[first_left].up = last_left
        self.targets[last_left].down = first_left
        if first_right ~= first_left then
            self.targets[first_right].up = last_right
            self.targets[last_right].down = first_right
        end
    end
end
