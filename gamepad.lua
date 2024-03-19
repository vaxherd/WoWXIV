local WoWXIV = WoWXIV
WoWXIV.Gamepad = {}

------------------------------------------------------------------------

-- Initialize gamepad handling.
function WoWXIV.Gamepad.Init()
    local f = WoWXIV.CreateEventFrame("GamePadListener")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_LOGOUT")

    local logged_in = false
    local l1_down = false
    local zoom_saved_pitch_rate = 1

    function f:PLAYER_LOGIN()
        logged_in = true
    end

    function f:PLAYER_LOGOUT()
        logged_in = false
    end

    function f:OnKeyDown(key)
        --print(key)
    end
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", f.OnKeyDown)

    function f:OnGamePadButtonDown(button)
        if InCombatLockdown() then return end  --FIXME: causes "Action failed because of an AddOn" error
        --print(button)

        -- L1 enables right stick zoom.
        if button == "PADLSHOULDER" then
            l1_down = true
            -- FIXME: This is a hack to ensure we get the "button up" event
            -- when L1 is released, since SetPropagateKeyboardInput() causes
            -- those events to not be sent to us.  This prevents movement
            -- and camera yaw while zooming, but it also means we don't
            -- need to save and restore GamePadCameraPitchSpeed to disable
            -- camera pitch.
            f:SetPropagateKeyboardInput(false)
            --zoom_saved_pitch_rate = C_CVar.GetCVar("GamePadCameraPitchSpeed")
            --C_CVar.SetCVar("GamePadCameraPitchSpeed", 0)
        end
    end
    f:EnableGamePadButton(true)
    f:SetScript("OnGamePadButtonDown", f.OnGamePadButtonDown)

    function f:OnGamePadButtonUp(button)
        if InCombatLockdown() then f:SetPropagateKeyboardInput(true); return end  --FIXME: as above
        if button == "PADLSHOULDER" then
            l1_down = false
            f:SetPropagateKeyboardInput(true)
            --C_CVar.SetCVar("GamePadCameraPitchSpeed", zoom_saved_pitch_rate)
        end
    end
    f:SetScript("OnGamePadButtonUp", f.OnGamePadButtonUp)

    function f:OnGamePadStick(stick, x, y)
        if InCombatLockdown() then f:SetPropagateKeyboardInput(true); return end  --FIXME: as above
        -- Handle zooming with L1 + camera up/down.
        if stick == "Camera" and l1_down then
            if y > 0.1 then
                CameraZoomIn(y/4)
            elseif y < -0.1 then
                CameraZoomOut(-y/4)
            end
        end
    end
    f:SetScript("OnGamePadStick", f.OnGamePadStick)
end
