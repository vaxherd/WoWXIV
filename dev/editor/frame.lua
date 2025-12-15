local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor

local class = WoWXIV.class
local Frame = WoWXIV.Frame
local list = WoWXIV.list

local strformat = string.format


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
SLASH_XIVEDITOR1="/xe" SlashCmdList.XIVEDITOR=function() ZZe=EditorFrame("Test", "Text 56789 123456789 123456789 123456789 123456789 123456789 123456789 123456789") end --FIXME temp

function EditorFrame:__allocator(filename, text)
    return __super("Frame", nil, UIParent, "WoWXIV_EditorFrameTemplate")
end

function EditorFrame:__constructor(filename, text)
    self.filename = filename
    self.buffer = Editor.Buffer(text or "", self.TextView)
    self.buffer:SetScrollCallback(function() self:UpdateTitle() end)

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

    -- Keymap for this frame.  Key names follow OnKeyDown argument values;
    -- modifiers follow Emacs style, and must be given in the order
    -- "S-C-M-key".  Handler functions receive the EditorFrame instance,
    -- pressed key (with modifiers), and translated character (nil if none)
    -- as arguments.  Keys with no bound handler but a translated character
    -- are inserted directly into the buffer.
    self.keymap = self:GetDefaultKeymap()

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
    self:SetFocused(false)
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
            self:UpdateTitle()
            self.cursor_timer = 0
        end
    end

    local cursor_timer = self.cursor_timer
    self.buffer:SetShowCursor(cursor_timer < CURSOR_BLINK_PERIOD/2)
    self.cursor_timer = (cursor_timer + dt) % CURSOR_BLINK_PERIOD
end

function EditorFrame:HandleKey(key, ch)
    local shift = IsShiftKeyDown()
    local ctrl = IsControlKeyDown()
    local alt = IsAltKeyDown()

    local keyname = strformat("%s%s%s%s", shift and "S-" or "",
                              ctrl and "C-" or "", alt and "A-" or "", key)
    local handler = self.keymap[keyname]
    if handler then
        handler(self, keyname, ch)
    elseif ch then
        self.buffer:InsertChar(ch)
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

function EditorFrame:UpdateTitle()
    local line, col = self.buffer:GetCursorPos()
    local title =
        strformat("%s - L%d C%d", self.filename or "(Untitled)", line, col)
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


-------- Default keymap and handler functions

function EditorFrame:GetDefaultKeymap()
    if not EditorFrame.DEFAULT_KEYMAP then
        EditorFrame.DEFAULT_KEYMAP = {
            ["UP"] = EditorFrame.HandleMovementKey,
            ["C-UP"] = EditorFrame.HandleMovementKey,
            ["DOWN"] = EditorFrame.HandleMovementKey,
            ["C-DOWN"] = EditorFrame.HandleMovementKey,
            ["LEFT"] = EditorFrame.HandleMovementKey,
            ["C-LEFT"] = EditorFrame.HandleMovementKey,
            ["RIGHT"] = EditorFrame.HandleMovementKey,
            ["C-RIGHT"] = EditorFrame.HandleMovementKey,
            ["HOME"] = EditorFrame.HandleMovementKey,
            ["C-HOME"] = EditorFrame.HandleMovementKey,
            ["END"] = EditorFrame.HandleMovementKey,
            ["C-END"] = EditorFrame.HandleMovementKey,
            ["ENTER"] = function(self) self.buffer:InsertNewline() end,
            ["BACKSPACE"] = function(self) self.buffer:DeleteChar(false) end,
            ["DELETE"] = function(self) self.buffer:DeleteChar(true) end,
        }
    end
    return EditorFrame.DEFAULT_KEYMAP
end

function EditorFrame:HandleMovementKey(key)
    self.buffer:MoveCursor(key)
end
