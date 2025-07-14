local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local floor = math.floor
local strformat = string.format
local strsub = string.sub
local tinsert = tinsert

local BankItemSubmenu = class(WoWXIV.UI.ItemSubmenu)


---------------------------------------------------------------------------
-- Utility routines
---------------------------------------------------------------------------

-- Find an inventory bag and slot suitable for the given item.
local function FindInventorySlot(info)
    local function FindEmptySlot(bag_id)
        for i = 1, C_Container.GetContainerNumSlots(bag_id) do
            if not C_Container.GetContainerItemInfo(bag_id, i) then
                return i
            end
        end
        return nil
    end

    -- First look for an existing stack we can add to.
    local max_stack, _, _, _, class, subclass =
        select(8, C_Item.GetItemInfo("item:"..info.itemID))
    if info.stackCount < max_stack then
        local NUM_TOTAL_BAG_FRAMES = Constants.InventoryConstants.NumBagSlots + Constants.InventoryConstants.NumReagentBagSlots
        for bag_id = 0, NUM_TOTAL_BAG_FRAMES do
            for i = 1, C_Container.GetContainerNumSlots(bag_id) do
                local slot_info = C_Container.GetContainerItemInfo(bag_id, i)
                if slot_info and info.stackCount + slot_info.stackCount < max_count then
                    if not slot_info.isLocked then
                        return bag_id, i
                    end
                end
            end
        end
    end

    -- No viable stack found, so look for an appropriate empty slot.
    if not target_bag and class == Enum.ItemClass.Tradegoods then
        for i = 1, Constants.InventoryConstants.NumReagentBagSlots do
            local reagent_bag = Constants.InventoryConstants.NumBagSlots + i
            local slot = FindEmptySlot(reagent_bag)
            if slot then return reagent_bag, slot end
        end
    end
    -- It looks like item-to-bag filtering code is not exposed to Lua,
    -- so we have to reimplement it ourselves.
    local type_flag
    if info.quality == Enum.ItemQuality.Poor then
        type_flag = Enum.BagSlotFlags.ClassJunk
    elseif class == Enum.ItemClass.Consumable then
        type_flag = Enum.BagSlotFlags.ClassConsumables
    elseif class == Enum.ItemClass.Weapon or
           class == Enum.ItemClass.Armor then
        type_flag = Enum.BagSlotFlags.ClassEquipment
    elseif class == Enum.ItemClass.Tradegoods then
        type_flag = Enum.BagSlotFlags.ClassReagents
    elseif class == Enum.ItemClass.Recipe or
           class == Enum.ItemClass.Profession then
        type_flag = Enum.BagSlotFlags.ClassProfessionGoods
    end
    if type_flag then
        for bag_id = 1, Constants.InventoryConstants.NumBagSlots do
            if C_Container.GetBagSlotFlag(bag_id, type_flag) then
                local slot = FindEmptySlot(bag_id)
                if slot then return bag_id, slot end
            end
        end
    end
    for bag_id = 0, Constants.InventoryConstants.NumBagSlots do
        local slot = FindEmptySlot(bag_id)
        if slot then return bag_id, slot end
    end
    return nil
end


---------------------------------------------------------------------------
-- Menu handler for BankFrame
---------------------------------------------------------------------------

local BankFrameHandler = class(MenuCursor.StandardMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(BankFrameHandler)
local BankItemSubmenuHandler = class(MenuCursor.StandardMenuFrame)

function BankFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
    -- Item submenu dropdown and associated cursor handler.
    class.item_submenu = BankItemSubmenu()
    class.instance_submenu = BankItemSubmenuHandler(class.item_submenu)
end

function BankFrameHandler:__constructor()
    self:__super(BankFrame)
    self.cursor_show_item = true
    self.cancel_func = self.OnCancel
    self.has_Button4 = true  -- Used to display item operation submenu.
    self.on_prev_page = function() self:OnPageCycle(-1) end
    self.on_next_page = function() self:OnPageCycle(1) end
    self.tab_handler = function(direction) self:OnTabCycle(direction) end

    self.current_subframe = nil  -- Currently active subframe.
    self.subframes = {BankSlotsFrame, ReagentBankFrame, AccountBankPanel}
    for _, subframe in ipairs(self.subframes) do
        self:HookShow(subframe, self.OnSubframeChange, self.OnSubframeChange)
    end
end

function BankFrameHandler:OnCancel()
    if GetCursorInfo() then
        ClearCursor()
    else
        HideUIPanel(BankFrame)
    end
end

function BankFrameHandler:OnTabCycle(direction)
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = #self.frame.Tabs
    elseif new_index > #self.frame.Tabs then
        new_index = 1
    end
    local tab = self.frame.Tabs[new_index]
    tab:GetScript("OnClick")(tab, "LeftButton", true)
end

function BankFrameHandler:OnPageCycle(direction)
    local f = AccountBankPanel
    if not f:IsVisible() then return end
    local tabs = {}
    for tab in f.bankTabPool:EnumerateActive() do
        tinsert(tabs, tab)
    end
    table.sort(tabs, function(a,b) return a.tabData.ID < b.tabData.ID end)
    if f.PurchaseTab then
        tinsert(tabs, f.PurchaseTab)
    end
    for i, tab in ipairs(tabs) do
        if tab:IsSelected() then
            local target = i + direction
            if target < 1 then target = #tabs end
            if target > #tabs then target = 1 end
            target = tabs[target]
            target:GetScript("OnClick")(target, "LeftButton", true)
            return
        end
    end
end

function BankFrameHandler:OnHide()
    MenuCursor.CoreMenuFrame.OnHide(self)
    self.current_subframe = nil
end

function BankFrameHandler:OnSubframeChange()
    local active = self:GetActiveSubframe()
    if active ~= self.current_subframe then
        self:RefreshTargets()
    end
end

function BankFrameHandler:GetActiveSubframe()
    for _, subframe in ipairs(self.subframes) do
        if subframe:IsVisible() then
            return subframe
        end
    end
    return nil
end

function BankFrameHandler:RefreshTargets()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function BankFrameHandler:SetTargets()
    self.current_subframe = self:GetActiveSubframe()
    local f = self.current_subframe
    if not f then
        return nil
    end

    self.targets = {
        [BankItemAutoSortButton] = {can_activate = true, lock_highlight = true,
                                    send_enter_leave = true,
                                    left = false, right = false},
    }

    if f == BankSlotsFrame then
        assert(C_Container.GetContainerNumSlots(f.Item1:GetBagID()) == 28)
        for i = 1, 28 do
            local item = f["Item"..i]
            local row = floor((i-1)/7)
            local up = row==0 and BankItemAutoSortButton or f["Item"..(i-7)]
            local down = row==3 and f["Bag"..(i-21)] or f["Item"..(i+7)]
            local left = i==1 and f.Item28 or f["Item"..(i-1)]
            local right = i==28 and f.Item1 or f["Item"..(i+1)]
            self.targets[item] = {
                is_item = true, on_click = function() self:ClickItem(item) end,
                lock_highlight = true, send_enter_leave = true,
                up = up, down = down, left = left, right = right}
        end
        for i = 1, 7 do
            local bag = f["Bag"..i]
            local up = f["Item"..(i+21)]
            local left = i==1 and f.Bag7 or f["Bag"..(i-1)]
            local right = i==7 and f.Bag1 or f["Bag"..(i+1)]
            self.targets[bag] = {
                is_bag = true, can_activate = true, lock_highlight = true,
                lock_highlight = true, send_enter_leave = true,
                up = up, down = BankItemAutoSortButton,
                left = left, right = right}
        end
        self.targets[BankItemAutoSortButton].up = f.Bag7
        self.targets[BankItemAutoSortButton].down = f.Item7
        return f.Item1

    elseif f == ReagentBankFrame then
        assert(C_Container.GetContainerNumSlots(f.Item1:GetBagID()) == 98)
        for i = 1, 98 do
            local item = f["Item"..i]
            local col = floor((i-1)/7)
            local row = (i-1)%7
            local up = row==0 and BankItemAutoSortButton or f["Item"..(i-1)]
            local down = row==6 and f.DespositButton or f["Item"..(i+1)]
            local left = col==0 and f["Item"..(i+91)] or f["Item"..(i-7)]
            local right = col==13 and f["Item"..(i-91)] or f["Item"..(i+7)]
            self.targets[item] = {
                is_item = true, on_click = function() self:ClickItem(item) end,
                send_enter_leave = true,
                up = up, down = down, left = left, right = right}
        end
        self.targets[f.DespositButton] = {  -- Typo in Blizzard code.
            can_activate = true, lock_highlight = true,
            up = f.Item7, down = BankItemAutoSortButton,
            left = false, right = false}
        self.targets[BankItemAutoSortButton].up = f.DespositButton
        self.targets[BankItemAutoSortButton].down = f.Item92
        return f.Item1

    else
        assert(f == AccountBankPanel)
        self.targets[f.MoneyFrame.WithdrawButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, down = BankItemAutoSortButton,
             left = f.MoneyFrame.DepositButton,
             right = f.MoneyFrame.DepositButton}
        self.targets[f.MoneyFrame.DepositButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, down = BankItemAutoSortButton,
             left = f.MoneyFrame.WithdrawButton,
             right = f.MoneyFrame.WithdrawButton}
        self.targets[BankItemAutoSortButton].up = f.MoneyFrame.DepositButton
        local bag_id = f.selectedTabID
        if bag_id == -1 then  -- "Purchase new tab" tab
            local button = f.PurchasePrompt.TabCostFrame.PurchaseButton
            self.targets[button] = {can_activate = true, lock_highlight = true,
                                    up = f.MoneyFrame.WithdrawButton,
                                    down = f.MoneyFrame.WithdrawButton,
                                    left = false, right= false}
            self.targets[f.MoneyFrame.WithdrawButton].up = button
            self.targets[f.MoneyFrame.DepositButton].up = button
            self.targets[BankItemAutoSortButton].down = button
            return button
        end
        self.targets[f.ItemDepositFrame.DepositButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, down = f.MoneyFrame.WithdrawButton,
             left = f.ItemDepositFrame.IncludeReagentsCheckbox,
             right = f.ItemDepositFrame.IncludeReagentsCheckbox}
        self.targets[f.ItemDepositFrame.IncludeReagentsCheckbox] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, down = f.MoneyFrame.WithdrawButton,
             left = f.ItemDepositFrame.DepositButton,
             right = f.ItemDepositFrame.DepositButton}
        self.targets[f.MoneyFrame.WithdrawButton].up =
            f.ItemDepositFrame.DepositButton
        self.targets[f.MoneyFrame.DepositButton].up =
            f.ItemDepositFrame.DepositButton
        local bag_size = C_Container.GetContainerNumSlots(bag_id)
        assert(bag_size == 98)
        local items = {}
        for item in f.itemButtonPool:EnumerateActive() do
            items[item.containerSlotID] = item
        end
        assert(#items == bag_size)
        for i = 1, 98 do
            local item = items[i]
            local col = floor((i-1)/7)
            local row = (i-1)%7
            local up = row==0 and BankItemAutoSortButton or items[i-1]
            local down = row==6 and f.ItemDepositFrame.DepositButton or items[i+1]
            local left = col==0 and items[i+91] or items[i-7]
            local right = col==13 and items[i-91] or items[i+7]
            self.targets[item] = {
                is_item = true, on_click = function() self:ClickItem(item) end,
                send_enter_leave = true,
                up = up, down = down, left = left, right = right}
        end
        self.targets[BankItemAutoSortButton].down = items[92]
        self.targets[f.ItemDepositFrame.DepositButton].up = items[7]
        self.targets[f.ItemDepositFrame.IncludeReagentsCheckbox].up = items[98]
        return items[1]
    end
end

function BankFrameHandler:ClickItem()
    local _, bag, slot = self:GetTargetItem()
    C_Container.PickupContainerItem(bag, slot)
end

function BankFrameHandler:OnAction(button)
    assert(button == "Button4")
    if GetCursorInfo() then return end
    local item, bag, slot = self:GetTargetItem()
    if item then
        self.item_submenu:Open(item, bag, slot)
    end
end

-- If the current target is an item button, returns the button and its
-- bag/slot location; otherwise, returns nil.
function BankFrameHandler:GetTargetItem()
    local item = self:GetTarget()
    if not self.targets[item].is_item then return nil end
    local bag, slot
    if self.current_subframe == AccountBankPanel then
        bag = item.bankTabID
        slot = item.containerSlotID
    else
        bag = item:GetBagID()
        slot = item:GetID()
    end
    return item, bag, slot
end


---------------------------------------------------------------------------
-- Item submenu handler and implementation
---------------------------------------------------------------------------

function BankItemSubmenuHandler:__constructor(submenu)
    self:__super(submenu, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = function(self) self.frame:Close() end
end

function BankItemSubmenuHandler:SetTargets()
    self.targets = {}
    local initial
    for _, button in ipairs(self.frame.buttons) do
        self.targets[button] = {can_activate = true}
        initial = initial or button
    end
    return initial
end


function BankItemSubmenu:__constructor()
    self:__super()

    -- "Take out" and "Take all" are the same thing, chosen depending
    -- on whether the item is a stack or not.
    self.menuitem_takeout =
        WoWXIV.UI.ItemSubmenuButton(self, "Take out", false)
    self.menuitem_takeout.ExecuteInsecure =
        function(bag, slot) self:TakeAllOrSome(bag, slot) end
    self.menuitem_takeall =
        WoWXIV.UI.ItemSubmenuButton(self, "Take all", false)
    self.menuitem_takeall.ExecuteInsecure =
        function(bag, slot) self:TakeAllOrSome(bag, slot) end

    self.menuitem_takesome =
        WoWXIV.UI.ItemSubmenuButton(self, "Take some", false)
    self.menuitem_takesome.ExecuteInsecure =
        function(bag, slot, info, item)
            self:DoTakeSome(bag, slot, info, item)
        end

    self.menuitem_splitstack =
        WoWXIV.UI.ItemSubmenuButton(self, "Split stack", false)
    self.menuitem_splitstack.ExecuteInsecure =
        function(bag, slot, info, item)
            self:DoSplitStack(bag, slot, info, item)
        end

    self.menuitem_discard =
        WoWXIV.UI.ItemSubmenuButton(self, "Discard", false)
    self.menuitem_discard.ExecuteInsecure =
        function(bag, slot, info) self:DoDiscard(bag, slot, info) end
end

function BankItemSubmenu:ConfigureForItem(bag, slot)
    local bag, slot = self.bag, self.slot
    local info = C_Container.GetContainerItemInfo(bag, slot)

    if info.stackCount > 1 then
        self:AppendButton(self.menuitem_takeall)
        self:AppendButton(self.menuitem_takesome)
        self:AppendButton(self.menuitem_splitstack)
    else
        self:AppendButton(self.menuitem_takeout)
    end
    self:AppendButton(self.menuitem_discard)
end

-------- Individual menu option handlers

-- Called directly for "Take out"/"Take all"; called as a SplitStackFrame
-- callback for "Take some".
function BankItemSubmenu:TakeAllOrSome(bag, slot, link, count)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    local target_bag, target_slot = FindInventorySlot(info)
    if not target_bag then
        WoWXIV.Error("No inventory slots available.")
        return
    end
    if link then  -- "take some
        if info.hyperlink ~= link then
            WoWXIV.Error("Item could not be found.")
            return
        end
        C_Container.SplitContainerItem(bag, slot, count)
    else
        C_Container.PickupContainerItem(bag, slot)
    end
    C_Container.PickupContainerItem(target_bag, target_slot)
end

-- See notes at ContainerItemSubmenu:DoSplitStack().
function BankItemSubmenu:DoTakeSome(bag, slot, info, item_button)
    if info.stackCount <= 1 then return end
    local limit = info.stackCount - 1
    if limit == 1 then
        self:DoTakeSomeConfirm(bag, slot, info.hyperlink, 1)
        return
    end
    StackSplitFrame:OpenStackSplitFrame(limit, item_button,
                                        "BOTTOMLEFT", "TOPLEFT")
    StackSplitFrame.owner = {SplitStack = function(_, count)
        self:TakeAllOrSome(bag, slot, info.hyperlink, count)
    end}
    MenuCursor.StackSplitFrameEditQuantity()
end

function BankItemSubmenu:DoSplitStack(bag, slot, info, item_button)
    if info.stackCount <= 1 then return end
    local limit = info.stackCount - 1
    if limit == 1 then
        self:DoSplitStackConfirm(bag, slot, info.hyperlink, 1)
        return
    end
    StackSplitFrame:OpenStackSplitFrame(limit, item_button,
                                        "BOTTOMLEFT", "TOPLEFT")
    StackSplitFrame.owner = {SplitStack = function(_, count)
        self:DoSplitStackConfirm(bag, slot, info.hyperlink, count)
    end}
    MenuCursor.StackSplitFrameEditQuantity()
end

function BankItemSubmenu:DoSplitStackConfirm(bag, slot, link, count)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    if info.hyperlink ~= link then
        WoWXIV.Error("Item could not be found.")
        return
    end
    C_Container.SplitContainerItem(bag, slot, count)
end

function BankItemSubmenu:DoDiscard(bag, slot, info)
    local class = select(12, C_Item.GetItemInfo("item:"..info.itemID))
    local text, check_text
    if class == Enum.ItemClass.Questitem then
        text = "Discard |W%s,|w abandoning any related quests?"
    elseif info.quality >= Enum.ItemQuality.Rare then
        text = "Are you sure you want to discard |W%s?|w"
        check_text = "Discard this high-quality item."
    else
        text = "Discard |W%s?|w"
    end
    local name = select(3, LinkUtil.ExtractLink(info.hyperlink))
    if name then
        if strsub(name, 1, 1) == "[" and strsub(name, -1) == "]" then
            name = strsub(name, 2, -2)
        end
    else
        name = info.itemName
    end
    name = WoWXIV.FormatItemColor(name, info.quality)
    if info.stackCount > 1 then
        name = strformat("%s×%d", name, info.stackCount)
    end
    text = strformat(text, name)
    WoWXIV.ShowConfirmation(
        text, check_text, "Discard", "Cancel",
        function() self:DoDiscardConfirm(bag, slot, info.hyperlink) end)
end

function BankItemSubmenu:DoDiscardConfirm(bag, slot, link)
    ClearCursor()
    assert(not GetCursorInfo())
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    C_Container.PickupContainerItem(bag, slot)
    local cursor_type, _, cursor_link = GetCursorInfo()
    if not (cursor_type == "item" and cursor_link == link) then
        WoWXIV.Error("Item could not be found.")
        ClearCursor()
        return
    end
    DeleteCursorItem()
end
