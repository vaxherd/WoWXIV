local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local cache_ItemInfoDropdown = {}

local ItemInteractionFrameHandler = class(MenuCursor.AddOnMenuFrame)
ItemInteractionFrameHandler.ADDON_NAME = "Blizzard_ItemInteractionUI"
MenuCursor.ItemInteractionFrameHandler = ItemInteractionFrameHandler  -- For exports.
MenuCursor.Cursor.RegisterFrameHandler(ItemInteractionFrameHandler)

function ItemInteractionFrameHandler:__constructor()
    __super(self, ItemInteractionFrame)
    self.has_Button4 = true  -- To clear the selected item (like right-click).
    self:HookShow(self.frame.CurrencyCost,
                  self.RefreshTargets, self.RefreshTargets)
end

function ItemInteractionFrameHandler:RefreshTargets()
    if self.frame:IsShown() then
        local target = self:GetTarget()
        self:ClearTarget()
        local default = self:SetTargets()
        if not self.targets[target] then target = default end
        self:SetTarget(target)
    end
end

function ItemInteractionFrameHandler:SetTargets()
    local f = self.frame
    local ActionButton = f.ButtonFrame.ActionButton
    local Currency = f.CurrencyCost.Currency
    local initial

    self.targets = {
        [ActionButton] =
            {can_activate = true, lock_highlight = true,
             up = false, down = false, left = false, right = false}
    }
    initial = ActionButton

    if f.CurrencyCost:IsShown() then
        self.targets[Currency] =
            {send_enter_leave = true, left = false, right = false,
             y_offset = -3,  -- Avoid covering up the cost.
             up = ActionButton, down = ActionButton}
        self.targets[ActionButton].up = Currency
        self.targets[ActionButton].down = Currency
    end

    if f.ItemConversionFrame:IsShown() then
        local InputSlot = f.ItemConversionFrame.ItemConversionInputSlot
        local OutputSlot = f.ItemConversionFrame.ItemConversionOutputSlot
        self.targets[InputSlot] =
            {on_click = function() self:OnClickItemButton(InputSlot) end,
             lock_highlight = true, send_enter_leave = true,
             up = ActionButton, down = ActionButton,
             left = OutputSlot, right = OutputSlot}
        self.targets[OutputSlot] =
            {lock_highlight = true, send_enter_leave = true,
             up = ActionButton, down = ActionButton,
             left = InputSlot, right = InputSlot}
        self.targets[ActionButton].down = OutputSlot
        if f.CurrencyCost:IsShown() then
            self.targets[InputSlot].down = Currency
            self.targets[OutputSlot].down = Currency
            self.targets[Currency].up = OutputSlot
        else
            self.targets[ActionButton].up = OutputSlot
        end
        initial = InputSlot
    end

    return initial
end

function ItemInteractionFrameHandler:OnClickItemButton()
    MenuCursor.CharacterFrameHandler.OpenForItemUpgrade()
end

function ItemInteractionFrameHandler:OnAction(button)
    assert(button == "Button4")
    local item_button
    if self.frame.ItemConversionFrame.ItemConversionInputSlot:IsVisible() then
        item_button = self.frame.ItemConversionFrame.ItemConversionInputSlot
    end
    if item_button and self:GetTarget() == item_button then
        item_button:GetScript("OnClick")(item_button, "RightButton", true)
    end
end

---------------------------------------------------------------------------

-- Give input focus to ItemInteractionFrame and put the cursor on the
-- action button.  The frame is assumed to be open.
function ItemInteractionFrameHandler.FocusActionButton()
    local instance = ItemInteractionFrameHandler.instance
    assert(instance:IsEnabled())
    instance:SetTarget(ItemInteractionFrame.ButtonFrame.ActionButton)
    instance:Focus()
end
