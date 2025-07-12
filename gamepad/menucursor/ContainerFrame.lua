local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class
local tinsert = tinsert

-- This is named like a global function but turns out to be local...
local function ContainerFrame_IsHeldBag(id)
    local NUM_TOTAL_BAG_FRAMES = Constants.InventoryConstants.NumBagSlots + Constants.InventoryConstants.NumReagentBagSlots  -- Also only defined locally.
    return id >= Enum.BagIndex.Backpack and id <= NUM_TOTAL_BAG_FRAMES
end

---------------------------------------------------------------------------

local cache_ItemSubmenuDropdown = {}

local ContainerFrameHandler = class(MenuCursor.MenuFrame)
-- NOTE: Currently disabled because we can't do anything useful with it
-- (see notes in SetupItemSubmenu()).
--MenuCursor.Cursor.RegisterFrameHandler(ContainerFrameHandler)


function ContainerFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
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

    -- Item submenu dropdown.  Creating this as a button and then moving
    -- the button right before opening the menu is a bit of a hack to
    -- work around the lack of an API to explicitly open a menu at a
    -- specified screen location.
    self.item_submenu_button =
        CreateFrame("DropdownButton", "WoWXIV_ItemSubmenuButton", UIParent)
    self.item_submenu_button:SetupMenu(function(dropdown, root)
        self:SetupItemSubmenu(dropdown, root)
    end)
end

function ContainerFrameHandler:OnShow(frame)
    local cur_target = self:GetTarget()
    if not cur_target then
        self.current_bag = frame:GetBagID()
        self.current_slot = 1
        local target, frame = self:SetTargets()
        self.frame = frame
        self:Enable(target)
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
    MenuCursor.MenuFrame.EnterTarget(self, target)
end

function ContainerFrameHandler:OnAction(button)
    assert(button == "Button4")
    local item = self:GetTarget()
    assert(item:GetBagID() == self.current_bag)
    assert(item:GetID() == self.current_slot)
    self.item_submenu_button:SetParent(item)
    self.item_submenu_button:SetAllPoints()
    self.item_submenu_button:SetMenuOpen(true)
    local menu, initial_target = self.SetupDropdownMenu(
        self.item_submenu_button, cache_ItemSubmenuDropdown)
    menu:Enable(initial_target)
end

function ContainerFrameHandler:SetupItemSubmenu(dropdown, root)
    if not self.current_bag then return end
    local location =
        ItemLocation:CreateFromBagAndSlot(self.current_bag, self.current_slot)
    local guid = C_Item.GetItemGUID(location)

    -- NOTE: Currently, none of these do anything due to API restrictions.
    -- This is more of a "would be nice" wishlist.

    if C_Item.IsEquippableItem(guid) then
        root:CreateButton("Equip", function() end)
    elseif C_Item.IsUsableItem(guid) then
        root:CreateButton("Use", function() end)
    end

    local prof1, prof2 = GetProfessions()
    local TEXTURE_ENCHANTING = 4620672
    if (prof1 and select(2, GetProfessionInfo(prof1)) == TEXTURE_ENCHANTING)
    or (prof2 and select(2, GetProfessionInfo(prof2)) == TEXTURE_ENCHANTING)
    then
        root:CreateButton("Disenchant", function() end)
    end

    root:CreateButton("Discard", function() end)
end
