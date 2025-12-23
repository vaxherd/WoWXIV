local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor

local class = WoWXIV.class
local list = WoWXIV.list
local set = WoWXIV.set

local floor = math.floor
local max = math.max
local min = math.min
local round = function(x) return floor(x+0.5) end
local strbyte = string.byte
local strfind = string.find
local strformat = string.format
local strgsub = string.gsub
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub


-- Constant larger than any reasonably-sized line, used to force the
-- cursor to the end of a line.
local END_OF_LINE = 999999999

-- Color used for selected text.  (We currently do not perform any
-- background highlighting for the selected region.)
local REGION_COLOR = {0.25, 1, 0.25}


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

function Buffer:__constructor(view)
    assert(type(view) == "table" and type(view.Show) == "function",
           "view must be a Frame")
    self.view = view
    self.cursor = view:CreateTexture(nil, "OVERLAY")
    self.cursor:SetColorTexture(1, 1, 1)
    self.cursor:SetPoint("TOP", view, "TOPLEFT")

    -- We differentiate in naming between "lines" (logical lines of text
    -- as delimited by newline characters) and "strings" (fragments of a
    -- logical line which fit on a single physical line).
    -- FIXME: "string" is a terrible term because we'll confuse it with
    -- other uses of the word; any better options?
    self.strings = list()       -- The buffer text, broken up into strings.
    self.line_map = list()      -- Map from physical line to string index.
    self.dirty = false          -- Have any changes been made?
    self.cur_line = 1           -- Logical cursor position.
    self.cur_col = 0
    self.mark_line = nil        -- Second endpoint of selection, nil if none.
    self.mark_col = nil
    self.mark_active = false    -- True to highlight the region.
    self.top_string = 1         -- Index of the topmost displayed string.
    self.linepool_free = set()  -- Pool of created but unused FontStrings.
    self.linepool_used = set()  -- FontStrings which are currently in used.
    self.on_dirty = nil         -- Callback for buffer-dirty events.
    self.on_scroll = nil        -- Callback for scroll events.

    self:InitScrollBar()
    self:MeasureView()
end


-------- General utility methods

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

-- Replace the entire text of the buffer with the given string.  The
-- cursor is set to the beginning of the buffer, the mark is cleared,
-- and the buffer is marked not dirty.
function Buffer:SetText(text)
    self:LayoutText(text)
    self.cur_line, self.cur_col = 1, 0
    self.mark_line, self.mark_col, self.mark_active = nil, nil, false
    self.dirty = false
    self:RefreshView()
end

-- Return whether this buffer is empty (that is, whether GetText() would
-- return an empty string).
function Buffer:IsEmpty()
    return #self.strings == 1 and #self.strings[1] == 0
end

-- Return whether the buffer is dirty (has been modified since the last
-- ClearDirty() call).
function Buffer:IsDirty()
    return self.dirty
end

-- Clear the buffer's dirty flag.
function Buffer:ClearDirty()
    self.dirty = false
end

-- Set a function to be called whenever the buffer's dirty flag is set.
-- Pass nil to remove any previously set callback.
function Buffer:SetDirtyCallback(func)
    self.on_dirty = func
end

-- Set a function to be called whenever the text view is scrolled using the
-- scrollbar widget.  Pass nil to remove any previously set callback.
function Buffer:SetScrollCallback(func)
    self.on_scroll = func
end


-------- Cursor/mark management

-- Set whether the text cursor should be displayed.
function Buffer:SetShowCursor(show)
    show = not not show  -- Force to boolean.
    self.cursor:SetShown(show)
end

-- Set the cursor position within the buffer.
function Buffer:SetCursorPos(line, col)
    assert(type(line) == "number" and line > 0 and floor(line) == line,
           "line must be a positive integer")
    assert(type(col) == "number" and col >= 0 and floor(col) == col,
           "col must be a nonnegative integer")
    local clamped_line = min(line, #self.line_map)
    local clamped_col = min(col, self:LineLength(clamped_line))
    self:SetCursorPosInternal(clamped_line, clamped_col)
    self:RefreshView()
end

-- Set the mark position within the buffer.  The mark and cursor position
-- together define the region for region-based operations like killing text.
-- If |active| is true, the region will be highlighted in the text view.
-- Passing nil for both line and col is equivalent to calling ClearMark().
function Buffer:SetMarkPos(line, col, active)
    if line == nil and pos == nil then
        self:ClearMark()
        return
    end
    assert(type(line) == "number" and line > 0 and floor(line) == line,
           "line must be nil or a positive integer")
    assert(type(col) == "number" and col >= 0 and floor(col) == col,
           "col must be nil or a nonnegative integer")
    local clamped_line = min(line, #self.line_map)
    local clamped_col = min(col, self:LineLength(clamped_line))
    self:SetMarkPosInternal(clamped_line, clamped_col)
    self.mark_active = not not active  -- Force to boolean.
    self:RefreshView()
end

-- Activate or deactivate the mark without moving it.
function Buffer:SetMarkActive(active)
    self.mark_active = not not active  -- Force to boolean.
end

-- Clear the buffer's mark.
function Buffer:ClearMark()
    self:SetMarkPosInternal(nil, nil)
    self.mark_active = false
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
    self:SetCursorPosInternal(self:StringToLinePos(s, c))
    self:RefreshView()
end

-- Set the mark position based on graphical coordinates (such as from a
-- mouse drag).  |x| and |y| should be relative to the top left corner of
-- the text view frame, with |y| increasing downward.
function Buffer:SetMarkPosFromMouse(x, y, active)
    assert(type(x) == "number", "x must be a number")
    assert(type(y) == "number", "y must be a number")
    local rel_s = max(0, min(self.view_lines-1, floor(y / self.cell_h)))
    local c = max(0, min(self.view_columns-1, floor(x / self.cell_w)))
    local s = min(self.top_string + rel_s, #self.strings)
    local line, col = self:StringToLinePos(s, c)
    active = not not active  -- Force to boolean.
    -- Don't RefreshView unless the mark has actually changed, to avoid
    -- excessive CPU load if we're called every frame during a drag.
    local compare_line, compare_col
    if self.mark_line then
        compare_line, compare_col = self.mark_line, self.mark_col
    else
        compare_line, compare_col = self.cur_line, self.cur_col
    end
    if line ~= compare_line or col ~= compare_col or active ~= self.mark_active
    then
        self:SetMarkPosInternal(line, col)
        self.mark_active = active
        self:RefreshView()
    end
end

-- Return the current cursor position.
function Buffer:GetCursorPos()
    return self.cur_line, min(self.cur_col, self:LineLength(self.cur_line))
end

-- Return the current mark position, or nil if the mark is not set.
function Buffer:GetMarkPos()
    if self.mark_line then
        return self.mark_line, min(self.mark_col,
                                   self:LineLength(self.mark_line))
    else
        return nil, nil
    end
end

-- Return whether the mark is currently active.
function Buffer:IsMarkActive()
    return self.mark_line ~= nil and self.mark_active
end

-- Return whether the cursor is currently on an empty line.
function Buffer:IsCursorOnEmptyLine()
    return self:IsEmptyLine(self.cur_line)
end

-- Move the cursor in the specified manner.  |dir| is a directional key
-- name with optional Emacs-style modifier prefix.
function Buffer:MoveCursor(dir)
    self:SetCursorPosInternal(
        self:ApplyMovement(self.cur_line, self.cur_col, dir))
    self:RefreshView()
end

-- Adjust the mark (region endpoint) in the specified manner.  |dir| is a
-- directional key name with optional Emacs-style modifier prefix.
function Buffer:MoveMark(dir)
    local line, col
    if self.mark_line then
        line, col = self.mark_line, self.mark_col
    else
        line, col = self.cur_line, self.cur_col
    end
    self:SetMarkPosInternal(self:ApplyMovement(line, col, dir))
    self:RefreshView()
end


-------- Buffer text manipulation methods

-- Return the character at the current cursor position, or the empty
-- string if the cursor is at the end of a line.
function Buffer:GetCharAtCursor()
    local s, c = self:GetStringPos()
    return strsub(self.strings[s], c+1, c+1)
end

-- Insert character |ch| at the current cursor position and advance the
-- cursor by one character.  If this moves the cursor outside the current
-- view range (because it wrapped past the end of the last displayed
-- string), recenter the cursor in the view.
function Buffer:InsertChar(ch)
    assert(type(ch) == "string" and #ch == 1,
           "ch must be a one-character string")
    assert(ch ~= "\n", "ch must not be a newline")
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
        str = self.strings[last]
        str = strsub(str, 1, c) .. ch .. strsub(str, c+1)
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
    self:SetCursorPosInternal(self.cur_line, self.cur_col + 1)
    self:SetDirty()
    self:RefreshView()
end

function Buffer:InsertNewline()
    local s, c, first, last = self:GetStringPos()
    local cur_line = self.cur_line
    local str = self.strings[s]
    local added_string = false

    -- The logical cursor position will always advance to the beginning of
    -- the next line, so update it now.
    self:SetCursorPosInternal(cur_line + 1, 0)

    -- Special case: breaking a line right after a wrap point doesn't
    -- move the physical cursor position.
    if s > first and c == 0 then
        self.line_map:insert(cur_line+1, s)
        self:SetDirty()
        self:RefreshView()
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

    self:SetDirty()
    self:RefreshView()
end

-- Insert text |text| at the current cursor position and advance the cursor
-- to the end of the inserted text.  Equivalent to (but more efficient than)
-- calling InsertChar() or InsertNewline() as appropriate for each character
-- of |text|.
function Buffer:InsertText(text)
    assert(type(text) == "string", "text must be a string")
    local lines = list()
    local i, j = 1, strstr(text, "\n")
    while j do
        lines:append(strsub(text, i, j-1))
        i = j+1
        j = strstr(text, "\n", i)
    end
    lines:append(strsub(text, i))

    local line = self.cur_line
    local s, c, _, line_end = self:LineToStringPos(self.cur_line, self.cur_col)
    local before_text = strsub(self.strings[s], 1, c)
    local after_text = strsub(self.strings[s], c+1)
    for i = s+1, line_end do
        after_text = after_text .. self.strings[i]
    end
    local str_limit = self.view_columns - 1
    for i, str in ipairs(lines) do
        if i > 1 then
            line = line+1
            self.line_map:insert(line, s)
        end
        if i == 1 then
            str = before_text .. str
        end
        if i == #lines then
            self.cur_col = #str
            str = str .. after_text
        end
        while true do  -- do...while
            if s > line_end then
                self.strings:insert(s, strsub(str, 1, str_limit))
            else
                self.strings[s] = strsub(str, 1, str_limit)
            end
            str = strsub(str, str_limit+1)
            s = s+1
            if #str == 0 then break end
        end
    end
    local delta = (s-1) - line_end
    assert(delta >= 0)
    if delta > 0 then
        for i = line+1, #self.line_map do
            self.line_map[i] = self.line_map[i] + delta
        end
    end
    self.cur_line = line
    self:SetMarkPosInternal(nil, nil)
    self:ValidateStrings()

    self:SetDirty()
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

    self:SetMarkPosInternal(nil, nil)
    self:SetDirty()
    self:RefreshView()
end

-- Delete the current region, and return the deleted text.  Returns nil
-- if there was no region or the region was empty (zero length).
function Buffer:DeleteRegion()
    local s1, c1, s2, c2 = self:GetRegion()
    if not s1 then
        return nil
    end
    local l1 = self:StringToLinePos(s1, c1)
    local l2 = self:StringToLinePos(s2, c2)

    local text
    if s1 == s2 then
        text = strsub(self.strings[s1], c1+1, c2)
    else
        local line = l1
        text = strsub(self.strings[s1], c1+1)
        for i = s1+1, s2 do
            if line < #self.line_map and i == self.line_map[line+1] then
                text = text .. "\n"
                line = line+1
            end
            if i < s2 then
                text = text .. self.strings[i]
            else
                text = text .. strsub(self.strings[s2], 1, c2)
            end
        end
    end

    -- Line map updates are simple: we merge [l1,l2] into a single line l1.
    for i = l1+1, l2 do
        self.line_map:pop(l1+1)
    end

    -- String updates are more complex, because we have to re-wrap the
    -- merged first and last strings.
    local str =
        strsub(self.strings[s1], 1, c1) .. strsub(self.strings[s2], c2+1)
    local old_end = self:LastStringForLine(l1)
    for i = s2+1, old_end do
        str = str .. self.strings[i]
    end
    local new_end = s1
    local str_limit = self.view_columns - 1
    self.strings[new_end] = strsub(str, 1, str_limit)
    local ofs = str_limit + 1
    while ofs <= #str do
        new_end = new_end + 1
        self.strings[new_end] = strsub(str, ofs, ofs + str_limit - 1)
        ofs = ofs + str_limit
    end
    assert(new_end <= old_end)
    local s_delta = old_end - new_end
    for i = 1, s_delta do
        self.strings:pop(new_end + 1)
    end
    for i = l1+1, #self.line_map do
        self.line_map[i] = self.line_map[i] - s_delta
    end
    self:ValidateStrings()

    self:SetMarkPosInternal(nil, nil)
    self:SetDirty()
    self:RefreshView()
    return text
end


-------- Buffer search/replace methods

-- Search for text |str| in the buffer, starting from the current cursor
-- position and searching forward (|forward| true) or backward (|forward|
-- false).  If |as_pattern| is true, |str| is treated as a Lua pattern
-- rather than a literal string.  If |match_case| is false, case is folded
-- when matching.
--
-- If a match is found:
--    - Set the cursor position to the end (|forward| true) or beginning
--      (|forward| false) of the match.
--    - If |highlight| is true, set the mark to the other side of the match
--      and activate it, so the match will be displayed highlighted.
--    - Return true.
-- Otherwise, return false.
function Buffer:Search(str, as_pattern, match_case, forward, highlight)
    -- FIXME: This method makes a strong argument for storing the buffer
    -- as a single string instead of as numerous view-sized fragments.
    -- Maybe we'll get to that someday.
    local text = self:GetText()
    -- Lua doesn't seem to have any explicit case-insensitive-compare
    -- functions, so we handle case folding by pre-converting to lowercase.
    -- We assume that patterns don't contain any inverted class tokens
    -- (which is currently always the case, see frame.lua:RegexToPattern()).
    if not match_case then
        text = text:lower()
        str = str:lower()
    end
    local index = self:LinePosToIndex(self.cur_line, self.cur_col)
    local found, found_end
    if forward then
        found, found_end = strfind(text, str, index, not as_pattern)
    else
        local i, i_end = strfind(text, str, 1, not as_pattern)
        while i and i < index do
            found, found_end = i, i_end
            i, i_end = strfind(text, str, i_end+1, not as_pattern)
        end
    end
    if found then
        local match_start, match_end = found, found_end+1
        local cursor_index = forward and match_end or match_start
        local mark_index = forward and match_start or match_end
        self:SetCursorPosInternal(self:IndexToLinePos(cursor_index))
        if highlight then
            local line, col = self:IndexToLinePos(mark_index)
            self:SetMarkPosInternal(line, col)
            self.mark_active = true
        end
        self:RefreshView()
        return true
    else
        if highlight then
            self.mark_active = false
            self:RefreshView()
        end
        return false
    end
end

-- Replace all occurrences of text |from| in the buffer with text |to|
-- from the current cursor position to the end of the buffer, and return
-- the number of replacements done (which may be zero).  If |as_pattern|
-- is true, |from| and |to| are treated as Lua pattern strings; otherwise,
-- both are treated as literal strings.  Case folding is never performed.
function Buffer:Replace(from, to, as_pattern)
    if not as_pattern then
        from = strgsub(from, "%W", "%%%0")  -- %W: all nonalphanumerics
        to = strgsub(to, "%%", "%%%%")
    end
    local text = self:GetText()
    local index = self:LinePosToIndex(self.cur_line, self.cur_col)
    -- For simplicity, we simply perform replacement on the linear text
    -- and reformat it afterward.
    local before_cursor = strsub(text, 1, index-1)
    local after_cursor = strsub(text, index)
    local new_after, n_repl = strgsub(after_cursor, from, to)
    if n_repl > 0 then
        self:SetDirty()
        self:LayoutText(before_cursor .. new_after)
        self:RefreshView()
    end
    return n_repl
end


-------- The remaining methods are private.

-- Mark the buffer dirty, and call the on-dirty callback if the dirty
-- flag was not previously set.
function Buffer:SetDirty()
    if not self.dirty then
        self.dirty = true
        if self.on_dirty then
            self.on_dirty()
        end
    end
end

-- Set the cursor position to the given (logical) line and column.
-- Also deactivates the mark if it was active.
function Buffer:SetCursorPosInternal(line, col)
    self.cur_line, self.cur_col = line, col
    self.mark_active = false
end

-- Set the mark position to the given (logical) line and column.
-- Pass nil to clear the mark.
function Buffer:SetMarkPosInternal(line, col)
    self.mark_line, self.mark_col = line, col
end

-- Apply movement action |action| to position |line|,|col| and return the
-- resulting line and column.
function Buffer:ApplyMovement(line, col, action)
    if action == "UP" then
        if line > 1 then
            line = line-1
        else
            line, col = 1, 0
        end

    elseif action == "C-UP" then
        -- The end result of this will be that either the cursor is on an
        -- empty line (at column 0) or a non-blank line 1 (and thus set to
        -- column 0 for trying to move past the beginning of the file), so
        -- we can unconditionally set column 0 here.
        while line > 1 and self:IsEmptyLine(line) do
            line = line-1
        end
        while line > 1 and not self:IsEmptyLine(line) do
            line = line-1
        end

    elseif action == "DOWN" then
        if line < #self.line_map then
            line = line+1
        else
            col = self:LineLength(line)
        end

    elseif action == "C-DOWN" then
        while line < #self.line_map and self:IsEmptyLine(line) do
            line = line+1
        end
        while line < #self.line_map and not self:IsEmptyLine(line) do
            line = line+1
        end
        col = self:LineLength(line)

    elseif action == "LEFT" then
        -- col might be past the end of the line (after up/down movement
        -- from a longer line), so first force it to the actual end of
        -- the line.
        col = min(col, self:LineLength(line))
        if col > 0 then
            col = col-1
        elseif line > 1 then
            line = line-1
            col = self:LineLength(line)
        end

    elseif action == "C-LEFT" then
        line, col = self:MoveToWord(line, col, false)

    elseif action == "RIGHT" then
        local line_len = self:LineLength(line)
        if line == #self.line_map and col == line_len then
            -- Already at the end of the last line, nothing to do.
        elseif col < line_len then
            col = col + 1
        else
            line, col = line + 1, 0
        end

    elseif action == "C-RIGHT" then
        line, col = self:MoveToWord(line, col, true)

    elseif action == "HOME" then
        col = 0

    elseif action == "C-HOME" then
        line, col = 1, 0

    elseif action == "END" then
        col = self:LineLength(line)

    elseif action == "C-END" then
        line = #self.line_map
        col = self:LineLength(line)

    elseif action == "PAGEUP" or action == "PAGEDOWN" then
        local s, c = self:LineToStringPos(line, col)
        local page_size = self.view_lines - 2
        local target
        if action == "PAGEUP" then
            -- Avoid scrolling back past the first line if the cursor isn't
            -- at the top of the viewport.
            local top_offset = s - self.top_string
            target = max(s - page_size, 1 + top_offset)
        else
            -- We're fine with scrolling the bottom of the viewport past
            -- the last line.
            target = min(s + page_size, #self.strings)
        end
        if target ~= s then
            local delta = target - s
            self.top_string = self.top_string + delta
            line, col = self:StringToLinePos(target, c)
        end

    else
        error("Invalid movement action: "..tostring(action))
    end

    return line, col
end

-- Set of characters in a "word" for MoveToWord().
local WORD_CHARS = set()
for i = 0, 9 do
    WORD_CHARS:add(48+i)  -- "0".."9"
end
for i = 0, 25 do
    WORD_CHARS:add(65+i)  -- "A".."Z"
    WORD_CHARS:add(97+i)  -- "a".."z"
end

-- Adjust the given position backward to the next beginning-of-word
-- (|forward| false) or forward to the next end-of-word (|forward| true),
-- where "word" is defined as any sequence of alphanumeric characters.
function Buffer:MoveToWord(line, col, forward)
    local s, c, line_start, line_end = self:LineToStringPos(line, col)
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
        line_end = self:LastStringForLine(line)
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
    return line, c
end

-- Return the length of the given (logical) line.
function Buffer:LineLength(line)
    local line_start = self.line_map[line]
    local line_end = self:LastStringForLine(line)
    local len = 0
    for i = line_start, line_end do
        len = len + #self.strings[i]
    end
    return len
end

-- Return whether the given (logical) line is empty.
function Buffer:IsEmptyLine(line)
    return #self.strings[self.line_map[line]] == 0
end

-- Return the index of the last (physical) string for the given (logical) line.
function Buffer:LastStringForLine(line)
    if line < #self.line_map then
        return self.line_map[line+1] - 1
    else
        return #self.strings
    end
end

-- Return the current cursor position as a string index and offset into
-- that string, along with the indexes of the first and last strings for
-- the current logical line.
function Buffer:GetStringPos()
    return self:LineToStringPos(self.cur_line, self.cur_col)
end

-- Convert the given logical (line-based) position to a physical
-- (string-based) position.  Returns the string index, column, and
-- (for convenience) the indexes of the first and last strings
-- corresponding to the selected line.
function Buffer:LineToStringPos(line, col)
    local line_start = self.line_map[line]
    local line_end = self:LastStringForLine(line)
    local c = col
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

-- Convert the given physical (string-based) position to a logical
-- (line-based) position.  The given position is assumed to be "near"
-- the current position, and thus we do a simple linear search from the
-- current position rather than a binary search over the entire buffer.
function Buffer:StringToLinePos(s, c)
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
    return line, c
end

-- Convert a line/column position to a 1-based string index into the
-- composite buffer string (as would be returned by GetText()).
function Buffer:LinePosToIndex(line, col)
    local index = 1 + col
    for i = 1, line-1 do
        for s = self.line_map[i], self.line_map[i+1] - 1 do
            index = index + #self.strings[s]
        end
        index = index+1  -- newline
    end
    return index
end

-- Convert a 1-based string index into the composite buffer string to a
-- line/column position.
function Buffer:IndexToLinePos(index)
    index = index - 1
    local line, s, c = 1, 1, 0
    local line_end = self:LastStringForLine(line)
    while s < #self.strings do
        local len = #self.strings[s]
        if index < len then
            return line, c + index
        end
        index = index - len
        if s < line_end then
            c = c + len
        elseif index == 0 then  -- Cursor is at the line break.
            return line, c + len
        else
            index = index-1  -- newline
            line = line+1
            line_end = self:LastStringForLine(line)
            c = 0
        end
        s = s+1
    end
    return line, c + index
end

-- Return the endpoints of the current region as a 4-tuple:
--     start_string, start_col, end_string, end_col
-- or no values if there is currently no region or the region has zero
-- length.  The region starts at the earlier of the cursor position and
-- mark position (inclusive) and extends up to the later of the two
-- positions (exclusive).
function Buffer:GetRegion()
    local cl, cc = self.cur_line, self.cur_col
    local ml, mc = self.mark_line, self.mark_col
    if ml and not (ml == cl and mc == cc) then
        local cs, ms
        cs, cc = self:LineToStringPos(cl, cc)
        ms, mc = self:LineToStringPos(ml, mc)
        if ms < cs or (ms == cs and mc < cc) then
            return ms, mc, cs, cc
        else
            return cs, cc, ms, mc
        end
    else
        return  -- no values
    end
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
    self.cursor:SetSize(1, self.cell_h)
end

-- Rebuild the string list from the given linear buffer text.
function Buffer:LayoutText(text)
    local wrap = self.view_columns - 1
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

    self:ValidateStrings()
end

-- Verify that the line map and string list are consistent.
function Buffer:ValidateStrings()
    assert(#self.line_map > 0)
    assert(#self.strings > 0)
    assert(self.line_map[1] == 1)
    local line = 1
    local line_end = self:LastStringForLine(line)
    local str_limit = self.view_columns - 1
    for i = 1, #self.strings do
        if i < line_end then
            assert(#self.strings[i] == str_limit)
        else
            assert(#self.strings[i] <= str_limit)
            if i == #self.strings then
                assert(line == #self.line_map)
            else
                assert(line < #self.line_map)
                line = line+1
                local new_end = self:LastStringForLine(line)
                assert(new_end > i)
                line_end = new_end
            end
        end
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
    local region_s1, region_c1, region_s2, region_c2
    if self.mark_active then
        region_s1, region_c1, region_s2, region_c2 = self:GetRegion()
    end

    self:ReleaseAllLines()
    local prev
    local line = top_line
    for i = top_string, min(top_string + bottom_ofs, #self.strings) do
        local str = self.strings[i]
        local is_final = (i == self:LastStringForLine(line))
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
        if region_s1 and i >= region_s1 and i <= region_s2 then
            local c1 = (i == region_s1) and region_c1 or 0
            local c2 = (i == region_s2) and region_c2 or #str
            if c2 > c1 then
                local region_text = strgsub(strsub(str, c1+1, c2), "|", "||")
                str = (strgsub(strsub(str, 1, c1), "|", "||")
                       .. WoWXIV.FormatColoredText(region_text, REGION_COLOR)
                       .. strgsub(strsub(str, c2+1), "|", "||"))
            end
        else
            str = strgsub(str, "|", "||")
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
            self:SetCursorPosInternal(self:StringToLinePos(new_s, 0))
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
        line = self.view:CreateFontString(nil, "ARTWORK")
        WoWXIV.SetFont(line, "EDITOR")
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
