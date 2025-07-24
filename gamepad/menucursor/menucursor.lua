local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
WoWXIV.Gamepad.MenuCursor = WoWXIV.Gamepad.MenuCursor or {}
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

local FormatColoredText = WoWXIV.FormatColoredText
local GameTooltip = GameTooltip
local abs = math.abs
local floor = math.floor
local strsub = string.sub
local tinsert = tinsert
local tremove = tremove


-- Static reference to the singleton MenuCursor instance.
local global_cursor = nil


---------------------------------------------------------------------------
-- Core implementation
---------------------------------------------------------------------------

--[[
    Implementation of the menu cursor itself.  Frame handlers which inherit
    from the MenuFrame class (see below) generally will not need to interact
    directly with this class other than by calling RegisterFrameHandler()
    at startup time; MenuFrame provides more convenient interfaces for all
    other cursor-related functionality.
]]--
MenuCursor.Cursor = class(Button)
local Cursor = MenuCursor.Cursor

function Cursor.__allocator(class)
    -- This is a SecureActionButtonTemplate only so that we can indirectly
    -- click the button pointed to by the cursor without introducing taint;
    -- the cursor is hidden during combat.
    return Button.__allocator("Button", "WoWXIV_MenuCursor", UIParent,
                              "SecureActionButtonTemplate")
end

function Cursor:__constructor()
    assert(not global_cursor)
    global_cursor = self

    -- Is the player currently using gamepad input?  (Mirrors the
    -- GAME_PAD_ACTIVE_CHANGED event.)
    self.gamepad_active = false
    -- Stack of active MenuFrames and their current targets (each element
    -- is a {frame,target} pair, or the value false which indicates that no
    -- frame currently has input focus).  The current focus is on top of
    -- the stack (focus_stack[#focus_stack]).
    self.focus_stack = {false}
    -- Stack of active modal MenuFrames and their current targets.  If a
    -- modal frame is active, the top frame on this stack is the current
    -- focus and input frame cycling is disabled.
    self.modal_stack = {}
    -- Frame which currently holds the cursor lock, nil if none (see Lock()).
    self.lock_frame = nil
    -- Recursive lock depth for the current cursor lock.
    self.lock_depth = 0
    -- True if the cancel button was pressed during cursor lock.
    self.pending_cancel = false
    -- Current cursor display type.
    self.cursor_type = "default"
    -- Button auto-repeat manager.
    self.brm = WoWXIV.ButtonRepeatManager()

    self:Hide()
    self:SetFrameStrata("TOOLTIP")  -- Make sure it stays on top.
    self:SetSize(32, 32)
    self:SetScript("OnShow", self.OnShow)
    self:SetScript("OnHide", self.OnHide)
    self:SetScript("OnEvent", self.OnEvent)
    self:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    self:RegisterEvent("CURSOR_CHANGED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:SetAttribute("type1", "click")
    self:SetAttribute("type2", "click")
    self:SetAttribute("clickbutton1", nil)
    self:SetAttribute("clickbutton2", nil)
    self:HookScript("OnClick",
                    function(_,button,down) self:OnClick(button,down) end)
    self:RegisterForClicks("AnyDown", "AnyUp")

    for _, handler_class in pairs(Cursor.handlers) do
        handler_class:Initialize(self)
    end

    local texture = self:CreateTexture(nil, "ARTWORK")
    self.texture = texture
    texture:SetAllPoints()
    self:SetCursorTexture()

    -- Icon holder for an item held by the game cursor.
    local held = self:CreateTexture(nil, "ARTWORK", nil, -1)
    self.held_item_icon = held
    held:Hide()
    held:SetSize(30, 30)
    held:SetPoint("TOPLEFT", 15, -8)
end


-------- Frame handler interface (methods intended for use by frame handlers)

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
-- omitted from the arguments passed to the handler.
function Cursor:RegisterFrameEvent(handler, event, event_arg)
    local handler_name, wrapper
    if event_arg then
        handler_name = event.."__"..tostring(event_arg)
        local old_handler = self[handler_name]
        if old_handler then
            wrapper = function(cursor, event, arg1, ...)
                old_handler(cursor, event, arg1, ...)
                handler(...)
            end
        else
            wrapper = function(cursor, event, arg1, ...) handler(...) end
        end
    else
        handler_name = event
        local old_handler = self[handler_name]
        if old_handler then
            wrapper = function(cursor, event, ...)
                old_handler(cursor, event, ...)
                handler(...)
            end
        else
            wrapper = function(cursor, event, ...) handler(...) end
        end
    end
    self[handler_name] = wrapper
    self:RegisterEvent(event)
end

-- Add the given frame (a MenuFrame instance) to the focus stack, set its
-- current target to the given input element, and optionally set the menu
-- cursor focus to that frame.
--
-- If |modal| is true, the frame becomes a modal frame, blocking menu
-- cursor input to any other frame until it is removed.
--
-- |target| sets the initial target for the frame.  If the frame is
-- already in the focus stack, its target is changed to that element.
-- If nil, the initial target is chosen by calling the frame's
-- GetDefaultTarget() method, but no change is made if the frame is
-- already in the focus stack and has a (non-nil) target.
--
-- If |focus| is true, the frame is added to the top of its focus stack,
-- or moved there if it is already in the stack; otherwise, if it is not
-- already in the stack, it is added to the bottom.
function Cursor:AddFrame(frame, modal, target, focus)
    local other_stack = modal and self.focus_stack or self.modal_stack
    if WoWXIV.anyt(function(v) return v and v[1]==frame end, other_stack) then
        error("Invalid attempt to change modal state of frame "..tostring(frame))
    end
    local stack = modal and self.modal_stack or self.focus_stack
    for i, v in ipairs(stack) do
        if v and v[1] == frame then
            if i == #stack or not focus then
                -- Frame is already present and not changing position in
                -- the stack, so just change the target if appropriate.
                if not target and not v[2] then
                    target = frame:GetDefaultTarget()
                end
                if target then
                    self:SetTargetForFrame(frame, target)
                end
                return
            end
            target = target or v[2]
            tremove(stack, i)
            break
        end
    end
    -- If this is a modal frame and it's the only one in the stack, it
    -- gets input focus regardless of whether it requested focus.
    if modal and #stack == 0 then
        focus = true
    end
    -- But note that we don't actually perform the focus change if we're
    -- currently locked, even if the new frame should be focused.
    local do_focus_change = focus and not self.lock_frame
    if do_focus_change then
        self:SendUnfocus()
    end
    target = target or frame:GetDefaultTarget()
    tinsert(stack, focus and #stack+1 or 1, {frame, target})
    if target then
        frame:ScrollToTarget(target)
    end
    if do_focus_change then
        self:SendFocus()
        self:UpdateCursor()
    end
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

-- Return whether any focus stack has the given frame.
function Cursor:HasFrame(frame)
    local function Match(entry) return entry and entry[1]==frame end
    return WoWXIV.anyt(Match, self.focus_stack)
        or WoWXIV.anyt(Match, self.modal_stack)
end

-- Return the MenuFrame which currently has focus, or nil if none.
function Cursor:GetFocus()
    if self.lock_frame then
        assert(self:HasFrame(self.lock_frame))
        return self.lock_frame
    else
        local stack = self:InternalGetFocusStack()
        local top = #stack
        return (top > 0 and stack[top] and stack[top][1]) or nil
    end
end

-- Set the cursor's input focus, bringing the specified frame to the top
-- of the focus stack.  If frame is nil, the input focus is cleared while
-- leaving the focus stack otherwise unaffected (a cycle-focus input will
-- reactivate the previously focused frame).  It is an error to attempt
-- to focus a non-modal frame or clear input focus while a modal frame is
-- active.  If the cursor is currently locked, the focus stack will be
-- updated but the cursor's focus itself will not change until the lock
-- is released.
function Cursor:SetFocus(frame)
    local stack = self:InternalGetFocusStack()
    local top = #stack
    for i, v in ipairs(stack) do
        if (frame and v and v[1] == frame) or (not frame and not v) then
            if i < top then
                self:SendUnfocus()
                tinsert(stack, tremove(stack, i))
                self:SendFocus()
                self:UpdateCursor()
            end
            return
        end
    end
    error("SetFocus for frame ("..tostring(frame)..") not in focus stack")
end

-- Return the input element most recently selected in the given frame.
-- Returns nil if the given frame is not in the focus stack.
function Cursor:GetTargetForFrame(frame)
    local stack, index = self:InternalFindFrame(frame)
    return stack and stack[index][2] or nil
end

-- Set the menu cursor target for a specific frame.  If the frame is
-- topmost on the focus stack, also sends the appropriate LeaveTarget()
-- and EnterTarget() calls for the old and new targets.  Does nothing if
-- the given frame is not on the focus stack.
function Cursor:SetTargetForFrame(frame, target)
    local stack, index = self:InternalFindFrame(frame)
    if stack then
        local is_focus =
            stack == self:InternalGetFocusStack() and index == #stack
        if target == stack[index][2] then
            return  -- No change.
        elseif is_focus and stack[index][2] then
            -- We're changing the target of the focused frame, so send a
            -- LeaveTarget() to the current target.  This could trigger a
            -- change of input focus or even remove the current frame, so
            -- we have to be careful here.
            local entry = stack[index]
            self:LeaveTarget()
            entry[2] = nil
            if target then
                -- If something changed the current focus (so we end up
                -- skipping the UpdateCursor() call below), that will
                -- itself have triggered an UpdateCursor() call, so we
                -- don't need to add an extra call for that case.
                return self:SetTargetForFrame(frame, target)
            else  -- Explicit clear of current target.
                self:UpdateCursor()
            end
        else
            stack[index][2] = target
            if is_focus then
                self:EnterTarget()
                self:UpdateCursor()
            end
        end
    end
end

-- Lock the cursor, preventing all input until Unlock() is called.  The
-- |frame| argument gives the calling frame, i.e. the frame requesting
-- the lock.  The frame must be in the frame stack; if it does not
-- currently have focus, it will gain focus for the duration of the lock
-- (though only nominally, since the lock also suppresses input).
--
-- This may be used when a menu action will take time to complete, to
-- prevent the player's inputs from interfering with that action.  A
-- typical sequence as implemented by a MenuFrame handler might look like:
--    function FrameHandler:OnAction()
--        -- (start the action)
--        self:RegisterEvent("ACTION_COMPLETE")  -- (action's completion event)
--        self:LockCursor()
--    end
--    function FrameHandler:ACTION_COMPLETE()
--        self:UnlockCursor()
--    end
--
-- Ordinary cursor input will be suppressed while the cursor is locked, but
-- the cursor will record whether the cancel button has been pressed; this
-- state can be retrieved with IsPendingCancel().  The locking frame can
-- use this information to abort its operation early, for example.
--
-- Locks may be nested; Unlock() must be called the same number of times
-- as Lock() was called in order to unlock the cursor.
--
-- If the locking frame is removed from the focus stack, the cursor is
-- automatically unlocked, as if Unlock() had been called.
--
-- AddFrame() behaves as usual while the cursor is locked, except that
-- the lock overrides normal focus behavior, and the locking frame will
-- retain input focus even if another frame is added on top of it in the
-- focus stack.  This is also the only case in which a non-modal frame can
-- have input focus while a modal frame is active.
function Cursor:Lock(frame)
    assert(frame)
    assert(self:HasFrame(frame), "Frame must be in focus stack to lock cursor")
    assert(not self.lock_frame or self.lock_frame == frame,
           "Cursor is already locked")
    if self.lock_frame then
        self.lock_depth = self.lock_depth + 1
    else
        assert(self.lock_depth == 0)
        local cur_focus = self:GetFocus()
        if cur_focus ~= frame then
            self:SendUnfocus()
        end
        self.lock_frame = frame
        self.lock_depth = 1
        self.pending_cancel = false  -- Should already be false, but be safe.
        if cur_focus ~= frame then
            self:SendFocus()
        end
        self:UpdateCursor()
    end
end

-- Unlock the cursor.  Does nothing if the cursor is not locked, or if the
-- calling frame is not the one which locked the cursor.
function Cursor:Unlock(frame)
    assert(frame)
    assert(not self.lock_frame or self.lock_frame == frame,
           "Unlock from frame which did not lock")
    assert(self.lock_depth > 0)
    self.lock_depth = self.lock_depth - 1
    if self.lock_depth <= 0 then
        self:ClearLock()
        self:UpdateCursor()
    end
end

-- Return whether the cancel button was pressed while the cursor was locked.
-- Always returns false if the cursor is not locked.
function Cursor:IsPendingCancel()
    return self.pending_cancel
end


-------- Internal implementation methods (should not be called externally)

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

-- Handler for cursor state changes.
function Cursor:CURSOR_CHANGED(active)
    self:UpdateCursor()
end

-- Handlers for entering and leaving combat.
function Cursor:PLAYER_REGEN_DISABLED()
    self:UpdateCursor(true)
end
function Cursor:PLAYER_REGEN_ENABLED()
    self:UpdateCursor(false)
end

-- Set the appropriate cursor texture for the current cursor type.
function Cursor:SetCursorTexture()
    local texture = self.texture
    if self.cursor_type == "map" then
        WoWXIV.SetUITexture(texture, 0, 40, 80, 120)
    else
        assert(self.cursor_type == "default")
        -- Use the default mouse cursor image (pointing gauntlet), but
        -- flip it horizontally to distinguish it from the mouse cursor.
        texture:SetTexture("Interface/CURSOR/Point")
        texture:SetTexCoord(1, 0, 0, 1)
    end
end

-- Internal helper for RemoveFrame().
function Cursor:InternalRemoveFrameFromStack(frame, stack, is_top_stack)
    for i, v in ipairs(stack) do
        if v and v[1] == frame then
            local had_lock = (self.lock_frame == frame)
            if had_lock then
                self:ClearLock()
            end
            local is_focus = had_lock or (is_top_stack and i == #stack)
            if is_focus then
                self:SendUnfocus()
            end
            tremove(stack, i)
            if is_focus then
                self:SendFocus()
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

-- Return the current focus and target in a single function call.
function Cursor:GetFocusAndTarget()
    if self.lock_frame then
        local stack, index = self:InternalFindFrame(self.lock_frame)
        assert(stack)
        return unpack(stack[index])
    else
        local stack = self:InternalGetFocusStack()
        local top = #stack
        if top > 0 and stack[top] then
            return unpack(stack[top])
        else
            return nil, nil
        end
    end
end

-- Send an OnFocus event to the currently focused MenuFrame.  Also calls
-- EnterTarget() for the new target.
function Cursor:SendFocus()
    local focus = self:GetFocus()
    if focus then
        focus:OnFocus()
        self:EnterTarget()
    end
end

-- Send an OnUnfocus event to the currently focused MenuFrame.  First calls
-- LeaveTarget() for the current target.
function Cursor:SendUnfocus()
    local focus = self:GetFocus()
    if focus then
        self:LeaveTarget()
        focus:OnUnfocus()
     end
end

-- Perform all actions appropriate to the cursor entering a target.
-- Does nothing if the cursor does not currently have a target.
function Cursor:EnterTarget()
    local focus, target = self:GetFocusAndTarget()
    if target then
        local cursor_type = focus:GetTargetCursorType(target) or "default"
        if cursor_type ~= self.cursor_type then
            self.cursor_type = cursor_type
            self:SetCursorTexture()
        end
        if self:IsShown() then
            focus:EnterTarget(target)
        end
    end
end

-- Perform all actions appropriate to the cursor leaving a target.
-- Does nothing if the cursor does not currently have a target.
function Cursor:LeaveTarget()
    local focus, target = self:GetFocusAndTarget()
    if target then
        if self:IsShown() then
            focus:LeaveTarget(target)
        end
    end
end

-- Internal helper to clear the menu cursor target without calling the
-- leave callback.  For use when the current target is invalid (and thus
-- attempting to call the leave callback may trigger an error).
function Cursor:InternalForceClearTarget()
    local stack = self:InternalGetFocusStack()
    local top = #stack
    if top > 0 and stack[top] then
        stack[top][2] = nil
    end
end

-- Internal helper to find a frame in the regular or modal frame stack.
-- Returns the stack and index, or (nil,nil) if not found.
function Cursor:InternalFindFrame(frame)
    local focus_stack = self.focus_stack
    for i, v in ipairs(focus_stack) do
        if v and v[1] == frame then
            return focus_stack, i
        end
    end
    local modal_stack = self.modal_stack
    for i, v in ipairs(modal_stack) do
        if v and v[1] == frame then
            return modal_stack, i
        end
    end
    return nil, nil
end

-- Clear state related to cursor locking.  Should be called when the lock
-- is released.
function Cursor:ClearLock()
    self.lock_frame = nil
    self.pending_cancel = false
end

-- Update the cursor's display state and input bindings.
-- This method is primarily intended for internal use, but frame handlers
-- may call it with no argument to force a resync if any state has changed
-- outside the control of the cursor.
function Cursor:UpdateCursor(in_combat)
    local entering_combat = in_combat  -- Passed as true only in this case.
    if in_combat == nil then
        in_combat = InCombatLockdown()
    end

    local focus, target = self:GetFocusAndTarget()
    while focus and not focus:GetFrame():IsVisible() do
        self:RemoveFrame(focus)
        focus, target = self:GetFocusAndTarget()
    end

    -- We update the parent regardless of whether the cursor should be
    -- shown or not, because the reparenting may be required to get
    -- input events in the first place.
    if not in_combat then
        local new_parent =
            (focus and focus:GetCursorParentOverride()) or UIParent
        if self:GetParent() ~= new_parent then
            self:SetParent(new_parent)
            -- Looks like we need to refresh this when reparenting.
            if new_parent == UIParent then
                self:SetFrameStrata("TOOLTIP")
            end
        end
    end

    local should_show = self.gamepad_active and not in_combat

    local target_frame
    if target then
        target_frame = focus:GetTargetFrame(target)
        if not target_frame and should_show and not self:IsShown() then
            -- The target might not have a frame only because it's
            -- scrolled out of view and SetTargetForFrame() didn't scroll
            -- to it because the cursor wasn't visible, so we resolve that
            -- chicken-and-egg problem here.
            focus:ScrollToTarget(target)
            target_frame = focus:GetTargetFrame(target)
        end
        if not target_frame then
            self:SetTargetForFrame(focus, nil)
            target = nil
        end
    end

    if target and should_show then
        self:SetCursorPoint(focus, target)
        if focus:IsTargetClickable(target) then
            local action = focus:GetTargetClickAction(target)
            if action then
                if action.type == "item" then
                    if not action.item then
                        error("Missing action item")
                    end
                    self:SetAttribute("type1", "item")
                    self:SetAttribute("item1", action.item)
                elseif action.type == "spell" then
                    if not action.spell then
                        error("Missing action spell")
                    end
                    self:SetAttribute("type1", "spell")
                    self:SetAttribute("spell1", action.spell)
                    self:SetAttribute("target-bag1", action["target-bag"])
                    self:SetAttribute("target-slot1", action["target-slot"])
                else
                    error("Unknown click action type: "..action.type)
                end
            else
                self:SetAttribute("type1", "click")
                self:SetAttribute("clickbutton1", target_frame)
            end
        else
            self:SetAttribute("type1", nil)
        end
        self:SetAttribute("clickbutton2", focus:GetCancelButton())
        if not self:IsShown() then
            self:Show()
            self:EnterTarget()
        end
    else
        if self:IsShown() then
            self:LeaveTarget()
            self:Hide()
        end
    end

    if self:IsShown() then
        local item_texture
        if focus and focus:IsCursorShowItem() then
            local info = {GetCursorInfo()}
            if info[1] == "item" then
                item_texture = select(10, C_Item.GetItemInfo(info[2]))
            end
        end
        if item_texture then
            self.held_item_icon:SetTexture(item_texture)
            self.held_item_icon:Show()
        else
            self.held_item_icon:Hide()
        end
    end

    if in_combat and not entering_combat then return end

    ClearOverrideBindings(self)
    -- Any access to WoWXIV_config here will taint execution in StaticPopup
    -- frames, which can break some common game actions such as item
    -- upgrading.  We work around this by suppressing frame cycling on
    -- modal frames, which shouldn't be a problem in practice.  See
    -- config.lua for how we deal with user-configurable confirm/cancel
    -- buttons (which ideally would have their own cvars, but oh well).
    local modal = (self:InternalGetFocusStack() == self.modal_stack)
    if not (modal or self.lock_frame) then
        SetOverrideBinding(self, true,
                           WoWXIV.Config.GamePadCycleFocusButton(),
                           "CLICK WoWXIV_MenuCursor:CycleFocus")
    end
    if self.lock_frame and not entering_combat then
        SetOverrideBinding(self, true, WoWXIV.Config.GamePadCancelButton(),
                           "CLICK WoWXIV_MenuCursor:CancelLock")
    elseif focus and not entering_combat then
        SetOverrideBinding(self, true, "PADDUP",
                           "CLICK WoWXIV_MenuCursor:DPadUp")
        SetOverrideBinding(self, true, "PADDDOWN",
                           "CLICK WoWXIV_MenuCursor:DPadDown")
        SetOverrideBinding(self, true, "PADDLEFT",
                           "CLICK WoWXIV_MenuCursor:DPadLeft")
        SetOverrideBinding(self, true, "PADDRIGHT",
                           "CLICK WoWXIV_MenuCursor:DPadRight")
        local cancel = focus:GetCancelButton() and "RightButton" or "Cancel"
        SetOverrideBinding(self, true, WoWXIV.Config.GamePadCancelButton(),
                           "CLICK WoWXIV_MenuCursor:"..cancel)
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
            SetOverrideBinding(self, true,
                               WoWXIV.Config.GamePadPrevPageButton(),
                               prev_button)
            SetOverrideBinding(self, true,
                               WoWXIV.Config.GamePadNextPageButton(),
                               next_button)
        end
        if focus:GetTabHandler() then
            SetOverrideBinding(self, true,
                               WoWXIV.Config.GamePadPrevTabButton(),
                               "CLICK WoWXIV_MenuCursor:PrevTab")
            SetOverrideBinding(self, true,
                               WoWXIV.Config.GamePadNextTabButton(),
                               "CLICK WoWXIV_MenuCursor:NextTab")
        end
        -- Make sure the cursor is visible before we allow menu actions.
        if self:IsShown() then
            SetOverrideBinding(self, true,
                               WoWXIV.Config.GamePadConfirmButton(),
                               "CLICK WoWXIV_MenuCursor:LeftButton")
            if focus:HasActionButton("Button3") then
                SetOverrideBinding(self, true,
                                   WoWXIV.Config.GamePadMenuButton3(),
                                   "CLICK WoWXIV_MenuCursor:Button3")
            end
            if focus:HasActionButton("Button4") then
                SetOverrideBinding(self, true,
                                   WoWXIV.Config.GamePadMenuButton4(),
                                   "CLICK WoWXIV_MenuCursor:Button4")
            end
        end
    end
end

-- Show() handler; activates menu cursor periodic update.
function Cursor:OnShow()
    self:SetScript("OnUpdate", self.OnUpdate)
    self:OnUpdate(0)
end

-- Hide() handler; clears menu cursor periodic update.  Also stops any
-- button repeat in progress, because apparently we lose button-up events
-- if a frame is hidden after the button-down event (even if the frame is
-- re-shown before the button is released).
function Cursor:OnHide()
    self:SetScript("OnUpdate", nil)
    self.brm:StopRepeat()
end

-- Per-frame update routine.  This serves two purposes: to implement
-- cursor bouncing, and to record the current focus frame and target
-- element to avoid a single click activating multiple elements (see
-- notes in OnClick()).
function Cursor:OnUpdate(dt)
    local focus, target = self:GetFocusAndTarget()
    if dt > 0 then
        self.last_focus, self.last_target = focus, target
    end
    local target_frame = target and focus:GetTargetFrame(target)
    if target_frame and not target_frame.GetLeft then
        self:InternalForceClearTarget()
        error("Invalid target frame ("..tostring(target_frame)..") for target "..tostring(target))
    end
    if not target_frame then
        self.brm:StopRepeat()
        return
    end

    self.brm:CheckRepeat(function(button) self:OnClick(button, true, true) end)

    --[[
         Calling out to fetch the target's position and resetting the
         cursor anchor points every frame is not ideal, but we need to
         keep the cursor position updated when buttons change positions,
         such as:
            - Scrolling of gossip/quest text
            - BfA troop recruit frame on first open after /reload
            - Upgrade confirmation dialog for Shadowlands covenant sanctum
    ]]--
    self:SetCursorPoint(focus, target)

    self.texture:ClearPointsOffset()
    if self.cursor_type == "default" then
        local t = GetTime()
        t = t - floor(t)
        local xofs = -4 * math.sin(t * math.pi)
        self.texture:AdjustPointsOffset(xofs, 0)
    end

    self:SetAlpha(target_frame and target_frame:GetAlpha() or 1)

    focus:OnUpdate(target_frame, dt)
end

-- Helper for UpdateCursor() and OnUpdate() to set the cursor frame anchor.
function Cursor:SetCursorPoint(focus, target)
    self:ClearAllPoints()
    -- Work around frame reference limitations on secure buttons.
    --self:SetPoint("TOPRIGHT", target, "LEFT")
    local x, y = focus:GetTargetPosition(target)
    if not x or not y then return end
    local parent = self:GetParent()
    self:SetPoint("TOPRIGHT", parent, "TOPLEFT", x, y-parent:GetHeight())
end

-- Click event handler; handles all events other than secure click passthrough.
function Cursor:OnClick(button, down, is_repeat)
    if not down then
        self.brm:StopRepeat()
        return
    end

    if button ~= self.brm:GetRepeatButton() then
        self.brm:StopRepeat()
    end

    if button == "CycleFocus" then
        if not self.lock_frame and #self.modal_stack == 0 then
            local stack = self.focus_stack
            local top = #stack
            if top > 1 then
                self:SendUnfocus()
                tinsert(stack, 1, tremove(stack, top))
                assert(#stack == top)
                self:SendFocus()
                self:UpdateCursor()
            end
        end
        return
    end

    local focus, target = self:GetFocusAndTarget()
    -- Click bindings should be cleared if we have no focus, but we could
    -- still get here right after a secure passthrough click closes the
    -- last frame.
    if not focus then return end
    if button == "DPadUp" or button == "DPadDown" or button == "DPadLeft" or button == "DPadRight" then
        local dir = strsub(button, 5):lower()
        if focus:IsTargetDPadOverride(target) then
            focus:OnDPad(dir)
        else
            self:Move(dir)
        end
        self.brm:StartRepeat(button)
    elseif button == "LeftButton" then  -- i.e., confirm
        if is_repeat and target and focus:IsTargetClickable(target) then
            -- Repeated clicks naturally don't get forwarded, so we have to
            -- call down ourselves.
            local target_frame = focus:GetTargetFrame(target)
            target_frame:GetScript("OnClick")(target_frame, button, down)
            -- Focus/target might have changed! (see notes below)
            focus, target = self:GetFocusAndTarget()
        end
        -- The click event (if not a repeat, see above) is passed to the
        -- target frame by SecureActionButtonTemplate.  This code is called
        -- afterward, so it's possible that the click already closed our
        -- (previously) current focus frame or otherwise changed the cursor
        -- state.  If we blindly proceed with calling the on_click handler
        -- here, we could potentially perform a second click action from a
        -- single button press, so ensure that the focus state has not in
        -- fact changed since the last OnUpdate() call.
        if focus == self.last_focus and target == self.last_target then
            if target then
                focus:OnConfirm(target)
                focus, target = self:GetFocusAndTarget()
            end
        end
        -- Only allow confirm button repeating for buttons which explicitly
        -- permit it, and then only if the confirm action didn't change the
        -- target (intended for things like profession skill upgrade buttons).
        local repeatable = false
        if focus == self.last_focus and target == self.last_target then
            repeatable = target and focus:IsTargetRepeatable(target)
        end
        if repeatable then
            self.brm:StartRepeat(button)
        else
            -- This could be the result of a repeated confirm action
            -- changing the target, so we have to make sure to stop it!
            self.brm:StopRepeat(button)
        end
    elseif button == "Cancel" then
        -- If the frame declared a cancel button, the click is passed down
        -- as a separate event, so we only get here in the no-passthrough
        -- case.
        focus:OnCancel()
    elseif button == "CancelLock" then
        assert(self.lock_frame)
        self.pending_cancel = true
    elseif button == "Button3" or button == "Button4" then
        focus:OnAction(button)
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
        local handler = focus:GetTabHandler()
        local direction = button=="PrevTab" and -1 or 1
        handler(direction)
    end
end

-- OnClick() helper which moves the cursor in the given direction.
-- dir gives the direction, one of the strings "up", "down", "left", or
-- "right".
function Cursor:Move(dir)
    if not self:IsShown() then
        -- We got a directional input event while in mouse input mode.
        -- Rather than immediately moving the cursor, just show it at its
        -- current position and let the next input do the actual movement.
        self:UpdateCursor()
        return
    end
    local focus, target = self:GetFocusAndTarget()
    local new_target = focus:NextTarget(target, dir)
    if new_target and new_target ~= target then
        self:SetTargetForFrame(focus, new_target)
        -- Check for the pathological case of the frame closing during
        -- the movement (as in SetCursorForFrame()).
        if self:InternalFindFrame(focus) then
            if focus.OnMove then
                focus:OnMove(target, new_target)
            end
        end
    end
end


---------------------------------------------------------------------------
-- Frame manager base class
---------------------------------------------------------------------------

--[[
    Base class for managing menu frames using the menu cursor.  Each
    managed frame should have an associated instance of this class or a
    subclass; typically, one would create a frame-specific subclass of
    this class and allow it to initialize automatically using the
    Cursor.RegisterFrameHandler() interface, though it is also possible
    to create and initialize instances of this class directly (see the
    SetupDropdownMenu() method for an example).

    Note that this file also provides StandardMenuFrame, CoreMenuFrame,
    and AddOnMenuFrame subclasses of MenuFrame which include standard
    behaviors such as show/hide hooks and automatic instance creation on
    registration; in many cases, these will be more convenient than
    subclassing MenuFrame itself.
]]--
MenuCursor.MenuFrame = class()
local MenuFrame = MenuCursor.MenuFrame

-- Convenience constant for passing true to the modal argument of the
-- MenuFrame constructor in a way that indicates the argument's meaning.
-- Python-style keyword-only arguments would be nice here.
MenuFrame.MODAL = true


-------- Instance constructor

-- Instance constructor.  Pass the WoW Frame instance to be managed.
-- If |modal| is true, the frame will be modal (preventing switching input
-- focus to any non-modal frame while active).
-- |frame| == nil is permitted only if the instance overrides GetFrame()
-- or otherwise arranges for instance.frame to have the proper value
-- whenever the menu cursor is on a target managed by the instance.
-- (See ContainerFrameHandler for an example.)
function MenuFrame:__constructor(frame, modal)
    self.frame = frame
    self.modal = modal

    -------- Frame parameters which may be set by specializations:

    -- Table of valid targets for cursor movement.  Each key is a WoW Frame
    -- instance (except as noted for is_scroll_box below) for a menu
    -- element, and each value is a subtable with the following possible
    -- keys:
    --    - can_activate: If true, a confirm input on this element causes a
    --         left-click action to be sent to the element (which must be a
    --         Button instance).
    --    - can_repeat: If true, confirm inputs on this element can be
    --         repeated by holding down the confirm button.  Cannot be used
    --         for actions which run secure code (attempting to do so will
    --         trigger a taint error), since repeats are handled by
    --         user-side logic.
    --    - click_action: Specifies the action to be securely performed
    --         when the target is activated.  The value must be a table
    --         containing a "type" field giving the action type (as for
    --         SecureActionButtonTemplate) along with any data appropriate
    --         to that type.  If not specified, a left-click action is
    --         performed on the target (which must be a Button instance);
    --         note that if the target button itself (i.e. the table value)
    --         is tainted, the button will not be able to execute any
    --         secure actions even if it was created with a secure template
    --         like SecureActionButtonTemplate.
    --    - cursor_show_item: If true, an item held by the game cursor
    --         (as indicated by GetCursorInfo()) will be displayed next to
    --         the cursor image.
    --    - cursor_type: Sets the cursor type for this target, one of:
    --         - "default" (or nil): Default bouncing finger pointer.
    --         - "map": Circle with internal crosshairs.
    --    - dpad_override: If true, while the cursor is on this element,
    --         all directional pad inputs will be passed to the OnDPad()
    --         method rather than performing their normal cursor movement
    --         behavior.  This should normally be left unset except while
    --         editing a numeric input.
    --    - is_default: If true, this element will be targeted if the frame
    --         receives input focus and no element was previously targeted.
    --         Behavior is undefined if more than one element has this key
    --         with a true value.
    --    - is_scroll_box: If non-nil, the key is a pseudo-frame for the
    --         corresponding scroll list element returned by
    --         PseudoFrameForScrollElement().
    --    - lock_highlight: If true, the element's LockHighlight() and
    --         UnlockHighlight() methods will be called when the element is
    --         targeted and untargeted, respectively.
    --    - on_click: If non-nil, a function to be called when the element
    --         is activated.  The element is passed as an argument.  When
    --         set along with can_activate, this is called after the click
    --         event is passed down to the element.
    --    - on_enter: If non-nil, a function to be called when the cursor
    --         is moved onto the element.  The element is passed as an
    --         argument.  Ignored if send_enter_leave is set.
    --    - on_leave: If non-nil, a function to be called when the cursor
    --         is moved off the element.  The element is passed as an
    --         argument.  Ignored if send_enter_leave is set.
    --    - scroll_frame: If non-nil, a ScrollFrame which should be scrolled
    --         to make the element visible when targeted.
    --    - send_enter_leave: If true, the element's OnEnter and OnLeave
    --         scripts (if any) will be called when the element is targeted
    --         and untargeted, respectively.
    --    - suppress_scroll: If true, no scrolling will be performed when
    --         this element is selected even if the is_scroll_box or
    --         scroll_frame key is set.  This can be used to work around
    --         scroll box containers which are slightly too small for
    --         their contents (such as the delve companion curio lists).
    --    - up, down, left, right: If non-nil, specifies the element to be
    --         targeted on the corresponding movement input from this
    --         element.  A value of false prevents movement in the
    --         corresponding direction.
    --    - x_offset: Specifies the horizontal offset of the menu cursor
    --         from its default position, in display units.  A nil value is
    --         treated as zero.
    --    - y_offset: Specifies the vertical offset of the menu cursor from
    --         its default position, in display units.  A nil value is
    --         treated as zero.
    self.targets = {}
    -- Function to call when the cancel button is pressed (receives self
    -- as an argument).  If nil, no action is taken.
    self.cancel_func = nil
    -- Button (WoW Button instance) to be clicked on a gamepad cancel
    -- button press, or nil for none.  If set, cancel_func is ignored.
    self.cancel_button = nil
    -- Flags indicating whether each action button is used by this frame.
    -- If true, the corresponding gamepad input will be captured while this
    -- frame has menu cursor focus.
    self.has_Button3 = false
    self.has_Button4 = false
    -- Object to handle gamepad previous-page button presses.  May be any of:
    --    - A string, giving the global name of a button to which a click
    --      action will be securely forwarded.
    --    - A Button instance, to which a click action will be (insecurely)
    --      sent.
    --    - A function, which will be called a single argument indicating
    --      the switch direction, -1 (previous) or 1 (next).
    --    - nil, indicating that page flipping is not supported by this frame.
    -- Must not be changed while the frame is enabled for input.  (Gamepad
    -- page flipping is only enabled if both this and on_next_page are
    -- non-nil.)
    self.on_prev_page = nil
    -- Object to handle gamepad next-page button presses.  See on_prev_page
    -- for details.
    self.on_next_page = nil
    -- Function to handle gamepad previous-tab and next-tab button presses,
    -- or nil to indicate that tab switching is not supported by this frame.
    -- The function will receive a single argument indicating the switch
    -- direction, -1 (previous) or 1 (next).  Must not be changed while the
    -- frame is enabled for input.
    self.tab_handler = nil
    -- Alternate parent for the Cursor frame.  This should normally not be
    -- touched; its primary use is in keeping the cursor visible for the
    -- cinematic cancel dialog.
    self.cursor_parent_override = nil

    -------- Internal data (specializations should not touch these):

    -- Currently executing subroutine for RunUnderLock(), nil if none.
    self.lock_coroutine = nil
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

-- Return the handler for previous-tab and next-tab actions for this frame,
-- or nil if none.
function MenuFrame:GetTabHandler()
    return self.tab_handler
end

-- Return the parent override frame for the cursor, if any.
function MenuFrame:GetCursorParentOverride()
    return self.cursor_parent_override
end

-- Return the WoW Button instance of the cancel button for this frame, or
-- nil if none.
function MenuFrame:GetCancelButton()
    return self.cancel_button
end

-- Return whether this frame makes use of the given action button, either
-- "Button3" or "Button4".  If this method returns true, the given button
-- will be captured by the menu cursor.
function MenuFrame:HasActionButton(button)
    assert(button == "Button3" or button == "Button4")
    return self["has_"..button]
end

-- Return whether a held-item icon should be displayed with the cursor.
function MenuFrame:IsCursorShowItem()
    return self.cursor_show_item
end

-- Return the frame's default cursor target, or nil if none.
function MenuFrame:GetDefaultTarget()
    for frame, params in pairs(self.targets) do
        if params.is_default then
            return frame
        end
    end
    return nil
end

-- Return the WoW Frame instance associated with the given menu element
-- (targets[] key).
function MenuFrame:GetTargetFrame(target)
    local params = self.targets[target]
    if params and params.is_scroll_box then
        local box = target.box
        local success, result = pcall(function()
            return box:FindFrame(box:FindElementData(target.index))
        end)
        return success and result or nil
    else
        return target
    end
end

-- Return whether confirm button click events should be securely passed
-- down to the given target's frame.
function MenuFrame:IsTargetClickable(target)
    local params = self.targets[target]
    return params and params.can_activate
end

-- Return whether confirm button click events should be repeatable.
function MenuFrame:IsTargetRepeatable(target)
    local params = self.targets[target]
    return params and params.can_repeat
end

-- For clickable targets (when IsTargetClickable() returns true), return
-- the click action data for the target, if any.  The return value should
-- be a table of secure button attributes, containing at minimum a "type"
-- member with the appropriate action.  A nil return causes the default
-- behavior of executing a secure click on the target.
function MenuFrame:GetTargetClickAction(target)
    local params = self.targets[target]
    return params and params.click_action
end

-- Return whether directional pad inputs should be passed directly to this
-- frame when the given target (which may be nil) is selected.
function MenuFrame:IsTargetDPadOverride(target)
    local params = target and self.targets[target]
    return params and params.dpad_override
end

-- Return the bounding box for a target.  Normally equivalent to
-- GetTargetFrame(target):GetRect(), but can be overridden to deal with
-- targets whose frame sizes don't match their visuals.
function MenuFrame:GetTargetRect(target)
    local frame = self:GetTargetFrame(target)
    if not frame then return nil end
    return frame:GetRect()
end

-- Return the effective render scale for a target.  Normally equivalent to
-- GetTargetFrame(target):GetEffectiveScale().
function MenuFrame:GetTargetEffectiveScale(target)
    local frame = self:GetTargetFrame(target)
    if not frame then return nil end
    return frame:GetEffectiveScale()
end

-- Return the position (relative to the cursor's parent frame, usually
-- UIParent) at which the cursor should be displayed for the given target.
function MenuFrame:GetTargetPosition(target)
    local params = self.targets[target]
    if not params then return end
    local frame = self:GetTargetFrame(target)
    if not frame then return end
    local x = (params and params.x_rightalign) and frame:GetRight()
                                               or frame:GetLeft()
    local _, y = frame:GetCenter()
    if not x or not y then return end
    local scale = (frame:GetEffectiveScale()
                   / global_cursor:GetParent():GetEffectiveScale())
    x = (x + (params.x_offset or 0)) * scale
    y = (y + (params.y_offset or 0)) * scale
    return x, y
end

-- Return the cursor display type for the given target.
function MenuFrame:GetTargetCursorType(target)
    local params = self.targets[target]
    return params and params.cursor_type
end

-- Return the next target in the given direction from the given target,
-- or nil to indicate no next target.  If target is nil, instead return
-- the target for a cursor input of the given direction when nothing is
-- targeted.  dir gives the direction, one of the strings "up", "down",
-- "left", or "right".
function MenuFrame:NextTarget(target, dir)
    if not target then
        return self:GetDefaultTarget()
    end

    local params = self.targets[target]
    local explicit_next = params[dir]
    if explicit_next ~= nil then
        -- A value of false indicates "suppress movement in this direction".
        -- We have to use false and not nil because Lua can't distinguish
        -- between "key in table with nil value" and "key not in table".
        return explicit_next or nil
    end

    local global_scale = global_cursor:GetParent():GetEffectiveScale()
    local cur_x0, cur_y0, cur_w, cur_h = self:GetTargetRect(target)
    local cur_scale = self:GetTargetEffectiveScale(target) / global_scale
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
            local f_x0, f_y0, f_w, f_h = self:GetTargetRect(frame)
            local scale = self:GetTargetEffectiveScale(frame) / global_scale
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
                frame_dx = f_x0 - cur_x0
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

-- Perform any scrolling operations necessary to ensure that the given
-- target is visible.
function MenuFrame:ScrollToTarget(target)
    local params = self.targets[target]
    assert(params)

    if not params.suppress_scroll then
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
    end
end

-- Perform all actions appropriate to the cursor entering a target.
function MenuFrame:EnterTarget(target)
    local params = self.targets[target]
    assert(params)

    self:ScrollToTarget(target)

    local frame = self:GetTargetFrame(target)
    assert(frame)  -- May not hold until after we've scrolled above.
    if params.lock_highlight then
        frame:LockHighlight()
    end
    if params.send_enter_leave then
        local script = frame:GetScript("OnEnter")
        if script then
            script(frame)
            --WoWXIV.ReplaceGameTooltip(script, frame)
        end
    elseif params.on_enter then
        params.on_enter(target)
    end
end

-- Perform all actions appropriate to the cursor leaving a target.
function MenuFrame:LeaveTarget(target)
    local params = self.targets[target]
    assert(params, "Target is not defined: "..tostring(target))
    local frame = self:GetTargetFrame(target)
    if not frame then return end  -- Ignore deleted scroll items.
    if params.lock_highlight then
        frame:UnlockHighlight()
    end
    if params.send_enter_leave then
        local script = frame:GetScript("OnLeave")
        if script then
            script(frame)
            --WoWXIV.ReplaceGameTooltip(script, frame)
        end
    elseif params.on_leave then
        params.on_leave(target)
    end
end


-------- Cursor callbacks (can be overridden by specializations if needed)

-- Per-frame update handler.  Receives the frame associated with the
-- current target (which may be different from the targets[] key itself)
-- and the current time step (delta-t).  This method is only called when
-- the cursor is visible.
--
-- Specializations using RunUnderLock() must be sure to call down to
-- this method in any overriding implementation.
function MenuFrame:OnUpdate(target_frame, dt)
    if self.lock_coroutine then
        local has_focus = self:HasFocus()
        local status
        if not has_focus then
            status = MenuFrame.RUNUNDERLOCK_ABORT
        elseif global_cursor:IsPendingCancel() then
            status = MenuFrame.RUNUNDERLOCK_CANCEL
        else
            status = MenuFrame.RUNUNDERLOCK_CONTINUE
        end
        local noerror, running = coroutine.resume(self.lock_coroutine, status)
        if not noerror or not running then
            self.lock_coroutine = nil
            self:UnlockCursor()
            if not noerror then
                local error_text = running
                error(error_text)
            end
        elseif not has_focus and running then
            -- Cursor was already unlocked by the loss of focus.
            self.lock_coroutine = nil
            error("Aborted coroutine did not complete immediately")
        end
    end
end

-- Focus-in event handler.  Called when the frame receives focus,
-- immediately before EnterTarget() is called for the current target (if any).
function MenuFrame:OnFocus()
end

-- Focus-out event handler.  Called when the frame loses focus,
-- immediately after LeaveTarget() is called for the current target (if any).
function MenuFrame:OnUnfocus()
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

-- Callback for additional menu action button presses.  button gives the
-- button name ("Button3" or "Button4").
function MenuFrame:OnAction(button)
    -- No-op by default.
end

-- Callback for cursor movement events.  Called immediately after the
-- new target has been set as active.
function MenuFrame:OnMove(old_target, new_target)
    -- No-op by default.
end

-- Callback for D-pad input when a target is overriding it.  dir gives the
-- direction, one of the strings "up", "down", "left", or "right".
function MenuFrame:OnDPad(dir)
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
        global_cursor:RegisterFrameEvent(
            function() class:OnAddOnLoaded(addon) end, "ADDON_LOADED", addon)
    end
end

-- Register an instance method as an event handler with the global cursor
-- instance.  If handler_method is omitted, the method named the same as
-- the event and optional argument (in the same style as Cursor:OnEvent())
-- is taken as the handler method,  Wraps Cursor:RegisterFrameEvent().
function MenuFrame:RegisterEvent(handler, event, event_arg)
    if type(handler) ~= "function" then
        assert(type(handler) == "string",
               "Invalid arguments: cursor, [handler_method,] event [, event_arg]")
        event, event_arg = handler, event
        handler = self[event]
        assert(handler, "Handler method is not defined")
    end
    global_cursor:RegisterFrameEvent(function(...) handler(self, ...) end,
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

-- Install a tab-switch handler for the frame which uses the given
-- TabSystem instance to control tab switching.
function MenuFrame:SetTabSystem(tab_system)
    self.tab_handler = function(direction)
        local new_tab, first_tab, stop_next
        local i = 1
        while true do
            local tab = tab_system:GetTabButton(i)
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
            tab_system:SetTab(new_tab:GetTabID())
        end
    end
end

-- Enable cursor input for this frame, and set it as the input focus.  If
-- initial_target is not nil, the cursor target will be set to that target.
function MenuFrame:Enable(initial_target)
    global_cursor:AddFrame(self, self.modal, initial_target, true)
end

-- Enable cursor input for this frame, but do not set it as the input focus.
-- If initial_target is not nil, the frame's current cursor target will be
-- set to that target.
function MenuFrame:EnableBackground(initial_target)
    global_cursor:AddFrame(self, self.modal, initial_target, false)
end

-- Disable cursor input for this frame.
function MenuFrame:Disable()
    global_cursor:RemoveFrame(self)
end

-- Return whether this frame has cursor input enabled, regardless of
-- whether it has the input focus.
function MenuFrame:IsEnabled()
    return global_cursor:HasFrame(self)
end

-- Move this frame to the top of the input focus stack.  If the frame is
-- not in the focus stack, it is newly added.  Equivalent to Enable(nil);
-- provided for semantic clarity.
function MenuFrame:Focus()
    self:Enable(nil)
end

-- Remove input focus from this frame, but leave it enabled for input.
-- If the frame currently has input focus, it remains at the top of the
-- input stack so a subsequent cycle-focus action will immediately focus it.
-- Does nothing if the frame does not currently have input focus.
function MenuFrame:Unfocus()
    if global_cursor:GetFocus() == self then
        global_cursor:SetFocus(nil)
    end
end

-- Return whether this frame currently has input focus.
function MenuFrame:HasFocus()
    return global_cursor:GetFocus() == self
end

-- Lock the cursor's focus to this frame.  See notes at Cursor:Lock() for
-- behavior details, and see RunUnderLock() for a higher-level interface
-- which manages locking around a coroutine.
function MenuFrame:LockCursor()
    global_cursor:Lock(self)
end

-- Release a cursor lock previously taken with LockCursor().
function MenuFrame:UnlockCursor()
    global_cursor:Unlock(self)
end

-- Lock the cursor for the execution of the given function.  The function
-- must be written as a coroutine, and should yield(true) to wait before
-- completion; any return values will be ignored, and the cursor will be
-- unlocked after the function returns.  Only one function at a time may
-- be run using this interface.
--
-- When the function resumes from a yield, it will be passed one of the
-- following values indicating whether the function should continue
-- processing:
--     MenuFrame.RUNUNDERLOCK_CONTINUE: Processing may continue normally.
--     MenuFrame.RUNUNDERLOCK_CANCEL: The user pressed the cancel button;
--         the function should end processing as soon as feasible.
--     MenuFrame.RUNUNDERLOCK_ABORT: The frame lost input focus (such as
--         because it waqs hidden); the function must return immediately.
-- Particularly in the case of RUNUNDERLOCK_ABORT, the function will not
-- be resumed even if it attempts to resume again (a Lua error will be
-- raised in this case).
--
-- This method will perform an initial call to the function; if the
-- function completes immediately (returning false), no locking will be
-- performed.  Any additional arguments to this method will be passed as
-- arguments to the function on this initial call.
--
-- Note that this interface relies on the MenuFrame.OnUpdate()
-- implementation; a subclass which overrides this method must be sure to
-- call down to MenuFrame.OnUpdate().
function MenuFrame:RunUnderLock(func, ...)
    assert(not self.lock_coroutine)
    local co = coroutine.create(func)
    local noerror, running = coroutine.resume(co, ...)
    if not noerror or not running then
        if not noerror then
            local error_text = running
            error(error_text)
        end
        return  -- Function returned immediately, nothing else to do.
    end
    self:LockCursor()
    self.lock_coroutine = co
    -- Coroutine will be resumed at the next OnUpdate() call.
end
MenuFrame.RUNUNDERLOCK_CONTINUE = 0
MenuFrame.RUNUNDERLOCK_CANCEL = 1
MenuFrame.RUNUNDERLOCK_ABORT = 2

-- Return the current cursor target for this frame, or nil if the frame has
-- not been enabled for cursor input.
function MenuFrame:GetTarget()
    return global_cursor:GetTargetForFrame(self)
end

-- Set the cursor target for this frame to the given target.  Does nothing
-- if the frame has not been enabled for cursor input.
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

-- Update cursor state.  Cursor updates are normally handled automatically,
-- but this method should be called if input assignments (cancel_button,
-- has_Button*) are changed without any cursor movement.
function MenuFrame:UpdateCursor(target)
    if global_cursor:GetFocus() == self then
        global_cursor:UpdateCursor()
    end
end


-------- Target list management methods

-- Add elements from a ScrollBox as frame targets, returning the topmost
-- and bottommost of the added targets (both nil if no targets were added).
-- The elements are assumed to be in a single column.
--
-- |filter| is a function which receives an element's data value and
-- element index, and returns either a target attribute table, which causes
-- the element to be included as a cursor target, or nil, which causes the
-- element to be omitted.  For included elements, the attribute
-- is_scroll_box=true will automatically be added to the target attribute
-- table, along with appropriate up and down attributes to enable proper
-- cursor movement.  By default, the top element's "up" attribute will
-- point to the bottom element and vice versa, so cursor movement wraps
-- around; the caller is responsible for changing these attributes if
-- different movement behavior is desired.
--
-- The filter function may optionally return a second value, which if true
-- indicates that the associated target should be returned as a third
-- return value from this method.  For example, this can be used to select
-- a particular element as the cursor target without setting it as the
-- default or storing a custom attribute which is only used to later find
-- the associated target.  Only one additional target can be returned in
-- this way; if multiple targets are indicated by the filter function, the
-- last of them is returned.
--
-- foreach_override should normally be nil; it can be used to provide a
-- replacement for scrollbox:ForEachElementData() if the scroll box's
-- data provider does not implement a ForEach() method (such as for the
-- auction house browse result list).
function MenuFrame:AddScrollBoxTargets(scrollbox, filter, foreach_override)
    -- Avoid errors in Blizzard code if the list is empty.
    if not scrollbox:GetDataProvider() then return end
    local top, bottom, other
    local index = 0
    local function ProcessElement(data)
        index = index + 1
        local attributes, is_other = filter(data, index)
        if attributes then
            local pseudo_frame =
                MenuFrame.PseudoFrameForScrollElement(scrollbox, index)
            attributes.is_scroll_box = true
            if bottom then
                self.targets[bottom].down = pseudo_frame
                attributes.up = bottom
            end
            self.targets[pseudo_frame] = attributes
            top = top or pseudo_frame
            bottom = pseudo_frame
            if is_other then other = pseudo_frame end
        end
    end
    if foreach_override then
        foreach_override(ProcessElement)
    else
        scrollbox:ForEachElementData(ProcessElement)
    end
    if top then
        self.targets[top].up = bottom
        self.targets[bottom].down = top
    end
    return top, bottom, other
end

-- Add widgets in the given WidgetContainer whose type is one of the
-- given types (supported: "Spell", "Item", "Bar") to the given target list.
-- |{up,down,left,right}_target| give the targets immediately in each
-- direction relative to the widget container, and can be nil for default
-- movement rules.
function MenuFrame:AddWidgetTargets(container, widget_types,
                                    up_target, down_target,
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
                self.targets[f] = {
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
                    local params = self.targets[f]
                    if params then
                        params.down = first
                    end
                end
            end
            last_y = y
            top_first = top_first or first
            bottom_first = first
            self.targets[first].left = left_target
            self.targets[last].right = right_target
        end
    end
    self.targets[up_target].down = top_first
    self.targets[down_target].up = bottom_first
end


-------- Other utility functions (these are all MenuFrame class methods)

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

-- Generic on_click handler which converts a click action into an
-- OnMouseDown("LeftButton",true) event followed by an
-- OnMouseUp("LeftButton") event for the button.
function MenuFrame.ClickToMouseDown(frame)
    local down = frame:GetScript("OnMouseDown")
    if down then down(frame, "LeftButton", true) end
    local up = frame:GetScript("OnMouseUp")
    if up then up(frame, "LeftButton") end
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

-- Return a MenuFrame and initial cursor target for a dropdown menu using
-- the builtin DropdownButtonMixin.  Pass four arguments:
--     dropdown: Dropdown button (a Button frame).
--     cache: Table in which already-created MenuFrames will be cached.
--     getIndex: Function to return the 1-based option index of a
--         selection (as returned by the menu's CollectSelectionData()
--         method).  If omitted, the cursor will always default to the
--         first item in the dropdown list.
--     onClick: Function to be called after an option is clicked.  May be
--         omitted.
function MenuFrame.SetupDropdownMenu(dropdown, cache, getIndex, onClick)
    local menu = dropdown.menu
    local menu_manager = cache[menu]
    if not menu_manager then
        menu_manager = MenuFrame(menu)
        menu_manager.cancel_func = function() dropdown:CloseMenu() end
        cache[menu] = menu_manager
        hooksecurefunc(menu, "Hide", function() menu_manager:Disable() end)
    end
    menu_manager.targets = {}
    menu_manager.item_order = {}
    -- FIXME: we may need to dig deeper into this; GetLayoutChildren()
    -- works for the delve NPC role dropdown and the 11.0.2 delve
    -- difficulty dropdown, but stopped working for the latter in 11.0.5
    -- (for which we iterate over the scroll box children instead)
    local items = menu:GetLayoutChildren()
    if #items > 0 then
        local function OnClickDropdownItem(button)
            button:GetScript("OnClick")(button, "LeftButton", true)
            if onClick then onClick() end
        end
        local is_first = true
        for _, button in ipairs(items) do
            if button:GetObjectType() == "Button" then
                menu_manager.targets[button] = {
                    send_enter_leave = true, on_click = OnClickDropdownItem,
                    is_default = is_first,
                }
                is_first = false
                -- FIXME: are buttons guaranteed to be in order?
                tinsert(menu_manager.item_order, button)
            end
        end
    elseif menu.ScrollBox then
        local function OnEnterDropdownItem(pseudo_frame)
            local button = pseudo_frame.button
            button:GetScript("OnEnter")(button)
        end
        local function OnLeaveDropdownItem(pseudo_frame)
            local button = pseudo_frame.button
            button:GetScript("OnLeave")(button)
        end
        local function OnClickDropdownItem(pseudo_frame)
            local button = pseudo_frame.button
            button:GetScript("OnClick")(button, "LeftButton", true)
            if onClick then onClick() end
        end
        -- Despite the "ForEachElementData" name, in this case the method
        -- iterates over actual Button elements, so it's a bit too awkward
        -- to call AddScrollBoxTargets() and we reimplement the logic here.
        local index = 0
        local last
        menu.ScrollBox:ForEachElementData(function(element)
            index = index + 1
            local pseudo_frame =
                MenuFrame.PseudoFrameForScrollElement(menu.ScrollBox, index)
            pseudo_frame.button = element
            local attributes = {
                is_scroll_box = true, is_default = (index == 1),
                on_enter = OnEnterDropdownItem, on_leave = OnLeaveDropdownItem,
                on_click = OnClickDropdownItem}
            if last then
                menu_manager.targets[last].down = pseudo_frame
                attributes.up = last
            end
            menu_manager.targets[pseudo_frame] = attributes
            last = pseudo_frame
            tinsert(menu_manager.item_order, pseudo_frame)
        end)
    end
    local first = menu_manager.item_order[1]
    local last = menu_manager.item_order[#menu_manager.item_order]
    menu_manager.targets[first].up = last
    menu_manager.targets[last].down = first
    -- Note that DropdownButtonMixin provides a GetSelectionData(), but it
    -- returns the wrong data!  It's not called from any other Blizzard code,
    -- so presumably it never got updated during a refactor or similar.
    local selection = select(3, dropdown:CollectSelectionData())
    local index = selection and getIndex and getIndex(selection[1])
    local initial_target = index and menu_manager.item_order[index]
    return menu_manager, initial_target
end


---------------------------------------------------------------------------
-- MenuFrame subclasses for common patterns
---------------------------------------------------------------------------

--[[
    MenuFrame subclass for handling a standard menu-style frame.  Includes
    OnShow/OnHide handlers which respectively call Enable() and Disable(),
    and a default cancel_func of MenuFrame.CancelUIFrame.  The frame itself
    is hooked with HookShow() by the constructor.

    As with the base MenuFrame, StandardMenuFrame supports a nil frame
    reference to allow one instance to handle multiple frames; in this
    case, the instance is responsible for both hooking the necessary
    frames and setting self.frame to the proper value before calling
    StandardMenuFrame.OnShow().

    If the instance defines a SetTargets() method, it will be called by
    OnShow() and its return value will be used as the initial target to
    pass to Enable().  If the method returns false (as opposed to nil),
    the OnShow event will instead be ignored.

    OnShow() will ignore any show events sent while a parent frame is
    hidden.
]]--
MenuCursor.StandardMenuFrame = class(MenuFrame)
local StandardMenuFrame = MenuCursor.StandardMenuFrame

function StandardMenuFrame:__constructor(frame, modal)
    self:__super(frame, modal)
    if frame then self:HookShow(frame) end
    self.cancel_func = MenuFrame.CancelUIFrame
end

function StandardMenuFrame:OnShow()
    if not self.frame:IsVisible() then return end
    local initial_target = self.SetTargets and self:SetTargets()
    if initial_target ~= false then
        self:Enable(initial_target)
    end
end

function StandardMenuFrame:OnHide()
    self:Disable()
end


--[[
    StandardMenuFrame subclass for handling a core frame (one which is
    initialized by core game code before any addons are loaded).
    A singleton instance for the (presumed also singleton) managed frame
    will be created and stored in class.instance by the default Initialize()
    implementation, and the global cursor instance will be stored in
    class.cursor.  No other default methods reference these values; they
    are provided for subclasses' convenience, and overriding methods do not
    need to initialize them if they are not needed.
]]--
MenuCursor.CoreMenuFrame = class(StandardMenuFrame)
local CoreMenuFrame = MenuCursor.CoreMenuFrame

function CoreMenuFrame.Initialize(class, cursor)
    class.cursor = cursor
    class.instance = class()
end


--[[
    StandardMenuFrame subclass for handling an addon frame (one which is
    not available until a specific addon has been loaded).  Similar to
    CoreMenuFrame, but instead of creating the frame manager instance in
    Initialize(), the Initialize() method sets up an addon watch for the
    addon named by class.ADDON_NAME (which must be declared by the subclass
    at the time Cursor.RegisterFrameHandler() is called) and creates the
    singleton instance in the method OnAddOnLoaded() (which may be
    overridden by the subclass if needed).

    Note that only one class may establish a load handler for any given
    addon.  To handle multiple frames managed by the same addon, inherit
    this class for one handler and have it create instances for the other
    frames.  See the PlayerChoiceFrame handler for an example.
]]--
MenuCursor.AddOnMenuFrame = class(StandardMenuFrame)
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

function AddOnMenuFrame.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch(class.ADDON_NAME)
end

function AddOnMenuFrame.OnAddOnLoaded(class)
    class.instance = class()
end


---------------------------------------------------------------------------
-- Utility class for numeric input
---------------------------------------------------------------------------

--[[
    Class implementing a gamepad-controlled numeric input field.
    Pass the associated input frame, which must be an EditBox, to the
    constructor.  Optionally also pass a callback to be called whenever
    the input value is changed during editing.
]]--
MenuCursor.NumberInput = class(StandardMenuFrame)
local NumberInput = MenuCursor.NumberInput

function NumberInput:__constructor(editbox, on_change)
    assert(type(editbox) == "table")
    -- Special case for StackSplitFrame, which uses a nonstandard input box.
    self.is_StackSplitText = (editbox == StackSplitFrame.StackSplitText)
    assert(self.is_StackSplitText or editbox:GetObjectType() == "EditBox")
    self.editbox = editbox
    self.on_change = on_change

    -- Value (text string) of the EditBox when editing was started.
    self.old_value = nil
    -- Saved alpha value of edit box text color.
    self.edittext_alpha = nil
    -- Current input value (numeric).
    self.value = nil
    -- Current digit position being edited (0 = units place, 1 = tens, etc).
    self.pos = nil

    local function Cancel()
        self:CancelEdit()
    end
    hooksecurefunc(self.is_StackSplitText and StackSplitFrame or editbox,
                   "Hide", Cancel)

    local f = CreateFrame("Frame")
    self:__super(f, MenuFrame.MODAL)
    self.cancel_func = Cancel
    f:Hide()
    f:SetFrameStrata("TOOLTIP") -- Make sure it's visible above other elements.
    if self.is_StackSplitText then
        f:SetScale(UIParent:GetEffectiveScale()*0.64)
        f:SetPoint("TOPRIGHT", editbox)
        f:SetPoint("BOTTOMRIGHT", editbox)
        f:SetWidth(72)
    else
        f:SetScale(editbox:GetEffectiveScale())
        -- Don't overlap the money icon in money input boxes (esp. silver).
        local parent = editbox:GetParent()
        if editbox == parent.GoldBox or editbox == parent.SilverBox then
            f:SetPoint("LEFT", editbox, "LEFT", 10, 0)
            f:SetPoint("TOPRIGHT", editbox.Icon, "TOPLEFT", -3, 0)
            f:SetPoint("BOTTOMRIGHT", editbox.Icon, "BOTTOMLEFT", -3, 0)
        else
            f:SetAllPoints(editbox)
        end
    end

    local label = f:CreateFontString(nil, "ARTWORK")
    self.label = label
    label:SetAllPoints(f)
    label:SetTextColor(0.6, 1, 0.45)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")

    self.targets = {[f] = {is_default = true, dpad_override = true,
                           on_click = function() self:ConfirmEdit() end}}
end

-- Set the rendering scale factor for the input text.  Useful when the
-- default size doesn't match the size of the original InputBox text.
function NumberInput:SetTextScale(scale)
    self.label:SetTextScale(scale)
end

-- Start editing.  This grabs the menu cursor focus; focus will be returned
-- when editing is complete, and the edit box's value will be set to the
-- value entered.  Focus will also be returned if the underlying EditBox is
-- hidden or CancelEdit() is called, in which case the previous value of
-- the EditBox will be restored.  Pass the minimum (must be 0 or 1) and
-- maximum limits for the value to be entered.
function NumberInput:Edit(value_min, value_max)
    assert(not self:HasFocus())
    assert(value_min == 0 or value_min == 1)
    assert(value_max and value_max >= value_min)

    local editbox = self.editbox
    assert(editbox:IsShown())
    local old_value = editbox:GetText()
    assert(old_value)

    local r, g, b, a = editbox:GetTextColor()
    self.edittext_alpha = a
    editbox:SetTextColor(r, g, b, 0)
    self.label:SetFont(editbox:GetFont())
    self.old_value = old_value
    self.value = tonumber(old_value) or value_min
    self.value_min = value_min
    self.value_max = value_max
    self.pos = 0
    self:UpdateLabel()
    self.frame:Show()
end

-- Confirm the in-progress edit and relinquish cursor focus.  Normally
-- called on a confirm button press.
function NumberInput:ConfirmEdit()
    if self.frame:IsShown() then
        self.frame:Hide()  -- Implicitly releases focus via OnHide().
        local editbox = self.editbox
        local r, g, b = editbox:GetTextColor()
        editbox:SetTextColor(r, g, b, self.edittext_alpha)
        self:SetEditBoxText(tostring(self.value))
    end
end

-- Cancel any edit in progress, and restore the previous value of the
-- associated EditBox.
function NumberInput:CancelEdit()
    if self.frame:IsShown() then
        self.frame:Hide()
        local editbox = self.editbox
        local r, g, b = editbox:GetTextColor()
        editbox:SetTextColor(r, g, b, self.edittext_alpha)
        self:SetEditBoxText(self.old_value)
    end
end

function NumberInput:OnDPad(dir)
    local value = self.value
    local pos = self.pos
    local value_min = self.value_min
    local value_max = self.value_max
    local unit = 10^pos

    if dir == "up" then
        if value >= value_max then
            value = value_min
        else
            value = value + unit
            if value > value_max then value = value_max end
        end
    elseif dir == "down" then
        if value <= value_min then
            value = value_max
        else
            value = value - unit
            if value < value_min then value = value_min end
        end
    elseif dir == "left" then
        if unit*10 <= value_max then
            pos = pos + 1
        else
            value = value_max
        end
    else assert(dir == "right")
        if pos > 0 then
            pos = pos - 1
        else
            value = value_min
        end
    end

    self.value = value
    self.pos = pos
    self:UpdateLabel()
    self:SetEditBoxText(tostring(value))
end

function NumberInput:UpdateLabel()
    local text = tostring(self.value)
    local pos = self.pos
    while pos >= #text do
        text = "0"..text
    end
    local digit = #text - pos
    text = (strsub(text, 1, digit-1)
            .. FormatColoredText(strsub(text, digit, digit), 1, 0.75, 0.3)
            .. strsub(text, digit+1))
    self.label:SetText(text)
end

-- Takes care of also calling the on-change callback, if any.
function NumberInput:SetEditBoxText(text)
    self.editbox:SetText(text)
    if self.on_change then self.on_change() end
end
