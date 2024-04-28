local _, WoWXIV = ...

local floor = math.floor

------------------------------------------------------------------------
-- Frame management routines
------------------------------------------------------------------------

-- Create a basic frame suitable for receiving events.  Any received
-- event will be passed to a same-named method on the frame, with the
-- "event" argument (giving the event name) omitted.  This function can
-- be used both for event-only (invisible) frames and for generic frames
-- which don't need to inherit from a specialized Frame subclass.
--
-- Parameters:
--     name: Global name to assign to the frame.  May be omitted or nil to
--         create an anonymous frame.
--     parent: Parent frame.  May be omitted or nil for a detached frame.
function WoWXIV.CreateEventFrame(name, parent)
    local f = CreateFrame("Frame", name, parent)
    f:SetScript("OnEvent", function(self, event, ...)
        if self[event] then
            return self[event](self, ...)
        end
    end)
    return f
end

-- Hide a frame created by the Blizzard UI, under the assumption it will
-- be replaced by a custom UI frame.
function WoWXIV.HideBlizzardFrame(frame)
    frame:UnregisterAllEvents()
    frame:Hide()
    function frame:Show() end
    function frame:SetShown() end
    function frame:Update() end
end

------------------------------------------------------------------------
-- Text formatting routines
------------------------------------------------------------------------

-- Helper for FormatColoredText().
local function ColorTo255(v)
    return floor((v<0 and 0 or v>1 and 1 or v) * 255 + 0.5)
end

-- Return the given string enclosed in formatting codes for the given
-- color (expressed as normalized red, green, and blue component values
-- or a table thereof).
function WoWXIV.FormatColoredText(text, r, g, b)
    if type(r) == "table" then
        r, g, b = unpack(r)
    end
    return ("|cFF%02X%02X%02X%s|r"):format(
        ColorTo255(r), ColorTo255(g), ColorTo255(b), text)
end

------------------------------------------------------------------------
-- Shared UI texture access
------------------------------------------------------------------------

-- Set the given Texture instance to reference the shared UI texture,
-- and optionally set the texture coordinates (as for SetUITexCoord()).
function WoWXIV.SetUITexture(texture, u0, u1, v0, v1)
    texture:SetTexture("Interface/Addons/WowXIV/textures/ui.png")
    if v1 then
        texture:SetTexCoord(u0/256.0, u1/256.0, v0/256.0, v1/256.0)
    end
end

-- Set the texture coordinate range for the given Texture instance,
-- assuming that the shared UI texture is in used.  Texture coordinates
-- are given in texels based on a 256x256-sized texture.
function WoWXIV.SetUITexCoord(texture, u0, u1, v0, v1)
    texture:SetTexCoord(u0/256.0, u1/256.0, v0/256.0, v1/256.0)
end

------------------------------------------------------------------------
-- Miscellaneous
------------------------------------------------------------------------

local CLASS_ATLAS = {rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
                     elite = "nameplates-icon-elite-gold",
                     rareelite = "nameplates-icon-elite-silver"}

-- Return the texture atlas ID of the classification icon for the given
-- unit's classification (rare, elite, etc.), or nil if no icon should
-- be displayed for the unit.  The unit must be a standard unit token
-- (like "target" or "boss1").
function WoWXIV.UnitClassificationIcon(unit)
    return CLASS_ATLAS[UnitClassification(unit)]
end
