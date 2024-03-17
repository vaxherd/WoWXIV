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

    AddHeader(f, 10, -10, "Confirm button type")

    f.button_confirm_type_east = AddRadioButton(f, 20, -40, "Nintendo style")
    f.button_confirm_type_east:SetChecked(WoWXIV_config["confirm_button"] == "PAD2")
    f.button_confirm_type_east:SetScript("OnClick", function(self)
        self:GetParent():SetConfirmType(true)
    end)

    f.button_confirm_type_south = AddRadioButton(f, 20, -60, "Microsoft style")
    f.button_confirm_type_south:SetChecked(WoWXIV_config["confirm_button"] == "PAD1")
    f.button_confirm_type_south:SetScript("OnClick", function(self)
        self:GetParent():SetConfirmType(false)
    end)

    AddHeader(f, 10, -100, "Target bar settings")

    f.button_targetbar_hide_native = AddCheckButton(f, 20, -130, "Hide native target frame (requires reload)")
    f.button_targetbar_hide_native:SetChecked(WoWXIV_config["targetbar_hide_native"])
    f.button_targetbar_hide_native:SetScript("OnClick", function(self)
        self:GetParent():SetTargetBarShowFocus(not WoWXIV_config["targetbar_hide_native"])
    end)

    f.button_targetbar_show_focus = AddCheckButton(f, 20, -160, "Show focus target when one is selected")
    f.button_targetbar_show_focus:SetChecked(WoWXIV_config["targetbar_show_focus"])
    f.button_targetbar_show_focus:SetScript("OnClick", function(self)
        self:GetParent():SetTargetBarShowFocus(not WoWXIV_config["targetbar_show_focus"])
    end)

    -- Required by the settings API:
    function f:OnCommit()
    end
    function f:OnDefault()
        f:SetConfirmType(true)
        f:SetTargetBarShowFocus(true)
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
