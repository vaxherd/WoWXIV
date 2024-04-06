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

-- Destroy the given frame.
-- Because the WoW API does not seem to have a function to actually
-- destroy a frame (FIXME: does it?), we instead reparent to nil and
-- explicitly hide the window, under the assumption that that will
-- remove all external references to the frame and allow it to be
-- garbage-collected.
--
-- Parameters:
--     frame: Frame to destroy.
function WoWXIV.DestroyFrame(frame)
    frame:SetParent(nil)
    frame:Hide()
    frame:UnregisterAllEvents()
end

-- Hide a frame created by the Blizzard UI, under the assumption it will
-- be replaced by a custom UI frame.
function WoWXIV.HideBlizzardFrame(frame)
    frame:UnregisterAllEvents()
    frame:Hide()
    function frame:Show() end
    function frame:SetShown() end
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
