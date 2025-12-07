local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local dropdown_cache = {}

local HousingHouseSettingsFrameHandler = class(MenuCursor.AddOnMenuFrame)
HousingHouseSettingsFrameHandler.ADDON_NAME = "Blizzard_HousingHouseSettings"
MenuCursor.Cursor.RegisterFrameHandler(HousingHouseSettingsFrameHandler)

function HousingHouseSettingsFrameHandler:__constructor()
    __super(self, HousingHouseSettingsFrame)
    local f = self.frame
    local p = f.PlotAccess
    local h = f.HouseAccess
    self.targets = {
        [f.HouseOwnerDropdown] = {
            on_click = function() self:OnClickOwnerDropdown() end,
            send_enter_leave = true, is_default = true,
            up = f.IgnoreListButton, down = p.AccessTypeDropdown,
            left = f.AbandonHouseButton, right = f.AbandonHouseButton},
        [f.AbandonHouseButton] = {
            can_activate = true, lock_highlight = true,
            up = f.SaveButton, down = h.AccessTypeDropdown,
            left = f.HouseOwnerDropdown, right = f.HouseOwnerDropdown},
        [p.AccessTypeDropdown] = {
            on_click = function(button) self:OnClickAccessDropdown(button) end,
            send_enter_leave = true, up = f.HouseOwnerButton,
            left = h.AccessTypeDropdown, right = h.AccessTypeDropdown},
        [h.AccessTypeDropdown] = {
            on_click = function(button) self:OnClickAccessDropdown(button) end,
            send_enter_leave = true, up = f.AbandonHouseButton,
            left = p.AccessTypeDropdown, right = p.AccessTypeDropdown},
        [f.IgnoreListButton] = {
            can_activate = true, lock_highlight = true,
            up = p.AccessTypeDropdown, down = f.HouseOwnerDropdown,
            left = f.SaveButton, right = f.SaveButton},
        [f.SaveButton] = {
            can_activate = true, lock_highlight = true,
            up = h.AccessTypeDropdown, down = f.AbandonHouseButton
,
            left = f.IgnoreListButton, right = f.IgnoreListButton},
    }
    -- We assume the plot and house access option lists are identical
    -- (they in fact are, as of patch 11.2.7).
    local p_options = p.accessOptions
    local h_options = h.accessOptions
    assert(#p_options == #h_options)
    for i, p_option in ipairs(p_options) do
        local h_option = h_options[i]
        assert(h_option.accessType == p_option.accessType)
        self.targets[p_option.Checkbox] = {
            can_activate = true, lock_highlight = true,
            up = i==1 and p.AccessTypeDropdown or p_options[i-1].Checkbox,
            down = i==#p_options and f.IgnoreListButton or p_options[i+1].Checkbox,
            left = h_option.Checkbox, right = h_option.Checkbox}
        self.targets[h_option.Checkbox] = {
            can_activate = true, lock_highlight = true,
            up = i==1 and h.AccessTypeDropdown or h_options[i-1].Checkbox,
            down = i==#h_options and f.SaveButton or h_options[i+1].Checkbox,
            left = p_option.Checkbox, right = p_option.Checkbox}
    end
    self.targets[p.AccessTypeDropdown].down = p_options[1].Checkbox
    self.targets[h.AccessTypeDropdown].down = h_options[1].Checkbox
    self.targets[f.IgnoreListButton].up = p_options[#p_options].Checkbox
    self.targets[f.SaveButton].up = h_options[#h_options].Checkbox
    -- It is most bizarre that clicks passed through to disabled checkboxes
    -- will still toggle the checkbox state...
    self:UpdateCheckboxActivateFlags(p)
    self:UpdateCheckboxActivateFlags(h)
    hooksecurefunc(p, "OnAccessTypeSelected",
                   function() self:UpdateCheckboxActivateFlags(p) end)
    hooksecurefunc(h, "OnAccessTypeSelected",
                   function() self:UpdateCheckboxActivateFlags(h) end)
end

function HousingHouseSettingsFrameHandler:UpdateCheckboxActivateFlags(column)
    for _, option in ipairs(column.accessOptions) do
        local checkbox = option.Checkbox
        self.targets[checkbox].can_activate = checkbox:IsEnabled()
    end
end

function HousingHouseSettingsFrameHandler:OnClickOwnerDropdown()
    local f = self.frame
    -- Don't try to open the dropdown if the data hasn't been loaded yet.
    if not (f.selectedOwnerID and f.selectedOwnerID > 0) then
        return
    end
    local dropdown = f.HouseOwnerDropdown
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        -- The character list doesn't have any radio buttons and thus no
        -- concept of a "selected" entry, so we have to look up the
        -- initial target by peeking into the frame's internal data.
        -- (We could also reproduce the frame's logic by catching the
        -- PLAYER_CHARACTER_LIST_UPDATED event, but probably not worth it;
        -- see HousingHouseSettingsFrameMixin:OnEvent() for details.)
        local menu = self.SetupDropdownMenu(dropdown, dropdown_cache)
        menu:Enable(menu.item_order[f.selectedOwnerID])
    end
end

function HousingHouseSettingsFrameHandler:OnClickAccessDropdown(dropdown)
    local f = self.frame
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        -- These dropdowns also don't use radio buttons, but the option
        -- order is well-defined, so we just look up the index directly
        -- from the button text.
        local menu = self.SetupDropdownMenu(dropdown, dropdown_cache)
        local order = {
            [HOUSING_HOUSE_SETTINGS_ANYONE] = 1,
            [HOUSING_HOUSE_SETTINGS_NOONE] = 2,
            [HOUSING_HOUSE_SETTINGS_LIMITED] = 3,
        }
        menu:Enable(menu.item_order[order[dropdown:GetText()] or 1])
    end
end
