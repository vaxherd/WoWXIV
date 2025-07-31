local module_name, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local AzeriteEmpoweredItemUIHandler = class(MenuCursor.AddOnMenuFrame)
AzeriteEmpoweredItemUIHandler.ADDON_NAME = "Blizzard_AzeriteUI"
MenuCursor.Cursor.RegisterFrameHandler(AzeriteEmpoweredItemUIHandler)

function AzeriteEmpoweredItemUIHandler:__constructor()
    __super(self, AzeriteEmpoweredItemUI)
    hooksecurefunc(self.frame, "RebuildTiers",
                   function() self:RefreshTargets() end)
    hooksecurefunc(self.frame, "UpdateTiers",
                   function() self:RefreshTargets() end)
end

function AzeriteEmpoweredItemUIHandler:RefreshTargets()
    -- It seems we have to wait a frame for all the UI elements to be
    -- properly configured, even with the RebuildTiers() hook.  We could
    -- probably dig deeper and figure out why, but the effort isn't worth
    -- it for an obsolete game feature.
    if not self.refreshing then
        self.refreshing = true
        RunNextFrame(function()
            self.refreshing = false
            self:SetTarget(nil)
            self:SetTarget(self:SetTargets())
        end)
    end
end

function AzeriteEmpoweredItemUIHandler:SetTargets()
    local f = self.frame
    self.targets = {}
    -- A clever UI for gamepad would be to lock the cursor to the center
    -- slots and use D-pad left/right to rotate the rings, but since the
    -- rings aren't designed to rotate freely (only once,  when a power
    -- is selected) and this is obsolete content anyway, we stick to
    -- just moving around the useful buttons.
    local initial_power = nil
    local selectable_power = nil
    for button in f.powerPool:EnumerateActive() do
        local is = button:IsSelected()
        local can = button:CanBeSelected()
        if is or can then
            self.targets[button] = {can_activate = can, send_enter_leave = true}
            if not initial_power or button.unlockLevel < initial_power.unlockLevel then
                initial_power = button
            end
            if can and not selectable_power then
                selectable_power = can
            end
        end
    end
    local initial_tier
    for tier in f.tierPool:EnumerateActive() do
        if not (tier:HasAnySelected() or tier:IsFinalTier()) then
            self.targets[tier.tierSlot] = {send_enter_leave = true}
            if not initial_tier or tier.tierInfo.unlockLevel <= initial_tier.tierInfo.unlockLevel then
                initial_tier = tier
            end
        end
    end
    return initial_tier and initial_tier.tierSlot
        or selectable_power  -- When the final tier is the only one left.
        or initial_power
end
