local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

assert(UI.ContextMenu)  -- Ensure proper load order.

UI.ItemSubmenu = class(UI.ContextMenu)
UI.ItemSubmenuButton = class(UI.ContextMenuButton)
local ItemSubmenu = UI.ItemSubmenu
local ItemSubmenuButton = UI.ItemSubmenuButton

---------------------------------------------------------------------------

-- Takes both the button itself and the bag/slot location parameters to
-- avoid having to worry about different styles of item button (e.g.
-- standard bags vs account bank).
function ItemSubmenu:Open(item_button, bag, slot, ...)
    self.item_button, self.bag, self.slot = item_button, bag, slot
    local item_loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not item_loc:IsValid() then  -- nothing there!
        self.bag, self.slot = nil, nil
        return
    end
    return __super(self, item_button, bag, slot, ...)
end

function ItemSubmenu:AppendButton(button)
    __super(self, button)
    button:SetItem(self.item_button, self.bag, self.slot)
end

function ItemSubmenu:Configure(button, ...)
    self:ConfigureForItem(...)
end

-- Should be implemented by subclasses.  Call self:AppendButton() (or
-- self:AppendLayout()) for each desired element in the menu.  Receives
-- bag/slot and all arguments after "slot" passed to ItemSubmenu:Open().
function ItemSubmenu:ConfigureForItem(bag, slot, ...)
end

-- Override these to create ItemSubmenuButtons instead of ContextMenuButtons.
function ItemSubmenu:CreateButton(text, ExecuteInsecure)
    local button = ItemSubmenuButton(self, text, false)
    if ExecuteInsecure then
        button.ExecuteInsecure = ExecuteInsecure
    end
    return button
end
function ItemSubmenu:CreateSecureButton(text, attributes)
    local button = ItemSubmenuButton(self, text, true)
    for attrib, value in pairs(attributes or {}) do
        button:SetAttribute(attrib, value)
    end
    return button
end

---------------------------------------------------------------------------

-- Called by ItemSubmenu to set the target item's location.
function ItemSubmenuButton:SetItem(item_button, bag, slot)
    self.item_button, self.bag, self.slot = item_button, bag, slot
    self.item_id = C_Item.GetItemID(
        ItemLocation:CreateFromBagAndSlot(bag, slot))
    self:SetAttribute("item", bag.." "..slot)
    self:SetAttribute("target-bag", bag)
    self:SetAttribute("target-slot", slot)
end

function ItemSubmenuButton:OnClick()
    local bag, slot = self.bag, self.slot
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
    -- like-for-like substitutions to avoid potentially confusing the
    -- player with errors like "found Foo instead of Foo".
    self.ExecuteInsecure(bag, slot, info, self.item_button)
end

-- Insecure menu options should override this function to implement their
-- behavior.  The target item location is passed, along with its container
-- info as obtained from C_Container.GetContainerItemInfo() and the owning
-- item button (UI element).  The function is not called if the slot is
-- empty or holds a different item than when SetItem() was called, as can
-- occur if a time-limited item expires.  Note that this is a simple
-- function, not an instance method!
function ItemSubmenuButton.ExecuteInsecure(bag, slot, info, item_button)
end
