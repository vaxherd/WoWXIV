local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class
local set = WoWXIV.set
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

local strformat = string.format
local strsub = string.sub
local tinsert = tinsert
local tremove = tremove
local yield = coroutine.yield


assert(WoWXIV.UI.ItemSubmenu)  -- Ensure proper load order.

-- Declared early to make available to utility routines.
local ContainerFrameHandler = class(MenuCursor.MenuFrame)

-- Class implementing the item submenu for inventory items.  We roll our
-- own rather than using the standard DropdownMenuButton so we can include
-- secure buttons to perform use/disenchant/etc actions.
local InventoryItemSubmenu = class(WoWXIV.UI.ItemSubmenu)


---------------------------------------------------------------------------
-- Utility routines
---------------------------------------------------------------------------

-- Send an item (identified by ItemLocation) to the auction house, and
-- focus the auction house sell frame if it's already visible.  (If it's
-- not visible, it will be imminently Show()n and the menu handler will
-- focus it at that point.)
local function SendToAuctionHouse(item_loc, info)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    AuctionHouseFrame:SetPostItem(item_loc)
    MenuCursor.AuctionHouseFrameHandler.FocusSellFrameFromInventory()
end

-- Send an item to the currently active bank frame.  May start a locked
-- sequence in order to split the source stack among multiple bank slots.
local InternalSendToBank  -- Forward declaration.
local function SendToBank(bag, slot, info)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    ContainerFrameHandler.instance:RunUnderLock(
        InternalSendToBank, bag, slot, info)
end
function InternalSendToBank(bag, slot, info)
    ClearCursor()
    assert(not GetCursorInfo())
    local limit = select(8, C_Item.GetItemInfo(info.itemID)) or 0
    local function SearchBag(bag_id)
        local size = C_Container.GetContainerNumSlots(bag_id) or 0
        local empty_slot
        for i = 1, size do
            local info2 = C_Container.GetContainerItemInfo(bag_id, i)
            if info2 then
                if info2.itemID == info.itemID and info2.stackCount < limit then
                    return bag_id, i, info2.stackCount
                end
            else
                if not empty_slot then
                    empty_slot = i
                end
            end
        end
        return nil, empty_slot
    end
    local target_bag, target_slot, target_count, empty_bag, empty_slot
    local bank_type = BankPanel:GetActiveBankType()
    for _, bag_id in ipairs(C_Bank.FetchPurchasedBankTabIDs(bank_type)) do
        target_bag, target_slot, target_count = SearchBag(bag_id)
        if target_bag then break end
        -- Standard game behavior is to take the first empty slot in
        -- the numerically first tab, but we choose to prioritize an
        -- empty slot in the currently displayed tab as better UX.
        if (not empty_bag
            or (bag_id == BankPanel:GetSelectedTabID()
                and empty_bag ~= bag_id))
        and target_slot then
            empty_bag, empty_slot = bag_id, target_slot
        end
    end
    if not target_bag then
        if empty_bag then
            target_bag, target_slot, target_count = empty_bag, empty_slot, 0
        else
            WoWXIV.Error("No room in bank for item.")
            return
        end
    end
    local is_partial
    if target_count + info.stackCount > limit then
        local split_count = limit - target_count
        C_Container.SplitContainerItem(bag, slot, split_count)
        is_partial = true
    else
        C_Container.PickupContainerItem(bag, slot)
    end
    local cursor_type, _, cursor_link = GetCursorInfo()
    assert(cursor_type == "item" and cursor_link == info.hyperlink)
    C_Container.PickupContainerItem(target_bag, target_slot)
    if is_partial then
        info.isLocked = true  -- Because we just picked it up.
        local item_loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local guid = C_Item.GetItemGUID(item_loc)
        local status
        while info.isLocked do
            status = yield(true)
            if status == MenuCursor.MenuFrame.RUNUNDERLOCK_ABORT then
                WoWXIV.Error("Item transfer interrupted.")
                return
            end
            info = C_Container.GetContainerItemInfo(bag, slot)
        end
        if status == MenuCursor.MenuFrame.RUNUNDERLOCK_CANCEL then
            return
        end
        if C_Item.GetItemGUID(item_loc) ~= guid then
            WoWXIV.Error("Item transfer interrupted due to inventory change.")
            return
        end
        return InternalSendToBank(bag, slot, info)
    end
end

-- Sell an item to a merchant.
local function SellItem(item_button, bag, slot, info)
    ClearCursor()
    assert(not GetCursorInfo())
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    -- This function is somewhat misnamed; it doesn't return a string of
    -- any sort, but shows the "refund this item?" popup and returns true
    -- if the item can be refunded.  Ideally we'd have a separate function
    -- which tells us whether it can be refunded, so we could show a
    -- "Refund" menu item in place of "Sell"; we could potentially write
    -- our own copy, but that would risk getting out of sync with upstream
    -- code on a potentially player-harming action, so we accept the
    -- awkwardness of keeping "Sell" even when a refund is possible (and
    -- in fairness, the tooltip will indicate refundability).
    if ContainerFrame_GetExtendedPriceString(item_button) then
        -- Popup is already shown, do nothing.
    else
        C_Container.PickupContainerItem(bag, slot)
        local cursor_type, _, cursor_link = GetCursorInfo()
        assert(cursor_type == "item" and cursor_link == info.hyperlink)
        SellCursorItem()
    end
end

-- Send an item to the item interaction frame.
local function SendToItemInteraction(item_loc, info)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
    end
    C_ItemInteraction.SetPendingItem(item_loc)
    MenuCursor.ItemInteractionFrameHandler.FocusActionButton()
end

-- Send an item to the item upgrade frame.
local function SendToItemUpgrade(bag, slot, info)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
    end
    C_Container.PickupContainerItem(bag, slot)
    C_ItemUpgrade.SetItemUpgradeFromCursorItem()
    MenuCursor.ItemUpgradeFrameHandler.FocusUpgradeButton()
end

-- Send an item to a scrapping machine (BfA, Remix etc).
local function SendToScrapper(bag, slot, info)
    ClearCursor()
    assert(not GetCursorInfo())
    local function FindSlot(b, s)
        for i = 0, 8 do
            local loc = C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(i)  -- whew, that's a mouthful
            if (b and loc and loc:IsEqualToBagAndSlot(b, s))
            or (not b and not loc)
            then
                return i
            end
        end
        return nil
    end
    if info.isLocked then
        -- It could be locked because it's already in the machine, in which
        -- case we should just pull it out instad.
        local scrap_slot = FindSlot(bag, slot)
        if scrap_slot then
            C_ScrappingMachineUI.RemoveItemToScrap(scrap_slot)
        else
            WoWXIV.Error("Item is locked.")
        end
        return
    end
    local scrap_slot = FindSlot()
    if not scrap_slot then
        WoWXIV.Error("The scrapper is full.")
        return
    end
    C_Container.PickupContainerItem(bag, slot)
    local cursor_type, _, cursor_link = GetCursorInfo()
    assert(cursor_type == "item" and cursor_link == info.hyperlink)
    C_ScrappingMachineUI.DropPendingScrapItemFromCursor(scrap_slot)
    if GetCursorInfo() then
        -- If the item is invalid for the scrapper or the scrapper is
        -- busy, the DropPending call will fail and leave the item on the
        -- cursor.  Report an error so the user knows to wait.
        WoWXIV.Error("The scrapping machine is busy.", true)
        ClearCursor()
        return
    end
    if not FindSlot() then
        -- Machine is full, time to scrap!
        MenuCursor.ScrappingMachineFrameHandler:FocusScrapButton()
    end
end

-- Send an item to a socket in the socketing interface.
-- If the item with the sockets has multiple sockets open, the first
-- free socket is chosen.  As a special case, for Circe's Circlet
-- (three sockets each requiring a different gem type), gems are sent
-- to the proper socket for that gem's type.
-- Unfortunately, there doesn't seem to be any way to get the subtype
-- of a nonstandard gem like the Singing Citrines, so we have to make
-- our own item list...
local GEM_TYPES = {
    [228634] = "SingingThunder",  -- Thunderlord's Crackling Citrine
    [228635] = "SingingWind",     -- Squall Sailor's Citrine
    [228636] = "SingingSea",      -- Undersea Overseer's Citrine
    [228638] = "SingingThunder",  -- Stormbringer's Runed Citrine
    [228639] = "SingingSea",      -- Fathomdweller's Runed Citrine
    [228640] = "SingingWind",     -- Windsinger's Runed Citrine
    [228642] = "SingingThunder",  -- Storm Sewer's Citrine
    [228643] = "SingingWind",     -- Old Salt's Bardic Citrine
    [228644] = "SingingSea",      -- Mariner's Hallowed Citrine
    [228646] = "SingingWind",     -- Legendary Skipper's Citrine
    [228647] = "SingingSea",      -- Seabed Leviathan's Citrine
    [228648] = "SingingThunder",  -- Roaring War-Queen's Citrine
}
local function SendToSocket(bag, slot, info)
    ClearCursor()
    assert(not GetCursorInfo())
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    -- Find the first empty slot.  Gem removals (on supported items) are
    -- always immediately applied, so we don't have to worry about the
    -- case of a pending removal.
    for i = 1, GetNumSockets() do
        local current = GetExistingSocketInfo(i)
        local pending = GetNewSocketInfo(i)
        if not current and not pending then
            local reject
            local type = GetSocketTypes(i)
            if type and strsub(type, 1, 7) == "Singing" then
                if GEM_TYPES[info.itemID] ~= type then reject = true end
            end
            if not reject then
                C_Container.PickupContainerItem(bag, slot)
                local cursor_type, _, cursor_link = GetCursorInfo()
                assert(cursor_type == "item" and cursor_link == info.hyperlink)
                ClickSocketButton(i)
                ClearCursor()  -- Looks like we have to do this manually.
                return
            end
        end
    end
    local error
    if GetNumSockets() > 1 then
        error = "No empty sockets available."
    else
        error = "The socket is already filled."
    end
    WoWXIV.Error(error)
end

-- Start an auto-deposit operation.
-- This displays a confirmation dialog, which when confirmed will start
-- the actual auto-deposit sequence.
local AutoDeposit  -- Forward declarations.
local function StartAutoDeposit()
    local text =
        "Deposit all stackable items which already have stacks in the bank?"
    local function RunAutoDeposit()
        ContainerFrameHandler.instance:RunUnderLock(AutoDeposit)
    end
    WoWXIV.ShowConfirmation(text, nil, "Deposit", "Cancel", RunAutoDeposit)
end
function AutoDeposit(prev_bag, prev_slot)
    local INVENTORY_BAGS = {Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1,
                            Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3,
                            Enum.BagIndex.Bag_4, Enum.BagIndex.ReagentBag}
    local BANK_BAGS = {Enum.BagIndex.CharacterBankTab_1,
                       Enum.BagIndex.CharacterBankTab_2,
                       Enum.BagIndex.CharacterBankTab_3,
                       Enum.BagIndex.CharacterBankTab_4,
                       Enum.BagIndex.CharacterBankTab_5,
                       Enum.BagIndex.CharacterBankTab_6,
                       Enum.BagIndex.AccountBankTab_1,
                       Enum.BagIndex.AccountBankTab_2,
                       Enum.BagIndex.AccountBankTab_3,
                       Enum.BagIndex.AccountBankTab_4,
                       Enum.BagIndex.AccountBankTab_5}

    -- First look up stackable items in the bank, so we know which to send.
    -- Also record where those items are stored for later lookup, along with
    -- sets of empty slots for each bank bag.
    local target_items = {}  -- Mapping from item ID to "is target" flag.
    local target_bags = {}   -- Mapping from item ID to bag list.
    local target_slots = {}  -- Mapping from item ID to {bag,slot,space} list.
    local empty_slots = {}   -- Mapping from bag ID to slot index list.
    local max_stack = {}     -- Mapping from item ID to max stack size.
    for _, bag in ipairs(BANK_BAGS) do
        local size = C_Container.GetContainerNumSlots(bag) or 0
        empty_slots[bag] = {}
        for slot = 1, size do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                id = info.itemID
                if target_items[id] == nil then
                    if not max_stack[id] then
                        max_stack[id] = select(8, C_Item.GetItemInfo(id)) or 0
                    end
                    target_items[id] = (max_stack[id] > 1)
                end
                if target_items[id] then
                    -- For now, we create target_bags as a set for simplicity.
                    -- We rewrite it to a list when we're all done.
                    target_bags[id] = target_bags[id] or set()
                    target_bags[id]:add(bag)
                    target_slots[id] = target_slots[id] or {}
                    local space = max_stack[id] - info.stackCount
                    assert(space >= 0)
                    if space > 0 then
                        tinsert(target_slots[id], {bag, slot, space})
                    end
                end
            else
                tinsert(empty_slots[bag], slot)
            end
        end
    end
    -- Turn target bag sets into lists sorted in BANK_BAGS order.
    for id, bag_set in pairs(target_bags) do
        local bag_list = {}
        for _, bag in ipairs(BANK_BAGS) do
            if bag_set:has(bag) then
                tinsert(bag_list, bag)
            end
        end
        target_bags[id] = bag_list
    end

    -- Next iterate over inventory bags, recording slots with sendable items.
    local source_slots = {}  -- List of {bag,slot,item} for each slot.
    for _, bag in ipairs(INVENTORY_BAGS) do
        local size = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, size do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and target_items[info.itemID] then
                tinsert(source_slots, {bag, slot, info.itemID})
            end
        end
    end
    if #source_slots == 0 then
        print(YELLOW_FONT_COLOR:WrapTextInColorCode(
            "Nothing found to auto-deposit."))
        return
    end

    -- Now start the actual move sequence.  Rather than simply sending all
    -- source slots in order, we batch as many nonconflicting moves as we
    -- can, then come back after slot locks clear to resolve remaining moves.
    ClearCursor()
    assert(not GetCursorInfo())
    local full_items = {}  -- Set of items we ran out of space for.
    while #source_slots > 0 do
        local unresolved = {}  -- List of unresolved slots for the next cycle.
        local pending_items = {}  -- Set of items we processed this cycle.
        local throttled = false  -- Did we fail a cursor operation?
        for i = 1, #source_slots do
            local bag, slot, id = unpack(source_slots[i])
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not info or info.itemID ~= id then
                WoWXIV.Error("Inventory consistency error, aborting deposit.")
                return
            end
            if throttled or info.isLocked or pending_items[id] then
                -- Avoid the risk of colliding move operations by only
                -- processing one stack of each source item each cycle.
                tinsert(unresolved, source_slots[i])
            elseif not full_items[id] then
                local limit = max_stack[id]
                local target_bag, target_slot, target_count
                -- Send to the first existing stack with space, if any.
                -- (Note that we don't try to skip over locked slots;
                -- we prefer consistent behavior over speed.)
                local is_merge
                if #target_slots[id] > 0 then
                    local space
                    target_bag, target_slot, space = unpack(target_slots[id][1])
                    assert(space > 0)
                    target_count = min(info.stackCount, space)
                    is_merge = true
                else
                    -- Otherwise, pick the first empty slot found in any bag
                    -- which already had a stack of this item.  (We enforce
                    -- this "same-bag" restriction partly to avoid items
                    -- getting pseudo-randomly scattered across bank bags and
                    -- partly to avoid having to check item restrictions on
                    -- reagent and account bank bags.)
                    for _, bag in ipairs(target_bags[id]) do
                        if #empty_slots[bag] > 0 then
                            target_bag, target_slot = bag, empty_slots[bag][1]
                            target_count = info.stackCount
                        end
                    end
                end
                if target_bag then
                    local target_info = C_Container.GetContainerItemInfo(
                        target_bag, target_slot)
                    if target_info and target_info.isLocked then
                        tinsert(unresolved, source_slots[i])
                    else
                        -- Actually perform the move!
                        if target_count < info.stackCount then
                            C_Container.SplitContainerItem(bag, slot,
                                                           target_count)
                        else
                            C_Container.PickupContainerItem(bag, slot)
                        end
                        local cursor_type, cursor_id = GetCursorInfo()
                        if not (cursor_type == "item" and cursor_id == id) then
                            if cursor_type then
                                -- Probably the player tried to do something
                                -- else while auto-deposit was in progress.
                                WoWXIV.Error("Auto-deposit aborted due to cursor error.")
                                return
                            else
                                -- If the cursor is empty, we probably hit
                                -- a throttling threshold or the like.
                                -- Exit this cycle now and try again later.
                                throttled = true
                            end
                        else
                            -- We've verified that the cursor has our item,
                            -- so drop it in the target slot and verify.
                            C_Container.PickupContainerItem(
                                target_bag, target_slot)
                            if GetCursorInfo() then
                                -- Again, presumably throttled.  Clear the
                                -- cursor so as not to confuse the next cycle.
                                throttled = true
                                ClearCursor()
                                if GetCursorInfo() then  -- Should be impossible?
                                    WoWXIV.Error("Auto-deposit aborted due to unexpected cursor error.")
                                    return
                                end
                            end
                        end
                        if throttled then
                            -- Retry this deposit next cycle.
                            tinsert(unresolved, source_slots[i])
                        else
                            -- The cursor is empty, so we assume the move
                            -- succeeded.  Update item tables as appropriate.
                            if is_merge then
                                local entry = target_slots[id][1]
                                assert(target_bag == entry[1])
                                assert(target_slot == entry[2])
                                entry[3] = entry[3] - target_count
                                assert(entry[3] >= 0)
                                if entry[3] == 0 then
                                    tremove(target_slots[id], 1)
                                end
                            else
                                assert(target_slot == empty_slots[target_bag][1])
                                tremove(empty_slots[target_bag], 1)
                                local space = limit - target_count
                                if space > 0 then
                                    -- If we used an empty slot for this move,
                                    -- there must not have been any partial
                                    -- stacks left in the bank.
                                    assert(#target_slots[id] == 0)
                                    target_slots[id][1] =
                                        {target_bag, target_slot, space}
                                end
                            end
                            if target_count < info.stackCount then
                                -- There's more to deposit next cycle.
                                tinsert(unresolved, source_slots[i])
                            end
                        end
                    end
                else
                    local name = C_Item.GetItemInfo(id)
                    WoWXIV.Error("No space in bank for "..name..".", false)
                    full_items[id] = true
                end
            end
        end
        source_slots = unresolved
        local status = yield(true)
        if status == MenuCursor.MenuFrame.RUNUNDERLOCK_ABORT then
            WoWXIV.Error("Auto-deposit interrupted.")
            return
        elseif status == MenuCursor.MenuFrame.RUNUNDERLOCK_CANCEL then
            -- Rather than waiting for all pending locks to resolve, which
            -- may take a while depending on how many moves are in flight,
            -- we stop immediately and return control to the player.
            WoWXIV.Error("Auto-deposit cancelled.", false)
            return
        end
    end

    print(YELLOW_FONT_COLOR:WrapTextInColorCode("Auto-deposit completed."))
end


---------------------------------------------------------------------------
-- Menu handler for ContainerFrames
---------------------------------------------------------------------------

MenuCursor.ContainerFrameHandler = ContainerFrameHandler  -- For exports.
MenuCursor.Cursor.RegisterFrameHandler(ContainerFrameHandler)

function ContainerFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
    -- Item context menu and associated cursor handler.
    class.item_submenu = InventoryItemSubmenu()
    class.instance_submenu = MenuCursor.ContextMenuHandler(class.item_submenu)
end

function ContainerFrameHandler:__constructor()
    -- In order to implement page swapping across multiple bag frames, we
    -- deliberately pass a nil frame reference to the base constructor and
    -- manage self.frame on our own.
    __super(self, nil)
    self.cursor_show_item = true
    self.cancel_func = self.OnCancel
    self.has_Button4 = true  -- Used to display item operation submenu.
    self.on_prev_page = function() self:CycleBag(-1) end
    self.on_next_page = function() self:CycleBag(1) end

    -- Currently selected item slot's bag and slot index.
    self.current_bag = nil
    self.current_slot = nil

    -- List of all bag-type container frames, in page-cycle order.
    self.bag_frames = {ContainerFrameCombinedBags}
    local i = 1
    local function Container(i) return _G["ContainerFrame"..i] end
    while Container(i) do
        tinsert(self.bag_frames, Container(i))
        i = i+1
    end
    for _, frame in ipairs(self.bag_frames) do
        self:HookShow(frame)
    end

    -- Ordered list of item buttons in the current bag.
    self.items = {}
    -- Used to manage the initial target, see OnShow().
    self.initial_target_pending = false
end

function ContainerFrameHandler:OnCancel()
    if GetCursorInfo() then
        ClearCursor()
    else
        CloseAllBags(nil)
        -- Also close any frames which might have opened bags for us.
        -- Note that we don't have to check for nil (unloaded addons)
        -- because HideUIPanel() is nil-safe.
        HideUIPanel(AuctionHouseFrame)
        HideUIPanel(BankFrame)
        HideUIPanel(ItemInteractionFrame)
        HideUIPanel(ItemUpgradeFrame)
        HideUIPanel(MailFrame)
        HideUIPanel(MerchantFrame)
        HideUIPanel(ScrappingMachineFrame)
    end
end

function ContainerFrameHandler:OnShow(shown_frame)
    -- Typically multiple bags will be shown at once, so rather than
    -- checking/updating the target for each one, we wait a frame until
    -- all relevant bags have (presumably) been shown and set the target
    -- then.
    if not self:GetTarget() then
        if not self.initial_target_pending then
            self.initial_target_pending = true
            RunNextFrame(function()
                self.initial_target_pending = false
                self:SetInitialTarget()
            end)
        end
    else
        -- If we already have a target, opening another bag shouldn't
        -- affect it.
    end
end

function ContainerFrameHandler:SetInitialTarget()
    local Match = ItemButtonUtil.ItemContextMatchResult.Match
    local target, first
    for _, frame in ipairs(self.bag_frames) do
        if frame:IsShown() then
            local items = {}
            for _, item in frame:EnumerateValidItems() do
                items[item:GetID()] = item
            end
            for _, item in ipairs(items) do
                first = first or item
                if item.itemContextMatchResult == Match then
                    target = item
                    break
                end
            end
        end
        if target then break end
    end
    target = target or first
    if not target then return end  -- Maybe bags were instantly closed?
    self.current_bag = target:GetBagID()
    self.current_slot = target:GetID()
    local returned_target, frame = self:SetTargets()
    assert(returned_target == target)
    self.frame = frame
    -- Various UIs automatically open the inventory alongside them,
    -- so don't steal focus from any other frame that's already open,
    -- but leave ourselves as the next frame in the stack in that case.
    local focus = self.cursor:GetFocus()
    self:Enable(target)
    if focus then
        self.cursor:SetFocus(focus)
    end
end

function ContainerFrameHandler:OnHide(frame)
    if frame:GetBagID() == self.current_bag then
        self.current_bag = nil
        for _, f in ipairs(self.bag_frames) do
            if f:IsShown() then
                self.current_bag = f:GetBagID()
                self.current_slot = 1
                break
            end
        end
        if self.current_bag then
            self:SetTarget(nil)
            local target, frame = self:SetTargets()
            self.frame = frame
            self:SetTarget(target)
        else
            self.current_slot = nil
            self:Disable()
        end
    end
end

function ContainerFrameHandler:CycleBag(direction)
    local new_index = 1
    for i, frame in ipairs(self.bag_frames) do
        if frame == self.frame then
            -- Tough decision here: do we cycle in bag order (bottom up)
            -- or natural reading order (top down)?  For now, we'll go
            -- with top down.
            direction = -direction
            new_index = i + direction
            while new_index ~= i do
                if new_index < 1 then new_index = #self.bag_frames end
                if new_index > #self.bag_frames then new_index = 1 end
                if self.bag_frames[new_index]:IsShown() then break end
                new_index = new_index + direction
            end
            break
        end
    end
    local frame = self.bag_frames[new_index]
    self.current_bag = frame:GetBagID()
    self:SetTarget(nil)
    self.frame = frame
    local target, frame_check = self:SetTargets()
    if target then
        assert(frame_check == frame)
    else
        -- The new bag doesn't have as many slots as the previous one.
        -- Select the last slot, but don't update current_slot yet
        -- so we can stay at a later slot while cycling through a
        -- smaller bag.  (We update current_slot in OnMove() and not
        -- EnterTarget() to allow this behavior.)
        target = self.items[#self.items]
    end
    self:SetTarget(target)
end

-- Returns the frame owning the current target as a second return value.
function ContainerFrameHandler:SetTargets()
    self.targets = {}
    self.items = {}
    local cur_target, cur_frame
    for _, frame in ipairs(self.bag_frames) do
        if frame:IsShown() and frame:GetBagID() == self.current_bag then
            for _, item in frame:EnumerateItems() do
                if item:IsExtended() then
                    -- This is for the extra 4 backpack slots which are
                    -- unlocked with 2FA.  We just ignore them if disabled.
                    -- We could also have just used EnumerateValidItems().
                else
                    self.targets[item] = {
                        send_enter_leave = true, lock_highlight = true,
                        on_click = function() self:ClickItem() end}
                    self.items[item:GetID()] = item
                    if item:GetID() == self.current_slot then
                        cur_target = item
                        cur_frame = frame
                    end
                end
            end
            local bag_size = C_Container.GetContainerNumSlots(self.current_bag)
            assert(#self.items == bag_size)
            -- Set directional movement.  We assume a fixed row size of 4.
            local rowlen = 4
            assert(#self.items >= rowlen)
            local top_row_offset = (rowlen - (#self.items % rowlen)) % rowlen
            local bottom_left = #self.items - 3
            local function last_row(i)
                return bottom_left + ((i-1 + top_row_offset) % 4)
            end
            local function first_row(i)
                local col = i - bottom_left
                return 1 + (col + (4 - top_row_offset)) % 4
            end
            for i, item in ipairs(self.items) do
                self.targets[item].up = self.items[i>rowlen and i-rowlen
                                                   or last_row(i)]
                self.targets[item].down = self.items[i<bottom_left and i+rowlen
                                                     or first_row(i)]
                self.targets[item].left = self.items[i==1 and #self.items
                                                     or i-1]
                self.targets[item].right = self.items[i==#self.items and 1
                                                      or i+1]
            end
            break
        end
    end
    return cur_target, cur_frame
end

function ContainerFrameHandler:EnterTarget(target)
    -- Work around item button layout sometimes not completing immediately.
    if target:GetRight() then
        __super(self, target)
    else
        RunNextFrame(function() self:EnterTarget(target) end)
    end
end

function ContainerFrameHandler:GetTargetCursorType(target)
    if SpellIsTargeting() and SpellCanTargetItem() then
        -- Same test as for the "Use as target" submenu item.
        return "cast"
    else
        return "default"
    end
end

function ContainerFrameHandler:OnMove(old_target, new_target)
    local params = self.targets[new_target]
    self.current_slot = new_target:GetID()
end

function ContainerFrameHandler:ClickItem()
    local item = self:GetTarget()
    local bag = item:GetBagID()
    local slot = item:GetID()
    local item_loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local cursor = {GetCursorInfo()}

    if #cursor > 0 then
        -- Apply whatever's on the cursor to this slot.  We rely on the
        -- game to deal with an inappropriate selection (empty slot, etc).
        C_Container.PickupContainerItem(bag, slot)
    elseif not info then
        -- Nothing to see here, move along.
    elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        if C_AuctionHouse.IsSellItemValid(item_loc, false) then
            SendToAuctionHouse(item_loc, info)
        else
            WoWXIV.Error("You can't sell this item.")
        end
    elseif BankFrame and BankFrame:IsShown() then
        SendToBank(bag, slot, info)
    elseif ItemInteractionFrame and ItemInteractionFrame:IsShown() then
        if C_Item.IsItemConvertibleAndValidForPlayer(item_loc) then
            SendToItemInteraction(item_loc, info)
        else
            WoWXIV.Error("Invalid selection.")
        end
    elseif ItemUpgradeFrame and ItemUpgradeFrame:IsShown() then
        if C_ItemUpgrade.CanUpgradeItem(item_loc) then
            SendToItemUpgrade(bag, slot, info)
        else
            WoWXIV.Error("Item cannot be upgraded.")
        end
    elseif MerchantFrame and MerchantFrame:IsShown() then
        -- See notes at InventoryItemSubmenu:ConfigureForItem().
        if C_MerchantFrame.IsSellAllJunkEnabled() then
            SellItem(item, bag, slot, info)
        end
    elseif ScrappingMachineFrame and ScrappingMachineFrame:IsShown() then
        SendToScrapper(bag, slot, info)
    else
        if info.isLocked then
            WoWXIV.Error("Item is locked.")
        end
        C_Container.PickupContainerItem(bag, slot)
    end
end

function ContainerFrameHandler:OnAction(button)
    assert(button == "Button4")
    if InCombatLockdown() then return end
    if GetCursorInfo() then return end
    local item = self:GetTarget()
    local bag, slot = item:GetBagID(), item:GetID()
    self.item_submenu:Open(item, bag, slot)
end


---------------------------------------------------------------------------
-- Item context menu implementation
---------------------------------------------------------------------------

-- Helper function and data for equipping items.
local function DoEquip(bag, bag_slot, equip_loc)
    ClearCursor()
    assert(not GetCursorInfo())
    C_Container.PickupContainerItem(bag, bag_slot)
    assert(GetCursorInfo() == "item")
    PickupInventoryItem(equip_loc)
    ClearCursor()
end
local invtype_loc_map = {
    INVTYPE_HEAD = INVSLOT_HEAD,
    INVTYPE_NECK = INVSLOT_NECK,
    INVTYPE_SHOULDER = INVSLOT_SHOULDER,
    INVTYPE_CLOAK = INVSLOT_BACK,
    INVTYPE_CHEST = INVSLOT_CHEST,
    INVTYPE_ROBE = INVSLOT_CHEST,
    INVTYPE_BODY = INVSLOT_BODY,  -- i.e. shirt
    INVTYPE_TABARD = INVSLOT_TABARD,
    INVTYPE_WRIST = INVSLOT_WRIST,
    INVTYPE_HAND = INVSLOT_HAND,
    INVTYPE_WAIST = INVSLOT_WAIST,
    INVTYPE_LEGS = INVSLOT_LEGS,
    INVTYPE_FEET = INVSLOT_FEET,
    INVTYPE_FINGER = INVSLOT_FINGER1,
    INVTYPE_TRINKET = INVSLOT_TRINKET1,
    INVTYPE_WEAPON = INVSLOT_MAINHAND,
    INVTYPE_SHIELD = INVSLOT_OFFHAND,
    INVTYPE_2HWEAPON = INVSLOT_HEAD,
    INVTYPE_WEAPONMAINHAND = INVSLOT_MAINHAND,
    INVTYPE_WEAPONOFFHAND = INVSLOT_OFFHAND,
    INVTYPE_HOLDABLE = INVSLOT_OFFHAND,
    INVTYPE_THROWN = INVSLOT_MAINHAND,
    INVTYPE_RANGED = INVSLOT_MAINHAND,
}

function InventoryItemSubmenu:__constructor()
    __super(self)

    -- "Open" and "Read" are just aliases for "Use" we use for loot-type
    -- and book-type items.  "Use as target" is likewise an alias we use
    -- if the game cursor has a pending spell.
    self.menuitem_use = self:CreateSecureButton("Use", {type="item"})
    self.menuitem_open = self:CreateSecureButton("Open", {type="item"})
    self.menuitem_read = self:CreateSecureButton("Read", {type="item"})
    self.menuitem_target = self:CreateSecureButton("Use as target",
                                                   {type="item"})

    self.menuitem_equip = self:CreateButton("Equip",
        function(bag, slot, info)
            -- We have two options for directly (i.e., without using cursor
            -- actions) equipping an item: C_Item.EquipItemByName() and
            -- C_Container.UseContainerItem().  The former can choose the
            -- wrong item if multiple copies of the same item are owned
            -- (even if we pass a hyperlink and all copies of the item have
            -- different attributes); the latter is nominally protected,
            -- and while we can in fact successfully call it to equip an
            -- item (at least in 11.2.5), "use" has a different meaning
            -- depending on game context (for example, when at a merchant
            -- it sells the item).  Neither of these is ideal, so we just
            -- make do with the somewhat more verbose and potentially
            -- desyncable cursor method - except for profession tools,
            -- for which it's not worth the effort to find the proper slot
            -- (and ambiguity seems unlikely to come up anyway - it's
            -- mostly an issue with things like Remix where you get gear
            -- items out the wazoo).
            local equip_type = select(9, C_Item.GetItemInfo(info.itemID))
            assert(equip_type and strsub(equip_type,1,8) == "INVTYPE_")
            assert(equip_type ~= "INVTYPE_NON_EQUIP_IGNORE")
            local equip_loc = invtype_loc_map[equip_type]
            if equip_loc then
                DoEquip(bag, slot, equip_loc)
            else
                C_Item.EquipItemByName(info.hyperlink)
            end
        end)
    self.menuitem_equip_ring1 = self:CreateButton("Equip (ring 1)",
        function(bag, slot, info)
            -- See above for why we don't use EquipItemByName().
            DoEquip(bag, slot, INVSLOT_FINGER1)
        end)
    self.menuitem_equip_ring2 = self:CreateButton("Equip (ring 2)",
        function(bag, slot, info)
            DoEquip(bag, slot, INVSLOT_FINGER2)
        end)
    self.menuitem_equip_trinket1 = self:CreateButton("Equip (trinket 1)",
        function(bag, slot, info)
            DoEquip(bag, slot, INVSLOT_TRINKET1)
        end)
    self.menuitem_equip_trinket2 = self:CreateButton("Equip (trinket 2)",
        function(bag, slot, info)
            DoEquip(bag, slot, INVSLOT_TRINKET2)
        end)

    self.menuitem_expand_sockets = self:CreateButton("View sockets",
        function(bag, slot)
            C_Container.SocketContainerItem(bag, slot)
        end)
    -- Legion artifact items also use the SocketContainerItem() API.
    self.menuitem_expand_artifact = self:CreateButton("View artifact",
        function(bag, slot)
            C_Container.SocketContainerItem(bag, slot)
        end)

    self.menuitem_expand_azerite = self:CreateButton("View Azerite powers",
        function(bag, slot, info)
            OpenAzeriteEmpoweredItemUIFromItemLocation(
                ItemLocation:CreateFromBagAndSlot(bag, slot))
        end)

    self.menuitem_expand_azerheart = self:CreateButton("View Azerite essences",
        function(bag, slot, info)
            OpenAzeriteEssenceUIFromItemLocation(
                ItemLocation:CreateFromBagAndSlot(bag, slot))
        end)

    self.menuitem_auction = self:CreateButton("Auction",
        function(bag, slot, info)
            local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
            SendToAuctionHouse(location, info)
        end)

    self.menuitem_sendtobank = self:CreateButton("Send to bank", SendToBank)

    self.menuitem_autodeposit = self:CreateButton("Auto-deposit",
                                                  StartAutoDeposit)

    self.menuitem_sell = self:CreateButton("Sell",
        function(bag, slot, info)
            SellItem(self.item_button, bag, slot, info)
        end)

    self.menuitem_socket = self:CreateButton("Socket", SendToSocket)

    self.menuitem_disenchant = self:CreateSecureButton("Disenchant",
        {type="spell", spell=WoWXIV.SPELL_DISENCHANT})

    self.menuitem_splitstack = self:CreateButton("Split stack",
        function(bag, slot, info, item)
            self:DoSplitStack(bag, slot, info, item)
        end)

    self.menuitem_sort_bag = self:CreateButton("Sort bag",
        function(bag, slot, info)
            self:DoSortBag(bag)
        end)

    self.menuitem_discard = self:CreateButton("Discard",
        function(bag, slot, info)
            self:DoDiscard(bag, slot, info)
        end)
end

function InventoryItemSubmenu:ConfigureForItem(bag, slot)
    local guid =
        C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
    local bagslot = strformat("%d %d", bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local equip_type, _, _, item_class = select(9, C_Item.GetItemInfo(guid))

    if SpellIsTargeting() and SpellCanTargetItem() then
        self:AppendButton(self.menuitem_target)

    elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        local item_loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if C_AuctionHouse.IsSellItemValid(item_loc, false) then
            self:AppendButton(self.menuitem_auction)
        end

    elseif BankFrame and BankFrame:IsShown() then
        self:AppendButton(self.menuitem_sendtobank)
        self:AppendButton(self.menuitem_autodeposit)

    elseif MerchantFrame and MerchantFrame:IsShown() then
        -- We assume this tracks the "does merchant accept selling" state
        -- (e.g. can't sell to delve repair points).
        if C_MerchantFrame.IsSellAllJunkEnabled() then
            self:AppendButton(self.menuitem_sell)
            -- Generally speaking, hasNoValue tracks sellPrice==0 from
            -- C_Item.GetItemInfo() (return index 11), but in a few cases
            -- hasNoValue is used to indicate items which might someday
            -- become sellable but are restricted, like current season
            -- crafting sparks or the BfA corruption cloak Ashjra'kamas.
            self.menuitem_sell:SetEnabled(not info.hasNoValue)
        end

    elseif ItemSocketingFrame and ItemSocketingFrame:IsShown() then
        if item_class == Enum.ItemClass.Gem then
            self:AppendButton(self.menuitem_socket)
        end

    elseif not C_Item.IsEquippableItem(guid) then
        -- Don't show Use/etc for equippable items because the "item"
        -- secure action executes "equip" for those instead.  Also don't
        -- show them while at a special location because those locations
        -- may cause the "default behavior" invoked by those commands to
        -- do something different.
        if info.hasLoot then
            self:AppendButton(self.menuitem_open)
        elseif info.isReadable then
            self:AppendButton(self.menuitem_read)
        else
            local is_usable = (WoWXIV.IsItemUsable(info.itemID)
                               or info.hasLoot
                               or info.isReadable)
            if not is_usable then
                local qi = C_Container.GetContainerItemQuestInfo(bag, slot)
                if qi and qi.questID and not qi.isActive then
                    is_usable = true
                end
            end
            if is_usable then
                self:AppendButton(self.menuitem_use)
            end
        end
    end

    if C_Item.IsEquippableItem(guid) then
        if C_Item.IsCosmeticItem(guid) then
            -- FIXME: the standard "item" action tries to equip this,
            -- which both isn't what we're looking for and doesn't
            -- learn the appearance (caused by a missing IsCosmeticItem
            -- check in SecureTemplates.lua:SECURE_ACTIONS.item, line
            -- 417 in build 11.1.7.61967, reported on 2025-07-30).
            -- These arguably shouldn't be marked as "equippable" in
            -- the first place, but since they are, we have no way to
            -- use them from insecure code and have to rely on mouse
            -- activation.
        elseif equip_type == "INVTYPE_FINGER" then
            self:AppendButton(self.menuitem_equip_ring1)
            self:AppendButton(self.menuitem_equip_ring2)
        elseif equip_type == "INVTYPE_TRINKET" then
            self:AppendButton(self.menuitem_equip_trinket1)
            self:AppendButton(self.menuitem_equip_trinket2)
        else
            self:AppendButton(self.menuitem_equip)
        end
    end

    if C_Item.GetItemNumSockets(info.hyperlink) > 0 then
        self:AppendButton(self.menuitem_expand_sockets)
    elseif info.quality == Enum.ItemQuality.Artifact then
        self:AppendButton(self.menuitem_expand_artifact)
    elseif C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItemByID(info.itemID) then
        self:AppendButton(self.menuitem_expand_azerite)
    else
        local heart_loc = C_AzeriteItem.FindActiveAzeriteItem()
        if heart_loc and heart_loc:IsEqualToBagAndSlot(bag, slot) then
            self:AppendButton(self.menuitem_expand_azerheart)
        end
    end

    if (C_SpellBook.IsSpellKnown(WoWXIV.SPELL_DISENCHANT)
        and C_Spell.IsSpellUsable(WoWXIV.SPELL_DISENCHANT))
    then
        if WoWXIV.IsItemDisenchantable(info.itemID) then
            self:AppendButton(self.menuitem_disenchant)
        end
    end

    if info.stackCount > 1 then
        self:AppendButton(self.menuitem_splitstack)
    end

    self:AppendButton(self.menuitem_sort_bag)

    self:AppendButton(self.menuitem_discard)
end

-------- Individual menu option handlers

function InventoryItemSubmenu:DoSplitStack(bag, slot, info, item_button)
    if info.stackCount <= 1 then return end
    local limit = info.stackCount - 1
    -- Due to a bug in StackSplitFrame, we can't request a limit of 1 (the
    -- frame opens but then closes on the next input without sending a
    -- completion event), so we have to handle that case manually.
    if limit == 1 then
        self:DoSplitStackConfirm(bag, slot, info.hyperlink, 1)
        return
    end
    StackSplitFrame:OpenStackSplitFrame(limit, item_button,
                                        "BOTTOMLEFT", "TOPLEFT")
    -- We have to pass item as the owner to get the frame anchored correctly,
    -- but we want to get the SplitStack callback ourselves.
    StackSplitFrame.owner = {SplitStack = function(_, count)
        self:DoSplitStackConfirm(bag, slot, info.hyperlink, count)
    end}
    MenuCursor.StackSplitFrameEditQuantity()
end

function InventoryItemSubmenu:DoSplitStackConfirm(bag, slot, link, count)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    -- Verify that the slot has the same item we asked the user about,
    -- just in case the inventory changed when we weren't looking.
    if info.hyperlink ~= link then
        WoWXIV.Error("Item could not be found.")
        return
    end
    C_Container.SplitContainerItem(bag, slot, count)
end

function InventoryItemSubmenu:DoSortBag(bag)
    local sorter = WoWXIV.isort_execute(bag)
    ContainerFrameHandler.instance:RunUnderLock(function()
        while not sorter:Run() do
            local status = yield(true)
            if status == MenuCursor.MenuFrame.RUNUNDERLOCK_ABORT then
                WoWXIV.Error("Bag sort interrupted.")
                return
            elseif status == MenuCursor.MenuFrame.RUNUNDERLOCK_CANCEL then
                WoWXIV.Error("Bag sort cancelled.", false)
                sorter:Abort()
            end
        end
    end)
end

function InventoryItemSubmenu:DoDiscard(bag, slot, info)
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

function InventoryItemSubmenu:DoDiscardConfirm(bag, slot, link)
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


---------------------------------------------------------------------------
-- Exported functions
---------------------------------------------------------------------------

-- Give input focus to ContainerFrameHandler if any container is open.
function ContainerFrameHandler.FocusIfOpen()
    local instance = ContainerFrameHandler.instance
    if instance:IsEnabled() then
        instance:Focus()
    end
end
