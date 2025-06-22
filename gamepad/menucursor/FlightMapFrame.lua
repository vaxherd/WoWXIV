local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local abs = math.abs
local band = bit.band
local tinsert = tinsert

---------------------------------------------------------------------------

local FlightMapFrameHandler = class(MenuCursor.AddOnMenuFrame)
FlightMapFrameHandler.ADDON_NAME = "Blizzard_FlightMap"
MenuCursor.Cursor.RegisterFrameHandler(FlightMapFrameHandler)

function FlightMapFrameHandler:__constructor()
    self:__super(FlightMapFrame)
    hooksecurefunc(self.frame, "OnMapChanged",
                   function() self:UpdateZoomButton() end)
    hooksecurefunc(self.frame, "OnCanvasScaleChanged",
                   function() self:UpdateZoomButton() end)
end

function FlightMapFrameHandler:SetTargets()
    self:UpdateZoomButton()
    self.targets = {}
    return self:AddTargets()
end

function FlightMapFrameHandler:UpdateZoomButton()
    local info = C_Map.GetMapInfo(self.frame.mapID)
    local autozoom = band(info.flags, Enum.UIMapFlag.FlightMapShowZoomOut) ~= 0
    self.has_Button3 = autozoom and self.frame:GetCanvasZoomPercent() > 0.5
    self:UpdateCursor()
end

function FlightMapFrameHandler:OnAction(button)
    assert(button == "Button3")
    self.frame:ZoomOut()
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

-- Override default behavior to prefer closer targets over narrower angles,
-- to try and ensure that all pins are reachable.  (Without this, for
-- example, when zoomed in to Krokuun on Argus, the cursor cannot move
-- directly from the Vindicaar to Krokul Hovel because there are points
-- closer to each cardinal direction, even though Krokul Hovel is the
-- closest point in terms of distance.)
function FlightMapFrameHandler:NextTarget(target, dir)
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

    local global_scale = UIParent:GetEffectiveScale()
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
    -- Rather than worrying about angles, we simply select the closest
    -- target in the appropriate quadrant.
    local best, best_dist2 = nil, nil
    for frame, params in pairs(self.targets) do
        if frame ~= target then
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
            local frame_dx = f_cx - cur_cx
            local frame_dy = f_cy - cur_cy
            if ((dx < 0 and frame_dx < 0 and abs(frame_dx) >= abs(frame_dy))
             or (dx > 0 and frame_dx > 0 and abs(frame_dx) >= abs(frame_dy))
             or (dy > 0 and frame_dy > 0 and abs(frame_dy) >= abs(frame_dx))
             or (dy < 0 and frame_dy < 0 and abs(frame_dy) >= abs(frame_dx)))
            then
                local frame_dist2 = frame_dx*frame_dx + frame_dy*frame_dy
                if not best or frame_dist2 < best_dist2 then
                    best = frame
                    best_dist2 = frame_dist2
                end
            end
        end
    end
    return best
end
