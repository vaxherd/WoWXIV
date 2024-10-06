local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
WoWXIV.Gamepad.MenuCursor = WoWXIV.Gamepad.MenuCursor or {}
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local GameTooltip = GameTooltip
local abs = math.abs
local floor = math.floor
local tinsert = tinsert
local tremove = tremove


-- Static reference to the singleton MenuCursor instance.
local global_cursor = nil


------------------------------------------------------------------------
-- Core implementation
------------------------------------------------------------------------

MenuCursor.Cursor = class()
local Cursor = MenuCursor.Cursor

function Cursor:__constructor()
    assert(not global_cursor)
    global_cursor = self

    -- Is the player currently using gamepad input?  (Mirrors the
    -- GAME_PAD_ACTIVE_CHANGED event.)
    self.gamepad_active = false
    -- Map of open frames which have menu cursor support.  Each key is a
    -- frame (table ref), and the value is a MenuFrame instance (see below).
    self.frames = {}
    -- Stack of active MenuFrames and their current targets (each element
    -- is a {frame,target} pair).  The current focus is on top of the
    -- stack (focus_stack[#focus_stack]).
    self.focus_stack = {}
    -- Stack of active modal MenuFrames and their current targets.  If a
    -- modal frame is active, the top frame on this stack is the current
    -- focus and input frame cycling is disabled.
    self.modal_stack = {}

    -- This is a SecureActionButtonTemplate only so that we can
    -- indirectly click the button pointed to by the cursor.
    local f = CreateFrame("Button", "WoWXIV_MenuCursor", UIParent,
                          "SecureActionButtonTemplate")
    self.cursor = f
    f:Hide()
    f:SetFrameStrata("TOOLTIP")  -- Make sure it stays on top.
    f:SetSize(32, 32)
    f:SetScript("OnShow", function() self:OnShow() end)
    f:SetScript("OnHide", function() self:OnHide() end)
    f:SetScript("OnEvent", function(_,...) self:OnEvent(...) end)
    f:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetAttribute("type1", "click")
    f:SetAttribute("type2", "click")
    f:SetAttribute("clickbutton1", nil)
    f:SetAttribute("clickbutton2", nil)
    f:HookScript("OnClick", function(_,...) self:OnClick(...) end)
    f:RegisterForClicks("AnyDown")

    for _, handler_class in pairs(Cursor.handlers) do
        handler_class:Initialize(self)
    end

    local texture = f:CreateTexture(nil, "ARTWORK")
    self.texture = texture
    texture:SetAllPoints()
    texture:SetTexture("Interface/CURSOR/Point")  -- Default mouse cursor image
    -- Flip it horizontally to distinguish it from the mouse cursor.
    texture:SetTexCoord(1, 0, 0, 1)
end

-- Register a frame handler class.  The handler's Initialize() class method
-- will be called when the global cursor instance is created, with the
-- signature:
--     handler_class:Initialize(global_cursor)
-- This is a static method.
function Cursor.RegisterFrameHandler(handler_class)
    Cursor.handlers = Cursor.handlers or {}
    tinsert(Cursor.handlers, handler_class)
end

-- Register an event handler.  If an optional event argument is provided,
-- the function will only be called when the event's first argument is
-- equal to that value.  The event (and event argument, if given) will be
-- omitted from the arguments passed to the handler.  The {event, event_arg}
-- pair must be unique among all registered events.
function Cursor:RegisterEvent(handler, event, event_arg)
    local handler_name, wrapper
    if event_arg then
        handler_name = event.."__"..tostring(event_arg)
        wrapper = function(cursor, event, arg1, ...) handler(...) end
    else
        handler_name = event
        wrapper = function(cursor, event, ...) handler(...) end
    end
    assert(not self[handler_name], "Duplicate event handler: "..handler_name)
    self[handler_name] = wrapper
    self.cursor:RegisterEvent(event)
end

-- Generic event handler.  Forwards events to same-named methods, optionally
-- with the first argument appended to the method name.
function Cursor:OnEvent(event, arg1, ...)
    -- Use a double underscore to ensure no collisions with event names
    -- (mostly on principle, since it probably wouldn't be a problem in
    -- actual usage).
    local event__arg1 = event .. "__" .. tostring(arg1)
    if self[event__arg1] then
        self[event__arg1](self, ...)
    elseif self[event] then
        self[event](self, arg1, ...)
    end
end

-- Handler for input type changes.
function Cursor:GAME_PAD_ACTIVE_CHANGED(active)
    self.gamepad_active = active
    self:UpdateCursor()
end

-- Handlers for entering and leaving combat, to hide or show the cursor
-- respectively.
function Cursor:PLAYER_REGEN_DISABLED()
    self:UpdateCursor(true)
end
function Cursor:PLAYER_REGEN_ENABLED()
    self:UpdateCursor(false)
end

-- Add the given frame (a MenuFrame instance) to the focus stack, make it
-- the current focus, and point the cursor at the given input element.
-- If |target| is nil, the initial input element is taken by calling the
-- frame's GetDefaultTarget() method.  If the frame is already in the focus
-- stack, it is moved to the top, and if |target| is nil, the frame's
-- current target is left unchanged.  If |modal| is true, the frame becomes
-- a modal frame, blocking menu cursor input to any other frame until it is
-- removed.
function Cursor:AddFrame(frame, target, modal)
    local other_stack = modal and self.focus_stack or self.modal_stack
    for _, v in ipairs(other_stack) do
        if v == frame then
            error("Invalid attempt to change modal state of frame "..tostring(frame))
            modal = not modal  -- In case we decide to make this non-fatal.
            break
        end
    end
    local found = false
    local stack = modal and self.modal_stack or self.focus_stack
    for i, v in ipairs(stack) do
        if v[1] == frame then
            if i == #stack then
                -- Frame was already on top, so just change the target.
                if target then 
                    self:SetTarget(target)
                end
                return
            end
            target = target or v[2]
            tremove(stack, i)
            found = true
            break
        end
    end
    local cursor_active = self.cursor:IsShown()
    if cursor_active and #stack > 0 then
        local last_focus, last_target = unpack(stack[#stack])
        if last_target then
            last_focus:LeaveTarget(last_target)
        end
    end
    target = target or frame:GetDefaultTarget()
    tinsert(stack, {frame, target})
    if cursor_active and target then
        frame:EnterTarget(target)
    end
    self:UpdateCursor()
end

-- Remove the given frame (a MenuFrame instance) from the focus stack.
-- If the frame is the current focus, the focus is changed to the next
-- frame on the stack.  Does nothing if the given frame is not in the
-- focus stack.
function Cursor:RemoveFrame(frame)
    if #self.modal_stack > 0 then
        self:InternalRemoveFrameFromStack(frame, self.modal_stack, true)
        self:InternalRemoveFrameFromStack(frame, self.focus_stack, false)
    else
        self:InternalRemoveFrameFromStack(frame, self.focus_stack, true)
    end
end

-- Internal helper for RemoveFrame().
function Cursor:InternalRemoveFrameFromStack(frame, stack, is_top_stack)
    for i, v in ipairs(stack) do
        if v[1] == frame then
            local is_top = is_top_stack and i == #stack
            if is_top then
                self:SetTarget(nil)
            end
            tremove(stack, i)
            local cursor_active = self.cursor:IsShown()
            if cursor_active and is_top and #stack > 0 then
                local new_focus, new_target = unpack(stack[#stack])
                new_focus:EnterTarget(new_target)
            end
            self:UpdateCursor()
            return
        end
    end
end

-- Internal helper to get the topmost stack (modal or normal).
function Cursor:InternalGetFocusStack()
    local modal_stack = self.modal_stack
    return #modal_stack > 0 and modal_stack or self.focus_stack
end

-- Return the MenuFrame which currently has focus, or nil if none.
function Cursor:GetFocus()
    local stack = self:InternalGetFocusStack()
    local top = #stack
    return top > 0 and stack[top][1] or nil
end

-- Return the input element in the current focus which is currently
-- pointed to by the cursor, or nil if none (or if there is no focus).
function Cursor:GetTarget()
    local stack = self:InternalGetFocusStack()
    local top = #stack
    return top > 0 and stack[top][2] or nil
end

-- Return the current focus and target in a single function call.
function Cursor:GetFocusAndTarget()
    local stack = self:InternalGetFocusStack()
    local top = #stack
    if top > 0 then
        return unpack(stack[top])
    else
        return nil, nil
    end
end

-- Set the menu cursor target.  If nil, clears the current target.
-- Handles all enter/leave interactions with the new and previous targets.
function Cursor:SetTarget(target)
    local stack = self:InternalGetFocusStack()
    local top = #stack
    assert(not target or top > 0)
    if top == 0 or target == stack[top][2] then return end

    local cursor_active = self.cursor:IsShown()
    local focus, old_target = unpack(stack[top])
    if cursor_active and old_target then
        focus:LeaveTarget(old_target)
    end
    stack[top][2] = target
    if cursor_active and target then
        focus:EnterTarget(target)
    end
    self:UpdateCursor()
end

-- Internal helper to clear the menu cursor target without calling the
-- leave callback.  For use when the current target is invalid (and thus
-- attempting to call the leave callback may trigger an error).
function Cursor:InternalForceClearTarget()
    local stack = self:InternalGetFocusStack()
    local top = #stack
    if top > 0 then
        stack[top][2] = nil
    end
end

-- Internal helper to find a frame in the regular or modal frame stack.
-- Returns the stack and index, or (nil,nil) if not found.
function Cursor:InternalFindFrame(frame)
    local focus_stack = self.focus_stack
    for i, v in ipairs(focus_stack) do
        if v[1] == frame then
            return focus_stack, i
        end
    end
    local modal_stack = self.modal_stack
    for i, v in ipairs(modal_stack) do
        if v[1] == frame then
            return modal_stack, i
        end
    end
    return nil, nil
end

-- Return the input element most recently selected in the given frame.
-- Returns nil if the given frame is not in the focus stack.
function Cursor:GetTargetForFrame(frame)
    local stack, index = self:InternalFindFrame(frame)
    return stack and stack[index][2] or nil
end

-- Set the menu cursor target for a specific frame.  Equivalent to
-- SetTarget() if the frame is topmost on the focus stack; otherwise, sets
-- the input element to be activated next time that frame becomes topmost
-- on the stack.  Does nothing if the given frame is not on the focus stack.
function Cursor:SetTargetForFrame(frame, target)
    local stack, index = self:InternalFindFrame(frame)
    if stack then
        if stack == self:InternalGetFocusStack() and index == #stack then
            self:SetTarget(target)
        else
            stack[index][2] = target
        end
    end
end

-- Update the display state of the cursor.
function Cursor:UpdateCursor(in_combat)
    if in_combat == nil then
        in_combat = InCombatLockdown()
    end
    local f = self.cursor

    local focus, target = self:GetFocusAndTarget()
    while focus and not focus:GetFrame():IsVisible() do
        self:RemoveFrame(focus)
        focus, target = self:GetFocusAndTarget()
    end

    if target and self.gamepad_active and not in_combat then
        local target_frame = focus:GetTargetFrame(target)
        self:SetCursorPoint(target_frame)
        if focus:GetTargetClickable(target) then
            f:SetAttribute("clickbutton1", target_frame)
        else
            f:SetAttribute("clickbutton1", nil)
        end
        f:SetAttribute("clickbutton2", focus:GetCancelButton())
        if not f:IsShown() then
            f:Show()
            focus:EnterTarget(target)
        else
            self:SetCancelBinding(focus)
        end
    else
        if f:IsShown() then
            if target then
                focus:LeaveTarget(target)
            end
            f:Hide()
        end
    end
end

-- Show() handler; activates menu cursor input bindings and periodic update.
function Cursor:OnShow()
    local focus = self:GetFocus()
    assert(focus)  -- Cursor should never be shown without an active focus.

    local f = self.cursor
    SetOverrideBinding(f, true, "PADDUP",
                       "CLICK WoWXIV_MenuCursor:DPadUp")
    SetOverrideBinding(f, true, "PADDDOWN",
                       "CLICK WoWXIV_MenuCursor:DPadDown")
    SetOverrideBinding(f, true, "PADDLEFT",
                       "CLICK WoWXIV_MenuCursor:DPadLeft")
    SetOverrideBinding(f, true, "PADDRIGHT",
                       "CLICK WoWXIV_MenuCursor:DPadRight")
    SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_confirm"],
                       "CLICK WoWXIV_MenuCursor:LeftButton")
    self:SetCancelBinding(focus)
    local prev, next = focus:GetPageHandlers()
    if prev and next then
        local prev_button, next_button
        if type(prev) == "string" then
            prev_button = "CLICK "..prev..":LeftButton"
        else
            prev_button = "CLICK WoWXIV_MenuCursor:PrevPage"
        end
        if type(next) == "string" then
            next_button = "CLICK "..next..":LeftButton"
        else
            next_button = "CLICK WoWXIV_MenuCursor:NextPage"
        end
        SetOverrideBinding(f, true,
                           WoWXIV_config["gamepad_menu_prev_page"],
                           prev_button)
        SetOverrideBinding(f, true,
                           WoWXIV_config["gamepad_menu_next_page"],
                           next_button)
    end
    if focus:GetTabSystem() then
        SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_prev_tab"],
                           "CLICK WoWXIV_MenuCursor:PrevTab")
        SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_next_tab"],
                           "CLICK WoWXIV_MenuCursor:NextTab")
    end
    SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_next_window"],
                       "CLICK WoWXIV_MenuCursor:CycleFrame")
    f:SetScript("OnUpdate", function() self:OnUpdate() end)
    self:OnUpdate()
end

-- Hide() handler; clears menu cursor input bindings and periodic updated.
function Cursor:OnHide()
    local f = self.cursor
    ClearOverrideBindings(f)
    f:SetScript("OnUpdate", nil)
end

-- Per-frame update routine.  This serves two purposes: to implement
-- cursor bouncing, and to record the current focus frame and target
-- element to avoid a single click activating multiple elements (see
-- notes in OnClick()).
function Cursor:OnUpdate()
    local focus, target = self:GetFocusAndTarget()
    self.last_focus, self.last_target = focus, target
    local target_frame = target and focus:GetTargetFrame(target)
    if not target_frame then return end
    if not target_frame.GetLeft then
        self:InternalForceClearTarget()
        error("Invalid target frame ("..tostring(target_frame)..") for target "..tostring(target))
    end

    --[[
         Calling out to fetch the target's position and resetting the
         cursor anchor points every frame is not ideal, but we need to
         keep the cursor position updated when buttons change positions,
         such as:
            - Scrolling of gossip/quest text
            - BfA troop recruit frame on first open after /reload
            - Upgrade confirmation dialog for Shadowlands covenant sanctum
    ]]--
    self:SetCursorPoint(target_frame)

    local t = GetTime()
    t = t - floor(t)
    local xofs = -4 * math.sin(t * math.pi)
    self.texture:ClearPointsOffset()
    self.texture:AdjustPointsOffset(xofs, 0)

    focus:OnUpdate(target_frame)
end

-- Helper for UpdateCursor() and OnUpdate() to set the cursor frame anchor.
function Cursor:SetCursorPoint(target)
    local f = self.cursor
    f:ClearAllPoints()
    -- Work around frame reference limitations on secure buttons
    --f:SetPoint("TOPRIGHT", target, "LEFT")
    local x = target:GetLeft()
    local _, y = target:GetCenter()
    if not x or not y then return end
    local scale = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x = x * scale
    y = y * scale
    f:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", x, y-UIParent:GetHeight())
end

-- Helper for UpdateCursor() and OnShow() to set the cancel button binding
-- for the current cursor target depending on whether it needs to be
-- securely passed through to the target.  The current focus is passed
-- down for convenience.
function Cursor:SetCancelBinding(focus)
    local f = self.cursor
    if focus:GetCancelButton() then
        SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_cancel"],
                           "CLICK WoWXIV_MenuCursor:RightButton")
    else
        SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_cancel"],
                           "CLICK WoWXIV_MenuCursor:Cancel")
    end
end

-- Click event handler; handles all events other than secure click
-- passthrough.
function Cursor:OnClick(button, down)
    local focus, target = self:GetFocusAndTarget()
    -- Click bindings should be cleared if we have no focus, but we could
    -- still get here right after a secure passthrough click closes the
    -- last frame.
    if not focus then return end
    if button == "DPadUp" then
        self:Move("up")
    elseif button == "DPadDown" then
        self:Move("down")
    elseif button == "DPadLeft" then
        self:Move("left")
    elseif button == "DPadRight" then
        self:Move("right")
    elseif button == "LeftButton" then  -- i.e., confirm
        -- Click event is passed to target by SecureActionButtonTemplate.
        -- This code is called afterward, so it's possible that the click
        -- already closed our (previously) current focus frame or otherwise
        -- changed the cursor state.  If we blindly proceed with calling
        -- the on_click handler here, we could potentially perform a second
        -- click action from a single button press, so ensure that the
        -- focus state has not in fact changed since the last OnUpdate() call.
        if focus == self.last_focus and target == self.last_target then
            if target then
                focus:OnConfirm(target)
            end
        end
    elseif button == "Cancel" then
        -- If the frame declared a cancel button, the click is passed down
        -- as a separate event, so we only get here in the no-passthrough
        -- case.
        focus:OnCancel()
    elseif button == "PrevPage" then
        local prev_button = focus:GetPageHandlers()
        if type(prev_button) == "table" then
            prev_button:GetScript("OnClick")(prev_button, "LeftButton", down)
        elseif type(prev_button) == "function" then
            prev_button(-1)
        else
            error("Invalid type for prev_button")
        end
    elseif button == "NextPage" then
        local _, next_button = focus:GetPageHandlers()
        if type(next_button) == "table" then
            next_button:GetScript("OnClick")(next_button, "LeftButton", down)
        elseif type(next_button) == "function" then
            next_button(1)
        else
            error("Invalid type for next_button")
        end
    elseif button == "PrevTab" or button == "NextTab" then
        local tabs = focus:GetTabSystem()
        local direction = button=="PrevTab" and -1 or 1
        local new_tab, first_tab, stop_next
        local i = 1
        while true do
            local tab = tabs:GetTabButton(i)
            i = i + 1
            if not tab then break end
            -- HACK: breaking encapsulation to access tab selected state
            if tab.isSelected then
                if direction < 0 then
                    -- If we already have a new_tab, it's the previous
                    -- (enabled) tab, so we're done.  Otherwise, let the
                    -- loop finish, so new_tab will point to the last
                    -- (again enabled) tab.
                    if new_tab then break end
                else  -- direction > 0
                    stop_next = true
                end
            end
            if tab:IsEnabled() then
                if stop_next then
                    new_tab = tab
                    break
                end
                if not first_tab then
                    first_tab = tab
                end
                if direction < 0 then
                    new_tab = tab
                end
            end
        end
        if stop_next and not new_tab then
            -- The current tab must be the last enabled one, so cycle back
            -- to the first tab.
            new_tab = first_tab
        end
        if new_tab then
            tabs:SetTab(new_tab:GetTabID())
        end
    elseif button == "CycleFrame" then
        if #self.modal_stack == 0 then
            local stack = self.focus_stack
            local top = #stack
            if top > 1 then
                local cursor_active = self.cursor:IsShown()
                local cur_entry = tremove(stack, top)
                local cur_focus, cur_target = unpack(cur_entry)
                if cursor_active and cur_target then
                    cur_focus:LeaveTarget(cur_target)
                end
                tinsert(stack, 1, cur_entry)
                assert(#stack == top)
                local new_focus, new_target = unpack(stack[top])
                if cursor_active and new_target then
                    new_focus:EnterTarget(new_target)
                end
            end
        end
    end
end

-- OnClick() helper which moves the cursor in the given direction.
-- dir gives the direction, one of the strings "up", "down", "left", or
-- "right".
function Cursor:Move(dir)
    local focus, target = self:GetFocusAndTarget()
    local new_target = focus:NextTarget(target, dir)
    if new_target then
        self:SetTarget(new_target)
        if focus.OnMove then
            focus:OnMove(target, new_target)
        end
    end
end

------------------------------------------------------------------------
-- Frame manager class
------------------------------------------------------------------------

MenuCursor.MenuFrame = class()
local MenuFrame = MenuCursor.MenuFrame

-- Convenience constant for passing true to the modal argument of the
-- MenuFrame constructor in a way that indicates what the argument is.
MenuFrame.MODAL = true


-------- Instance constructor

-- Instance constructor.  Pass the WoW Frame instance to be managed.
-- If modal is true, the frame will be modal (preventing switching
-- input focus to any non-modal frame while active).
function MenuFrame:__constructor(frame, modal)
    self.frame = frame
    self.modal = modal

    -- Table of valid targets for cursor movement.  Each key is a frame
    -- (except as noted for scroll_box below), and each value is a subtable
    -- with the following possible elements:
    --    - can_activate: If true, a confirm input on this frame causes a
    --         left-click action to be sent to the frame.
    --    - is_default: If true, a call to UpdateCursor() when no frame is
    --         targeted will cause this frame to be targeted.
    --    - is_scroll_box: If non-nil, the key is a pseudo-frame for the
    --         corresponding scroll list element returned by
    --         PseudoFrameForScrollElement().
    --    - lock_highlight: If true, the frame's LockHighlight() and
    --         UnlockHighlight() methods will be called when the frame is
    --         targeted and untargeted, respectively.
    --    - on_click: If non-nil, a function to be called when the element
    --         is activated.  The element is passed as an argument.  When
    --         set along with can_activate, this is called after the click
    --         event is passed down to the frame.
    --    - on_enter: If non-nil, a function to be called when the cursor
    --         is moved onto the element.  The frame is passed as an argument.
    --         Ignored if send_enter_leave is set.
    --    - on_leave: If non-nil, a function to be called when the cursor
    --         is moved off the element.  The frame is passed as an argument.
    --         Ignored if send_enter_leave is set.
    --    - scroll_frame: If non-nil, a ScrollFrame which should be scrolled
    --         to make the element visible when targeted.
    --    - send_enter_leave: If true, the frame's OnEnter and OnLeave
    --         scripts (if any) will be called when the frame is targeted
    --         and untargeted, respectively.
    --    - up, down, left, right: If non-nil, specifies the frame to be
    --         targeted on the corresponding movement input from this frame.
    --         A value of false prevents movement in the corresponding
    --         direction.
    self.targets = {}
    -- Function to call when the cancel button is pressed (receives self
    -- as an argument).  If nil, no action is taken.
    self.cancel_func = nil
    -- Subframe (button) to be clicked on a gamepad cancel button press,
    -- or nil for none.  If set, cancel_func is ignored.
    self.cancel_button = nil
    -- Object to handle gamepad previous-page button presses.  May be any of:
    --    - A string, giving the global name of a button to which a click
    --      action will be securely forwarded.
    --    - A Button instance, to which a click action will be (insecurely)
    --      sent.
    --    - A function, which will be called with no arguments.
    --    - nil, indicating that page flipping is not supported by this frame.
    -- Must not be changed while the frame is enabled for input.  (Gamepad
    -- page flipping is only enabled if both this and on_next_page
    -- non-nil.)
    self.on_prev_page = nil
    -- Object to handle gamepad next-page button presses.  See on_prev_page
    -- for details.
    self.on_next_page = nil
    -- TabSystem instance of tab list to be controlled with gamepad
    -- previous-tab and next-tab button presses, or nil if none.
    self.tab_system = nil
    -- Should the current button be highlighted if enabled?
    -- (This is a cache of the current button's lock_highlight parameter.)
    self.want_highlight = true
    -- Is the current button highlighted via lock_highlight?
    -- (This is a cache to avoid unnecessary repeated calls to the
    -- button's LockHighlight() method in OnUpdate().)
    self.highlight_locked = false
end


-------- Cursor interface (methods intended only to be called from Cursor)

-- Return the WoW Frame instance for this frame.
function MenuFrame:GetFrame()
    return self.frame
end

-- Return the handlers for previous-page and next-page actions for this frame,
-- or (nil,nil) if none.
function MenuFrame:GetPageHandlers()
    return self.on_prev_page, self.on_next_page
end

-- Return the TabSystem instance of the tab set for this frame, or nil if none.
function MenuFrame:GetTabSystem()
    return self.tab_system
end

-- Return the frame (WoW Button instance) of the cancel button for this
-- frame, or nil if none.
function MenuFrame:GetCancelButton()
    return self.cancel_button
end

-- Return the frame's default cursor target.
function MenuFrame:GetDefaultTarget()
    for frame, params in pairs(self.targets) do
        if params.is_default then
            return frame
        end
    end
    return nil
end

-- Return the frame associated with the given targets[] key.
function MenuFrame:GetTargetFrame(target)
    local params = self.targets[target]
    if params and params.is_scroll_box then
        local box = target.box
        return box:FindFrame(box:FindElementData(target.index))
    else
        return target
    end
end

-- Return whether click events should be securely passed down to the
-- given target's frame.
function MenuFrame:GetTargetClickable(target)
    local params = self.targets[target]
    return params and params.can_activate
end

-- Return the next target in the given direction from the given target,
-- or nil to indicate no next target.  If target is nil, instead return
-- the target for an initial cursor input of the given direction. dir gives
-- the direction, one of the strings "up", "down", "left", or "right".
function MenuFrame:NextTarget(target, dir)
    if not target then
        return self:GetDefaultTarget()
    end

    local params = self.targets[target]
    local explicit_next = params[dir]
    if explicit_next ~= nil then
        -- A value of false indicates "suppress movement in this
        -- direction".  We have to use false and not nil because
        -- Lua can't distinguish between "key in table with nil value"
        -- and "key not in table".
        return explicit_next or nil
    end

    local global_scale = UIParent:GetEffectiveScale()
    local cur_x0, cur_y0, cur_w, cur_h = target:GetRect()
    local cur_scale = target:GetEffectiveScale() / global_scale
    cur_x0 = cur_x0 * cur_scale
    cur_y0 = cur_y0 * cur_scale
    cur_w = cur_w * cur_scale
    cur_h = cur_h * cur_scale
    local cur_x1 = cur_x0 + cur_w
    local cur_y1 = cur_y0 + cur_h
    local cur_cx = (cur_x0 + cur_x1) / 2
    local cur_cy = (cur_y0 + cur_y1) / 2
    local dx = dir=="left" and -1 or dir=="right" and 1 or 0
    local dy = dir=="down" and -1 or dir=="up" and 1 or 0
    --[[
         We attempt to choose the "best" movement target by selecting the
         target that (1) has the minimum angle from the movement direction
         and (2) within all targets matching (1), has the minimum parallel
         distance from the current cursor position.  Targets not in the
         movement direction (i.e., at least 90 degrees from the movement
         vector) are excluded.

         When calculating the angle and distance, we use the shortest
         distance between line segments through each frame perpendicular
         to the direction of movement: thus, for example, when moving
         vertically, we take the shortest distance between the horizontal
         center line of each frame.  Note that we do not need to consider
         overlap, since cases in which the segments overlap will be
         treated as "not in the direction of movement".
    ]]--
    local best, best_dx, best_dy = nil, nil, nil
    for frame, params in pairs(self.targets) do
        if (frame ~= target
            and frame.GetRect)  -- skip scroll list elements
        then
            local f_x0, f_y0, f_w, f_h = frame:GetRect()
            local scale = frame:GetEffectiveScale() / global_scale
            f_x0 = f_x0 * scale
            f_y0 = f_y0 * scale
            f_0 = f_w * scale
            f_h = f_h * scale
            local f_x1 = f_x0 + f_w
            local f_y1 = f_y0 + f_h
            local f_cx = (f_x0 + f_x1) / 2
            local f_cy = (f_y0 + f_y1) / 2
            local frame_dx, frame_dy
            if dx ~= 0 then
                frame_dx = f_cx - cur_cx
                if f_y1 < cur_y0 then
                    frame_dy = f_y1 - cur_y0
                elseif f_y0 > cur_y1 then
                    frame_dy = f_y0 - cur_y1
                else
                    frame_dy = 0
                end
            else
                frame_dy = f_cy - cur_cy
                if f_x1 < cur_x0 then
                    frame_dx = f_x1 - cur_x0
                elseif f_x0 > cur_x1 then
                    frame_dx = f_x0 - cur_x1
                else
                    frame_dx = 0
                end
            end
            if ((dx < 0 and frame_dx < 0)
             or (dx > 0 and frame_dx > 0)
             or (dy > 0 and frame_dy > 0)
             or (dy < 0 and frame_dy < 0))
            then
                frame_dx = abs(frame_dx)
                frame_dy = abs(frame_dy)
                local frame_dpar = dx~=0 and frame_dx or frame_dy  -- parallel
                local frame_dperp = dx~=0 and frame_dy or frame_dx -- perpendicular
                local best_dpar = dx~=0 and best_dx or best_dy
                local best_dperp = dx~=0 and best_dy or best_dx
                if not best then
                    best_dpar, best_dperp = 1, 1e10  -- almost but not quite 90deg
                end
                if (frame_dperp / frame_dpar < best_dperp / best_dpar
                    or (frame_dperp / frame_dpar == best_dperp / best_dpar
                        and frame_dpar < best_dpar))
                then
                    best = frame
                    best_dx = frame_dx
                    best_dy = frame_dy
                end
            end
        end
    end
    return best
end

-- Perform all actions appropriate to the cursor entering a target.
function MenuFrame:EnterTarget(target)
    local params = self.targets[target]
    assert(params)

    local MARGIN = 20
    if params.scroll_frame then
        local scroll_frame = params.scroll_frame
        local scroll_top = -(scroll_frame:GetTop())
        local scroll_bottom = -(scroll_frame:GetBottom())
        local scroll_height = scroll_bottom - scroll_top
        local top = -(target:GetTop()) - scroll_top
        local bottom = -(target:GetBottom()) - scroll_top
        local scroll_amount
        if top < MARGIN then
            scroll_amount = top - MARGIN
        elseif bottom > scroll_height - MARGIN then
            scroll_amount = bottom - (scroll_height - MARGIN)
        end
        if scroll_amount then
            local scroll_target = scroll_frame:GetVerticalScroll() + scroll_amount
            -- SetVerticalScroll() automatically clamps to valid range.
            scroll_frame:SetVerticalScroll(scroll_target)
        end
    elseif params.is_scroll_box then
        local scroll_frame = target.box
        local scroll_height = scroll_frame:GetVisibleExtent()
        local scroll_current = scroll_frame:GetScrollPercentage() * scroll_frame:GetDerivedScrollRange()
        local top = scroll_frame:GetExtentUntil(target.index)
        local bottom = top + scroll_frame:GetElementExtent(target.index)
        local scroll_target
        if top - MARGIN < scroll_current then
            scroll_target = top - MARGIN
        elseif bottom + MARGIN > scroll_current + scroll_height then
            scroll_target = bottom + MARGIN - scroll_height
        end
        if scroll_target then
            -- ScrollToOffset() automatically clamps to valid range.
            scroll_frame:ScrollToOffset(scroll_target)
        end
    end

    local frame = self:GetTargetFrame(target)
    if params.lock_highlight then
        self.want_highlight = true
        if frame:IsEnabled() then
            self.highlight_locked = true
            frame:LockHighlight()
        end
    end
    if params.send_enter_leave then
        local script = frame:GetScript("OnEnter")
        if script then script(frame) end
    elseif params.on_enter then
        params.on_enter(frame)
    end
end

-- Perform all actions appropriate to the cursor leaving a target.
function MenuFrame:LeaveTarget(target)
    local params = self.targets[target]
    assert(params, "Target is not defined: "..tostring(target))
    local frame = self:GetTargetFrame(target)
    if params.lock_highlight then
        -- We could theoretically check highlight_locked here, but
        -- it should be safe to unconditionally unlock (we take the
        -- lock_highlight parameter as an indication that we have
        -- exclusive control over the highlight lock).
        frame:UnlockHighlight()
    end
    if params.send_enter_leave then
        local script = frame:GetScript("OnLeave")
        if script then script(frame) end
    elseif params.on_leave then
        params.on_leave(frame)
    end
    self.want_highlight = false
    self.highlight_locked = false
end


-------- Cursor callbacks (can be overridden by specializations if needed)

-- Per-frame update handler.  Handles locking highlight on a newly
-- enabled button.
function MenuFrame:OnUpdate(target_frame)
    if self.want_highlight and not self.highlight_locked then
        -- The button was previously disabled.  See if it is now enabled,
        -- such as in the Revival Catalyst confirmation dialog after the
        -- 5-second delay ends.  (The reverse case of an enabled button
        -- being disabled is also theoretically possible, but we ignore
        -- that case pending evidence that it can occur in practice.)
        if not target_frame.IsEnabled or target_frame:IsEnabled() then
            self.highlight_locked = true
            target_frame:LockHighlight()
        end
    end
end

-- Confirm input event handler, called from Cursor:OnClick() for confirm
-- button presses after secure click passthrough.  Receives the target on
-- which the confirm action occurred.
function MenuFrame:OnConfirm(target)
    local params = self.targets[target]
    if params.on_click then params.on_click(target) end
end

-- Cancel input event handler, called from Cursor:OnClick() for cancel
-- button presses.  Not called if the frame declares a cancel button (the
-- input is securely passed through to the button instead).
function MenuFrame:OnCancel()
    if self.cancel_func then
        self:cancel_func()
    end
end

-- Callback for cursor movement events.  Called immediately after the
-- new target has been set as active.
function MenuFrame:OnMove(old_target, new_target)
    -- No-op by default.
end


-------- Subclass interface (methods intended be called by specializations)

-- Register a watch on an ADDON_LOADED event for the given-named addon.
-- When the addon is loaded, the class method OnAddOnLoaded() is called,
-- passing the addon name as an argument.  If the addon is already loaded,
-- the method is called immediately.
-- This is a class method.
function MenuFrame.RegisterAddOnWatch(class, addon)
    if C_AddOns.IsAddOnLoaded(addon) then
        class:OnAddOnLoaded(addon)
    else
        global_cursor:RegisterEvent(function() class:OnAddOnLoaded(addon) end,
                                    "ADDON_LOADED", addon)
    end
end

-- Register an instance method as an event handler with the global cursor
-- instance.  If handler_method is omitted, the method named the same as
-- the event and optional argument (in the same style as Cursor:OnEvent())
-- is taken as the handler method,  Wraps Cursor:RegisterEvent().
function MenuFrame:RegisterEvent(handler, event, event_arg)
    if type(handler) ~= "function" then
        assert(type(handler) == "string",
               "Invalid arguments: cursor, [handler_method,] event [, event_arg]")
        event, event_arg = handler, event
        handler = self[event]
        assert(handler, "Handler method is not defined")
    end
    global_cursor:RegisterEvent(function(...) handler(self, ...) end,
                                event, event_arg)
end

-- Hook a frame's Show/Hide/SetShown methods, calling the given instance
-- methods when the frame is shown or hidden, respectively.  The frame
-- itself is passed as an argument to the event, for use when handling
-- multiple related frames with a single event (like StaticPopups).
-- If omitted, the methods default to OnShow and OnHide respectively.
-- The value false can be used to suppress a specific callback, when only
-- one of the two callbacks is needed.
function MenuFrame:HookShow(frame, show_method, hide_method)
    if show_method == nil then show_method = self.OnShow end
    if hide_method == nil then hide_method = self.OnHide end
    if show_method then
        hooksecurefunc(frame, "Show", function() show_method(self, frame) end)
    end
    if hide_method then
        hooksecurefunc(frame, "Hide", function() hide_method(self, frame) end)
    end
    hooksecurefunc(frame, "SetShown", function(_, shown)
        local func = shown and show_method or hide_method
        if func then func(self, frame) end
    end)
end

-- Add this frame to the cursor's frame list if not already present, and
-- set it as the input focus.  If initial_target is not nil, the cursor
-- target will be set to that target.
function MenuFrame:Enable(initial_target)
    global_cursor:AddFrame(self, initial_target, self.modal)
end

-- Remove this frame from the cursor's frame list.  Does nothing if the
-- frame is not on the cursor's frame list.
function MenuFrame:Disable()
    global_cursor:RemoveFrame(self)
end

-- Return whether this frame currently has input focus.
function MenuFrame:HasFocus()
    return global_cursor:GetFocus() == self
end

-- Return the current cursor target for this frame, or nil if the frame is
-- not in the cursor's frame list.
function MenuFrame:GetTarget()
    return global_cursor:GetTargetForFrame(self)
end

-- Set the cursor target for this frame to the given target.  Does nothing
-- if the frame is not in the cursor's frame list.
function MenuFrame:SetTarget(target)
    assert(not target or self.targets[target],
           "Target ("..tostring(target)..") is not in frame's target list")
    global_cursor:SetTargetForFrame(self, target)
end

-- Move the cursor target for this frame to the next target in the given
-- direction, which must be one of the strings "up", "down", "left", or
-- "right".  If the frame does not currently have a cursor target, the
-- frame's default target is selected regardless of direction.
function MenuFrame:MoveCursor(dir)
    local target = self:GetTarget()
    target = self:NextTarget(self:GetTarget(), dir)
    if target then
        self:SetTarget(target)
    end
end

-- Clear the cursor target for this frame.  Equivalent to SetTarget(nil).
-- Be sure to call this before removing a target from the frame's target list,
-- or the cursor will throw errors due to the missing target!
function MenuFrame:ClearTarget()
    self:SetTarget(nil)
end


-------- Utility functions (these are all MenuFrame class methods)

-- Generic cancel_func to close a frame.
function MenuFrame.CancelFrame(frame)
    frame:Disable()
    frame:GetFrame():Hide()
end

-- Generic cancel_func to close a UI frame.  Equivalent to CancelFrame()
-- but with calling HideUIPanel(focus) instead of focus:Hide().
function MenuFrame.CancelUIFrame(frame)
    frame:Disable()
    HideUIPanel(frame:GetFrame())
end

-- Generic cancel_func to close a UI frame, when a callback has already
-- been established on the frame's Hide() method to clear the frame focus.
function MenuFrame.HideUIFrame(frame)
    HideUIPanel(frame:GetFrame())
end

-- Shared on_leave handler which simply hides the tooltip.
function MenuFrame.HideTooltip()
    if not GameTooltip:IsForbidden() then
        GameTooltip:Hide()
    end
end

-- on_click handler for NumericInputSpinnerTemplate increment/decrement
-- buttons, which use an OnMouseDown/Up event pair instead of OnClick.
function MenuFrame.ClickNumericSpinnerButton(frame)
    frame:GetScript("OnMouseDown")(frame, "LeftButton", true)
    frame:GetScript("OnMouseUp")(frame, "LeftButton")
end

-- Return a table suitable for use as a targets[] key for an element of
-- a ScrollBox data list or tree.  Pass the ScrollBox frame and the
-- data index of the element.
function MenuFrame.PseudoFrameForScrollElement(box, index)
    return {box = box, index = index}
end

-- Take a list of targets known to be organized in rows, and return a list
-- of target rows sorted from top to bottom, each containing a list of
-- targets in the same row sorted from left to right.  The targets must
-- all be visible Frame instances.
function MenuFrame.SortTargetGrid(targets)
    local rows = {}
    local row_y = {}
    for _, target in ipairs(targets) do
        local x, y = target:GetLeft(), target:GetTop()
        local row = rows[y]
        if not row then
            tinsert(row_y, y)
            row = {}
            rows[y] = row
        end
        tinsert(row, {target, x})
    end
    table.sort(row_y, function(a, b) return a > b end)
    local result = {}
    for _, y in ipairs(row_y) do
        local row_in = rows[y]
        table.sort(row_in, function(a, b) return a[2] < b[2] end)
        local row_out = {}
        for _, v in ipairs(row_in) do
            tinsert(row_out, v[1])
        end
        tinsert(result, row_out)
    end
    return result
end

-- Add widgets in the given WidgetContainer whose type is one of the
-- given types (supported: "Spell", "Bar") to the given target list.
-- |{up,down,left,right}_target| give the targets immediately in each
-- direction relative to the widget container, and can be nil for default
-- movement rules.
function MenuFrame.AddWidgetTargets(container, widget_types,
                                    targets, up_target, down_target,
                                    left_target, right_target)
    if not container.widgetFrames then return end

    local rows = {}
    local row_y = {}
    -- FIXME: is there any better way to get the child list than
    -- breaking encapsulation?
    for _, f in pairs(container.widgetFrames) do
        local y = f:GetTop()
        if not rows[y] then
            tinsert(row_y, y)
            rows[y] = {}
        end
        tinsert(rows[y], f)
    end
    table.sort(row_y, function(a,b) return a > b end)
    for _, row in pairs(rows) do
        table.sort(row, function(a,b) return a:GetLeft() < b:GetLeft() end)
    end

    local top_first, bottom_first
    local last_y = nil
    for _, y in ipairs(row_y) do
        local row = rows[y]
        local first, last
        for i, f in ipairs(row) do
            local subframe
            for _, widget_type in ipairs(widget_types) do
                if f[widget_type] then
                    subframe = f[widget_type]
                    break
                end
            end
            if subframe then
                targets[f] = {
                    -- We have to call the subframe's methods.
                    on_enter = function(frame)
                        subframe:OnEnter()
                    end,
                    on_leave = function(frame)
                        subframe:OnLeave()
                    end,
                    up = bottom_first or up_target,
                    down = down_target,  -- Possibly rewritten below.
                }
                first = first or f
                last = f
            end
        end
        if first then
            if last_y then
                for i, f in ipairs(rows[last_y]) do
                    local params = targets[f]
                    if params then
                        params.down = first
                    end
                end
            end
            last_y = y
            top_first = top_first or first
            bottom_first = first
            targets[first].left = left_target
            targets[last].right = right_target
        end
    end
    targets[up_target].down = top_first
    targets[down_target].up = bottom_first
end

-- Return the currently selected element(s) for the given dropdown menu
-- (must be a button using Blizzard's DropdownButtonMixin).  The returned
-- values are description tables, which should be examined as appropriate
-- for the particular menu.
function MenuFrame.GetDropdownSelection(dropdown)
    -- Note that DropdownButtonMixin provides a GetSelectionData(), but
    -- it returns the wrong data!  It's not called from any other
    -- Blizzard code, so presumably it never got updated during a
    -- refactor or similar.
    local selection = select(3, dropdown:CollectSelectionData())
    if not selection then return nil end
    return unpack(selection)
end

-- Return a MenuFrame and initial cursor target for a dropdown menu using
-- the builtin DropdownButtonMixin.  Pass three arguments:
--     dropdown: Dropdown button (a Button frame).
--     cache: Table in which already-created MenuFrames will be cached.
--     getIndex: Function to return the 1-based option index of a
--         selection (as returned by GetDropdownSelection()).
--     onClick: Function to be called when an option is clicked.
function MenuFrame.SetupDropdownMenu(dropdown, cache, getIndex, onClick)
    local menu = dropdown.menu
    local menu_menu = cache[menu]
    if not menu_menu then
        menu_menu = MenuFrame(menu)
        menu_menu.cancel_func = function() dropdown:CloseMenu() end
        cache[menu] = menu_menu
        hooksecurefunc(menu, "Hide", function() menu_menu:Disable() end)
    end
    menu_menu.targets = {}
    menu_menu.item_order = {}
    local is_first = true
    for _, button in ipairs(menu:GetLayoutChildren()) do
        menu_menu.targets[button] = {
            send_enter_leave = true,
            on_click = function(button)
                button:GetScript("OnClick")(button, "LeftButton", true)
                onClick()
            end,
            is_default = is_first,
        }
        is_first = false
        -- FIXME: are buttons guaranteed to be in order?
        tinsert(menu_menu.item_order, button)
    end
    local first = menu_menu.item_order[1]
    local last = menu_menu.item_order[#menu_menu.item_order]
    menu_menu.targets[first].up = last
    menu_menu.targets[last].down = first
    local initial_target
    local selection = MenuFrame.GetDropdownSelection(dropdown)
    local index = selection and getIndex(selection)
    local initial_target = index and menu_menu.item_order[index]
    return menu_menu, initial_target
end


------------------------------------------------------------------------
-- MenuFrame subclasses for common patterns
------------------------------------------------------------------------

--[[
    MenuFrame subclass for handling a core frame (one which is initialized
    by core game code before any addons are loaded).  Includes OnShow/OnHide
    handlers which respectively call Enable() and Disable(), and a default
    cancel_func of MenuFrame.CancelUIFrame.

    If the subclass defines a SetTargets() method, it will be called by
    OnShow() and its return value will be used as the initial target to
    pass to Enable().  If the method returns false (as opposed to nil),
    the OnShow event will instead be ignored.

    A singleton instance for the (presumed also singleton) managed frame
    will be created and stored in class.instance by the default Initialize()
    implementation; the global cursor instance will be stored in class.cursor.
    No other default methods reference these values; they are provided for
    subclasses' convenience, and overriding methods do not need to initialize
    them if they are not needed.
]]--
MenuCursor.CoreMenuFrame = class(MenuFrame)
local CoreMenuFrame = MenuCursor.CoreMenuFrame

function CoreMenuFrame.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
end

function CoreMenuFrame:__constructor(frame)
    self:__super(frame)
    self:HookShow(frame)
    self.cancel_func = MenuFrame.CancelUIFrame
end

function CoreMenuFrame:OnShow()
    assert(self.frame:IsVisible())
    local initial_target = self.SetTargets and self:SetTargets()
    if initial_target ~= false then
        self:Enable(initial_target)
    end
end

function CoreMenuFrame:OnHide()
    self:Disable()
end


--[[
    MenuFrame subclass for handling an addon frame (one which is not
    available until a specific addon has been loaded).  Functions
    identically to (and in fact subclasses) CoreMenuFrame except in that
    the default Initialize() implementation sets up an addon watch for
    the addon named by class.ADDON_NAME (which must be declared by the
    subclass if it uses this implementation) and creates the singleton
    instance in the default OnAddOnLoaded() implementation.
]]--
MenuCursor.AddOnMenuFrame = class(CoreMenuFrame)
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

function AddOnMenuFrame.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch(class.ADDON_NAME)
end

function AddOnMenuFrame.OnAddOnLoaded(class)
    class.instance = class()
end
