local _, WoWXIV = ...
WoWXIV.Config = {}

local class = WoWXIV.class

-- Global config array, saved and restored by the API.
-- This is currently restored after parsing, so the value will always be
-- nil here, but we write it this way as future-proofing against values
-- being loaded sooner.
WoWXIV_Config = WoWXIV_Config or {}

------------------------------------------------------------------------

-- Default settings list.  Anything in here which is missing from
-- WoWXIV_Config after module load is inserted by the init routine.
local config_default = {}

-- Buff bars: show distance for dragon glyph?
config_default["buffbar_dragon_glyph_distance"] = true

-- Enmity list: enable?
config_default["hatelist_enable"] = true

-- Fly text: enable?
config_default["flytext_enable"] = true
-- Fly text: if enabled, hide loot frame when autolooting?
config_default["flytext_hide_autoloot"] = true

-- Map: show current coordinates under minimap?
config_default["map_show_coords_minimap"] = true
-- Map: show mouseover coordinates on world map?
config_default["map_show_coords_worldmap"] = true

-- Party list: use role colors in background?
config_default["partylist_role_bg"] = false

-- Target bar: hide the native target and focus frames?
config_default["targetbar_hide_native"] = true
-- Target bar: show only own debuffs on target bar?
config_default["targetbar_target_own_debuffs_only"] = false
-- Target bar: show only own debuffs on focus bar?
config_default["targetbar_focus_own_debuffs_only"] = false
-- Target bar: move top-center info widget to bottom right?
config_default["targetbar_move_top_center"] = true

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

-- Call as: AddCheckButton([indent,] text, setting, on_change)
function ConfigFrame:AddCheckButton(arg1, ...)
    local indent, text, setting, on_change
    if type(arg1) == "number" then
        indent = arg1
        text, setting, on_change = ...
    else
        indent = 0
        text = arg1
        setting, on_change = ...
    end
    local f = self.native_frame
    local button = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    self.y = self.y - 10
    button:SetPoint("TOPLEFT", self.x+10+30*indent, self.y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    self.y = self.y - 20
    button:SetChecked(WoWXIV_config[setting])
    button:SetScript("OnClick", function(self)
        local new_value = not WoWXIV_config[setting]
        WoWXIV_config[setting] = new_value
        self:SetChecked(new_value)
        if on_change then on_change(new_value) end
    end)
    return button
end

-- We don't have any of these at the moment, but in case we add some later:
function ConfigFrame:AddRadioButton(text, setting, value, on_change)
    local f = self.native_frame
    local button = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
    self.y = self.y - 10
    button:SetPoint("TOPLEFT", self.x+10, self.y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    self.y = self.y - 20
    button:SetChecked(WoWXIV_config[setting] == value)
    button.WoWXIV_value = value
    f.WoWXIV_radio_buttons = f.WoWXIV_radio_buttons or {}
    f.WoWXIV_radio_buttons[setting] = f.WoWXIV_radio_buttons[setting] or {}
    tinsert(f.WoWXIV_radio_buttons[setting], button)
    button:SetScript("OnClick", function(self)
        WoWXIV_config[setting] = value
        self:SetChecked(true)
        for _, other in ipairs(f.WoWXIV_radio_buttons) do
            if other.WoWXIV_value ~= value then
                other.SetChecked(false)
            end
        end
        if on_change then on_change(new_value) end
    end)
    return button
end

function ConfigFrame:__constructor()
    local f = CreateFrame("Frame", "WoWXIV_Config")
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
                        function(enable) self:SetEnableFlyText(enable) end)
    self.flytext_hide_autoloot_button =
        self:AddCheckButton(1, "Hide loot frame when autolooting",
                           "flytext_hide_autoloot")

    self:AddHeader("Map settings")
    self:AddCheckButton("Show current coordinates under minimap",
                       "map_show_coords_minimap",
                       function(enable) WoWXIV.Map.SetShowCoords(WoWXIV_config["map_show_coords_worldmap"], enable) end)
    self:AddCheckButton("Show mouseover coordinates on world map",
                       "map_show_coords_worldmap",
                       function(enable) WoWXIV.Map.SetShowCoords(enable, WoWXIV_config["map_show_coords_minimap"]) end)

    self:AddHeader("Party list settings")
    self:AddCheckButton("Use role color in list background",
                       "partylist_role_bg", WoWXIV.PartyList.Refresh)

    self:AddHeader("Target bar settings")
    self:AddCheckButton("Hide native target frame |cffff0000(requires reload)|r",
                       "targetbar_hide_native")
    self:AddCheckButton("Show only own debuffs on target bar",
                       "targetbar_target_own_debuffs_only",
                       WoWXIV.TargetBar.Refresh)
    self:AddCheckButton("Show only own debuffs on focus bar",
                       "targetbar_focus_own_debuffs_only",
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
                 "Author: vaxherd")

    f:SetHeight(-self.y + 10)

    -- Set dependent option sensitivity appropriately.
    self:SetEnableFlyText(WoWXIV_config["flytext_enable"])
end

function ConfigFrame:SetEnableFlyText(enable)
    WoWXIV.FlyText.Enable(enable)
    self.flytext_hide_autoloot_button:SetEnabled(enable)
    -- SetEnabled() doesn't change the text color, so we have to do
    -- that manually.
    self.flytext_hide_autoloot_button.text:SetTextColor(
        (enable and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
end

------------------------------------------------------------------------

-- Initialize configuration data and create the configuration window.
function WoWXIV.Config.Create()
    for k, v in pairs(config_default) do
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
