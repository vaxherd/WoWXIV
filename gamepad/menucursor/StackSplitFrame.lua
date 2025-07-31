local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local StackSplitFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(StackSplitFrameHandler)

function StackSplitFrameHandler:__constructor()
    local StackSplitFrame = StackSplitFrame
    local StackSplitText = StackSplitFrame.StackSplitText
    local OkayButton = StackSplitFrame.OkayButton
    local CancelButton = StackSplitFrame.CancelButton

    __super(self, StackSplitFrame, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
    self.cancel_button = CancelButton
    -- The frame has convenient increment/decrement buttons, so we just
    -- link to those rather than implementing our own function.
    self.on_prev_page = StackSplitFrame.LeftButton
    self.on_next_page = StackSplitFrame.RightButton

    self.targets = {
        [StackSplitText] = {
            on_click = function() self:EditQuantity() end, is_default = true,
            x_rightalign = true, x_offset = -72,
            up = OkayButton, down = OkayButton, left = false, right = false},
        [OkayButton] = {
            can_activate = true, lock_highlight = true,
            up = StackSplitText, down = StackSplitText,
            left = CancelButton, right = CancelButton},
        [CancelButton] = {
            can_activate = true, lock_highlight = true,
            up = StackSplitText, down = StackSplitText,
            left = OkayButton, right = OkayButton},
    }

    self.quantity_input = MenuCursor.NumberInput(
        StackSplitText, function() self:OnQuantityChanged() end,
        function() self:SetTarget(OkayButton) end)
end

function StackSplitFrameHandler:EditQuantity()
    self.quantity_input:Edit(1, self.frame.maxStack)
end

function StackSplitFrameHandler:OnQuantityChanged()
    StackSplitFrame.split = tonumber(StackSplitFrame.StackSplitText:GetText())
    StackSplitFrame:UpdateStackText()
    StackSplitFrame:UpdateStackSplitFrame(StackSplitFrame.maxStack)
end

---------------------------------------------------------------------------

-- Used by MerchantFrame.
function MenuCursor.StackSplitFrameEditQuantity()
    local instance = StackSplitFrameHandler.instance
    assert(instance)
    assert(instance.frame:IsShown())
    instance:EditQuantity()
end
