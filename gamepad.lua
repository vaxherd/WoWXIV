local _, WoWXIV = ...
WoWXIV.Gamepad = {}

-- This addon assumes the following console variable settings:
--    - GamePadEmulateShift = PADRTRIGGER
--    - GamePadEmulateCtrl = PADLTRIGGER
--    - GamePadEmulateAlt = PADLSHOULDER
-- Shift/Ctrl are not currently used in code but are assumed to be used
-- for hotkey bindings.

------------------------------------------------------------------------

-- Saved value of GamePadCameraPitchSpeed, used to prevent camera
-- rotation while zooming.
local zoom_saved_pitch_speed = nil

-- Initialize gamepad handling.
function WoWXIV.Gamepad.Init()
    local f = WoWXIV.CreateEventFrame("GamePadListener")
    f:SetPropagateKeyboardInput(true)

    function f:OnGamePadStick(stick, x, y)
        -- Handle zooming with L1 + camera up/down.
        if stick == "Camera" then
            if IsAltKeyDown() then  -- L1 assumed to be assigned to Alt
                if not zoom_saved_pitch_speed then
                    zoom_saved_pitch_speed = C_CVar.GetCVar("GamePadCameraPitchSpeed")
                    C_CVar.SetCVar("GamePadCameraPitchSpeed", 0)
                end
                if y > 0.1 then
                    CameraZoomIn(y/4)
                elseif y < -0.1 then
                    CameraZoomOut(-y/4)
                end
            else
                if zoom_saved_pitch_speed then
                    C_CVar.SetCVar("GamePadCameraPitchSpeed", zoom_saved_pitch_speed)
                    zoom_saved_pitch_speed = nil
                end
            end
        end
    end
    f:SetScript("OnGamePadStick", f.OnGamePadStick)
end
