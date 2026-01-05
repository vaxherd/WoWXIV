local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local strformat = string.format
local strgsub = string.gsub
local strmatch = string.match
local strsub = string.sub

---------------------------------------------------------------------------

local StackSplitFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(StackSplitFrameHandler)


-- Helper to strip the STACKS format text out of edit box text.
-- Returns the numeric value embedded in the text.
local function StripSTACKS(text)
    if strsub(STACKS, 1, 2) == "%d" then
        n = tonumber(strmatch(text, "^(%d+)"))
    elseif strsub(STACKS, #stacks-1) == "%d" then
        n = tonumber(strmatch(text, "(%d+)$"))
    end
    return n or tonumber(text)
end


-- Subclass of NumberInput to handle funky syntax in the input box.
local StackSplitNumberInput = class(MenuCursor.NumberInput)

function StackSplitNumberInput:__constructor(editbox, on_change, on_confirm,
                                             parent)
    __super(self, editbox, on_change, on_confirm)
    self.parent = parent
end

function StackSplitNumberInput:GetEditBoxValue()
    local s = self.editbox:GetText()
    local n
    if self.parent.isMultiStack then
        -- The edit box has flavor text in it, so strip that out.
        n = StripSTACKS(s)
    end
    return n or tonumber(s)
end

function StackSplitNumberInput:MakeLabelText(value_str)
    if self.parent.isMultiStack then
        local s = strgsub(STACKS, "%%d", "%%s")
        return strformat(s, value_str)
    end
    return value_str
end


function StackSplitFrameHandler:__constructor()
    __super(self, StackSplitFrame, MenuCursor.MenuFrame.MODAL)
    local f = self.frame
    local StackSplitText = f.StackSplitText
    local OkayButton = f.OkayButton
    local CancelButton = f.CancelButton
    self.cancel_func = nil
    self.cancel_button = CancelButton
    -- The frame has convenient increment/decrement buttons, so we just
    -- link to those rather than implementing our own function.
    self.on_prev_page = f.LeftButton
    self.on_next_page = f.RightButton

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

    self.quantity_input = StackSplitNumberInput(
        StackSplitText, function() self:OnQuantityChanged() end,
        function() self:SetTarget(OkayButton) end, f)
end

function StackSplitFrameHandler:EditQuantity()
    local f = self.frame
    assert(type(f.minSplit) == "number")
    assert(f.minSplit > 0)
    assert(f.minSplit % 1 == 0)
    self.unit = f.minSplit  -- Assumed constant during editing.
    self.quantity_input:Edit(1, self.frame.maxStack)
end

function StackSplitFrameHandler:OnQuantityChanged()
    local f = self.frame
    local split
    if self.frame.isMultiStack then
        split = StripSTACKS(f.StackSplitText:GetText())
    end
    if not split then
        split = tonumber(f.StackSplitText:GetText())
    end
    if split then
        f.split = split * self.unit
        f:UpdateStackText()
        -- StackSplitMixin.UpdateStackSplitFrame is obsolete logic which
        -- hasn't been updated to support isMultiStack, and the parts of
        -- it which handled updating left/right button state based on the
        -- input value have now been copy-pasted into the individual input
        -- handlers (?!) so we have to reimplement that behavior ourselves.
        --f:UpdateStackSplitFrame(f.maxStack)
        f.LeftButton:SetEnabled(split > 1)
        f.RightButton:SetEnabled(split < StackSplitFrame.maxStack)
    end
end

---------------------------------------------------------------------------

-- Used by MerchantFrame.
function MenuCursor.StackSplitFrameEditQuantity()
    local instance = StackSplitFrameHandler.instance
    assert(instance)
    assert(instance.frame:IsShown())
    instance:EditQuantity()
end
