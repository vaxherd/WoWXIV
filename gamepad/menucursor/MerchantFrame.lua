local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local MerchantFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(MerchantFrameHandler)

function MerchantFrameHandler:__constructor()
    self:__super(MerchantFrame)
    self.on_prev_page = "MerchantPrevPageButton"
    self.on_next_page = "MerchantNextPageButton"
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
    self.targets = {
        [MerchantFrameTab1] = {can_activate = true},
        [MerchantFrameTab2] = {can_activate = true},
    }
    if MerchantFrame.selectedTab == 1 then
        self.targets[MerchantSellAllJunkButton] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true, down = MerchantFrameTab2}
        self.targets[MerchantBuyBackItemItemButton] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true,
            up = MerchantNextPageButton, down = MerchantFrameTab2}
        if MerchantPrevPageButton:IsShown() then
            self.targets[MerchantPrevPageButton] = {
                can_activate = true, lock_highlight = true,
                down = MerchantSellAllJunkButton}
            self.targets[MerchantNextPageButton] = {
                can_activate = true, lock_highlight = true,
                down = MerchantBuyBackItemItemButton}
            self.targets[MerchantSellAllJunkButton].up = MerchantPrevPageButton
            self.targets[MerchantBuyBackItemItemButton].up = MerchantNextPageButton
        end
        if MerchantRepairItemButton:IsShown() then
            self.targets[MerchantRepairItemButton] = {
                lock_highlight = true, send_enter_leave = true,
                down = MerchantFrameTab1}
            self.targets[MerchantRepairAllButton] = {
                can_activate = true, lock_highlight = true,
                send_enter_leave = true, down = MerchantFrameTab2}
            if MerchantPrevPageButton:IsShown() then
                self.targets[MerchantRepairItemButton].up = MerchantPrevPageButton
                self.targets[MerchantRepairAllButton].up = MerchantPrevPageButton
            end
            self.targets[MerchantFrameTab1].up = MerchantRepairItemButton
            self.targets[MerchantFrameTab2].up = MerchantRepairAllButton
        else
            self.targets[MerchantFrameTab1].up = MerchantSellAllJunkButton
            self.targets[MerchantFrameTab2].up = MerchantSellAllJunkButton
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
    local first_left, first_right, last_left, last_right
    if last_item > 0 then
        first_left = ItemButton(1)
        first_right = ItemButton(last_item==1 and 1 or 2)
        local i = last_item
        if i%2 == 0 then i = i-1 end
        last_left = ItemButton(i)
        last_right = ItemButton(last_item)
        local prev = last_right
        for i = 1, last_item do
            local button = ItemButton(i)
            local next = ItemButton(i==last_item and 1 or i+1)
            self.targets[button].left = prev
            self.targets[button].right = next
            prev = button
        end
    else
        if MerchantPrevPageButton:IsShown() then
            first_left = MerchantPrevPageButton
            first_right = MerchantNextPageButton
        elseif MerchantSellAllJunkButton:IsShown() then
            if MerchantRepairItemButton:IsShown() then
                first_left = MerchantRepairItemButton
            else
                first_left = MerchantSellAllJunkButton
            end
            first_right = MerchantSellAllJunkButton
        else
            first_left = false
            first_right = false
        end
        last_left = MerchantFrameTab1
        last_right = MerchantFrameTab2
    end
    if first_left then
        self.targets[first_left].up = MerchantFrameTab1
        self.targets[MerchantFrameTab1].down = first_left
        if first_right ~= first_left then
            self.targets[first_right].up = MerchantFrameTab2
            self.targets[MerchantFrameTab2].down = first_right
        end
    end
    if MerchantPrevPageButton:IsShown() then
        self.targets[MerchantPrevPageButton].up = last_left
        self.targets[MerchantNextPageButton].up = last_right
        if last_left then
            self.targets[last_left].down = MerchantPrevPageButton
            if last_right ~= last_left then
                self.targets[last_right].down = MerchantNextPageButton
            end
        end
    elseif MerchantSellAllJunkButton:IsShown() then
        local left
        if MerchantRepairItemButton:IsShown() then
            self.targets[MerchantRepairItemButton].up = last_left
            self.targets[MerchantRepairAllButton].up = last_left
            left = MerchantRepairItemButton
        else
            left = MerchantSellAllJunkButton
        end
        self.targets[MerchantSellAllJunkButton].up = last_left
        self.targets[MerchantBuyBackItemItemButton].up = last_right
        if last_left then
            self.targets[last_left].down = left
            if last_right ~= last_left then
                self.targets[last_right].down = MerchantBuyBackItemItemButton
            end
        end
    else
        self.targets[MerchantFrameTab1].up = last_left
        self.targets[MerchantFrameTab2].up = last_right
        if last_left then
            self.targets[last_left].down = MerchantFrameTab1
            if last_right ~= last_left then
                self.targets[last_right].down = MerchantFrameTab2
            end
        end
    end
end
