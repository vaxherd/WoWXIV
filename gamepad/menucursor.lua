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

    for _,handler in pairs(MenuCursor.handlers) do
        handler(self)
    end

    local texture = f:CreateTexture(nil, "ARTWORK")
    self.texture = texture
    texture:SetAllPoints()
    texture:SetTexture("Interface/CURSOR/Point")  -- Default mouse cursor image
    -- Flip it horizontally to distinguish it from the mouse cursor.
    texture:SetTexCoord(1, 0, 0, 1)
end

-- {Register,Unregister}Event() wrappers so frame handlers don't need to
-- peek at the actual cursor frame.
function MenuCursor:RegisterEvent(...)
    self.cursor:RegisterEvent(...)
end
function MenuCursor:UnregisterEvent(...)
    self.cursor:UnregisterEvent(...)
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
    --         MenuCursor:PseudoFrameForScrollElement().
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
-- Utility methods
------------------------------------------------------------------------

-- Hook a frame's Show/Hide/SetShown methods, calling OnEvent() with tne
-- given event name suffixed by either "_Show" or "_Hide" as appropriate.
-- The frame itself is passed as an argument to the event, for use when
-- handling multiple related frames with a single event (like StaticPopups).
function MenuCursor:HookShow(frame, event)
    hooksecurefunc(frame, "Show", function()
        self:OnEvent(event.."_Show", frame)
    end)
    hooksecurefunc(frame, "Hide", function()
        self:OnEvent(event.."_Hide", frame)
    end)
    hooksecurefunc(frame, "SetShown", function(_, shown)
        local suffix = shown and "_Show" or "_Hide"
        self:OnEvent(event..suffix, frame)
    end)
end

-- Generic cancel_func to close a frame.
local function CancelFrame(frame)
    global_cursor:RemoveFrame(frame)
    frame:GetFrame():Hide()
end

-- Generic cancel_func to close a UI frame.  Equivalent to CancelFrame()
-- but with calling HideUIPanel(focus) instead of focus:Hide().
local function CancelUIFrame(frame)
    global_cursor:RemoveFrame(frame)
    HideUIPanel(frame:GetFrame())
end

-- Generic cancel_func to close a UI frame, when a callback has already
-- been established on the frame's Hide() method to clear the frame focus.
local function HideUIFrame(frame)
    HideUIPanel(frame:GetFrame())
end

-- Shared cancel_func used for quest frames.
local function CancelQuestFrame(frame)
    global_cursor:RemoveFrame(frame)
    CloseQuest()
end

-- Shared on_leave handler which simply hides the tooltip.
local function HideTooltip()
    if not GameTooltip:IsForbidden() then
        GameTooltip:Hide()
    end
end

-- on_click handler for NumericInputSpinnerTemplate increment/decrement
-- buttons, which use an OnMouseDown/Up event pair instead of OnClick.
local function ClickNumericSpinnerButton(frame)
    frame:GetScript("OnMouseDown")(frame, "LeftButton", true)
    frame:GetScript("OnMouseUp")(frame, "LeftButton")
end

-- Return a table suitable for use as a targets[] key for an element of
-- a ScrollBox data list or tree.  Pass the ScrollBox frame and the
-- data index of the element.
local function PseudoFrameForScrollElement(box, index)
    return {box = box, index = index}
end

-- Add widgets in the given WidgetContainer whose type is one of the
-- given types (supported: "Spell", "Bar") to the given target list.
-- |{up,down,left,right}_target| give the targets immediately in each
-- direction relative to the widget container, and can be nil for default
-- movement rules.
local function AddWidgetTargets(container, widget_types,
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
function GetDropdownSelection(dropdown)
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
function SetupDropdownMenu(dropdown, cache, getIndex, onClick)
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
    local selection = GetDropdownSelection(dropdown)
    local index = selection and getIndex(selection)
    local initial_target = index and menu_menu.item_order[index]
    return menu_menu, initial_target
end

------------------------------------------------------------------------
-- Individual frame handlers
------------------------------------------------------------------------

-- All functions defined in this table will be called from the MenuCursor
-- constructor (key value is irrelevant).
MenuCursor.handlers = {}

-------- Gossip (NPC dialogue) frame

local menu_GossipFrame = MenuFrame(GossipFrame)

local function GossipFrame_OnShow()
    local self = menu_GossipFrame
    self.cancel_func = CancelUIFrame
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
                    PseudoFrameForScrollElement(GossipScroll, index)
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

function GossipFrame_OnConfirmCancel()
    local self = menu_GossipFrame
    -- Clear all targets to prevent further inputs until the next event
    -- (typically GOSSIP_SHOW or GOSSIP_CLOSED).
    global_cursor:SetTargetForFrame(self, nil)
    self.targets = {}
end

function MenuCursor.handlers.GossipFrame(cursor)
    cursor:RegisterEvent("GOSSIP_CLOSED")
    cursor:RegisterEvent("GOSSIP_CONFIRM_CANCEL")
    cursor:RegisterEvent("GOSSIP_SHOW")
end

function MenuCursor:GOSSIP_SHOW()
    if not GossipFrame:IsVisible() then
        return  -- Flight map, etc.
    end
    local initial_target = GossipFrame_OnShow(menu_GossipFrame)
    self:AddFrame(menu_GossipFrame, initial_target)
end

function MenuCursor:GOSSIP_CONFIRM_CANCEL()
    GossipFrame_OnConfirmCancel()
end

function MenuCursor:GOSSIP_CLOSED()
    self:RemoveFrame(menu_GossipFrame)
end


-------- Quest info frame

local menu_QuestFrame = MenuFrame(QuestFrame)

local function QuestFrame_OnShow(event)
    local self = menu_QuestFrame
    self.cancel_func = CancelQuestFrame

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

function MenuCursor.handlers.QuestFrame(cursor)
    cursor:RegisterEvent("QUEST_COMPLETE")
    cursor:RegisterEvent("QUEST_DETAIL")
    cursor:RegisterEvent("QUEST_FINISHED")
    cursor:RegisterEvent("QUEST_GREETING")
    cursor:RegisterEvent("QUEST_PROGRESS")
end

function MenuCursor:QUEST_GREETING()
    assert(QuestFrame:IsVisible())  -- FIXME: might be false if previous quest turn-in started a cutscene (e.g. The Underking Comes in the Legion Highmountain scenario)
    QuestFrame_OnShow("QUEST_GREETING")
    self:AddFrame(menu_QuestFrame)
end

function MenuCursor:QUEST_DETAIL()
    -- FIXME: some map-based quests (e.g. Blue Dragonflight campaign)
    -- start a quest directly from the map; we should support those too
    if not QuestFrame:IsVisible() then return end
    QuestFrame_OnShow("QUEST_DETAIL")
    self:AddFrame(menu_QuestFrame)
end

function MenuCursor:QUEST_PROGRESS()
    assert(QuestFrame:IsVisible())
    QuestFrame_OnShow("QUEST_PROGRESS")
    self:AddFrame(menu_QuestFrame)
end

function MenuCursor:QUEST_COMPLETE()
    -- Quest frame can fail to open under some conditions?
    if not QuestFrame:IsVisible() then return end
    QuestFrame_OnShow("QUEST_COMPLETE")
    self:AddFrame(menu_QuestFrame)
end

function MenuCursor:QUEST_FINISHED()
    self:RemoveFrame(menu_QuestFrame)
end


-------- Legion/BfA troop recruitment frame

local menu_TroopRecruitmentFrame

local function TroopRecruitmentFrame_OnShow()
    local self = menu_TroopRecruitmentFrame
    self.cancel_func = CancelUIFrame
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

function MenuCursor.handlers.TroopRecruitmentFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if GarrisonCapacitiveDisplayFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_GarrisonUI")
    end
    -- We need to add these early because it seems that if we add them
    -- during the ADDON_LOADED event, we don't see the OPENED event which
    -- is sent in the same frame (possibly because the addon was loaded in
    -- an OPENED handler, so the event had technically already been sent).
    cursor:RegisterEvent("SHIPMENT_CRAFTER_CLOSED")
    cursor:RegisterEvent("SHIPMENT_CRAFTER_OPENED")
end

function MenuCursor:ADDON_LOADED__Blizzard_GarrisonUI()
    menu_TroopRecruitmentFrame = MenuFrame(GarrisonCapacitiveDisplayFrame)
    if GarrisonCapacitiveDisplayFrame:IsVisible() then
        self:SHIPMENT_CRAFTER_OPENED()
    end
end

function MenuCursor:SHIPMENT_CRAFTER_OPENED()
    assert(menu_TroopRecruitmentFrame)  -- See note in startup handler.
    assert(GarrisonCapacitiveDisplayFrame:IsVisible())
    TroopRecruitmentFrame_OnShow()
    self:AddFrame(menu_TroopRecruitmentFrame)
end

function MenuCursor:SHIPMENT_CRAFTER_CLOSED()
    self:RemoveFrame(menu_TroopRecruitmentFrame)
end


-------- Shadowlands covenant sanctum frame

local menu_CovenantSanctumFrame

local function CovenantSanctumFrame_ChooseTalent(upgrade_button)
    local self = menu_CovenantSanctumFrame
    upgrade_button:OnMouseDown()
    local talent_menu = MenuFrame(CovenantSanctumFrame)
    talent_menu.cancel_func = function(self) global_cursor:RemoveFrame(self) end
    talent_menu.targets = {
        [CovenantSanctumFrame.UpgradesTab.TalentsList.UpgradeButton] =
            {can_activate = true, lock_highlight = true,
             is_default = true},
    }
    for frame in CovenantSanctumFrame.UpgradesTab.TalentsList.talentPool:EnumerateActive() do
        talent_menu.targets[frame] = {send_enter_leave = true}
    end
    global_cursor:AddFrame(talent_menu)
end

local function CovenantSanctumFrame_OnShow()
    local self = menu_CovenantSanctumFrame
    self.cancel_func = CancelUIFrame
    self.targets = {
        [CovenantSanctumFrame.UpgradesTab.TravelUpgrade] =
            {send_enter_leave = true,
             on_click = CovenantSanctumFrame_ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.DiversionUpgrade] =
            {send_enter_leave = true,
             on_click = CovenantSanctumFrame_ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.AdventureUpgrade] =
            {send_enter_leave = true,
             on_click = CovenantSanctumFrame_ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.UniqueUpgrade] =
            {send_enter_leave = true,
             on_click = CovenantSanctumFrame_ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.DepositButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, is_default = true},
    }
end

function MenuCursor.handlers.CovenantSanctumFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if CovenantSanctumFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_CovenantSanctum")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_CovenantSanctum()
    menu_CovenantSanctumFrame = MenuFrame(CovenantSanctumFrame)
    self:HookShow(CovenantSanctumFrame, "CovenantSanctumFrame")
end

function MenuCursor:CovenantSanctumFrame_Show()
    assert(CovenantSanctumFrame:IsVisible())
    CovenantSanctumFrame_OnShow()
    self:AddFrame(menu_CovenantSanctumFrame)
end

function MenuCursor:CovenantSanctumFrame_Hide()
    self:RemoveFrame(menu_CovenantSanctumFrame)
end


-------- Generic player choice frame

local menu_PlayerChoiceFrame

local function PlayerChoiceFrame_OnShow()
    local self = menu_PlayerChoiceFrame

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

    self.cancel_func = CancelUIFrame
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
                self.targets[button].on_leave = HideTooltip
            else
                self.targets[button].send_enter_leave = true
            end
            if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                leftmost = button
            end
            if option.WidgetContainer:IsShown() then
                AddWidgetTargets(option.WidgetContainer, {"Spell","Bar"},
                                 self.targets, button, button, false, false)
            end
        end
    end
    if leftmost then  -- i.e., if we found any buttons
        self.targets[leftmost].is_default = true
    else
        return false
    end
    return true
end

function MenuCursor.handlers.PlayerChoiceFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if PlayerChoiceFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_PlayerChoice")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_PlayerChoice()
    menu_PlayerChoiceFrame = MenuFrame(PlayerChoiceFrame)
    self:HookShow(PlayerChoiceFrame, "PlayerChoiceFrame")
end

function MenuCursor:PlayerChoiceFrame_Show()
    assert(PlayerChoiceFrame:IsVisible())
    if PlayerChoiceFrame_OnShow() then
        self:AddFrame(menu_PlayerChoiceFrame)
    end
end

function MenuCursor:PlayerChoiceFrame_Hide()
    self:RemoveFrame(menu_PlayerChoiceFrame)
end


-------- New content splash frame

local menu_SplashFrame = MenuFrame(SplashFrame)

local function SplashFrame_OnShow()
    local self = menu_SplashFrame
    self.cancel_func = CancelUIFrame
    self.targets = {}
    local StartQuestButton = SplashFrame.RightFeature.StartQuestButton
    if StartQuestButton:IsVisible() then
        self.targets[StartQuestButton] =
            {can_activate = true, send_enter_leave = true, is_default = true}
    end
end

function MenuCursor.handlers.SplashFrame(cursor)
    cursor:HookShow(SplashFrame, "SplashFrame")
end

function MenuCursor:SplashFrame_Show()
    assert(SplashFrame:IsVisible())
    SplashFrame_OnShow()
    self:AddFrame(menu_SplashFrame)
end

function MenuCursor:SplashFrame_Hide()
    self:RemoveFrame(menu_SplashFrame)
end


-------- Info popup frame ("Campaign Complete!" etc.) (FIXME: untested)

local menu_UIWidgetCenterDisplayFrame = MenuFrame(UIWidgetCenterDisplayFrame)

local function UIWidgetCenterDisplayFrame_OnShow()
    local self = menu_UIWidgetCenterDisplayFrame
    self.cancel_func = CancelUIFrame
    self.targets = {
        [UIWidgetCenterDisplayFrame.CloseButton] = {
            can_activate = true, lock_highlight = true, is_default = true},
    }
end

function MenuCursor.handlers.UIWidgetCenterDisplayFrame(cursor)
    cursor:HookShow(UIWidgetCenterDisplayFrame, "UIWidgetCenterDisplayFrame")
end

function MenuCursor:UIWidgetCenterDisplayFrame_Show()
    assert(UIWidgetCenterDisplayFrame:IsVisible())
    UIWidgetCenterDisplayFrame_OnShow()
    self:AddFrame(menu_UIWidgetCenterDisplayFrame)
end

function MenuCursor:UIWidgetCenterDisplayFrame_Hide()
    self:RemoveFrame(menu_UIWidgetCenterDisplayFrame)
end


-------- Static popup dialogs

local menu_StaticPopup = {}

local function StaticPopup_OnShow(self)
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
end

function MenuCursor.handlers.StaticPopup(cursor)
    for i = 1, STATICPOPUP_NUMDIALOGS do
        local frame_name = "StaticPopup" .. i
        local frame = _G[frame_name]
        assert(frame)
        menu_StaticPopup[frame] = MenuFrame(frame)
        cursor:HookShow(frame, "StaticPopup")
    end
end

function MenuCursor:StaticPopup_Show(frame)
    if self.focus == frame then return end  -- Sanity check
    local menu_frame = menu_StaticPopup[frame]
    assert(menu_frame)
    StaticPopup_OnShow(menu_frame)
    self:AddFrame(menu_frame, nil, true)  -- Modal frame.
end

function MenuCursor:StaticPopup_Hide(frame)
    local menu_frame = menu_StaticPopup[frame]
    assert(menu_frame)
    self:RemoveFrame(menu_frame)
end


-------- Mail inbox

local menu_InboxFrame = MenuFrame(InboxFrame)
local menu_OpenMailFrame = MenuFrame(OpenMailFrame)

local function InboxFrame_UpdateMovement()
    local self = menu_InboxFrame
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

local function InboxFrame_OnShow()
    local self = menu_InboxFrame
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
            global_cursor:MailItemButton_Show(button)
        end
    end
    InboxFrame_UpdateMovement()
end

local function OpenMailFrame_OnShow()
    local self = menu_OpenMailFrame
    self.cancel_button = OpenMailCancelButton
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
    for i = 1, 16 do
        local button = _G["OpenMailAttachmentButton"..i]
        assert(button)
        if button:IsShown() then
            global_cursor:OpenMailAttachmentButton_Show(button)
            if not first_attachment then first_attachment = button end
        end
    end
    if OpenMailMoneyButton:IsShown() then
        global_cursor:OpenMailMoneyButton_Show(OpenMailMoneyButton)
        if not first_attachment then first_attachment = OpenMailMoneyButton end
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

function MenuCursor.handlers.InboxFrame(cursor)
    -- We could react to PLAYER_INTERACTION_MANAGER_FRAME_{SHOW,HIDE}
    -- with arg1 == Enum.PlayerInteractionType.MailInfo (17) for mailbox
    -- handling, but we don't currently have any support for the send UI,
    -- so we isolate our handling to the inbox frame.
    cursor:HookShow(InboxFrame, "InboxFrame")
    for i = 1, 7 do
        local frame_name = "MailItem" .. i .. "Button"
        local frame = _G[frame_name]
        assert(frame)
        cursor:HookShow(frame, "MailItemButton")
    end
    cursor:HookShow(OpenMailFrame, "OpenMailFrame")
    for i = 1, 16 do
        local frame_name = "OpenMailAttachmentButton" .. i
        local frame = _G[frame_name]
        assert(frame)
        cursor:HookShow(frame, "OpenMailAttachmentButton")
    end
    cursor:HookShow(OpenMailMoneyButton, "OpenMailMoneyButton")
end

function MenuCursor:InboxFrame_Show()
    assert(InboxFrame:IsShown())
    InboxFrame_OnShow()
    self:AddFrame(menu_InboxFrame)
end

function MenuCursor:InboxFrame_Hide()
    self:RemoveFrame(menu_InboxFrame)
end

function MenuCursor:MailItemButton_Show(frame)
    menu_InboxFrame.targets[frame] = {
        can_activate = true, lock_highlight = true,
        send_enter_leave = true},
    InboxFrame_UpdateMovement()
end

function MenuCursor:MailItemButton_Hide(frame)
    local focus, target = self:GetFocusAndTarget()
    if focus == menu_InboxFrame and target == frame then
        self:Move(0, -1, "down")
    end
    menu_InboxFrame.targets[frame] = nil
    InboxFrame_UpdateMovement()
end

function MenuCursor:OpenMailFrame_Show()
    assert(OpenMailFrame:IsShown())
    local initial_target = OpenMailFrame_OnShow()
    self:AddFrame(menu_OpenMailFrame, initial_target)
end

function MenuCursor:OpenMailFrame_Hide()
    -- Note that this event appears to fire sporadically even when the
    -- frame isn't shown in the first place.  RemoveFrame() ignores frames
    -- not in the focus list so this isn't a problem for us.
    self:RemoveFrame(menu_OpenMailFrame)
end

function MenuCursor:OpenMailAttachmentButton_Show(frame)
    menu_OpenMailFrame.targets[frame] = {
        can_activate = true, lock_highlight = true,
        send_enter_leave = true}
end

function MenuCursor:OpenMailAttachmentButton_Hide(frame)
    local focus, target = self:GetFocusAndTarget()
    if focus == menu_OpenMailFrame and target == frame then
        local new_target = nil
        local id = frame:GetID() - 1
        while id >= 1 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id - 1
        end
        id = frame:GetID() + 1
        while id <= 16 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id + 1
        end
        if not new_target and OpenMailMoneyButton:IsShown() then
            new_target = OpenMailMoneyButton
        end
        self:SetTarget(new_target or OpenMailDeleteButton)
    end
    menu_OpenMailFrame.targets[frame] = nil
end

function MenuCursor:OpenMailMoneyButton_Show(frame)
    menu_OpenMailFrame.targets[frame] = {
        can_activate = true, lock_highlight = true,
        on_enter = function(frame)  -- hardcoded in XML
            if OpenMailFrame.money then
                GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                SetTooltipMoney(GameTooltip, OpenMailFrame.money)
                GameTooltip:Show()
            end
        end,
        on_leave = HideTooltip,
    }
end

function MenuCursor:OpenMailMoneyButton_Hide(frame)
    local focus, target = self:GetFocusAndTarget()
    if focus == menu_OpenMailFrame and target == frame then
        local new_target = nil
        local id = 16
        while id >= 1 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id - 1
        end
        self:SetTarget(new_target or OpenMailDeleteButton)
    end
    menu_OpenMailFrame.targets[frame] = nil
end


-------- Shop menu

local menu_MerchantFrame = MenuFrame(MerchantFrame)

local function MerchantFrame_UpdateTargets()
    local self = menu_MerchantFrame
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
            global_cursor:MerchantItemButton_Show(button, true)
            if not initial then
                initial = button
            end
        end
    end
end

local function MerchantFrame_UpdateMovement()
    local self = menu_MerchantFrame
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

local function MerchantFrame_OnShow()
    local self = menu_MerchantFrame
    self.cancel_func = CancelUIFrame
    self.prev_page_button = "MerchantPrevPageButton"
    self.next_page_button = "MerchantNextPageButton"
    MerchantFrame_UpdateTargets()
    MerchantFrame_UpdateMovement()
    if self.targets[MerchantItem1ItemButton] then
        return MerchantItem1ItemButton
    else
        return MerchantSellAllJunkButton
    end
end

function MenuCursor.handlers.MerchantFrame(cursor)
    cursor:HookShow(MerchantFrame, "MerchantFrame")
    -- We use the "sell all junk" button (which is always displayed on the
    -- "buy" tab and never displayed on the "sell" tab) as a proxy for tab
    -- change detection.
    cursor:HookShow(MerchantSellAllJunkButton, "MerchantSellTab")
    for i = 1, 12 do
        local frame_name = "MerchantItem" .. i .. "ItemButton"
        local frame = _G[frame_name]
        assert(frame)
        cursor:HookShow(frame, "MerchantItemButton")
    end
end

function MenuCursor:MerchantFrame_Show()
    assert(MerchantFrame:IsShown())
    assert(MerchantFrame.selectedTab == 1)
    local initial_target = MerchantFrame_OnShow()
    self:AddFrame(menu_MerchantFrame, initial_target)
end

function MenuCursor:MerchantFrame_Hide()
    self:RemoveFrame(menu_MerchantFrame)
end

function MenuCursor:MerchantSellTab_Show()
    MerchantFrame_UpdateTargets()
    MerchantFrame_UpdateMovement()
end

function MenuCursor:MerchantSellTab_Hide()
    MerchantFrame_UpdateTargets()
    MerchantFrame_UpdateMovement()
end

function MenuCursor:MerchantItemButton_Show(frame, skip_update)
    menu_MerchantFrame.targets[frame] = {
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
        MerchantFrame_UpdateMovement()
    end
end

function MenuCursor:MerchantItemButton_Hide(frame)
    local focus, target = self:GetFocusAndTarget()
    if focus == menu_MerchantFrame and target == frame then
        local prev_id = frame:GetID() - 1
        local prev_frame = _G["MerchantItem" .. prev_id .. "ItemButton"]
        if prev_frame and prev_frame:IsShown() then
            self:SetTarget(prev_frame)
        else
            self:Move(0, -1, "down")
        end
    end
    menu_MerchantFrame.targets[frame] = nil
    if MerchantSellAllJunkButton:IsShown() ~= (MerchantFrame.selectedTab==1) then
        skip_update = true
    end
    if not skip_update then
        MerchantFrame_UpdateMovement()
    end
end


-------- Profession training menu

local menu_ClassTrainerFrame

local function ClassTrainerFrame_OnShow()
    local self = menu_ClassTrainerFrame
    self.cancel_func = CancelUIFrame
    self.targets = {
        [ClassTrainerFrameSkillStepButton] = {
            can_activate = true, lock_highlight = true,
            up = ClassTrainerTrainButton},
        [ClassTrainerTrainButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            down = ClassTrainerFrameSkillStepButton},
    }
    -- FIXME: also allow moving through list (ClassTrainerFrame.ScrollBox)
    -- (this temporary hack selects the first item so that we can still train)
    RunNextFrame(function()
        for _, frame in ClassTrainerFrame.ScrollBox:EnumerateFrames() do
            ClassTrainerSkillButton_OnClick(frame, "LeftButton")
            break
        end
    end)
end

function MenuCursor.handlers.ClassTrainerFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if ClassTrainerFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_TrainerUI")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_TrainerUI()
    menu_ClassTrainerFrame = MenuFrame(ClassTrainerFrame)
    self:HookShow(ClassTrainerFrame, "ClassTrainerFrame")
end

function MenuCursor:ClassTrainerFrame_Show()
    assert(ClassTrainerFrame:IsShown())
    ClassTrainerFrame_OnShow()
    self:AddFrame(menu_ClassTrainerFrame)
end

function MenuCursor:ClassTrainerFrame_Hide()
    self:RemoveFrame(menu_ClassTrainerFrame)
end


-------- Talents/spellbook frame

local menu_SpellBookFrame

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
-- button column.  Helper for SpellBookFrame_RefreshTargets().
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
local function SpellBookFrame_RefreshTargets()
    local self = menu_SpellBookFrame
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

local function SpellBookFrame_OnShow()
    local self = menu_SpellBookFrame
    self.cancel_func = HideUIFrame
    return SpellBookFrame_RefreshTargets()
end

function MenuCursor.handlers.PlayerSpellsFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if PlayerSpellsFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_PlayerSpells()
    menu_SpellBookFrame = MenuFrame(PlayerSpellsFrame.SpellBookFrame)

    -- We hook the individual tabs for show behavior only, but we use the
    -- common utility method for convenience and just make the unused hooks
    -- no-ops.
    self:HookShow(PlayerSpellsFrame.SpellBookFrame, "SpellBookFrame")
    self:HookShow(PlayerSpellsFrame, "PlayerSpellsFrame")
    EventRegistry:RegisterCallback(
        "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged",
        function()
            if PlayerSpellsFrame.SpellBookFrame:IsVisible() then
                self:SetTargetForFrame(menu_SpellBookFrame,
                                       SpellBookFrame_RefreshTargets())
            end
        end);

    local sbf = PlayerSpellsFrame.SpellBookFrame
    local pc = sbf.PagedSpellsFrame.PagingControls
    local buttons = {sbf.HidePassivesCheckButton.Button,
                     pc.PrevPageButton, pc.NextPageButton}
    for _, tab in ipairs(sbf.CategoryTabSystem.tabs) do
        tinsert(buttons, tab)
    end
    for _, button in ipairs(buttons) do
        hooksecurefunc(button, "Click", function() self:SetTargetForFrame(menu_SpellBookFrame, SpellBookFrame_RefreshTargets()) end)
    end
end

function MenuCursor:SpellBookFrame_Hide() end

function MenuCursor:PlayerSpellsFrame_Show()
    if PlayerSpellsFrame.SpellBookFrame:IsShown() then
        self:SpellBookFrame_Show()
    end
end

function MenuCursor:SpellBookFrame_Show()
    if not PlayerSpellsFrame:IsShown() then return end
    local target = SpellBookFrame_OnShow()
    self:AddFrame(menu_SpellBookFrame, target)
end

function MenuCursor:PlayerSpellsFrame_Hide()
    self:RemoveFrame(menu_PlayerSpellsFrame)
end


-------- Professions frame

local menu_ProfessionsBookFrame

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
local function ProfessionsBookFrame_OnShow()
    local self = menu_ProfessionsBookFrame
    self.cancel_func = CancelUIFrame
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

function MenuCursor.handlers.ProfessionsBookFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if ProfessionsBookFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_ProfessionsBook")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_ProfessionsBook()
    menu_ProfessionsBookFrame = MenuFrame(ProfessionsBookFrame)
    self:HookShow(ProfessionsBookFrame, "ProfessionsBookFrame")
end

function MenuCursor:ProfessionsBookFrame_Show()
    assert(ProfessionsBookFrame:IsShown())
    ProfessionsBookFrame_OnShow()
    self:AddFrame(menu_ProfessionsBookFrame)
end

function MenuCursor:ProfessionsBookFrame_Hide()
    self:RemoveFrame(menu_ProfessionsBookFrame)
end


-------- Crafting frame

local menu_ProfessionsFrame
local menu_ProfessionsFrame_SchematicForm
local menu_ProfessionsFrame_QualityDialog
local menu_ProfessionsItemFlyout

local function ProfessionsFrame_SchematicForm_UpdateMovement()
    local self = menu_ProfessionsFrame_SchematicForm

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

local function ProfessionsFrame_SchematicForm_OnShow()
    local self = menu_ProfessionsFrame_SchematicForm
    local CraftingPage = ProfessionsFrame.CraftingPage
    local SchematicForm = CraftingPage.SchematicForm

    self.cancel_func = function(self)
        global_cursor:RemoveFrame(self)
        self.targets = {}  -- suppress update calls from CreateAllButton:Show() hook
    end

    self.targets = {
        [SchematicForm.OutputIcon] = {send_enter_leave = true},
        [CraftingPage.CreateAllButton] = {
            can_activate = true, lock_highlight = true,
            down = SchematicForm.OutputIcon, left = false},
        [CraftingPage.CreateMultipleInputBox.DecrementButton] = {
            on_click = ClickNumericSpinnerButton,
            lock_highlight = true,
            down = SchematicForm.OutputIcon},
        [CraftingPage.CreateMultipleInputBox.IncrementButton] = {
            on_click = ClickNumericSpinnerButton,
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

    ProfessionsFrame_SchematicForm_UpdateMovement()
    return r_top
end

local function ProfessionsFrame_QualityDialog_OnShow()
    local self = menu_ProfessionsFrame_QualityDialog
    local QualityDialog = ProfessionsFrame.CraftingPage.SchematicForm.QualityDialog
    self.cancel_button = QualityDialog.CancelButton
    self.targets = {
        [QualityDialog.Container1.EditBox.DecrementButton] = {
            on_click = ClickNumericSpinnerButton, lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container1.EditBox.IncrementButton] = {
            on_click = ClickNumericSpinnerButton, lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container2.EditBox.DecrementButton] = {
            on_click = ClickNumericSpinnerButton, lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container2.EditBox.IncrementButton] = {
            on_click = ClickNumericSpinnerButton, lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container3.EditBox.DecrementButton] = {
            on_click = ClickNumericSpinnerButton, lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.Container3.EditBox.IncrementButton] = {
            on_click = ClickNumericSpinnerButton, lock_highlight = true,
            up = false, down = QualityDialog.AcceptButton},
        [QualityDialog.AcceptButton] = {
            can_activate = true, lock_highlight = true, is_default = true},
        [QualityDialog.CancelButton] = {
            can_activate = true, lock_highlight = true},
    }
end

local function ProfessionsItemFlyout_RefreshTargets()
    local self = menu_ProfessionsItemFlyout
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
                          RunNextFrame(ProfessionsItemFlyout_RefreshTargets)
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
                    PseudoFrameForScrollElement(ItemScroll, index)
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

local function ProfessionsItemFlyout_OnShow()
    local self = menu_ProfessionsItemFlyout
    self.cancel_func = CloseProfessionsItemFlyout
    self.targets = {}
    -- Call RefreshTargets() after adding the frame.
end

local function ProfessionsFrame_FocusRecipe(tries)
    local self = menu_ProfessionsFrame
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
            RunNextFrame(function() ProfessionsFrame_FocusRecipe(tries-1) end)
        end
        return
    end
    local initial_target = ProfessionsFrame_SchematicForm_OnShow()
    global_cursor:AddFrame(menu_ProfessionsFrame_SchematicForm, initial_target)
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
local function ProfessionsFrame_RefreshTargets(initial_element)
    local self = menu_ProfessionsFrame
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
                    PseudoFrameForScrollElement(RecipeScroll, index)
                self.targets[pseudo_frame] = {
                    is_scroll_box = true, can_activate = true,
                    up = bottom or false, down = false,
                    left = false, right = CraftingPage.LinkButton}
                if data.recipeInfo then
                    self.targets[pseudo_frame].on_click = function()
                        ProfessionsFrame_FocusRecipe()
                    end
                else  -- is a category header
                    self.targets[pseudo_frame].on_click = function()
                        local target = ProfessionsFrame_RefreshTargets(element)
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

local function ProfessionsFrame_OnShow()
    local self = menu_ProfessionsFrame
    self.cancel_func = HideUIFrame
    self.need_refresh = true
    return ProfessionsFrame_RefreshTargets()
end

function MenuCursor.handlers.ProfessionsFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if ProfessionsFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_Professions")
    end
    cursor:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
end

function MenuCursor:ADDON_LOADED__Blizzard_Professions()
    menu_ProfessionsFrame = MenuFrame(ProfessionsFrame)
    self:HookShow(ProfessionsFrame, "ProfessionsFrame")
    self:HookShow(ProfessionsFrame.CraftingPage.CreateAllButton, "ProfessionsFrame_CreateAllButton")

    local SchematicForm = ProfessionsFrame.CraftingPage.SchematicForm
    menu_ProfessionsFrame_SchematicForm = MenuFrame(SchematicForm)

    local QualityDialog = SchematicForm.QualityDialog
    menu_ProfessionsFrame_QualityDialog = MenuFrame(QualityDialog)
    self:HookShow(QualityDialog, "ProfessionsFrame_QualityDialog")

    -- Hack for interacting with the item selector popup.
    local flyout = OpenProfessionsItemFlyout(UIParent, UIParent)
    CloseProfessionsItemFlyout()
    menu_ProfessionsItemFlyout = MenuFrame(flyout)
    self:HookShow(flyout, "ProfessionsItemFlyout")
end

function MenuCursor:TRADE_SKILL_LIST_UPDATE()
    if menu_ProfessionsFrame.need_refresh then
        -- The list itself apparently isn't ready until the next frame.
        RunNextFrame(function()
            global_cursor:SetTargetForFrame(menu_ProfessionsFrame,
                                            ProfessionsFrame_RefreshTargets())
        end)
    end
end

function MenuCursor:ProfessionsFrame_Show()
    assert(ProfessionsFrame:IsShown())
    local initial_target = ProfessionsFrame_OnShow()
    self:AddFrame(menu_ProfessionsFrame, initial_target)
end

function MenuCursor:ProfessionsFrame_Hide()
    self:RemoveFrame(menu_ProfessionsFrame)
    self:RemoveFrame(menu_ProfessionsFrame_SchematicForm)
end

function MenuCursor:ProfessionsFrame_CreateAllButton_Show()
    -- FIXME: this gets called every second, avoid update calls if no change
    if menu_ProfessionsFrame_SchematicForm.targets[ProfessionsFrame.CraftingPage.CreateButton] then
        ProfessionsFrame_SchematicForm_UpdateMovement()
    end
end

function MenuCursor:ProfessionsFrame_CreateAllButton_Hide()
    if menu_ProfessionsFrame_SchematicForm.targets[ProfessionsFrame.CraftingPage.CreateButton] then
        local CraftingPage = ProfessionsFrame.CraftingPage
        local cur_target = self:GetTargetForFrame(menu_ProfessionsFrame_SchematicForm)
        if (cur_target == CraftingPage.CreateAllButton
         or cur_target == CraftingPage.CreateMultipleInputBox.DecrementButton
         or cur_target == CraftingPage.CreateMultipleInputBox.IncrementButton)
        then
            self:SetTargetForFrame(menu_ProfessionsFrame_SchematicForm,
                                   CraftingPage.CreateButton)
        end
        ProfessionsFrame_SchematicForm_UpdateMovement()
    end
end

function MenuCursor:ProfessionsFrame_QualityDialog_Show(frame)
    ProfessionsFrame_QualityDialog_OnShow()
    self:AddFrame(menu_ProfessionsFrame_QualityDialog)
end

function MenuCursor:ProfessionsFrame_QualityDialog_Hide()
    self:RemoveFrame(menu_ProfessionsFrame_QualityDialog)
end

function MenuCursor:ProfessionsItemFlyout_Show()
    ProfessionsItemFlyout_OnShow()
    self:AddFrame(menu_ProfessionsItemFlyout)
    RunNextFrame(ProfessionsItemFlyout_RefreshTargets)
end

function MenuCursor:ProfessionsItemFlyout_Hide(frame)
    self:RemoveFrame(menu_ProfessionsItemFlyout)
end


-------- Great Vault

local menu_WeeklyRewardsFrame

local function WeeklyRewardsFrame_OnShow()
    local self = menu_WeeklyRewardsFrame
    self.cancel_func = CancelUIFrame
    self.targets = {}
    local first, bottom
    local can_claim = C_WeeklyRewards.CanClaimRewards()
    for _, info in ipairs(C_WeeklyRewards.GetActivities()) do
        local frame = WeeklyRewardsFrame:GetActivityFrame(info.type, info.index)
        if frame and frame ~= WeeklyRewardsFrame.ConcessionFrame then
            local unlocked = can_claim and #info.rewards > 0
            self.targets[frame] = {send_enter_leave = true}
            if unlocked then
                self.targets[frame].on_click = function()
                    frame:GetScript("OnMouseUp")(frame, "LeftButton", true)
                end
            end
            if not first or frame:GetTop() > first:GetTop()
                         or (frame:GetTop() == first:GetTop()
                             and frame:GetLeft() < first:GetLeft()) then
                first = frame
            end
            if not bottom or frame:GetTop() < bottom:GetTop()
                          or (frame:GetTop() == bottom:GetTop()
                              and frame:GetLeft() < bottom:GetLeft()) then
                bottom = frame
            end
        end
    end
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
            left = false, right = false}
    end
    if first then
        self.targets[first].is_default = true
    end
end

function MenuCursor.handlers.WeeklyRewardsFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if WeeklyRewardsFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_WeeklyRewards")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_WeeklyRewards()
    menu_WeeklyRewardsFrame = MenuFrame(WeeklyRewardsFrame)
    self:HookShow(WeeklyRewardsFrame, "WeeklyRewardsFrame")
end

function MenuCursor:WeeklyRewardsFrame_Show()
    assert(WeeklyRewardsFrame:IsShown())
    WeeklyRewardsFrame_OnShow()
    self:AddFrame(menu_WeeklyRewardsFrame)
end

function MenuCursor:WeeklyRewardsFrame_Hide()
    self:RemoveFrame(menu_WeeklyRewardsFrame)
end


-------- Delve companion setup frame

local menu_DelvesCompanionConfigurationFrame
local menu_DelvesCompanionConfigurationSlot = {}
local menu_DelvesCompanionAbilityListFrame
local menu_DelvesCompanionRoleDropdown = {}

local function DelvesCompanionConfigurationFrame_ClickSlot(frame)
    frame:OnMouseDown("LeftButton", true)
end

local function DelvesCompanionConfigurationFrame_OnShow()
    local self = menu_DelvesCompanionConfigurationFrame
    local dccf = DelvesCompanionConfigurationFrame
    self.cancel_func = CancelUIFrame
    local function ClickSlot(frame)
        DelvesCompanionConfigurationFrame_ClickSlot(frame)
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

local function DelvesCompanionConfigurationSlot_OnShow(frame)
    local self = menu_DelvesCompanionConfigurationSlot[frame]
    local slot = frame:GetParent()
    self.cancel_func = function() frame:Hide() end
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

local DelvesCompanionAbilityListFrame_RefreshTargets  -- forward declaration

local function DelvesCompanionAbilityListFrame_ToggleRoleDropdown()
    local self = menu_DelvesCompanionAbilityListFrame
    local dcalf = DelvesCompanionAbilityListFrame
    local role_dropdown = dcalf.DelvesCompanionRoleDropdown

    role_dropdown:SetMenuOpen(not role_dropdown:IsMenuOpen())
    if role_dropdown:IsMenuOpen() then
        local menu, initial_target = SetupDropdownMenu(
            role_dropdown, menu_DelvesCompanionRoleDropdown,
            function(selection)
                if selection.data and selection.data.entryID == 123306 then
                    return 2  -- DPS
                else
                    return 1  -- Healer
                end
            end,
            DelvesCompanionAbilityListFrame_RefreshTargets)
        global_cursor:AddFrame(menu, initial_target)
    end
end

-- Forward-declared as local above.
function DelvesCompanionAbilityListFrame_RefreshTargets()
    local self = menu_DelvesCompanionAbilityListFrame
    local dcalf = DelvesCompanionAbilityListFrame
    self.targets = {
        [dcalf.DelvesCompanionRoleDropdown] = {
            on_click = function() DelvesCompanionAbilityListFrame_ToggleRoleDropdown() end,
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

local function DelvesCompanionAbilityListFrame_OnShow()
    local self = menu_DelvesCompanionAbilityListFrame
    self.cancel_func = HideUIFrame
    self.targets = {}
    -- Call RefreshTargets() after adding the frame.
end

function MenuCursor.handlers.DelvesCompanionConfigurationFrame(cursor)
    local dccf = DelvesCompanionConfigurationFrame
    menu_DelvesCompanionConfigurationFrame = MenuFrame(dccf)
    cursor:HookShow(dccf, "DelvesCompanionConfigurationFrame")
    local lists = {dccf.CompanionCombatRoleSlot.OptionsList,
                   dccf.CompanionCombatTrinketSlot.OptionsList,
                   dccf.CompanionUtilityTrinketSlot.OptionsList}
    for _, list in ipairs(lists) do
        menu_DelvesCompanionConfigurationSlot[list] = MenuFrame(list)
        cursor:HookShow(list, "DelvesCompanionConfigurationSlot")
    end
    local dcalf = DelvesCompanionAbilityListFrame
    menu_DelvesCompanionAbilityListFrame = MenuFrame(dcalf)
    cursor:HookShow(dcalf, "DelvesCompanionAbilityListFrame")
end

function MenuCursor:DelvesCompanionConfigurationFrame_Show()
    assert(DelvesCompanionConfigurationFrame:IsShown())
    DelvesCompanionConfigurationFrame_OnShow()
    self:AddFrame(menu_DelvesCompanionConfigurationFrame)
end

function MenuCursor:DelvesCompanionConfigurationFrame_Hide()
    self:RemoveFrame(menu_DelvesCompanionConfigurationFrame)
end

function MenuCursor:DelvesCompanionConfigurationSlot_Show(frame)
    DelvesCompanionConfigurationSlot_OnShow(frame)
    self:AddFrame(menu_DelvesCompanionConfigurationSlot[frame])
end

function MenuCursor:DelvesCompanionConfigurationSlot_Hide(frame)
    self:RemoveFrame(menu_DelvesCompanionConfigurationSlot[frame])
end

function MenuCursor:DelvesCompanionAbilityListFrame_Show()
    assert(DelvesCompanionAbilityListFrame:IsShown())
    DelvesCompanionAbilityListFrame_OnShow()
    self:AddFrame(menu_DelvesCompanionAbilityListFrame)
    DelvesCompanionAbilityListFrame_RefreshTargets()
end

function MenuCursor:DelvesCompanionAbilityListFrame_Hide()
    self:RemoveFrame(menu_DelvesCompanionAbilityListFrame)
end


-------- Delve start frame

local menu_DelvesDifficultyPickerFrame
local menu_DelvesDifficultyDropdown = {}

local function DelvesDifficultyDropdown_Hide(menu)
    self:PopFocus(menu)
    if self.focus == DelvesDifficultyPickerFrame then
        self:DelvesDifficultyPickerFrame_RefreshTargets()
    end
end

local DelvesDifficultyPickerFrame_RefreshTargets  -- forward declaration

local function DelvesDifficultyPickerFrame_ToggleDropdown()
    local ddpf = DelvesDifficultyPickerFrame
    local dropdown = ddpf.Dropdown

    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local menu, initial_target = SetupDropdownMenu(
            dropdown, menu_DelvesDifficultyDropdown,
            function(selection)
                return selection.data and selection.data.orderIndex + 1
            end,
            DelvesDifficultyPickerFrame_RefreshTargets)
        global_cursor:AddFrame(menu, initial_target)
    end
end

-- Forward-declared as local above.
function DelvesDifficultyPickerFrame_RefreshTargets()
    local self = menu_DelvesDifficultyPickerFrame
    local ddpf = DelvesDifficultyPickerFrame
    local Dropdown = ddpf.Dropdown
    local EnterDelveButton = ddpf.EnterDelveButton

    self.targets = {
        [Dropdown] = {
            on_click = function() DelvesDifficultyPickerFrame_ToggleDropdown() end,
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
                DelvesDifficultyPickerFrame_RefreshTargets()
            else
                RunNextFrame(TryRewards)
            end
        end
        RunNextFrame(TryRewards)
    end

    local dmwc = ddpf.DelveModifiersWidgetContainer
    if dmwc:IsShown() then
        AddWidgetTargets(dmwc, {"Spell"}, self.targets,
                         Dropdown, EnterDelveButton, false, nil)
    end

    if not initial_target then
        initial_target = (EnterDelveButton:IsEnabled() and EnterDelveButton
                          or Dropdown)
    end
    global_cursor:SetTargetForFrame(self, initial_target)
end

function MenuCursor.handlers.DelvesDifficultyPickerFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if DelvesDifficultyPickerFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_DelvesDifficultyPicker")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_DelvesDifficultyPicker()
    menu_DelvesDifficultyPickerFrame = MenuFrame(DelvesDifficultyPickerFrame)
    self:HookShow(DelvesDifficultyPickerFrame,
                  "DelvesDifficultyPickerFrame")
end

function MenuCursor:DelvesDifficultyPickerFrame_Show()
    assert(DelvesDifficultyPickerFrame:IsShown())
    menu_DelvesDifficultyPickerFrame.cancel_func = CancelUIFrame
    self:AddFrame(menu_DelvesDifficultyPickerFrame)
    DelvesDifficultyPickerFrame_RefreshTargets()
end

function MenuCursor:DelvesDifficultyPickerFrame_Hide()
    self:RemoveFrame(menu_DelvesDifficultyPickerFrame)
end


-------- Void storage purchase popup

local menu_VoidStoragePurchaseFrame

local function VoidStoragePurchaseFrame_OnShow()
    local self = menu_VoidStoragePurchaseFrame
    self.cancel_func = function() HideUIPanel(VoidStorageFrame) end
    self.targets = {
        [VoidStoragePurchaseButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            up = false, down = false, left = false, right = false},
    }
end

function MenuCursor.handlers.VoidStoragePurchaseFrame(cursor)
    cursor:RegisterEvent("ADDON_LOADED")
    if VoidStoragePurchaseFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_VoidStorageUI")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_VoidStorageUI()
    menu_VoidStoragePurchaseFrame = MenuFrame(VoidStoragePurchaseFrame)
    self:HookShow(VoidStoragePurchaseFrame, "VoidStoragePurchaseFrame")
end

function MenuCursor:VoidStoragePurchaseFrame_Show()
    VoidStoragePurchaseFrame_OnShow()
    self:AddFrame(menu_VoidStoragePurchaseFrame)
end

function MenuCursor:VoidStoragePurchaseFrame_Hide()
    self:RemoveFrame(menu_VoidStoragePurchaseFrame)
end


-------- Pet battle UI

local menu_PetBattleFrame, menu_PetBattlePetSelectionFrame

local function PetBattleFrame_RefreshTargets(initial_target)
    local self = menu_PetBattleFrame
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

local function PetBattleFrame_OnShow()
    local self = menu_PetBattleFrame
    self.cancel_func = function()
        global_cursor:SetTargetForFrame(
            self, PetBattleFrame.BottomFrame.ForfeitButton)
    end
    return PetBattleFrame_RefreshTargets(nil)
end

local function PetBattlePetSelectionFrame_OnShow()
    local self = menu_PetBattlePetSelectionFrame
    local psf = PetBattleFrame.BottomFrame.PetSelectionFrame

    self.cancel_func = nil
    self.targets = {
        [psf.Pet1] = {can_activate = true, send_enter_leave = true},
        [psf.Pet2] = {can_activate = true, send_enter_leave = true},
        [psf.Pet3] = {can_activate = true, send_enter_leave = true},
    }
    if C_PetBattles.CanPetSwapIn(1) then
        return psf.Pet1
    elseif C_PetBattles.CanPetSwapIn(2) then
        return psf.Pet2
    else  -- Should never get here.
        return psf.Pet3
    end
end

function MenuCursor.handlers.PetBattleFrame(cursor)
    menu_PetBattleFrame = MenuFrame(PetBattleFrame)
    menu_PetBattlePetSelectionFrame =
        MenuFrame(PetBattleFrame.BottomFrame.PetSelectionFrame)
    cursor:HookShow(PetBattleFrame, "PetBattleFrame")
    cursor:HookShow(PetBattleFrame.BottomFrame.PetSelectionFrame,
                    "PetBattlePetSelectionFrame")
    -- If we're in the middle of a pet battle, these might already be active!
    if PetBattleFrame:IsVisible() then
        cursor:PetBattleFrame_Show()
    end
    if PetBattleFrame.BottomFrame.PetSelectionFrame:IsVisible() then
        cursor:PetBattlePetSelectionFrame_Show()
    end
end

function MenuCursor:PetBattleFrame_Show()
    PetBattleFrame_OnShow()
    -- Don't activate input focus unless a battle is already in progress
    -- (i.e. we just reloaded the UI).
    if C_PetBattles.GetBattleState() == Enum.PetbattleState.WaitingForFrontPets then
        -- In this case, the pet battle UI (specifically the action buttons)
        -- won't be set up until later this frame, so wait a frame before
        -- setting input focus.
        RunNextFrame(function()
            local initial_target = PetBattleFrame_RefreshTargets(nil)
            self:AddFrame(menu_PetBattleFrame, initial_target)
        end)
    end
    self:RegisterEvent("PET_BATTLE_PET_CHANGED")
    self:RegisterEvent("PET_BATTLE_ACTION_SELECTED")
    self:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
end

function MenuCursor:PetBattleFrame_Hide()
    self:UnregisterEvent("PET_BATTLE_PET_CHANGED")
    self:UnregisterEvent("PET_BATTLE_ACTION_SELECTED")
    self:UnregisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
    self:RemoveFrame(menu_PetBattleFrame)
end

function MenuCursor:PetBattlePetSelectionFrame_Show()
    local initial_target = PetBattlePetSelectionFrame_OnShow()
    self:AddFrame(menu_PetBattlePetSelectionFrame, initial_target, true)  -- modal
end

function MenuCursor:PetBattlePetSelectionFrame_Hide()
    self:RemoveFrame(menu_PetBattlePetSelectionFrame)
end

function MenuCursor:PET_BATTLE_PET_CHANGED()
    local target = PetBattleFrame_RefreshTargets(nil)
    self:SetTargetForFrame(menu_PetBattleFrame, target)
end

function MenuCursor:PET_BATTLE_ACTION_SELECTED()
    menu_PetBattleFrame.last_target =
        self:GetTargetForFrame(menu_PetBattleFrame)
    self:RemoveFrame(menu_PetBattleFrame)
end

function MenuCursor:PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE()
    local target =
        PetBattleFrame_RefreshTargets(menu_PetBattleFrame.last_target)
    self:AddFrame(menu_PetBattleFrame, target)
end
