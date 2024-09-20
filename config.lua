local _, WoWXIV = ...
WoWXIV.Config = {}

local class = WoWXIV.class

-- Global config array, saved and restored by the API.
-- This is currently restored after parsing, so the value will always be
-- nil here, but we write it this way as future-proofing against values
-- being loaded sooner.
WoWXIV_config = WoWXIV_config or {}

------------------------------------------------------------------------

-- Default settings list.  Anything in here which is missing from
-- WoWXIV_config after module load is inserted by the init routine.
local CONFIG_DEFAULT = {

    -- Gamepad binding: menu cursor confirm
    gamepad_menu_confirm = "PAD2",
    -- Gamepad binding: menu cursor cancel
    gamepad_menu_cancel = "PAD1",
    -- Gamepad binding: previous page in menus
    gamepad_menu_prev_page = "PADLSHOULDER",
    -- Gamepad binding: next page in menus
    gamepad_menu_next_page = "PADRSHOULDER",
    -- Gamepad binding: focus next input window
    gamepad_menu_next_window = "PADBACK",
    -- Gamepad binding: use quest item
    gamepad_use_quest_item = "CTRL-PADLSTICK",
    -- Gamepad binding: select active quest item
    gamepad_select_quest_item = "CTRL-ALT-PADLSTICK",
    -- Gamepad binding: leave vehicle
    gamepad_leave_vehicle = "ALT-PADRSTICK",
    -- Gamepad binding: toggle first-person camera
    gamepad_toggle_fpv = "PADRSTICK",

    -- Gamepad: invert horizontal camera movement?
    gamepad_camera_invert_h = false,
    -- Gamepad: invert vertical camera movement?
    gamepad_camera_invert_v = false,
    -- Gamepad: camera zoom modifier for right stick
    gamepad_zoom_modifier = "ALT",

    -- Buff bars: show distance for skyriding glyph?
    buffbar_dragon_glyph_distance = true,

    -- Enmity list: enable?
    hatelist_enable = true,
    -- Enmity list: show rare/elite icon?
    hatelist_show_classification = true,

    -- Flying text: enable?
    flytext_enable = true,
    -- Flying text: if enabled, hide loot frame when autolooting?
    flytext_hide_autoloot = true,

    -- Log window: enable?
    logwindow_enable = true,
    -- Log window: number of history lines to keep
    logwindow_history = 10000,
    -- Log window: scroll to bottom on new messages?
    logwindow_auto_show_new = true,

    -- Map: show current coordinates under minimap?
    map_show_coords_minimap = true,
    -- Map: show mouseover coordinates on world map?
    map_show_coords_worldmap = true,

    -- Party list: when to enable
    partylist_enable = "solo,party,raid",
    -- Party list: where to use role/class colors
    partylist_colors = "none",
    -- Party list: when to use narrow format
    partylist_narrow_condition = "never",
    -- Party list: sort by role?
    partylist_sort = true,
    -- Party list: override Fn key bindings? (only when partylist_sort is true)
    partylist_fn_override = true,

    -- Quest item button: also use for scenario actions?
    questitem_scenario_action = true,

    -- Target bar: hide the native target and focus frames?
    targetbar_hide_native = true,
    -- Target bar: show target's power bar?
    targetbar_power = true,
    -- Target bar: only show target's power bar for bosses?
    targetbar_power_boss_only = true,
    -- Target bar: show numeric value of target's health shield?
    targetbar_show_shield_value = false,
    -- Target bar: show all debuffs (true) or only own debuffs (false)?
    targetbar_target_all_debuffs = true,
    -- Target bar: limit to own debuffs in raids only?
    targetbar_target_all_debuffs_not_raid = true,
    -- Target bar: show cast bar?
    targetbar_target_cast_bar = true,
    -- Target bar: show all debuffs on focus bar?
    targetbar_focus_all_debuffs = false,
    -- Target bar: ... except in raids?
    targetbar_focus_all_debuffs_not_raid = false,
    -- Target bar: show cast bar for focus?
    targetbar_focus_cast_bar = true,
    -- Target bar: move top-center info widget to bottom right?
    targetbar_move_top_center = true,

}

------------------------------------------------------------------------

-- Abstract base class for config panel elements.  Lua technically
-- doesn't need an explicit abstract base class because everything is
-- resolved dynamically, but this serves as documentation of the shared
-- API for all elements.

local ConfigPanelElement = class()

-- Return the desired vertical spacing between this element and the next.
function ConfigPanelElement:GetSpacing()
    return 0
end

------------------------------------------------------------------------

local CPCheckButton = class(ConfigPanelElement)

function CPCheckButton:__constructor(panel, x, y, text, setting, on_change,
                                     depends_on)
    self.setting = setting
    self.on_change = on_change
    self.depends_on = depends_on
    self.dependents = {}

    local indent = depends_on and 1 or 0
    local button = CreateFrame("CheckButton", nil, panel.frame,
                               "UICheckButtonTemplate")
    self.button = button
    button:SetPoint("TOPLEFT", x+30*indent, y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    button:SetChecked(WoWXIV_config[setting])
    button:SetScript("OnClick", function() self:OnClick() end)
    if depends_on then
        depends_on:AddDependent(self)
        self:SetSensitive(WoWXIV_config[depends_on.setting])
    end
end

function CPCheckButton:GetSpacing()
    return 30
end

function CPCheckButton:AddDependent(dependent)
    tinsert(self.dependents, dependent)
end

function CPCheckButton:SetSensitive(sensitive) -- SetEnable() plus color change
    local button = self.button
    self.button:SetEnabled(sensitive)
    -- SetEnabled() doesn't change the text color, so we have to do
    -- that manually.
    self.button.text:SetTextColor(
        (sensitive and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
end

function CPCheckButton:SetChecked(checked)
    checked = checked and true or false  -- Force to boolean type.
    self.button:SetChecked(checked)
    for _, dep in ipairs(self.dependents) do
        dep:SetSensitive(checked)
    end
    WoWXIV_config[self.setting] = checked
    if self.on_change then
        self.on_change(checked)
    end
end

function CPCheckButton:OnClick()
    self:SetChecked(not WoWXIV_config[self.setting])
end

------------------------------------------------------------------------

-- This class is not a visible element, but serves to group all radio
-- buttons for a single setting to ensure that only one is checked.
local CPRadioGroup = class()

function CPRadioGroup:__constructor(setting, on_change)
    self.setting = setting
    self.on_change = on_change
    self.buttons = {}
end

-- button must be a CPRadioButton.
function CPRadioGroup:AddButton(button)
    self.buttons[button.value] = button
end

function CPRadioGroup:SetValue(value)
    local value_button = self.buttons[value]
    if not value_button then
        error(("Invalid value for radio group %s: %s"):format(
                  self.setting, value))
        return
    end
    value_button:SetChecked(true)
    for _, button in pairs(self.buttons) do
        if button ~= value_button then
            button:SetChecked(false)
        end
    end
    WoWXIV_config[self.setting] = value
    if self.on_change then
        self.on_change(value)
    end
end

------------------------------------------------------------------------

local CPRadioButton = class(ConfigPanelElement)

-- Automatically adds the button to the given CPRadioGroup.
function CPRadioButton:__constructor(panel, x, y, text, group, value)
    self.group = group
    self.value = value

    self.on_change = on_change
    self.depends_on = depends_on
    self.dependents = {}

    local button = CreateFrame("CheckButton", nil, panel.frame,
                               "UIRadioButtonTemplate")
    self.button = button
    button:SetPoint("TOPLEFT", x, y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    button:SetChecked(WoWXIV_config[group.setting] == value)
    button:SetScript("OnClick", function() self:OnClick() end)

    group:AddButton(self)
end

function CPRadioButton:GetSpacing()
    return 20
end

function CPRadioButton:SetChecked(checked)
    self.button:SetChecked(checked)
end

function CPRadioButton:OnClick()
    self.group:SetValue(self.value)
end

------------------------------------------------------------------------

local CPGamepadBinding = class(ConfigPanelElement)

CPGamepadBinding.active_binding = nil

function CPGamepadBinding:__constructor(panel, x, y, text, setting, is_cvar,
                                        on_change)
    self.setting = setting
    self.is_cvar = is_cvar
    self.on_change = on_change

    local f = CreateFrame("Frame", nil, panel.frame)
    self.frame = f
    f:SetPoint("TOPLEFT", x, y+1)
    f:SetPoint("TOPRIGHT", -10, y+1)
    f:SetHeight(25)

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label = label
    label:SetPoint("LEFT")
    label:SetText(text)

    local button = CreateFrame("Button", nil, f, "UIMenuButtonStretchTemplate")
    self.button = button
    button:SetPoint("LEFT", 170, 0)
    button:SetSize(120, f:GetHeight()+5)
    button:SetScript("OnClick", function() self:OnClick() end)

    local button_text =
        button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    self.button_text = button_text
    button_text:SetPoint("CENTER")
    self:UpdateButtonText()
end

function CPGamepadBinding:GetSpacing()
    return self.frame:GetHeight()+5
end

function CPGamepadBinding:UpdateButtonText()
    local binding
    if self.is_cvar then
        binding = C_CVar.GetCVar(self.setting)
    else
        binding = WoWXIV_config[self.setting]
    end
    if binding ~= "" then
        self.button_text:SetTextColor(WHITE_FONT_COLOR:GetRGB())
        self.button_text:SetText(GetBindingText(binding))
    else
        self.button_text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
        self.button_text:SetText(GetBindingText(binding))
    end
end

function CPGamepadBinding:SetBinding(value, suppress_onchange)
    assert(type(value) == "string")
    local old_value
    if self.is_cvar then
        assert(not value:find("-", 1, true))
        old_value = C_CVar.GetCVar(self.setting)
        C_CVar.SetCVar(self.setting, value)
    else
        old_value = WoWXIV_config[self.setting]
        WoWXIV_config[self.setting] = value
    end
    self:UpdateButtonText()
    if not suppress_onchange and self.on_change then
        self.on_change(value, old_value)
    end
end

function CPGamepadBinding:Activate()
    -- If the player is reckless enough to try changing their bindings in
    -- the middle of combat, we can at least not exacerbate the problem by
    -- throwing up a taint warning on top of it.
    if InCombatLockdown() then return end

    assert(not CPGamepadBinding.active_binding)
    CPGamepadBinding.active_binding = self
    self.frame:SetPropagateKeyboardInput(false)
    self.frame:SetScript("OnGamePadButtonDown", function(_,...)
                            self:OnGamePadButtonDown(...)
                        end)
    self.frame:SetScript("OnGamePadButtonUp", function(_,...)
                            self:OnGamePadButtonUp(...)
                        end)
    self.frame:SetScript("OnKeyUp", function(_,...) self:OnKeyUp(...) end)
    self.buttons_down = {}
    self.new_binding = ""
    self.button_text:SetTextColor(WHITE_FONT_COLOR:GetRGB())
    self.button_text:SetText("Waiting...")
end

function CPGamepadBinding:Deactivate()
    self.frame:SetPropagateKeyboardInput(true)
    self.frame:SetScript("OnGamePadButtonDown", nil)
    self.frame:SetScript("OnGamePadButtonUp", nil)
    self.frame:SetScript("OnKeyUp", nil)
    self.buttons_down = nil
    assert(CPGamepadBinding.active_binding == self)
    CPGamepadBinding.active_binding = nil
end

function CPGamepadBinding:OnClick()
    if CPGamepadBinding.active_binding then
        CPGamepadBinding.active_binding:Deactivate()
    end
    self:Activate()
end

function CPGamepadBinding:OnGamePadButtonDown(button)
    -- We only accept the first (possibly modified) button, but we track
    -- all pressed buttons and only release the input lock once all
    -- buttons have been released.
    for _,b in ipairs(self.buttons_down) do
        assert(b ~= button)
    end
    tinsert(self.buttons_down, button)
    if #self.buttons_down == 1 then
        local modifiers = ""
        if IsAltKeyDown() then modifiers = modifiers .. "ALT-" end
        if IsControlKeyDown() then modifiers = modifiers .. "CTRL-" end
        if IsShiftKeyDown() then modifiers = modifiers .. "SHIFT-" end
        if self.is_cvar and modifiers ~= "" then
            -- Modifier buttons (and apparently also click buttons) have
            -- to be a single button, not a chord.
            return
        end
        self.new_binding = modifiers .. button
        self.button_text:SetText(GetBindingText(self.new_binding))
    end
end

function CPGamepadBinding:OnGamePadButtonUp(button)
    local found = false
    for i,b in ipairs(self.buttons_down) do
        if b == button then
            tremove(self.buttons_down, i)
            found = true
            break
        end
    end
    assert(found)
    if #self.buttons_down == 0 and self.new_binding ~= "" then
        self:Deactivate()
        self:SetBinding(self.new_binding)
    end
end

function CPGamepadBinding:OnKeyUp(key)
    if key == "ESCAPE" then
        self:Deactivate()
        if not self.is_cvar then
            self:SetBinding("")
        end
    end
end

------------------------------------------------------------------------

local ConfigPanel = class()

function ConfigPanel:__constructor()
    self.buttons = {}
    self.cvar_bindings = {}

    local f = CreateFrame("Frame", "WoWXIV_ConfigPanel")
    self.frame = f
    self.x = 10
    self.y = 0

    self:AddHeader("Gamepad bindings")
    self:AddBindingCvar("Modifier button 1 (Shift)", "GamePadEmulateShift")
    self:AddBindingCvar("Modifier button 2 (Ctrl)", "GamePadEmulateCtrl")
    self:AddBindingCvar("Modifier button 3 (Alt)", "GamePadEmulateAlt")
    self:AddComment("The Alt modifier is used to confirm/cancel target selection from the party list.")
    self:AddBindingCvar("Confirm ground target", "GamePadCursorLeftClick")
    self:AddBindingCvar("RMB emulation (unused)", "GamePadCursorRightClick")
    self:AddBindingLocal("Confirm menu selection", "gamepad_menu_confirm")
    self:AddBindingLocal("Cancel menu selection", "gamepad_menu_cancel")
    self:AddBindingLocal("Previous menu page", "gamepad_menu_prev_page")
    self:AddBindingLocal("Next menu page", "gamepad_menu_next_page")
    self:AddBindingLocal("Select next window", "gamepad_menu_next_window")
    self:AddBindingLocal("Use quest item", "gamepad_use_quest_item")
    self:AddBindingLocal("Select quest item", "gamepad_select_quest_item")
    self:AddBindingLocal("Leave vehicle", "gamepad_leave_vehicle")
    self:AddBindingLocal("Toggle first-person view", "gamepad_toggle_fpv")
    self.y = self.y - 10

    self:AddHeader("Gamepad camera control settings")
    self:AddCheckButton("Invert horizontal camera rotation",
                        "gamepad_camera_invert_h",
                        WoWXIV.Gamepad.UpdateCameraSettings)
    self:AddCheckButton("Invert vertical camera rotation",
                        "gamepad_camera_invert_v",
                        WoWXIV.Gamepad.UpdateCameraSettings)
    self:AddRadioGroup("Zoom modifier (with right stick up/down):",
                       "gamepad_zoom_modifier", WoWXIV.PartyList.Refresh,
                       "Shift", "SHIFT",
                       "Ctrl", "CTRL",
                       "Alt", "ALT")
    self.y = self.y - 10

    self:AddHeader("Buff/debuff bar settings")
    self:AddCheckButton("Show direction/distance for Skyriding Glyph Resonance",
                        "buffbar_dragon_glyph_distance")
    self:AddComment("Note: Dragon Isles glyphs show distance instead of direction, updated every 5 seconds.")

    self:AddHeader("Enmity list settings")
    self:AddCheckButton("Enable enmity list",
                        "hatelist_enable", WoWXIV.HateList.Enable)
    self:AddCheckButton("Show enemy classification (rare/elite) next to name",
                        "hatelist_show_classification",
                        WoWXIV.HateList.Refresh, "hatelist_enable")

    self:AddHeader("Flying text settings")
    self:AddCheckButton("Enable flying text (player only)", "flytext_enable",
                        WoWXIV.FlyText.Enable)
    self:AddCheckButton("Hide loot frame when autolooting",
                        "flytext_hide_autoloot", nil, "flytext_enable")

    self:AddHeader("Log window settings")
    self:AddCheckButton("Enable log window |cffff0000(requires reload)|r",
                        "logwindow_enable")
    self:AddCheckButton("Automatically scroll to bottom on new messages",
                        "logwindow_auto_show_new", nil, "logwindow_enable")

    self:AddHeader("Map settings")
    self:AddCheckButton("Show current coordinates under minimap",
                        "map_show_coords_minimap",
                        function(enable) WoWXIV.Map.SetShowCoords(WoWXIV_config["map_show_coords_worldmap"], enable) end)
    self:AddCheckButton("Show mouseover coordinates on world map",
                        "map_show_coords_worldmap",
                        function(enable) WoWXIV.Map.SetShowCoords(enable, WoWXIV_config["map_show_coords_minimap"]) end)

    self:AddHeader("Party list settings")
    self:AddRadioGroup("Enable party list: |cffff0000(requires reload)|r",
                       "partylist_enable", nil,
                       "Never", "none",
                       "Party only", "party",
                       "Solo and party only", "solo,party",
                       "Party and raid", "party,raid",
                       "Always (solo, party, and raid)", "solo,party,raid")
    self:AddRadioGroup("Role/class coloring:",
                       "partylist_colors", WoWXIV.PartyList.Refresh,
                       "None", "none",
                       "Role color in background", "role",
                       "Role color in background, class color in name", "role+class",
                       "Class color in background", "class")
    self:AddRadioGroup("Use narrow format (omit mana and limit buffs/debuffs):",
                       "partylist_narrow_condition", WoWXIV.PartyList.Refresh,
                       "Never", "never",
                       "Always", "always",
                       "Only in raids", "raid",
                       "Only in raids with 21+ members", "raidlarge")
    self:AddCheckButton("Sort party list by role",
                       "partylist_sort", WoWXIV.PartyList.Refresh)
    self:AddCheckButton("Override Fn hotkeys to match sorted party order",
                        "partylist_fn_override", WoWXIV.PartyList.Refresh,
                        "partylist_sort")

    self:AddHeader("Quest item button settings")
    self:AddCheckButton("Also use to activate scenario actions",
                        "questitem_scenario_action")

    self:AddHeader("Target bar settings")
    self:AddCheckButton("Hide native target frames |cffff0000(requires reload)|r",
                        "targetbar_hide_native")
    self:AddCheckButton("Show target's power bar", "targetbar_power",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Only for bosses", "targetbar_power_boss_only",
                        WoWXIV.TargetBar.Refresh, "targetbar_power")
    self:AddCheckButton("Show shield amount next to health value",
                        "targetbar_show_shield_value",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Show all debuffs on target bar",
                        "targetbar_target_all_debuffs",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Except in raids",
                        "targetbar_target_all_debuffs_not_raid",
                        WoWXIV.TargetBar.Refresh,
                        "targetbar_target_all_debuffs")
    self:AddCheckButton("Show cast bar on target bar",
                        "targetbar_target_cast_bar",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Show all debuffs on focus bar",
                        "targetbar_focus_all_debuffs",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Except in raids",
                        "targetbar_focus_all_debuffs_not_raid",
                        WoWXIV.TargetBar.Refresh,
                        "targetbar_focus_all_debuffs")
    self:AddCheckButton("Show cast bar on focus bar",
                        "targetbar_focus_cast_bar",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Move top-center widget to bottom right |cffff0000(requires reload)|r",
                        "targetbar_move_top_center",
                        WoWXIV.TargetBar.Refresh)
    self:AddComment("(Eye of the Jailer, Heart of Amirdrassil health, etc.)")

    self.y = self.y - 20
    self:AddHorizontalBar()
    self.y = self.y + 10
    self:AddHeader("About WoWXIV")
    self:AddText("WoWXIV is designed to change several aspects of the " ..
                 "WoW user interface to mimic the UI of Final Fantasy XIV, " ..
                 "along with a few general quality-of-life tweaks.|n|n" ..
                 "Author: vaxherd|nVersion: "..WoWXIV.VERSION)

    f:SetHeight(-self.y + 10)
end

function ConfigPanel:AddHeader(text)
    local f = self.frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    self.y = self.y - 20
    label:SetPoint("TOPLEFT", self.x, self.y)
    label:SetTextScale(1.2)
    label:SetText(text)
    self.y = self.y - 25
    return label
end

function ConfigPanel:AddText(text)
    local f = self.frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.y = self.y - 15
    label:SetPoint("TOPLEFT", self.x, self.y)
    label:SetPoint("TOPRIGHT", -self.x, self.y)
    label:SetJustifyH("LEFT")
    label:SetSpacing(3)
    label:SetTextScale(1.1)
    label:SetText(text)
    -- FIXME: This is fundamentally broken because we don't know how wide
    -- the frame will be until it's sized when the options window is first
    -- opened, and therefore we don't know how tall it will end up being.
    -- We can get away with this for now because this is only used once
    -- and at the very bottom of the config frame (for the about text).
    self.y = self.y - 80
    return label
end

function ConfigPanel:AddComment(text)
    local f = self.frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", self.x+40, self.y+4)
    label:SetTextColor(1, 0.5, 0)
    label:SetText(text)
    self.y = self.y - 16
    return label
end

function ConfigPanel:AddHorizontalBar(text)
    local f = self.frame
    local texture = f:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("LEFT", f, "TOPLEFT", self.x, self.y)
    texture:SetPoint("RIGHT", f, "TOPRIGHT", 0, self.y)
    texture:SetHeight(1.5)
    texture:SetAtlas("Options_HorizontalDivider")
    self.y = self.y - 20
    return texture
end

function ConfigPanel:AddCheckButton(text, setting, on_change, depends_on)
    depends_on = depends_on and self.buttons[depends_on]
    local button = CPCheckButton(self, self.x+10, self.y,
                                 text, setting, on_change, depends_on)
    self.y = self.y - button:GetSpacing()
    self.buttons[setting] = button
end

-- Call as: AddRadioGroup(header, setting, on_change,
--                        text1, value1, [text2, value2...])
function ConfigPanel:AddRadioGroup(header, setting, on_change, ...)
    local f = self.frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.y = self.y - 10
    label:SetPoint("TOPLEFT", self.x+15, self.y)
    label:SetText(header)
    self.y = self.y - 20

    local group = CPRadioGroup(setting, on_change)
    for i = 1, select("#",...), 2 do
        local text, value = select(i,...)
        local button = CPRadioButton(self, self.x+35, self.y,
                                     text, group, value)
        self.y = self.y - button:GetSpacing()
    end
end

function ConfigPanel:AddBindingCvar(text, cvar)
    local binding = CPGamepadBinding(
        self, self.x+15, self.y, text, cvar, true,
        function(value, old_value)
            self:CheckBindingCollision(cvar, value, old_value)
        end)
    self.y = self.y - binding:GetSpacing()
    self.cvar_bindings[cvar] = binding
end

function ConfigPanel:CheckBindingCollision(cvar, value, old_value)
    for other_cvar, other_binding in pairs(self.cvar_bindings) do
        if other_cvar ~= cvar then
            local other_value = C_CVar.GetCVar(other_cvar)
            if other_value == value then
                other_binding:SetBinding(old_value, true)
            end
        end
    end
end

function ConfigPanel:AddBindingLocal(text, setting)
    local binding = CPGamepadBinding(self, self.x+15, self.y, text,
                                     setting, false,
                                     WoWXIV.Gamepad.UpdateBindings)
    self.y = self.y - binding:GetSpacing()
end

------------------------------------------------------------------------

-- Initialize configuration data and create the configuration window.
function WoWXIV.Config.Create()
    for k, v in pairs(CONFIG_DEFAULT) do
        if WoWXIV_config[k] == nil then
            WoWXIV_config[k] = v
        end
    end

    local config_panel = ConfigPanel()
    WoWXIV.Config.panel = config_panel
    local f = config_panel.frame

    local container = CreateFrame("ScrollFrame", "WoWXIV_ConfigScroller", nil,
                                  "UIPanelScrollFrameTemplate")
    container:SetScrollChild(f)

    local root = CreateFrame("Frame", "WoWXIV_ConfigRoot")
    container:SetParent(root)
    -- Required by the settings API:
    function root:OnCommit()
    end
    function root:OnDefault()
        -- Currently unimplemented because we had an implementation but it
        -- kept getting out of sync with the actual options.  If we add
        -- this back then we'll need to massage the button implementation
        -- a bit.
    end
    function root:OnRefresh()
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT")
        container:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -29, 6)
        f:SetWidth(container:GetWidth())
    end
    local category = Settings.RegisterCanvasLayoutCategory(root, "WoWXIV")
    WoWXIV.Config.category = category
    category.ID = "WoWXIV"
    Settings.RegisterAddOnCategory(category)
end

-- Open the addon configuration window.
function WoWXIV.Config.Open()
    Settings.OpenToCategory(WoWXIV.Config.category.ID)
end
