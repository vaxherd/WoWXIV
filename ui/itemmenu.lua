local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

UI.ItemSubmenu = class(Frame)
UI.ItemSubmenuButton = class(Button)
local ItemSubmenu = UI.ItemSubmenu
local ItemSubmenuButton = UI.ItemSubmenuButton

---------------------------------------------------------------------------

function ItemSubmenu:__allocator()
    return Frame.__allocator("Frame", nil, UIParent)
end

function ItemSubmenu:__constructor()
    self.BORDER = 4  -- Inset from frame edge to menu items.
    self.MIN_EDGE = 4  -- Don't get closer than this to the screen edge.
    self.buttons = {}  -- List of buttons currently shown in the layout.

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

-- Takes both the button itself and the bag/slot location parameters to
-- avoid having to worry about different styles of item button (e.g.
-- standard bags vs account bank).
function ItemSubmenu:Open(item_button, bag, slot, ...)
    if self:IsShown() then
        self:Close()
    end

    self.item_button, self.bag, self.slot = item_button, bag, slot
    local item_loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not item_loc:IsValid() then  -- nothing there!
        self.bag, self.slot = nil, nil
        return
    end

    self:ClearLayout()
    self:ConfigureForItem(bag, slot, ...)
    self:FinishLayout()

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
    self.bag, self.slot = nil, nil
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
    button:SetItem(self.item_button, self.bag, self.slot)
    button:Show()
end

function ItemSubmenu:FinishLayout()
    self:SetSize(self.layout_width + 2*self.BORDER,
                 self.layout_height + 2*self.BORDER)
    self.layout_prev = nil
end

-- Should be implemented by subclasses.  Call self:AppendButton() (or
-- self:AppendLayout()) for each desired element in the menu.  Receives
-- bag/slot and all arguments after "slot" passed to ItemSubmenu:Open().
function ItemSubmenu:ConfigureForItem(bag, slot, ...)
end  

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
    self.label:SetTextColor(
        (enabled and WHITE_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
end
-- Ensure all enable changes go through SetEnabled() to update the text color.
function ItemSubmenu:Enable() self:SetEnabled(true) end
function ItemSubmenu:Disable() self:SetEnabled(false) end

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
    -- like-for-like substitutions to avoid potentially confusing error
    -- messages.
    self.ExecuteInsecure(bag, slot, info, self.item_button)
end

-- Called by ItemSubmenu to set the target item's location.
function ItemSubmenuButton:SetItem(item_button, bag, slot)
    self.item_button, self.bag, self.slot = item_button, bag, slot
    self.item_id = C_Item.GetItemID(
        ItemLocation:CreateFromBagAndSlot(bag, slot))
    self:SetAttribute("item", bag.." "..slot)
    self:SetAttribute("target-bag", bag)
    self:SetAttribute("target-slot", slot)
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
