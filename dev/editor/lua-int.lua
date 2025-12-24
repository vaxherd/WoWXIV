local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor

local strformat = string.format
local strgsub = string.gsub
local strjoin = string.join
local strsub = string.sub
local tostringall = tostringall


---------------------------------------------------------------------------
-- Lua interaction handlers
---------------------------------------------------------------------------

Editor.LuaInt = {}
local LuaInt = Editor.LuaInt

-- Set up an (assumed empty) editor frame for Lua interaction.
function LuaInt.InitFrame(frame)
    frame:SetName("(Lua interaction)")
    frame:SetText(
        "-- Press Ctrl-Enter to execute the current line as Lua code.\n" ..
        "-- Select a text region and press Ctrl-Enter to execute that region.\n" ..
        "\n", true)
    frame:BindKey("C-ENTER", LuaInt.HandleEval)
end

-- Evaluate the line under the cursor, or the region if a region is active.
function LuaInt.HandleEval(frame)
    local text, line
    if frame.buffer:IsMarkActive() then
        text = frame.buffer:GetRegionText()
        frame.buffer:MoveCursorToEndOfRegion()
        line = frame.buffer:GetMarkPos()
    else
        text = frame.buffer:GetLineText()
        line = frame.buffer:GetCursorPos()
    end

    -- Ensure the result is inserted on its own line.
    frame.buffer:MoveCursor("END")
    frame.buffer:InsertNewline()

    -- We support evaluating both proper Lua chunks (definitions/statements)
    -- and simple values, printing the result of evaluation in the latter
    -- case.  This leads to ambiguity in cases like function calls, which
    -- are also syntactically valid as Lua chunks, so we first try parsing
    -- the text with a "return" prepended; a successful parse in that case
    -- will lead to the returned values being captured by pcall() so we can
    -- print them.  If that fails, we assume the text is a more complex Lua
    -- chunk and parse it as-is.
    local tag = strformat("buffer:%d", line)
    -- For the prepended "return" case, we don't save the error string
    -- because either the "return" itself caused the error, in which case
    -- the error will be resolved by reparsing and we don't want to report
    -- it, or there's a problem with the code itself, in which case we can
    -- just report the reparse error.
    local code = loadstring("return "..text, tag)
    local error
    if not code then
        code, error = loadstring(text, tag)
    end

    -- Insert the result of evaluation (output and/or error).
    local output = ""
    if code then
        assert(error == nil)
        local function printhandler(...)
            output = output .. strjoin(" ", tostringall(...)) .. "\n"
        end
        local saved_printhandler = getprinthandler()
        setprinthandler(printhandler)
        local result = {pcall(code)}
        setprinthandler(saved_printhandler)
        if result[1] then
            if #result > 1 then
                printhandler(select(2, unpack(result)))
            end
        else
            error = result[2]
        end
    end
    if error then
        output = output .. error .. "\n"
    end
    frame.buffer:InsertText(output)
end
