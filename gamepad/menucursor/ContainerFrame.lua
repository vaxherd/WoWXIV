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
            self.targets[item] = {frame = frame, send_enter_leave = true}
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
print("delaying enter") --FIXME temp
        RunNextFrame(function() self:EnterTarget(target) end)
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

local ItemSubmenuButton = class(Button)


function ItemSubmenu:__allocator()
    return Frame.__allocator("Frame", "WoWXIV_ItemSubmenu", UIParent)
end

function ItemSubmenu:__constructor()
    self.BORDER = 4  -- Inset from frame edge to menu items.
    self.MIN_EDGE = 4  -- Don't get closer than this to the screen edge.
    self.buttons = {}  -- List of buttons currently shown in the layout.

    -- Note that both of these are the same action because "item" resolves
    -- to either "equip" or "use" based on C_Item.IsEquippableItem() (see
    -- SECURE_ACTIONS.item in SecureTemplates.lua), which is the same test
    -- we use for showing the "Equip" menu item in place of "Use".
    self.menuitem_equip = ItemSubmenuButton(self, "Equip", true)
    self.menuitem_equip:SetAttribute("type1", "item")
    self.menuitem_use = ItemSubmenuButton(self, "Use", true)
    self.menuitem_use:SetAttribute("type1", "item")

    self.menuitem_disenchant = ItemSubmenuButton(self, "Disenchant", true)
    self.menuitem_disenchant:SetAttribute("type1", "spell")
    self.menuitem_disenchant:SetAttribute("spell", "Disenchant")

    self.menuitem_discard = ItemSubmenuButton(self, "Discard", false)
    self.menuitem_discard:SetScript(
        "OnClick", function() self:DoDiscard(self.item_loc) end)

    self:Hide()
    self:SetFrameStrata("DIALOG")
    self:SetScript("OnHide", self.OnHide)
    -- Immediately close the submenu on any mouse click, to reduce the
    -- risk of colliding inventory operations.
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    self:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then self:Hide() end
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
    local bagslot = strformat("%d %d", self.item:GetBagID(), self.item:GetID())

    if C_Item.IsEquippableItem(guid) then
        self:AppendButton(self.menuitem_equip)
        self.menuitem_equip:SetAttribute("item", bagslot)
    elseif C_Item.IsUsableItem(guid) then
        self:AppendButton(self.menuitem_use)
        self.menuitem_use:SetAttribute("item", bagslot)
    end

    local prof1, prof2 = GetProfessions()
    local TEXTURE_ENCHANTING = 4620672
    if (prof1 and select(2, GetProfessionInfo(prof1)) == TEXTURE_ENCHANTING)
    or (prof2 and select(2, GetProfessionInfo(prof2)) == TEXTURE_ENCHANTING)
    then
        self:AppendButton(self.menuitem_disenchant)
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
    button:Show()
end

function ItemSubmenu:FinishLayout()
    self:SetSize(self.layout_width + 2*self.BORDER,
                 self.layout_height + 2*self.BORDER)
    self.layout_prev = nil
end


-------- Individual menu option handlers

function ItemSubmenu:DoDiscard(item_loc)
    local bag, slot = item_loc:GetBagAndSlot()
    assert(type(bag) == "number")
    assert(type(slot) == "number")
    local info = C_Container.GetContainerItemInfo(bag, slot)
    assert(info)
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
        PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)  -- generic error sound
        print(WoWXIV.FormatColoredText("Item is locked.",
                                       RED_FONT_COLOR:GetRGB()))
        return
    end
    C_Container.PickupContainerItem(bag, slot)
    -- Verify that we picked up the same item we asked the user about,
    -- just in case the inventory changed when we weren't looking.
    local cursor_type, _, cursor_link = GetCursorInfo()
    if cursor_type == "item" and cursor_link == link then
        DeleteCursorItem()
    else
        PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)
        print(WoWXIV.FormatColoredText("Item could not be found.",
                                       RED_FONT_COLOR:GetRGB()))
        ClearCursor()
    end
end


-------- Menu item implementation

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
    self:HookScript("PostClick", function() parent:Hide() end)
    local label = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label = label
    label:SetPoint("CENTER")
    label:SetTextColor(WHITE_FONT_COLOR:GetRGB())
    label:SetTextScale(1.0)
    label:SetText(text)
    self:SetSize(label:GetStringWidth()+4, label:GetStringHeight()+2)
end

function ItemSubmenuButton:SetEnabled(enabled)
    Button.SetEnabled(self, enabled)
    label:SetTextColor(
        (enabled and WHITE_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
end
-- Ensure all enable changes go through SetEnabled() to update the text color.
function ItemSubmenu:Enable() self:SetEnabled(true) end
function ItemSubmenu:Disable() self:SetEnabled(false) end
