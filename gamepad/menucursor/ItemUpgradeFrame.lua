local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local cache_ItemInfoDropdown = {}

local ItemUpgradeFrameHandler = class(MenuCursor.AddOnMenuFrame)
MenuCursor.ItemUpgradeFrameHandler = ItemUpgradeFrameHandler  -- for exports
ItemUpgradeFrameHandler.ADDON_NAME = "Blizzard_ItemUpgradeUI"
MenuCursor.Cursor.RegisterFrameHandler(ItemUpgradeFrameHandler)

function ItemUpgradeFrameHandler:__constructor()
    self:__super(ItemUpgradeFrame)
    self.has_Button4 = true  -- To clear the selected item (like right-click).
    self:HookShow(self.frame.ItemInfo.Dropdown,
                  self.RefreshTargets, self.RefreshTargets)
    self:HookShow(self.frame.UpgradeCostFrame,
                  self.RefreshTargets, self.RefreshTargets)
end

-- FIXME: surely this can be a shared function?
function ItemUpgradeFrameHandler:RefreshTargets()
    if self.frame:IsShown() then
        local target = self:GetTarget()
        self:ClearTarget()
        self:SetTargets()
        if not self.targets[target] then target = nil end
        self:SetTarget(target or self:GetDefaultTarget())
    end
end

function ItemUpgradeFrameHandler:SetTargets()
    local f = self.frame
    self.targets = {
        [f.UpgradeItemButton] =
            {on_click = function() self:OnClickItemButton() end,
             lock_highlight = true, is_default = true,
             up = f.UpgradeButton, down = f.UpgradeButton,
             left = false, right = false},
        [f.UpgradeButton] =
            {can_activate = true, lock_highlight = true,
             up = f.UpgradeItemButton, down = f.UpgradeItemButton,
             left = false, right = false}
    }

    local topright = f.UpgradeItemButton
    local dropdown = f.ItemInfo.Dropdown
    if dropdown:IsShown() then
      if false then  -- FIXME: taints the upgrade action
        self.targets[dropdown] = {
            on_click = function() self:OnClickDropdown() end,
            send_enter_leave = true,
            up = f.UpgradeButton, down = f.UpgradeButton,
            left = f.UpgradeItemButton, right = f.UpgradeItemButton}
        self.targets[f.UpgradeItemButton].left = dropdown
        self.targets[f.UpgradeItemButton].right = dropdown
        topright = dropdown
      end
    end

    if f.UpgradeCostFrame:IsShown() then
        local first, prev
        for _, subframe in ipairs({f.UpgradeCostFrame:GetChildren()}) do
            first = first or subframe
            if prev then
                self.targets[prev].right = subframe
            end
            self.targets[subframe] = {
                y_offset = -3,  -- Avoid covering up the cost.
                send_enter_leave = true,
                up = topright, down = f.UpgradeButton, left = prev}
            prev = subframe
        end
        if first then
            self.targets[first].left = prev
            self.targets[prev].right = first
            self.targets[f.UpgradeButton].up = first
            self.targets[f.UpgradeItemButton].down = first
            if self.targets[dropdown] then  -- Should always be present.
                self.targets[dropdown].down = first
            end
        end
    end
end

function ItemUpgradeFrameHandler:OnClickDropdown()
    local f = self.frame
    local dropdown = f.ItemInfo.Dropdown
    local currUpgrade = f.upgradeInfo and f.upgradeInfo.currUpgrade or 0
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local menu, initial_target = self.SetupDropdownMenu(
            dropdown, cache_ItemInfoDropdown,
            function(selection)
                return selection.data and selection.data - currUpgrade
            end,
            function() self:RefreshTargets() end)
        menu:Enable(initial_target)
    end
end

function ItemUpgradeFrameHandler:OnClickItemButton()
    MenuCursor.CharacterFrameHandler.OpenForItemUpgrade()
end

function ItemUpgradeFrameHandler:OnAction(button)
    assert(button == "Button4")
    local item_button = self.frame.UpgradeItemButton
    if self:GetTarget() == item_button then
        item_button:GetScript("OnClick")(item_button, "RightButton", true)
    end
end

---------------------------------------------------------------------------

-- Give input focus to ItemUpgradeFrame and put the cursor on the "Upgrade"
-- button.  The frame is assumed to be open.
function ItemUpgradeFrameHandler.FocusUpgradeButton()
    local instance = ItemUpgradeFrameHandler.instance
    assert(instance:IsEnabled())
    instance:SetTarget(ItemUpgradeFrame.UpgradeButton)
    instance:Focus()
end
