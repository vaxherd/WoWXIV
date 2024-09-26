local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
local Gamepad = WoWXIV.Gamepad

local class = WoWXIV.class

local GameTooltip = GameTooltip
local abs = math.abs
local floor = math.floor
local function round(x) return floor(x+0.5) end
local tinsert = tinsert
local tremove = tremove


-- Static reference to the singleton MenuCursor instance.
local global_cursor = nil

------------------------------------------------------------------------
-- Core implementation
------------------------------------------------------------------------

Gamepad.MenuCursor = class()
local MenuCursor = Gamepad.MenuCursor

function MenuCursor:__constructor()
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

    for _, handler_class in pairs(MenuCursor.handlers) do
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
function MenuCursor.RegisterFrameHandler(handler_class)
    MenuCursor.handlers = MenuCursor.handlers or {}
    tinsert(MenuCursor.handlers, handler_class)
end

-- Register an event handler.  If an optional event argument is provided,
-- the function will only be called when the event's first argument is
-- equal to that value.  The event (and event argument, if given) will be
-- omitted from the arguments passed to the handler.  The {event, event_arg}
-- pair must be unique among all registered events.
function MenuCursor:RegisterEvent(handler, event, event_arg)
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
function MenuCursor:OnEvent(event, arg1, ...)
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
function MenuCursor:GAME_PAD_ACTIVE_CHANGED(active)
    self.gamepad_active = active
    self:UpdateCursor()
end

-- Handlers for entering and leaving combat, to hide or show the cursor
-- respectively.
function MenuCursor:PLAYER_REGEN_DISABLED()
    self:UpdateCursor(true)
end
function MenuCursor:PLAYER_REGEN_ENABLED()
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
function MenuCursor:AddFrame(frame, target, modal)
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
function MenuCursor:RemoveFrame(frame)
    if #self.modal_stack > 0 then
        self:InternalRemoveFrameFromStack(frame, self.modal_stack, true)
        self:InternalRemoveFrameFromStack(frame, self.focus_stack, false)
    else
        self:InternalRemoveFrameFromStack(frame, self.focus_stack, true)
    end
end

-- Internal helper for RemoveFrame().
function MenuCursor:InternalRemoveFrameFromStack(frame, stack, is_top_stack)
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
function MenuCursor:InternalGetFocusStack()
    local modal_stack = self.modal_stack
    return #modal_stack > 0 and modal_stack or self.focus_stack
end

-- Return the MenuFrame which currently has focus, or nil if none.
function MenuCursor:GetFocus()
    local stack = self:InternalGetFocusStack()
    local top = #stack
    return top > 0 and stack[top][1] or nil
end

-- Return the input element in the current focus which is currently
-- pointed to by the cursor, or nil if none (or if there is no focus).
function MenuCursor:GetTarget()
    local stack = self:InternalGetFocusStack()
    local top = #stack
    return top > 0 and stack[top][2] or nil
end

-- Return the current focus and target in a single function call.
function MenuCursor:GetFocusAndTarget()
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
function MenuCursor:SetTarget(target)
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

-- Internal helper to find a frame in the regular or modal frame stack.
-- Returns the stack and index, or (nil,nil) if not found.
function MenuCursor:InternalFindFrame(frame)
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
function MenuCursor:GetTargetForFrame(frame)
    local stack, index = self:InternalFindFrame(frame)
    return stack and stack[index][2] or nil
end

-- Set the menu cursor target for a specific frame.  Equivalent to
-- SetTarget() if the frame is topmost on the focus stack; otherwise, sets
-- the input element to be activated next time that frame becomes topmost
-- on the stack.  Does nothing if the given frame is not on the focus stack.
function MenuCursor:SetTargetForFrame(frame, target)
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
function MenuCursor:UpdateCursor(in_combat)
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
function MenuCursor:OnShow()
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
    local prev, next = focus:GetPageButtons()
    if prev and next then
        SetOverrideBinding(f, true,
                           WoWXIV_config["gamepad_menu_prev_page"],
                           "CLICK "..prev..":LeftButton")
        SetOverrideBinding(f, true,
                           WoWXIV_config["gamepad_menu_next_page"],
                           "CLICK "..next..":LeftButton")
    end
    SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_next_window"],
                       "CLICK WoWXIV_MenuCursor:CycleFrame")
    f:SetScript("OnUpdate", function() self:OnUpdate() end)
    self:OnUpdate()
end

-- Hide() handler; clears menu cursor input bindings and periodic updated.
function MenuCursor:OnHide()
    local f = self.cursor
    ClearOverrideBindings(f)
    f:SetScript("OnUpdate", nil)
end

-- Per-frame update routine which implements cursor bouncing.
function MenuCursor:OnUpdate()
    local focus, target = self:GetFocusAndTarget()
    local target_frame = target and focus:GetTargetFrame(target)
    if not target_frame then return end

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
    t = t - math.floor(t)
    local xofs = -4 * math.sin(t * math.pi)
    self.texture:ClearPointsOffset()
    self.texture:AdjustPointsOffset(xofs, 0)

    focus:OnUpdate(target_frame)
end

-- Helper for UpdateCursor() and OnUpdate() to set the cursor frame anchor.
function MenuCursor:SetCursorPoint(target)
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
function MenuCursor:SetCancelBinding(focus)
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
function MenuCursor:OnClick(button, down)
    local focus, target = self:GetFocusAndTarget()
    -- Click bindings should be cleared if we have no focus, but we could
    -- still get here right after a secure passthrough click closes the
    -- last frame.
    if not focus then return end
    if button == "DPadUp" then
        self:Move(0, 1, "up")
    elseif button == "DPadDown" then
        self:Move(0, -1, "down")
    elseif button == "DPadLeft" then
        self:Move(-1, 0, "left")
    elseif button == "DPadRight" then
        self:Move(1, 0, "right")
    elseif button == "LeftButton" then  -- i.e., confirm
        -- Click event is passed to target by SecureActionButtonTemplate.
        -- This code is called afterward, so it's possible that the click
        -- already closed our (previously) current focus frame or otherwise
        -- changed the cursor state.  If we blindly proceed with calling
        -- the on_click handler here, we could potentially perform a second
        -- click action from a single button press, so ensure that the
        -- focus state has not in fact changed.
        local new_focus, new_target = self:GetFocusAndTarget()
        if new_focus == focus and new_target == target then
            if target then
                focus:OnConfirm(target)
            end
        end
    elseif button == "Cancel" then
        -- If the frame declared a cancel button, the click is passed down
        -- as a separate event, so we only get here in the no-passthrough
        -- case.
        focus:OnCancel()
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
-- dx and dy give the movement direction with respect to screen
-- coordinates (with WoW's usual "+Y = up" mapping); dir gives the
-- direction keyword for checking target-specific movement overrides.
function MenuCursor:Move(dx, dy, dir)
    local focus, target = self:GetFocusAndTarget()
    local new_target
    if target then
        new_target = focus:NextTarget(target, dx, dy, dir)
    else
        new_target = focus:GetDefaultTarget()
    end
    if new_target then
        self:SetTarget(new_target)
    end
end


------------------------------------------------------------------------
-- Frame manager class
------------------------------------------------------------------------

local MenuFrame = class()

-- Instance constructor.  Pass the WoW Frame instance to be managed.
function MenuFrame:__constructor(frame)
    self.frame = frame

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
    --         is activated.  The element is passed as an argument.  When set
    --         with can_activate, this is called after the click event is
    --         passed down to the frame.
    --    - on_enter: If non-nil, a function to be called when the cursor
    --         is moved onto the element.  The frame is passed as an argument.
    --         Ignored if send_enter_leave is set.
    --    - on_leave: If non-nil, a function to be called when the cursor
    --         is moved off the element.  The frame is passed as an argument.
    --         Ignored if send_enter_leave is set.
    --    - scroll_frame: If non-nil, a ScrollFrame which should be scrolled
    --         to make the element visible when targeted.
    --    - send_enter_leave: If true, the frame's OnEnter and OnLeave
    --         srcipts will be called when the frame is targeted and
    --         untargeted, respectively.
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
    -- Global name of button to be clicked on a gamepad previous-page
    -- button press, or nil if none.  (Gamepad page flipping is only
    -- enabled if both this and next_page_button are non-nil.)
    self.prev_page_button = nil
    -- Global name of button to be clicked on a gamepad next-page button
    -- press, or nil if none.
    self.next_page_button = nil
    -- Should the current button be highlighted if enabled?
    -- (This is a cache of the current button's lock_highlight parameter.)
    self.want_highlight = true
    -- Is the current button highlighted via lock_highlight?
    -- (This is a cache to avoid unnecessary repeated calls to the
    -- button's LockHighlight() method in OnUpdate().)
    self.highlight_locked = false
end

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

-- Confirm input event handler, called from MenuCursor:OnClick() for
-- confirm button presses after secure click passthrough.  Receives the
-- target on which the confirm action occurred.
function MenuFrame:OnConfirm(target)
    local params = self.targets[target]
    if params.on_click then params.on_click(target) end
end

-- Cancel input event handler, called from MenuCursor:OnClick() for cancel
-- button presses.  Not called if the frame declares a cancel button (the
-- input is securely passed through to the button instead).
function MenuFrame:OnCancel()
    if self.cancel_func then
        self:cancel_func()
    end
end

-- Return the next target in the given direction from the given target,
-- or nil to indicate no next target.
-- dx and dy give the movement direction with respect to screen
-- coordinates (with WoW's usual "+Y = up" mapping); dir gives the
-- direction keyword for checking target-specific movement overrides.
function MenuFrame:NextTarget(target, dx, dy, dir)
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
                frame_dx = math.abs(frame_dx)
                frame_dy = math.abs(frame_dy)
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

-- Return the global names of the previous and next page buttons for this
-- frame, or (nil,nil) if none.
function MenuFrame:GetPageButtons()
    return self.prev_page_button, self.next_page_button
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
        frame:GetScript("OnEnter")(frame)
    elseif params.on_enter then
        params.on_enter(frame)
    end
end

-- Perform all actions appropriate to the cursor leaving a target.
function MenuFrame:LeaveTarget(target)
    local params = self.targets[target]
    assert(params)
    local frame = self:GetTargetFrame(target)
    if params.lock_highlight then
        -- We could theoretically check highlight_locked here, but
        -- it should be safe to unconditionally unlock (we take the
        -- lock_highlight parameter as an indication that we have
        -- exclusive control over the highlight lock).
        frame:UnlockHighlight()
    end
    if params.send_enter_leave then
        frame:GetScript("OnLeave")(frame)
    elseif params.on_leave then
        params.on_leave(frame)
    end
    self.want_highlight = false
    self.highlight_locked = false
end

-- Return the WoW Frame instance for this frame.
function MenuFrame:GetFrame()
    return self.frame
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


------------------------------------------------------------------------
-- Utility methods/functions
------------------------------------------------------------------------

-- Register a watch on an ADDON_LOADED event for the given-named addon.
-- When the addon is loaded, the class method OnAddOnLoaded() is called,
-- passing the addon name as an argument.  If the addon is already loaded,
-- the method is called immediately.
-- This is a class method.
function MenuFrame.RegisterAddOnWatch(class, cursor, addon)
    if C_AddOns.IsAddOnLoaded(addon) then
        class:OnAddOnLoaded(addon)
    else
        cursor:RegisterEvent(function() class:OnAddOnLoaded(addon) end,
                             "ADDON_LOADED", addon)
    end
end

-- Register an instance method as an event handler with the global cursor
-- instance.  If handler_method is omitted, the method named the same as
-- the event and optional argument (in the same style as MenuCursor:OnEvent())
-- is taken as the handler method,  Wraps MenuCursor:RegisterEvent().
function MenuFrame:RegisterEvent(cursor, handler, event, event_arg)
    if type(handler) ~= "function" then
        assert(type(handler) == "string",
               "Invalid arguments: cursor, [handler_method,] event [, event_arg]")
        event, event_arg = handler, event
        handler = self[event]
        assert(handler, "Handler method is not defined")
    end
    cursor:RegisterEvent(function(...) handler(self, ...) end,
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
    show_method = show_method ~= nil and show_method or self.OnShow
    hide_method = hide_method ~= nil and hide_method or self.OnHide
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

-- Generic cancel_func to close a frame.
function MenuFrame.CancelFrame(frame)
    global_cursor:RemoveFrame(frame)
    frame:GetFrame():Hide()
end

-- Generic cancel_func to close a UI frame.  Equivalent to CancelFrame()
-- but with calling HideUIPanel(focus) instead of focus:Hide().
function MenuFrame.CancelUIFrame(frame)
    global_cursor:RemoveFrame(frame)
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
        hooksecurefunc(menu, "Hide", function() global_cursor:RemoveFrame(menu_menu) end)
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
    handlers which respectively call AddFocus and RemoveFocus for the frame,
    and a default cancel_func of MenuFrame.CancelUIFrame.

    If the subclass defines a SetTargets() method, it will be called by
    OnShow() and its return value will be used as the initial target to
    pass to AddFrame().  If the method returns false (as opposed to nil),
    the OnShow event will instead be ignored.

    A singleton instance for the (presumed also singleton) managed frame
    will be created and stored in class.instance by the default Initialize()
    implementation; the global cursor instance will be stored in class.cursor.
    No other default methods reference these values; they are provided for
    subclasses' convenience, and overriding methods do not need to initialize
    them if they are not needed.
]]--
local CoreMenuFrame = class(MenuFrame)

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
        global_cursor:AddFrame(self, initial_target)
    end
end

function CoreMenuFrame:OnHide()
    global_cursor:RemoveFrame(self)
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
local AddOnMenuFrame = class(CoreMenuFrame)

function AddOnMenuFrame.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch(cursor, class.ADDON_NAME)
end

function AddOnMenuFrame.OnAddOnLoaded(class)
    class.instance = class()
end

------------------------------------------------------------------------
-- Individual frame handlers
------------------------------------------------------------------------

-------- Gossip (NPC dialogue) frame

local GossipFrameHandler = class(MenuFrame)
MenuCursor.RegisterFrameHandler(GossipFrameHandler)

function GossipFrameHandler.Initialize(class, cursor)
    local instance = class()
    class.instance = instance
    instance:RegisterEvent(cursor, "GOSSIP_CLOSED")
    instance:RegisterEvent(cursor, "GOSSIP_CONFIRM_CANCEL")
    instance:RegisterEvent(cursor, "GOSSIP_SHOW")
end

function GossipFrameHandler:__constructor()
    self:__super(GossipFrame)
    self.cancel_func = MenuFrame.CancelUIFrame
end

function GossipFrameHandler:GOSSIP_SHOW()
    if not GossipFrame:IsVisible() then
        return  -- Flight map, etc.
    end
    global_cursor:SetTargetForFrame(self, nil) -- In case it's already open.
    local initial_target = self:SetTargets()
    global_cursor:AddFrame(self, initial_target)
end

function GossipFrameHandler:GOSSIP_CONFIRM_CANCEL()
    -- Clear all targets to prevent further inputs until the next event
    -- (typically GOSSIP_SHOW or GOSSIP_CLOSED).
    global_cursor:SetTargetForFrame(self, nil)
    self.targets = {}
end

function GossipFrameHandler:GOSSIP_CLOSED()
    global_cursor:RemoveFrame(self)
end

function GossipFrameHandler:SetTargets()
    local goodbye = GossipFrame.GreetingPanel.GoodbyeButton
    self.targets = {[goodbye] = {can_activate = true,
                                 lock_highlight = true}}
    local up_target, down_target = goodbye, goodbye
    if GossipFrame.FriendshipStatusBar:IsShown() then
        up_target = GossipFrame.FriendshipStatusBar
        self.targets[GossipFrame.FriendshipStatusBar] =
            {send_enter_leave = true, up = goodbye}
        self.targets[goodbye].down = GossipFrame.FriendshipStatusBar
    end

    local GossipScroll = GossipFrame.GreetingPanel.ScrollBox
    local first = nil
    local last = up_target
    -- Avoid errors in Blizzard code if the list is empty.
    if GossipScroll:GetDataProvider() then
        local index = 0
        GossipScroll:ForEachElementData(function(data)
            index = index + 1
            if (data.availableQuestButton or
                data.activeQuestButton or
                data.titleOptionButton)
            then
                local pseudo_frame =
                    MenuFrame.PseudoFrameForScrollElement(GossipScroll, index)
                self.targets[pseudo_frame] = {
                    is_scroll_box = true, can_activate = true,
                    lock_highlight = true, up = last, down = down_target}
                self.targets[last].down = pseudo_frame
                if not first then first = pseudo_frame end
                last = pseudo_frame
            end
        end)
    end
    self.targets[last].down = goodbye
    self.targets[goodbye].up = last

    -- If the frame is scrollable and also has selectable options, default
    -- to the "goodbye" button to ensure that we start at the top of the
    -- scrollable text (rather than automatically scrolling to the bottom
    -- where the options are).  But we treat an extremely tiny scroll range
    -- as zero, as for the right stick scrolling logic.
    if GossipScroll:GetDerivedScrollRange() > 0.01 then
        first = nil
    end

    local default_target = first or goodbye
    self.targets[default_target].is_default = true
    return default_target
end


-------- Quest info frame

local QuestFrameHandler = class(MenuFrame)
MenuCursor.RegisterFrameHandler(QuestFrameHandler)

function QuestFrameHandler.Initialize(class, cursor)
    local instance = class()
    class.instance = instance
    instance:RegisterEvent(cursor, "QUEST_COMPLETE")
    instance:RegisterEvent(cursor, "QUEST_DETAIL")
    instance:RegisterEvent(cursor, "QUEST_FINISHED")
    instance:RegisterEvent(cursor, "QUEST_GREETING")
    instance:RegisterEvent(cursor, "QUEST_PROGRESS")
end

function QuestFrameHandler:__constructor()
    self:__super(QuestFrame)
    self.cancel_func = function()
        global_cursor:RemoveFrame(frame)
        CloseQuest()
    end
end

function QuestFrameHandler:QUEST_GREETING()
    assert(QuestFrame:IsVisible())  -- FIXME: might be false if previous quest turn-in started a cutscene (e.g. The Underking Comes in the Legion Highmountain scenario)
    self:OnShow("QUEST_GREETING")
    global_cursor:AddFrame(self)
end

function QuestFrameHandler:QUEST_DETAIL()
    -- FIXME: some map-based quests (e.g. Blue Dragonflight campaign)
    -- start a quest directly from the map; we should support those too
    if not QuestFrame:IsVisible() then return end
    self:OnShow("QUEST_DETAIL")
    global_cursor:AddFrame(self)
end

function QuestFrameHandler:QUEST_PROGRESS()
    assert(QuestFrame:IsVisible())
    self:OnShow("QUEST_PROGRESS")
    global_cursor:AddFrame(self)
end

function QuestFrameHandler:QUEST_COMPLETE()
    -- Quest frame can fail to open under some conditions?
    if not QuestFrame:IsVisible() then return end
    self:OnShow("QUEST_COMPLETE")
    global_cursor:AddFrame(self)
end

function QuestFrameHandler:QUEST_FINISHED()
    global_cursor:RemoveFrame(self)
end

function QuestFrameHandler:OnShow(event)
    if event == "QUEST_GREETING" then
        local goodbye = QuestFrameGreetingGoodbyeButton
        self.targets = {[goodbye] = {can_activate = true,
                                     lock_highlight = true}}
        local first_button, last_button, first_avail
        local avail_y = (AvailableQuestsText:IsShown()
                         and AvailableQuestsText:GetTop())
        for button in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            local y = button:GetTop()
            if not first_button then
                first_button = button
                last_button = button
            else
                if y > first_button:GetTop() then first_button = button end
                if y < last_button:GetTop() then last_button = button end
            end
            if avail_y and y < avail_y then
                if not first_avail or y > first_avail:GetTop() then
                    first_avail = button
                end
            end
        end
        self.targets[first_avail or first_button or goodbye].is_default = true

    elseif event == "QUEST_PROGRESS" then
        local can_complete = QuestFrameCompleteButton:IsEnabled()
        self.targets = {
            [QuestFrameCompleteButton] = {can_activate = true,
                                          lock_highlight = true,
                                          is_default = can_complete},
            [QuestFrameGoodbyeButton] = {can_activate = true,
                                         lock_highlight = true,
                                         is_default = not can_complete},
        }
        for i = 1, 99 do
            local name = "QuestProgressItem" .. i
            local item_frame = _G[name]
            if not item_frame or not item_frame:IsShown() then break end
            self.targets[item_frame] = {send_enter_leave = true}
        end

    else  -- DETAIL or COMPLETE
        local is_complete = (event == "QUEST_COMPLETE")
        local button1, button2
        if is_complete then
            self.targets = {
                [QuestFrameCompleteQuestButton] = {
                    up = false, down = false, left = false, right = false,
                    can_activate = true, lock_highlight = true,
                    is_default = true}
            }
            button1 = QuestFrameCompleteQuestButton
            button2 = nil
        else
            self.targets = {
                [QuestFrameAcceptButton] = {
                    up = false, down = false, left = false,
                    right = QuestFrameDeclineButton,
                    can_activate = true, lock_highlight = true,
                    is_default = true},
                [QuestFrameDeclineButton] = {
                    up = false, down = false, right = false,
                    left = QuestFrameAcceptButton,
                    can_activate = true, lock_highlight = true},
            }
            button1 = QuestFrameAcceptButton
            button2 = QuestFrameDeclineButton
        end
        local rewards = {}
        if QuestInfoSkillPointFrame:IsVisible() then
            tinsert(rewards, {QuestInfoSkillPointFrame, false})
        end
        for i = 1, 99 do
            local name = "QuestInfoRewardsFrameQuestInfoItem" .. i
            local reward_frame = _G[name]
            if not reward_frame or not reward_frame:IsShown() then break end
            tinsert(rewards, {reward_frame, true})
        end
        for reward_frame in QuestInfoRewardsFrame.spellRewardPool:EnumerateActive() do
            tinsert(rewards, {reward_frame, false})
        end
        for reward_frame in QuestInfoRewardsFrame.reputationRewardPool:EnumerateActive() do
            tinsert(rewards, {reward_frame, false})
        end
        for i, v in ipairs(rewards) do
            local frame = v[1]
            tinsert(rewards[i], frame:GetLeft())
            tinsert(rewards[i], frame:GetTop())
        end
        table.sort(rewards, function(a, b)
            return a[4] > b[4] or (a[4] == b[4] and a[3] < b[3])
        end)
        local last_l, last_r, this_l
        for _, v in ipairs(rewards) do
            local reward_frame, is_item = unpack(v)
            self.targets[reward_frame] = {
                up = false, down = false, left = false, right = false,
                can_activate = is_item, send_enter_leave = true,
                scroll_frame = (is_complete and QuestRewardScrollFrame
                                             or QuestDetailScrollFrame),
            }
            if this_l and reward_frame:GetTop() == this_l:GetTop() then
                -- Item is in the right column.
                if last_r then
                    self.targets[last_r].down = reward_frame
                    self.targets[reward_frame].up = last_r
                elseif last_l then
                    self.targets[reward_frame].up = last_l
                end
                self.targets[this_l].right = reward_frame
                self.targets[reward_frame].left = this_l
                last_l, last_r = this_l, reward_frame
                this_l = nil
            else
                -- Item is in the left column.
                if this_l then
                    last_l, last_r = this_l, nil
                end
                if last_l then
                    self.targets[last_l].down = reward_frame
                    self.targets[reward_frame].up = last_l
                end
                if last_r then
                    -- This will be overwritten if we find another item
                    -- on the same line.
                    self.targets[last_r].down = reward_frame
                end
                this_l = reward_frame
            end
        end
        if this_l then
            last_l, last_r = this_l, nil
        end
        if last_l then
            self.targets[last_l].down = button1
            self.targets[button1].up = last_l
            if button2 then
                self.targets[button2].up = last_l
            end
        end
        if last_r then
            self.targets[last_r].down = button2 or button1
            if button2 then
                self.targets[button2].up = last_r
            end
        end
    end
end


-------- Legion/BfA troop recruitment frame

local TroopRecruitmentFrameHandler = class(AddOnMenuFrame)
TroopRecruitmentFrameHandler.ADDON_NAME = "Blizzard_GarrisonUI"
MenuCursor.RegisterFrameHandler(TroopRecruitmentFrameHandler)

function TroopRecruitmentFrameHandler:__constructor()
    self:__super(GarrisonCapacitiveDisplayFrame)
    self.targets = {
        [GarrisonCapacitiveDisplayFrame.CreateAllWorkOrdersButton] =
            {can_activate = true, lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.DecrementButton] =
            {on_click = GarrisonCapacitiveDisplayFrameDecrement_OnClick,
             lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.IncrementButton] =
            {on_click = GarrisonCapacitiveDisplayFrameIncrement_OnClick,
             lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.StartWorkOrderButton] =
            {can_activate = true, lock_highlight = true,
             is_default = true},
    }
end


-------- Shadowlands covenant sanctum frame

local CovenantSanctumFrameHandler = class(AddOnMenuFrame)
CovenantSanctumFrameHandler.ADDON_NAME = "Blizzard_CovenantSanctum"
local CovenantSanctumTalentFrameHandler = class(MenuFrame)
MenuCursor.RegisterFrameHandler(CovenantSanctumFrameHandler)

function CovenantSanctumFrameHandler.OnAddOnLoaded(class)
    AddOnMenuHandler.OnAddOnLoaded(class)
    class.talent_instance = CovenantSanctumTalentFrameHandler()
end

function CovenantSanctumFrameHandler:__constructor()
    self:__super(CovenantSanctumFrame)
    local function ChooseTalent(button)
        self:OnChooseTalent(button)
    end
    self.targets = {
        [CovenantSanctumFrame.UpgradesTab.TravelUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.DiversionUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.AdventureUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.UniqueUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.DepositButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, is_default = true},
    }
end

function CovenantSanctumFrameHandler:OnChooseTalent(upgrade_button)
    upgrade_button:OnMouseDown()
    local talent_menu = CovenantSanctumFrameHandler.talent_instance
    global_cursor:AddFrame(talent_menu, talent_menu:SetTargets())
end

function CovenantSanctumTalentFrameHandler:__constructor()
    self:__super(CovenantSanctumFrame)
    self.cancel_func = function(self) global_cursor:RemoveFrame(self) end
end

function CovenantSanctumTalentFrameHandler:SetTargets()
    local TalentsList = CovenantSanctumFrame.UpgradesTab.TalentsList
    self.targets = {
        [TalentsList.UpgradeButton] =
            {can_activate = true, lock_highlight = true},
    }
    for frame in TalentsList.talentPool:EnumerateActive() do
        talent_menu.targets[frame] = {send_enter_leave = true}
    end
    return TalentsList.UpgradeButton
end


-------- Generic player choice frame

local PlayerChoiceFrameHandler = class(AddOnMenuFrame)
PlayerChoiceFrameHandler.ADDON_NAME = "Blizzard_PlayerChoice"
MenuCursor.RegisterFrameHandler(PlayerChoiceFrameHandler)

function PlayerChoiceFrameHandler:__constructor()
    self:__super(PlayerChoiceFrame)
end

function PlayerChoiceFrameHandler:SetTargets()
    local KNOWN_FORMATS = {  -- Only handle formats we've explicitly verified.
        -- Emissary boost choice, Last Hurrah quest choice, etc.
        PlayerChoiceNormalOptionTemplate = true,
        -- Cobalt anima powers, Superbloom dreamfruit, etc.
        PlayerChoiceGenericPowerChoiceOptionTemplate = true,
        -- Torghast anima powers
        PlayerChoiceTorghastOptionTemplate = true,
    }
    if not KNOWN_FORMATS[PlayerChoiceFrame.optionFrameTemplate] then
        return false
    end

    self.targets = {}
    local leftmost = nil
    for option in PlayerChoiceFrame.optionPools:EnumerateActiveByTemplate(PlayerChoiceFrame.optionFrameTemplate) do
        for button in option.OptionButtonsContainer.buttonPool:EnumerateActive() do
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            if PlayerChoiceFrame.optionFrameTemplate == "PlayerChoiceTorghastOptionTemplate" then
                self.targets[button].on_enter = function()
                    if not GameTooltip:IsForbidden() then
                        if option.OptionText:IsTruncated() then
                            option:OnEnter()
                        end
                    end
                end
                self.targets[button].on_leave = MenuFrame.HideTooltip
            else
                self.targets[button].send_enter_leave = true
            end
            if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                leftmost = button
            end
            if option.WidgetContainer:IsShown() then
                MenuFrame.AddWidgetTargets(option.WidgetContainer, {"Spell","Bar"},
                                           self.targets, button, button, false, false)
            end
        end
    end
    return leftmost or false  -- Ignore frame if no buttons found.
end


-------- New content splash frame

local SplashFrameHandler = class(CoreMenuFrame)
MenuCursor.RegisterFrameHandler(SplashFrameHandler)

function SplashFrameHandler:__constructor()
    self:__super(SplashFrame)
end

function SplashFrameHandler:SetTargets()
    self.targets = {}
    local StartQuestButton = SplashFrame.RightFeature.StartQuestButton
    if StartQuestButton:IsVisible() then
        self.targets[StartQuestButton] =
            {can_activate = true, send_enter_leave = true, is_default = true}
    end
end


-------- Info popup frame ("Campaign Complete!" etc.) (FIXME: untested)

local UIWidgetCenterDisplayFrameHandler = class(CoreMenuFrame)
MenuCursor.RegisterFrameHandler(UIWidgetCenterDisplayFrameHandler)

function UIWidgetCenterDisplayFrameHandler:__constructor()
    self:__super(UIWidgetCenterDisplayFrame)
    self.targets = {
        [UIWidgetCenterDisplayFrame.CloseButton] = {
            can_activate = true, lock_highlight = true, is_default = true},
    }
end


-------- Static popup dialogs

local StaticPopupHandler = class(MenuFrame)
MenuCursor.RegisterFrameHandler(StaticPopupHandler)

function StaticPopupHandler.Initialize(class, cursor)
    local instance = class()
    class.instances = {}
    for i = 1, STATICPOPUP_NUMDIALOGS do
        local frame_name = "StaticPopup" .. i
        local frame = _G[frame_name]
        assert(frame)
        local instance = StaticPopupHandler(frame)
        class.instances[i] = instance
        instance:HookShow(frame)
    end
end

function StaticPopupHandler:OnShow()
    if global_cursor:GetFocus() == self then return end  -- Sanity check.
    self:SetTargets()
    global_cursor:AddFrame(self, nil, true)  -- Modal frame.
end

function StaticPopupHandler:OnHide()
    global_cursor:RemoveFrame(self)
end

function StaticPopupHandler:SetTargets()
    local frame = self.frame
    self.targets = {}
    local leftmost = nil
    for i = 1, 5 do
        local name = i==5 and "extraButton" or "button"..i
        local button = frame[name]
        assert(button)
        if button:IsShown() then
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                leftmost = button
            end
        end
    end
    if leftmost then  -- i.e., if we found any buttons
        self.targets[leftmost].is_default = true
        if frame.button2:IsShown() then
            self.cancel_button = frame.button2
        end
    end
    -- Special cases for extra elements like item icons in specific popups.
    if frame.which == "CONFIRM_SELECT_WEEKLY_REWARD" then
        assert(frame.insertedFrame)
        local ItemFrame = frame.insertedFrame.ItemFrame
        assert(ItemFrame)
        assert(ItemFrame:IsShown())
        self.targets[ItemFrame] = {send_enter_leave = true,
                                   left = false, right = false}
        local AlsoItemsFrame = frame.insertedFrame.AlsoItemsFrame
        assert(AlsoItemsFrame)
        if AlsoItemsFrame:IsShown() then
            local row = {}
            for subframe in AlsoItemsFrame.pool:EnumerateActive() do
                self.targets[subframe] =
                    {send_enter_leave = true, up = ItemFrame, down = leftmost}
                tinsert(row, {subframe:GetLeft(), subframe})
            end
            table.sort(row, function(a,b) return a[1] < b[1] end)
            local first = row[1][2]
            local last = row[#row][2]
            for i = 1, #row do
                local target = row[i][2]
                self.targets[target].left = i==1 and last or row[i-1][2]
                self.targets[target].right = i==#row and first or row[i+1][2]
            end
            self.targets[ItemFrame].up = leftmost
            self.targets[ItemFrame].down = first
            self.targets[leftmost].up = first
            self.targets[leftmost].down = ItemFrame
        end
    end
end


-------- Mail inbox

local InboxFrameHandler = class(CoreMenuFrame)
MenuCursor.RegisterFrameHandler(InboxFrameHandler)

function InboxFrameHandler:__constructor()
    -- We could react to PLAYER_INTERACTION_MANAGER_FRAME_{SHOW,HIDE}
    -- with arg1 == Enum.PlayerInteractionType.MailInfo (17) for mailbox
    -- handling, but we don't currently have any support for the send UI,
    -- so we isolate our handling to the inbox frame.
    self:__super(InboxFrame)
    for i = 1, 7 do
        local frame_name = "MailItem" .. i .. "Button"
        local frame = _G[frame_name]
        assert(frame)
        self:HookShow(frame, self.OnShowMailItemButton,
                             self.OnHideMailItemButton)
    end
end

function InboxFrameHandler:OnShowMailItemButton(frame)
    self.targets[frame] = {can_activate = true, lock_highlight = true,
                           send_enter_leave = true}
    self:UpdateMovement()
end

function InboxFrameHandler:OnHideMailItemButton(frame)
    local focus, target = global_cursor:GetFocusAndTarget()
    if focus == self and target == frame then
        global_cursor:Move(0, -1, "down")
    end
    self.targets[frame] = nil
    self:UpdateMovement()
end

function InboxFrameHandler:SetTargets()
    -- We specifically hook the inbox frame, so we need a custom handler
    -- to hide the proper frame on cancel.
    self.cancel_func = function(self)
        global_cursor:RemoveFrame(self)
        HideUIPanel(MailFrame)
    end
    self.prev_page_button = "InboxPrevPageButton"
    self.next_page_button = "InboxNextPageButton"
    self.targets = {
        [OpenAllMail] = {can_activate = true, lock_highlight = true,
                         is_default = true},
        [InboxPrevPageButton] = {can_activate = true, lock_highlight = true},
        [InboxNextPageButton] = {can_activate = true, lock_highlight = true},
    }
    for i = 1, 7 do
        local button = _G["MailItem"..i.."Button"]
        assert(button)
        if button:IsShown() then
            self:OnShowMailItemButton(button)
        end
    end
    self:UpdateMovement()
end

function InboxFrameHandler:UpdateMovement()
    -- Ensure "up" from all bottom-row buttons goes to the bottommost mail item
    -- (by default, OpenAll and NextPage will go to the top item due to a lower
    -- angle of movement).
    local last_item = false
    for i = 1, 7 do
        local button = _G["MailItem"..i.."Button"]
        if button:IsShown() then
            if not last_item or button:GetTop() < last_item:GetTop() then
                last_item = button
            end
        end
    end
    self.targets[OpenAllMail].up = last_item
    self.targets[InboxPrevPageButton].up = last_item
    self.targets[InboxNextPageButton].up = last_item
end


-------- Mail item

local OpenMailFrameHandler = class(CoreMenuFrame)
MenuCursor.RegisterFrameHandler(OpenMailFrameHandler)

function OpenMailFrameHandler:__constructor()
    self:__super(OpenMailFrame)
    -- Note that the Hide event appears to fire sporadically even when the
    -- frame isn't shown in the first place.  RemoveFrame() ignores frames
    -- not in the focus list, so this isn't a problem for us and we don't
    -- need to override OnHide().
    self.cancel_func = nil
    self.cancel_button = OpenMailCancelButton
    for i = 1, 16 do
        local frame_name = "OpenMailAttachmentButton" .. i
        local frame = _G[frame_name]
        assert(frame)
        self:HookShow(frame, self.OnShowAttachmentButton,
                             self.OnHideAttachmentButton)
    end
    self:HookShow(OpenMailMoneyButton, self.OnShowMoneyButton,
                                       self.OnHideMoneyButton)
end

function OpenMailFrameHandler:OnShowAttachmentButton(frame)
    self.targets[frame] = {can_activate = true, lock_highlight = true,
                           send_enter_leave = true}
end

function OpenMailFrameHandler:OnHideAttachmentButton(frame)
    local focus, target = global_cursor:GetFocusAndTarget()
    if focus == self and target == frame then
        local new_target = nil
        local id = frame:GetID() - 1
        while id >= 1 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id - 1
        end
        if not new_target and OpenMailMoneyButton:IsShown() then
            new_target = OpenMailMoneyButton
        end
        id = frame:GetID() + 1
        while id <= 16 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id + 1
        end
        global_cursor:SetTarget(new_target or OpenMailDeleteButton)
    end
    self.targets[frame] = nil
end

function OpenMailFrameHandler:OnShowMoneyButton(frame)
    self.targets[frame] = {
        can_activate = true, lock_highlight = true,
        on_enter = function(frame)  -- hardcoded in XML
            if OpenMailFrame.money then
                GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                SetTooltipMoney(GameTooltip, OpenMailFrame.money)
                GameTooltip:Show()
            end
        end,
        on_leave = MenuFrame.HideTooltip,
    }
end

function OpenMailFrameHandler:OnHideMoneyButton(frame)
    local focus, target = global_cursor:GetFocusAndTarget()
    if focus == self and target == frame then
        local new_target = nil
        local id = 1
        while id <= 16 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id + 1
        end
        global_cursor:SetTarget(new_target or OpenMailDeleteButton)
    end
    self.targets[frame] = nil
end

function OpenMailFrameHandler:SetTargets()
    -- The cancel button is positioned slightly out of line with the other
    -- two, so we have to set explicit movement here to avoid unexpected
    -- behavior (e.g. up from "delete" moving to "close").
    self.targets = {
        [OpenMailReplyButton] = {can_activate = true, lock_highlight = true,
                                 up = false, down = false},
        [OpenMailDeleteButton] = {can_activate = true, lock_highlight = true,
                                  up = false, down = false},
        [OpenMailCancelButton] = {can_activate = true, lock_highlight = true,
                                  up = false, down = false}
    }
    local have_report_spam = OpenMailReportSpamButton:IsShown()
    if have_report_spam then
        self.targets[OpenMailReportSpamButton] = {can_activate = true,
                                                  lock_highlight = true}
    end
    local first_attachment = nil
    if OpenMailMoneyButton:IsShown() then
        self:OnShowMoneyButton(OpenMailMoneyButton)
        first_attachment = OpenMailMoneyButton
    end
    for i = 1, 16 do
        local button = _G["OpenMailAttachmentButton"..i]
        assert(button)
        if button:IsShown() then
            self:OnShowAttachmentButton(button)
            if not first_attachment then first_attachment = button end
        end
    end
    if first_attachment then
        self.targets[OpenMailReplyButton].up = first_attachment
        self.targets[OpenMailDeleteButton].up = first_attachment
        self.targets[OpenMailCancelButton].up = first_attachment
        if have_report_spam then
            self.targets[OpenMailReportSpamButton].down = first_attachment
        end
        return first_attachment
    else
        if have_report_spam then
            self.targets[OpenMailReportSpamButton].down = OpenMailCancelButton
        end
        return OpenMailCancelButton
    end
end


-------- Shop menu

local MerchantFrameHandler = class(CoreMenuFrame)
MenuCursor.RegisterFrameHandler(MerchantFrameHandler)

function MerchantFrameHandler:__constructor()
    self:__super(MerchantFrame)
    self.prev_page_button = "MerchantPrevPageButton"
    self.next_page_button = "MerchantNextPageButton"
    -- We use the "sell all junk" button (which is always displayed on the
    -- "buy" tab and never displayed on the "sell" tab) as a proxy for tab
    -- change detection.
    self:HookShow(MerchantSellAllJunkButton,
                  self.OnTabChange, self.OnTabChange)
    for i = 1, 12 do
        local frame_name = "MerchantItem" .. i .. "ItemButton"
        local frame = _G[frame_name]
        assert(frame)
        self:HookShow(frame, self.OnShowItemButton,
                             self.OnHideItemButton)
    end
end

function MerchantFrameHandler:SetTargets()
    assert(MerchantFrame.selectedTab == 1)
    self:UpdateTargets()
    self:UpdateMovement()
    return (self.targets[MerchantItem1ItemButton]
            and MerchantItem1ItemButton
            or MerchantSellAllJunkButton)
end

function MerchantFrameHandler:OnTabChange()
    self:UpdateTargets()
    self:UpdateMovement()
end

function MerchantFrameHandler:OnShowItemButton(frame, skip_update)
    self.targets[frame] = {
        lock_highlight = true, send_enter_leave = true,
        -- Pass a confirm action down as a right click because left-click
        -- activates the item drag functionality.  (On the buyback tab,
        -- right and left click do the same thing, so we don't need a
        -- special case for that.)
        on_click = function()
            MerchantItemButton_OnClick(frame, "RightButton")
        end,
    }
    -- Suppress updates when called from UpdateBuybackInfo().
    if MerchantSellAllJunkButton:IsShown() ~= (MerchantFrame.selectedTab==1) then
        skip_update = true
    end
    if not skip_update then
        self:UpdateMovement()
    end
end

function MerchantFrameHandler:OnHideItemButton(frame)
    local focus, target = global_cursor:GetFocusAndTarget()
    if focus == self and target == frame then
        local prev_id = frame:GetID() - 1
        local prev_frame = _G["MerchantItem" .. prev_id .. "ItemButton"]
        if prev_frame and prev_frame:IsShown() then
            global_cursor:SetTarget(prev_frame)
        else
            global_cursor:Move(0, -1, "down")
        end
    end
    self.targets[frame] = nil
    if MerchantSellAllJunkButton:IsShown() == (MerchantFrame.selectedTab==1) then
        self:UpdateMovement()
    end
end

function MerchantFrameHandler:UpdateTargets()
    self.targets = {
        [MerchantFrameTab1] = {can_activate = true},
        [MerchantFrameTab2] = {can_activate = true},
    }
    if MerchantFrame.selectedTab == 1 then
        self.targets[MerchantSellAllJunkButton] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true, down = MerchantFrameTab2}
        self.targets[MerchantBuyBackItemItemButton] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true,
            up = MerchantNextPageButton, down = MerchantFrameTab2}
        if MerchantPrevPageButton:IsShown() then
            self.targets[MerchantPrevPageButton] = {
                can_activate = true, lock_highlight = true,
                down = MerchantSellAllJunkButton}
            self.targets[MerchantNextPageButton] = {
                can_activate = true, lock_highlight = true,
                down = MerchantBuyBackItemItemButton}
            self.targets[MerchantSellAllJunkButton].up = MerchantPrevPageButton
            self.targets[MerchantBuyBackItemItemButton].up = MerchantNextPageButton
        end
        if MerchantRepairItemButton:IsShown() then
            self.targets[MerchantRepairItemButton] = {
                lock_highlight = true, send_enter_leave = true,
                down = MerchantFrameTab1}
            self.targets[MerchantRepairAllButton] = {
                can_activate = true, lock_highlight = true,
                send_enter_leave = true, down = MerchantFrameTab2}
            if MerchantPrevPageButton:IsShown() then
                self.targets[MerchantRepairItemButton].up = MerchantPrevPageButton
                self.targets[MerchantRepairAllButton].up = MerchantPrevPageButton
            end
            self.targets[MerchantFrameTab1].up = MerchantRepairItemButton
            self.targets[MerchantFrameTab2].up = MerchantRepairAllButton
        else
            self.targets[MerchantFrameTab1].up = MerchantSellAllJunkButton
            self.targets[MerchantFrameTab2].up = MerchantSellAllJunkButton
        end
    end
    local initial = nil
    for i = 1, 12 do
        local holder = _G["MerchantItem"..i]
        local button = _G["MerchantItem"..i.."ItemButton"]
        assert(button)
        if holder:IsShown() and button:IsShown() then
            self:OnShowItemButton(button, true)
            if not initial then
                initial = button
            end
        end
    end
end

function MerchantFrameHandler:UpdateMovement()
    -- FIXME: is this check still needed?
    if global_cursor:GetFocus() ~= self then
        return  -- Deal with calls during frame setup on UI reload.
    end
    -- Ensure correct up/down behavior, as for mail inbox.
    local last_left, last_right = false, false
    for i = 1, 12 do
        local holder = _G["MerchantItem"..i]
        local button = _G["MerchantItem"..i.."ItemButton"]
        if holder:IsShown() and button:IsShown() then
            if not last_left or button:GetTop() < last_left:GetTop() then
                last_left = button
                last_right = button
            elseif button:GetTop() == last_left:GetTop() and button:GetLeft() > last_left:GetLeft() then
                last_right = button
            end
        end
    end
    if MerchantPrevPageButton:IsShown() then
        self.targets[MerchantPrevPageButton].up = last_left
        self.targets[MerchantNextPageButton].up = last_right
        if last_left then
            self.targets[last_left].down = MerchantPrevPageButton
            if last_right ~= last_left then
                self.targets[last_right].down = MerchantNextPageButton
            end
        end
    elseif MerchantSellAllJunkButton:IsShown() then
        local left
        if MerchantRepairItemButton:IsShown() then
            self.targets[MerchantRepairItemButton].up = last_left
            self.targets[MerchantRepairAllButton].up = last_left
            left = MerchantRepairItemButton
        else
            left = MerchantSellAllJunkButton
        end
        self.targets[MerchantSellAllJunkButton].up = last_left
        self.targets[MerchantBuyBackItemItemButton].up = last_right
        if last_left then
            self.targets[last_left].down = left
            if last_right ~= last_left then
                self.targets[last_right].down = MerchantBuyBackItemItemButton
            end
        end
    elseif MerchantFrameTab1:IsShown() then
        self.targets[MerchantFrameTab1].up = last_left
        self.targets[MerchantFrameTab2].up = last_right
        if last_left then
            self.targets[last_left].down = MerchantFrameTab1
            if last_right ~= last_left then
                self.targets[last_right].down = MerchantFrameTab2
            end
        end
    end
end


-------- Profession training menu

local ClassTrainerFrameHandler = class(AddOnMenuFrame)
ClassTrainerFrameHandler.ADDON_NAME = "Blizzard_TrainerUI"
MenuCursor.RegisterFrameHandler(ClassTrainerFrameHandler)

function ClassTrainerFrameHandler:__constructor()
    self:__super(ClassTrainerFrame)
    self.targets = {
        [ClassTrainerFrameSkillStepButton] = {
            can_activate = true, lock_highlight = true,
            up = ClassTrainerTrainButton},
        [ClassTrainerTrainButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            down = ClassTrainerFrameSkillStepButton},
    }
end

function ClassTrainerFrameHandler:SetTargets()
    -- FIXME: also allow moving through list (ClassTrainerFrame.ScrollBox)
    -- (this temporary hack selects the first item so that we can still train)
    RunNextFrame(function()
        for _, frame in ClassTrainerFrame.ScrollBox:EnumerateFrames() do
            ClassTrainerSkillButton_OnClick(frame, "LeftButton")
            break
        end
    end)
end


-------- Talents/spellbook frame

local SpellBookFrameHandler = class(MenuFrame)
MenuCursor.RegisterFrameHandler(SpellBookFrameHandler)

function SpellBookFrameHandler.Initialize(class, cursor)
    class:RegisterAddOnWatch(cursor, "Blizzard_PlayerSpells")
end

function SpellBookFrameHandler.OnAddOnLoaded(class)
    local instance = class()
    class.instance = instance
    instance:HookShow(PlayerSpellsFrame)

    local sbf = PlayerSpellsFrame.SpellBookFrame
    instance:HookShow(sbf, instance.OnShowSpellBookTab, instance.OnHide)
    EventRegistry:RegisterCallback(
        "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged",
        function()
            if PlayerSpellsFrame.SpellBookFrame:IsVisible() then
                global_cursor:SetTargetForFrame(instance,
                                                instance:RefreshTargets())
            end
        end)
    local pc = sbf.PagedSpellsFrame.PagingControls
    local buttons = {sbf.HidePassivesCheckButton.Button,
                     pc.PrevPageButton, pc.NextPageButton}
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        tinsert(buttons, tab)
    end
    for _, button in ipairs(buttons) do
        hooksecurefunc(button, "Click", function() global_cursor:SetTargetForFrame(instance, instance:RefreshTargets()) end)
    end
end

function SpellBookFrameHandler:__constructor()
    self:__super(PlayerSpellsFrame.SpellBookFrame)
    self.cancel_func = function()
        HideUIPanel(PlayerSpellsFrame)
    end
end

function SpellBookFrameHandler:OnShow()
    if PlayerSpellsFrame.SpellBookFrame:IsShown() then
        self:OnShowSpellBookTab()
    end
end

function SpellBookFrameHandler:OnHide()
    global_cursor:RemoveFrame(self)
end

function SpellBookFrameHandler:OnShowSpellBookTab()
    if not PlayerSpellsFrame:IsShown() then return end
    local target = self:RefreshTargets()
    global_cursor:AddFrame(self, target)
end

-- Effectively the same as SpellBookItemMixin:OnIconEnter() and ...Leave()
-- from Blizzard_SpellBookItem.lua.  We need to reimplement them ourselves
-- because those functions touch global variables, which become tainted if
-- we call the functions directly.  (As a result, action bar highlights are
-- not updated as they would be from mouse movement.)
local function SpellBookFrame_OnEnterButton(frame)
    local item = frame:GetParent()
    if not item:HasValidData() then
        return
    end
    if not item.isUnlearned then
        item.Button.IconHighlight:Show()
        item.Backplate:SetAlpha(item.hoverBackplateAlpha)
    end
    GameTooltip:SetOwner(item.Button, "ANCHOR_RIGHT")
    GameTooltip:SetSpellBookItem(item.slotIndex, item.spellBank)
    local actionBarStatusToolTip = item.actionBarStatus and SpellSearchUtil.GetTooltipForActionBarStatus(item.actionBarStatus)
    if actionBarStatusToolTip then
        GameTooltip_AddColoredLine(GameTooltip, actionBarStatusToolTip, LIGHTBLUE_FONT_COLOR)
    end
    GameTooltip:Show()
end

local function SpellBookFrame_OnLeaveButton(frame)
    local item = frame:GetParent()
    if not item:HasValidData() then
        return
    end
    item.Button.IconHighlight:Hide()
    item.Button.IconHighlight:SetAlpha(item.iconHighlightHoverAlpha)
    item.Backplate:SetAlpha(item.defaultBackplateAlpha)
    GameTooltip:Hide()
end

-- Return the closest spell button to the given Y coordinate in the given
-- button column.  Helper for SpellBookFrameHandler:RefreshTargets().
local function ClosestSpellButton(column, y)
    local best = column[1][1]
    local best_diff = abs(column[1][2] - y)
    for i = 2, #column do
        local diff = abs(column[i][2] - y)
        if diff < best_diff then
            best = column[i][1]
            best_diff = diff
        end
    end
    return best
end

-- Returns the new cursor target.
function SpellBookFrameHandler:RefreshTargets()
    local sbf = PlayerSpellsFrame.SpellBookFrame

    --[[
        Movement layout:

        [Category tabs]             ←→             [] Hide Passives
             ↑↓                                          ↑↓
        Top left spell ←→ ..................... ←→ Top right spell
             ↑↓                   ↑↓                   ↑↓
            .......         .....................          ........
          Left column  ←→ ..................... ←→   Right column
            .......         .....................          ........
             ↑↓                   ↑↓                   ↑↓
        Bottom left spell ←→ ................ ←→ Bottom right spell
              ↑                                           ↑↓
              ↓                               ↓→ Page N/M [<] ←→ [>]
        [Specialization] [Talents] [Spellbook] ←
    ]]--

    self.targets = {
        [sbf.HidePassivesCheckButton.Button] = {
            can_activate = true, lock_highlight = true, right = false},
    }

    local default_page_tab = nil
    local left_page_tab = nil
    local right_page_tab = nil
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab] = {can_activate = true, send_enter_leave = true,
                                 up = bottom, down = top}
            -- HACK: breaking encapsulation to access tab selected state
            if not default_page_tab or tab.isSelected then
                default_page_tab = tab
            end
            if not left_page_tab or tab:GetLeft() < left_page_tab:GetLeft() then
                left_page_tab = tab
            end
            if not right_page_tab or tab:GetLeft() > right_page_tab:GetLeft() then
                right_page_tab = tab
            end
        end
    end
    self.targets[left_page_tab].left = false
    self.targets[right_page_tab].right = sbf.HidePassivesCheckButton.Button

    local default_book_tab = nil
    local right_book_tab = nil
    for _, tab in ipairs(PlayerSpellsFrame.TabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab] = {can_activate = true, send_enter_leave = true,
                                 down = default_page_tab}
            -- HACK: breaking encapsulation to access tab selected state
            if not default_book_tab or tab.isSelected then
                default_book_tab = tab
            end
            if not right_book_tab or tab:GetLeft() > right_book_tab:GetLeft() then
                right_book_tab = tab
            end
        end
    end
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab].up = default_book_tab
        end
    end

    local pc = sbf.PagedSpellsFrame.PagingControls
    local page_buttons = {pc.PrevPageButton, pc.NextPageButton}
    for _, button in ipairs(page_buttons) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                up = sbf.HidePassivesCheckButton.Button,
                                down = right_book_tab}
    end
    self.targets[right_book_tab].right = pc.PrevPageButton
    self.targets[pc.PrevPageButton].left = right_book_tab
    self.targets[pc.NextPageButton].right = false
    self.targets[sbf.HidePassivesCheckButton.Button].down = pc.PrevPageButton

    local first_spell = nil
    local columns = {}
    local column_x = {}
    sbf:ForEachDisplayedSpell(function(spell)
        local button = spell.Button
        local x = button:GetLeft()
        if not columns[x] then
            columns[x] = {}
            tinsert(column_x, x)
        end
        tinsert(columns[x], {button, button:GetTop()})
    end)
    table.sort(column_x, function(a,b) return a < b end)
    for _, column in pairs(columns) do
        table.sort(column, function(a,b) return a[2] > b[2] end)
    end
    for x_index, x in ipairs(column_x) do
        local is_left = (x_index == 1)
        local is_right = (x_index == #column_x)
        local is_left_half = ((x_index-1) < 0.5*(#column_x-1))
        local top_target =
            is_left_half and default_page_tab or sbf.HidePassivesCheckButton.Button
        local bottom_target =
            is_left_half and default_book_tab or pc.PrevPageButton
        local column = columns[x]
        for i, button_pair in ipairs(column) do
            local button, y = button_pair[1], button_pair[2]
            local is_top = (i == 1)
            local is_bottom = (i == #column)
            self.targets[button] = {
                can_activate = true,
                on_enter = function(frame) SpellBookFrame_OnEnterButton(frame) end,
                on_leave = function(frame) SpellBookFrame_OnLeaveButton(frame) end,
                up = is_top and top_target or column[i-1][1],
                down = is_bottom and bottom_target or column[i+1][1],
                left = not is_left and ClosestSpellButton(columns[column_x[x_index-1]], y),
                right = not is_right and ClosestSpellButton(columns[column_x[x_index+1]], y),
            }
            if is_left and is_top then
                first_spell = button
            end
            if is_right then
                if is_top then
                    self.targets[sbf.HidePassivesCheckButton.Button].down = button
                end
                if is_bottom then
                    for _, page_button in ipairs(page_buttons) do
                        self.targets[page_button].up = button
                    end
                end
            end
        end
    end

    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab].down = first_spell or default_book_tab
        end
    end

    -- If the cursor was previously on a spell button, the button might
    -- have disappeared, so reset to the top of the page.
    local cur_target = global_cursor:GetTargetForFrame(self)
    if not self.targets[cur_target] then
        cur_target = nil
    end

    return cur_target or first_spell or default_page_tab
end


-------- Professions frame

local ProfessionsBookFrameHandler = class(AddOnMenuFrame)
ProfessionsBookFrameHandler.ADDON_NAME = "Blizzard_ProfessionsBook"
MenuCursor.RegisterFrameHandler(ProfessionsBookFrameHandler)

function ProfessionsBookFrameHandler:__constructor()
    self:__super(ProfessionsBookFrame)
end

local PROFESSION_BUTTONS_P = {
    "PrimaryProfession1SpellButtonTop",
    "PrimaryProfession1SpellButtonBottom",
    "PrimaryProfession2SpellButtonTop",
    "PrimaryProfession2SpellButtonBottom",
}
local PROFESSION_BUTTONS_S = {
    "SecondaryProfession1SpellButtonLeft",
    "SecondaryProfession1SpellButtonRight",
    "SecondaryProfession2SpellButtonLeft",
    "SecondaryProfession2SpellButtonRight",
    "SecondaryProfession3SpellButtonLeft",
    "SecondaryProfession3SpellButtonRight",
}
function ProfessionsBookFrameHandler:SetTargets()
    self.targets = {}
    local initial = nil
    local bottom = nil
    for _, bname in ipairs(PROFESSION_BUTTONS_P) do
        local button = _G[bname]
        assert(button)
        if button:IsShown() then
            self.targets[button] = {can_activate = true, lock_highlight = true}
            if not initial then
                self.targets[button].is_default = true
                initial = button
            end
            bottom = button
        end
    end
    local bottom_primary = bottom or false
    local first_secondary = nil
    for _, bname in ipairs(PROFESSION_BUTTONS_S) do
        local button = _G[bname]
        assert(button)
        if button:IsShown() then
            self.targets[button] = {can_activate = true, lock_highlight = true}
            if not initial then
                self.targets[button].is_default = true
                initial = button
            end
            if not first_secondary then
                first_secondary = button
            end
            if button:GetTop() == first_secondary:GetTop() then
                self.targets[button].up = bottom_primary
            end
            if not bottom or button:GetTop() < bottom:GetTop() then
                bottom = button
            end
        end
    end
end


-------- Crafting frame

local ProfessionsFrameHandler = class(MenuFrame)
local SchematicFormHandler = class(MenuFrame)
local QualityDialogHandler = class(MenuFrame)
local ItemFlyoutHandler = class(MenuFrame)
MenuCursor.RegisterFrameHandler(ProfessionsFrameHandler)

function ProfessionsFrameHandler.Initialize(class, cursor)
    class:RegisterAddOnWatch(cursor, "Blizzard_Professions")
end

function ProfessionsFrameHandler.OnAddOnLoaded(class)
    local instance = class()
    class.instance = instance
    class.instance_SchematicForm = SchematicFormHandler()
    class.instance_QualityDialog = QualityDialogHandler()
    class.instance_ItemFlyout = ItemFlyoutHandler()
end

function ProfessionsFrameHandler:__constructor()
    self:__super(ProfessionsFrame)
    self:HookShow(ProfessionsFrame)
    self:RegisterEvent(global_cursor, "TRADE_SKILL_LIST_UPDATE")
    self.cancel_func = MenuFrame.HideUIFrame
end

function SchematicFormHandler:__constructor()
    self:__super(ProfessionsFrame.CraftingPage.SchematicForm)
    self:HookShow(ProfessionsFrame.CraftingPage.CreateAllButton,
                  self.OnShowCreateAllButton, self.OnHideCreateAllButton)
    self.cancel_func = function(self)
        global_cursor:RemoveFrame(self)
        self.targets = {}  -- suppress update calls from CreateAllButton:Show() hook
    end
end

function QualityDialogHandler:__constructor()
    local QualityDialog = ProfessionsFrame.CraftingPage.SchematicForm.QualityDialog
    self:__super(QualityDialog)
    self:HookShow(QualityDialog)
    self.cancel_button = QualityDialog.CancelButton
    self.targets = {
        [QualityDialog.Container1.EditBox.DecrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container1.EditBox.IncrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container2.EditBox.DecrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container2.EditBox.IncrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container3.EditBox.DecrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container3.EditBox.IncrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.AcceptButton] = {
            can_activate = true, lock_highlight = true, is_default = true},
        [QualityDialog.CancelButton] = {
            can_activate = true, lock_highlight = true},
    }
end

function ItemFlyoutHandler:__constructor()
    -- The item selector popup doesn't have a global reference, so we need
    -- this hack to get the frame.
    local ItemFlyout = OpenProfessionsItemFlyout(UIParent, UIParent)
    CloseProfessionsItemFlyout()
    self:__super(ItemFlyout)
    self:HookShow(ItemFlyout)
    self.cancel_func = CloseProfessionsItemFlyout  -- Blizzard function.
end

function ProfessionsFrameHandler:TRADE_SKILL_LIST_UPDATE()
    if self.need_refresh then
        -- The list itself apparently isn't ready until the next frame.
        RunNextFrame(function()
            global_cursor:SetTargetForFrame(self, self:RefreshTargets())
        end)
    end
end

function ProfessionsFrameHandler:OnShow()
    assert(ProfessionsFrame:IsShown())
    self.need_refresh = true
    self.targets = {}
    global_cursor:AddFrame(self)
    RunNextFrame(function()
        global_cursor:SetTargetForFrame(self, self:RefreshTargets())
    end)
end

function ProfessionsFrameHandler:OnHide()
    global_cursor:RemoveFrame(self)
    global_cursor:RemoveFrame(ProfessionsFrameHandler.instance_SchematicForm)
end

function SchematicFormHandler:OnShowCreateAllButton()
    -- FIXME: this gets called every second, avoid update calls if no change
    if self.targets[ProfessionsFrame.CraftingPage.CreateButton] then
        self:UpdateMovement()
    end
end

function SchematicFormHandler:OnHideCreateAllButton()
    if self.targets[ProfessionsFrame.CraftingPage.CreateButton] then
        local CraftingPage = ProfessionsFrame.CraftingPage
        local cur_target = global_cursor:GetTargetForFrame(self)
        if (cur_target == CraftingPage.CreateAllButton
         or cur_target == CraftingPage.CreateMultipleInputBox.DecrementButton
         or cur_target == CraftingPage.CreateMultipleInputBox.IncrementButton)
        then
            global_cursor:SetTargetForFrame(self, CraftingPage.CreateButton)
        end
        self:UpdateMovement()
    end
end

function QualityDialogHandler:OnShow()
    global_cursor:AddFrame(self)
end

function QualityDialogHandler:OnHide()
    global_cursor:RemoveFrame(self)
end

function ItemFlyoutHandler:OnShow()
    self.targets = {}
    global_cursor:AddFrame(self)
    RunNextFrame(function() self:RefreshTargets() end)
end

function ItemFlyoutHandler:OnHide(frame)
    global_cursor:RemoveFrame(self)
end

function SchematicFormHandler:UpdateMovement()
    local CraftingPage = ProfessionsFrame.CraftingPage
    local create_left
    if CraftingPage.CreateAllButton:IsShown() then
        self.targets[CraftingPage.CreateButton].left = nil
        self.targets[CraftingPage.SchematicForm.OutputIcon].up = CraftingPage.CreateAllButton
        create_left = CraftingPage.CreateAllButton
    else
        self.targets[CraftingPage.CreateButton].left = false
        self.targets[CraftingPage.SchematicForm.OutputIcon].up = CraftingPage.CreateButton
        create_left = CraftingPage.CreateButton
    end

    local r_bottom = self.r_bottom
    if r_bottom then
        self.targets[r_bottom].down = create_left
    end
    local SchematicForm = CraftingPage.SchematicForm
    local frsc = SchematicForm.Details.CraftingChoicesContainer.FinishingReagentSlotContainer
    if frsc and frsc:IsVisible() then
        for _, frame in ipairs({frsc:GetChildren()}) do
            local button = frame:GetChildren()
            if self.targets[button] then
                self.targets[button].down = create_left
            end
        end
    end
    if SchematicForm.OptionalReagents:IsShown() then
        for _, frame in ipairs({SchematicForm.OptionalReagents:GetChildren()}) do
            local button = frame:GetChildren()
            if self.targets[button] then
                self.targets[button].down = create_left
            end
        end
    end
end

local function ProfessionsFrame_ClickItemButton(button)
    local onMouseDown = button:GetScript("OnMouseDown")
    assert(onMouseDown)
    -- We pass down=true for completeness, but all current implementations
    -- ignore that parameter and don't register for button-up events.
    onMouseDown(button, "LeftButton", true)
end

function SchematicFormHandler:SetTargets()
    local CraftingPage = ProfessionsFrame.CraftingPage
    local SchematicForm = CraftingPage.SchematicForm

    self.targets = {
        [SchematicForm.OutputIcon] = {send_enter_leave = true},
        [CraftingPage.CreateAllButton] = {
            can_activate = true, lock_highlight = true,
            down = SchematicForm.OutputIcon, left = false},
        [CraftingPage.CreateMultipleInputBox.DecrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            down = SchematicForm.OutputIcon},
        [CraftingPage.CreateMultipleInputBox.IncrementButton] = {
            on_click = MenuFrame.ClickNumericSpinnerButton,
            lock_highlight = true,
            down = SchematicForm.OutputIcon},
        [CraftingPage.CreateButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            down = SchematicForm.OutputIcon, right = false},
    }

    local r_left, r_right = false, false
    local frsc = SchematicForm.Details.CraftingChoicesContainer.FinishingReagentSlotContainer
    if frsc and frsc:IsVisible() then
        for _, frame in ipairs({frsc:GetChildren()}) do
            local button = frame:GetChildren()
            self.targets[button] = {
                on_click = ProfessionsFrame_ClickItemButton,
                lock_highlight = true, send_enter_leave = true,
                up = false, down = CraftingPage.CreateButton}
            if not r_left or button:GetLeft() < r_left:GetLeft() then
                r_left = button
            end
            if not r_right or button:GetLeft() > r_right:GetLeft() then
                r_right = button
            end
        end
    end
    local ctb = SchematicForm.Details.CraftingChoicesContainer.ConcentrateContainer.ConcentrateToggleButton
    if ctb and ctb:IsVisible() then
        self.targets[ctb] = {
            can_activate = true, lock_highlight = true,
            send_enter_leave = true,
            up = false, down = CraftingPage.CreateButton}
        if not r_left or ctb:GetLeft() < r_left:GetLeft() then
            r_left = ctb
        end
        if not r_right or ctb:GetLeft() > r_right:GetLeft() then
            r_right = ctb
        end
    end

    local r_top, r_bottom = false, false
    if SchematicForm.Reagents:IsShown() then
        for _, frame in ipairs({SchematicForm.Reagents:GetChildren()}) do
            local button = frame:GetChildren()
            if button:IsVisible() then
                self.targets[button] = {
                    lock_highlight = true, send_enter_leave = true,
                    left = false, right = r_left}
                if button:GetScript("OnMouseDown") then
                    self.targets[button].on_click = ProfessionsFrame_ClickItemButton
                elseif button:GetScript("OnClick") then
                    self.targets[button].can_activate = true
                end
                if not r_top or button:GetTop() > r_top:GetTop() then
                    r_top = button
                end
                if not r_bottom or button:GetTop() < r_bottom:GetTop() then
                    r_bottom = button
                end
            end
        end
        if r_top then
            self.targets[r_top].up = SchematicForm.OutputIcon
        end
        if r_bottom and r_left then
            self.targets[r_left].left = r_bottom
        end
    end

    if SchematicForm.OptionalReagents:IsShown() then
        local or_left, or_right
        for _, frame in ipairs({SchematicForm.OptionalReagents:GetChildren()}) do
            local button = frame:GetChildren()
            if button:IsVisible() then
                self.targets[button] = {
                    on_click = ProfessionsFrame_ClickItemButton,
                    lock_highlight = true, send_enter_leave = true,
                    up = r_bottom, down = CraftingPage.CreateAllButton}
                if not or_left or button:GetLeft() < or_left:GetLeft() then
                    or_left = button
                end
                if not or_right or button:GetLeft() > or_right:GetLeft() then
                    or_right = button
                end
            end
        end
        if or_left then
            self.targets[or_left].left = false
            r_bottom = or_left
        end
        if or_right then
            self.targets[or_right].right = r_left
            if r_left then
                self.targets[r_left].left = or_right
            end
        end
    end

    local create_left_up = r_left or r_bottom or SchematicForm.OutputIcon
    local create_right_up = r_right or r_bottom or SchematicForm.OutputIcon
    self.targets[CraftingPage.CreateAllButton].up = create_left_up
    self.targets[CraftingPage.CreateMultipleInputBox.DecrementButton].up = create_left_up
    self.targets[CraftingPage.CreateMultipleInputBox.IncrementButton].up = create_left_up
    self.targets[CraftingPage.CreateButton].up = create_right_up
    self.r_bottom = r_bottom

    self:UpdateMovement()
    return r_top
end

function ItemFlyoutHandler:RefreshTargets()
    local frame = self.frame
    local ItemScroll = frame.ScrollBox
    local checkbox = frame.HideUnownedCheckbox
    self.targets = {
        [checkbox] = {can_activate = true, lock_highlight = true,
                      on_click = function()
                          -- We have to wait a frame for button layout.
                          -- Ensure that a D-pad press during that frame
                          -- doesn't leave us on a vanished button.
                          self.targets = {[checkbox] = self.targets[checkbox]}
                          RunNextFrame(function() self:RefreshTargets() end)
                      end},
    }
    local default = nil
    local last_y = nil
    local rows = {}
    -- Avoid errors in Blizzard code if the list is empty.
    if ItemScroll:GetDataProvider() then
        local index = 0
        ItemScroll:ForEachElementData(function(element)
            index = index + 1
            local button = ItemScroll:FindFrame(ItemScroll:FindElementData(index))
            if button then  -- FIXME: need to deal with overflowing lists (e.g. embellishments)
                local pseudo_frame =
                    MenuFrame.PseudoFrameForScrollElement(ItemScroll, index)
                self.targets[pseudo_frame] = {
                    is_scroll_box = true, can_activate = true,
                    up = false, down = false, left = false, right = false}
                default = default or pseudo_frame
                assert(self:GetTargetFrame(pseudo_frame) == button)
                assert(button:IsShown())
                assert(button:GetTop() ~= nil)
                local y = button:GetTop()
                if y == last_y then
                    tinsert(rows[#rows], pseudo_frame)
                else
                    last_y = y
                    tinsert(rows, {pseudo_frame})
                end
            end
        end)
        local first_row = rows[1]
        local last_row = rows[#rows]
        for i, row in ipairs(rows) do
            local prev_row = i > 1 and rows[i-1]
            local next_row = i < #rows and rows[i+1]
            for j, pseudo_frame in ipairs(row) do
                local target_info = self.targets[pseudo_frame]
                target_info.up = prev_row and prev_row[j] or checkbox
                target_info.down = next_row and (next_row[j] or next_row[#next_row]) or checkbox
                if j > 1 then
                    target_info.left = row[j-1]
                elseif prev_row then
                    target_info.left = prev_row[#prev_row]
                else
                    target_info.left = last_row[#last_row]
                end
                if j < #row then
                    target_info.right = row[j+1]
                elseif next_row then
                    target_info.right = next_row[1]
                else
                    target_info.right = first_row[1]
                end
            end
        end
        self.targets[checkbox].up = last_row[1]
        self.targets[checkbox].down = first_row[1]
    end
    local cur_target = global_cursor:GetTargetForFrame(self)
    global_cursor:SetTargetForFrame(self, cur_target or default or checkbox)
end

function ProfessionsFrameHandler:FocusRecipe(tries)
    local CraftingPage = ProfessionsFrame.CraftingPage
    local SchematicForm = CraftingPage.SchematicForm
    assert(SchematicForm:IsShown())
    if SchematicForm.recraftSlot:IsShown() then
        return  -- We don't currently handle the recrafting interface.
    end
    if not CraftingPage.CreateButton:IsShown() then
        -- Recipe data is still loading, or recipe is not learned.
        tries = tries or 10
        if tries > 0 then
            RunNextFrame(function() self:FocusRecipe(tries-1) end)
        end
        return
    end
    local form = ProfessionsFrameHandler.instance_SchematicForm
    local initial_target = form:SetTargets()
    global_cursor:AddFrame(form, initial_target)
end

local PROFESSION_GEAR_SLOTS = {
    "Prof0ToolSlot",
    "Prof0Gear0Slot",
    "Prof0Gear1Slot",
    "Prof1ToolSlot",
    "Prof1Gear0Slot",
    "Prof1Gear1Slot",
    "CookingToolSlot",
    "CookingGear0Slot",
    "FishingToolSlot",
}
function ProfessionsFrameHandler:RefreshTargets(initial_element)
    local CraftingPage = ProfessionsFrame.CraftingPage

    global_cursor:SetTargetForFrame(self, nil)
    self.targets = {}
    local top, bottom, initial = nil, nil, nil

    if CraftingPage:IsShown() then
        self.targets[CraftingPage.LinkButton] = {
            can_activate = true, lock_highlight = true,
            up = false, down = false}
        for _, slot_id in ipairs(PROFESSION_GEAR_SLOTS) do
            local slot = CraftingPage[slot_id]
            if slot:IsShown() then
                self.targets[slot] = {
                    lock_highlight = true, send_enter_leave = true,
                    up = false, down = false}
            end
        end
        local RecipeScroll = CraftingPage.RecipeList.ScrollBox
        local index = 0
        RecipeScroll:ForEachElementData(function(element)
            self.need_refresh = false
            index = index + 1
            local data = element:GetData()
            if data.categoryInfo or data.recipeInfo then
                local pseudo_frame =
                    MenuFrame.PseudoFrameForScrollElement(RecipeScroll, index)
                self.targets[pseudo_frame] = {
                    is_scroll_box = true, can_activate = true,
                    up = bottom or false, down = false,
                    left = false, right = CraftingPage.LinkButton}
                if data.recipeInfo then
                    self.targets[pseudo_frame].on_click = function()
                        self:FocusRecipe()
                    end
                else  -- is a category header
                    self.targets[pseudo_frame].on_click = function()
                        local target = self:RefreshTargets(element)
                        global_cursor:SetTargetForFrame(self, target)
                    end
                end
                if bottom then
                    self.targets[bottom].down = pseudo_frame
                end
                if not top then
                    top = pseudo_frame
                    self.targets[CraftingPage.LinkButton].left = pseudo_frame
                end
                bottom = pseudo_frame
                if initial_element then
                    if initial_element == element then
                        initial = pseudo_frame
                    end
                else
                    if not initial and self:GetTargetFrame(pseudo_frame) then
                        initial = pseudo_frame
                    end
                end
            end
        end)
    end

    local default_tab = nil
    for _, tab in ipairs(ProfessionsFrame.TabSystem.tabs) do
        if tab:IsShown() then
            self.targets[tab] = {can_activate = true, send_enter_leave = true,
                                 up = bottom, down = top}
            -- HACK: breaking encapsulation to access tab selected state
            if not default_tab or tab.isSelected then default_tab = tab end
        end
    end
    if top then
        self.targets[top].up = default_tab or bottom or false
    end
    if bottom then
        self.targets[bottom].down = default_tab or top or false
    end

    if not initial then
        initial = top or default_tab
        assert(initial)
    end
    return initial
end


-------- Great Vault

local WeeklyRewardsFrameHandler = class(AddOnMenuFrame)
WeeklyRewardsFrameHandler.ADDON_NAME = "Blizzard_WeeklyRewards"
MenuCursor.RegisterFrameHandler(WeeklyRewardsFrameHandler)

function WeeklyRewardsFrameHandler:__constructor()
    self:__super(WeeklyRewardsFrame)
end

function WeeklyRewardsFrameHandler:SetTargets()
    self.targets = {}
    if WeeklyRewardsFrame.Overlay and WeeklyRewardsFrame.Overlay:IsShown() then
        return  -- Prevent any menu input if the blocking overlay is up.
    end
    local can_claim = C_WeeklyRewards.CanClaimRewards()
    local row_y = {}
    local rows = {}
    for _, info in ipairs(C_WeeklyRewards.GetActivities()) do
        local frame = WeeklyRewardsFrame:GetActivityFrame(info.type, info.index)
        if frame and frame ~= WeeklyRewardsFrame.ConcessionFrame then
            local unlocked = can_claim and #info.rewards > 0
            local x = frame:GetLeft()
            local y = frame:GetTop()
            -- If a reward is available, we want to target the item itself
            -- rather than the activity box, but the activity box is still
            -- the frame that needs to get the click on activation.
            local target
            if unlocked then
                target = frame.ItemFrame
                self.targets[target] = {
                    send_enter_leave = true,
                    on_click = function()
                        frame:GetScript("OnMouseUp")(frame, "LeftButton", true)
                    end,
                }
            else
                target = frame
                self.targets[target] = {send_enter_leave = true}
            end
            if not rows[y] then
                rows[y] = {}
                tinsert(row_y, y)
            end
            tinsert(rows[y], {x, target})
        end
    end
    table.sort(row_y, function(a,b) return a > b end)
    local top_row = rows[row_y[1]]
    local bottom_row = rows[row_y[#row_y]]
    local n_columns = #top_row
    for _, row in pairs(rows) do
        assert(#row == n_columns)
        table.sort(row, function(a,b) return a[1] < b[1] end)
        local left = row[1][2]
        local right = row[n_columns][2]
        self.targets[left].left = right
        self.targets[right].right = left
    end
    local first = top_row[1][2]
    local bottom = bottom_row[1][2]
    self.targets[first].is_default = true
    if can_claim then
        local cf = WeeklyRewardsFrame.ConcessionFrame
        self.targets[cf] = {
            -- This is a bit awkward/hackish because the OnEnter/OnLeave
            -- handlers are attached to ConcessionFrame, but instead of
            -- just toggling the tooltip on and off, they set up an
            -- OnUpdate script which explicitly checks whether the mouse
            -- cursor is over RewardsFrame.
            on_enter = function()
                assert(self.CFRewardsFrame_IsMouseOver == nil)
                assert(cf.RewardsFrame.IsMouseOver)
                self.CFRewardsFrame_IsMouseOver = cf.RewardsFrame.IsMouseOver
                cf.RewardsFrame.IsMouseOver = function() return true end
                cf:GetScript("OnEnter")(cf)
            end,
            on_leave = function()
                assert(self.CFRewardsFrame_IsMouseOver)
                cf:GetScript("OnLeave")(cf)
                cf.RewardsFrame.IsMouseOver = self.CFRewardsFrame_IsMouseOver
                self.CFRewardsFrame_IsMouseOver = nil
            end,
            on_click = function()
                cf:GetScript("OnMouseDown")(cf)
            end,
            left = false, right = false, up = bottom}
        self.targets[WeeklyRewardsFrame.SelectRewardButton] = {
            can_activate = true, lock_highlight = true,
            left = false, right = false, down = first}
        for _, activity in ipairs(top_row) do
            local target = activity[2]
            self.targets[target].up = WeeklyRewardsFrame.SelectRewardButton
        end
    else
        for i = 1, n_columns do
            local top = top_row[i][2]
            local bottom = bottom_row[i][2]
            self.targets[top].up = bottom
            self.targets[bottom].down = top
        end
    end
end


-------- Delve companion setup frame

local DelvesCompanionConfigurationFrameHandler = class(CoreMenuFrame)
local DelvesCompanionConfigurationSlotHandler = class(CoreMenuFrame)
local DelvesCompanionAbilityListFrameHandler = class(CoreMenuFrame)
MenuCursor.RegisterFrameHandler(DelvesCompanionConfigurationFrameHandler)

function DelvesCompanionConfigurationFrameHandler.Initialize(class, cursor)
    CoreMenuFrame.Initialize(class, cursor)
    class.instance_slot = {}
    local dccf = DelvesCompanionConfigurationFrame
    local lists = {dccf.CompanionCombatRoleSlot.OptionsList,
                   dccf.CompanionCombatTrinketSlot.OptionsList,
                   dccf.CompanionUtilityTrinketSlot.OptionsList}
    for _, list in ipairs(lists) do
        class.instance_slot[list] =
            DelvesCompanionConfigurationSlotHandler(list)
    end
    class.instance_abilist = DelvesCompanionAbilityListFrameHandler()
end

function DelvesCompanionConfigurationFrameHandler:__constructor()
    local dccf = DelvesCompanionConfigurationFrame
    self:__super(dccf)
    local function ClickSlot(frame)
        frame:OnMouseDown("LeftButton", true)
    end
    self.targets = {
        -- Mouse behavior brings up the tooltip when mousing over the
        -- portrait rather than the experience ring; we take the
        -- level indicator to be the more natural gamepad movement target,
        -- so we have to manually trigger the portrait enter/leave events.
        [dccf.CompanionLevelFrame] = {
            on_enter = function()
                local portrait = dccf.CompanionPortraitFrame
                portrait:GetScript("OnEnter")(portrait)
            end,
            on_leave = function()
                local portrait = dccf.CompanionPortraitFrame
                portrait:GetScript("OnLeave")(portrait)
            end,
            up = dccf.CompanionConfigShowAbilitiesButton,
            down = dccf.CompanionCombatRoleSlot,
            left = false, right = false},
        [dccf.CompanionCombatRoleSlot] = {
            on_click = ClickSlot, send_enter_leave = true, is_default = true,
            left = false, right = false},
        [dccf.CompanionCombatTrinketSlot] = {
            on_click = ClickSlot, send_enter_leave = true,
            left = false, right = false},
        [dccf.CompanionUtilityTrinketSlot] = {
            on_click = ClickSlot, send_enter_leave = true,
            left = false, right = false},
        [dccf.CompanionConfigShowAbilitiesButton] = {
            can_activate = true, lock_highlight = true,
            up = dccf.CompanionUtilityTrinketSlot,
            down = dccf.CompanionLevelFrame,
            left = false, right = false},
    }
end

function DelvesCompanionConfigurationSlotHandler:__constructor(frame)
    self:__super(frame)
    self.cancel_func = function() frame:Hide() end
end

function DelvesCompanionAbilityListFrameHandler:__constructor()
    self:__super(DelvesCompanionAbilityListFrame)
    self.cancel_func = MenuFrame.HideUIFrame
end

function DelvesCompanionAbilityListFrameHandler:OnShow()
    assert(DelvesCompanionAbilityListFrame:IsShown())
    self.targets = {}
    global_cursor:AddFrame(self)
    self:RefreshTargets()
end

function DelvesCompanionConfigurationSlotHandler:SetTargets(frame)
    local frame = self.frame
    local slot = frame:GetParent()
    self.targets = {}
    -- FIXME: rewrite with new algorithm in GossipFrame
    local subframes = {frame.ScrollBox.ScrollTarget:GetChildren()}
    local top, default
    local active_id = slot:HasActiveEntry() and slot.selectionNodeInfo.activeEntry.entryID
    for index, f in ipairs(subframes) do
        if f.GetElementData then
            local data = f:GetElementData()
            self.targets[f] = {can_activate = true, lock_highlight = true,
                               send_enter_leave = true}
            if not top or f:GetTop() > top:GetTop()then
                top = f
            end
            if active_id and data.entryID == active_id then
                default = f
            end
        end
    end
    local target = default or top
    if target then
        self.targets[target].is_default = true
    end
end

local cache_DelvesCompanionRoleDropdown = {}
function DelvesCompanionAbilityListFrameHandler:ToggleRoleDropdown()
    local dcalf = DelvesCompanionAbilityListFrame
    local role_dropdown = dcalf.DelvesCompanionRoleDropdown
    role_dropdown:SetMenuOpen(not role_dropdown:IsMenuOpen())
    if role_dropdown:IsMenuOpen() then
        local menu, initial_target = MenuFrame.SetupDropdownMenu(
            role_dropdown, cache_DelvesCompanionRoleDropdown,
            function(selection)
                if selection.data and selection.data.entryID == 123306 then
                    return 2  -- DPS
                else
                    return 1  -- Healer
                end
            end,
            function() self:RefreshTargets() end)
        global_cursor:AddFrame(menu, initial_target)
    end
end

function DelvesCompanionAbilityListFrameHandler:RefreshTargets()
    local dcalf = DelvesCompanionAbilityListFrame
    self.targets = {
        [dcalf.DelvesCompanionRoleDropdown] = {
            on_click = function() self:ToggleRoleDropdown() end,
            send_enter_leave = true,
            up = false, down = false, left = false, right = false},
    }
    -- Same logic as in DelvesCompanionAbilityListFrameMixin:UpdatePaginatedButtonDisplay()
    local MAX_DISPLAYED_BUTTONS = 12
    local start_index = ((dcalf.DelvesCompanionAbilityListPagingControls.currentPage - 1) * MAX_DISPLAYED_BUTTONS) + 1
    local count = 0
    local first, last1, last2, prev
    for i = start_index, #dcalf.buttons do
        if count >= MAX_DISPLAYED_BUTTONS then break end
        local button = dcalf.buttons[i]
        if button then
            self.targets[button] = {send_enter_leave = true, left = prev}
            if prev then
                self.targets[prev].right = button
            end
            first = first or button
            if last1 and button:GetTop() == last1:GetTop() then
                last2 = button
            else
                last1, last2 = button, nil
            end
            prev = button
        end
    end
    self.targets[dcalf.DelvesCompanionRoleDropdown].down = first
    self.targets[dcalf.DelvesCompanionRoleDropdown].up = last1
    self.targets[last1].down = dcalf.DelvesCompanionRoleDropdown
    if last2 then
        self.targets[last2].down = dcalf.DelvesCompanionRoleDropdown
    end
    self.targets[first].left = last2 or last1
    self.targets[last2 or last1].right = first
    global_cursor:SetTargetForFrame(self, first)
end


-------- Delve start frame

local cache_DelvesDifficultyDropdown = {}

local DelvesDifficultyPickerFrameHandler = class(AddOnMenuFrame)
DelvesDifficultyPickerFrameHandler.ADDON_NAME = "Blizzard_DelvesDifficultyPicker"
MenuCursor.RegisterFrameHandler(DelvesDifficultyPickerFrameHandler)

function DelvesDifficultyPickerFrameHandler:__constructor()
    self:__super(DelvesDifficultyPickerFrame)
end

function DelvesDifficultyPickerFrameHandler:OnShow()
    assert(DelvesDifficultyPickerFrame:IsShown())
    self.targets = {}
    global_cursor:AddFrame(self)
    self:RefreshTargets()
end

local cache_DelvesDifficultyDropdown = {}
function DelvesDifficultyPickerFrameHandler:ToggleDropdown()
    local ddpf = DelvesDifficultyPickerFrame
    local dropdown = ddpf.Dropdown

    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local menu, initial_target = MenuFrame.SetupDropdownMenu(
            dropdown, cache_DelvesDifficultyDropdown,
            function(selection)
                return selection.data and selection.data.orderIndex + 1
            end,
            function () self:RefreshTargets() end)
        global_cursor:AddFrame(menu, initial_target)
    end
end

function DelvesDifficultyPickerFrameHandler:RefreshTargets()
    local ddpf = DelvesDifficultyPickerFrame
    local Dropdown = ddpf.Dropdown
    local EnterDelveButton = ddpf.EnterDelveButton

    self.targets = {
        [Dropdown] = {
            on_click = function() self:ToggleDropdown() end,
            send_enter_leave = true,
            left = false, right = false, up = EnterDelveButton},
        [EnterDelveButton] = {
            can_activate = true, send_enter_leave = true,
            left = false, right = false, down = Dropdown},
    }

    local rewards = {ddpf.DelveRewardsContainerFrame:GetChildren()}
    if ddpf.DelveRewardsContainerFrame:IsShown() and rewards and #rewards>0 then
        local first_reward, last_reward
        for _, f in ipairs(rewards) do
            if f:IsVisible() then
                self.targets[f] = {send_enter_leave = true, right = false}
                if not first_reward or f:GetTop() > first_reward:GetTop() then
                    first_reward = f
                end
                if not last_reward or f:GetTop() < last_reward:GetTop() then
                    last_reward = f
                end
            end
        end
        self.targets[Dropdown].right = first_reward
        self.targets[EnterDelveButton].right = last_reward
    else
        -- Either no difficulty selected or rewards have not been loaded yet.
        local function TryRewards()
            local rewards = {ddpf.DelveRewardsContainerFrame:GetChildren()}
            if ddpf.DelveRewardsContainerFrame:IsShown() and rewards and #rewards>0 then
                self:RefreshTargets()
            else
                RunNextFrame(TryRewards)
            end
        end
        RunNextFrame(TryRewards)
    end

    local dmwc = ddpf.DelveModifiersWidgetContainer
    if dmwc:IsShown() then
        MenuFrame.AddWidgetTargets(dmwc, {"Spell"}, self.targets,
                                   Dropdown, EnterDelveButton, false, nil)
    end

    if not initial_target then
        initial_target = (EnterDelveButton:IsEnabled() and EnterDelveButton
                          or Dropdown)
    end
    global_cursor:SetTargetForFrame(self, initial_target)
end


-------- Void storage purchase popup

local VoidStoragePurchaseFrameHandler = class(AddOnMenuFrame)
VoidStoragePurchaseFrameHandler.ADDON_NAME = "Blizzard_VoidStorageUI"
MenuCursor.RegisterFrameHandler(VoidStoragePurchaseFrameHandler)

function VoidStoragePurchaseFrameHandler:__constructor()
    self:__super(VoidStoragePurchaseFrame)
    self.cancel_func = function() HideUIPanel(VoidStorageFrame) end
    self.targets = {
        [VoidStoragePurchaseButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            up = false, down = false, left = false, right = false},
    }
end


-------- Pet battle UI

local PetBattleFrameHandler = class(MenuFrame)
local PetBattlePetSelectionFrameHandler = class(MenuFrame)
MenuCursor.RegisterFrameHandler(PetBattleFrameHandler)

function PetBattleFrameHandler.Initialize(class, cursor)
    class.instance = class()
    class.instance_PetSelection = PetBattlePetSelectionFrameHandler()
    -- If we're in the middle of a pet battle, these might already be active!
    if PetBattleFrame:IsVisible() then
        class.instance:OnShow()
    end
    if PetBattleFrame.BottomFrame.PetSelectionFrame:IsVisible() then
        class.instance_PetSelection:OnShow()
    end
end

function PetBattleFrameHandler:__constructor()
    self:__super(PetBattleFrame)
    self:HookShow(PetBattleFrame)
    self:RegisterEvent(global_cursor, "PET_BATTLE_PET_CHANGED")
    self:RegisterEvent(global_cursor, "PET_BATTLE_ACTION_SELECTED")
    self:RegisterEvent(global_cursor, "PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
    self.cancel_func = function()
        global_cursor:SetTargetForFrame(
            self, PetBattleFrame.BottomFrame.ForfeitButton)
    end
end

function PetBattlePetSelectionFrameHandler:__constructor()
    local psf = PetBattleFrame.BottomFrame.PetSelectionFrame
    self:__super(psf)
    self:HookShow(psf)
    self.cancel_func = nil
    self.targets = {
        [psf.Pet1] = {can_activate = true, send_enter_leave = true},
        [psf.Pet2] = {can_activate = true, send_enter_leave = true},
        [psf.Pet3] = {can_activate = true, send_enter_leave = true},
    }
end

function PetBattleFrameHandler:OnShow()
    -- Don't activate input focus unless a battle is already in progress
    -- (i.e. we just reloaded the UI).
    if C_PetBattles.GetBattleState() == Enum.PetbattleState.WaitingForFrontPets then
        -- In this case, the pet battle UI (specifically the action buttons)
        -- won't be set up until later this frame, so wait a frame before
        -- setting input focus.
        RunNextFrame(function()
            local initial_target = self:RefreshTargets(nil)
            global_cursor:AddFrame(self, initial_target)
        end)
    end
end

function PetBattleFrameHandler:OnHide()
    global_cursor:RemoveFrame(self)
end

function PetBattlePetSelectionFrameHandler:OnShow()
    local psf = PetBattleFrame.BottomFrame.PetSelectionFrame
    local initial_target
    if C_PetBattles.CanPetSwapIn(1) then
        initial_target = psf.Pet1
    elseif C_PetBattles.CanPetSwapIn(2) then
        initial_target = psf.Pet2
    else  -- Should never get here.
        initial_target = psf.Pet3
    end
    global_cursor:AddFrame(self, initial_target, true)  -- modal
end

function PetBattlePetSelectionFrameHandler:OnHide()
    global_cursor:RemoveFrame(self)
end

function PetBattleFrameHandler:PET_BATTLE_PET_CHANGED()
    if not self.frame:IsShown() then return end
    local target = self:RefreshTargets(nil)
    global_cursor:SetTargetForFrame(self, target)
end

function PetBattleFrameHandler:PET_BATTLE_ACTION_SELECTED()
    if not self.frame:IsShown() then return end
    self.last_target = global_cursor:GetTargetForFrame(self)
    global_cursor:RemoveFrame(self)
end

function PetBattleFrameHandler:PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE()
    if not self.frame:IsShown() then return end
    -- If the previous round ended with an enemy pet death, the player
    -- already has menu control, so don't move the cursor back to its
    -- previous position.
    local last_target = (global_cursor:GetTargetForFrame(self)
                         or self.last_target)
    local target = self:RefreshTargets(last_target)
    global_cursor:AddFrame(self, target)
end

function PetBattleFrameHandler:RefreshTargets(initial_target)
    local bf = PetBattleFrame.BottomFrame

    local button1 = bf.abilityButtons[1]
    local button2 = bf.abilityButtons[2]
    local button3 = bf.abilityButtons[3]
    local button4 = bf.SwitchPetButton
    local button5 = bf.CatchButton
    local button6 = bf.ForfeitButton
    local button_pass = bf.TurnTimer.SkipButton
    if button1 and not button1:IsVisible() then print("foo") button1 = nil end
    if button2 and not button2:IsVisible() then button2 = nil end
    if button3 and not button3:IsVisible() then button3 = nil end

    local first_action = button1 or button2 or button3 or button4
    local last_action = button3 or button2 or button1 or button6
    self.targets = {
        [button4] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = last_action, right = button5},
        [button5] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button4, right = button6},
        [button6] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button5, right = first_action},
        [button_pass] = {
            can_activate = true, lock_highlight = true,
            up = first_action, down = first_action,
            left = false, right = false},
    }
    if button1 then
        self.targets[button1] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button6, right = button2 or button3 or button4}
    end
    if button2 then
        self.targets[button2] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button1 or button6, right = button3 or button4}
    end
    if button3 then
        self.targets[button3] = {
            can_activate = true, lock_highlight = true, send_enter_leave = true,
            up = button_pass, down = button_pass,
            left = button2 or button1 or button6, right = button4}
    end

    if self.targets[initial_target] then
        return initial_target
    else
        return first_action
    end
end
