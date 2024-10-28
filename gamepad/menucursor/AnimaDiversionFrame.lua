local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local AnimaDiversionFrameHandler = class(MenuCursor.AddOnMenuFrame)
AnimaDiversionFrameHandler.ADDON_NAME = "Blizzard_AnimaDiversionUI"
MenuCursor.Cursor.RegisterFrameHandler(AnimaDiversionFrameHandler)

function AnimaDiversionFrameHandler:__constructor()
    self:__super(AnimaDiversionFrame)
end

function AnimaDiversionFrameHandler:SetTargets()
    local function OnClickPin(pin)
        self:OnClickPin(pin)
    end
    self.targets = {}
    local pool = self.frame.pinPools.AnimaDiversionPinTemplate
    for pin in pool:EnumerateActive() do
        local is_origin = (pin.nodeData == nil)
        self.targets[pin] = {on_click = not is_origin and OnClickPin,
                             is_default = is_origin}
    end
end

function AnimaDiversionFrameHandler:OnClickPin(pin)
    pin:OnClick("LeftButton", true)
end
