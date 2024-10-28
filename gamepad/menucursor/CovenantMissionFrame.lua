local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local CovenantMissionFrameHandler = class(MenuCursor.AddOnMenuFrame)
CovenantMissionFrameHandler.ADDON_NAME = "Blizzard_GarrisonUI"
MenuCursor.Cursor.RegisterFrameHandler(CovenantMissionFrameHandler)

function CovenantMissionFrameHandler:__constructor()
    self:__super(CovenantMissionFrame)
end

function CovenantMissionFrameHandler:SetTargets()
    self.targets = {}
    -- Pin load is delayed, so wait for data to show up.
    self:AddTargets()
end

function CovenantMissionFrameHandler:AddTargets()
    local pool = self.frame.MapTab.pinPools.AdventureMap_QuestChoicePinTemplate
    if pool then
        local pins = {}
        for pin in pool:EnumerateActive() do
            tinsert(pins, pin)
        end
        if #pins > 0 then
            local function OnEnterPin(pin) self:OnEnterPin(pin) end
            local function OnLeavePin(pin) self:OnLeavePin(pin) end
            local function OnClickPin(pin) self:OnClickPin(pin) end
            local top
            for _, pin in ipairs(pins) do
                -- Pins aren't true buttons and don't have IsEnabled(), so
                -- we can't use lock_highlight and have to roll our own.
                self.targets[pin] = {on_click = OnClickPin,
                                     on_enter = OnEnterPin,
                                     on_leave = OnLeavePin}
                if not top or pin.normalizedY < top.normalizedY then
                    top = pin
                end
            end
            self:SetTarget(top)
            return
        end
    end
    -- Pins are not yet loaded, so try again next frame.
    RunNextFrame(function() self:AddTargets() end)
end

function CovenantMissionFrameHandler:OnEnterPin(pin)
    pin:OnMouseEnter()
    pin:LockHighlight()
end

function CovenantMissionFrameHandler:OnLeavePin(pin)
    pin:UnlockHighlight()
    pin:OnMouseLeave()
end

function CovenantMissionFrameHandler:OnClickPin(pin)
    pin:OnClick("LeftButton", true)
end
