local WoWXIV = WoWXIV
WoWXIV.Config = {}

------------------------------------------------------------------------

local config_default = {}

-- Confirm/cancel buttons.
-- PAD1 is the south button (Microsoft A, Nintendo B, Sony cross)
-- PAD2 is the east button (Microsoft B, Nintendo A, Sony circle)
config_default["confirm_button"] = "PAD2"
config_default["cancel_button"] = "PAD1"

-- Target bar: display focus (if it exists) instead of target?
config_default["targetbar_hide_native"] = true
config_default["targetbar_show_focus"] = false

-- Fly text: enable?
config_default["flytext_enable"] = true

------------------------------------------------------------------------

local function AddHeader(f, x, y, text)
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    label:SetPoint("TOPLEFT", x, y)
    label:SetTextScale(1.2)
    label:SetText(text)
    return label
end

local function AddCheckButton(f, x, y, text)
    local button = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    return button
end

local function AddRadioButton(f, x, y, text)
    local button = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    return button
end

-- Initialize configuration data and create the configuration window.
function WoWXIV.Config.Create()
    for k, v in pairs(config_default) do
        if WoWXIV_config[k] == nil then
            WoWXIV_config[k] = v
        end
    end

    local f = WoWXIV.CreateEventFrame("WoWXIV_Config")
    WoWXIV.Config.frame = f

    local y = -10

    AddHeader(f, 10, y, "Confirm button type")
    y = y - 30

    f.button_confirm_type_east = AddRadioButton(f, 20, y, "Nintendo style")
    f.button_confirm_type_east:SetChecked(WoWXIV_config["confirm_button"] == "PAD2")
    f.button_confirm_type_east:SetScript("OnClick", function(self)
        self:GetParent():SetConfirmType(true)
    end)
    y = y - 20

    f.button_confirm_type_south = AddRadioButton(f, 20, y, "Microsoft style")
    f.button_confirm_type_south:SetChecked(WoWXIV_config["confirm_button"] == "PAD1")
    f.button_confirm_type_south:SetScript("OnClick", function(self)
        self:GetParent():SetConfirmType(false)
    end)
    y = y - 20

    y = y - 20
    AddHeader(f, 10, y, "Target bar settings")
    y = y - 30

    f.button_targetbar_hide_native = AddCheckButton(f, 20, y, "Hide native target frame")
    f.button_targetbar_hide_native:SetChecked(WoWXIV_config["targetbar_hide_native"])
    f.button_targetbar_hide_native:SetScript("OnClick", function(self)
        self:GetParent():SetTargetBarHideNative(not WoWXIV_config["targetbar_hide_native"])
    end)
    y = y - 30

    f.button_targetbar_show_focus = AddCheckButton(f, 20, y, "Show focus target when one is selected")
    f.button_targetbar_show_focus:SetChecked(WoWXIV_config["targetbar_show_focus"])
    f.button_targetbar_show_focus:SetScript("OnClick", function(self)
        self:GetParent():SetTargetBarShowFocus(not WoWXIV_config["targetbar_show_focus"])
    end)
    y = y - 30

    y = y - 20
    AddHeader(f, 10, y, "Fly text settings")
    y = y - 30

    f.button_flytext_enable = AddCheckButton(f, 20, y, "Enable fly text (player only)")
    f.button_flytext_enable:SetChecked(WoWXIV_config["flytext_enable"])
    f.button_flytext_enable:SetScript("OnClick", function(self)
        self:GetParent():SetFlyTextEnable(not WoWXIV_config["flytext_enable"])
    end)
    y = y - 30

    -- Required by the settings API:
    function f:OnCommit()
    end
    function f:OnDefault()
        f:SetConfirmType(true)
        f:SetTargetBarHideNative(true)
        f:SetTargetBarShowFocus(false)
        f:SetFlyTextEnable(true)
    end
    function f:OnRefresh()
    end

    function f:SetConfirmType(is_east)
        self.button_confirm_type_east:SetChecked(false)
        self.button_confirm_type_south:SetChecked(false)
        if is_east then
            self.button_confirm_type_east:SetChecked(true)
            WoWXIV_config["confirm_button"] = "PAD2"
            WoWXIV_config["cancel_button"] = "PAD1"
        else
            self.button_confirm_type_south:SetChecked(true)
            WoWXIV_config["confirm_button"] = "PAD1"
            WoWXIV_config["cancel_button"] = "PAD2"
        end
    end

    function f:SetTargetBarHideNative(hide)
        self.button_targetbar_hide_native:SetChecked(hide)
        WoWXIV_config["targetbar_hide_native"] = hide
    end

    function f:SetTargetBarShowFocus(show)
        self.button_targetbar_show_focus:SetChecked(show)
        WoWXIV_config["targetbar_show_focus"] = show
    end

    function f:SetFlyTextEnable(enable)
        self.button_flytext_enable:SetChecked(enable)
        WoWXIV_config["flytext_enable"] = enable
        WoWXIV.FlyText.Enable(enable)
    end

    local category = Settings.RegisterCanvasLayoutCategory(f, "WoWXIV")
    WoWXIV.Config.category = category
    category.ID = "WoWXIV"
    Settings.RegisterAddOnCategory(category)
end

-- Open the addon configuration window.
function WoWXIV.Config.Open()
    InterfaceOptionsFrame_OpenToCategory(WoWXIV.Config.category)
end

------------------------------------------------------------------------
