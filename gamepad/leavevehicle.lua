local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
local Gamepad = WoWXIV.Gamepad

assert(Gamepad.GamepadBoundButton)  -- Ensure proper load order.

local class = WoWXIV.class

------------------------------------------------------------------------

-- Button used to leave a vehicle (event mount or taxi).
-- This is needed because there are two different native "leave" buttons
-- (MainMenuBarVehicleLeaveButton for the small button above action bars,
-- OverrideActionBarLeaveFrameLeaveButton for the button in the separate
-- vehicle UI), and we can't bind one input to both buttons at once.
Gamepad.LeaveVehicleButton = class(Gamepad.GamepadBoundButton)
local LeaveVehicleButton = Gamepad.LeaveVehicleButton

function LeaveVehicleButton:__constructor()
    local f = CreateFrame("Button", "WoWXIV_LeaveVehicleButton")
    self.frame = f
    f:SetScript("OnClick", function(_,...) self:OnClick(...) end)
    self:__super(f, "gamepad_leave_vehicle",
                 "CLICK WoWXIV_LeaveVehicleButton:LeftButton")
end

function LeaveVehicleButton:OnClick(button, down)
    -- VehicleExit() and TaxiRequestEarlyLanding() both appear to not
    -- be protected (as of 10.2.6), so we can just call these directly,
    -- reproducing the behavior of the two native buttons.
    if UnitOnTaxi("player") then
        TaxiRequestEarlyLanding()
        local native_button = MainMenuBarVehicleLeaveButton
        if native_button then  -- sanity check
            native_button:Disable()
            native_button:SetHighlightTexture(
                "Interface/Buttons/CheckButtonHilight", "ADD")
            native_button:LockHighlight()
        end
    else
        VehicleExit()
    end
end
