local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local GameTooltip = GameTooltip
local abs = math.abs
local tinsert = tinsert

---------------------------------------------------------------------------

local PlayerSpellsFrameHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(PlayerSpellsFrameHandler)
local SpecFrameHandler = class(MenuCursor.StandardMenuFrame)
local TalentsFrameHandler = class(MenuCursor.StandardMenuFrame)
local SpellBookFrameHandler = class(MenuCursor.StandardMenuFrame)


function PlayerSpellsFrameHandler.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch("Blizzard_PlayerSpells")
end

function PlayerSpellsFrameHandler.OnAddOnLoaded(class)
    class.instance = class()
    class.instance_SpecFrame = SpecFrameHandler()
    class.instance_TalentsFrame = TalentsFrameHandler()
    class.instance_SpellBookFrame = SpellBookFrameHandler()
end

function PlayerSpellsFrameHandler:__constructor()
    -- Same pattern as e.g. CharacterFrame.
    self:__super(PlayerSpellsFrame)
    self:HookShow(self.frame)
    self:SetTabSystem(self.frame.TabSystem)
end

function PlayerSpellsFrameHandler.CancelMenu()  -- Static method.
    HideUIPanel(PlayerSpellsFrame)
end

function PlayerSpellsFrameHandler:OnShow()
    local f = self.frame
    if f.SpecFrame:IsShown() then
        PlayerSpellsFrameHandler.instance_SpecFrame:OnShow()
    elseif f.TalentsFrame:IsShown() then
        PlayerSpellsFrameHandler.instance_TalentsFrame:OnShow()
    elseif f.SpellBookFrame:IsShown() then
        PlayerSpellsFrameHandler.instance_SpellBookFrame:OnShow()
    end
end

function PlayerSpellsFrameHandler:OnHide()
    local f = self.frame
    if f.SpecFrame:IsShown() then
        PlayerSpellsFrameHandler.instance_SpecFrame:OnHide()
    elseif f.TalentsFrame:IsShown() then
        PlayerSpellsFrameHandler.instance_TalentsFrame:OnHide()
    elseif f.SpellBookFrame:IsShown() then
        PlayerSpellsFrameHandler.instance_SpellBookFrame:OnHide()
    end
end


function SpecFrameHandler:__constructor()
    self:__super(PlayerSpellsFrame.SpecFrame)
    self.cancel_func = PlayerSpellsFrameHandler.CancelMenu
    self.tab_handler = PlayerSpellsFrameHandler.instance.tab_handler
    self:HookShow(self.frame.DisabledOverlay,
                  self.OnOverlaySetShown, self.OnOverlaySetShown)
end

function SpecFrameHandler:OnOverlaySetShown()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function SpecFrameHandler:SetTargets()
    local f = self.frame

    self.targets = {}

    if f.DisabledOverlay:IsShown() then
        return nil  -- Spec is currently changing.
    end

    local activates = {}
    local spells = {}
    for specf in self.frame.SpecContentFramePool:EnumerateActive() do
        local activate = specf.ActivateButton
        if activate:IsShown() then  -- Not shown for active spec.
            tinsert(activates, activate)
        end
        for spell in specf.SpellButtonPool:EnumerateActive() do
            tinsert(spells, spell)
        end
    end
    local function CompareX(a,b) return a:GetLeft() < b:GetLeft() end
    table.sort(activates, CompareX)
    table.sort(spells, CompareX)

    for i, button in ipairs(activates) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                left = activates[i==1 and #activates or i-1],
                                right = activates[i==#activates and 1 or i+1]}
    end
    for i, icon in ipairs(spells) do
        self.targets[icon] = {send_enter_leave = true,
                              left = spells[i==1 and #spells or i-1],
                              right = spells[i==#spells and 1 or i+1]}
    end

    return activates[1]
end


function TalentsFrameHandler:__constructor()
    self:__super(PlayerSpellsFrame.TalentsFrame)
    self.cancel_func = PlayerSpellsFrameHandler.CancelMenu
    self.tab_handler = PlayerSpellsFrameHandler.instance.tab_handler
end


function SpellBookFrameHandler:__constructor()
    self:__super(PlayerSpellsFrame.SpellBookFrame)
    self.cancel_func = PlayerSpellsFrameHandler.CancelMenu
    self.tab_handler = PlayerSpellsFrameHandler.instance.tab_handler
    self.on_prev_page = self.frame.PagedSpellsFrame.PagingControls.PrevPageButton
    self.on_next_page = self.frame.PagedSpellsFrame.PagingControls.NextPageButton

    EventRegistry:RegisterCallback(
        "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged",
        function()
            if self.frame:IsVisible() then
                self:SetTarget(self:RefreshTargets())
            end
        end)
    for _, button in ipairs({self.on_prev_page, self.on_next_page}) do
        hooksecurefunc(button, "Click", function()
            self:SetTarget(self:RefreshTargets())
        end)
    end
end

function SpellBookFrameHandler:OnShow()
    if not self.frame:IsVisible() then return end
    local target = self:RefreshTargets()
    self:Enable(target)
end

-- Effectively the same as SpellBookItemMixin:OnIconEnter() and ...Leave()
-- from Blizzard_SpellBookItem.lua.  We need to reimplement them ourselves
-- because those functions touch global variables, which become tainted if
-- we call the functions directly.  (As a result, action bar highlights are
-- not updated as they would be from mouse movement.)
local function SpellBookFrame_OnEnterButton(frame)
    local item = frame:GetParent()
    if not item:HasValidData() then
        return
    end
    if not item.isUnlearned then
        item.Button.IconHighlight:Show()
        item.Backplate:SetAlpha(item.hoverBackplateAlpha)
    end
    GameTooltip:SetOwner(item.Button, "ANCHOR_RIGHT")
    GameTooltip:SetSpellBookItem(item.slotIndex, item.spellBank)
    local actionBarStatusToolTip = item.actionBarStatus and SpellSearchUtil.GetTooltipForActionBarStatus(item.actionBarStatus)
    if actionBarStatusToolTip then
        GameTooltip_AddColoredLine(GameTooltip, actionBarStatusToolTip, LIGHTBLUE_FONT_COLOR)
    end
    GameTooltip:Show()
end

local function SpellBookFrame_OnLeaveButton(frame)
    local item = frame:GetParent()
    if not item:HasValidData() then
        return
    end
    item.Button.IconHighlight:Hide()
    item.Button.IconHighlight:SetAlpha(item.iconHighlightHoverAlpha)
    item.Backplate:SetAlpha(item.defaultBackplateAlpha)
    GameTooltip:Hide()
end

-- Return the closest spell button to the given Y coordinate in the given
-- button column.  Helper for SpellBookFrameHandler:RefreshTargets().
local function ClosestSpellButton(column, y)
    local best = column[1][1]
    local best_diff = abs(column[1][2] - y)
    for i = 2, #column do
        local diff = abs(column[i][2] - y)
        if diff < best_diff then
            best = column[i][1]
            best_diff = diff
        end
    end
    return best
end

-- Returns the new cursor target.
function SpellBookFrameHandler:RefreshTargets()
    local old_target = self:GetTarget()
    self:SetTarget(nil)

    local sbf = self.frame
    local pc = sbf.PagedSpellsFrame.PagingControls

    --[[
        Movement layout:

        [Category tabs]
             ↑↓
        Top left spell ←→ ..................... ←→ Top right spell
             ↑↓                   ↑↓                   ↑↓
            .......         .....................          ........
          Left column  ←→ ..................... ←→   Right column
            .......         .....................          ........
             ↑↓                   ↑↓                   ↑↓
        Bottom left spell ←→ ................ ←→ Bottom right spell
              ↑                                           ↑↓
                                              Page N/M [<] ←→ [>]
    ]]--

    self.targets = {}

    local default_page_tab = nil
    local left_page_tab = nil
    local right_page_tab = nil
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab] = {can_activate = true, send_enter_leave = true,
                                 up = pc.PrevPageButton,
                                 down = pc.PrevPageButton}
            -- HACK: breaking encapsulation to access tab selected state
            if not default_page_tab or tab.isSelected then
                default_page_tab = tab
            end
            if not left_page_tab or tab:GetLeft() < left_page_tab:GetLeft() then
                left_page_tab = tab
            end
            if not right_page_tab or tab:GetLeft() > right_page_tab:GetLeft() then
                right_page_tab = tab
            end
        end
    end
    self.targets[left_page_tab].left = right_page_tab
    self.targets[right_page_tab].right = left_page_tab

    local page_buttons = {pc.PrevPageButton, pc.NextPageButton}
    for _, button in ipairs(page_buttons) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                up = right_page_tab, down = right_page_tab}
    end
    self.targets[pc.PrevPageButton].left = pc.NextPageButton
    self.targets[pc.NextPageButton].right = pc.PrevPageButton

    -- If the cursor was previously on a spell button, the button might
    -- have disappeared or been reused in a different position, so reset
    -- to the top of the page.
    if not self.targets[old_target] then
        old_target = nil
    end

    local first_spell = nil
    local columns = {}
    local column_x = {}
    sbf:ForEachDisplayedSpell(function(spell)
        local button = spell.Button
        local x = button:GetLeft()
        if not columns[x] then
            columns[x] = {}
            tinsert(column_x, x)
        end
        tinsert(columns[x], {button, button:GetTop()})
    end)
    table.sort(column_x, function(a,b) return a < b end)
    for _, column in pairs(columns) do
        table.sort(column, function(a,b) return a[2] > b[2] end)
    end
    for x_index, x in ipairs(column_x) do
        local is_left = (x_index == 1)
        local is_right = (x_index == #column_x)
        local is_left_half = ((x_index-1) < 0.5*(#column_x-1))
        local top_target =
            is_left_half and default_page_tab or right_page_tab
        local bottom_target = pc.PrevPageButton
        local column = columns[x]
        for i, button_pair in ipairs(column) do
            local button, y = button_pair[1], button_pair[2]
            local is_top = (i == 1)
            local is_bottom = (i == #column)
            self.targets[button] = {
                can_activate = true,
                on_enter = function(frame) SpellBookFrame_OnEnterButton(frame) end,
                on_leave = function(frame) SpellBookFrame_OnLeaveButton(frame) end,
                up = is_top and top_target or column[i-1][1],
                down = is_bottom and bottom_target or column[i+1][1],
                left = not is_left and ClosestSpellButton(columns[column_x[x_index-1]], y),
                right = not is_right and ClosestSpellButton(columns[column_x[x_index+1]], y),
            }
            if is_left and is_top then
                first_spell = button
            end
            if is_right then
                if is_bottom then
                    for _, page_button in ipairs(page_buttons) do
                        self.targets[page_button].up = button
                    end
                end
            end
        end
    end

    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab].down = first_spell
        end
    end

    return old_target or first_spell or default_page_tab
end
