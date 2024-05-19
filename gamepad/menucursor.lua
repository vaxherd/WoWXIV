local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
local Gamepad = WoWXIV.Gamepad

local class = WoWXIV.class

local GameTooltip = GameTooltip
local function round(x) return math.floor(x+0.5) end

------------------------------------------------------------------------
-- Core implementation
------------------------------------------------------------------------

Gamepad.MenuCursor = class()
local MenuCursor = Gamepad.MenuCursor

function MenuCursor:__constructor()
    -- Is the player currently using gamepad input?  (Mirrors the
    -- GAME_PAD_ACTIVE_CHANGED event.)
    self.gamepad_active = false
    -- Frame which currently has the cursor's input focus, nil if none.
    self.focus = nil
    -- Stack of saved focus frames, used with PushFocus() and PopFocus().
    self.focus_stack = {}

    -- The following are only used when self.focus is not nil:

    -- List of subframes which are valid targets for cursor movement.
    self.targets = nil
    -- Subframe which the cursor is currently targeting.
    self.cur_target = nil
    -- Last targeted subframe, used when the cursor is temporarily hidden
    -- (such as due to mouse movement).
    self.saved_target = nil
    -- Function to call when the cancel button is pressed (receives self
    -- as an argument).  If nil, no action is taken.
    self.cancel_func = nil
    -- Subframe (button) to be clicked on a gamepad cancel button press,
    -- or nil for none.  If set, cancel_func is ignored.
    self.cancel_button = nil
    -- Should the current button be highlighted if enabled?
    -- (This is a cache of the current button's lock_highlight parameter.)
    self.want_highlight = true
    -- Is the current button highlighted via lock_highlight?
    -- (This is a cache to avoid unnecessary repeated calls to the
    -- button's LockHighlight() method in OnUpdate().)
    self.highlight_locked = false

    -- This is a SecureActionButtonTemplate only so that we can
    -- indirectly click the button pointed to by the cursor.
    local f = CreateFrame("Button", "WoWXIV_MenuCursor", UIParent,
                          "SecureActionButtonTemplate")
    self.frame = f
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

-- Set the focus frame to the given frame.  Any previous focus frame is
-- cleared.
function MenuCursor:SetFocus(frame)
    if self.focus then
        self:ClearFocus()
    end
    self.focus = frame
    self.cur_target = nil
    self.saved_target = nil
    self.cancel_func = nil
    self.cancel_button = nil
    self.want_highlight = false
    self.highlight_locked = false
end

-- Clear any current focus frame, hiding the menu cursor if it is displayed.
function MenuCursor:ClearFocus()
    self:SetTarget(nil)
    self.focus = nil
end

-- Set the focus frame to the given frame, saving the current focus frame
-- state so that it will be restored on a call to PopFocus().
function MenuCursor:PushFocus(frame)
    if self.focus then
        local focus_state = {
            frame = self.focus, 
            targets = self.targets,
            cur_target = self.cur_target,
            saved_target = self.saved_target,
            cancel_func = self.cancel_func,
            cancel_button = self.cancel_button,
        }
        tinsert(self.focus_stack, focus_state)
        self:SetTarget(nil)  -- clear current button's highlight/tooltip
    end
    self:SetFocus(frame)
end

-- Pop the given frame from the focus stack, if it exists in the stack.
-- If the frame is the top frame, the previous focus state is restored.
-- If the frame is in the stack but not on top (such as if multiple
-- frames are hidden at once but not in the reverse order of being shown),
-- it is removed from the stack but the focus state remains unchanged.
function MenuCursor:PopFocus(frame)
    if self.focus == frame then
        if #self.focus_stack > 0 then
            self:SetTarget(nil)
            local focus_state = tremove(self.focus_stack)
            self.focus = focus_state.frame
            self.targets = focus_state.targets
            self.saved_target = focus_state.saved_target
            self.cancel_func = focus_state.cancel_func
            self.cancel_button = focus_state.cancel_button
            self:SetTarget(focus_state.cur_target)
        else
            self:ClearFocus()
        end
        self:UpdateCursor()
    else
        for i, focus_state in ipairs(self.focus_stack) do
            if focus_state.frame == frame then
                tremove(self.focus_stack, i)
                break
            end
        end
    end
end

-- Set the menu cursor target.  If nil, clears the current target.
-- Handles all enter/leave interactions with the new and previous targets.
function MenuCursor:SetTarget(target)
    local old_target = self.cur_target
    if old_target then
        local params = self.targets[old_target]
        if params.lock_highlight then
            -- We could theoretically check highlight_locked here, but
            -- it should be safe to unconditionally unlock (we take the
            -- lock_highlight parameter as an indication that we have
            -- exclusive control over the highlight lock).
            old_target:UnlockHighlight()
        end
        if params.send_enter_leave then
            old_target:OnLeave()
        end
        if params.set_tooltip then
            if not GameTooltip:IsForbidden() then
                GameTooltip:Hide()
            end
        end
    end

    self.cur_target = target
    self.want_highlight = false
    self.highlight_locked = false
    if target then
        local params = self.targets[target]
        if params.lock_highlight then
            self.want_highlight = true
            if target:IsEnabled() then
                self.highlight_locked = true
                target:LockHighlight()
            end
        end
        if params.send_enter_leave then
            target:OnEnter()
        end
        if params.set_tooltip then
            if not GameTooltip:IsForbidden() then
                self.targets[target].set_tooltip(target)
            end
        end
    end
end

-- Update the display state of the cursor.
function MenuCursor:UpdateCursor(in_combat)
    if in_combat == nil then
        in_combat = InCombatLockdown()
    end
    local f = self.frame

    if self.focus and not self.focus:IsVisible() then
        self:ClearFocus()
    end

    local target = self.cur_target
    if self.focus and self.gamepad_active and not in_combat then
        if not target then
            if self.saved_target then
                target = self.saved_target
            else
                for frame, params in pairs(self.targets) do
                    if params.is_default then
                        target = frame
                        break
                    end
                end
                if not target then
                    error("MenuCursor: no default target")
                    -- We make this a fatal error for now, but it would be
                    -- less intrusive to fall back to an arbitrary target,
                    -- hence we leave in this (currently unreachable) line.
                    target = next(self.targets)
                end
            end
            self:SetTarget(target)
        end
        self:SetCursorPoint(target)
        if self.targets[target].can_activate then
            f:SetAttribute("clickbutton1", target)
        else
            f:SetAttribute("clickbutton1", nil)
        end
        if self.cancel_button then
            f:SetAttribute("clickbutton2", self.cancel_button)
        else
            f:SetAttribute("clickbutton2", nil)
        end
        if not f:IsShown() then
            f:Show()
            f:SetScript("OnUpdate", function() self:OnUpdate() end)
            self:OnUpdate()
        else
            self:SetCancelBinding()
        end
    else
        if self.cur_target then
            self.saved_target = self.cur_target
            self:SetTarget(nil)
        end
        if f:IsShown() then  -- avoid unnecessary taint warnings
            f:Hide()
        end
        f:SetScript("OnUpdate", nil)
    end
end

-- Per-frame update routine which implements cursor bouncing.
function MenuCursor:OnUpdate()
    local target = self.cur_target

    --[[
         Calling out to fetch the target's position and resetting the
         cursor anchor points every frame is not ideal, but we need to
         keep the cursor position updated when buttons change positions,
         such as:
            - Scrolling of gossip/quest text
            - BfA troop recruit frame on first open after /reload
            - Upgrade confirmation dialog for Shadowlands covenant sanctum
    ]]--
    self:SetCursorPoint(target)

    local t = GetTime()
    t = t - math.floor(t)
    local xofs = -4 * math.sin(t * math.pi)
    self.texture:ClearPointsOffset()
    self.texture:AdjustPointsOffset(xofs, 0)

    if self.want_highlight and not self.highlight_locked then
        -- The button was previously disabled.  See if it is now enabled,
        -- such as in the Revival Catalyst confirmation dialog after the
        -- 5-second delay ends.  (The reverse case of an enabled button
        -- being disabled is also theoretically possible, but we ignore
        -- that case pending evidence that it can occur in practice.)
        if target:IsEnabled() then
            self.highlight_locked = true
            target:LockHighlight()
        end
    end
end

-- Helper for UpdateCursor() and OnUpdate() to set the cursor frame anchor.
function MenuCursor:SetCursorPoint(target)
    local f = self.frame
    f:ClearAllPoints()
    -- Work around frame reference limitations on secure buttons
    --f:SetPoint("TOPRIGHT", target, "LEFT")
    local x = target:GetLeft()
    local _, y = target:GetCenter()
    f:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", x, y-UIParent:GetHeight())
end

-- Show() handler; activates menu cursor input bindings.
function MenuCursor:OnShow()
    local f = self.frame
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
    self:SetCancelBinding()
end

-- Hide() handler; clears menu cursor input bindings.
function MenuCursor:OnHide()
    ClearOverrideBindings(self.frame)
end

-- Helper for UpdateCursor() and OnShow() to set the cancel button binding
-- for the current cursor target depending on whether it needs to be
-- securely passed through to the target.
function MenuCursor:SetCancelBinding()
    local f = self.frame
    if self.cancel_button then
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
        -- This code is called afterward, so it's possible that the target
        -- already closed our focus frame; avoid erroring in that case.
        if self.focus then
            local params = self.targets[self.cur_target]
            if params.on_click then params.on_click(self.cur_target) end
        end
    elseif button == "Cancel" then
        if self.cancel_func then
            self:cancel_func()
        end
        self:UpdateCursor()
    end
end

-- OnClick() helper which moves the cursor in the given direction.
-- dx and dy give the movement direction with respect to screen
-- coordinates (with WoW's usual "+Y = up" mapping); dir gives the
-- direction keyword for checking target-specific movement overrides.
function MenuCursor:Move(dx, dy, dir)
    local cur_target = self.cur_target
    local params = self.targets[cur_target]
    if params[dir] ~= nil then
        -- A value of false indicates "suppress movement in this
        -- direction".  We have to use false and not nil because
        -- Lua can't distinguish between "key in table with nil value"
        -- and "key not in table".
        new_target = params[dir]
    else
        new_target = self:NextTarget(dx, dy)
    end
    if new_target then
        local scroll_frame = self.targets[new_target].scroll_frame
        if scroll_frame then
            local scroll_top = -(scroll_frame:GetTop())
            local scroll_bottom = -(scroll_frame:GetBottom())
            local scroll_height = scroll_bottom - scroll_top
            local top = -(new_target:GetTop()) - scroll_top
            local bottom = -(new_target:GetBottom()) - scroll_top
            local MARGIN = 20
            local scroll_target
            if top < MARGIN then
                scroll_target = MARGIN - top
            elseif bottom > scroll_height - MARGIN then
                scroll_target = bottom - (scroll_height - MARGIN)
            end
            if scroll_target then
                if scroll_target < 0 then scroll_target = 0 end
                -- SetVerticalScroll() automatically clamps to child height.
                scroll_frame:SetVerticalScroll(scroll_target)
            end
        end
        self:SetTarget(new_target)
        self:UpdateCursor()
    end
end

-- Move() helper which returns the next target in the given direction,
-- or nil if none is found.
function MenuCursor:NextTarget(dx, dy)
    local cur_x0, cur_y0, cur_w, cur_h = self.cur_target:GetRect()
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
        local f_x0, f_y0, f_w, f_h = frame:GetRect()
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
    return best
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
function MenuCursor:CancelFrame()
    local frame = self.focus
    self:ClearFocus()
    frame:Hide()
end

-- Generic cancel_func to close a UI frame.  Equivalent to CancelFrame()
-- but with calling HideUIPanel(focus) instead of focus:Hide().
function MenuCursor:CancelUIPanel()
    local frame = self.focus
    self:ClearFocus()
    HideUIPanel(frame)
end

-- Shared cancel_func used for quest frames.
function MenuCursor:CancelQuestFrame()
    self:ClearFocus()
    CloseQuest()
end

------------------------------------------------------------------------
-- Individual frame handlers
------------------------------------------------------------------------

-- All functions defined in this table will be called from the MenuCursor
-- constructor (key value is irrelevant).
MenuCursor.handlers = {}

-------- Gossip (NPC dialogue) frame

function MenuCursor.handlers.GossipFrame(cursor)
    local f = cursor.frame
    f:RegisterEvent("GOSSIP_CLOSED")
    f:RegisterEvent("GOSSIP_SHOW")
end

function MenuCursor:GOSSIP_CLOSED()
    -- This event can fire even when the gossip window was never opened
    -- (generally when a menu opens instead), so don't assume we're in
    -- gossip menu state.
    if self.focus == GossipFrame then
        self:ClearFocus()
        self:UpdateCursor()
    end
end

function MenuCursor:GOSSIP_SHOW()
    if not GossipFrame:IsVisible() then
        return  -- Flight map, etc.
    end
    self:SetFocus(GossipFrame)
    self.cancel_func = self.CancelUIPanel
    local goodbye = GossipFrame.GreetingPanel.GoodbyeButton
    self.targets = {[goodbye] = {can_activate = true,
                                 lock_highlight = true}}
    -- FIXME: This logic to find the quest / dialogue option buttons is
    -- a bit kludgey and certainly won't work if the list is scrolled
    -- to the point where some elements move offscreen.  Is there any
    -- better way to get the positions of individual scroll list elements?
    local subframes = {GossipFrame.GreetingPanel.ScrollBox.ScrollTarget:GetChildren()}
    local first_button, last_button = nil, nil
    for index, f in ipairs(subframes) do
        if f.GetElementData then
            local data = f:GetElementData()
            if (data.availableQuestButton or
                data.activeQuestButton or
                data.titleOptionButton)
            then
                self.targets[f] = {can_activate = true,
                                   lock_highlight = true}
                local y = f:GetTop()
                if not first_button then
                    first_button = f
                    last_button = f
                else
                    if y > first_button:GetTop() then first_button = f end
                    if y < last_button:GetTop() then last_button = f end
                end
            end
        end
    end
    self.targets[first_button or goodbye].is_default = true
    self:UpdateCursor()
end


-------- Quest info frame

function MenuCursor.handlers.QuestFrame(cursor)
    local f = cursor.frame
    f:RegisterEvent("QUEST_COMPLETE")
    f:RegisterEvent("QUEST_DETAIL")
    f:RegisterEvent("QUEST_FINISHED")
    f:RegisterEvent("QUEST_GREETING")
    f:RegisterEvent("QUEST_PROGRESS")
end

function MenuCursor:QUEST_GREETING()
    assert(QuestFrame:IsVisible())
    self:SetFocus(QuestFrame)
    self.cancel_func = self.CancelQuestFrame
    local goodbye = QuestFrameGreetingGoodbyeButton
    self.targets = {[goodbye] = {can_activate = true,
                                 lock_highlight = true}}
    local first_button, last_button = nil, nil
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
    end
    self.targets[first_button or goodbye].is_default = true
    self:UpdateCursor()
end

function MenuCursor:QUEST_PROGRESS()
    assert(QuestFrame:IsVisible())
    self:SetFocus(QuestFrame)
    self.cancel_func = self.CancelQuestFrame
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
        self.targets[item_frame] = {
            -- This logic is coded directly into the XML templates as
            -- part (but not all) of the OnEnter handler, so we have to
            -- reimplement it ourselves.
            set_tooltip = function()
                if GameTooltip:IsForbidden() then return end
                if item_frame.objectType == "item" then
                    GameTooltip:SetOwner(item_frame, "ANCHOR_RIGHT")
                    GameTooltip:SetQuestItem(item_frame.type, item_frame:GetID())
                    GameTooltip_ShowCompareItem(GameTooltip)
                elseif item_frame.objectType == "currency" then
                    GameTooltip:SetOwner(item_frame, "ANCHOR_RIGHT")
                    GameTooltip:SetQuestCurrency(item_frame.type, item_frame:GetID())
                end
            end,
        }
    end
    self:UpdateCursor()
end

function MenuCursor:QUEST_DETAIL()
    -- FIXME: some map-based quests (e.g. Blue Dragonflight campaign)
    -- start a quest directly from the map; we should support those too
    if not QuestFrame:IsVisible() then return end
    return self:DoQuestDetail(false)
end

function MenuCursor:QUEST_COMPLETE()
    assert(QuestFrame:IsVisible())
    return self:DoQuestDetail(true)
end

function MenuCursor:DoQuestDetail(is_complete)
    self:SetFocus(QuestFrame)
    self.cancel_func = self.CancelQuestFrame
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
    for i = 1, 99 do
        local name = "QuestInfoRewardsFrameQuestInfoItem" .. i
        local reward_frame = _G[name]
        if not reward_frame or not reward_frame:IsShown() then break end
        tinsert(rewards, {reward_frame, false})
    end
    for reward_frame in QuestInfoRewardsFrame.reputationRewardPool:EnumerateActive() do
        tinsert(rewards, {reward_frame, true})
    end
    local last_l, last_r, this_l
    for _,v in ipairs(rewards) do
        local reward_frame, is_rep = unpack(v)
        self.targets[reward_frame] = {
            up = false, down = false, left = false, right = false,
            scroll_frame = QuestDetailScrollFrame,
        }
        -- Reputation reward frames have the usual OnEnter/OnLeave
        -- handlers, but item rewards need manual handling.
        if is_rep then
            self.targets[reward_frame].send_enter_leave = true
        else
            self.targets[reward_frame].set_tooltip = function()
                QuestInfoRewardItemCodeTemplate_OnEnter(reward_frame)
            end
        end
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
    self:UpdateCursor()
end

function MenuCursor:QUEST_FINISHED()
    assert(self.focus == nil or self.focus == QuestFrame)
    self:ClearFocus()
    self:UpdateCursor()
end


-------- BfA troop recruitment frame

function MenuCursor.handlers.TroopRecruitmentFrame(cursor)
    local f = cursor.frame
    f:RegisterEvent("SHIPMENT_CRAFTER_CLOSED")
    f:RegisterEvent("SHIPMENT_CRAFTER_OPENED")
end

function MenuCursor:SHIPMENT_CRAFTER_OPENED()
    assert(GarrisonCapacitiveDisplayFrame:IsVisible())
    self:SetFocus(GarrisonCapacitiveDisplayFrame)
    self.cancel_func = self.CancelUIPanel
    self.targets = {
        [GarrisonCapacitiveDisplayFrame.CreateAllWorkOrdersButton] =
            {can_activate = true, lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.DecrementButton] =
            {can_activate = true, lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.IncrementButton] =
            {can_activate = true, lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.StartWorkOrderButton] =
            {can_activate = true, lock_highlight = true,
             is_default = true},
    }
    self:UpdateCursor()
end

function MenuCursor:SHIPMENT_CRAFTER_CLOSED()
    assert(self.focus == nil or self.focus == GarrisonCapacitiveDisplayFrame)
    self:ClearFocus()
    self:UpdateCursor()
end


-------- Shadowlands covenant sanctum frame

function MenuCursor.handlers.CovenantSanctumFrame(cursor)
    cursor.frame:RegisterEvent("ADDON_LOADED")
    if CovenantSanctumFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_CovenantSanctum")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_CovenantSanctum()
    self:HookShow(CovenantSanctumFrame, "CovenantSanctumFrame")
end

function MenuCursor:CovenantSanctumFrame_Show()
    assert(CovenantSanctumFrame:IsVisible())
    self:SetFocus(CovenantSanctumFrame)
    self.cancel_func = self.CancelFrame
    local function ChooseTalent(button)
        button:OnMouseDown()
        self:OnEvent("CovenantSanctumFrame_ChooseTalent", button)
    end
    self.targets = {
        [CovenantSanctumFrame.UpgradesTab.TravelUpgrade] =
            {set_tooltip = function(self) self:OnEnter() end,
             on_click = function(self) ChooseTalent(self) end},
        [CovenantSanctumFrame.UpgradesTab.DiversionUpgrade] =
            {set_tooltip = function(self) self:OnEnter() end,
             on_click = function(self) ChooseTalent(self) end},
        [CovenantSanctumFrame.UpgradesTab.AdventureUpgrade] =
            {set_tooltip = function(self) self:OnEnter() end,
             on_click = function(self) ChooseTalent(self) end},
        [CovenantSanctumFrame.UpgradesTab.UniqueUpgrade] =
            {set_tooltip = function(self) self:OnEnter() end,
             on_click = function(self) ChooseTalent(self) end},
        [CovenantSanctumFrame.UpgradesTab.DepositButton] =
            {set_tooltip = function(self)  -- copied from XML
                 GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                 GameTooltip_SetTitle(GameTooltip, COVENANT_SANCTUM_DEPOSIT_TOOLTIP)
                 GameTooltip:Show()
             end,
             can_activate = true, lock_highlight = true,
             is_default = true},
    }
    self:UpdateCursor()
end

function MenuCursor:CovenantSanctumFrame_Hide()
    assert(self.focus == nil or self.focus == CovenantSanctumFrame)
    self:ClearFocus()
    self:UpdateCursor()
end

function MenuCursor:CovenantSanctumFrame_ChooseTalent(upgrade_button)
    self:PushFocus(self.focus)
    self.cancel_func = function(self) self:PopFocus(self.focus) end
    self.targets = {
        [CovenantSanctumFrame.UpgradesTab.TalentsList.UpgradeButton] =
            {can_activate = true, lock_highlight = true,
             is_default = true},
    }
    for frame in CovenantSanctumFrame.UpgradesTab.TalentsList.talentPool:EnumerateActive() do
        self.targets[frame] =
            {set_tooltip = function(self) self:OnEnter() end}
    end
    self:UpdateCursor()
end


-------- Generic player choice frame

function MenuCursor.handlers.PlayerChoiceFrame(cursor)
    cursor.frame:RegisterEvent("ADDON_LOADED")
    if PlayerChoiceFrame then
        cursor:OnEvent("ADDON_LOADED", "Blizzard_PlayerChoice")
    end
end

function MenuCursor:ADDON_LOADED__Blizzard_PlayerChoice()
    self:HookShow(PlayerChoiceFrame, "PlayerChoiceFrame_SetShown")
end

function MenuCursor:PlayerChoiceFrame_Show()
    local KNOWN_FORMATS = {  -- Only handle formats we've explicitly verified.
        -- Emissary boost choice, Last Hurrah quest choice, etc.
        PlayerChoiceNormalOptionTemplate = true,
        -- Cobalt anima powers Superbloom dreamfruit, etc.
        PlayerChoiceGenericPowerChoiceOptionTemplate = true,
        -- Torghast anima powers
        PlayerChoiceTorghastOptionTemplate = true,
    }
    if not KNOWN_FORMATS[PlayerChoiceFrame.optionFrameTemplate] then
        return  
    end
    assert(PlayerChoiceFrame:IsVisible())
    self:SetFocus(PlayerChoiceFrame)
    self.cancel_func = self.CancelFrame
    self.targets = {}
    local leftmost = nil
    for option in PlayerChoiceFrame.optionPools:EnumerateActiveByTemplate(PlayerChoiceFrame.optionFrameTemplate) do
        for button in option.OptionButtonsContainer.buttonPool:EnumerateActive() do
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            if PlayerChoiceFrame.optionFrameTemplate == "PlayerChoiceTorghastOptionTemplate" then
                self.targets[button].set_tooltip = function()
                    if option.OptionText:IsTruncated() then
                        option:OnEnter()
                    end
                end
            else
                self.targets[button].send_enter_leave = true
            end
            if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                leftmost = button
            end
        end
    end
    if leftmost then  -- i.e., if we found any buttons
        self:SetTarget(leftmost)
    else
        self:ClearFocus()
    end
    self:UpdateCursor()
end

function MenuCursor:PlayerChoiceFrame_Hide()
    assert(self.focus == nil or self.focus == PlayerChoiceFrame)
    self:ClearFocus()
    self:UpdateCursor()
end


-------- Static popup dialogs

function MenuCursor.handlers.StaticPopup(cursor)
    for i = 1, STATICPOPUP_NUMDIALOGS do
        local frame_name = "StaticPopup" .. i
        local frame = _G[frame_name]
        assert(frame)
        cursor:HookShow(frame, "StaticPopup")
    end
end

function MenuCursor:StaticPopup_Show(frame)
    if self.focus == frame then return end  -- Sanity check
    self:PushFocus(frame)
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
        self:SetTarget(leftmost)
        if frame.button2:IsShown() then
            self.cancel_button = frame.button2
        end
    else
        self:PopFocus(frame)
    end
    self:UpdateCursor()
end

function MenuCursor:StaticPopup_Hide(frame)
    self:PopFocus(frame)
    self:UpdateCursor()
end


-------- Mail inbox

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
    self:SetFocus(InboxFrame)
    -- We specifically hook the inbox frame, so we need a custom handler
    -- to hide the proper frame on cancel.
    self.cancel_func = function(self)
        self:ClearFocus()
        HideUIPanel(MailFrame)
    end
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
            self:MailItemButton_Show(button)
        end
    end
    self:InboxFrame_UpdateMovement()
    self:UpdateCursor()
end

function MenuCursor:InboxFrame_Hide()
    assert(self.focus == nil or self.focus == MailFrame)
    self:ClearFocus()
    self:UpdateCursor()
end

function MenuCursor:MailItemButton_Show(frame)
    if self.focus ~= InboxFrame then return end
    self.targets[frame] = {
        can_activate = true, lock_highlight = true,
        set_tooltip = function()
            InboxFrameItem_OnEnter(frame)
        end,
    }
    self:InboxFrame_UpdateMovement()
end

function MenuCursor:MailItemButton_Hide(frame)
    if self.focus ~= InboxFrame then return end
    if self.cur_target == frame then
        self:Move(0, -1, "down")
    end
    self.targets[frame] = nil
    self:InboxFrame_UpdateMovement()
end

function MenuCursor:InboxFrame_UpdateMovement(frame)
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

function MenuCursor:OpenMailFrame_Show()
    assert(OpenMailFrame:IsShown())
    self:PushFocus(OpenMailFrame)
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
            self:OpenMailAttachmentButton_Show(button)
            if not first_attachment then first_attachment = button end
        end
    end
    if OpenMailMoneyButton:IsShown() then
        self:OpenMailMoneyButton_Show(OpenMailMoneyButton)
        if not first_attachment then first_attachment = OpenMailMoneyButton end
    end
    if first_attachment then
        self:SetTarget(first_attachment)
        self.targets[OpenMailReplyButton].up = first_attachment
        self.targets[OpenMailDeleteButton].up = first_attachment
        self.targets[OpenMailCancelButton].up = first_attachment
        if have_report_spam then
            self.targets[OpenMailReportSpamButton].down = first_attachment
        end
    else
        self:SetTarget(OpenMailCancelButton)
        if have_report_spam then
            self.targets[OpenMailReportSpamButton].down = OpenMailCancelButton
        end
    end
    self:UpdateCursor()
end

function MenuCursor:OpenMailFrame_Hide()
    assert(self.focus == nil or self.focus == InboxFrame
           or self.focus == OpenMailFrame)
    if self.focus == OpenMailFrame then
        self:PopFocus(OpenMailFrame)
        self:UpdateCursor()
    end
end

function MenuCursor:OpenMailAttachmentButton_Show(frame)
    if self.focus ~= OpenMailFrame then return end
    self.targets[frame] = {
        can_activate = true, lock_highlight = true,
        set_tooltip = function(self)
            OpenMailAttachment_OnEnter(frame, frame:GetID())
        end,
    }
end

function MenuCursor:OpenMailAttachmentButton_Hide(frame)
    if self.focus ~= OpenMailFrame then return end
    if self.cur_target == frame then
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
    self.targets[frame] = nil
end

function MenuCursor:OpenMailMoneyButton_Show(frame)
    if self.focus ~= OpenMailFrame then return end
    self.targets[frame] = {
        can_activate = true, lock_highlight = true,
        set_tooltip = function(self)  -- hardcoded in FrameXML
            if OpenMailFrame.money then
                GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                SetTooltipMoney(GameTooltip, OpenMailFrame.money)
                GameTooltip:Show()
            end
        end,
    }
end

function MenuCursor:OpenMailAttachmentButton_Hide(frame)
    if self.focus ~= OpenMailFrame then return end
    if self.cur_target == frame then
        local new_target = nil
        local id = 16
        while id >= 1 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id - 1
        end
        self:SetTarget(new_target or OpenMailDeleteButton)
    end
    self.targets[frame] = nil
end
