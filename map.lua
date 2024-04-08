local _, WoWXIV = ...
WoWXIV.Map = {}

local class = WoWXIV.class
local strformat = string.format
local GetBestMapForUnit = C_Map.GetBestMapForUnit
local GetPlayerMapPosition = C_Map.GetPlayerMapPosition

---------------------------------------------------------------------------

local MinimapOverlay = class()

function MinimapOverlay:__constructor()
    self.text_x = ""
    self.text_y = ""

    local f = CreateFrame("Frame", "WoWXIV_MinimapOverlay", MinimapBackdrop)
    self.frame = f
    f:SetSize(116, 19)
    f:SetPoint("TOP", f:GetParent(), "BOTTOM", 0, 8)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    self.bg = bg
    bg:SetAllPoints(f)
    bg:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    bg:SetTexCoord(0, 1, 0/256.0, 11/256.0)
    bg:SetVertexColor(0, 0, 0, 0.75)

    local label_x = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label_x = label_x
    label_x:SetPoint("RIGHT", f, "CENTER", -3, -0.5)

    local label_y = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label_y = label_y
    label_y:SetPoint("LEFT", f, "CENTER", 3, -0.5)
end

function MinimapOverlay:Enable(enable)
    local f = self.frame
    if enable then
        f:Show()
        f:SetScript("OnUpdate", function() self:OnUpdate() end)
    else
        f:Hide()
        f:SetScript("OnUpdate", nil)
    end
end

function MinimapOverlay:OnUpdate()
    if not self.frame:IsVisible() then return end

    local map = GetBestMapForUnit("player")
    local pos = GetPlayerMapPosition(map, "player")
    local str_x = strformat("X:%.1f", pos.x*100)
    local str_y = strformat("Y:%.1f", pos.y*100)
    if str_x ~= self.text_x then
        self.text_x = str_x
        self.label_x:SetText(str_x)
    end
    if str_y ~= self.text_y then
        self.text_y = str_y
        self.label_y:SetText(str_y)
    end
end

---------------------------------------------------------------------------

function WoWXIV.Map.Init()
    WoWXIV.Map.minimap_overlay = MinimapOverlay()
    WoWXIV.Map.SetShowCoords(WoWXIV_config["map_show_coords"])
end

function WoWXIV.Map.SetShowCoords(show)
    WoWXIV.Map.minimap_overlay:Enable(show)
end
