local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor
Dev.FS = Dev.FS or {}
local FS = Dev.FS

local class = WoWXIV.class
local Frame = WoWXIV.Frame
local list = WoWXIV.list

local floor = math.floor
local strfind = string.find
local strformat = string.format
local strgsub = string.gsub
local strjoin = string.join
local strmatch = string.match
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


-------- Constructor and related functions

function EditorFrame:__allocator()
    return __super("Frame", nil, UIParent, "WoWXIV_EditorFrameTemplate")
end

function EditorFrame:__constructor()
    self.buffer = Editor.Buffer(self.TextView)
    self.buffer:SetDirtyCallback(function() self:OnBufferStateChange() end)
    self.buffer:SetScrollCallback(function() self:OnBufferStateChange() end)

    WoWXIV.SetFont(self.CommandLine.Text, "EDITOR")
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

    self:OnAcquire()
end

function EditorFrame:OnAcquire()
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

    -- Current editor command: nil for normal editing, otherwise a
    -- CommandHandler (or subclass) instance managing command line input.
    self.command = nil
    -- Character offset of the cursor in the command line.  If nil, the
    -- normal buffer cursor is displayed.
    self.command_cursor_pos = nil

    -- Keymap for this frame.  Key names follow OnKeyDown argument values;
    -- modifiers follow Emacs style, and must be given in the order
    -- "S-C-M-key".  Handler functions receive the EditorFrame instance,
    -- pressed key (with modifiers), and translated character (nil if none)
    -- as arguments.  Keys with no bound handler but a translated character
    -- are inserted directly into the buffer.
    self.keymap = WoWXIV.deepcopy(self:GetDefaultKeymap())
    -- List of prefix keys input so far in the current input sequence.
    self.prefix_keys = list()
    -- Timeout for displaying the current prefix in the command line.
    self.prefix_timeout = nil
    -- Modified name of the previously pressed key.  Key handlers can use
    -- this to detect repeated presses of a key.
    self.prev_key = ""

    -- Are we currently being dragged?
    self.is_moving = false
    -- Are we currently in an OnUpdate() call?
    self.in_update = false
    -- Was Close() called during the current OnUpdate() call?
    self.pending_close = false

    self.name = "(Untitled)"
    self.filepath = nil
    self.buffer:SetText("")
    self.CommandLine.Text:SetText("")
    self:UpdateTitle()
    self:SetFocused(false)
end

function EditorFrame:OnRelease()
    -- Allow sub-objects to be garbage-collected.
    self.buffer:SetText("")
    self.command = nil
    self.keys = nil
    self.keymap = nil
    self.prefix_keys = nil
end

-- Pass in the EditorManager reference.
function EditorFrame:Init(manager)
    self.manager = manager
end


-------- Event handlers and associated helper functions

function EditorFrame:OnEnter()
    self.manager:FocusFrame(self)
end

function EditorFrame:OnLeave()
    -- If the user is dragging, keep focus as long the mouse button is down.
    if not (self.is_moving or self.drag_select) then
        self.manager:ReleaseFocus(self)
    end
end

function EditorFrame:OnKeyDown(key)
    local shortcut_key = strformat("%s%s%s%s",
                                   IsAltKeyDown() and "ALT-" or "",
                                   IsControlKeyDown() and "CTRL-" or "",
                                   IsShiftKeyDown() and "SHIFT-" or "", key)
    if not Dev.RunShortcut(shortcut_key) then
        self.keys:append({key})
        self.repeat_delay = 0
    end
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
    -- It must have been a key used as a shortcut trigger, so just ignore.
end

function EditorFrame:OnMouseDown(button)
    if button == "LeftButton" then
        if self.TextView:IsMouseOver() then
            self.buffer:SetCursorPosFromMouse(self:MouseToTextCoords())
            self:OnBufferStateChange()
            self.drag_select = true
        end
        -- This raise call is properly the purview of the window manager,
        -- but we're not worrying about those details for now.
        self.manager:RaiseFrame(self)
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
        self.manager:ReleaseFocus(self)
    end
end

function EditorFrame:OnMouseWheel(delta)
    self.TextView.ScrollBar:ScrollStepInDirection(-delta)
end

function EditorFrame:OnTitleMouseDown(button)
    if button == "LeftButton" then
        self.manager:RaiseFrame(self)
        -- We immediately start dragging on mouse-down because the
        -- DragStart event is noticeably delayed.
        self:StartMoving()
        self.is_moving = true
    end
end

function EditorFrame:OnTitleMouseUp(button)
    if button == "LeftButton" and self.is_moving then
        self:StopMovingOrSizing()
        self.is_moving = false
        if not self:IsMouseOver() then
            self.manager:ReleaseFocus(self)
        end
    end
end

function EditorFrame:OnFocus()
    self:SetFocused(true)
end

function EditorFrame:OnUnfocus()
    self:SetFocused(false)
end

function EditorFrame:OnUpdate()
    assert(self.focused)

    self.in_update = true

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

    self.in_update = false
    if self.pending_close then
        self:Close()
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
    self.prev_key = keyname
end

function EditorFrame:SetFocused(focused)
    self.focused = focused
    self:EnableKeyboard(focused)
    self:SetBorderActive(focused)
    self.now = GetTime()
    if focused then
        self:SetScript("OnUpdate", self.OnUpdate)
        self.cursor_timer = 0
    else
        self:SetScript("OnUpdate", nil)
        SetCursor(nil)
        self.buffer:SetShowCursor(false)
        self.command_cursor:Hide()
    end

    -- We'll get paired leave/enter events if the cursor moves from one UI
    -- element to another (e.g. title bar to close button), so don't clear
    -- pressed keys unless we're still unfocused at the end of the frame.
    RunNextFrame(function()
        if not self.focused then
            if self.keys then  -- Check in case we were closed.
                self.keys:clear()
                self.repeat_delay = nil
            end
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
    local name_escaped = strgsub(self.name or "(Untitled)", "|", "||")
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

-- Load the given file into the buffer.  If the path does not exist, assume
-- it is a new file to be created and empty the buffer.
-- On error, the pathname associated with the frame (if any) is not changed.
function EditorFrame:LoadFile(path)
    local st = FS.Stat(path)
    local ok
    if not st then
        self.buffer:SetText("")
        self:SetCommandText("(New file)")
        ok = true
    elseif st.is_dir then
        self:SetCommandText(strformat("Pathname is a directory: %s", path))
    else
        local text = FS.ReadFile(path)
        if not text then
            self:SetCommandText(strformat("Unable to read file: %s", path))
        else
            self.buffer:SetText(text)
            ok = true
        end
    end
    if ok then
        self:SetFilePath(path)
    end
end

-- Save the buffer to the given pathname.  If |path| is omitted, the
-- pathname associated with the frame is used; it is an error if the
-- frame also has no associated pathname.
-- Returns true on success, false on error.
function EditorFrame:SaveFile(path)
    path = path or self.filepath
    if not path then
        self:SetCommandText("No file to save to")
        return false
    end
    local fd = FS.Open(path, FS.OPEN_TRUNCATE)
    if not fd then
        self:SetCommandText(strformat("Unable to open file: %s", path))
        return false
    else
        local ok = FS.Write(fd, self.buffer:GetText())
        FS.Close(fd)
        if not ok then
            self:SetCommandText(strformat("Writing to %s failed", path))
            return false
        else
            self:SetCommandText(strformat("Wrote %s", path))
            self.buffer:ClearDirty()
            self:SetFilePath(path)
            return true
        end
    end
end


-------- Miscellaneous utility functions

-- Set the mark at the current cursor position.
function EditorFrame:SetMark()
    self.buffer:SetMarkPos(self.buffer:GetCursorPos())
    self:SetCommandText("Mark set")
end

-- Set a key binding for the current editor frame.
-- |keyseq| is either a single key (see the description of self.keymap) of
-- list of keys for a multi-key sequence.  If a key previously assigned as
-- a prefix (e.g. C-X in the default keymap) is bound directly, all
-- bindings using that prefix are deleted; conversely, using a bound key
-- in a sequence prefix deletes that existing binding.
-- |func| is the function to call when the key sequence is pressed.  The
-- function receives the EditorFrame instance, the name of the last key
-- pressed (with any modifiers prepended), and the translated character
-- (nil if the key has no text equivalent).
function EditorFrame:BindKey(keyseq, func)
    if type(keyseq) == "string" then
        keyseq = {keyseq}
    else
        assert(type(keyseq) == "table", "keyseq must be a string or table")
        assert(#keyseq > 0, "keyseq must not be an empty list")
    end
    assert(type(func) == "function", "func must be a function")
    local parent = self.keymap
    for i = 1, #keyseq-1 do
        local key = keyseq[i]
        if type(parent[key]) ~= "table" then
            parent[key] = {}
        end
        parent = parent[key]
    end
    parent[keyseq[#keyseq]] = func
end

-- Set the file path for this frame, and update the frame name appropriately.
function EditorFrame:SetFilePath(path)
    assert(type(path) == "string", "path must be a string")
    self.filepath = path
    self.name = strmatch(path, "([^/]+)$") or path
    self:UpdateTitle()
end

-- Return the file path associated with this frame, or nil if none.
function EditorFrame:GetFilePath()
    return self.filepath
end

-- Set the name for this frame.  Overrides any name set from the file path.
function EditorFrame:SetName(name)
    assert(type(name) == "string", "name must be a string")
    self.name = name
end

-- Set the buffer text for this frame.  If |move_to_end| is true, also
-- move the cursor to the end of the text; otherwise, leave it at the
-- beginning.  To avoid data loss, this function can only be used when
-- the frame has no associated file and its buffer is clean (unedited).
function EditorFrame:SetText(text, move_to_end)
    assert(type(text) == "string", "text must be a string")
    if self.filepath then
        error("Cannot be used when frame has an associated file")
    end
    if self.buffer:IsDirty() then
        error("Cannot be used when frame's buffer is dirty")
    end
    self.buffer:SetText(text)
    if move_to_end then
        self.buffer:MoveCursor("C-END")
    end
end

-- Close this editor window.
function EditorFrame:Close()
    if self.in_update then
        -- Don't actually close until OnUpdate() returns, to avoid
        -- worrying about use-after-free in that routine.
        self.pending_close = true
        return
    end
    self.manager:CloseFrame(self)
end


-------- Base command line processing

-- Emacs has sensible reasons for implementing the command line as a buffer
-- of its own (the "minibuffer"), but that's overkill for our purposes; we
-- suffer a bit of code duplication for the sake of less overall complexity.


-- Display the given text on the command line.  The text will be cleared
-- on the next key input.  The command line is formatted as follows:
--
-- - If |text| is not nil, it will be displayed after |prefix|, and the
--   cursor will be displayed at its end.
--
-- - If |suffix| is not nil, it will be displayed after |text|.
--
-- If the combined text extends past the width of the frame, it is
-- truncated according to the following priority:
--
-- - If |prefix| extends past the width of the frame, it will be truncated
--   at the end and neither |text| nor |suffix| will be displayed (but the
--   cursor will be displayed at the end of the line if |text| is not nil).
--
-- - Otherwise, if |suffix| is not nil and the combination of |prefix| and
--   |suffix| extends past the width of the frame, |suffix| will be
--   truncated at the end and |text| will not be displayed.
--
-- - Otherwise, |text| will be truncated if necessary at the beginning.
function EditorFrame:SetCommandText(prefix, text, suffix)
    local limit =
        floor((self.CommandLine.Text:GetWidth() + 0.5) / self.command_cell_w)
    suffix = suffix or ""
    local str, cursor_pos
    if #prefix > limit then
        str = strsub(prefix, 1, limit-3) .. "..."
        cursor_pos = text and #str
    elseif #(prefix..suffix) > limit then
        str = strsub(prefix..suffix, 1, limit-3) .. "..."
        cursor_pos = text and (#prefix > limit-3 and limit or #prefix)
    else
        limit = limit - #prefix - #suffix
        if text then
            if limit <= 3 then
                text = strsub("...", 1, limit)
            elseif #text > limit then
                text = "..." .. strsub(text, (#text+1) - (limit-3))
            end
            str = prefix..text..suffix
            cursor_pos = #(prefix..text)
        else
            str = prefix..suffix
        end
    end
    self.CommandLine.Text:SetText(strgsub(str, "|", "||"))
    self.command_cursor_pos = cursor_pos
end

-- Clear any currently active command, then start processing for the given
-- command.  |command| is an instance of CommandHandler (or a subclass).
function EditorFrame:StartCommand(command)
    self:ClearCommand()
    if command:Start() then
        self.command = command
    end
end

-- Clear any current command state and any displayed text on the command line.
-- If a command is currently active and has an EndCommand handler, that
-- handler is called after clearing the command line text (so it can
-- display a final status message if appropriate).
function EditorFrame:ClearCommand()
    local command = self.command
    self.command = nil
    self:SetCommandText("")
    if command then
        command:End()
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
-- incremental search handler for an example).
function EditorFrame:HandleCommandInput(input, arg)
    local handler
    if self.command then
        return self.command:HandleInput(input, arg)
    end
end


-------- Base classes for command implementations

local CommandHandler = class()

-- The default constructor accepts the EditorFrame instance and saves it
-- in self.frame for subsequent use.
function CommandHandler:__constructor(frame)
    self.frame = frame
end

-- Start processing for the command.  If this method does not return true,
-- the command is aborted (End() is not called in this case).
function CommandHandler:Start()
    return true
end

-- Handle an input event.  |input| and |arg| are as for
-- EditorFrame:HandleCommandInput().  The input is considered consumed
-- if the method returns true.
function CommandHandler:HandleInput(input, arg)
end

-- Clean up when the command is terminated.
function CommandHandler:End()
end


-- This subclass implements standard input handling for commands that
-- accept a simple string entered on the command line.  The string is
-- stored in self.input.
local InputCommandHandler = class(CommandHandler)

-- The constructor accepts an additional optional argument which
-- specifies the prompt prepended to the input text on the command line.
function InputCommandHandler:__constructor(frame, prompt)
    __super(self, frame)
    self.prompt = prompt or ""
end

function InputCommandHandler:Start()
    self.input = ""
    self:SetCommandText()
    return true
end

function InputCommandHandler:HandleInput(input, arg)
    if input == "CHAR" then
        local ch = arg
        self.input = self.input .. ch
        self:SetCommandText()
        return true
    elseif input == "BACKSPACE" then
        if #self.input > 0 then
            self.input = strsub(self.input, 1, #self.input-1)
        end
        self:SetCommandText()
        return true
    elseif input == "ENTER" then
        self.frame:ClearCommand()
        self:ConfirmInput(self.input)
        return true
    end
end

-- Called to update the command line text.  The base implementation
-- simply displays the prompt from the constructor followed by the
-- current input text.
function InputCommandHandler:SetCommandText()
    self.frame:SetCommandText(self.prompt, self.input)
end

-- Called when the input is confirmed with Enter.  The command has already
-- been cleared.
function InputCommandHandler:ConfirmInput(input)
end


-- Variant of InputCommandHandler which handles absolute path input,
-- treating a double slash as the beginning of a new absolute path and
-- stripping the preceding text.
local PathInputCommandHandler = class(InputCommandHandler)

-- Helper to split the input string at a double slash.
local function SplitPathInput(input)
    local before, after = strmatch(input, "^(.*/)(/.*)$")
    if after then
        return before, after
    else
        return nil, input
    end
end

-- The default for path input is the directory containing the current
-- file path if the frame has an associated file.
function PathInputCommandHandler:Start()
    self.input =
        self.frame.filepath and strmatch(self.frame.filepath, "^(.*/)") or ""
    self:SetCommandText()
    return true
end

function PathInputCommandHandler:HandleInput(input, arg)
    if input == "ENTER" then
        self.frame:ClearCommand()
        local _, path = SplitPathInput(self.input)
        self:ConfirmInput(path)
        return true
    elseif input == "TAB" then
        local before, path = SplitPathInput(self.input)
        before = before or ""
        if strsub(path, 1, 1) ~= "/" then
            self:SetCommandText("Path is not absolute")
        else
            local dir, name = strmatch(path, "^(.*/)(.*)$")
            assert(name)
            local entries = FS.ListDirectory(dir)  -- Trailing slash is fine.
            if not entries then
                self:SetCommandText("Directory not found")
            else
                local matches = list()
                for _, entry in ipairs(entries) do
                    if strsub(entry, 1, #name) == name then
                        matches:append(entry)
                    end
                end
                if #matches == 0 then
                    self:SetCommandText("No match")
                elseif #matches == 1 then
                    local new_path = dir .. matches[1]
                    local st = FS.Stat(new_path)
                    if st and st.is_dir then
                        new_path = new_path .. "/"
                    end
                    self.input = before .. new_path
                    local info
                    if new_path == dir .. name then
                        info = "Sole completion"
                    end
                    self:SetCommandText(info)
                else
                    matches:sort()
                    local first, last = matches[1], matches[#matches]
                    assert(first ~= last)
                    local common_len = #name
                    while strsub(first, 1, common_len+1) == strsub(last, 1, common_len+1) do
                        common_len = common_len + 1
                    end
                    self.input = before .. dir .. strsub(first, 1, common_len)
                    local info
                    if common_len == #name then
                        info = "Multiple completions"
                    end
                    self:SetCommandText(info)
                end
            end
        end
    else
        return __super(self, input, arg)
    end
end

function PathInputCommandHandler:SetCommandText(info)
    local before, after = SplitPathInput(self.input)
    local s
    if before then
        s = strformat("{%s} %s", before, after)
    else
        s = after
    end
    self.frame:SetCommandText(self.prompt, s,
                              info and strformat(" [%s]", info))
end


-------- Command-specific implementations

-- Convert the given Emacs regular expression |re| to a Lua pattern.
-- Returns nil if the string is not a valid regular expression.
-- Helper for the various regular expression search commands.
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

local CloseCommand = class(CommandHandler)

function CloseCommand:SetCommandText()
    local s
    if self.error_timeout then
        s = "Please enter y or n."
        if GetTime() >= self.error_timeout then
            self.error_timeout = nil
        end
    elseif self.state == "confirm-save" then
        s = "Save changes? (y or n) "
    else
        assert(self.state == "confirm-quit")
        s = "Buffer is modified; close anyway? (y or n) "
    end
    self.frame:SetCommandText(s, "")
end

function CloseCommand:Start()
    if self.filepath and self.frame.buffer:IsDirty() then
        self.state = "confirm-save"
        self.error_timeout = nil
        self:SetCommandText()
        return true
    else
        self.frame:Close()
        return false
    end
end

function CloseCommand:HandleInput(input, arg)
    if input == "CHAR" and arg == "y" then
        self.frame:ClearCommand()
        if self.state == "confirm-save" then
            if self.frame:SaveFile() then
                self.frame:Close()
            end
        else
            assert(self.state == "confirm-quit")
            self.frame:Close()
        end
        return true
    elseif input == "CHAR" and arg == "n" then
        if self.state == "confirm-save" then
            self.state = "confirm-quit"
            self:SetCommandText()
        else
            assert(self.state == "confirm-quit")
            self.frame:ClearCommand()
        end
        return true
    elseif input ~= "CANCEL" then
        self.error_timeout = GetTime() + 1
        self:SetCommandText()
        return true
    end
end


local FindFileCommand = class(PathInputCommandHandler)

function FindFileCommand:__constructor(frame)
    __super(self, frame, "Find file: ")
end

function FindFileCommand:ConfirmInput(path)
    if not self.filepath then
        self.frame:LoadFile(path)
    else
        Editor.Open(path)
    end
end


local GoToLineCommand = class(InputCommandHandler)

function GoToLineCommand:__constructor(frame)
    __super(self, frame, "Goto line: ")
end

function GoToLineCommand:ConfirmInput(input)
    local line = tonumber(self.input)
    if line and line > 0 and line == floor(line) then
        self.frame:SetMark()
        self.frame.buffer:SetCursorPos(line, 0)
    else
        self.frame:SetCommandText("Line number must be a positive integer")
    end
end


local InsertFileCommand = class(PathInputCommandHandler)

function InsertFileCommand:__constructor(frame)
    __super(self, frame, "Insert file: ")
end

function InsertFileCommand:ConfirmInput(path)
    local data = FS.ReadFile(path)
    if data then
        self.frame.buffer:InsertText(data)
    else
        self.frame:SetCommandText(strformat("Failed to read file: %s", path))
    end
end


local IsearchCommand = class(CommandHandler)

function IsearchCommand:__constructor(frame, forward, regex)
    __super(self, frame)
    self.forward = forward
    self.regex = regex
end

function IsearchCommand:SetCommandText(info)
    local prompt = strformat("%s%s%sI-search%s: ",
                             self.failing and "failing " or "",
                             self.wrapped and "wrapped " or "",
                             self.regex and "regexp " or "",
                             self.forward and "" or " backward")
    prompt = strsub(prompt,1,1):upper() .. strsub(prompt,2)
    local suffix = info and " ["..info.."]"
    self.frame:SetCommandText(prompt, self.text, suffix)
end

-- Helper to update search state and set the command line.
function IsearchCommand:Update()
    if #self.text > 0 then
        local str
        if self.regex then
            str = RegexToPattern(self.text)
            if not str then
                self:SetCommandText("incomplete input")
                return
            end
        else
            str = self.text
        end
        if self.frame.buffer:IsMarkActive() then
            -- If the mark is active, it implies we just edited the search
            -- text (since we clear the mark on start and on a "next match"
            -- input), so move the cursor to the mark (which is set at the
            -- opposite side of the match) and search again from the
            -- current match position.
            self.frame.buffer:SetCursorPos(self.frame.buffer:GetMarkPos())
            self.frame.buffer:ClearMark()
        end
        local highlight = true
        self.failing = not self.frame.buffer:Search(str, self.regex, self.case,
                                                    self.forward, highlight)
        if not self.failing then
            self.last_success = self.text
        end
    else
        self.frame.buffer:SetCursorPos(unpack(self.initial_cursor))
    end
    self:SetCommandText()
end

function IsearchCommand:Start()
    self.case = false
    self.initial_cursor = {self.frame.buffer:GetCursorPos()}
    self.initial_mark = {self.frame.buffer:GetMarkPos()}
    self.text = ""
    self.last_success = ""  -- Last successfully matched string.
    self.failing = false
    self.wrapped = false

    self.frame.buffer:ClearMark()
    self:SetCommandText()
    return true
end

function IsearchCommand:End()
    if self.initial_cursor then
        self.frame.buffer:SetMarkPos(unpack(self.initial_cursor))
        self.frame:SetCommandText("Mark saved where search started")
    end
end

function IsearchCommand:HandleInput(input, arg)
    if input == "CHAR" then
        local ch = arg
        self.text = self.text .. ch
        self:Update()
        return true
    elseif input == "BACKSPACE" then
        if #self.text > 0 then
            self.text = strsub(self.text, 1, #self.text-1)
        end
        self:Update()
        return true
    elseif input == "CANCEL" then
        if self.failing then
            self.text = self.last_success
            self:Update()
        else
            self.frame.buffer:SetCursorPos(unpack(self.initial_cursor))
            self.frame.buffer:SetMarkPos(unpack(self.initial_mark))
            self.initial_cursor = nil  -- Don't set mark on EndCommand.
            self.frame:ClearCommand()
            self.frame:SetCommandText("Quit")
        end
        return true
    elseif input == "ENTER" then
        self.frame:ClearCommand()
        if self.text == "" then
            self.frame:StartCommand("search")
        end
        return true
    elseif input == "ISEARCH" then
        local forward = arg
        if forward ~= self.forward then
            self.forward = forward
        elseif self.failing then
            self.wrapped = true
            self.frame.buffer:MoveCursor(self.forward and "C-HOME" or "C-END")
        end
        self.frame.buffer:ClearMark()
        self:Update()
        return true
    elseif input == "ISEARCH_CASE" then
        self.case = not self.case
        local info = self.case and "case sensitive" or "case insensitive"
        self:SetCommandText(info)
        return true
    end
end


local ReplaceCommand = class(InputCommandHandler)

function ReplaceCommand:__constructor(frame, regex)
    __super(self, frame, regex and "Replace regexp" or "Replace string")
    self.regex = regex
end

function ReplaceCommand:Start()
    __super(self)
    self.from = nil
    return true
end

function ReplaceCommand:SetCommandText()
    local prompt
    if self.from then
        prompt = strformat("%s %s with: ", self.prompt, self.from)
    else
        prompt = self.prompt .. ": "
    end
    self.frame:SetCommandText(prompt, self.input)
end

function ReplaceCommand:HandleInput(input, arg)
    if input == "ENTER" and not self.from then
        if self.input == "" then
            self.frame:ClearCommand()
        else
            self.from = self.input
            self.input = ""
            self:SetCommandText()
        end
        return true
    else
        return __super(self, input, arg)
    end
end

function ReplaceCommand:ConfirmInput(input)
    local from, to
    if self.regex then
        from = RegexToPattern(self.from)
        if not str then
            self.frame:SetCommandText("Invalid regexp")
        end
        to = input:gsub("%%", "%%%%")
                  :gsub("\\([0-9])", "%%%1")
    else
        from = self.from
        to = input
    end
    if from and from ~= "" then
        local cur_line, cur_col = self.frame.buffer:GetCursorPos()
        -- Unintended deviation from Emacs behavior: replacing does not
        -- move the cursor to the location of the last replacement
        -- (because Lua provides no easy way to get this without
        -- iterating on the replacements one at a time).
        local n_repl = self.frame.buffer:Replace(from, to, self.regex)
        self.frame:SetCommandText(strformat("Replaced %d occurrences", n_repl))
    end
end


local SaveToCommand = class(PathInputCommandHandler)

function SaveToCommand:__constructor(frame, prompt)
    __super(self, frame, prompt..": ")
end

function SaveToCommand:ConfirmInput(path)
    if path ~= "" then
        self.frame:SaveFile(path)
    end
end


local SearchCommand = class(InputCommandHandler)

function SearchCommand:__constructor(frame, regex)
    __super(self, frame, regex and "RE search: " or "Search: ")
    self.regex = regex
end

function SearchCommand:ConfirmInput(input)
    local str
    if self.regex then
        str = RegexToPattern(self.input)
        if not str then
            self.frame:SetCommandText("Invalid regexp")
        end
    else
        str = self.input
    end
    if str and str ~= "" then
        local cur_line, cur_col = self.frame.buffer:GetCursorPos()
        local has_case = (strfind(self.input, "%u") ~= nil)
        local forward = true
        local highlight = false
        local found = self.frame.buffer:Search(
            str, self.regex, has_case, forward, highlight)
        if found then
            -- Deliberate deviation from Emacs behavior: Set the mark on
            -- a non-incremental search, to match i-search behavior.
            self.frame.buffer:SetMarkPos(cur_line, cur_col)
            self.frame:SetCommandText("Mark saved where search started")
        else
            self.frame:SetCommandText(
                strformat("Search failed: \"%s\"", self.input))
        end
    end
end


-------- Default keymap and handler functions

function EditorFrame:GetDefaultKeymap()
    if not EditorFrame.DEFAULT_KEYMAP then
        EditorFrame.DEFAULT_KEYMAP = {
            ["BACKSPACE"] = EditorFrame.HandleBackspace,
            ["DELETE"] = EditorFrame.HandleDelete,
            ["ENTER"] = EditorFrame.HandleEnter,
            ["TAB"] = EditorFrame.HandleTab,

            ["F2"] = EditorFrame.HandleYank,
            ["F7"] = EditorFrame.HandleFindFile,
            ["F8"] = EditorFrame.HandleInsertFile,
            ["F9"] = EditorFrame.HandleSaveFile,
            ["F10"] = EditorFrame.HandleSaveAndClose,

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
                ["C-C"] = EditorFrame.HandleClose,
                ["C-F"] = EditorFrame.HandleFindFile,
                ["I"] = EditorFrame.HandleInsertFile,
                ["C-S"] = EditorFrame.HandleSaveFile,
                ["C-W"] = EditorFrame.HandleWriteFile,
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
        self.buffer:SetMarkActive(false)
        self:SetCommandText("Quit")
    end
end

function EditorFrame:HandleClose()
    self:StartCommand(CloseCommand(self))
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
    self:StartCommand(FindFileCommand(self))
end

function EditorFrame:HandleGoToLine()
    self:StartCommand(GoToLineCommand(self))
end

function EditorFrame:HandleInsertFile()
    self:StartCommand(InsertFileCommand(self))
end

function EditorFrame:HandleIsearch(forward, regex)
    if not self:HandleCommandInput("ISEARCH", forward) then
        self:StartCommand(IsearchCommand(self, forward, regex))
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

function EditorFrame:HandleKillLine(key)
    if not self:HandleCommandInput("KILL-LINE") then
        self:ClearCommand()
        local text = self.buffer:DeleteToEndOfLine()
        if text then
            if key == self.prev_key then
                self.yank_text = self.yank_text .. text
            else
                self.yank_text = text
            end
        end
    end
end

function EditorFrame:HandleMakeCapital()
    if not self:HandleCommandInput("ISEARCH_CASE", forward) then
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
    self:StartCommand(ReplaceCommand(self, regex))
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
        self:StartCommand(SaveToCommand(self, "File to save in"))
    else
        self:SaveFile()
    end
end

function EditorFrame:HandleSaveAndClose()
    if self.buffer:IsDirty() and self.filepath then
        if not self:SaveFile() then
            return
        end
    end
    self:Close()
end

function EditorFrame:HandleSearch(regex)
    self:StartCommand(SearchCommand(self, regex))
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

function EditorFrame:HandleSetMark(key)
    self:SetMark()
    if key == self.prev_key then
        self.buffer:SetMarkActive(true, true)
        self:SetCommandText("Mark activated")
    end
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

function EditorFrame:HandleTab()
    self:HandleCommandInput("TAB")
end

function EditorFrame:HandleWriteFile()
    self:StartCommand(SaveToCommand(self, "Write file"))
end

function EditorFrame:HandleYank()
    if not self:HandleCommandInput("YANK") then
        self:ClearCommand()
        if self.yank_text then
            self.buffer:InsertText(self.yank_text)
        end
    end
end
