local _, WoWXIV = ...
WoWXIV.Gamepad = {}

local class = WoWXIV.class

-- This addon assumes the following console variable settings:
--    GamePadEmulateShift = PADRTRIGGER
--    GamePadEmulateCtrl = PADLTRIGGER
--    GamePadEmulateAlt = PADLSHOULDER

------------------------------------------------------------------------

-- Invisible button used to securely activate quest items.
-- FIXME: It would be nice to make this visible, like the special action
-- button.  It would be even nicer if quest items consistently showed up
-- in the special action button in the first place so we didn't need
-- this workaround.
local QuestItemButton = class()

function QuestItemButton:__constructor()
    self.item = nil
    self.pending_update = false

    local f = CreateFrame("Button", "WoWXIV_QuestItemButton", nil,
                          "SecureActionButtonTemplate")
    self.frame = f
    f:SetAttribute("type", "item")
    f:SetAttribute("item", nil)
    -- FIXME: Setting unit=target means we can't use ground-target items
    -- without an arbitrary target selected (including soft targets), and
    -- we can't use non-targeted items like Aqueous Material Accumulator
    -- (Maldraxxus world quest "Further Gelatinous Research"), though
    -- targeting the player seems to work in that case.  Need to find a
    -- better solution here.  Ideally we would just call
    -- UseQuestLogSpecialItem(log_index), but that's a protected function
    -- and there's no secure action wrapper for it.
    f:SetAttribute("unit", "target")
    f:RegisterForClicks("LeftButtonDown")
    -- FIXME: make this configurable
    SetOverrideBinding(f, false, "CTRL-PADLSTICK",
                       "CLICK WoWXIV_QuestItemButton:LeftButton")

    f:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
    f:SetScript("OnEvent", function() self:UpdateQuestItem() end)
    self:UpdateQuestItem()
end

function QuestItemButton:UpdateQuestItem(is_retry)
    if not is_retry and self.pending_update then return end
    if InCombatLockdown() then
        self.pending_update = true
        C_Timer.After(1, function() self:UpdateQuestItem(true) end)
        return
    end
    self.pending_update = false

    local item = nil
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local link, icon, charges, show_when_complete =
            GetQuestLogSpecialItemInfo(index)
        if link then
            -- GetItemInfoFromHyperlink() is defined in Blizzard's
            -- SharedXML/LinkUtil.lua
            item = GetItemInfoFromHyperlink(link)
            if item then break end
        end
    end
    if item then
        -- We can't activate an item by ID (the ID would be interpreted as
        -- an inventory slot index), so we need to set the name instead.
        local name = GetItemInfo(item)
        self.frame:SetAttribute("item", name)
    else
        self.frame:SetAttribute("item", nil)
    end
end

------------------------------------------------------------------------

local GamePadListener = class()

function GamePadListener:__constructor()
    -- Saved value of GamePadCameraPitchSpeed, used to prevent camera
    -- rotation while zooming.
    self.zoom_saved_pitch_speed = nil

    local f = WoWXIV.CreateEventFrame("WoWXIV_GamePadListener")
    self.frame = f
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnGamePadStick", function(_,...) self:OnGamePadStick(...) end)
end

function GamePadListener:OnGamePadStick(stick, x, y)
    -- Handle zooming with L1 + camera up/down.
    if stick == "Camera" then
        if IsAltKeyDown() then  -- L1 assumed to be assigned to Alt
            if not self.zoom_saved_pitch_speed then
                self.zoom_saved_pitch_speed =
                    C_CVar.GetCVar("GamePadCameraPitchSpeed")
                C_CVar.SetCVar("GamePadCameraPitchSpeed", 0)
            end
            if y > 0.1 then
                CameraZoomIn(y/4)
            elseif y < -0.1 then
                CameraZoomOut(-y/4)
            end
        else
            if self.zoom_saved_pitch_speed then
                C_CVar.SetCVar("GamePadCameraPitchSpeed",
                               self.zoom_saved_pitch_speed)
                self.zoom_saved_pitch_speed = nil
            end
        end
    end
end

---------------------------------------------------------------------------

function WoWXIV.Gamepad.Init()
    WoWXIV.Gamepad.listener = GamePadListener()
    WoWXIV.Gamepad.qib = QuestItemButton()
end
