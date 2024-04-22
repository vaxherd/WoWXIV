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

    -- Buff bars: show distance for dragon glyph?
    buffbar_dragon_glyph_distance = true,

    -- Enmity list: enable?
    hatelist_enable = true,

    -- Fly text: enable?
    flytext_enable = true,
    -- Fly text: if enabled, hide loot frame when autolooting?
    flytext_hide_autoloot = true,

    -- Map: show current coordinates under minimap?
    map_show_coords_minimap = true,
    -- Map: show mouseover coordinates on world map?
    map_show_coords_worldmap = true,

    -- Party list: where to use role/class colors
    partylist_colors = nil,
    -- Party list: when to use narrow format
    partylist_narrow_condition = "never",

    -- Target bar: hide the native target and focus frames?
    targetbar_hide_native = true,
    -- Target bar: show target's power bar?
    targetbar_power = true,
    -- Target bar: only show target's power bar for bosses?
    targetbar_power_boss_only = true,
    -- Target bar: show all debuffs (true) or only own debuffs (false)?
    targetbar_target_all_debuffs = true,
    -- Target bar: limit to own debuffs in raids only?
    targetbar_target_all_debuffs_not_raid = true,
    -- Target bar: show all debuffs on focus bar?
    targetbar_focus_all_debuffs = false,
    -- Target bar: ... except in raids?
    targetbar_focus_all_debuffs_not_raid = false,
    -- Target bar: move top-center info widget to bottom right?
    targetbar_move_top_center = true,

}

------------------------------------------------------------------------

local ConfigFrame = class()

function ConfigFrame:AddHeader(text)
    local f = self.native_frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    self.y = self.y - 30
    label:SetPoint("TOPLEFT", self.x, self.y)
    label:SetTextScale(1.2)
    label:SetText(text)
    self.y = self.y - 15
    return label
end

function ConfigFrame:AddText(text)
    local f = self.native_frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.y = self.y - 25
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
    self.y = self.y - 70
    return label
end

function ConfigFrame:AddComment(text)
    local f = self.native_frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.y = self.y - 6
    label:SetPoint("TOPLEFT", self.x+40, self.y)
    label:SetTextColor(1, 0.5, 0)
    label:SetText(text)
    self.y = self.y - 10
    return label
end

function ConfigFrame:AddHorizontalBar(text)
    local f = self.native_frame
    local texture = f:CreateTexture(nil, "ARTWORK")
    self.y = self.y - 10
    texture:SetPoint("LEFT", f, "TOPLEFT", self.x, self.y)
    texture:SetPoint("RIGHT", f, "TOPRIGHT", 0, self.y)
    texture:SetHeight(1.5)
    texture:SetAtlas("Options_HorizontalDivider")
    self.y = self.y - 10
    return texture
end

function ConfigFrame:AddCheckButton(text, setting, on_change, depends_on)
    local indent = depends_on and 1 or 0
    local f = self.native_frame
    local button = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    self.y = self.y - 10
    button:SetPoint("TOPLEFT", self.x+10+30*indent, self.y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    self.y = self.y - 20
    button:SetChecked(WoWXIV_config[setting])
    function button:SetSensitive(sensitive)  -- SetEnable() plus color change
        self:SetEnabled(sensitive)
        -- SetEnabled() doesn't change the text color, so we have to do
        -- that manually.
        self.text:SetTextColor(
            (sensitive and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
    end
    button:SetScript("OnClick", function(self)
        local new_value = not WoWXIV_config[setting]
        WoWXIV_config[setting] = new_value
        self:SetChecked(new_value)
        for _, dep in ipairs(self.dependents) do
            dep:SetSensitive(new_value)
        end
        if on_change then on_change(new_value) end
    end)
    button.dependents = {}
    if depends_on then
        local depends_on_button = self.buttons[depends_on]
        assert(depends_on_button)
        tinsert(depends_on_button.dependents, button)
        button:SetSensitive(WoWXIV_config[depends_on])
    end
    self.buttons[setting] = button
    return button
end

function ConfigFrame:AddRadioHeader(text)
    local f = self.native_frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.y = self.y - 20
    label:SetPoint("TOPLEFT", self.x+15, self.y)
    label:SetText(text)
    self.y = self.y - 10
    return label
end

function ConfigFrame:AddRadioButton(text, setting, value, on_change)
    local f = self.native_frame
    local button = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
    self.y = self.y - 10
    button:SetPoint("TOPLEFT", self.x+35, self.y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    self.y = self.y - 10
    button:SetChecked(WoWXIV_config[setting] == value)
    button.WoWXIV_value = value
    f.WoWXIV_radio_buttons = f.WoWXIV_radio_buttons or {}
    f.WoWXIV_radio_buttons[setting] = f.WoWXIV_radio_buttons[setting] or {}
    tinsert(f.WoWXIV_radio_buttons[setting], button)
    button:SetScript("OnClick", function(self)
        WoWXIV_config[setting] = value
        self:SetChecked(true)
        for _, other in ipairs(f.WoWXIV_radio_buttons[setting]) do
            if other.WoWXIV_value ~= value then
                other:SetChecked(false)
            end
        end
        if on_change then on_change(new_value) end
    end)
    return button
end

function ConfigFrame:__constructor()
    self.buttons = {}

    local f = CreateFrame("Frame", "WoWXIV_ConfigFrame")
    self.native_frame = f
    self.x = 10
    self.y = 10  -- Assuming an initial header.

    self:AddHeader("Buff/debuff bar settings")
    self:AddCheckButton("Show distance for Dragon Glyph Resonance",
                        "buffbar_dragon_glyph_distance")
    self:AddComment("Note: The game only updates the distance once every 5 seconds.")

    self:AddHeader("Enmity list settings")
    self:AddCheckButton("Enable enmity list",
                        "hatelist_enable", WoWXIV.HateList.Enable)

    self:AddHeader("Fly text settings")
    self:AddCheckButton("Enable fly text (player only)", "flytext_enable",
                        WoWXIV.FlyText.Enable)
    self:AddCheckButton("Hide loot frame when autolooting",
                        "flytext_hide_autoloot", nil, "flytext_enable")

    self:AddHeader("Map settings")
    self:AddCheckButton("Show current coordinates under minimap",
                        "map_show_coords_minimap",
                        function(enable) WoWXIV.Map.SetShowCoords(WoWXIV_config["map_show_coords_worldmap"], enable) end)
    self:AddCheckButton("Show mouseover coordinates on world map",
                        "map_show_coords_worldmap",
                        function(enable) WoWXIV.Map.SetShowCoords(enable, WoWXIV_config["map_show_coords_minimap"]) end)

    self:AddHeader("Party list settings")
    self:AddRadioHeader("Role/class coloring:",
                        "partylist_role_bg", WoWXIV.PartyList.Refresh)
    self:AddRadioButton("None", "partylist_colors", nil,
                        WoWXIV.PartyList.Refresh)
    self:AddRadioButton("Role color in background",
                        "partylist_colors", "role",
                        WoWXIV.PartyList.Refresh)
    self:AddRadioButton("Role color in background, class color in name",
                        "partylist_colors", "role+class",
                        WoWXIV.PartyList.Refresh)
    self:AddRadioButton("Class color in background",
                        "partylist_colors", "class",
                        WoWXIV.PartyList.Refresh)
    self:AddRadioHeader("Use narrow format (omit mana and limit buffs/debuffs):")
    self:AddRadioButton("Never", "partylist_narrow_condition", "never",
                        WoWXIV.PartyList.Refresh)
    self:AddRadioButton("Always", "partylist_narrow_condition", "always",
                        WoWXIV.PartyList.Refresh)
    self:AddRadioButton("Only in raids", "partylist_narrow_condition", "raid",
                        WoWXIV.PartyList.Refresh)
    self:AddRadioButton("Only in raids with 21+ members",
                        "partylist_narrow_condition", "raidlarge",
                        WoWXIV.PartyList.Refresh)

    self:AddHeader("Target bar settings")
    self:AddCheckButton("Hide native target frames |cffff0000(requires reload)|r",
                        "targetbar_hide_native")
    self:AddCheckButton("Show target's power bar", "targetbar_power",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Only for bosses", "targetbar_power_boss_only",
                        WoWXIV.TargetBar.Refresh, "targetbar_power")
    self:AddCheckButton("Show all debuffs on target bar",
                        "targetbar_target_all_debuffs",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Except in raids",
                        "targetbar_target_all_debuffs_not_raid",
                        WoWXIV.TargetBar.Refresh,
                        "targetbar_target_all_debuffs")
    self:AddCheckButton("Show all debuffs on focus bar",
                        "targetbar_focus_all_debuffs",
                        WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Except in raids",
                        "targetbar_focus_all_debuffs_not_raid",
                        WoWXIV.TargetBar.Refresh,
                        "targetbar_focus_all_debuffs")
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
                 "Author: vaxherd")

    f:SetHeight(-self.y + 10)
end

------------------------------------------------------------------------

-- Initialize configuration data and create the configuration window.
function WoWXIV.Config.Create()
    for k, v in pairs(CONFIG_DEFAULT) do
        if WoWXIV_config[k] == nil then
            WoWXIV_config[k] = v
        end
    end

    local config_frame = ConfigFrame()
    WoWXIV.Config.frame = config_frame
    local f = config_frame.native_frame

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
    InterfaceOptionsFrame_OpenToCategory(WoWXIV.Config.category)
end
