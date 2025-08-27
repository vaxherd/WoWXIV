local _, WoWXIV = ...

local class = WoWXIV.class
local set = WoWXIV.set

local floor = math.floor
local max = math.max
local strfind = string.find
local strgsub = string.gsub
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end

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
-- Button auto-repeat manager class
------------------------------------------------------------------------

-- Auto-repeat delay and period, in seconds.
local CURSOR_REPEAT_DELAY = 300/1000
local CURSOR_REPEAT_PERIOD = 50/1000

local ButtonRepeatManager = class()
WoWXIV.ButtonRepeatManager = ButtonRepeatManager

-- Set auto-repeat state for a newly pressed button.  Does nothing if the
-- button is already being repeated, so that the caller does not need to
-- distinguish between an initial press and a repeated press.
function ButtonRepeatManager:StartRepeat(button)
    if self.repeat_button ~= button then
        self.repeat_button = button
        self.repeat_next = GetTime() + CURSOR_REPEAT_DELAY
    end
end

-- Clear auto-repeat state.
function ButtonRepeatManager:StopRepeat()
    self.repeat_button = nil
end

-- Return the button currently being auto-repeated, nil if none.
function ButtonRepeatManager:GetRepeatButton()
    return self.repeat_button
end

-- Check for button auto-repeat.  If an auto-repeat input has been
-- generated, call the given callback function, passing the button name
-- as the sole argument.
function ButtonRepeatManager:CheckRepeat(callback)
    if self.repeat_button then
        local now = GetTime()
        if now >= self.repeat_next then
            -- Note that we add the period to the nominal timestamp of the
            -- repeat event, not the actual current timestamp, to ensure a
            -- consistent average interval regardless of fluctuations in
            -- the game's refresh rate.
            self.repeat_next = self.repeat_next + CURSOR_REPEAT_PERIOD
            callback(self.repeat_button)
        end
    end
end

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

-- Show a confirmation message with optional checkbox.  If check_text is
-- not nil, a checkbox with that text will be inserted under the primary
-- popup text, and the "accept" option will be disabled until it is checked.
--
-- Parameters:
--     text: Primary popup text.
--     check_text: Checkbox text, or nil for no checkbox.
--     accept_text: Text for the "accept" button.
--     cancel_text: Text for the "cancel" button.
--     accept_cb: Callback function for the "accept" button.
--     cancel_cb: Callback function for the "cancel" button.  Also called
--         if the dialog is closed or suppressed.  May be nil.
function WoWXIV.ShowConfirmation(text, check_text, accept_text,
                                 cancel_text, accept_cb, cancel_cb)
    assert(type(text) == "string")
    assert(check_text == nil or type(check_text) == "string")
    assert(type(accept_text) == "string")
    assert(type(cancel_text) == "string")
    assert(type(accept_cb) == "function")
    assert(cancel_cb == nil or type(cancel_cb) == "function")
    assert(not StaticPopupDialogs[id])

    local wrapper = WoWXIV._ShowStaticPopup_check_wrapper
    if not wrapper then
        wrapper = CreateFrame("Frame")
        WoWXIV._ShowStaticPopup_check_wrapper = wrapper
        local button = CreateFrame(
            "CheckButton", "WoWXIV_StaticPopupCheckButton", wrapper,
            "UICheckButtonTemplate")
        WoWXIV._ShowStaticPopup_check_button = button
        button.text:SetFontObject("GameFontHighlight")
        button:SetPoint("LEFT")
    end
    wrapper:SetShown(check_text ~= nil)

    local data = {
        text = text,
        check_text = check_text,
        accept_text = accept_text,
        cancel_text = cancel_text,
        accept_cb = accept_cb,
        cancel_cb = cancel_cb,
    }
    StaticPopup_Show("WOWXIV_CONFIRMATION", nil, nil, data,
                     check_text and wrapper)
end

-- Similar to GENERIC_CONFIRMATION, but adjusted for our purposes.
StaticPopupDialogs["WOWXIV_CONFIRMATION"] = {
    text = "",
    button1 = "",
    button2 = "",
    OnAccept = function(self, data)
        data.accept_cb()
    end,
    OnCancel = function(self, data)
        if data.cancel_cb then data.cancel_cb() end
    end,
    OnShow = function(self, data)
        self:SetText(data.text)
        self:GetButton1():SetText(data.accept_text)
        self:GetButton2():SetText(data.cancel_text)
        if data.check_text then
            local button = WoWXIV._ShowStaticPopup_check_button
            button.text:SetText(data.check_text)
            button:GetParent():SetWidth(button:GetWidth() + button.text:GetStringWidth())
            button:GetParent():SetHeight(max(button:GetHeight(), button.text:GetStringHeight()))
            button:SetChecked(false)
            button:SetScript("OnClick", function()
                self:GetButton1():SetEnabled(button:GetChecked())
            end)
            self:GetButton1():Disable()
        end
    end,
    OnHide = function(self, data)
        local button = WoWXIV._ShowStaticPopup_check_button
        button:SetScript("OnClick", nil)
    end,
    timeout = 0,
    hideOnEscape = true,
}

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
-- Equivalent to the WrapTextInColorCode() method on predefined color
-- objects like RED_FONT_COLOR.
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
function WoWXIV.SetUITexture(texture, ...)
    texture:SetTexture("Interface/Addons/WowXIV/textures/ui.png")
    if select("#", ...) >= 4 then
        WoWXIV.SetUITexCoord(texture, ...)
    end
end

-- Set the texture coordinate range for the given Texture instance,
-- assuming that the shared UI texture is in used.  Texture coordinates
-- are given in texels based on a 256x256-sized texture.
function WoWXIV.SetUITexCoord(texture, ...)
    local w = 256.0
    local h = 256.0
    if select("#", ...) == 8 then
        local u0, v0, u1, v1, u2, v2, u3, v3 = ...
        texture:SetTexCoord(u0/w, v0/h, u1/w, v1/h, u2/w, v2/h, u3/w, v3/h)
    else
        local u0, u1, v0, v1 = ...
        texture:SetTexCoord(u0/w, u1/w, v0/h, v1/h)
    end
end

------------------------------------------------------------------------
-- Convenience operations
------------------------------------------------------------------------

-- Return true iff func(arg) returns a true value for every argument.
-- If the function does not return pure boolean values, the return value
-- is undefined except in that its truth value is as described above.
-- Essentially reduce(and, map(func, ...)).
function WoWXIV.all(func, ...)
    for i = 1, select("#", ...) do
        local arg = select(i, ...)  -- Isolate the single argument.
        if not func(arg) then return false end
    end
    return true
end

-- Equivalent of all(), accepting a table instead of a varargs list.
function WoWXIV.allt(func, table)
    for _, value in pairs(table) do
        if not func(value) then return false end
    end
    return true
end

-- Return true iff func(arg) returns a true value for any argument.
-- If the function does not return pure boolean values, the return value
-- is undefined except in that its truth value is as described above.
-- Essentially reduce(or, map(func, ...)).
function WoWXIV.any(func, ...)
    for i = 1, select("#", ...) do
        local arg = select(i, ...)  -- Isolate the single argument.
        if func(arg) then return true end
    end
    return false
end

-- Equivalent of any(), accepting a table instead of a varargs list.
function WoWXIV.anyt(func, table)
    for _, value in pairs(table) do
        if func(value) then return true end
    end
    return false
end

-- Return the return value of the given function applied to each argument.
function WoWXIV.map(func, ...)
    -- Lua can't manage the functional-style tail-recursive approach
    -- without quadratic-time lossage, so we just pack and unpack.
    -- As a corollary, if the values are in a table to begin with, it's
    -- faster to call mapt() and unpack the result than to unpack the
    -- input table as arguments to this function.
    return unpack(WoWXIV.mapt(func, {...}))
end

-- Return a table containing the return value of the given function
-- applied to each element of the input table.
function WoWXIV.mapt(func, table)
    local result = {}
    for k, v in pairs(table) do
        result[k] = func(v)
    end
    return result
end

-- Return a table containing the return value of the given function
-- applied to each integer in the given range.  |range| may be specified
-- one of two ways:
--    maptn(func, start, end)  -- iterates from start to end inclusive
--    maptn(func, end)         -- equivalent to maptn(func, 1, end)
-- As a special case, if |func| is a string, each entry in the returned
-- table is that string with all occurrences of "%n" replaced by the key.
-- Analogous to the Perl idiom "map {&func($_)} ($start..$end)".
function WoWXIV.maptn(func, range, ...)
    if type(func) == "string" then
        local s = func
        func = function(n) return strgsub(s, "%%n", n) end
    end
    local startval, endval = range, ...
    if not endval then
        startval, endval = 1, range
    end
    -- Note that even for the case of startval==1, there's no measurable
    -- performance benefit to preallocating the array with table.create().
    local result = {}
    for i = startval, endval do
        result[i] = func(i)
    end
    return result
end

-- Helper to create an overlay environment table for envcall() or deepcall().
-- Pass a table of overlay values; the table will be modified as appropriate
-- for passing as the "env" argument to those functions and returned.  Note
-- that the returned table is "closed": attempts to store to it (except via
-- rawset()) will write to the global environment instead!  Make sure the
-- table is complete before passing it to this function.
local makefenv_hack_names  -- Defined below.
function WoWXIV.makefenv(env)
    -- HACK: Some native code seems to rely on having mixin tables present
    -- directly in the function environment (i.e., not via __index lookup),
    -- so we have to add those to not get an "unable to find mixin" error.
    -- See:
    --     https://github.com/Stanzilla/WoWUIBugs/issues/589
    --     https://github.com/WeakAuras/WeakAuras2/pull/5221
    for _, name in ipairs(makefenv_hack_names) do
        env[name] = _G[name]
    end
    return setmetatable(env, {__index = _G, __newindex = _G})
end
-- NOTE: Make sure _frame.lua is kept in sync with this list!
makefenv_hack_names = {
    "ColorMixin",
    "ItemLocationMixin",
    "ItemTransmogInfoMixin",
    "PlayerLocationMixin",
    "TransmogLocationMixin",
    "TransmogPendingInfoMixin",
    "Vector2DMixin",
    "Vector3DMixin",
}

-- Call a function with a specified environment, restoring the function's
-- original environment afterward.  Only the first return value (if any)
-- is passed up to the caller.  For an "overlay"-type environment, make
-- sure to set a metatable on the environment table with {__index = _G} so
-- non-overlaid global symbols work as usual.
--
-- The environment will _only_ apply to the specified function, and will
-- _not_ be passed down to any functions it calls (i.e., lexical scoping).
-- For a dynamically scoped environment override, see deepcall().
--
-- Note that as of 11.1.7, setting the environment for a function does not
-- in itself appear to taint the function (though of course taint will be
-- passed in via the execution path).
function WoWXIV.envcall(env, func, ...)
    local saved_env = getfenv(func)
    setfenv(func, env)
    local retval = func(...)
    setfenv(func, saved_env)
    return retval
end

-- Call a function with a specified environment, restoring the function's
-- original environment afterward.  Only the first return value (if any)
-- is passed up to the caller.
--
-- Unlike envcall(), this function applies the environment to all code
-- called from the given function (i.e., dynamic scoping), to the degree
-- possible.  Note that Lua does not allow lookup of function upvalues
-- (such as values declared "local" in the relevant module), except via
-- the debug library which is not available in WoW, so locally-declared
-- functions called by local name will not see the replaced environment,
-- and the environment cannot replace locally-declared variables when
-- those variables are referenced by local name.
--
-- Because Lua does not natively support dynamic scoping, this script-side
-- implementation is fairly CPU-intensive, and it should be used only when
-- necessary.
function WoWXIV.deepcall(env, func, ...)
    local getmetatable, setmetatable, type = getmetatable, setmetatable, type

    -- Environment manipulation helpers.  We accomplish dynamic scoping by
    -- inserting a wrap call on every table lookup via __index (including
    -- the environment table) and table member addition via __newindex,
    -- and individually wrap existing table members when a table is first
    -- encountered.
    local wrapped_tables = {}
    local wrapped_funcs = {}
    local wrap_value  -- Forward declaration.
    local function make_index(index)
        if type(index) == "function" then
            return function(t, k) return wrap_value(index(t, k)) end
        elseif index ~= nil then
            return function(t, k) return wrap_value(index[k]) end
        else
            return nil
        end
    end
    local function make_newindex(newindex)
        if type(newindex) == "function" then
            return function(t, k, v) newindex(t, k, wrap_value(v)) end
        elseif newindex ~= nil then
            return function(t, k, v) newindex[k] = wrap_value(v) end
        else
            return function(t, k, v) rawset(t, k, wrap_value(v)) end
        end
    end
    local function wrap_func(f)
        if not wrapped_funcs[f] then
            local old_env = getfenv(f)
            local success, error = pcall(setfenv, f, env)
            if success then
                wrapped_funcs[f] = old_env
            elseif not strstr(error, "cannot change env") then
                error("setfenv() failed: "..error)
            end
        end
    end
    local function wrap_table(t)
        if wrapped_tables[t] == nil then
            local meta = getmetatable(t)
            -- We use a value of false to indicate a table which had
            -- no metatable, so we can use nil as "not yet seen".
            wrapped_tables[t] = meta or false
            for k, v in pairs(t) do
                wrap_value(v)
            end
            local new_meta = {}
            if meta then
                for k, v in pairs(meta) do
                    new_meta[k] = v
                end
                new_meta.__index = make_index(meta.__index)
            end
            new_meta.__newindex = make_newindex(meta and meta.__newindex)
            setmetatable(t, new_meta)
        end
    end
    function wrap_value(v)  -- Declared local above.
        if type(v) == "function" then
            wrap_func(v)
        elseif type(v) == "table" then
            wrap_table(v)
        end
        return v
    end

    local env_meta = getmetatable(env)
    setmetatable(env, env_meta and {__index = make_index(env_meta.__index)})
    wrap_func(func)
    for i = 1, select("#", ...) do
        wrap_value(select(i, ...))
    end
    local result = func(...)
    for f, e in pairs(wrapped_funcs) do
        setfenv(f, e)
    end
    for t, m in pairs(wrapped_tables) do
        setmetatable(t, m or nil)
    end
    return result
end

-- Wrap a function with a "lock", such that if the first argument
-- (optionally following an implicit "self" argument) is not equal to the
-- lock value, the call is ignored.  This can be used to suppress calls to
-- a particular object method from external sources (see PlayerPowerBarAlt
-- handling in targetbar.lua for an example).
--
-- [Parameters]
--     func: Function to wrap.
--     is_method: If true, the key will be expected as the second rather
--         than the first argument, to allow for an implicit "self".
--     lock: Lock value.  If the key argument is not equal to this value,
--         the function will return immediately with no values.
-- [Return value]
--     Wrapped function.
function WoWXIV.lockfunc(func, is_method, lock)
    if is_method then
        return function(self, key, ...)
            if key ~= lock then return end
            return func(self, ...)
        end
    else
        return function(key, ...)
            if key ~= lock then return end
            return func(...)
        end
    end
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

-- Return whether the given item (given as a numeric ID) goes in the
-- reagent bag.  (There doesn't seem to be a global API for this.)
local REAGENT  -- Defined below.
function WoWXIV.IsItemReagent(item)
    return REAGENT:has(item)
        or select(12, C_Item.GetItemInfo(item)) == Enum.ItemClass.Tradegoods
end
--[[local]] REAGENT = set(
    -- Mechagon Tinkering reagents
    166846,  -- Spare Parts
    166970,  -- Energy Cell
    166971,  -- Empty Energy Cell
    168327,  -- Chain Ignitercoil
    168832,  -- Galvanic Oscillator
    169610,  -- S.P.A.R.E. Crate
    -- Protoform Synthesis (Zereth Mortis) reagents
    187633,  -- Bufonid Lattice
    187634,  -- Ambystan Lattice
    187635,  -- Cervid Lattice
    187636,  -- Aurelid Lattice
    188957,  -- Genesis Mote
    189145,  -- Helicid Lattice
    189146,  -- Geomental Lattice
    189147,  -- Leporid Lattice
    189148,  -- Poultrid Lattice
    189149,  -- Proto Avian Lattice
    189150,  -- Raptora Lattice
    189151,  -- Scarabid Lattice
    189152,  -- Tarachnid Lattice
    189153,  -- Unformed Lattice
    189154,  -- Vespoid Lattice
    189155,  -- Viperid Lattice
    189156,  -- Vombata Lattice
    189157,  -- Glimmer of Animation
    189158,  -- Glimmer of Cunning
    189159,  -- Glimmer of Discovery
    189160,  -- Glimmer of Focus
    189161,  -- Glimmer of Malice
    189162,  -- Glimmer of Metamorphosis
    189163,  -- Glimmer of Motion
    189164,  -- Glimmer of Multiplicity
    189165,  -- Glimmer of Predation
    189166,  -- Glimmer of Renewal
    189167,  -- Glimmer of Satisfaction
    189168,  -- Glimmer of Serenity
    189169,  -- Glimmer of Survival
    189170,  -- Glimmer of Vigilance
    189171,  -- Bauble of Pure Innovation
    189172,  -- Crystallized Echo of the First Song
    189173,  -- Eternal Ragepearl
    189174,  -- Lens of Focused Intention
    189175,  -- Mawforged Bridle
    189176,  -- Protoform Sentience Crown
    189177,  -- Revelation Key
    189178,  -- Tools of Incomprehensible Experimentation
    189179,  -- Unalloyed Bronze Ingot
    189180,  -- Wind's Infinite Call
    190388   -- Lupine Lattice
)

-- Spell ID of the "Disenchant" spell.
WoWXIV.SPELL_DISENCHANT = 13262
-- Return whether the given item can be disenchanted.
local DISENCHANTABLE_TYPES, DISENCHANTABLE_ITEMS  --  Defined below.
function WoWXIV.IsItemDisenchantable(item)
    local info = {C_Item.GetItemInfo(item)}
    local quality, item_class, item_subclass = info[3], info[12], info[13]
    if not item_subclass then return false end
    local disenchantable = (DISENCHANTABLE_TYPES[item_class]
                            or DISENCHANTABLE_ITEMS:has(item))
    if type(disenchantable) == "table" then
        disenchantable = disenchantable:has(item_subclass)
    end
    if quality >= Enum.ItemQuality.Legendary then
        disenchantable = false
    end
    return disenchantable or false  -- Ensure it's a boolean return value.
end
--[[local]] DISENCHANTABLE_TYPES = {
    [Enum.ItemClass.Weapon] = true,
    [Enum.ItemClass.Armor] = set(
        Enum.ItemArmorSubclass.Generic,
        Enum.ItemArmorSubclass.Cloth,
        Enum.ItemArmorSubclass.Leather,
        Enum.ItemArmorSubclass.Mail,
        Enum.ItemArmorSubclass.Plate,
        -- Enum.ItemArmorSubclass.Cosmetic: not disenchantable!
        Enum.ItemArmorSubclass.Shield
    ),
    [Enum.ItemClass.Profession] = true,
    [Enum.ItemClass.Gem] = set(
        Enum.ItemGemSubclass.Artifactrelic  -- Legion artifact relics
    ),
}
--[[local]] DISENCHANTABLE_ITEMS = set(
    -- FIXME: is there any more general way to detect these?
    182067  -- Antique Duelist's Rapier (Revendreth enchanting WQ)
)

-- Return whether the given item is usable.  Wraps C_Item.IsUsableItem()
-- but also handles usable items for which that function returns false.
-- Does _not_ handle items which start quests (because the only API for
-- identifying those requires a container slot rather than an item ID).
local USABLE_ITEMS  -- Defined below.
function WoWXIV.IsItemUsable(item)
    return USABLE_ITEMS:has(item) or C_Item.IsUsableItem(item)
end
--[[local]] USABLE_ITEMS = set(
    239567,   -- 11.2 utility curio: Tailwind Conduit
    239568,   -- 11.2 utility curio: Audio Amplification Crystal
    239569,   -- 11.2 utility curio: Battered Aegis
    239570,   -- 11.2 utility curio: Temporal Decelerator Crystal
    239571,   -- 11.2 utility curio: Sands of K'aresh
    239573,   -- 11.2 combat curio: Ethereal Energy Converter
    239576,   -- 11.2 combat curio: Mana-Tinted Glasses
    239578,   -- 11.2 combat curio: Quizzical Device
    239579,   -- 11.2 combat curio: Hatarang
    239580    -- 11.2 combat curio: Nether Overlay Matrix
)

-- Display an error message, optionally with an error sound.
-- with_sound defaults to true if not specified.
function WoWXIV.Error(text, with_sound)
    if with_sound ~= false then
        PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)  -- generic error sound
    end
    UIErrorsFrame:AddExternalErrorMessage(text)
end
