local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

-- FIXME: currently just a minimal implementation for use by ItemUpgradeFrame

---------------------------------------------------------------------------

local CharacterFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.CharacterFrameHandler = CharacterFrameHandler  -- For exports.
MenuCursor.Cursor.RegisterFrameHandler(CharacterFrameHandler)

function CharacterFrameHandler:__constructor()
    self:__super(CharacterFrame)
end

function CharacterFrameHandler:SetTargets()
    local left = {CharacterHeadSlot, CharacterNeckSlot,
                  CharacterShoulderSlot, CharacterBackSlot,
                  CharacterChestSlot, CharacterShirtSlot,
                  CharacterTabardSlot, CharacterWristSlot}
    local right = {CharacterHandsSlot, CharacterWaistSlot,
                   CharacterLegsSlot, CharacterFeetSlot,
                   CharacterFinger0Slot, CharacterFinger1Slot,
                   CharacterTrinket0Slot, CharacterTrinket1Slot}
    local bottom = {CharacterMainHandSlot, CharacterSecondaryHandSlot}
    self.targets = {}
    local function OnClickSlot(slot)
        self:OnClickSlot(slot)
    end
    for i = 0, 7 do
        local l = left[i+1]
        local r = right[i+1]
        self.targets[l] = {
            on_click = OnClickSlot, lock_highlight = true,
            send_enter_leave = true, left = r, right = r,
            up = left[(i+7)%8+1], down = left[(i+1)%8+1]}
        self.targets[r] = {
            on_click = OnClickSlot, lock_highlight = true,
            send_enter_leave = true, left = l, right = l,
            up = right[(i+7)%8+1], down = right[(i+1)%8+1]}
    end
    self.targets[bottom[1]] = {
        on_click = OnClickSlot, lock_highlight = true, send_enter_leave = true,
        left = left[8], right = bottom[2], up = false, down = false}
    self.targets[bottom[2]] = {
        on_click = OnClickSlot, lock_highlight = true, send_enter_leave = true,
        left = bottom[1], right = right[8], up = false, down = false}
    self.targets[left[8]].right = bottom[1]
    self.targets[right[8]].left = bottom[2]
    self.targets[left[1]].is_default = true
end

function CharacterFrameHandler:OnClickSlot(slot)
    if slot.itemContextMatchResult == ItemButtonUtil.ItemContextMatchResult.Match then
        PaperDollItemSlotButton_OnClick(slot, "RightButton")
        HideUIPanel(CharacterFrame)
    end
end

---------------------------------------------------------------------------

-- Exported function, called by ItemUpgradeFrame.  (FIXME: this is a bit
-- sloppy, revisit when CharacterFrame is more fully implemented)
function CharacterFrameHandler.OpenForItemUpgrade()
    ToggleCharacter("PaperDollFrame", true)
    CharacterFrameHandler.instance:Enable()  -- In case it was already open.
end
