local _, WoWXIV = ...
WoWXIV.Gamepad = {}

local class = WoWXIV.class
local GetItemInfo = C_Item.GetItemInfo

-- This addon assumes the following console variable settings:
--    GamePadEmulateShift = PADRTRIGGER
--    GamePadEmulateCtrl = PADLTRIGGER
--    GamePadEmulateAlt = PADLSHOULDER

------------------------------------------------------------------------

-- Convenience function for checking the state of all modifiers:
local function IsModifier(shift, ctrl, alt)
    local function bool(x) return x and x~=0 end
    local function eqv(a,b) return bool(a) == bool(b) end
    return eqv(shift, IsShiftKeyDown()) and
           eqv(ctrl, IsControlKeyDown()) and
           eqv(alt, IsAltKeyDown())
end


-- Invisible button used to securely activate quest items.
-- FIXME: It would be nice to make this visible, like the special action
-- button.  It would be even nicer if quest items consistently showed up
-- in the special action button in the first place so we didn't need
-- this workaround.
local QuestItemButton = class()

-- FIXME: The required target for quest items varies, and is not always
-- obvious from the item data available via the API; for example, Azure
-- Span sidequest "Setting the Defense" (ID 66489) has a quest item
-- "Arch Instructor's Wand" (ID 192471) intended to be used on a targeted
-- friendly NPC, but is neither "helpful" nor "harmful", while Rusziona's
-- Whistle (202293) from Little Scales Daycare quest "What's a Duck?"
-- (72459) is marked "helpful" but requires the player to be targeted in
-- order to fire.  Ideally we would just call
-- UseQuestLogSpecialItem(log_index), but that's a protected function and
-- there's no secure action wrapper for it (as of 10.2.6), so for the
-- meantime we record specific items whose required targets we know and
-- use fallback logic for others.
local ITEM_TARGET = {
    -- Primordial Muck (59808: Muck It Up)
    [177880] = "player",
    -- Aqueous Material Accumulator (61189: Further Gelatinous Research)
    [180876] = "player",
    -- Fae Flute (61717: Gormling Piper: Tranquil Pools [and others])
    [182189] = "",  -- FIXME: does not seem to work with any target
    -- Assassin's Soulcloak (61765: Words of Warding)
    [182303] = "player",
    -- Niya's Staff (63840: They Grow Up So Quickly)
    [186089] = "target",
    -- Arch Instructor's Wand (66489: Setting the Defense)
    [192471] = "target",
    -- Rusziona's Whistle (72459: What's a Duck?)
    [202293] = "player",
}

function QuestItemButton:__constructor()
    self.item = nil
    self.pending_update = false

    local f = CreateFrame("Button", "WoWXIV_QuestItemButton", nil,
                          "SecureActionButtonTemplate")
    self.frame = f
    f:SetAttribute("type", "item")
    f:SetAttribute("item", nil)
    f:SetAttribute("unit", nil)
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
        local known_target = ITEM_TARGET[item]
        if known_target then
            if #known_target then
               self.frame:SetAttribute("unit", known_target)
            else
               self.frame:SetAttribute("unit", nil)
            end
        elseif C_Item.IsHelpfulItem(item) or C_Item.IsHarmfulItem(item) then
            self.frame:SetAttribute("unit", "target")
        else
            self.frame:SetAttribute("unit", "player")
        end
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
    -- Saved camera zoom while in first-person camera.
    self.fpv_saved_zoom = nil

    local f = WoWXIV.CreateEventFrame("WoWXIV_GamePadListener")
    self.frame = f
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnGamePadButtonDown", function(_,...) self:OnGamePadButton(...) end)
    f:SetScript("OnGamePadStick", function(_,...) self:OnGamePadStick(...) end)
end

function GamePadListener:OnGamePadButton(button)
    -- Use R3 to toggle first-person view.
    if button == "PADRSTICK" and IsModifier(0,0,0) then
        if self.fpv_saved_zoom then
            -- CameraZoomOut() operates from the current zoom value, not
            -- the target value, so we need to check whether we're still
            -- in the middle of zooming in and adjust appropriately.
            local zoom = GetCameraZoom()
            -- Note that the engine is a bit sloppy with zooming and
            -- tends to over/undershoot a bit.  We accept that as just
            -- part of the game rather than spending an OnUpdate script
            -- on trying to micromanage the zoom value.
            CameraZoomOut(self.fpv_saved_zoom - zoom)
            self.fpv_saved_zoom = nil
        else
            local zoom = GetCameraZoom()
            if zoom > 0 then
                self.fpv_saved_zoom = zoom
                CameraZoomIn(zoom)
            end
        end
    end
end

function GamePadListener:OnGamePadStick(stick, x, y)
    -- Handle zooming with L1 + camera up/down.
    if stick == "Camera" then
        if IsModifier(0,0,1) then  -- L1 assumed to be assigned to Alt
            if not self.zoom_saved_pitch_speed then
                self.zoom_saved_pitch_speed =
                    C_CVar.GetCVar("GamePadCameraPitchSpeed")
                C_CVar.SetCVar("GamePadCameraPitchSpeed", 0)
            end
            if y > 0.1 then
                CameraZoomIn(y/4)
            elseif y < -0.1 then
                CameraZoomOut(-y/4)
                -- Since WoW doesn't have an independent "first-person view"
                -- state, we allow normally zooming out of FPV and silently
                -- cancel FPV state in that case.
                self.fpv_saved_zoom = nil
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
