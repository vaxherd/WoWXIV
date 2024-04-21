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
-- order to fire.  Yet other items explicitly require a target of "none".
-- Ideally we would just call UseQuestLogSpecialItem(log_index), but that's
-- a protected function and there's no secure action wrapper for it (as of
-- 10.2.6), so for the meantime we record specific items whose required
-- targets we know and use fallback logic for others.
local ITEM_TARGET = {
    -- Benthic Sealant (56160: Plug the Geysers)
    [168482] = "none",
    -- Loremaster's Notebook (58471: Aggressive Notation)
    [174197] = "target",
    -- Primordial Muck (59808: Muck It Up)
    [177880] = "player",
    -- Resonating Anima Core (60609: Who Devours the Devourers?)
    [180008] = "none",
    -- Resonating Anima Mote (60609: Who Devours the Devourers?)
    [180009] = "none",
    -- Torch (60770: Squish and Burn)
    [180274] = "none",
    -- Aqueous Material Accumulator (61189: Further Gelatinous Research)
    [180876] = "player",
    -- Gormling in a Bag (61394: Gormling Toss: Tranquil Pools)
    [181284] = "none",
    -- Fae Flute (61717: Gormling Piper: Tranquil Pools)
    [182189] = "player",
    -- Assassin's Soulcloak (61765: Words of Warding)
    [182303] = "player",
    -- Gormling in a Bag (62051: Gormling Toss: Spirit Glen)
    [182600] = "none",
    -- Niya's Staff (63840: They Grow Up So Quickly)
    [186089] = "target",
    -- Ornithological Medical Kit (66071: Flying Rocs)
    [189384] = "target",
    -- Feather-Plucker 3300 (65374: It's Plucking Time)
    [189454] = "target",
    -- The Chirpsnide Auto-Excre-Collector (65490: Explosive Excrement)
    [190188] = "player",
    -- Im-PECK-able Screechflight Disguise (65778: Screechflight Potluck)
    [191681] = "player",
    -- Im-PECK-able Screechflight Disguise v2 (66299: The Awaited Egg-splosion)
    [191763] = "player",
    -- Arch Instructor's Wand (66489: Setting the Defense)
    [192471] = "target",
    -- Borrowed Breath (66180: Wake the Ancients)
    [192555] = "player",
    -- Trusty Dragonkin Rake (72991: Warm Dragonfruit Pie)
    [193826] = "target",
    -- Bottled Water Elemental (66998: Fighting Fire with... Water)
    [194441] = "none",
    -- Rusziona's Whistle (72459: What's a Duck?)
    [202293] = "player",
}

-- Special cases for quests which don't have items listed but really should.
local QUEST_ITEM = {
    -- Ardenweald world quest: Who Devours the Devourers?
    [60609] = {
        map = 1565,  -- Ardenweald
        items = {
            180008,  -- Resonating Anima Core
            180009,  -- Resonating Anima Mote
        }
    }
}

function QuestItemButton:__constructor()
    self.item = nil
    self.pending_update = false
    self.last_update = 0

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
    f:RegisterEvent("BAG_UPDATE")  -- for QUEST_ITEM quests
    f:SetScript("OnEvent", function() self:UpdateQuestItem() end)
    self:UpdateQuestItem()
end

function QuestItemButton:UpdateQuestItem(event, is_retry)
    if not is_retry and self.pending_update then return end
    local now = GetTime()
    if InCombatLockdown() or now - self.last_update < 1 then
        self.pending_update = true
        C_Timer.After(1, function() self:UpdateQuestItem(event, true) end)
        return
    end
    self.pending_update = false
    self.last_update = now

    local item = nil

    for quest, info in pairs(QUEST_ITEM) do
        if C_QuestLog.IsOnQuest(quest) then
            if C_Map.GetBestMapForUnit("player") == info.map then
                for _, quest_item in ipairs(info.items) do
                    if C_Item.GetItemCount(quest_item) > 0 then
                        item = quest_item
                        break
                    end
                end
                if item then break end
            end
        end
    end
    if not item then
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
    end
    if item then
        -- Note that we have to use the "item:" format rather than just
        -- the numeric item ID, because the latter would be treated as an
        -- inventory index instead.  We can't use the item name because
        -- that fails when multiple items have the same name, such as the
        -- quest items for the various gormling world quests in Ardenweald.
        self.frame:SetAttribute("item", "item:"..item)
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
