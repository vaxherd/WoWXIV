local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local floor = math.floor

---------------------------------------------------------------------------

-- Convenience function to return the MerchantItemButton with the given
-- index (1-12).
local function ItemButton(index)
    return _G["MerchantItem"..index.."ItemButton"]
end

-- Convenience function to return the MerchantItemButton frame for the
-- given button ID.  Non-trivial because IDs are assigned uniquely across
-- all shop items instead of being directly associated with the buttons.
local function ItemButtonForID(id)
    return ItemButton((id-1)%10 + 1)
end

---------------------------------------------------------------------------

local MerchantFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(MerchantFrameHandler)

function MerchantFrameHandler:__constructor()
    self:__super(MerchantFrame)
    self.has_Button4 = true  -- Used to purchase multiple of an item.
    self.on_prev_page = "MerchantPrevPageButton"
    self.on_next_page = "MerchantNextPageButton"
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
    -- We use the "sell all junk" button (which is always[*] displayed on
    -- the "buy" tab and never displayed on the "sell" tab) as a proxy for
    -- tab change detection.
    -- [*] Except at delve repair stations, but those have no sell tab
    --     anyway so it's not an issue.
    self:HookShow(MerchantSellAllJunkButton,
                  self.OnTabChange, self.OnTabChange)
    for i = 1, 12 do
        local frame = ItemButton(i)
        assert(frame)
        self:HookShow(frame, self.OnShowItemButton,
                             self.OnHideItemButton)
    end
end

function MerchantFrameHandler:SetTargets()
    assert(MerchantFrame.selectedTab == 1)
    self:UpdateTargets()
    self:UpdateMovement()
    if self.targets[MerchantItem1ItemButton] then
        return MerchantItem1ItemButton
    elseif self.targets[MerchantSellAllJunkButton] then
        return MerchantSellAllJunkButton
    else
        assert(self.targets[MerchantRepairAllButton])
        return MerchantRepairAllButton
    end
end

function MerchantFrameHandler:OnAction(button)
    assert(button == "Button4")

    local target = self:GetTarget()
    local id
    for i = 1, 12 do
        local frame = ItemButton(i)
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
        counts the number of purchasable stacks instead.  It's not clear
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
    -- Immediately activate the quantity input (since that's why we opened
    -- the box in the first place).
    MenuCursor.StackSplitFrameEditQuantity()
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
    local have_sell_junk = (self.targets[MerchantSellAllJunkButton] ~= nil)
    if have_sell_junk ~= MerchantSellAllJunkButton:IsShown() then
        self:SetTarget(nil)
        self:UpdateTargets()
        self:UpdateMovement()
        -- OnHideItemButton() ensures we always have a target at position 1.
        assert(self.targets[MerchantItem1ItemButton])
        self:SetTarget(MerchantItem1ItemButton)
    end
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
    local is_buy = (MerchantSellAllJunkButton:IsShown()
                    or MerchantRepairAllButton:IsShown())
    if is_buy ~= (MerchantFrame.selectedTab==1) then
        skip_update = true
    end
    if not skip_update then
        self:UpdateMovement()
    end
end

function MerchantFrameHandler:OnHideItemButton(frame)
    if self:GetTarget() == frame then
        local prev_id = frame:GetID() - 1
        local prev_frame = ItemButtonForID(prev_id)
        if prev_frame and prev_frame:IsShown() then
            self:SetTarget(prev_frame)
        else
            self:MoveCursor("down")
        end
    end
    if frame == MerchantItem1ItemButton then
        -- Dummy target so we have somewhere to put the cursor even if
        -- the page is empty (as for the buyback page right after login).
        self.targets[frame] = {}
    else
        self.targets[frame] = nil
    end
    local is_buy = (MerchantSellAllJunkButton:IsShown()
                    or MerchantRepairAllButton:IsShown())
    if is_buy == (MerchantFrame.selectedTab==1) then
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
        local have_sell_all = MerchantSellAllJunkButton:IsShown()
        if have_sell_all then
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
        end
        if MerchantRepairItemButton:IsShown() then
            self.targets[MerchantRepairItemButton] = {
                lock_highlight = true, send_enter_leave = true,
                left = (have_sell_all and MerchantBuyBackItemItemButton
                                       or MerchantRepairAllButton),
                right = MerchantRepairAllButton}
            self.targets[MerchantRepairAllButton] = {
                can_activate = true, lock_highlight = true,
                send_enter_leave = true,
                left = MerchantRepairItemButton,
                right = (have_sell_all and MerchantSellAllJunkButton
                                        or MerchantRepairItemButton)}
            if have_sell_all then
                self.targets[MerchantSellAllJunkButton].left =
                    MerchantRepairAllButton
                self.targets[MerchantBuyBackItemItemButton].right =
                    MerchantRepairItemButton
            end
        end
    end
    for i = 1, 12 do
        local holder = _G["MerchantItem"..i]
        local button = _G["MerchantItem"..i.."ItemButton"]  -- ==ItemButton(i)
        assert(button)
        if holder:IsShown() and button:IsShown() then
            self:OnShowItemButton(button, true)
        elseif i == 1 then  -- Ensure we have at least one target.
            self:OnHideItemButton(button, true)
        end
    end
end

function MerchantFrameHandler:UpdateMovement()
    if not self:HasFocus() then
        return  -- Deal with calls during frame setup on UI reload.
    end
    -- Ensure correct up/down behavior, as for mail inbox.  Also allow
    -- left/right to move through all items in sequence.  We assume the
    -- buttons are numbered in display order and that there are no holes
    -- in the sequence, which should be guaranteed by core game code.
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
            self.targets[button].up = nil
            self.targets[button].down = nil
            if i%2 == 0 then
                last_right = button
            else
                last_left = button
            end
            prev = button
        end
    end
    last_right = last_right or last_left
    if MerchantPrevPageButton:IsShown() then
        assert(last_left)  -- Should never have page buttons without items.
        self.targets[last_left].down = MerchantPrevPageButton
        if last_right and last_right ~= last_left then
            self.targets[last_right].down = MerchantNextPageButton
        end
        self.targets[MerchantPrevPageButton].up = last_left
        self.targets[MerchantNextPageButton].up = last_right
        last_left = MerchantPrevPageButton
        last_right = MerchantNextPageButton
        first_left = first_left or last_left
        first_right = first_right or last_right
    end
    local have_repair = MerchantRepairItemButton:IsShown()
    local have_sell_all = MerchantSellAllJunkButton:IsShown()
    if have_repair or have_sell_all then
        local left_button, right_button
        if have_repair then
            left_button = MerchantRepairItemButton
        else
            left_button = MerchantSellAllJunkButton
        end
        if have_sell_all then
            right_button = MerchantBuyBackItemItemButton
        else
            right_button = MerchantRepairAllButton
        end
        if last_left then
            self.targets[last_left].down = left_button
        end
        if last_right and last_right ~= last_left then
            self.targets[last_right].down = right_button
        end
        if have_repair then
            self.targets[MerchantRepairItemButton].up = last_left
            self.targets[MerchantRepairAllButton].up = last_left
        end
        if have_sell_all then
            self.targets[MerchantSellAllJunkButton].up = last_left
            self.targets[MerchantBuyBackItemItemButton].up = last_right
        end
        last_left = left_button
        last_right = right_button
        first_left = first_left or last_left
        first_right = first_right or last_right
    end
    if first_left then
        self.targets[first_left].up = last_left
        self.targets[last_left].down = first_left
        if first_right ~= first_left then
            self.targets[first_right].up = last_right
        end
        self.targets[last_right].down = first_right
    end
end
