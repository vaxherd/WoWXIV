local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor

local class = WoWXIV.class
local Frame = WoWXIV.Frame
local list = WoWXIV.list

local floor = math.floor
local strfind = string.find
local strformat = string.format
local strgsub = string.gsub
local strjoin = string.join
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub


-- Key auto-repeat delay and period, in seconds.
local KEY_REPEAT_DELAY = 0.3
local KEY_REPEAT_PERIOD = 0.05

-- Cursor blink period, in seconds.
local CURSOR_BLINK_PERIOD = 1.0


---------------------------------------------------------------------------
-- Main editor frame
---------------------------------------------------------------------------

local EditorFrame = class(Frame)
Editor.EditorFrame = EditorFrame
SLASH_XIVEDITOR1="/xe" SlashCmdList.XIVEDITOR=function() ZZe=EditorFrame("Test", nil, "Text 56789 123456789 123456789 123456789 123456789 123456789 123456789 123456789") end --FIXME temp

function EditorFrame:__allocator(filename, text)
    return __super("Frame", nil, UIParent, "WoWXIV_EditorFrameTemplate")
end

function EditorFrame:__constructor(name, filepath, text)
    self.name = name
    self.filepath = filepath
    self.buffer = Editor.Buffer(text or "", self.TextView)
    self.buffer:SetDirtyCallback(function() self:OnBufferStateChange() end)
    self.buffer:SetScrollCallback(function() self:OnBufferStateChange() end)
    WoWXIV.SetFont(self.CommandLine.Text, "EDITOR")

    -- List of keys which are currently pressed, in press order.  Each
    -- element is a {key, ch} pair; if |ch| is not nil, it is the text
    -- equivalent of |key|.
    self.keys = list()
    -- Key repeat timer.  A value of 0 signifies a newly-pressed key; the
    -- key is not actually processed until the OnUpdate event, to ensure
    -- that key-to-text translation is performed (by the OnChar event) if
    -- appropriate.  A value of nil indicates that no key is currently
    -- repeating; if self.keys is not empty, this is because the most
    -- recently pressed key was released.  Note that while OnChar provides
    -- built-in repeat functionality, we implement our own because
    -- (1) we want non-text keys like Enter and arrow keys to repeat and
    -- (2) we want the flexibility to choose our own repeat delays.
    self.repeat_delay = nil
    -- Cursor blink timer.  This is reset to zero on every input, so the
    -- cursor is always visible while the user is actively typing.
    self.cursor_timer = 0
    -- Timestamp of last OnUpdate() call, used for repeat and cursor blink
    -- timing.
    self.now = GetTime()
    -- Is the mouse cursor currently set to the "I-bar" text editing cursor?
    self.cursor_ibar = false
    -- Is the user currently performing a text-selection mouse drag?
    self.drag_select = false
    -- Text most recently deleted with a "kill" command (C-w), nil if none.
    self.yank_text = nil

    -- Command input state: nil for normal editing, otherwise a token
    -- indicating what is being entered on the command line (see
    -- StartCommand() for details).
    self.command_state = nil
    -- Character offset of the cursor in the command line.  If nil, the
    -- normal buffer cursor is displayed.
    self.command_cursor_pos = nil
    -- Size of a character cell in the command line font.  See notes in
    -- Buffer:MeasureView().
    do
        local text = self.CommandLine.Text
        text:SetText("X")
        local w1 = text:GetStringWidth()
        text:SetText("XXXXXXXXXXX")
        local w11 = text:GetStringWidth()
        self.command_cell_w = (w11 - w1) / 10
        self.command_cell_h = text:GetStringHeight()
        text:SetText("")
    end
    -- Texture instance for displaying the command line cursor.
    self.command_cursor = self.CommandLine:CreateTexture(nil, "OVERLAY")
    self.command_cursor:Hide()
    self.command_cursor:SetSize(1, self.command_cell_h)
    self.command_cursor:SetColorTexture(1, 1, 1)
    self.command_cursor:SetPoint("TOP", self.CommandLine, "TOPLEFT")

    -- Keymap for this frame.  Key names follow OnKeyDown argument values;
    -- modifiers follow Emacs style, and must be given in the order
    -- "S-C-M-key".  Handler functions receive the EditorFrame instance,
    -- pressed key (with modifiers), and translated character (nil if none)
    -- as arguments.  Keys with no bound handler but a translated character
    -- are inserted directly into the buffer.
    self.keymap = self:GetDefaultKeymap()
    -- List of prefix keys input so far in the current input sequence.
    self.prefix_keys = list()
    -- Timeout for displaying the current prefix in the command line.
    self.prefix_timeout = nil

    self:UpdateTitle()
    self:SetFocused(self:IsMouseOver())
end


-------- Event handlers and associated helper functions

function EditorFrame:OnClose()
    self:Hide()
end

function EditorFrame:OnEnter()
    self:SetFocused(true)
end

function EditorFrame:OnLeave()
    -- If the user is dragging, keep focus as long the mouse button is down.
    if not self.drag_select then
        self:SetFocused(false)
    end
end

function EditorFrame:OnKeyDown(key)
    self.keys:append({key})
    self.repeat_delay = 0
end

function EditorFrame:OnChar(ch)
    if #self.keys == 0 then
        -- WoW (at least as of version 11.2.7) sends OnChar events for
        -- keys held down across a mouse focus change, so be careful to
        -- ignore those.
        return
    end
    if self.keys[#self.keys][2] then
        assert(self.keys[#self.keys][2] == ch)
    else
        assert(self.repeat_delay == 0)  -- Must have been pressed this frame.
        self.keys[#self.keys][2] = ch
    end
end

function EditorFrame:OnKeyUp(key)
    for i, key_ch in ipairs(self.keys) do
        if key_ch[1] == key then
            if i == #self.keys then
                self.repeat_delay = nil
            end
            self.keys:pop(i)
            return
        end
    end
    error("Received OnKeyUp for unpressed key "..tostring(key))
end

function EditorFrame:OnMouseDown(button)
    if button == "LeftButton" then
        if self.TextView:IsMouseOver() then
            self.buffer:SetCursorPosFromMouse(self:MouseToTextCoords())
            self:OnBufferStateChange()
            self.drag_select = true
        end
    end
end

function EditorFrame:MouseToTextCoords()
    local x, y = GetCursorPosition()
    local scale = self.TextView:GetEffectiveScale()
    x, y = x/scale, y/scale
    x, y = x - self.TextView:GetLeft(), self.TextView:GetTop() - y
    return floor(x), floor(y)
end

function EditorFrame:OnMouseUp(button)
    self.drag_select = false
    if not self:IsMouseOver() then
        self:SetFocused(false)
    end
end

function EditorFrame:OnMouseWheel(delta)
    self.TextView.ScrollBar:ScrollStepInDirection(-delta)
end

function EditorFrame:OnTitleDragStart()
    self:StartMoving()
end

function EditorFrame:OnTitleDragStop()
    self:StopMovingOrSizing()
end

function EditorFrame:OnUpdate()
    assert(self.focused)

    local now = GetTime()
    local dt = now - self.now
    self.now = now

    local repeat_delay = self.repeat_delay
    if repeat_delay then
        assert(#self.keys > 0)
        local send
        if repeat_delay == 0 then
            send = true
            repeat_delay = KEY_REPEAT_DELAY
        else
            repeat_delay = repeat_delay - dt
            while repeat_delay <= 0 do
                send = true
                repeat_delay = repeat_delay + KEY_REPEAT_PERIOD
            end
        end
        self.repeat_delay = repeat_delay
        if send then
            self:HandleKey(unpack(self.keys[#self.keys]))
            self:OnBufferStateChange()
        end
    end

    local cursor_timer = self.cursor_timer
    local cursor_on = (cursor_timer < CURSOR_BLINK_PERIOD/2)
    self.cursor_timer = (cursor_timer + dt) % CURSOR_BLINK_PERIOD
    if self.command_cursor_pos then
        self.buffer:SetShowCursor(false)
        local x = self.CommandLine.Text:GetLeft() - self.CommandLine:GetLeft()
        local y = -(self.CommandLine.Text:GetHeight()/2 - self.command_cell_h/2)
        local offset = self.command_cell_w * self.command_cursor_pos
        self.command_cursor:SetPointsOffset(x+offset, y)
        self.command_cursor:SetShown(cursor_on)
    else
        self.buffer:SetShowCursor(cursor_on)
        self.command_cursor:Hide()
    end

    if #self.prefix_keys > 0 then
        if self.prefix_timeout and GetTime() >= self.prefix_timeout then
            self.prefix_timeout = nil
            local prefix = strjoin(" ", unpack(self.prefix_keys))
            self:SetCommandText(prefix.."-")
        end
    end

    self:SetCursorType(self.TextView:IsMouseOver())
    if self.drag_select then
        local line, col = self:MouseToTextCoords()
        self.buffer:SetMarkPosFromMouse(line, col, true)
    end
end

function EditorFrame:SetCursorType(ibar)
    ibar = not not ibar  -- Force to boolean.
    if self.cursor_ibar ~= ibar then
        self.cursor_ibar = ibar
        if ibar then
            -- FIXME: this doesn't actually work because SetCursor() ignores
            -- all directory components of the path and always searches under
            -- Interface/Cursor in the builtin asset archive
            --SetCursor(WoWXIV.makepath("textures/text-cursor.png"))
        else
            SetCursor(nil)
        end
    end
end

function EditorFrame:HandleKey(key, ch)
    local shift = IsShiftKeyDown()
    local ctrl = IsControlKeyDown()
    local alt = IsAltKeyDown()
    local keyname = strformat("%s%s%s%s", shift and "S-" or "",
                              ctrl and "C-" or "", alt and "M-" or "", key)
    local keymap = self.keymap
    for prefix_key in self.prefix_keys do
        assert(type(keymap[prefix_key]) == "table")
        keymap = keymap[prefix_key]
    end
    local handler = keymap[keyname]
    if handler then
        if type(handler) == "table" then
            self.prefix_keys:append(keyname)
            if #self.prefix_keys == 1 or self.prefix_timeout then
                self.prefix_timeout = GetTime() + 1
            else
                local prefix = strjoin(" ", unpack(self.prefix_keys))
                self:SetCommandText(prefix.."-")
            end
        else
            assert(type(handler) == "function")
            self.prefix_keys:clear()
            self:SetCommandText("")
            handler(self, keyname, ch)
        end
    elseif #self.prefix_keys > 0 then
        local prefix = strjoin(" ", unpack(self.prefix_keys))
        self:SetCommandText(strformat("%s %s is undefined", prefix, keyname))
        self.prefix_keys:clear()
    elseif ch then
        self:SetCommandText("")
        if not self:HandleCommandInput("CHAR", ch) then
            self:ClearCommand()
            self.buffer:InsertChar(ch)
        end
    end
end

function EditorFrame:SetFocused(focused)
    self.focused = focused
    self:EnableKeyboard(focused)
    self:SetBorderActive(focused)
    self.now = GetTime()
    if focused then
        self:SetScript("OnUpdate", self.OnUpdate)
    else
        self:SetScript("OnUpdate", nil)
        SetCursor(nil)
        self.buffer:SetShowCursor(false)
    end

    -- We'll get paired leave/enter events if the cursor moves from one UI
    -- element to another (e.g. title bar to close button), so don't clear
    -- pressed keys unless we're still unfocused at the end of the frame.
    RunNextFrame(function()
        if not self.focused then
            self.keys:clear()
        end
    end)
end

-- Called from various places when some change has occurred in buffer state.
function EditorFrame:OnBufferStateChange()
    self:UpdateTitle()
    self.cursor_timer = 0
end

function EditorFrame:UpdateTitle()
    local line, col = self.buffer:GetCursorPos()
    local dirty = self.buffer:IsDirty() and "(*) " or ""
    local name_escaped = strgsub(self.filename or "(Untitled)", "|", "||")
    local title = strformat("%s%s - L%d C%d", dirty, name_escaped, line, col)
    self.Border.Title:SetText(title)
end

-- NineSlice.lua has a convenient ForEachPiece() function we could use
-- to darken/lighten the border, except that sadly it's left as a local
-- function with no export, so we have to reimplement it ourselves.
-- "Center" is unused for our case, but we include it for completeness.
local BORDER_PIECES = list(
    "TopLeftCorner", "TopEdge", "TopRightCorner",
    "LeftEdge", "Center", "RightEdge",
    "BottomLeftCorner", "BottomEdge", "BottomRightCorner")
function EditorFrame:SetBorderActive(active)
    local level = active and 1 or 0.5
    for piece_tag in BORDER_PIECES do
        local piece = self.Border[piece_tag]
        if piece and piece:IsShown() then
            piece:SetVertexColor(level, level, level)
        end
    end
    self.CloseButton:SetAlpha(level)
    self.Divider:SetVertexColor(level, level, level)
end


-------- File access

function EditorFrame:SaveFile(path)
    path = path or self.filepath
    if not path then
        self:SetCommandText("No file to save to")
        return
    end
    local FS = Dev.FS
    local fd = FS.Open(path, FS.OPEN_TRUNCATE)
    if not fd then
        self:SetCommandText(strformat("Unable to open file: %s", path))
    else
        local ok = FS.Write(fd, self.buffer:GetText())
        FS.Close(fd)
        if not ok then
            self:SetCommandText(strformat("Writing to %s failed", path))
        else
            self:SetCommandText(strformat("Wrote %s", path))
            self.buffer:ClearDirty()
            self.filepath = path
            self.name = strmatch(path, "([^/]+)$") or path
            self:UpdateTitle()
        end
    end
end


-------- Miscellaneous utility functions

-- Set the mark at the current cursor position.
function EditorFrame:SetMark()
    self.buffer:SetMarkPos(self.buffer:GetCursorPos())
    self:SetCommandText("Mark set")
end


-------- Base command line processing

-- Emacs has sensible reasons for implementing the command line as a buffer
-- of its own (the "minibuffer"), but that's overkill for our purposes; we
-- suffer a bit of code duplication for the sake of less overall complexity.


-- Display the given text on the command line.  The text will be cleared
-- on the next key input.  If |cursor_pos| is not nil, the cursor will be
-- displayed at that position in the text (and hidden from the buffer).
function EditorFrame:SetCommandText(text, cursor_pos)
    self.CommandLine.Text:SetText(strgsub(text, "|", "||"))
    self.command_cursor_pos = cursor_pos
end

-- Clear any currently active command, then start processing for the given
-- command.  |command| is a token used to identify command-specific
-- processing methods:
--     StartCommand_|command|(...)  (performs initialization for the command)
--     EndCommand_|command|()  (performs finalization, called when cleared)
--     HandleCommandInput_|command|(...)  (implements HCI() for the command)
-- Note that the command's StartCommand handler must return true for the
-- command to be activated.  Any additional arguments to this method are
-- passed directly to the handler.
function EditorFrame:StartCommand(command, ...)
    self:ClearCommand()
    local start_method = self["StartCommand_"..command]
    if start_method and start_method(self, ...) then
        self.command_state = command
    end
end

-- Clear any current command state and any displayed text on the command line.
-- If a command is currently active and has an EndCommand handler, that
-- handler is called after clearing the command line text (so it can
-- display a final status message if appropriate).
function EditorFrame:ClearCommand()
    local end_method =
        self.command_state and self["EndCommand_" .. self.command_state]
    self.command_state = nil
    self:SetCommandText("")
    if end_method then
        end_method(self)
    end
end

-- Process the given input under the current command state, returning true
-- if the input was consumed.  |input| is one of the following:
--     "CHAR": insert the character |arg| at the current cursor position
--     "BACKSPACE": delete one character to the left of the cursor
--     "CANCEL": cancel any pending operation
--     "CURSOR": move the cursor as specified by |arg| (a keycode with
--         optional modifiers, as in keymap entries)
--     "DELETE": delete one character to the right of the cursor
--     "ENTER": confirm the current input, as for the Enter key
--     "KILL-LINE": delete all characters to the end of the line and
--         store the deleted text in the kill buffer
--     "YANK": insert the kill buffer text (if any) at the cursor
-- Individual command handlers can also define their own inputs (see the
-- isearch handler for an example).
function EditorFrame:HandleCommandInput(input, arg)
    local handler
    if self.command_state then
        handler = self["HandleCommandInput_" .. self.command_state]
    end
    return handler and handler(self, input, arg)
end


-------- Command-specific implementations
-------- (FIXME: yes, we should probably have a base class for these)

function EditorFrame:goto_CommandText()
    local s = "Goto line: " .. self.goto_input
    return s, #s
end

function EditorFrame:StartCommand_goto()
    self.goto_input = ""
    self:SetCommandText(self:goto_CommandText())
    return true
end

function EditorFrame:HandleCommandInput_goto(input, arg)
    if input == "CHAR" then
        local ch = arg
        self.goto_input = self.goto_input .. ch
        self:SetCommandText(self:goto_CommandText())
        return true
    elseif input == "BACKSPACE" then
        if #self.goto_input > 0 then
            self.goto_input =
                strsub(self.goto_input, 1, #self.goto_input-1)
        end
        self:SetCommandText(self:goto_CommandText())
        return true
    elseif input == "ENTER" then
        self:ClearCommand()
        local line = tonumber(self.goto_input)
        if line and line > 0 and line == floor(line) then
            self:SetMark()
            self.buffer:SetCursorPos(line, 0)
        else
            self:SetCommandText("Line number must be a positive integer")
        end
        return true
    end
end


-- Convert the given Emacs regular expression |re| to a Lua pattern.
-- Returns nil if the string is not a valid regular expression.
local function RegexToPattern(re)
    local BASE = 0
    local ESCAPE = 1
    local RANGE_START = 2
    local RANGE = 3
    local GROUP = 4
    local state_stack = list(BASE)

    local pattern = ""
    local i = 1
    while i <= #re do
        local ch = strsub(re, i, i)
        i = i + 1
        local state = state_stack[#state_stack]
        if state == ESCAPE then
            state_stack:pop()
            if ch == "(" then
                if strsub(re, i, i) == "?" then
                    return nil  -- Shy groups not supported.
                end
                state_stack:append(GROUP)
                pattern = pattern .. "("
            elseif ch == "|" then
                if state_stack[#state_stack] ~= GROUP then
                    return nil  -- Alternation not inside a group.
                end
                return nil  -- Alternation not supported.
            elseif ch == ")" then
                if state_stack:pop() ~= GROUP then
                    return nil  -- Unbalanced parentheses.
                end
                pattern = pattern .. ")"
            elseif strstr("123456789", ch) then
                pattern = pattern .. "%" .. ch
            elseif strstr("bBcCsS_<>{}`'=", ch) then
                return nil  -- Unsupported features.
            elseif ch == "n" then
                -- Convenient deviation from Emacs style to allow searching
                -- for newlines without having to explicitly enter them as
                -- control characters.
                pattern = pattern .. "\n"
            elseif string.match(ch, "%w") then
                pattern = pattern .. ch
            else
                pattern = pattern .. "%" .. ch
            end
        elseif state == RANGE_START or state == RANGE then
            if ch == "^" and state == RANGE_START then
                pattern = pattern .. "^"
                -- Stay on RANGE_START to allow an immediately following "]".
            else
                state_stack[#state_stack] = RANGE
                if ch == "]" then
                    pattern = pattern .. "]"
                    if state ~= RANGE_START then
                        state_stack:pop()
                    end
                elseif ch == "%" then
                    pattern = pattern .. "%%"
                elseif ch == "[" and strsub(re, i, i) == ":" then
                    local class_end = strstr(re, ":]", i+1)
                    if not class_end then
                        return nil  -- Unterminated character class specified.
                    end
                    local class_name = strsub(re, i+1, class_end-1)
                    i = class_end+2
                    if class_name == "alnum" then
                        pattern = pattern .. "%w"
                    elseif class_name == "alpha" then
                        pattern = pattern .. "%a"
                    elseif class_name == "ascii" then
                        pattern = pattern .. "%z\001-\127"
                    elseif class_name == "blank" then
                        pattern = pattern .. "\032\009"
                    elseif class_name == "cntrl" then
                        pattern = pattern .. "%c"
                    elseif class_name == "digit" then
                        pattern = pattern .. "%d"
                    elseif class_name == "graph" then
                        pattern = pattern .. "\033-\126"
                    elseif class_name == "lower" then
                        pattern = pattern .. "%l"
                    elseif class_name == "print" then
                        pattern = pattern .. "\032-\126"
                    elseif class_name == "punct" then
                        pattern = pattern .. "%p"
                    elseif class_name == "space" then
                        pattern = pattern .. "%s"
                    elseif class_name == "upper" then
                        pattern = pattern .. "%u"
                    elseif class_name == "word" then
                        pattern = pattern .. "%w_"
                    elseif class_name == "xdigits" then
                        pattern = pattern .. "0-9a-fA-F"
                    else
                        return nil  -- Unsupported character class.
                    end
                else
                    pattern = pattern .. ch
                end
            end
        else
            assert(state == BASE or state == GROUP)
            if ch == "\\" then
                state_stack:append(ESCAPE)
            elseif ch == "[" then
                pattern = pattern .. "["
                state_stack:append(RANGE_START)
            elseif ch == "*" then
                if strsub(re, i, i) == "?" then
                    i = i + 1
                    pattern = pattern .. "-"
                else
                    pattern = pattern .. "*"
                end
            elseif ch == "+" then
                if strsub(re, i, i) == "?" then
                    return nil  -- Non-greedy "+" not supported.
                else
                    pattern = pattern .. "+"
                end
            elseif ch == "?" then
                if strsub(re, i, i) == "?" then
                    return nil  -- Non-greedy "?" not supported.
                else
                    pattern = pattern .. "?"
                end
            elseif ch == "^" then
                pattern = pattern .. "(^|\n)"
            elseif ch == "$" then
                pattern = pattern .. "($|\n)"
            elseif strstr("()%-", ch) then
                pattern = pattern .. "%" .. ch
            else
                pattern = pattern .. ch
            end
        end
    end

    if state_stack:pop() == BASE then
        return pattern
    else
        return nil
    end
end

-- Helper to return the command line text for the current isearch state.
function EditorFrame:isearch_CommandText(info)
    local prompt = strformat("%s%s%sI-search%s: ",
                             self.isearch_failing and "failing " or "",
                             self.isearch_wrapped and "wrapped " or "",
                             self.isearch_regex and "regexp " or "",
                             self.isearch_forward and "" or " backward")
    prompt = strsub(prompt,1,1):upper() .. strsub(prompt,2)
    local suffix = info and " ["..info.."]" or ""
    -- FIXME: handle command line overflow
    local pre_cursor = prompt .. self.isearch_text
    return pre_cursor .. suffix, #pre_cursor
end

-- Helper to update search state and set the command line.
function EditorFrame:isearch_Update()
    if #self.isearch_text > 0 then
        local str
        if self.isearch_regex then
            str = RegexToPattern(self.isearch_text)
            if not str then
                self:SetCommandText(
                    self:isearch_CommandText("incomplete input"))
                return
            end
        else
            str = self.isearch_text
        end
        if self.buffer:IsMarkActive() then
            -- If the mark is active, it implies we just edited the search
            -- text (since we clear the mark on start and on a "next match"
            -- input), so move the cursor to the mark (which is set at the
            -- opposite side of the match) and search again from the
            -- current match position.
            self.buffer:SetCursorPos(self.buffer:GetMarkPos())
            self.buffer:ClearMark()
        end
        local highlight = true
        self.isearch_failing = not self.buffer:Search(
            str, self.isearch_regex, self.isearch_case,
            self.isearch_forward, highlight)
        if not self.isearch_failing then
            self.isearch_last_success = self.isearch_text
        end
    else
        self.buffer:SetCursorPos(unpack(self.isearch_initial_cursor))
    end
    self:SetCommandText(self:isearch_CommandText())
end

function EditorFrame:StartCommand_isearch(forward, regex)
    self.isearch_forward = forward
    self.isearch_regex = regex
    self.isearch_case = false
    self.isearch_initial_cursor = {self.buffer:GetCursorPos()}
    self.isearch_initial_mark = {self.buffer:GetMarkPos()}
    self.isearch_text = ""
    self.isearch_last_success = ""  -- Last successfully matched string.
    self.isearch_failing = false
    self.isearch_wrapped = false

    self.buffer:ClearMark()
    self:SetCommandText(self:isearch_CommandText())
    return true
end

function EditorFrame:EndCommand_isearch()
    if self.isearch_initial_cursor then
        self.buffer:SetMarkPos(unpack(self.isearch_initial_cursor))
        self:SetCommandText("Mark saved where search started")
    end
end

function EditorFrame:HandleCommandInput_isearch(input, arg)
    if input == "CHAR" then
        local ch = arg
        self.isearch_text = self.isearch_text .. ch
        self:isearch_Update()
        return true
    elseif input == "BACKSPACE" then
        if #self.isearch_text > 0 then
            self.isearch_text =
                strsub(self.isearch_text, 1, #self.isearch_text-1)
        end
        self:isearch_Update()
        return true
    elseif input == "CANCEL" then
        if self.isearch_failing then
            self.isearch_text = self.isearch_last_success
            self:isearch_Update()
        else
            self.buffer:SetCursorPos(unpack(self.isearch_initial_cursor))
            self.buffer:SetMarkPos(unpack(self.isearch_initial_mark))
            self.isearch_initial_cursor = nil  -- Don't set mark on EndCommand.
            self:ClearCommand()
            self:SetCommandText("Quit")
        end
        return true
    elseif input == "ENTER" then
        self:ClearCommand()
        if self.isearch_text == "" then
            self:StartCommand("search")
        end
        return true
    elseif input == "ISEARCH" then
        local forward = arg
        if forward ~= self.isearch_forward then
            self.isearch_forward = forward
        elseif self.isearch_failing then
            self.isearch_wrapped = true
            self.buffer:MoveCursor(self.isearch_forward and "C-HOME" or "C-END")
        end
        self.buffer:ClearMark()
        self:isearch_Update()
        return true
    elseif input == "ISEARCH_CASE" then
        self.isearch_case = not self.isearch_case
        local info = (self.isearch_case
                      and "case sensitive" or "case insensitive")
        self:SetCommandText(self:isearch_CommandText(info))
        return true
    end
end


function EditorFrame:replace_CommandText()
    local prefix = self.replace_regex and "Replace regexp" or "Replace string"
    if self.replace_from then
        s = strformat("%s %s with: %s",
                      prefix, self.replace_from, self.replace_input)
    else
        s = strformat("%s: %s", prefix, self.replace_input)
    end
    return s, #s
end

function EditorFrame:StartCommand_replace(regex)
    self.replace_regex = regex
    self.replace_input = ""
    self.replace_from = nil
    self:SetCommandText(self:replace_CommandText())
    return true
end

function EditorFrame:HandleCommandInput_replace(input, arg)
    if input == "CHAR" then
        local ch = arg
        self.replace_input = self.replace_input .. ch
        self:SetCommandText(self:replace_CommandText())
        return true
    elseif input == "BACKSPACE" then
        if #self.replace_input > 0 then
            self.replace_input =
                strsub(self.replace_input, 1, #self.replace_input-1)
        end
        self:SetCommandText(self:replace_CommandText())
        return true
    elseif input == "ENTER" then
        if not self.replace_from then
            if self.replace_input == "" then
                self:ClearCommand()
            else
                self.replace_from = self.replace_input
                self.replace_input = ""
                self:SetCommandText(self:replace_CommandText())
            end
            return true
        end
        self:ClearCommand()
        local from, to
        if self.replace_regex then
            from = RegexToPattern(self.replace_from)
            if not str then
                self:SetCommandText("Invalid regexp")
            end
            to = self.replace_input:gsub("%%", "%%%%")
                                   :gsub(to, "\\([0-9])", "%%%1")
        else
            from = self.replace_from
            to = self.replace_input
        end
        if from and from ~= "" then
            local cur_line, cur_col = self.buffer:GetCursorPos()
            -- Unintended deviation from Emacs behavior: replacing does not
            -- move the cursor to the location of the last replacement
            -- (because Lua provides no easy way to get this without
            -- iterating on the replacements one at a time).
            local n_repl = self.buffer:Replace(from, to, self.replace_regex)
            self:SetCommandText(strformat("Replaced %d occurrences", n_repl))
        end
        return true
    end
end


function EditorFrame:save_to_CommandText()
    local s = strformat("File to save in: %s", self.save_to_input)
    return s, #s
end

function EditorFrame:StartCommand_save_to()
    self.save_to_input = ""
    self:SetCommandText(self:save_to_CommandText())
    return true
end

function EditorFrame:HandleCommandInput_save_to(input, arg)
    if input == "CHAR" then
        local ch = arg
        self.save_to_input = self.save_to_input .. ch
        self:SetCommandText(self:save_to_CommandText())
        return true
    elseif input == "BACKSPACE" then
        if #self.save_to_input > 0 then
            self.save_to_input =
                strsub(self.save_to_input, 1, #self.save_to_input-1)
        end
        self:SetCommandText(self:save_to_CommandText())
        return true
    elseif input == "ENTER" then
        self:ClearCommand()
        self:SaveFile(self.save_to_input)
        return true
    end
end


function EditorFrame:search_CommandText()
    local s = strformat(
        "%s: %s", self.search_regex and "RE search" or "Search",
        self.search_input)
    return s, #s
end

function EditorFrame:StartCommand_search(regex)
    self.search_regex = regex
    self.search_input = ""
    self:SetCommandText(self:search_CommandText())
    return true
end

function EditorFrame:HandleCommandInput_search(input, arg)
    if input == "CHAR" then
        local ch = arg
        self.search_input = self.search_input .. ch
        self:SetCommandText(self:search_CommandText())
        return true
    elseif input == "BACKSPACE" then
        if #self.search_input > 0 then
            self.search_input =
                strsub(self.search_input, 1, #self.search_input-1)
        end
        self:SetCommandText(self:search_CommandText())
        return true
    elseif input == "ENTER" then
        self:ClearCommand()
        local str
        if self.search_regex then
            str = RegexToPattern(self.search_input)
            if not str then
                self:SetCommandText("Invalid regexp")
            end
        else
            str = self.search_input
        end
        if str and str ~= "" then
            local cur_line, cur_col = self.buffer:GetCursorPos()
            local has_case = (strfind(self.search_input, "%u") ~= nil)
            local forward = true
            local highlight = false
            local found = self.buffer:Search(
                str, self.search_regex, has_case, forward, highlight)
            if found then
                -- Deliberate deviation from Emacs behavior: Set the mark on
                -- a non-incremental search, to match i-search behavior.
                self.buffer:SetMarkPos(cur_line, cur_col)
                self:SetCommandText("Mark saved where search started")
            else
                self:SetCommandText(strformat("Search failed: \"%s\"",
                                              self.search_input))
            end
        end
        return true
    end
end


-------- Default keymap and handler functions

function EditorFrame:GetDefaultKeymap()
    if not EditorFrame.DEFAULT_KEYMAP then
        EditorFrame.DEFAULT_KEYMAP = {
            ["ENTER"] = EditorFrame.HandleEnter,
            ["BACKSPACE"] = EditorFrame.HandleBackspace,
            ["DELETE"] = EditorFrame.HandleDelete,

            ["F2"] = EditorFrame.HandleYank,
            ["F7"] = EditorFrame.HandleFindFile,
            ["F8"] = EditorFrame.HandleInsertFile,
            ["F9"] = EditorFrame.HandleSaveFile,

            ["C-SPACE"] = EditorFrame.HandleSetMark,

            ["M-C"] = EditorFrame.HandleMakeCapital,
            ["C-G"] = EditorFrame.HandleCancel,
            ["M-G"] = EditorFrame.HandleGoToLine,
            ["M-L"] = EditorFrame.HandleMakeLowercase,
            ["C-K"] = EditorFrame.HandleKillLine,
            ["C-R"] = EditorFrame.HandleIsearchBackward,
            ["M-R"] = EditorFrame.HandleReplaceString,
            ["S-M-R"] = EditorFrame.HandleReplaceRegex,
            ["C-M-R"] = EditorFrame.HandleRegexIsearchBackward,
            ["C-S"] = EditorFrame.HandleIsearchForward,
            ["M-S"] = EditorFrame.HandleSearchString,
            ["S-M-S"] = EditorFrame.HandleSearchRegex,
            ["C-M-S"] = EditorFrame.HandleRegexIsearchForward,
            ["M-U"] = EditorFrame.HandleMakeUppercase,
            ["C-W"] = EditorFrame.HandleKill,
            ["C-X"] = {
                ["C-F"] = EditorFrame.HandleFindFile,
                ["I"] = EditorFrame.HandleInsertFile,
                ["C-S"] = EditorFrame.HandleSaveFile,
                ["C-X"] = EditorFrame.HandleSwapMark,
            },  -- C-X
            ["C-Y"] = EditorFrame.HandleYank,

            ["UP"] = EditorFrame.HandleMovementKey,
            ["S-UP"] = EditorFrame.HandleSelectionKey,
            ["C-UP"] = EditorFrame.HandleMovementKey,
            ["S-C-UP"] = EditorFrame.HandleSelectionKey,
            ["DOWN"] = EditorFrame.HandleMovementKey,
            ["S-DOWN"] = EditorFrame.HandleSelectionKey,
            ["C-DOWN"] = EditorFrame.HandleMovementKey,
            ["S-C-DOWN"] = EditorFrame.HandleSelectionKey,
            ["LEFT"] = EditorFrame.HandleMovementKey,
            ["S-LEFT"] = EditorFrame.HandleSelectionKey,
            ["C-LEFT"] = EditorFrame.HandleMovementKey,
            ["S-C-LEFT"] = EditorFrame.HandleSelectionKey,
            ["RIGHT"] = EditorFrame.HandleMovementKey,
            ["S-RIGHT"] = EditorFrame.HandleSelectionKey,
            ["C-RIGHT"] = EditorFrame.HandleMovementKey,
            ["S-C-RIGHT"] = EditorFrame.HandleSelectionKey,
            ["HOME"] = EditorFrame.HandleMovementKey,
            ["S-HOME"] = EditorFrame.HandleSelectionKey,
            ["C-HOME"] = EditorFrame.HandleMovementKey,
            ["S-C-HOME"] = EditorFrame.HandleSelectionKey,
            ["END"] = EditorFrame.HandleMovementKey,
            ["S-END"] = EditorFrame.HandleSelectionKey,
            ["C-END"] = EditorFrame.HandleMovementKey,
            ["S-C-END"] = EditorFrame.HandleSelectionKey,
            ["PAGEUP"] = EditorFrame.HandleMovementKey,
            ["S-PAGEUP"] = EditorFrame.HandleSelectionKey,
            ["PAGEDOWN"] = EditorFrame.HandleMovementKey,
            ["S-PAGEDOWN"] = EditorFrame.HandleSelectionKey,
        }
    end
    return EditorFrame.DEFAULT_KEYMAP
end

function EditorFrame:HandleBackspace()
    if not self:HandleCommandInput("BACKSPACE") then
        self:ClearCommand()
        self.buffer:DeleteChar(false)
    end
end

function EditorFrame:HandleCancel()
    if not self:HandleCommandInput("CANCEL") then
        self:ClearCommand()
        self:SetCommandText("Quit")
    end
end

function EditorFrame:HandleDelete()
    if not self:HandleCommandInput("DELETE") then
        self:ClearCommand()
        self.buffer:DeleteChar(true)
    end
end

function EditorFrame:HandleEnter()
    if not self:HandleCommandInput("ENTER") then
        self:ClearCommand()
        self.buffer:InsertNewline()
    end
end

function EditorFrame:HandleFindFile()
    self:ClearCommand()
    --FIXME notimp
end

function EditorFrame:HandleGoToLine()
    self:StartCommand("goto")
end

function EditorFrame:HandleInsertFile()
    self:ClearCommand()
    --FIXME notimp
end

function EditorFrame:HandleIsearch(forward, regex)
    if self.command_state == "isearch" then
        assert(self:HandleCommandInput("ISEARCH", forward))
    else
        self:StartCommand("isearch", forward, regex)
    end
end

function EditorFrame:HandleIsearchBackward()
    return self:HandleIsearch(false, false)
end

function EditorFrame:HandleIsearchForward()
    return self:HandleIsearch(true, false)
end

function EditorFrame:HandleKill()
    self:ClearCommand()
    local text = self.buffer:DeleteRegion()
    if text then
        self.yank_text = text
    end
end

function EditorFrame:HandleKillLine()
    if not self:HandleCommandInput("KILL-LINE") then
        self:ClearCommand()
        --FIXME notimp
    end
end

function EditorFrame:HandleMakeCapital()
    if self.command_state == "isearch" then
        assert(self:HandleCommandInput("ISEARCH_CASE", forward))
    else
        self:ClearCommand()
        --FIXME notimp
    end
end

function EditorFrame:HandleMakeLower()
    self:ClearCommand()
    --FIXME notimp
end

function EditorFrame:HandleMakeUpper()
    self:ClearCommand()
    --FIXME notimp
end

function EditorFrame:HandleMovementKey(key)
    if not self:HandleCommandInput("CURSOR", key) then
        self:ClearCommand()
        self.buffer:MoveCursor(key)
    end
end

function EditorFrame:HandleRegexIsearchBackward()
    return self:HandleIsearch(false, true)
end

function EditorFrame:HandleRegexIsearchForward()
    return self:HandleIsearch(true, true)
end

function EditorFrame:HandleReplace(regex)
    self:StartCommand("replace", regex)
end

function EditorFrame:HandleReplaceRegex()
    return self:HandleReplace(true)
end

function EditorFrame:HandleReplaceString()
    return self:HandleReplace(false)
end

function EditorFrame:HandleSaveFile()
    if not self.buffer:IsDirty() then
        self:SetCommandText("(No changes need to be saved)")
    elseif not self.filepath then
        self:StartCommand("save_to")
    else
        self:SaveFile()
    end
end

function EditorFrame:HandleSearch(regex)
    self:StartCommand("search", regex)
end

function EditorFrame:HandleSearchRegex()
    return self:HandleSearch(true)
end

function EditorFrame:HandleSearchString()
    return self:HandleSearch(false)
end

function EditorFrame:HandleSelectionKey(key)
    self:ClearCommand()
    assert(strsub(key, 1, 2) == "S-")
    if not self.buffer:IsMarkActive() then
        self.buffer:SetMarkPos(self.buffer:GetCursorPos())
    end
    self.buffer:SetMarkActive(true)
    self.buffer:MoveMark(strsub(key, 3))
end

function EditorFrame:HandleSetMark()
    -- FIXME: handle mark activation
    self:SetMark()
end

function EditorFrame:HandleSwapMark()
    local mark_line, mark_col = self.buffer:GetMarkPos()
    if not mark_line then
        self:SetCommandText("No mark set in this buffer")
    else
        local cur_line, cur_col = self.buffer:GetCursorPos()
        self.buffer:SetCursorPos(mark_line, mark_col)
        self.buffer:SetMarkPos(cur_line, cur_col)
    end
end

function EditorFrame:HandleYank()
    if not self:HandleCommandInput("YANK") then
        self:ClearCommand()
        if self.yank_text then
            self.buffer:InsertText(self.yank_text)
        end
    end
end
