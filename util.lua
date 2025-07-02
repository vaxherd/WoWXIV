local _, WoWXIV = ...

local floor = math.floor

------------------------------------------------------------------------
-- Timing routines
------------------------------------------------------------------------

-- Used by timePrecise(), see details below.
local timePrecise_last_time = nil
local timePrecise_last_GetTime = nil
local timePrecise_offset = nil

-- Return the current Unix time with sub-second precision.
--
-- Because Lua's time() only has second precision, and the WoW function
-- GetTime() (which has millisecond precision) uses system uptime rather
-- than Unix time, we estimate the offset between GetTime() timestamps
-- and true time-of-day timestamps, and apply that offset to the return
-- value of GetTime() to obtain a sub-second value to add to the time()
-- result.
--
-- Values returned by this function will always be monotonically
-- increasing (provided the system's time-of-day clock is not changed).
-- If necessary, the sub-second offset will be adjusted to ensure
-- monotonicity, so calls for the first second of runtime may have an
-- inaccurate sub-second part.
function WoWXIV.timePrecise()
    local now_time = time()
    local now_GetTime = GetTime()

    if not timePrecise_last_time then  -- First call?
        timePrecise_last_time = now_time
        timePrecise_last_GetTime = now_GetTime
        -- Assume that the time-of-day timestamp just changed (this will
        -- ensure monotonicity during the first second, at the cost of a
        -- likely jump in timestamp when we hit the next second.
        timePrecise_offset = select(2, math.modf(now_GetTime))
        -- Wait until the time() timestamp changes, and make a better estimate.
        local function EstimateOffset()
            if time() == now_time then
                RunNextFrame(EstimateOffset)
            else
                local _ = WoWXIV.timePrecise()  -- Call for side effects.
            end
        end
        RunNextFrame(EstimateOffset)
    end

    local last_time = timePrecise_last_time
    local last_GetTime = timePrecise_last_GetTime
    timePrecise_last_time = now_time
    timePrecise_last_GetTime = now_GetTime
    local now_subsec = select(2, math.modf(now_GetTime))
    local last_subsec = select(2, math.modf(last_GetTime))
    local now_adjusted =
        select(2, math.modf((now_subsec + 1) - timePrecise_offset))
    local last_adjusted =
        select(2, math.modf((last_subsec + 1) - timePrecise_offset))
    if now_time == last_time then
        -- The integral timestamp is unchanged, so the sub-second portion
        -- must be increasing.  (Since we overestimate the initial offset,
        -- this should never be violated except possibly as a result of
        -- rounding error.)
        if now_adjusted < last_adjusted then
            -- Wait at x.999 until the next second.
            timePrecise_offset = select(2, math.modf((now_subsec + 1) - 0.999))
        end
    elseif now_time > last_time then
        -- The integral timestamp has advanced.  If this is not the result
        -- of a system clock change, the GetTime() delta should be within
        -- 1 second (on either side) of the time() delta.  Use that to
        -- adjust our estimate of the offset.
        local delta_time = now_time - last_time
        local delta_GetTime = now_GetTime - last_GetTime
        if delta_GetTime > delta_time-1 and delta_GetTime < delta_time+1 then
            if delta_GetTime < delta_time and now_adjusted > last_adjusted then
                -- We overestimated the offset, so push it back to the
                -- current fractional timestamp (treating "now" as .000).
                timePrecise_offset = now_subsec
            elseif delta_GetTime > delta_time and now_adjusted < last_adjusted then
                -- We underestimated the offset.  As above, this should never
                -- occur except due to rounding.
                timePrecise_offset =
                    select(2, math.modf((now_subsec + 1) - 0.999))
            end
        end
    else
        -- The integral timestamp has moved backwards, presumably as the
        -- result of a system clock change, so we can't learn any
        -- additional information.  Just assume the offset is unchanged.
    end

    local final_subsec =
        select(2, math.modf((now_subsec + 1) - timePrecise_offset))
    return now_time + final_subsec
end

-- Perform an initial call to kickstart the offset estimation.
local _ = WoWXIV.timePrecise()

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
    hooksecurefunc(frame, "Show", frame.Hide)
    hooksecurefunc(frame, "SetShown",
                   function(f,show) if show then f:Hide() end end)
end

------------------------------------------------------------------------
-- Text formatting routines
------------------------------------------------------------------------

-- Helper for FormatColoredText().
local function ColorTo255(v)
    return floor((v<0 and 0 or v>1 and 1 or v) * 255 + 0.5)
end

-- Return the given string enclosed in markup codes for the given color.
-- The color can be expressed as:
--    * Normalized red, green, and blue component values
--    * A table of normalized component values ({red, green, blue})
--    * A 6-digit hexadecimal string of component values ("RRGGBB")
function WoWXIV.FormatColoredText(text, r, g, b)
    local hex
    if type(r) == "string" then
        hex = r
    else
        if type(r) == "table" then
            r, g, b = unpack(r)
        end
        hex = ("%02X%02X%02X"):format(
            ColorTo255(r), ColorTo255(g), ColorTo255(b))
    end
    return ("|cFF%s%s|r"):format(hex, text)
end

-- Return a markup string containing the given text in the color for the
-- given item quality.
function WoWXIV.FormatItemColor(text, quality)
    return ("|cnIQ%d:%s|r"):format(quality, text)
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

-- Call a function with a specified environment, restoring the function's
-- original environment afterward.  Only the first return value (if any)
-- is passed up to the caller.  Note that as of 11.1.7, setting the
-- environment for a function does not in itself appear to taint the
-- function (though of course taint will be passed in via the execution
-- path).
function WoWXIV.envcall(env, fn, ...)
    local saved_env = getfenv(fn)
    setfenv(fn, env)
    local retval = fn(...)
    setfenv(fn, saved_env)
    return retval
end
