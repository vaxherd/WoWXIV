local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local GameTooltip = GameTooltip
local abs = math.abs
local tinsert = tinsert

---------------------------------------------------------------------------

-- The old SpellBookFrame has been subsumed into the new PlayerSpellsFrame
-- which also covers specializations and talents, but we only handle the
-- actual spell list for now.

local SpellBookFrameHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(SpellBookFrameHandler)

function SpellBookFrameHandler.Initialize(class, cursor)
    class:RegisterAddOnWatch("Blizzard_PlayerSpells")
end

function SpellBookFrameHandler.OnAddOnLoaded(class)
    local instance = class()
    class.instance = instance
    instance:HookShow(PlayerSpellsFrame)

    local sbf = PlayerSpellsFrame.SpellBookFrame
    instance:HookShow(sbf, instance.OnShowSpellBookTab, instance.OnHide)
    EventRegistry:RegisterCallback(
        "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged",
        function()
            if PlayerSpellsFrame.SpellBookFrame:IsVisible() then
                instance:SetTarget(instance:RefreshTargets())
            end
        end)
    local pc = sbf.PagedSpellsFrame.PagingControls
    local buttons = {sbf.HidePassivesCheckButton.Button,
                     pc.PrevPageButton, pc.NextPageButton}
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        tinsert(buttons, tab)
    end
    for _, button in ipairs(buttons) do
        hooksecurefunc(button, "Click", function()
            instance:SetTarget(instance:RefreshTargets())
        end)
    end
end

function SpellBookFrameHandler:__constructor()
    self:__super(PlayerSpellsFrame.SpellBookFrame)
    self.cancel_func = function()
        HideUIPanel(PlayerSpellsFrame)
    end
    self.on_prev_page = PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.PrevPageButton
    self.on_next_page = PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.NextPageButton
end

function SpellBookFrameHandler:OnShow()
    if PlayerSpellsFrame.SpellBookFrame:IsShown() then
        self:OnShowSpellBookTab()
    end
end

function SpellBookFrameHandler:OnHide()
    self:Disable()
end

function SpellBookFrameHandler:OnShowSpellBookTab()
    if not PlayerSpellsFrame:IsShown() then return end
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
    local sbf = PlayerSpellsFrame.SpellBookFrame

    --[[
        Movement layout:

        [Category tabs]             ←→             [] Hide Passives
             ↑↓                                          ↑↓
        Top left spell ←→ ..................... ←→ Top right spell
             ↑↓                   ↑↓                   ↑↓
            .......         .....................          ........
          Left column  ←→ ..................... ←→   Right column
            .......         .....................          ........
             ↑↓                   ↑↓                   ↑↓
        Bottom left spell ←→ ................ ←→ Bottom right spell
              ↑                                           ↑↓
              ↓                               ↓→ Page N/M [<] ←→ [>]
        [Specialization] [Talents] [Spellbook] ←
    ]]--

    self.targets = {
        [sbf.HidePassivesCheckButton.Button] = {
            can_activate = true, lock_highlight = true, right = false},
    }

    local default_page_tab = nil
    local left_page_tab = nil
    local right_page_tab = nil
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab] = {can_activate = true, send_enter_leave = true,
                                 up = bottom, down = top}
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
    self.targets[left_page_tab].left = false
    self.targets[right_page_tab].right = sbf.HidePassivesCheckButton.Button

    local default_book_tab = nil
    local right_book_tab = nil
    for _, tab in ipairs(PlayerSpellsFrame.TabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab] = {can_activate = true, send_enter_leave = true,
                                 down = default_page_tab}
            -- HACK: breaking encapsulation to access tab selected state
            if not default_book_tab or tab.isSelected then
                default_book_tab = tab
            end
            if not right_book_tab or tab:GetLeft() > right_book_tab:GetLeft() then
                right_book_tab = tab
            end
        end
    end
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab].up = default_book_tab
        end
    end

    local pc = sbf.PagedSpellsFrame.PagingControls
    local page_buttons = {pc.PrevPageButton, pc.NextPageButton}
    for _, button in ipairs(page_buttons) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                up = sbf.HidePassivesCheckButton.Button,
                                down = right_book_tab}
    end
    self.targets[right_book_tab].right = pc.PrevPageButton
    self.targets[pc.PrevPageButton].left = right_book_tab
    self.targets[pc.NextPageButton].right = false
    self.targets[sbf.HidePassivesCheckButton.Button].down = pc.PrevPageButton

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
            is_left_half and default_page_tab or sbf.HidePassivesCheckButton.Button
        local bottom_target =
            is_left_half and default_book_tab or pc.PrevPageButton
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
                if is_top then
                    self.targets[sbf.HidePassivesCheckButton.Button].down = button
                end
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
            self.targets[tab].down = first_spell or default_book_tab
        end
    end

    -- If the cursor was previously on a spell button, the button might
    -- have disappeared, so reset to the top of the page.
    local cur_target = self:GetTarget()
    if not self.targets[cur_target] then
        cur_target = nil
    end

    return cur_target or first_spell or default_page_tab
end
