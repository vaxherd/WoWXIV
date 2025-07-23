local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local ScrappingMachineFrameHandler = class(MenuCursor.AddOnMenuFrame)
MenuCursor.ScrappingMachineFrameHandler = ScrappingMachineFrameHandler  -- For exports.
ScrappingMachineFrameHandler.ADDON_NAME = "Blizzard_ScrappingMachineUI"
MenuCursor.Cursor.RegisterFrameHandler(ScrappingMachineFrameHandler)

function ScrappingMachineFrameHandler:__constructor()
    self:__super(ScrappingMachineFrame)
    local f = self.frame
    local slots = {}
    for button in f.ItemSlots.scrapButtons:EnumerateActive() do
        slots[button.SlotNumber+1] = button
    end
    assert(#slots == 9)
    for i, button in ipairs(slots) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                up = i<=3 and f.ScrapButton or slots[i-3],
                                down = i>=7 and f.ScrapButton or slots[i+3],
                                left = slots[i==1 and 9 or i-1],
                                right = slots[i==9 and 1 or i+1]}
    end
    self.targets[f.ScrapButton] = {can_activate = true, lock_highlight = true,
                                   on_click = self.PostClickScrapButton,
                                   up = slots[9], down = slots[1],
                                   left = false, right = false,
                                   is_default = true}
end

function ScrappingMachineFrameHandler:OnShow()
    -- We reimplement OnShow() ourselves to avoid taking focus from the
    -- inventory bags, since the player will want to start there.
    self:EnableBackground()
end

function ScrappingMachineFrameHandler.PostClickScrapButton()  -- static method
    -- Send the cursor back to the inventory to save the player some time.
    MenuCursor.ContainerFrameHandler.FocusIfOpen()
end

---------------------------------------------------------------------------

-- Exported function, called by ContainerFrame.
function ScrappingMachineFrameHandler.FocusScrapButton()
    local instance = ScrappingMachineFrameHandler.instance
    assert(instance:IsEnabled())
    instance:SetTarget(instance.frame.ScrapButton)
    instance:Focus()
end
