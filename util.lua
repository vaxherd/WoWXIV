local WoWXIV = WoWXIV

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

-- Helper to deal with Show() getting called during combat via
-- the CLIENT_SCENE_CLOSED event.
local function HideBlizzardFrameHelper(frame)
    if InCombatLockdown() then
        C_Timer.After(1, function() HideBlizzardFrameHelper(frame) end)
    else
        frame:Hide()
    end
end

-- Hide a frame created by the Blizzard UI, under the assumption it will
-- be replaced by a custom UI frame.  Logic borrowed from ElvUI's
-- UF:DisableBlizzard_HideFrame().
function WoWXIV.HideBlizzardFrame(frame)
    frame:UnregisterAllEvents()
    frame:Hide()
    hooksecurefunc(frame, "Show", HideBlizzardFrameHelper)
    hooksecurefunc(frame, "SetShown", function(frame, shown)
        if shown then HideBlizzardFrameHelper(frame) end
    end)
end
