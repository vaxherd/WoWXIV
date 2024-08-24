local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
local Gamepad = WoWXIV.Gamepad

local class = WoWXIV.class

local strsub = string.sub

------------------------------------------------------------------------

-- Convenience function for checking the state of all modifiers:
local function IsModifier(shift, ctrl, alt)
    local function bool(x) return x and x~=0 end
    local function eqv(a,b) return bool(a) == bool(b) end
    return eqv(shift, IsShiftKeyDown()) and
           eqv(ctrl, IsControlKeyDown()) and
           eqv(alt, IsAltKeyDown())
end

-- Convenience function for translating a modifier prefix on an input
-- specification into modifier flags:
local function ExtractModifiers(spec)
    local alt, ctrl, shift = 0, 0, 0
    if strsub(spec, 1, 4) == "ALT-" then
        alt = 1
        spec = strsub(spec, 5, -1)
    end
    if strsub(spec, 1, 5) == "CTRL-" then
        ctrl = 1
        spec = strsub(spec, 6, -1)
    end
    if strsub(spec, 1, 6) == "SHIFT-" then
        shift = 1
        spec = strsub(spec, 7, -1)
    end
    return shift, ctrl, alt, spec
end

-- Convenience function for checking whether a button press combined with
-- current modifiers matches an input specifier:
local function MatchModifiedButton(button, spec)
    local shift, ctrl, alt, raw_spec = ExtractModifiers(spec)
    return IsModifier(shift, ctrl, alt) and button == raw_spec
end

------------------------------------------------------------------------

-- Base class for LeaveVehicleButton and QuestItemButton.
-- Handles updating the input binding on config change.
Gamepad.GamepadBoundButton = class()
local GamepadBoundButton = Gamepad.GamepadBoundButton

function GamepadBoundButton:__constructor(frame, binding_setting, command)
    self.binding_frame = frame
    self.binding_setting = binding_setting
    self.binding_command = command
    self:UpdateBinding()
end

function GamepadBoundButton:UpdateBinding()
    ClearOverrideBindings(self.binding_frame)
    SetOverrideBinding(self.binding_frame, false,
                       WoWXIV_config[self.binding_setting],
                       self.binding_command)
end

------------------------------------------------------------------------

-- Class handling miscellaneous gamepad behaviors.
local GamePadListener = class()

function GamePadListener:__constructor()
    -- Current frame's timestamp.
    self.frame_ts = GetTime()
    -- Current frame's delta-time value. (FIXME: is there no API for this?)
    self.frame_dt = 0
    -- Reasons why the camera stick is currently disabled.
    self.camera_stick_disable = {}
    -- Saved value of GamePadCameraPitchSpeed while camera stick is disabled.
    self.zoom_saved_pitch_speed = nil
    -- Saved value of GamePadCameraYawSpeed while camera stick is disabled.
    self.zoom_saved_yaw_speed = nil
    -- Saved camera zoom while in first-person camera.
    self.fpv_saved_zoom = nil

    local f = WoWXIV.CreateEventFrame("WoWXIV_GamePadListener")
    self.frame = f
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnUpdate", function() self:OnUpdate() end)
    f:SetScript("OnGamePadButtonDown", function(_,...) self:OnGamePadButton(...) end)
    f:SetScript("OnGamePadStick", function(_,...) self:OnGamePadStick(...) end)

    -- Handle L1/R1 for page flipping in item text.
    ItemTextFrame:HookScript("OnShow", function() self:ItemTextFrame_OnShow() end)
    ItemTextFrame:HookScript("OnHide", function() self:ItemTextFrame_OnHide() end)
end

function GamePadListener:OnUpdate()
    local now = GetTime()
    self.frame_dt = now - self.frame_ts
    self.frame_ts = now
end

function GamePadListener:OnGamePadButton(button)
    -- Check for first-person view toggle.
    if MatchModifiedButton(button, WoWXIV_config["gamepad_toggle_fpv"]) then
        if self.fpv_saved_zoom then
            -- CameraZoomOut() operates from the current zoom value, not
            -- the target value, so we need to check whether we're still
            -- in the middle of zooming in and adjust appropriately.
            local zoom = GetCameraZoom()
            -- Note that the engine is a bit sloppy with zooming and
            -- tends to over/undershoot a bit.  We accept that as just
            -- part of the game rather than spending an OnUpdate script
            -- on trying to micromanage the zoom value.
            CameraZoomOut(self.fpv_saved_zoom - zoom)
            self.fpv_saved_zoom = nil
        else
            local zoom = GetCameraZoom()
            if zoom > 0 then
                self.fpv_saved_zoom = zoom
                CameraZoomIn(zoom)
            end
        end
    end
end

function GamePadListener:SetCameraStickDisable(type, active)
    self.camera_stick_disable[type] = active and true or nil
    local disable_x, disable_y = false, false
    for disable_type, _ in pairs(self.camera_stick_disable) do
        if type == "ZOOM" then
            disable_y = true
        end
        if type == "SCROLL_TEXT" then
            disable_x = true
            disable_y = true
        end
    end
    if disable_x then
        if not self.zoom_saved_yaw_speed then
            self.zoom_saved_yaw_speed =
                C_CVar.GetCVar("GamePadCameraYawSpeed")
            C_CVar.SetCVar("GamePadCameraYawSpeed", 0)
        end
    else
        if self.zoom_saved_yaw_speed then
            C_CVar.SetCVar("GamePadCameraYawSpeed",
                           self.zoom_saved_yaw_speed)
            self.zoom_saved_yaw_speed = nil
        end
    end
    if disable_y then
        if not self.zoom_saved_pitch_speed then
            self.zoom_saved_pitch_speed =
                C_CVar.GetCVar("GamePadCameraPitchSpeed")
            C_CVar.SetCVar("GamePadCameraPitchSpeed", 0)
        end
    else
        if self.zoom_saved_pitch_speed then
            C_CVar.SetCVar("GamePadCameraPitchSpeed",
                           self.zoom_saved_pitch_speed)
            self.zoom_saved_pitch_speed = nil
        end
    end
end

function GamePadListener:OnGamePadStick(stick, x, y)
    -- Handle zooming with modifier + camera up/down.
    if stick == "Camera" then
        local shift, ctrl, alt =
            ExtractModifiers(WoWXIV_config["gamepad_zoom_modifier"] .. "-")
        if IsModifier(shift, ctrl, alt) then
            self:SetCameraStickDisable("ZOOM", true)
            if y > 0.1 then
                CameraZoomIn(y/4)
            elseif y < -0.1 then
                CameraZoomOut(-y/4)
                -- Since WoW doesn't have an independent "first-person view"
                -- state, we allow normally zooming out of FPV and silently
                -- cancel FPV state in that case.
                self.fpv_saved_zoom = nil
            end
        else
            self:SetCameraStickDisable("ZOOM", false)
        end
    end

    -- Handle scrolling quest text frames.
    local SCROLL_FRAMES = {
        ItemTextScrollFrame,
        QuestDetailScrollFrame,
        QuestRewardScrollFrame,
    }
    local scroll_frame
    for _, frame in ipairs(SCROLL_FRAMES) do
        if frame:IsVisible() then
            scroll_frame = frame
            break
        end
    end
    self:SetCameraStickDisable("SCROLL_TEXT", scroll_frame)
    if scroll_frame and stick == "Camera" then
        local scroll_delta = -1000 * self.frame_dt
        local scroll = scroll_frame:GetVerticalScroll() + (y * scroll_delta)
        -- SetVerticalScroll() automatically clamps to child height.
        scroll_frame:SetVerticalScroll(scroll)
    end
end

function GamePadListener:ItemTextFrame_OnShow()
    SetOverrideBinding(ItemTextFrame, true,
                       WoWXIV_config["gamepad_menu_prev_page"],
                       "CLICK ItemTextPrevPageButton:LeftButton")
    SetOverrideBinding(ItemTextFrame, true,
                       WoWXIV_config["gamepad_menu_next_page"],
                       "CLICK ItemTextNextPageButton:LeftButton")
end

function GamePadListener:ItemTextFrame_OnHide()
    ClearOverrideBindings(ItemTextFrame)
end

---------------------------------------------------------------------------

function Gamepad.Init()
    Gamepad.listener = GamePadListener()
    Gamepad.qib = Gamepad.QuestItemButton()
    Gamepad.lvb = Gamepad.LeaveVehicleButton()
    Gamepad.cursor = Gamepad.MenuCursor()
end

function Gamepad.UpdateBindings()
    Gamepad.qib:UpdateBinding()
    Gamepad.lvb:UpdateBinding()
end
