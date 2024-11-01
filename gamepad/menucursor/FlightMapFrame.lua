local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local FlightMapFrameHandler = class(MenuCursor.AddOnMenuFrame)
FlightMapFrameHandler.ADDON_NAME = "Blizzard_FlightMap"
MenuCursor.Cursor.RegisterFrameHandler(FlightMapFrameHandler)

function FlightMapFrameHandler:__constructor()
    self:__super(FlightMapFrame)
end

function FlightMapFrameHandler:SetTargets()
    self.targets = {}
    return self:AddTargets()
end

function FlightMapFrameHandler:AddTargets()
    local pool = self.frame.pinPools.FlightMap_FlightPointPinTemplate
    if pool then
        local pins = {}
        for pin in pool:EnumerateActive() do
            if pin.taxiNodeData.state ~= Enum.FlightPathState.Unreachable then
                tinsert(pins, pin)
            end
        end
        if #pins > 0 then
            local function OnEnterPin(pin) self:OnEnterPin(pin) end
            local function OnLeavePin(pin) self:OnLeavePin(pin) end
            local function OnClickPin(pin) self:OnClickPin(pin) end
            local top, current
            for _, pin in ipairs(pins) do
                -- Pins aren't true buttons and don't have IsEnabled(), so
                -- we can't use lock_highlight and have to roll our own.
                self.targets[pin] = {on_click = OnClickPin,
                                     on_enter = OnEnterPin,
                                     on_leave = OnLeavePin}
                if not top or pin.normalizedY < top.normalizedY then
                    top = pin
                end
                if pin.taxiNodeData.state == Enum.FlightPathState.Current then
                    current = pin
                end
            end
            local target = current or top
            self:SetTarget(target)
            return target
        end
    end
    -- Pins are not yet loaded, so try again next frame.
    RunNextFrame(function() self:AddTargets() end)
    return nil
end

function FlightMapFrameHandler:OnEnterPin(pin)
    pin:OnMouseEnter()
    pin:LockHighlight()
end

function FlightMapFrameHandler:OnLeavePin(pin)
    pin:UnlockHighlight()
    pin:OnMouseLeave()
end

function FlightMapFrameHandler:OnClickPin(pin)
    pin:OnClick("LeftButton", true)
end
