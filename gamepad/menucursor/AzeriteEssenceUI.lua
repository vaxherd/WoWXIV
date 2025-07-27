local module_name, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local AzeriteEssenceUIHandler = class(MenuCursor.AddOnMenuFrame)
AzeriteEssenceUIHandler.ADDON_NAME = "Blizzard_AzeriteEssenceUI"
MenuCursor.Cursor.RegisterFrameHandler(AzeriteEssenceUIHandler)

function AzeriteEssenceUIHandler:__constructor()
    self:__super(AzeriteEssenceUI)
    self.cancel_func = function() self:OnCancel() end
    self.has_Button3 = true  -- Used to toggle between slots and essence list.

    -- Is the cursor on the essence list (true) or node map (false)?
    self.on_list = true
    -- ID of currently selected essence, nil if none (i.e. when the frame
    -- is first opened).  This is independent from the "pending essence"
    -- set for socketing.
    self.cur_essence = nil
end

local function GetPendingActivationEssence()  -- Map 0 to nil.
    local id = C_AzeriteEssence.GetPendingActivationEssence()
    if id == 0 then id = nil end
    return id
end

function AzeriteEssenceUIHandler:OnCancel()
    if GetPendingActivationEssence() then
        C_AzeriteEssence.ClearPendingActivationEssence()
        self.on_list = true
        self:RefreshTargets()
    else
        MenuCursor.MenuFrame.CancelUIFrame(self)
    end
end

function AzeriteEssenceUIHandler:OnShow()
    self.cur_essence = nil
    self.on_list = true
    MenuCursor.AddOnMenuFrame.OnShow(self)
end

function AzeriteEssenceUIHandler:OnAction(button)
    assert(button == "Button3")
    self.on_list = not self.on_list
    self:RefreshTargets()
end

function AzeriteEssenceUIHandler:EnterTarget(target)
    MenuCursor.AddOnMenuFrame.EnterTarget(self, target)
    if self.on_list then
        self.cur_essence = self:GetTargetFrame(target).essenceID
    end
end

function AzeriteEssenceUIHandler:GetHeldItemTexture()
    local pending = GetPendingActivationEssence()
    if pending then
        local info = C_AzeriteEssence.GetEssenceInfo(pending)
        return info and info.icon
    end
    return nil
end

function AzeriteEssenceUIHandler:OnClickEssence(button)
    self.on_list = not self.on_list
    self:RefreshTargets()
end

function AzeriteEssenceUIHandler:OnClickSlot(button)
    local pending = GetPendingActivationEssence()
    button:OnMouseUp("LeftButton")
    if pending and not GetPendingActivationEssence() then
        -- We just slotted an essence, so go back to the list.
        self.on_list = true
        self:RefreshTargets()
    end
end

function AzeriteEssenceUIHandler:RefreshTargets()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function AzeriteEssenceUIHandler:SetTargets()
    local f = self.frame
    self.targets = {}
    if self.on_list then
        local first, last, initial = self:AddScrollBoxTargets(
            f.EssenceList.ScrollBox,
            function(data)
                if data.valid then
                    local params = {can_activate = true, lock_highlight = true,
                                    send_enter_leave = true,
                                    on_click = function(button)
                                        self:OnClickEssence(button)
                                    end}
                    return params, data.ID == self.cur_essence
                end
            end)
        return initial or first
    else
        local slots = {}
        for _, button in ipairs(f.Milestones) do
            if button.slot then
                slots[button.slot] = button
            end
        end
        local MainSlot = Enum.AzeriteEssenceSlot.MainSlot
        local PassiveOneSlot = Enum.AzeriteEssenceSlot.PassiveOneSlot
        local PassiveTwoSlot = Enum.AzeriteEssenceSlot.PassiveTwoSlot
        local PassiveThreeSlot = Enum.AzeriteEssenceSlot.PassiveThreeSlot
        local slot_movement = {
            [MainSlot] = {up = PassiveThreeSlot, down = PassiveOneSlot,
                          right = PassiveTwoSlot},
            [PassiveOneSlot] = {up = MainSlot, right = PassiveTwoSlot},
            [PassiveTwoSlot] = {up = PassiveThreeSlot, down = PassiveOneSlot,
                                left = MainSlot},
            [PassiveThreeSlot] = {down = MainSlot, right = PassiveTwoSlot},
        }
        for slot, button in pairs(slots) do
            local params =
                {on_click = function(button) self:OnClickSlot(button) end,
                 send_enter_leave = true}
            for dir, target in pairs(slot_movement[slot]) do
                params[dir] = slots[target]
            end
            self.targets[button] = params
        end
        return slots[MainSlot]
    end
end
