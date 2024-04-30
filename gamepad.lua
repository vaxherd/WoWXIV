local _, WoWXIV = ...
WoWXIV.Gamepad = {}

local class = WoWXIV.class

local GameTooltip = GameTooltip
local GetItemCount = C_Item.GetItemCount
local GetItemInfo = C_Item.GetItemInfo
local IsHarmfulItem = C_Item.IsHarmfulItem
local IsHelpfulItem = C_Item.IsHelpfulItem

-- This addon assumes the following console variable settings:
--    GamePadEmulateShift = PADRTRIGGER
--    GamePadEmulateCtrl = PADLTRIGGER
--    GamePadEmulateAlt = PADLSHOULDER

-- Convenience function for checking the state of all modifiers:
local function IsModifier(shift, ctrl, alt)
    local function bool(x) return x and x~=0 end
    local function eqv(a,b) return bool(a) == bool(b) end
    return eqv(shift, IsShiftKeyDown()) and
           eqv(ctrl, IsControlKeyDown()) and
           eqv(alt, IsAltKeyDown())
end

------------------------------------------------------------------------

local GamepadBoundButton = class()

function GamepadBoundButton:__constructor(frame, binding_setting, command)
    self.binding_frame = frame
    self.binding_setting = binding_setting
    self.binding_command = command
    self:UpdateBinding()
end

function GamepadBoundButton:UpdateBinding()
    ClearOverrideBindings(self.binding_frame)
    SetOverrideBinding(self.binding_frame, false,
                       WoWXIV_config[self.binding_setting],
                       self.binding_command)
end

------------------------------------------------------------------------

-- Custom button used to securely activate quest items.
local QuestItemButton = class(GamepadBoundButton)

-- FIXME: The required target for quest items varies, and is not always
-- obvious from the item data available via the API; for example, Azure
-- Span sidequest "Setting the Defense" (ID 66489) has a quest item
-- "Arch Instructor's Wand" (ID 192471) intended to be used on a targeted
-- friendly NPC, but is neither "helpful" nor "harmful", while Rusziona's
-- Whistle (202293) from Little Scales Daycare quest "What's a Duck?"
-- (72459) is marked "helpful" but requires the player to be targeted in
-- order to fire.  Yet other items explicitly require a target of "none",
-- notably those which use the ground target cursor.  Ideally we would
-- just call UseQuestLogSpecialItem(log_index), but that's a protected
-- function and there's no secure action wrapper for it (as of 10.2.6),
-- so for the meantime we record specific items whose required targets we
-- know and use fallback logic for others.
local ITEM_TARGET = {
    [168482] = "none",    -- Benthic Sealant (56160: Plug the Geysers)
    [173691] = "target",  -- Anima Drainer (57932: Resource Drain)
    [173692] = "target",  -- Nemea's Javelin (58040: With Lance and Larion)
    [174043] = "none",    -- Phylactery of Arin'gore (61708: Drawing Out the Poison)
    [174197] = "target",  -- Loremaster's Notebook (58471: Aggressive Notation)
    [175827] = "player",  -- Ani-Matter Orb (57245: Ani-Matter Animator
    [177836] = "target",  -- Wingpierce Javelin (59771: History of Corruption)
    [177880] = "player",  -- Primordial Muck (59808: Muck It Up)
    [178464] = "player",  -- Discarded Harp (60188: Go Beyond! [Lonely Matriarch])
    [178791] = "none",    -- Carved Cloudfeather Call (60366: WANTED: Darkwing)
    [180008] = "none",    -- Resonating Anima Core (60609: Who Devours the Devourers?)
    [180009] = "none",    -- Resonating Anima Mote (60609: Who Devours the Devourers?)
    [180274] = "none",    -- Torch (60770: Squish and Burn)
    [180876] = "player",  -- Aqueous Material Accumulator (61189: Further Gelatinous Research)
    [181284] = "none",    -- Gormling in a Bag (61394: Gormling Toss: Tranquil Pools)
    [182189] = "player",  -- Fae Flute (61717: Gormling Piper: Tranquil Pools)
    [182303] = "player",  -- Assassin's Soulcloak (61765: Words of Warding)
    [182457] = "none",    -- Mirror Fragment (61967: Remedial Lessons)
    [182600] = "none",    -- Gormling in a Bag (62051: Gormling Toss: Spirit Glen)
    [182611] = "player",  -- Fae Flute (62068: Gormling Piper: Crumbled Ridge)
    [183725] = "none",    -- Moth Net (62459: Go Beyond!)
    [184876] = "none",    -- Cohesion Crystal [63455: Dead On Their Feet]
    [186089] = "target",  -- Niya's Staff (63840: They Grow Up So Quickly)
    [189384] = "target",  -- Ornithological Medical Kit (66071: Flying Rocs)
    [189454] = "target",  -- Feather-Plucker 3300 (65374: It's Plucking Time)
    [190188] = "player",  -- The Chirpsnide Auto-Excre-Collector (65490: Explosive Excrement)
    [191681] = "player",  -- Im-PECK-able Screechflight Disguise (65778: Screechflight Potluck)
    [191763] = "player",  -- Im-PECK-able Screechflight Disguise v2 (66299: The Awaited Egg-splosion)
    [192191] = "none",    -- Tuskarr Fishing Net (66411: Troubled Waters)
    [192471] = "target",  -- Arch Instructor's Wand (66489: Setting the Defense)
    [192555] = "player",  -- Borrowed Breath (66180: Wake the Ancients)
    [193826] = "target",  -- Trusty Dragonkin Rake (72991: Warm Dragonfruit Pie)
    [194441] = "none",    -- Bottled Water Elemental (66998: Fighting Fire with... Water)
    [198855] = "none",    -- Throw Net (70438: Flying Fish [and other fish restock dailies])
    [200153] = "target",  -- Aylaag Skinning Shear (70990: If There's Wool There's a Way)
    [200747] = "none",    -- Zikkori's Water Siphoning Device (70994: Drainage Solutions)
    [202293] = "player",  -- Rusziona's Whistle (72459: What's a Duck?)
    [202642] = "target",  -- Proto-Killing Spear (73194: Up Close and Personal)
    [203013] = "player",  -- Niffen Incense (73408: Sniffen 'em Out!)
    [203706] = "target",  -- Hurricane Scepter (74352: Whirling Zephyr)
    [203731] = "target",  -- Enchanted Bandage (74570: Aid Our Wounded)
    [204344] = "player",  -- Conductive Lodestone (74988: If You Can't Take the Heat)
    [204365] = "player",  -- Bundle of Ebon Spears (74991: We Have Returned)
    [204698] = "none",    -- Cataloging Camera (73044: Cataloging Horror)
    [205980] = "target",  -- Snail Lasso (72878: Slime Time Live)
    [208841] = "none",    -- True Sight (76550: True Sight)
    [210227] = "target",  -- Q'onzu's Faerie Feather (76992: Fickle Judgment)
    [211302] = "target",  -- Slumberfruit (76993: Turtle Power)
}

-- Special cases for quests which don't have items listed but really should.
local QUEST_ITEM = {
    -- Marasmius daily quest: Go Beyond! [Lonely Matriarch]
    [60188] = {
        map = 1565,  -- Ardenweald
        items = {
            178464,  -- Discarded Harp
        }
    },
    -- Ardenweald world quest: Who Devours the Devourers?
    [60609] = {
        map = 1565,  -- Ardenweald
        items = {
            180008,  -- Resonating Anima Core
            180009,  -- Resonating Anima Mote
        }
    },
}

function QuestItemButton:__constructor()
    self.item = nil
    self.pending_update = false
    self.last_update = 0

    local f = CreateFrame("Button", "WoWXIV_QuestItemButton", UIParent,
                          "SecureActionButtonTemplate, FadeableFrameTemplate")
    self.frame = f
    -- Place the button between the chat box and action bar.  (This size
    -- just fits with the default UI scale at resolution 2560x1440.)
    f:SetPoint("BOTTOM", -470, 10)
    f:SetSize(224, 112)
    f:SetAlpha(0)
    local holder = f:CreateTexture(nil, "ARTWORK")
    self.holder = holder
    holder:SetAllPoints()
    holder:SetTexture("Interface/ExtraButton/Default")
    local icon = f:CreateTexture(nil, "BACKGROUND")
    self.icon = icon
    icon:SetPoint("CENTER", 0, -1.5)
    icon:SetSize(42, 42)
    local cooldown = CreateFrame("Cooldown", "WoWXIV_QuestItemButtonCooldown",
                                 f, "CooldownFrameTemplate")
    self.cooldown = cooldown
    cooldown:SetAllPoints(icon)

    f:SetAttribute("type", "item")
    f:SetAttribute("item", nil)
    f:SetAttribute("unit", nil)
    f:RegisterForClicks("LeftButtonDown")
    self:__super(f, "gamepad_use_quest_item",
                 "CLICK WoWXIV_QuestItemButton:LeftButton")

    f:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
    f:RegisterEvent("BAG_UPDATE")  -- for QUEST_ITEM quests
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:SetScript("OnEvent", function() self:UpdateQuestItem() end)
    f:SetScript("OnEnter", function() self:OnEnter() end)
    f:SetScript("OnLeave", function() self:OnLeave() end)
    self:UpdateQuestItem()
end

function QuestItemButton:OnEnter()
    if GameTooltip:IsForbidden() then return end
    if not self.frame:IsVisible() then return end
    GameTooltip:SetOwner(self.frame, "ANCHOR_TOP")
    self:UpdateTooltip()
end

function QuestItemButton:OnLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

function QuestItemButton:UpdateTooltip()
    if GameTooltip:IsForbidden() or GameTooltip:GetOwner() ~= self.frame then
        return
    end
    if self.item then
        GameTooltip:SetItemByID(self.item)
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
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
                    if GetItemCount(quest_item) > 0 then
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
        elseif IsHelpfulItem(item) or IsHarmfulItem(item) then
            self.frame:SetAttribute("unit", "target")
        else
            self.frame:SetAttribute("unit", "player")
        end
        local icon_id = (select(10, GetItemInfo(item))
                         or "Interface/ICONS/INV_Misc_QuestionMark")
        self.icon:SetTexture(icon_id)
        if self.frame:GetAlpha() < 1 and (self.frame.fadeout:IsPlaying() or not self.frame.fadein:IsPlaying()) then
            self.frame.fadeout:Stop()
            self.frame.fadein:Play()
        end
        local start, duration = C_Item.GetItemCooldown(item)
        self.cooldown:SetCooldown(start, duration)
    else
        self.frame:SetAttribute("item", nil)
        if self.frame:GetAlpha() > 0 and (self.frame.fadein:IsPlaying() or not self.frame.fadeout:IsPlaying()) then
            self.frame.fadein:Stop()
            self.frame.fadeout:Play()
        end
    end

    self.item = item
    self:UpdateTooltip()
end

------------------------------------------------------------------------

local LeaveVehicleButton = class(GamepadBoundButton)

function LeaveVehicleButton:__constructor()
    local f = CreateFrame("Button", "WoWXIV_LeaveVehicleButton")
    self.frame = f
    f:SetScript("OnClick", function(_,...) self:OnClick(...) end)
    self:__super(f, "gamepad_leave_vehicle",
                 "CLICK WoWXIV_LeaveVehicleButton:LeftButton")
end

function LeaveVehicleButton:OnClick(button, down)
    -- Reproduce the behavior of MainMenuBarVehicleLeaveButton.
    -- VehicleExit() and TaxiRequestEarlyLanding() both appear to not
    -- be protected (as of 10.2.6), so we can just call these directly,
    -- which is convenient because there are two different native
    -- "leave" buttons (MainMenuBarVehicleLeaveButton for the small
    -- button above action bars, OverrideActionBarLeaveFrameLeaveButton
    -- for the button in the separate vehicle UI), and we can't bind
    -- one input to both buttons at once.
    if UnitOnTaxi("player") then
        TaxiRequestEarlyLanding()
        local native_button = MainMenuBarVehicleLeaveButton
        if native_button then  -- sanity check
            native_button:Disable()
            native_button:SetHighlightTexture(
                "Interface/Buttons/CheckButtonHilight", "ADD")
            native_button:LockHighlight()
        end
    else
        VehicleExit()
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
    WoWXIV.Gamepad.lvb = LeaveVehicleButton()
end

function WoWXIV.Gamepad.UpdateBindings()
    WoWXIV.Gamepad.qib:UpdateBinding()
    WoWXIV.Gamepad.lvb:UpdateBinding()
end
