local WoWXIV = WoWXIV
WoWXIV.Config = {}

------------------------------------------------------------------------

local config_default = {}

-- Confirm/cancel buttons.
-- PAD1 is the south button (Microsoft A, Nintendo B, Sony cross)
-- PAD2 is the east button (Microsoft B, Nintendo A, Sony circle)
config_default["confirm_button"] = "PAD2"
config_default["cancel_button"] = "PAD1"

------------------------------------------------------------------------

local config_frame

-- Create the configuration window.
function WoWXIV.Config.Create()
    config_frame = WoWXIV.CreateEventFrame("WoWXIV_Config")
    local f = config_frame

    f:RegisterEvent("ADDON_LOADED")
    function f:ADDON_LOADED(addon)
        if addon == "WoWXIV" then
            for k, v in pairs(config_default) do
                if WoWXIV_config[k] == nil then
                    WoWXIV_config[k] = v
                end
            end
            f:CreateSettingsUI()
        end
    end

    -- Required by the settings API:
    function f:OnCommit()
    end
    function f:OnDefault()
        f:SetConfirmType(true)
    end
    function f:OnRefresh()
    end

    function f:CreateSettingsUI()
        self.label_confirm_type = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        self.label_confirm_type:SetPoint("TOPLEFT", 10, -10)
        self.label_confirm_type:SetText("Confirm button type")

        self.button_confirm_type_east = CreateFrame("CheckButton", nil, self, "UIRadioButtonTemplate")
        self.button_confirm_type_east:SetPoint("TOPLEFT", 20, -40)
        self.button_confirm_type_east.text:SetText("Nintendo style")
        self.button_confirm_type_east:SetChecked(WoWXIV_config["confirm_button"] == "PAD2")
        self.button_confirm_type_east:SetScript("OnClick", function(self)
            self:GetParent():SetConfirmType(true)
        end)

        self.button_confirm_type_south = CreateFrame("CheckButton", nil, self, "UIRadioButtonTemplate")
        self.button_confirm_type_south:SetPoint("TOPLEFT", 20, -60)
        self.button_confirm_type_south.text:SetText("Microsoft style")
        self.button_confirm_type_south:SetChecked(WoWXIV_config["confirm_button"] == "PAD1")
        self.button_confirm_type_south:SetScript("OnClick", function(self)
            self:GetParent():SetConfirmType(false)
        end)

        local category = Settings.RegisterCanvasLayoutCategory(self, "WoWXIV")
        category.ID = "WoWXIV"
        Settings.RegisterAddOnCategory(category)
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
end

-- Open the addon configuration window.
function WoWXIV.Config.Open()
    InterfaceOptionsFrame_OpenToCategory(config_frame)
end

------------------------------------------------------------------------
