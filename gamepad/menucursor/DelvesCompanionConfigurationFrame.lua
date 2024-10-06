local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

local DelvesCompanionConfigurationFrameHandler = class(CoreMenuFrame)
local DelvesCompanionConfigurationSlotHandler = class(CoreMenuFrame)
local DelvesCompanionAbilityListFrameHandler = class(CoreMenuFrame)
Cursor.RegisterFrameHandler(DelvesCompanionConfigurationFrameHandler)

function DelvesCompanionConfigurationFrameHandler.Initialize(class, cursor)
    CoreMenuFrame.Initialize(class, cursor)
    class.instance_slot = {}
    local dccf = DelvesCompanionConfigurationFrame
    local lists = {dccf.CompanionCombatRoleSlot.OptionsList,
                   dccf.CompanionCombatTrinketSlot.OptionsList,
                   dccf.CompanionUtilityTrinketSlot.OptionsList}
    for _, list in ipairs(lists) do
        class.instance_slot[list] =
            DelvesCompanionConfigurationSlotHandler(list)
    end
    class.instance_abilist = DelvesCompanionAbilityListFrameHandler()
end

function DelvesCompanionConfigurationFrameHandler:__constructor()
    local dccf = DelvesCompanionConfigurationFrame
    self:__super(dccf)
    local function ClickSlot(frame)
        frame:OnMouseDown("LeftButton", true)
    end
    self.targets = {
        -- Mouse behavior brings up the tooltip when mousing over the
        -- portrait rather than the experience ring; we take the
        -- level indicator to be the more natural gamepad movement target,
        -- so we have to manually trigger the portrait enter/leave events.
        [dccf.CompanionLevelFrame] = {
            on_enter = function()
                local portrait = dccf.CompanionPortraitFrame
                portrait:GetScript("OnEnter")(portrait)
            end,
            on_leave = function()
                local portrait = dccf.CompanionPortraitFrame
                portrait:GetScript("OnLeave")(portrait)
            end,
            up = dccf.CompanionConfigShowAbilitiesButton,
            down = dccf.CompanionCombatRoleSlot,
            left = false, right = false},
        [dccf.CompanionCombatRoleSlot] = {
            on_click = ClickSlot, send_enter_leave = true, is_default = true,
            left = false, right = false},
        [dccf.CompanionCombatTrinketSlot] = {
            on_click = ClickSlot, send_enter_leave = true,
            left = false, right = false},
        [dccf.CompanionUtilityTrinketSlot] = {
            on_click = ClickSlot, send_enter_leave = true,
            left = false, right = false},
        [dccf.CompanionConfigShowAbilitiesButton] = {
            can_activate = true, lock_highlight = true,
            up = dccf.CompanionUtilityTrinketSlot,
            down = dccf.CompanionLevelFrame,
            left = false, right = false},
    }
end

function DelvesCompanionConfigurationSlotHandler:__constructor(frame)
    self:__super(frame)
    self.cancel_func = function() frame:Hide() end
end

function DelvesCompanionAbilityListFrameHandler:__constructor()
    self:__super(DelvesCompanionAbilityListFrame)
    self.cancel_func = MenuFrame.HideUIFrame
end

function DelvesCompanionAbilityListFrameHandler:OnShow()
    assert(DelvesCompanionAbilityListFrame:IsShown())
    self.targets = {}
    self:Enable()
    self:RefreshTargets()
end

function DelvesCompanionConfigurationSlotHandler:SetTargets(frame)
    local frame = self.frame
    local slot = frame:GetParent()
    self.targets = {}
    -- FIXME: rewrite with new algorithm in GossipFrame
    local subframes = {frame.ScrollBox.ScrollTarget:GetChildren()}
    local top, default
    local active_id = slot:HasActiveEntry() and slot.selectionNodeInfo.activeEntry.entryID
    for index, f in ipairs(subframes) do
        if f.GetElementData then
            local data = f:GetElementData()
            self.targets[f] = {can_activate = true, lock_highlight = true,
                               send_enter_leave = true}
            if not top or f:GetTop() > top:GetTop()then
                top = f
            end
            if active_id and data.entryID == active_id then
                default = f
            end
        end
    end
    local target = default or top
    if target then
        self.targets[target].is_default = true
    end
end

local cache_DelvesCompanionRoleDropdown = {}
function DelvesCompanionAbilityListFrameHandler:ToggleRoleDropdown()
    local dcalf = DelvesCompanionAbilityListFrame
    local role_dropdown = dcalf.DelvesCompanionRoleDropdown
    role_dropdown:SetMenuOpen(not role_dropdown:IsMenuOpen())
    if role_dropdown:IsMenuOpen() then
        local menu, initial_target = MenuFrame.SetupDropdownMenu(
            role_dropdown, cache_DelvesCompanionRoleDropdown,
            function(selection)
                if selection.data and selection.data.entryID == 123306 then
                    return 2  -- DPS
                else
                    return 1  -- Healer
                end
            end,
            function() self:RefreshTargets() end)
        menu:Enable(initial_target)
    end
end

function DelvesCompanionAbilityListFrameHandler:RefreshTargets()
    local dcalf = DelvesCompanionAbilityListFrame
    self.targets = {
        [dcalf.DelvesCompanionRoleDropdown] = {
            on_click = function() self:ToggleRoleDropdown() end,
            send_enter_leave = true,
            up = false, down = false, left = false, right = false},
    }
    -- Same logic as in DelvesCompanionAbilityListFrameMixin:UpdatePaginatedButtonDisplay()
    local MAX_DISPLAYED_BUTTONS = 12
    local start_index = ((dcalf.DelvesCompanionAbilityListPagingControls.currentPage - 1) * MAX_DISPLAYED_BUTTONS) + 1
    local count = 0
    local first, last1, last2, prev
    for i = start_index, #dcalf.buttons do
        if count >= MAX_DISPLAYED_BUTTONS then break end
        local button = dcalf.buttons[i]
        if button then
            self.targets[button] = {send_enter_leave = true, left = prev}
            if prev then
                self.targets[prev].right = button
            end
            first = first or button
            if last1 and button:GetTop() == last1:GetTop() then
                last2 = button
            else
                last1, last2 = button, nil
            end
            prev = button
        end
    end
    self.targets[dcalf.DelvesCompanionRoleDropdown].down = first
    self.targets[dcalf.DelvesCompanionRoleDropdown].up = last1
    self.targets[last1].down = dcalf.DelvesCompanionRoleDropdown
    if last2 then
        self.targets[last2].down = dcalf.DelvesCompanionRoleDropdown
    end
    self.targets[first].left = last2 or last1
    self.targets[last2 or last1].right = first
    self:SetTarget(first)
end