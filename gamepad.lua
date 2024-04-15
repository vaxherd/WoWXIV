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
    -- (item ID 180876, from Maldraxxus world quest "Further Gelatinous
    -- Research", quest ID 61189), though targeting the player seems to
    -- work in that case.  For now we use a kludge to detect cases likely
    -- to need the player targeted, but we need to find a better solution
    -- here.  Ideally we would just call UseQuestLogSpecialItem(log_index),
    -- but that's a protected function and there's no secure action wrapper
    -- for it (as of 10.2.6).
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
        -- Some quest items need to be targeted on the player for the
        -- item to activate.  This is our best guess at the condition
        -- for the moment, though it's not perfect.  See e.g. Azure Span
        -- sidequest "Setting the Defense" (ID 66489), in which an item
        -- (Arch Instructor's Wand, ID 192471) intended to be used on
        -- friendly NPCs matches this condition and thus can't be used
        -- if we force unit="player" (though it's also usable with a
        -- normal confirm button press).  Conversely, Rusziona's Whistle
        -- (202293) from Little Scales Daycare quest "What's a Duck?"
        -- (72459) requires the player to be targeted but is marked
        -- "helpful".
        if not C_Item.IsHelpfulItem(item) and not C_Item.IsHarmfulItem(item) then
            self.frame:SetAttribute("unit", "player")
        else
            self.frame:SetAttribute("unit", "target")
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
