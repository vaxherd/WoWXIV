local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor

local class = WoWXIV.class
local Frame = WoWXIV.Frame
local list = WoWXIV.list
local set = WoWXIV.set

local floor = math.floor
local min = math.min
local round = function(x) return floor(x+0.5) end
local strbyte = string.byte
local strfind = string.find
local strformat = string.format
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub


-- Constant larger than any reasonably-sized line, used to force the
-- cursor to the end of a line.
local END_OF_LINE = 999999999


---------------------------------------------------------------------------
-- Text buffer implementation
--
-- Stores the text content of an editor window and manages text rendering.
--
-- FIXME: There's probably an argument for splitting editing and rendering
-- functionality.  I can't be bothered because the addon will be dead in a
-- few months anyway.
---------------------------------------------------------------------------

local Buffer = class()
Editor.Buffer = Buffer

function Buffer:__constructor(text, view)
    assert(type(text) == "string", "text must be a string")
    assert(type(view) == "table" and type(view.Show) == "function",
           "view must be a Frame")

    self.view = view
    self.cursor = view:CreateTexture(nil, "OVERLAY")
    self.cursor:SetColorTexture(1, 1, 1)
    self.cursor:SetPoint("TOP", view, "TOPLEFT")
    self.show_cursor = true

    -- We differentiate in naming between "lines" (logical lines of text
    -- as delimited by newline characters) and "strings" (fragments of a
    -- logical line which fit on a single physical line).
    -- FIXME: "string" is a terrible term because we'll confuse it with
    -- other uses of the word; any better options?
    self.strings = list(text)   -- The buffer text, broken up into strings.
    self.line_map = list(1)     -- Map from physical line to string index.
    self.cur_line = 1           -- Logical cursor position.
    self.cur_col = 0
    self.top_string = 1         -- Index of the topmost displayed string.
    self.linepool_free = set()  -- Pool of created but unused FontStrings.
    self.linepool_used = set()  -- FontStrings which are currently in used.
    self.on_scroll = nil        -- Callback for scroll events.

    self:InitScrollBar()
    self:MeasureView()
    self:LayoutText()
    self:RefreshView()
end

-- Set a function to be called whenever the text view is scrolled using the
-- scrollbar widget.  Pass nil to remove any previously set callback.
function Buffer:SetScrollCallback(func)
    self.on_scroll = func
end

-- Return the text content of the buffer as a string.
function Buffer:GetText()
    local text = ""
    local line = 1
    for s = 1, #self.strings do
        if line < #self.line_map and s == self.line_map[line+1] then
            text = text .. "\n"
            line = line+1
        end
        text = text .. self.strings[s]
    end
    return text
end

-- Set whether the text cursor should be displayed.
function Buffer:SetShowCursor(show)
    self.show_cursor = not not show  -- Force to boolean.
    self.cursor:SetShown(show)
end

-- Set the cursor position within the buffer.
function Buffer:SetCursorPos(line, col)
    assert(type(line) == "number" and line > 0 and floor(line) == line,
           "line must be a positive integer")
    assert(type(col) == "number" and col >= 0 and floor(col) == col,
           "col must be a nonnegative integer")
    self:SetCursorPosInternal(line, col)
    self:RefreshView()
end

-- Set the cursor position based on graphical coordinates (such as from a
-- mouse click).  |x| and |y| should be relative to the top left corner of
-- the text view frame, with |y| increasing downward.
function Buffer:SetCursorPosFromMouse(x, y)
    assert(type(x) == "number", "x must be a number")
    assert(type(y) == "number", "y must be a number")
    local rel_s = max(0, min(self.view_lines-1, floor(y / self.cell_h)))
    local c = max(0, min(self.view_columns-1, floor(x / self.cell_w)))
    local s = min(self.top_string + rel_s, #self.strings)
    self:SetCursorPosFromStringPos(s, c)
    self:RefreshView()
end

-- Return the current cursor position.
function Buffer:GetCursorPos()
    local line, col = self.cur_line, self.cur_col
    -- Temporarily clamp to line length to return the actual column.
    self:SetCursorPosInternal(line, col)
    local clamped_col = self.cur_col
    -- Restore original column.
    self.cur_col = col
    return line, clamped_col
end

-- Return the character at the current cursor position, or the empty
-- string if the cursor is at the end of a line.
function Buffer:GetCharAtCursor()
    local s, c = self:GetStringPos()
    return strsub(self.strings[s], c+1, c+1)
end

-- Return whether the cursor is currently on an empty line.
function Buffer:IsCursorOnEmptyLine()
    local line = self.cur_line
    local s = self.line_map[line]
    local next = (line < #self.line_map
                  and self.line_map[line+1] or #self.line_map)
    return next == s+1 and #self.strings[s] == 0
end

-- Move the cursor in the specified manner.  |dir| is a directional key
-- name with optional Emacs-style modifier prefix.
function Buffer:MoveCursor(dir)
    if dir == "UP" then
        if self.cur_line > 1 then
            self:SetCursorPosInternal(self.cur_line-1, self.cur_col, true)
        else
            self:SetCursorPosInternal(1, 0)
        end

    elseif dir == "C-UP" then
        -- The end result of this will be that either the cursor is on an
        -- empty line (at column 0) or a non-blank line 1 (and thus set to
        -- column 0 for trying to move past the beginning of the file), so
        -- we can unconditionally set column 0 here.
        while self.cur_line > 1 and self:IsCursorOnEmptyLine() do
            self:SetCursorPosInternal(self.cur_line-1, 0)
        end
        while self.cur_line > 1 and not self:IsCursorOnEmptyLine() do
            self:SetCursorPosInternal(self.cur_line-1, 0)
        end

    elseif dir == "DOWN" then
        if self.cur_line < #self.line_map then
            self:SetCursorPosInternal(self.cur_line+1, self.cur_col, true)
        else
            -- Let SetCursorPosInternal() find the end of the line.
            self:SetCursorPosInternal(#self.line_map, END_OF_LINE)
        end

    elseif dir == "C-DOWN" then
        while self.cur_line < #self.line_map and self:IsCursorOnEmptyLine() do
            self:SetCursorPosInternal(self.cur_line+1, END_OF_LINE)
        end
        while self.cur_line < #self.line_map and not self:IsCursorOnEmptyLine() do
            self:SetCursorPosInternal(self.cur_line+1, END_OF_LINE)
        end

    elseif dir == "LEFT" then
        if self.cur_col > 0 then
            -- cur_col might be past the end of the line (after up/down
            -- movement from a longer line), so first force it to the
            -- actual end of the line.
            self:SetCursorPosInternal(self.cur_line, self.cur_col)
            self:SetCursorPosInternal(self.cur_line, self.cur_col-1)
        elseif self.cur_line > 1 then
            self.cur_line = self.cur_line - 1
            local s, _, first, last = self:GetStringPos()
            local len = 0
            for i = first, last do
                len = len + #self.strings[i]
            end
            self.cur_col = len
        end

    elseif dir == "C-LEFT" then
        self:MoveToWord(false)

    elseif dir == "RIGHT" then
        local s, c, first, last = self:GetStringPos()
        if s == #self.strings and c == #self.strings[s] then
            -- Already at the end of the last line, nothing to do.
        elseif s < last or c < #self.strings[s] then
            self.cur_col = self.cur_col + 1
        else
            self.cur_line = self.cur_line + 1
            self.cur_col = 0
        end

    elseif dir == "C-RIGHT" then
        self:MoveToWord(true)

    elseif dir == "HOME" then
        self:SetCursorPosInternal(self.cur_line, 0)

    elseif dir == "C-HOME" then
        self:SetCursorPosInternal(1, 0)

    elseif dir == "END" then
        self:SetCursorPosInternal(self.cur_line, END_OF_LINE)

    elseif dir == "C-END" then
        self:SetCursorPosInternal(#self.line_map, END_OF_LINE)

    else
        error("Invalid movement direction: "..tostring(dir))
    end

    self:RefreshView()
end

-- Insert character |ch| at the current cursor position and advance the
-- cursor by one character.  If this moves the cursor outside the current
-- view range (because it wrapped past the end of the last displayed
-- string), recenter the cursor in the view.
function Buffer:InsertChar(ch)
    assert(type(ch) == "string" and #ch == 1,
           "ch must be a one-character string")
    local s, c, first, last = self:GetStringPos()
    local str = self.strings[s]
    if s == last and #str < self.view_columns - 1 then
        -- Trivial case: we're on the last string of a logical line and
        -- adding this character won't overflow the string.
        self.strings[s] = strsub(str, 1, c) .. ch .. strsub(str, c+1)
    else
        -- Some sort of wrapping is required.
        for i = s, last-1 do
            str = self.strings[i]
            self.strings[i] =
                strsub(str, 1, c) .. ch .. strsub(str, c+1, #str-1)
            ch = strsub(str, #str)
            c = 0
        end
        str = ch .. self.strings[last]
        local width = self.view_columns
        if #str < width then
            self.strings[last] = str
        else
            -- We overflowed the last string of the line, so insert a new
            -- string.
            assert(#str == width)
            self.strings[last] = strsub(str, 1, width-1)
            self.strings:insert(last+1, strsub(str, width))
            for i = self.cur_line+1, #self.line_map do
                self.line_map[i] = self.line_map[i] + 1
            end
            s = s+1  -- Focus the cursor's new string, not the old one.
        end
    end
    self.cur_col = self.cur_col + 1
    self:RefreshView()
end

function Buffer:InsertNewline()
    local s, c, first, last = self:GetStringPos()
    local cur_line = self.cur_line
    local str = self.strings[s]
    local added_string = false

    -- The logical cursor position will always advance to the beginning of
    -- the next line, so update it now.
    self.cur_line = cur_line + 1
    self.cur_col = 0

    -- Special case: breaking a line right after a wrap point doesn't
    -- move the physical cursor position.
    if s > first and c == 0 then
        self.line_map:insert(cur_line+1, s)
        return
    end

    -- In all other cases, the cursor will move to the next string.

    if s == first and c == 0 then
        -- Inserting a blank line before the current line.
        self.strings:insert(s, "")
        added_string = true

    elseif s == last and c == #str then
        -- Inserting a blank line after the current line.
        self.strings:insert(s+1, "")
        added_string = true

    else
        -- Breaking an existing line.  We have to re-wrap the new line.
        self.strings[s] = strsub(str, 1, c)
        local line = strsub(str, c+1)
        for i = s+1, last do
            line = line .. self.strings[i]
        end
        local width = self.view_columns
        local i = s+1
        while #line >= width do
            assert(i <= last)
            self.strings[i] = strsub(line, 1, width-1)
            line = strsub(line, width)
            i = i+1
        end
        if i == last+1 then
            self.strings:insert(i, line)
            added_string = true
        else
            assert(i == last)
            self.strings[i] = line
        end
    end

    local line_map = self.line_map
    line_map:insert(cur_line+1, s+1)
    if added_string then
        for i = cur_line+2, #line_map do
            line_map[i] = line_map[i] + 1
        end
    end

    self:RefreshView()
end

-- Delete one character either before (|forward| false) or after
-- (|forward| true) the current cursor position.  Does nothing if there
-- is no character to delete in the specified direction.
function Buffer:DeleteChar(forward)
    if not forward then
        if self.cur_line == 1 and self.cur_col == 0 then
            return  -- Already at the beginning of the buffer.
        end
        self:MoveCursor("LEFT")
    end

    local s, c, first, last = self:GetStringPos()
    if s == #self.strings and c == #self.strings[s] then
        assert(forward)  -- Impossible if we just moved left.
        return  -- Already at the end of the buffer.
    end

    local str = self.strings[s]
    if c == #str then
        -- Deleting a newline.
        assert(s == last)
        assert(self.cur_line < #self.line_map)
        last = self.line_map:pop(self.cur_line+1)
    else
        -- Deleting a character within a line.
        str = strsub(str, 1, c) .. strsub(str, c+2)
    end
    for i = s+1, last do
        str = str .. self.strings[i]
    end
    local width = self.view_columns
    while #str >= width do
        self.strings[s] = strsub(str, 1, width-1)
        str = strsub(str, width)
        s = s+1
    end
    self.strings[s] = str
    if s < last then
        assert(s == last-1)
        self.strings:pop(s+1)
        for i = self.cur_line+1, #self.line_map do
            self.line_map[i] = self.line_map[i]-1
        end
    end

    self:RefreshView()
end


-------- The remaining methods and variables are private.

-- Set of characters in a "word" for MoveToWord().
local WORD_CHARS = set()
for i = 0, 9 do
    WORD_CHARS:add(48+i)  -- "0".."9"
end
for i = 0, 25 do
    WORD_CHARS:add(65+i)  -- "A".."Z"
    WORD_CHARS:add(97+i)  -- "a".."z"
end

-- Move the cursor backward to the next beginning-of-word (|forward| false)
-- or forward to the next end-of-word (|forward| true), where "word" is
-- defined as any sequence of alphanumeric characters.
function Buffer:MoveToWord(forward)
    local line = self.cur_line
    local s, c, line_start, line_end = self:GetStringPos()
    local str = self.strings[s]

    -- has() wrappers.  End-of-line is treated as not in a word.
    local function IsInWord()
        return c < #str and WORD_CHARS:has(strbyte(str, c+1))
    end
    local function NotInWord()
        return c >= #str or not WORD_CHARS:has(strbyte(str, c+1))
    end

    -- Helper to update line_start/line_end after changing logical lines.
    local function UpdateLine()
        line_start = self.line_map[line]
        line_end = (line < #self.line_map
                    and self.line_map[line+1]-1 or #self.strings)
    end

    if forward then
        local function NextChar()
            if c < #str then
                c = c+1
                if c == #str and s < line_end then
                    s = s+1
                    str = self.strings[s]
                    c = 0
                end
            elseif s < #self.strings then
                assert(s == line_end)
                line = line+1
                UpdateLine()
                s = s+1
                assert(s == line_start)
                str = self.strings[s]
                c = 0
            else
                return false
            end
            return true
        end
        while NotInWord() do
            if not NextChar() then break end
        end
        while IsInWord() do
            if not NextChar() then break end
        end

    else  -- backward
        local function PrevChar()
            if c > 0 then
                c = c-1
            elseif s > 1 then
                s = s-1
                str = self.strings[s]
                if s < line_start then
                    line = line-1
                    UpdateLine()
                    assert(s == line_end)
                    c = #str
                else
                    c = #str-1
                end
            else
                return false
            end
            return true
        end
        -- We want to look at the character before the cursor, not the
        -- one after it, so we take an initial step backward here and
        -- then move forward again at the end.
        PrevChar()
        while NotInWord() do
            if not PrevChar() then break end
        end
        local last_line, last_s, last_c = line, s, c
        while IsInWord() do
            last_line, last_s, last_c = line, s, c
            if not PrevChar() then break end
        end
        line, s, c = last_line, last_s, last_c
    end

    for i = self.line_map[line], s-1 do
        c = c + #self.strings[i]
    end
    self:SetCursorPosInternal(line, c)
end

-- Set the cursor position, bounding it to the current buffer size and
-- line length.  If |preserve_col| is true, do not clamp the current
-- column to the line length (used to allow up/down cursor movement to
-- stay at the end of each line regardless of line length).
function Buffer:SetCursorPosInternal(line, col, preserve_col)
    line = min(line, #self.line_map)
    self.cur_line = line

    if not preserve_col then
        local line_start = self.line_map[line]
        local line_end = (line == #self.line_map
                          and #self.strings or self.line_map[line+1] - 1)
        local len = 0
        for i = line_start, line_end do
            len = len + #self.strings[i]
        end
        col = min(col, len)
    end
    self.cur_col = col
end

-- Set the (logical) cursor position to match the given string index and
-- column.  The new position is assumed to be "near" the current position
-- (and thus we do a simple linear search from the current position rather
-- than a binary search over the entire buffer).
function Buffer:SetCursorPosFromStringPos(s, c)
    local line = self.cur_line
    local line_map = self.line_map
    while line > 1 and s < line_map[line] do
        line = line-1
    end
    while line < #line_map and s >= line_map[line+1] do
        line = line+1
    end
    local strings = self.strings
    c = min(c, #strings[s])
    for i = line_map[line], s-1 do
        c = c + #strings[i]
    end
    self.cur_line, self.cur_col = line, c
end

-- Return the current cursor position as a string index and and offset into
-- that string, along with the indexes of the first and last strings for
-- the current logical line.
function Buffer:GetStringPos()
    local line_start = self.line_map[self.cur_line]
    local line_end = (self.cur_line == #self.line_map
                      and #self.strings or self.line_map[line_start+1] - 1)
    local c = self.cur_col
    for s = line_start, line_end do
        local len = #self.strings[s]
        if c < len then
            return s, c, line_start, line_end
        elseif s == line_end then  -- At or past the end of the line.
            return s, len, line_start, line_end
        end
        c = c - len
    end
    error("unreachable")
end

-- Set up the scroll bar widget in the text view frame.
function Buffer:InitScrollBar()
    local scrollbar = self.view.ScrollBar

    -- Suppress the up/down arrow buttons, and extend the track to the
    -- entire height of the frame.
    scrollbar.Back:Hide()
    scrollbar.Forward:Hide()
    scrollbar.Track:ClearAllPoints()
    scrollbar.Track:SetPoint("TOP")
    scrollbar.Track:SetPoint("BOTTOM")

    -- Override default scroll bar behavior to always display the thumb
    -- widget even when it covers the entire track.
    scrollbar.HasScrollableExtent = function() return true end

    scrollbar:Init(0, 0)
    scrollbar:RegisterCallback("OnScroll",
                               function(_,target) self:OnScroll(target) end)
end

function Buffer:MeasureView()
    local line = self:AcquireLine()
    -- Measuring a single character doesn't seem to give us correct values,
    -- so measure the difference between two widths instead.
    line:SetText("X")
    local w1 = line:GetStringWidth()
    line:SetText("XXXXXXXXXXX")
    local w11 = line:GetStringWidth()
    self.cell_w = (w11 - w1) / 10
    self.cell_h = line:GetStringHeight()
    self:ReleaseLine(line)
    self.view_columns = floor((self.view:GetWidth() + 0.5) / self.cell_w)
    self.view_lines = floor((self.view:GetHeight() + 0.5) / self.cell_h)
    self.cursor:SetHeight(self.cell_h)
end

function Buffer:LayoutText()
    local wrap = self.view_columns - 1
    local text = self:GetText()
    local len = #text
    local strings = self.strings
    local line_map = self.line_map

    strings:clear()
    line_map:clear()
    local s = 1
    line_map:append(s)
    local pos = 1
    while pos <= len do
        local lf = strstr(text, "\n", pos)
        local eol = lf or len+1
        if eol - pos > wrap then
            strings[s] = strsub(text, pos, pos+(wrap-1))
            pos = pos + wrap
        else
            strings[s] = strsub(text, pos, eol)
            pos = eol+1
            if lf then
                line_map:append(s+1)
            end
        end
        s = s+1
    end
    if line_map[#line_map] == #strings+1 then
        strings[#strings+1] = ""  -- Empty line at the end of the buffer.
    end
end

-- Redisplay the current view and update the cursor display state.
-- If |recenter| is true or omitted and the string corresponding to the
-- current cursor position is not displayed, shift the viewport to display
-- that string in the middle.
function Buffer:RefreshView(recenter)
    local top_string = self.top_string
    local bottom_ofs = self.view_lines - 1
    if recenter ~= false then
        local focus_s = self:GetStringPos()
        if focus_s < top_string or focus_s > top_string + bottom_ofs then
            local top_limit = #self.strings - bottom_ofs
            top_string = max(1, min(top_limit, focus_s - floor(bottom_ofs/2)))
            assert(top_string >= 1)
            assert(top_string + bottom_ofs <= #self.strings)
            self.top_string = top_string
        end
    end

    local top_line = self.cur_line
    while top_line > 1 and self.line_map[top_line] > top_string do
        top_line = top_line - 1
    end

    self:ReleaseAllLines()
    local prev
    local line = top_line
    for i = top_string, min(top_string + bottom_ofs, #self.strings) do
        local str = self.strings[i]
        local is_final
        if line < #self.line_map then
            is_final = (i == self.line_map[line+1] - 1)
        else
            is_final = (i == #self.strings)
        end
        if is_final then
            line = line+1
        else
            str = str .. "\\"
        end
        local fs = self:AcquireLine()
        fs:ClearAllPoints()
        if prev then
            fs:SetPoint("TOPLEFT", prev, 0, -self.cell_h)
        else
            fs:SetPoint("TOPLEFT")
        end
        fs:SetText(str)
        prev = fs
    end

    local scrollbar = self.view.ScrollBar
    if #self.strings <= self.view_lines then
        scrollbar:SetVisibleExtentPercentage(1)
        scrollbar:SetPanExtentPercentage(0)
        ScrollControllerMixin.SetScrollPercentage(scrollbar, 0)
    else
        scrollbar:SetVisibleExtentPercentage(self.view_lines / #self.strings)
        scrollbar:SetPanExtentPercentage(1 / (#self.strings - self.view_lines))
        ScrollControllerMixin.SetScrollPercentage(
            scrollbar, (self.top_string-1) / (#self.strings - self.view_lines))
    end
    scrollbar:Update()

    self:RefreshCursor()
end

-- Update the cursor display state.
function Buffer:RefreshCursor()
    local s, c = self:GetStringPos()
    local y = (s - self.top_string) * self.cell_h
    local x = c * self.cell_w
    self.cursor:SetPointsOffset(x, -y)
end

-- Callback for scroll bar movement.
function Buffer:OnScroll(target)
    if #self.strings <= self.view_lines then
        return  -- Nothing to scroll.
    end
    local top = round(target * (#self.strings - self.view_lines)) + 1
    if top ~= self.top_string then
        self.top_string = top
        local bottom = top + (self.view_lines - 1)
        local s = self:GetStringPos()
        local new_s = max(top+1, min(bottom-1, s))
        if new_s ~= s then
            self:SetCursorPosFromStringPos(new_s, 0)
        end
        self:RefreshView(false)
        if self.on_scroll then
            self.on_scroll()
        end
    end
end

-- Acquire a FontString instance for a single line of text from the
-- FontString pool.
function Buffer:AcquireLine()
    local line
    if self.linepool_free:len() > 0 then
        line = self.linepool_free:pop()
        line:Show()
    else
        line = self.view:CreateFontString(nil, "ARTWORK", "WoWXIV_EditorFont")
    end
    self.linepool_used:add(line)
    return line
end

-- Release a previously acquired FontString.
function Buffer:ReleaseLine(line)
    line:Hide()
    self.linepool_used:remove(line)
    self.linepool_free:add(line)
end

-- Release all currently acquired FontStrings.
function Buffer:ReleaseAllLines()
    for line in self.linepool_used do
        line:Hide()
        self.linepool_free:add(line)
    end
    self.linepool_used:clear()
end
