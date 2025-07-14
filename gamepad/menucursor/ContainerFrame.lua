local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

local max = math.max
local strformat = string.format
local strsub = string.sub
local tinsert = tinsert

-- This is named like a global function but turns out to be local...
local function ContainerFrame_IsHeldBag(id)
    local NUM_TOTAL_BAG_FRAMES = Constants.InventoryConstants.NumBagSlots + Constants.InventoryConstants.NumReagentBagSlots  -- Also only defined locally.
    return id >= Enum.BagIndex.Backpack and id <= NUM_TOTAL_BAG_FRAMES
end

-- Class implementing the item submenu.  We roll our own rather than using
-- the standard DropdownMenuButton so we can include secure buttons to
-- perform use/disenchant/etc actions.
local ItemSubmenu = class(Frame)

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

---------------------------------------------------------------------------
-- Menu handler for ContainerFrames
---------------------------------------------------------------------------

local ContainerFrameHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(ContainerFrameHandler)
local ItemSubmenuHandler = class(MenuCursor.StandardMenuFrame)

function ContainerFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
    -- Item submenu dropdown and associated cursor handler.
    class.item_submenu = ItemSubmenu()
    class.instance_submenu = ItemSubmenuHandler(class.item_submenu)
end

function ContainerFrameHandler:__constructor()
    -- In order to implement cursor movement across multiple bag frames,
    -- we deliberately pass a nil frame reference to the base constructor
    -- and manage self.frame on our own.
    self:__super(nil)
    self.cancel_func = function() CloseAllBags(nil) end
    self.has_Button4 = true  -- Used to display item operation submenu.

    -- Currently selected item slot's bag and slot index.
    self.current_bag = nil
    self.current_slot = nil

    -- List of all bag-type container frames.
    self.bag_frames = {ContainerFrameCombinedBags}
    local i = 1
    local function Container(i) return _G["ContainerFrame"..i] end
    while Container(i) and ContainerFrame_IsHeldBag(Container(i):GetBagID()) do
        tinsert(self.bag_frames, Container(i))
        i = i+1
    end
    for _, frame in ipairs(self.bag_frames) do
        self:HookShow(frame)
    end
end

function ContainerFrameHandler:OnShow(frame)
    local cur_target = self:GetTarget()
    if not cur_target then
        self.current_bag = frame:GetBagID()
        self.current_slot = 1
        local target, frame = self:SetTargets()
        self.frame = frame
        -- Various UIs automatically open the inventory alongside them,
        -- so don't steal focus from any other frame that's already open.
        --self:EnableBackground(target)
        self:Enable(target) --FIXME temp
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
        if not self.current_bag then
            self.current_slot = nil
            self:Disable()
        end
    end
end

-- Returns the frame owning the current target as a second return value.
function ContainerFrameHandler:SetTargets()
    self.targets = {}
    local cur_target, cur_frame
    for _, frame in ipairs(self.bag_frames) do
        for _, item in frame:EnumerateItems() do
            self.targets[item] = {frame = frame, send_enter_leave = true,
                                  on_click = function() self:ClickItem() end}
            if item:GetBagID() == self.current_bag and item:GetID() == self.current_slot then
                cur_target = item
                cur_frame = frame
            end
        end
    end
    return cur_target, cur_frame
end

function ContainerFrameHandler:EnterTarget(target)
    local params = self.targets[target]
    self.frame = params.frame
    self.current_bag = target:GetBagID()
    self.current_slot = target:GetID()
    -- Work around item button layout sometimes not completing immediately.
    if target:GetRight() then
        MenuCursor.MenuFrame.EnterTarget(self, target)
    else
        RunNextFrame(function() self:EnterTarget(target) end)
    end
end

function ContainerFrameHandler:ClickItem()
    local item = self:GetTarget()
    local bag = item:GetBagID()
    local slot = item:GetID()
    local item_loc = ItemLocation:CreateFromBagAndSlot(bag, slot)

    if AuctionHouseFrame:IsShown() then
        if C_AuctionHouse.IsSellItemValid(item_loc, false) then
            SendToAuctionHouse(item_loc)
        end
    end
end

function ContainerFrameHandler:OnAction(button)
    assert(button == "Button4")
    if InCombatLockdown() then return end
    local item = self:GetTarget()
    self.item_submenu:Open(item)
end


function ItemSubmenuHandler:__constructor(submenu)
    self:__super(submenu, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = function(self) self.frame:Close() end
end

function ItemSubmenuHandler:SetTargets()
    self.targets = {}
    local initial
    for _, button in ipairs(self.frame.buttons) do
        self.targets[button] = {can_activate = true}
        initial = initial or button
    end
    return initial
end


---------------------------------------------------------------------------
-- Item submenu implementation
---------------------------------------------------------------------------

local ItemSubmenuButton = class(Button)


function ItemSubmenu:__allocator()
    return Frame.__allocator("Frame", "WoWXIV_ItemSubmenu", UIParent)
end

function ItemSubmenu:__constructor()
    self.BORDER = 4  -- Inset from frame edge to menu items.
    self.MIN_EDGE = 4  -- Don't get closer than this to the screen edge.
    self.buttons = {}  -- List of buttons currently shown in the layout.

    -- FIXME: "Use" for spell-type items (e.g. Hearthstone) and "Disenchant"
    -- currently fail due to taint errors when activated via menu cursor.
    -- They work fine via physical mouse click, so hopefully not an
    -- unresolvable problem?

    -- Note that both of these are the same action because "item" resolves
    -- to either "equip" or "use" based on C_Item.IsEquippableItem() (see
    -- SECURE_ACTIONS.item in SecureTemplates.lua), which is the same test
    -- we use for showing the "Equip" menu item in place of "Use".
    self.menuitem_equip = ItemSubmenuButton(self, "Equip", true)
    self.menuitem_equip:SetAttribute("type", "item")
    self.menuitem_use = ItemSubmenuButton(self, "Use", true)
    self.menuitem_use:SetAttribute("type", "item")

    self.menuitem_auction = ItemSubmenuButton(self, "Auction", false)
    self.menuitem_auction.ExecuteInsecure =
        function(item, info) self:DoAuction(item, info) end

    self.menuitem_disenchant = ItemSubmenuButton(self, "Disenchant", true)
    self.menuitem_disenchant:SetAttribute("type", "spell")
    self.menuitem_disenchant:SetAttribute("spell", 13262)

    self.menuitem_splitstack = ItemSubmenuButton(self, "Split stack", false)
    self.menuitem_splitstack.ExecuteInsecure =
        function(item, info) self:DoSplitStack(item, info) end

    self.menuitem_discard = ItemSubmenuButton(self, "Discard", false)
    self.menuitem_discard.ExecuteInsecure =
        function(item, info) self:DoDiscard(item, info) end

    self:Hide()
    self:SetFrameStrata("DIALOG")
    self:SetScript("OnHide", self.OnHide)
    -- Immediately close the submenu on any mouse click, to reduce the
    -- risk of colliding inventory operations.
    self:RegisterEvent("GLOBAL_MOUSE_UP")
    self:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_UP" and self:IsShown() then self:Hide() end
    end)

    self.background = self:CreateTexture(nil, "BACKGROUND")
    self.background:SetAllPoints()
    self.background:SetColorTexture(0, 0, 0)
end

function ItemSubmenu:Open(item_button)
    if self:IsShown() then
        self:Close()
    end

    self.item = item_button
    self.item_loc = ItemLocation:CreateFromBagAndSlot(
        item_button:GetBagID(), item_button:GetID())
    if not self.item_loc:IsValid() then  -- nothing there!
        self.item = nil
        self.item_loc = nil
        return
    end

    self:ConfigureForItem()

    self:ClearAllPoints()
    local w, h = self:GetSize()
    local ix, iy, iw, ih = item_button:GetRect()
    local anchor, refpoint
    if (ix+iw) + w + self.MIN_EDGE <= UIParent:GetWidth() then
        anchor = "TOPLEFT"
        refpoint = "BOTTOMRIGHT"
    else
        -- Doesn't fit on the right side, move to the left.
        anchor = "TOPRIGHT"
        refpoint = "BOTTOMLEFT"
    end
    local y_offset = max((h + self.MIN_EDGE) - iy, 0)
    self:SetPoint(anchor, item_button, refpoint, 0, y_offset)
    self:Show()
end

-- Just a synonym for Hide().  Included for parallelism with Open().
function ItemSubmenu:Close()
    self:Hide()
end

function ItemSubmenu:OnHide()
    for _, button in ipairs(self.buttons) do
        button:Hide()
    end
    self.buttons = {}
    self.item = nil
    self.item_loc = nil
end

function ItemSubmenu:ConfigureForItem()
    self:ClearLayout()
    local prev_element = self.top_border

    local guid = C_Item.GetItemGUID(self.item_loc)
    local bag, slot = self.item_loc:GetBagAndSlot()
    local bagslot = strformat("%d %d", bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local class = select(12, C_Item.GetItemInfo(guid))

    if C_Item.IsEquippableItem(guid) then
        self:AppendButton(self.menuitem_equip)
    elseif C_Item.IsUsableItem(guid) or info.hasLoot or info.isReadable then
        self:AppendButton(self.menuitem_use)
    end

    if AuctionHouseFrame:IsShown() then
        if C_AuctionHouse.IsSellItemValid(self.item_loc, false) then
            self:AppendButton(self.menuitem_auction)
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

    self:FinishLayout()
end  

function ItemSubmenu:ClearLayout()
    self.layout_prev = nil
    self.layout_width = 64  -- Set a sensible minimum width.
    self.layout_height = 0
    self.buttons = {}
end

function ItemSubmenu:AppendLayout(element)
    local target, ref, offset
    if self.layout_prev then
        target = self.layout_prev
        ref = "BOTTOM"
        offset = 0
    else
        target = self
        ref = "TOP"
        offset = self.BORDER
    end
    element:ClearAllPoints()
    element:SetPoint("TOPLEFT", target, ref.."LEFT", offset, -offset)
    self.layout_width = max(self.layout_width, element:GetWidth())
    self.layout_height = self.layout_height + element:GetHeight()
    self.layout_prev = element
end

function ItemSubmenu:AppendButton(button)
    self:AppendLayout(button)
    tinsert(self.buttons, button)
    button:SetItem(self.item)
    button:Show()
end

function ItemSubmenu:FinishLayout()
    self:SetSize(self.layout_width + 2*self.BORDER,
                 self.layout_height + 2*self.BORDER)
    self.layout_prev = nil
end


-------- Individual menu option handlers

function ItemSubmenu:DoAuction(item, info)
    local bag = item:GetBagID()
    local slot = item:GetID()
    SendToAuctionHouse(ItemLocation:CreateFromBagAndSlot(bag, slot))
end

function ItemSubmenu:DoSplitStack(item, info)
    local bag = item:GetBagID()
    local slot = item:GetID()
    if info.stackCount <= 1 then return end
    local limit = info.stackCount - 1
    StackSplitFrame:OpenStackSplitFrame(limit, item, "BOTTOMLEFT", "TOPLEFT")
    -- We have to pass item as the owner to get the frame anchored correctly,
    -- but we want to get the SplitStack callback ourselves.
    StackSplitFrame.owner = {SplitStack = function(_, count)
        self:DoSplitStackConfirm(bag, slot, info.hyperlink, count)
    end}
    MenuCursor.StackSplitFrameEditQuantity()
end

function ItemSubmenu:DoSplitStackConfirm(bag, slot, link, count)
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
    -- Find an empty slot for the new stack.  We prefer a slot in the same
    -- bag even if it's the wrong bag for the item type.
    local target_bag, target_slot
    local class, subclass =
        select(12, C_Item.GetItemInfo(strformat("item:%d", info.itemID)))
    local function FindSlot(bag_id)
        for i = 1, C_Container.GetContainerNumSlots(bag_id) do
            if not C_Container.GetContainerItemInfo(bag_id, i) then
                target_bag = bag_id
                target_slot = i
                return true
            end
        end
    end
    FindSlot(bag)
    if not target_bag and class == Enum.ItemClass.Tradegoods then
        for i = 1, Constants.InventoryConstants.NumReagentBagSlots do
            local reagent_bag = Constants.InventoryConstants.NumBagSlots + i
            if FindSlot(reagent_bag) then
                break
            end
        end
    end
    if not target_bag then
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
        elseif class == Enum.ItemClass.Profession then
            type_flag = Enum.BagSlotFlags.ClassProfessionGoods
        end
        if type_flag then
            for i = 1, Constants.InventoryConstants.NumBagSlots do
                if C_Container.GetBagSlotFlag(i, type_flag) then
                    if FindSlot(i) then
                        break
                    end
                end
            end
        end
    end
    if not target_bag then
        for i = 1, Constants.InventoryConstants.NumBagSlots do
            if FindSlot(i) then
                break
            end
        end
    end
    if not target_bag then
        WoWXIV.Error("No free inventory slots for new stack.")
        return
    end
    C_Container.SplitContainerItem(bag, slot, count)
    C_Container.PickupContainerItem(target_bag, target_slot)
end

function ItemSubmenu:DoDiscard(item, info)
    local bag = item:GetBagID()
    local slot = item:GetID()
    local class =
        select(12, C_Item.GetItemInfo(strformat("item:%d", info.itemID)))
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

function ItemSubmenu:DoDiscardConfirm(bag, slot, link)
    ClearCursor()
    assert(not GetCursorInfo())
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info.isLocked then
        WoWXIV.Error("Item is locked.")
        return
    end
    C_Container.PickupContainerItem(bag, slot)
    -- Verify that we picked up the same item we asked the user about,
    -- just in case the inventory changed when we weren't looking.
    local cursor_type, _, cursor_link = GetCursorInfo()
    if not (cursor_type == "item" and cursor_link == link) then
        WoWXIV.Error("Item could not be found.")
        ClearCursor()
        return
    end
    DeleteCursorItem()
end


---------------------------------------------------------------------------
-- Item submenu menu item (button) implementation
---------------------------------------------------------------------------

function ItemSubmenuButton:__allocator(parent, text, secure)
    if secure then
        return Button.__allocator("Button", nil, parent,
                                  "SecureActionButtonTemplate")
    else
        return Button.__allocator("Button", nil, parent)
    end
end

function ItemSubmenuButton:__constructor(parent, text, secure)
    self:Hide()
    local label = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label = label
    label:SetPoint("CENTER")
    label:SetTextColor(WHITE_FONT_COLOR:GetRGB())
    label:SetTextScale(1.0)
    label:SetText(text)
    self:SetSize(label:GetStringWidth()+4, label:GetStringHeight()+2)
    self:RegisterForClicks("LeftButtonUp")
    self:SetAttribute("useOnKeyDown", false)  -- Indirect clicks are always up.
    self:HookScript("PostClick", function() parent:Hide() end)
    if not secure then
        self:SetScript("OnClick", self.OnClick)
    end
end

function ItemSubmenuButton:SetEnabled(enabled)
    Button.SetEnabled(self, enabled)
    label:SetTextColor(
        (enabled and WHITE_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
end
-- Ensure all enable changes go through SetEnabled() to update the text color.
function ItemSubmenu:Enable() self:SetEnabled(true) end
function ItemSubmenu:Disable() self:SetEnabled(false) end

function ItemSubmenuButton:OnClick()
    assert(self.item)
    local bag = self.item:GetBagID()
    local slot = self.item:GetID()
    local info = C_Container.GetContainerItemInfo(bag, slot)
    -- If the item expired or was otherwise consumed or moved, we could
    -- see one of two things:
    -- (1) The slot is now empty.
    if not info then return end
    -- (2) The slot now holds a different item (item granted by the
    -- expiring item, loot that randomly dropped into the same slot, etc).
    if info.itemID ~= self.item_id then return end
    -- If we get here, the slot has the same item as it originally did.
    -- It may not be the same specific instance (GUID), but we accept
    -- like-for-like substitutions to avoid potentially confusing error
    -- messages.
    self.ExecuteInsecure(self.item, info)
end

-- Called by ItemSubmenu to set the target item.
function ItemSubmenuButton:SetItem(item)
    self.item = item
    local bag = item:GetBagID()
    local slot = item:GetID()
    self.item_id = C_Item.GetItemID(
        ItemLocation:CreateFromBagAndSlot(bag, slot))
    self:SetAttribute("item", bag.." "..slot)
    self:SetAttribute("target-bag", bag)
    self:SetAttribute("target-slot", slot)
end

-- Insecure menu options should override this function to implement their
-- behavior.  The target item button is passed, along with its container
-- info as obtained from C_Container.GetContainerItemInfo().  The function
-- is not called if the slot is empty or holds a different item than when
-- SetItem() was called, as can occur if a time-limited item expires.
-- Note that this is a simple function, not an instance method!
function ItemSubmenuButton.ExecuteInsecure(item, info)
end
