local _, WoWXIV = ...
WoWXIV.Map = {}

local class = WoWXIV.class
local strformat = string.format
local GetBestMapForUnit = C_Map.GetBestMapForUnit
local GetPlayerMapPosition = C_Map.GetPlayerMapPosition

---------------------------------------------------------------------------

local CoordinatesFrame = class()

-- Pass in the parent frame, and a function which returns either
-- (1) the X and Y coordinates to display or (2) nil to hide the display.
function CoordinatesFrame:__constructor(parent, coord_source)
    self.coord_source = coord_source
    self.text_x = ""
    self.text_y = ""

    local f = CreateFrame("Frame", "WoWXIV_CoordinatesFrame", parent)
    self.frame = f
    f:SetSize(116, 19)

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

function CoordinatesFrame:SetFrameStrata(...)
    self.frame:SetFrameStrata(...)
end

function CoordinatesFrame:SetPoint(...)
    self.frame:SetPoint(...)
end

function CoordinatesFrame:Enable(enable)
    local f = self.frame
    if enable then
        f:Show()
        f:SetScript("OnUpdate", function() self:OnUpdate() end)
    else
        f:Hide()
        f:SetScript("OnUpdate", nil)
    end
end

function CoordinatesFrame:OnUpdate()
    local f = self.frame
    if not f:IsVisible() then return end

    local x, y = self.coord_source()
    if not x then
        f:SetAlpha(0)
        return
    end
    f:SetAlpha(1)
       
    local str_x = strformat("X:%.1f", x)
    local str_y = strformat("Y:%.1f", y)
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

local MapOverlay = class()

function MapOverlay:__constructor()
    self.enabled = false
    self.map_shown = false

    local f = CoordinatesFrame(WorldMapFrame, MapOverlay.GetCoords)
    self.frame = f
    f:SetFrameStrata("HIGH")
    f:SetPoint("BOTTOM", WorldMapFrame.ScrollContainer, "BOTTOM", 0, 5)

    WorldMapFrame:HookScript("OnShow", function() self:OnShowMap() end)
    WorldMapFrame:HookScript("OnHide", function() self:OnHideMap() end)
end

function MapOverlay:Enable(enable)
    self.enabled = enable
    self.frame:Enable(self.enabled and self.map_shown)
end

function MapOverlay:OnShowMap()
    self.map_shown = true
    self.frame:Enable(self.enabled and self.map_shown)
end

function MapOverlay:OnHideMap()
    self.map_shown = false
    self.frame:Enable(false)
end

function MapOverlay:GetCoords()
    if not WorldMapFrame.ScrollContainer:IsMouseOver() then
        return nil
    end
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    if x < 0 or x >= 0.9995 or y < 0 or y >= 0.9995 then
        return nil
    end
    return x*100, y*100
end

---------------------------------------------------------------------------

local MinimapOverlay = class()

function MinimapOverlay:__constructor()
    local f = CoordinatesFrame(MinimapBackdrop, MinimapOverlay.GetCoords)
    self.frame = f
    f:SetPoint("TOP", MinimapBackdrop, "BOTTOM", 0, 8)
end

function MinimapOverlay:Enable(enable)
    self.frame:Enable(enable)
end

function MinimapOverlay:GetCoords()
    local map = GetBestMapForUnit("player")
    if not map then return end  -- May happen while teleporting between zones.
    local pos = GetPlayerMapPosition(map, "player")
    if not pos then return nil end  -- No position returned in dungeons.
    return pos.x*100, pos.y*100
end

---------------------------------------------------------------------------

function WoWXIV.Map.Init()
    WoWXIV.Map.map_overlay = MapOverlay()
    WoWXIV.Map.minimap_overlay = MinimapOverlay()
    WoWXIV.Map.SetShowCoords(WoWXIV_config["map_show_coords_worldmap"],
                             WoWXIV_config["map_show_coords_minimap"])
end

function WoWXIV.Map.SetShowCoords(show_worldmap, show_minimap)
    WoWXIV.Map.map_overlay:Enable(show_worldmap)
    WoWXIV.Map.minimap_overlay:Enable(show_minimap)
end
