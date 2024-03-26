local WoWXIV = WoWXIV
WoWXIV.Config = {}

-- Global config array, saved and restored by the API.
-- This is currently restored after parsing, so the value will always be
-- nil here, but we write it this way as future-proofing against values
-- being loaded sooner.
WoWXIV_Config = WoWXIV_Config or {}

------------------------------------------------------------------------

-- Default settings list.  Anything in here which is missing from
-- WoWXIV_Config after module load is inserted by the init routine.
local config_default = {}

-- Fly text: enable?
config_default["flytext_enable"] = true

-- Party list: use role colors in background?
config_default["partylist_role_bg"] = false

-- Target bar: hide the native target and focus frames?
config_default["targetbar_hide_native"] = true
-- Target bar: show only own debuffs on target bar?
config_default["targetbar_target_own_debuffs_only"] = false
-- Target bar: show only own debuffs on focus bar?
config_default["targetbar_focus_own_debuffs_only"] = false

------------------------------------------------------------------------

local ConfigFrame = {}
ConfigFrame.__index = ConfigFrame

function ConfigFrame:AddHeader(text)
    local f = self.native_frame
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    self.y = self.y - 20
    label:SetPoint("TOPLEFT", self.x, self.y)
    self.y = self.y - 30
    label:SetTextScale(1.2)
    label:SetText(text)
end

function ConfigFrame:AddCheckButton(text, setting, on_change)
    local f = self.native_frame
    local button = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", self.x+10, self.y)
    self.y = self.y - 30
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
    button:SetPoint("TOPLEFT", self.x+10, self.y)
    self.y = self.y - 30
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

function ConfigFrame:New()
    -- It sure would be nice if Lua had some syntactic sugar for this...
    local new = {}
    setmetatable(new, self)
    new.__index = self

    local f = CreateFrame("Frame", "WoWXIV_Config", nil)
    new.native_frame = f
    new.x = 10
    new.y = 10  -- Assuming an initial header.

    new:AddHeader("Fly text settings")
    new:AddCheckButton("Enable fly text (player only)",
                       "flytext_enable", WoWXIV.FlyText.Enable)

    new:AddHeader("Party list settings")
    new:AddCheckButton("Use role color in list background",
                       "partylist_role_bg", WoWXIV.PartyList.Refresh)

    new:AddHeader("Target bar settings")
    new:AddCheckButton("Hide native target frame (requires reload)",
                       "targetbar_hide_native")
    new:AddCheckButton("Show only own debuffs on target bar",
                       "targetbar_target_own_debuffs_only",
                       WoWXIV.TargetBar.Refresh)
    new:AddCheckButton("Show only own debuffs on focus bar",
                       "targetbar_focus_own_debuffs_only",
                       WoWXIV.TargetBar.Refresh)

    -- Required by the settings API:
    function f:OnCommit()
    end
    function f:OnDefault()
        -- Currently unimplemented because we had an implementation but it
        -- kept getting out of sync with the actual options.  If we add
        -- this back then we'll need to massage the button implementation
        -- a bit.
    end
    function f:OnRefresh()
    end

    return new
end

------------------------------------------------------------------------

-- Initialize configuration data and create the configuration window.
function WoWXIV.Config.Create()
    for k, v in pairs(config_default) do
        if WoWXIV_config[k] == nil then
            WoWXIV_config[k] = v
        end
    end
    local config_frame = ConfigFrame:New()
    WoWXIV.Config.frame = config_frame
    local f = config_frame.native_frame
    local category = Settings.RegisterCanvasLayoutCategory(f, "WoWXIV")
    WoWXIV.Config.category = category
    category.ID = "WoWXIV"
    Settings.RegisterAddOnCategory(category)
end

-- Open the addon configuration window.
function WoWXIV.Config.Open()
    InterfaceOptionsFrame_OpenToCategory(WoWXIV.Config.category)
end
