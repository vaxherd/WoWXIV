local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local CoreMenuFrame = MenuCursor.CoreMenuFrame

local class = WoWXIV.class

local abs = math.abs
local function clamp(x, l, h)
    if x < l then return l elseif x > h then return h else return x end
end
local strsub = string.sub

---------------------------------------------------------------------------

local WorldMapFrameHandler = class(CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(WorldMapFrameHandler)


function WorldMapFrameHandler:__constructor()
    -- Current cursor position, in normalized coordinates.
    self.cursor_x = 0.5
    self.cursor_y = 0.5
    -- Current cursor movement direction (+/-1).
    self.cursor_dx = 0
    self.cursor_dy = 0
    -- Current cursor movement speed (normalized coordinates / sec).
    self.cursor_speed = 0
    -- Cursor acceleration (speed / sec).  This is currently a constant.
    self.cursor_accel = 1
    -- Cursor minimum (initial) movement speed.  This is currently a constant.
    self.cursor_min_speed = 0.8
    -- Cursor maximum movement speed.  This is currently a constant.
    self.cursor_max_speed = 2
    -- Highlight pin currently under cursor, if any.
    self.cursor_highlight = nil

    __super(self, WorldMapFrame)
    self.has_Button3 = true

    -- Dummy frame we use to provide a target for the map cursor.
    self.cursor_frame =
        CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    self.cursor_frame:SetSize(1, 1)
    self.cursor_frame:SetScript(
        "OnGamePadButtonDown",
        function(_, button) self:OnGamePadButton(button, true) end)
    self.cursor_frame:SetScript(
        "OnGamePadButtonUp",
        function(_, button) self:OnGamePadButton(button, false) end)
    self.cursor_frame:SetScript(
        "OnEvent", function(_, ...) self:OnEnterCombat() end)
    self.cursor_frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.targets = {
        [self.cursor_frame] = {cursor_type = "map", dpad_override = true,
                               on_click = function() self:OnClickMap() end,
                               is_default = true},
    }
end

function WorldMapFrameHandler:OnShow()
    self.cursor_x = 0.5
    self.cursor_y = 0.5
    self.cursor_dx = 0
    self.cursor_dy = 0
    self.cursor_speed = 0
    self.cursor_highlight = nil
    self:UpdateCursorTarget()
    __super(self)
end

function WorldMapFrameHandler:OnGamePadButton(button, down)
    local is_modified = IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
    if not is_modified and self:HasFocus() and not InCombatLockdown() then
        if button == "PADDLEFT" or button == "PADDRIGHT" then
            self.cursor_dx = down and (button=="PADDLEFT" and -1 or 1) or 0
            -- It seems we have to explicitly toggle this flag on every event.
            self.cursor_frame:SetPropagateKeyboardInput(false)
            return
        end
        if button == "PADDUP" or button == "PADDDOWN" then
            self.cursor_dy = down and (button=="PADDUP" and -1 or 1) or 0
            self.cursor_frame:SetPropagateKeyboardInput(false)
            return
        end
    else
        self.cursor_dx = 0
        self.cursor_dy = 0
    end
    if not InCombatLockdown() then
        self.cursor_frame:SetPropagateKeyboardInput(true)
    end
end

function WorldMapFrameHandler:OnEnterCombat()
    self.cursor_dx = 0
    self.cursor_dy = 0
    self.cursor_frame:SetPropagateKeyboardInput(true)
end

function WorldMapFrameHandler:OnUpdate(target_frame, dt)
    local dx, dy = self.cursor_dx, self.cursor_dy
    local speed = self.cursor_speed
    if dx ~= 0 or dy ~= 0 then
        speed = clamp(speed + (self.cursor_accel * dt),
                      self.cursor_min_speed, self.cursor_max_speed)
        self.cursor_speed = speed
        local dist = speed * dt
        if dx ~= 0 and dy ~= 0 then
            dist = dist * (2^-0.5)
        end
        local x, y = self.cursor_x, self.cursor_y
        x = clamp(x + dx*dist, 0, 1)
        y = clamp(y + dy*dist, 0, 1)
        self.cursor_x, self.cursor_y = x, y
        self:UpdateCursorTarget()
    else
        self.cursor_speed = 0
    end
    target_frame:SetAlpha(self.frame:GetAlpha())
end

function WorldMapFrameHandler:OnAction(button)
    assert(button == "Button3")
    local last_map = WorldMapFrame.mapID
    local info = C_Map.GetMapInfo(last_map)
    local parent_map = info and info.parentMapID
    if not parent_map or parent_map == 0 then return end
    if parent_map == last_map then return end  -- Already at top map.
    C_Map.OpenWorldMap(parent_map)
    self:PutCursorAtMapLinkOrCenter(last_map)
    self:UpdateCursorTarget()
end

function WorldMapFrameHandler:OnClickMap()
    local current_map = self.frame.mapID
    local target_map
    for _, info in ipairs(C_Map.GetMapLinksForMap(current_map)) do
        -- We use a box instead of circle test since the icons are
        -- generally more boxy than circular.
        if abs(info.position.x - self.cursor_x) <= 0.03
        and abs(info.position.y - self.cursor_y) <= 0.03
        then
            target_map = info.linkedUiMapID
            break
        end
    end
    if not target_map then
        local info = C_Map.GetMapInfoAtPosition(
            current_map, self.cursor_x, self.cursor_y)
        if info then
            target_map = info.mapID
        end
    end
    if target_map then
        C_Map.OpenWorldMap(target_map)
        self:PutCursorAtMapLinkOrCenter(current_map)
        self:UpdateCursorTarget()
    end
end

-- Looks for a link from the current map to |link_map| and places the
-- cursor there if found, or at the center of the map if not.  If there
-- are multiple such links, it is unspecified which one is used.
function WorldMapFrameHandler:PutCursorAtMapLinkOrCenter(link_map)
    self.cursor_highlight = nil
    for _, info in ipairs(C_Map.GetMapLinksForMap(self.frame.mapID)) do
        if info.linkedUiMapID == link_map then
            self.cursor_x = info.position.x
            self.cursor_y = info.position.y
            return
        end
    end
    -- No link found, default to center.
    self.cursor_x = 0.5
    self.cursor_y = 0.5
end

function WorldMapFrameHandler:UpdateCursorTarget()
    local cf = self.cursor_frame
    local x, y, w, h = WorldMapFrame.ScrollContainer.Child:GetRect()
    cf:ClearAllPoints()
    cf:SetPoint("TOPLEFT", w*self.cursor_x, (-h)*self.cursor_y)
end
