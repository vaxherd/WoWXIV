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
function WoWXIV_CreateEventFrame(name, parent)
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
function WoWXIV_DestroyFrame(frame)
    frame:SetParent(nil)
    frame:Hide()
end
