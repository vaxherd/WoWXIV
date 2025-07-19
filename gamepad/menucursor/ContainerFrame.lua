local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

local strformat = string.format
local strsub = string.sub
local tinsert = tinsert
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
-- not visible, it will be imminently Show()n and the manu handler will
-- focus it at that point.)
local function SendToAuctionHouse(item_loc)
    AuctionHouseFrame:SetPostItem(item_loc)
    MenuCursor.AuctionHouseFrameHandler.FocusSellFrame()
end

-- Send an item to the currently active bank frame.  May start a locked
-- sequence in order to split the source stack among multiple bank slots.
local SendToBankInternal  -- Forward declaration.
local function SendToBank(bag, slot, info)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    ContainerFrameHandler.instance:RunUnderLock(
        SendToBankInternal, bag, slot, info)
end
function SendToBankInternal(bag, slot, info)
    ClearCursor()
    assert(not GetCursorInfo())
    local limit = select(8, C_Item.GetItemInfo("item:"..info.itemID)) or 0
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
    if BankSlotsFrame:IsVisible() then
        for i = 0, 7 do
            local bag_id =
                i==0 and Enum.BagIndex.Bank or (Enum.BagIndex.BankBag_1 + (i-1))
            target_bag, target_slot, target_count = SearchBag(bag_id)
            if target_bag then break end
            if not empty_bag and target_slot then
                empty_bag, empty_slot = bag_id, target_slot
            end
        end
    elseif ReagentBankFrame:IsVisible() then
        if not WoWXIV.IsItemReagent(info.itemID) then
            WoWXIV.Error("That item doesn't go in that container.")
            return
        end
        local bag_id = Enum.BagIndex.Reagentbank
        target_bag, target_slot, target_count = SearchBag(bag_id)
        if not target_bag and target_slot then
            empty_bag, empty_slot = bag_id, target_slot
        end
    else
        assert(AccountBankPanel:IsVisible())
        for i = 1, 5 do
            local bag_id = Enum.BagIndex.AccountBankTab_1 + (i-1)
            target_bag, target_slot, target_count = SearchBag(bag_id)
            if target_bag then break end
            -- Standard game behavior is to take the first empty slot in
            -- the numerically first tab, but we choose to prioritize an
            -- empty slot in the currently displayed tab as better UX.
            if (not empty_bag
                or (bag_id == AccountBankPanel.selectedTabID
                    and empty_bag ~= bag_id))
            and target_slot then
                empty_bag, empty_slot = bag_id, target_slot
            end
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
        while info.isLocked do
            if not yield(true) then
                WoWXIV.Error("Item transfer interrupted.")
                return
            end
            info = C_Container.GetContainerItemInfo(bag, slot)
        end
        if C_Item.GetItemGUID(item_loc) ~= guid then
            WoWXIV.Error("Item transfer interrupted due to inventory change.")
            return
        end
        return SendToBankInternal(bag, slot, info)
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

-- Send an item to the BfA scrapping machine.
local function SendToScrapper(bag, slot, info)
    ClearCursor()
    assert(not GetCursorInfo())
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    local scrap_slot
    for i = 0, 8 do
        if not C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(i) then  -- whew, that's a mouthful
            scrap_slot = i
            break
        end
    end
    if not scrap_slot then
        WoWXIV.Error("The scrapper is full.")
        return
    end
    C_Container.PickupContainerItem(bag, slot)
    local cursor_type, _, cursor_link = GetCursorInfo()
    assert(cursor_type == "item" and cursor_link == info.hyperlink)
    C_ScrappingMachineUI.DropPendingScrapItemFromCursor(scrap_slot)
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


---------------------------------------------------------------------------
-- Menu handler for ContainerFrames
---------------------------------------------------------------------------

MenuCursor.ContainerFrameHandler = ContainerFrameHandler  -- For exports.
MenuCursor.Cursor.RegisterFrameHandler(ContainerFrameHandler)
local InventoryItemSubmenuHandler = class(MenuCursor.StandardMenuFrame)

function ContainerFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
    -- Item submenu dropdown and associated cursor handler.
    class.item_submenu = InventoryItemSubmenu()
    class.instance_submenu = InventoryItemSubmenuHandler(class.item_submenu)
end

function ContainerFrameHandler:__constructor()
    -- In order to implement page swapping across multiple bag frames, we
    -- deliberately pass a nil frame reference to the base constructor and
    -- manage self.frame on our own.
    self:__super(nil)
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
    local cur_target = self:GetTarget()
    if not cur_target then
        self.current_bag = shown_frame:GetBagID()
        self.current_slot = 1
        local target, frame = self:SetTargets()
        self.frame = frame
        -- Various UIs automatically open the inventory alongside them,
        -- so don't steal focus from any other frame that's already open.
        if self.cursor:GetFocus() then
            self:EnableBackground(target)
        else
            self:Enable(target)
        end
    else
        local target, frame = self:SetTargets()
        assert(target == cur_target)
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
        MenuCursor.MenuFrame.EnterTarget(self, target)
    else
        RunNextFrame(function() self:EnterTarget(target) end)
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

    if GetCursorInfo() then
        -- We prioritize this over checking info.isLocked because we might
        -- be putting an item back where we picked it up, in which case
        -- the slot will be locked but this call will still succeed.
        -- There doesn't seem to be any way to determine the location of
        -- the held item, so we rely on the game itself to handle errors
        -- in this case.
        C_Container.PickupContainerItem(bag, slot)
    elseif not info then
        return  -- Slot is empty.
    elseif info.isLocked then
        WoWXIV.Error("Item is locked.")
    elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        if C_AuctionHouse.IsSellItemValid(item_loc, false) then
            SendToAuctionHouse(item_loc)
        else
            WoWXIV.Error("You can't sell this item.")
        end
    elseif BankFrame and BankFrame:IsShown() then
        -- The mouse default is SendToBank, but that's a bit awkward
        -- when extended bank bags appear as ContainerFrames.
        -- Stick with PickupContainerItem for now, and revisit if
        -- the character bank interface is ever changed to match the
        -- new (tabbed) account bank UI.
        --SendToBank(bag, slot, info)
        C_Container.PickupContainerItem(bag, slot)
    elseif ItemInteractionFrame and ItemInteractionFrame:IsShown() then
        if C_Item.IsItemConvertibleAndValidForPlayer(item_loc) then
            C_ItemInteraction.SetPendingItem(item_loc)
            MenuCursor.ItemInteractionFrameHandler.FocusActionButton()
        else
            WoWXIV.Error("Invalid selection.")
        end
    elseif ItemUpgradeFrame and ItemUpgradeFrame:IsShown() then
        if C_ItemUpgrade.CanUpgradeItem(item_loc) then
            C_Container.PickupContainerItem(bag, slot)
            C_ItemUpgrade.SetItemUpgradeFromCursorItem()
            MenuCursor.ItemUpgradeFrameHandler.FocusUpgradeButton()
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
        C_Container.PickupContainerItem(bag, slot)
    end
end

function ContainerFrameHandler:OnAction(button)
    assert(button == "Button4")
    if InCombatLockdown() then return end
    if GetCursorInfo() then return end
    local item = self:GetTarget()
    local bag, slot = item:GetBagID(), item:GetID()
    if bag >= Enum.BagIndex.BankBag_1 then
        MenuCursor.BankFrameHandler.OpenBankItemSubmenu(item, bag, slot)
    else
        self.item_submenu:Open(item, bag, slot)
    end
end


---------------------------------------------------------------------------
-- Item submenu handler and implementation
---------------------------------------------------------------------------

function InventoryItemSubmenuHandler:__constructor(submenu)
    self:__super(submenu, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = function(self) self.frame:Close() end
end

function InventoryItemSubmenuHandler:SetTargets()
    self.targets = {}
    local initial
    for _, button in ipairs(self.frame.buttons) do
        self.targets[button] = {can_activate = true}
        initial = initial or button
    end
    return initial
end


function InventoryItemSubmenu:__constructor()
    self:__super()

    -- FIXME: "Use" for spell-type items (e.g. Hearthstone) and "Disenchant"
    -- currently fail due to taint errors when activated via menu cursor.
    -- They work fine via physical mouse click, so hopefully not an
    -- unresolvable problem?

    -- Note that both of these are the same action because "item" resolves
    -- to either "equip" or "use" based on C_Item.IsEquippableItem() (see
    -- SECURE_ACTIONS.item in SecureTemplates.lua), which is the same test
    -- we use for showing the "Equip" menu item in place of "Use".  "Open"
    -- and "Read" are just aliases for "Use" we use for loot-type and
    -- book-type items.
    self.menuitem_equip =
        WoWXIV.UI.ItemSubmenuButton(self, "Equip", true)
    self.menuitem_equip:SetAttribute("type", "item")
    self.menuitem_use =
        WoWXIV.UI.ItemSubmenuButton(self, "Use", true)
    self.menuitem_use:SetAttribute("type", "item")
    self.menuitem_open =
        WoWXIV.UI.ItemSubmenuButton(self, "Open", true)
    self.menuitem_open:SetAttribute("type", "item")
    self.menuitem_read =
        WoWXIV.UI.ItemSubmenuButton(self, "Read", true)
    self.menuitem_read:SetAttribute("type", "item")

    self.menuitem_auction =
        WoWXIV.UI.ItemSubmenuButton(self, "Auction", false)
    self.menuitem_auction.ExecuteInsecure =
        function(bag, slot, info)
            SendToAuctionHouse(ItemLocation:CreateFromBagAndSlot(bag, slot))
        end

    self.menuitem_sendtobank =
        WoWXIV.UI.ItemSubmenuButton(self, "Send to bank", false)
    self.menuitem_sendtobank.ExecuteInsecure =
        function(bag, slot, info) SendToBank(bag, slot, info) end

    self.menuitem_sell =
        WoWXIV.UI.ItemSubmenuButton(self, "Sell", false)
    self.menuitem_sell.ExecuteInsecure =
        function(bag, slot, info)
            SellItem(self.item_button, bag, slot, info)
        end

    self.menuitem_socket =
        WoWXIV.UI.ItemSubmenuButton(self, "Socket", false)
    self.menuitem_socket.ExecuteInsecure =
        function(bag, slot, info) SendToSocket(bag, slot, info) end

    self.menuitem_disenchant =
        WoWXIV.UI.ItemSubmenuButton(self, "Disenchant", true)
    self.menuitem_disenchant:SetAttribute("type", "spell")
    self.menuitem_disenchant:SetAttribute("spell", 13262)

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

function InventoryItemSubmenu:ConfigureForItem(bag, slot)
    local guid =
        C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
    local bagslot = strformat("%d %d", bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local class = select(12, C_Item.GetItemInfo(guid))

    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        if C_AuctionHouse.IsSellItemValid(self.item_loc, false) then
            self:AppendButton(self.menuitem_auction)
        end

    elseif BankFrame and BankFrame:IsShown() then
        self:AppendButton(self.menuitem_sendtobank)

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
        if class == Enum.ItemClass.Gem then
            self:AppendButton(self.menuitem_socket)
        end

    else
        -- Don't show Equip/Use while at a special location because those
        -- may cause the "default behavior" invoked by those commands to
        -- do something different.
        if C_Item.IsEquippableItem(guid) then
            self:AppendButton(self.menuitem_equip)
        elseif info.hasLoot then
            self:AppendButton(self.menuitem_open)
        elseif info.isReadable then
            self:AppendButton(self.menuitem_read)
        elseif C_Item.IsUsableItem(guid) or info.hasLoot or info.isReadable then
            self:AppendButton(self.menuitem_use)
        end
    end

    if class == Enum.ItemClass.Weapon
    or class == Enum.ItemClass.Armor
    or class == Enum.ItemClass.Profession
    then
        local prof1, prof2 = GetProfessions()
        local TEXTURE_ENCHANTING = 4620672
        if (prof1 and select(2, GetProfessionInfo(prof1)) == TEXTURE_ENCHANTING)
        or (prof2 and select(2, GetProfessionInfo(prof2)) == TEXTURE_ENCHANTING)
        then
            self:AppendButton(self.menuitem_disenchant)
        end
    end

    if info.stackCount > 1 then
        self:AppendButton(self.menuitem_splitstack)
    end

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

function InventoryItemSubmenu:DoDiscard(bag, slot, info)
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
