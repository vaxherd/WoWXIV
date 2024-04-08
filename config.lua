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
config_default["map_show_coords"] = true

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
    self.y = self.y - 15
    label:SetTextScale(1.2)
    label:SetText(text)
end

function ConfigFrame:AddComment(text)
    local f = self.native_frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.y = self.y - 5
    label:SetPoint("TOPLEFT", self.x+40, self.y)
    self.y = self.y - 10
    label:SetTextColor(1, 0.5, 0)
    label:SetText(text)
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
    self.y = self.y - 20
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    button:SetChecked(WoWXIV_config[setting])
    button:SetScript("OnClick", function(self)
        local new_value = not WoWXIV_config[setting]
        WoWXIV_config[setting] = new_value
        self:SetChecked(new_value)
        if on_change then on_change(new_value) end
    end)
end

-- We don't have any of these at the moment, but in case we add some later:
function ConfigFrame:AddRadioButton(text, setting, value, on_change)
    local f = self.native_frame
    local button = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
    self.y = self.y - 10
    button:SetPoint("TOPLEFT", self.x+10, self.y)
    self.y = self.y - 20
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
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
    self:AddCheckButton("Enable fly text (player only)",
                       "flytext_enable", WoWXIV.FlyText.Enable)
    self:AddCheckButton(1, "Hide loot frame when autolooting",
                       "flytext_hide_autoloot")

    self:AddHeader("Map settings")
    self:AddCheckButton("Show current coordinates under minimap",
                       "map_show_coords", WoWXIV.Map.SetShowCoords)

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

    f:SetHeight(-self.y)
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
        container:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -26, 0)
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
