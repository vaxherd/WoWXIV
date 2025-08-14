local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local floor = math.floor
local strformat = string.format
local strsub = string.sub
local tinsert = tinsert
local yield = coroutine.yield


assert(WoWXIV.UI.ItemSubmenu)  -- Ensure proper load order.

local BankItemSubmenu = class(WoWXIV.UI.ItemSubmenu)


---------------------------------------------------------------------------
-- Utility routines
---------------------------------------------------------------------------

-- Find an inventory bag and slot suitable for the given item.  If a count
-- is also given, ensure that that many of the item can fit in the returned
-- slot.
local function FindInventorySlot(info, count)
    local function FindEmptySlot(bag_id)
        for i = 1, C_Container.GetContainerNumSlots(bag_id) do
            if not C_Container.GetContainerItemInfo(bag_id, i) then
                return i
            end
        end
        return nil
    end

    -- If no count was given, we take any stack which isn't full.
    count = count or 1

    -- First look for an existing stack we can add to.
    local max_stack, _, _, _, class, subclass =
        select(8, C_Item.GetItemInfo(info.itemID))
    local NUM_TOTAL_BAG_FRAMES = Constants.InventoryConstants.NumBagSlots + Constants.InventoryConstants.NumReagentBagSlots
    for bag_id = 0, NUM_TOTAL_BAG_FRAMES do
        for i = 1, C_Container.GetContainerNumSlots(bag_id) do
            local slot_info = C_Container.GetContainerItemInfo(bag_id, i)
            if slot_info and slot_info.itemID == info.itemID
            and slot_info.stackCount + count <= max_stack
            then
                if not slot_info.isLocked then
                    return bag_id, i, slot_info.stackCount
                end
            end
        end
    end

    -- No viable stack found, so look for an appropriate empty slot.
    if not target_bag and WoWXIV.IsItemReagent(info.itemID) then
        for i = 1, Constants.InventoryConstants.NumReagentBagSlots do
            local reagent_bag = Constants.InventoryConstants.NumBagSlots + i
            local slot = FindEmptySlot(reagent_bag)
            if slot then return reagent_bag, slot, 0 end
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
                if slot then return bag_id, slot, 0 end
            end
        end
    end
    for bag_id = 0, Constants.InventoryConstants.NumBagSlots do
        local slot = FindEmptySlot(bag_id)
        if slot then return bag_id, slot, 0 end
    end
    return nil
end


---------------------------------------------------------------------------
-- Menu handler for BankFrame
---------------------------------------------------------------------------

local BankFrameHandler = class(MenuCursor.StandardMenuFrame)
MenuCursor.BankFrameHandler = BankFrameHandler  -- For exports.
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
    __super(self, BankFrame)
    self.cursor_show_item = true
    self.cancel_func = self.OnCancel
    self.has_Button4 = true  -- Used to display item operation submenu.
    self.on_prev_page = function() self:OnPageCycle(-1) end
    self.on_next_page = function() self:OnPageCycle(1) end
    self:SetTabSystem(self.frame.TabSystem)
    BankPanel:RegisterCallback(BankPanelMixin.Event.NewBankTabSelected,
                               function() self:RefreshTargets() end)
end

function BankFrameHandler:OnCancel()
    if GetCursorInfo() then
        ClearCursor()
    else
        HideUIPanel(BankFrame)
    end
end

function BankFrameHandler:OnPageCycle(direction)
    local tabs = {}
    for tab in BankPanel.bankTabPool:EnumerateActive() do
        tinsert(tabs, tab)
    end
    table.sort(tabs, function(a,b) return a.tabData.ID < b.tabData.ID end)
    if BankPanel.PurchaseTab:IsShown() then
        tinsert(tabs, BankPanel.PurchaseTab)
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

function BankFrameHandler:RefreshTargets()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function BankFrameHandler:SetTargets()
    self.targets = {}
    local f = BankPanel
    local bag_id = f.selectedTabID
    if bag_id == -1 then  -- "Purchase new tab" tab
        local button = f.PurchasePrompt.TabCostFrame.PurchaseButton
        self.targets[button] = {can_activate = true, lock_highlight = true}
        return button
    end
    local bag_size = C_Container.GetContainerNumSlots(bag_id)
    assert(bag_size == 98)  -- Currently true for all bank tabs.
    local items = {}
    for item in f.itemButtonPool:EnumerateActive() do
        items[item.containerSlotID] = item
    end
    if #items == 0 then  -- Frame is still being set up.
        RunNextFrame(function() self:RefreshTargets() end)
        return nil
    end
    assert(#items == bag_size)
    for i = 1, 98 do
        local item = items[i]
        local col = floor((i-1)/7)
        local up = i==1 and items[98] or items[i-1]
        local down = i==98 and items[1] or items[i+1]
        local left = col==0 and items[i+91] or items[i-7]
        local right = col==13 and items[i-91] or items[i+7]
        self.targets[item] = {
            is_item = true, on_click = function() self:ClickItem(item) end,
            send_enter_leave = true,
            up = up, down = down, left = left, right = right}
    end
    return items[1]
end

function BankFrameHandler:ClickItem()
    local _, bag, slot = self:GetTargetItem()
    if not ItemLocation:CreateFromBagAndSlot(bag, slot):IsValid() then
        -- Slot is empty, but allow the click anyway if the cursor is
        -- holding something (it might be an item the player is trying
        -- to drop).
        if not GetCursorInfo() then
            return
        end
    end
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
    __super(self, submenu, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = function(self) self.frame:Close() end
end

function BankItemSubmenuHandler:SetTargets()
    self.targets = {}
    local f = self.frame
    local initial
    for i, button in ipairs(f.buttons) do
        self.targets[button] = {can_activate = true,
                                up = f.buttons[i==1 and #f.buttons or i-1],
                                down = f.buttons[i==#f.buttons and 1 or i+1]}
        initial = initial or button
    end
    return initial
end


function BankItemSubmenu:__constructor()
    __super(self)

    -- "Take out" and "Take all" are the same thing, chosen depending
    -- on whether the item is a stack or not.
    self.menuitem_takeout =
        WoWXIV.UI.ItemSubmenuButton(self, "Take out", false)
    self.menuitem_takeout.ExecuteInsecure = function(bag, slot)
        self:TakeAllOrSome(bag, slot)
    end
    self.menuitem_takeall =
        WoWXIV.UI.ItemSubmenuButton(self, "Take all", false)
    self.menuitem_takeall.ExecuteInsecure = function(bag, slot)
        self:TakeAllOrSome(bag, slot)
    end

    self.menuitem_takesome =
        WoWXIV.UI.ItemSubmenuButton(self, "Take some", false)
    self.menuitem_takesome.ExecuteInsecure = function(bag, slot, info, item)
        self:DoTakeSome(bag, slot, info, item)
    end

    self.menuitem_disenchant =
        WoWXIV.UI.ItemSubmenuButton(self, "Disenchant", true)
    self.menuitem_disenchant:SetAttribute("type", "spell")
    self.menuitem_disenchant:SetAttribute("spell", WoWXIV.SPELL_DISENCHANT)

    self.menuitem_splitstack =
        WoWXIV.UI.ItemSubmenuButton(self, "Split stack", false)
    self.menuitem_splitstack.ExecuteInsecure = function(bag, slot, info, item)
        self:DoSplitStack(bag, slot, info, item)
    end

    self.menuitem_sort_tab =
        WoWXIV.UI.ItemSubmenuButton(self, "Sort tab", false)
    self.menuitem_sort_tab.ExecuteInsecure = function(bag, slot, info)
        self:DoSortTab(bag)
    end

    self.menuitem_discard =
        WoWXIV.UI.ItemSubmenuButton(self, "Discard", false)
    self.menuitem_discard.ExecuteInsecure = function(bag, slot, info)
        self:DoDiscard(bag, slot, info)
    end
end

function BankItemSubmenu:ConfigureForItem(bag, slot)
    local bag, slot = self.bag, self.slot
    local info = C_Container.GetContainerItemInfo(bag, slot)

    if info.stackCount > 1 then
        self:AppendButton(self.menuitem_takeall)
        self:AppendButton(self.menuitem_takesome)
    else
        self:AppendButton(self.menuitem_takeout)
    end

    -- Theoretically possible, but blocked by taint (possibly tooltip
    -- related).
    --[[
    if C_Spell.IsSpellUsable(WoWXIV.SPELL_DISENCHANT) then
        if WoWXIV.IsItemDisenchantable(info.itemID) then
            self:AppendButton(self.menuitem_disenchant)
        end
    end
    ]]--

    if info.stackCount > 1 then
        self:AppendButton(self.menuitem_splitstack)
    end

    self:AppendButton(self.menuitem_sort_tab)

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
    -- If the player requested "take some" (and thus count is non-nil),
    -- require that many to fit onto the target stack; otherwise, look for
    -- any non-full stack and we'll split the stack ourselves if needed.
    local target_bag, target_slot, target_count = FindInventorySlot(info, count)
    if not target_bag then
        WoWXIV.Error("No inventory slots available.")
        return
    end
    if link then  -- "take some"
        -- In this case we're coming here after a quantity input, so
        -- check that the slot hasn't changed when we weren't looking.
        if info.hyperlink ~= link then
            WoWXIV.Error("Item could not be found.")
            return
        end
        C_Container.SplitContainerItem(bag, slot, count)
    else
        local limit = select(8, C_Item.GetItemInfo(info.itemID))
        if target_count > 0 and target_count + info.stackCount > limit then
            C_Container.SplitContainerItem(bag, slot, limit - target_count)
        else
            C_Container.PickupContainerItem(bag, slot)
        end
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

function BankItemSubmenu:DoSortTab(bag)
    local sorter = WoWXIV.isort_execute(bag)
    BankFrameHandler.instance:RunUnderLock(function()
        while not sorter:Run() do
            local status = yield(true)
            if status == MenuCursor.MenuFrame.RUNUNDERLOCK_ABORT then
                WoWXIV.Error("Tab sort interrupted.")
                return
            elseif status == MenuCursor.MenuFrame.RUNUNDERLOCK_CANCEL then
                WoWXIV.Error("Tab sort cancelled.", false)
                sorter:Abort()
            end
        end
    end)
end

function BankItemSubmenu:DoDiscard(bag, slot, info)
    local class = select(12, C_Item.GetItemInfo(info.itemID))
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
