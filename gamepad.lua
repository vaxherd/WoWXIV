local _, WoWXIV = ...
WoWXIV.Gamepad = {}

local class = WoWXIV.class

local strsub = string.sub
local GameTooltip = GameTooltip
local GetItemCount = C_Item.GetItemCount
local GetItemInfo = C_Item.GetItemInfo
local IsHarmfulItem = C_Item.IsHarmfulItem
local IsHelpfulItem = C_Item.IsHelpfulItem

------------------------------------------------------------------------

-- Convenience function for checking the state of all modifiers:
local function IsModifier(shift, ctrl, alt)
    local function bool(x) return x and x~=0 end
    local function eqv(a,b) return bool(a) == bool(b) end
    return eqv(shift, IsShiftKeyDown()) and
           eqv(ctrl, IsControlKeyDown()) and
           eqv(alt, IsAltKeyDown())
end

-- Convenience function for translating a modifier prefix on an input
-- specification into modifier flags:
local function ExtractModifiers(spec)
    local alt, ctrl, shift = 0, 0, 0
    if strsub(spec, 1, 4) == "ALT-" then
        alt = 1
        spec = strsub(spec, 5, -1)
    end
    if strsub(spec, 1, 5) == "CTRL-" then
        ctrl = 1
        spec = strsub(spec, 6, -1)
    end
    if strsub(spec, 1, 6) == "SHIFT-" then
        shift = 1
        spec = strsub(spec, 7, -1)
    end
    return shift, ctrl, alt, spec
end

-- Convenience function for checking whether a button press combined with
-- current modifiers matches an input specifier:
local function MatchModifiedButton(button, spec)
    local shift, ctrl, alt, raw_spec = ExtractModifiers(spec)
    return IsModifier(shift, ctrl, alt) and button == raw_spec
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
    [ 72018] = "none",    -- Discarded Weapon (29510: Putting Trash to Good Use)
    [ 72048] = "none",    -- Darkmoon Banner Kit (29520: Banners, Banners Everywhere!)
    [ 72049] = "none",    -- Darkmoon Banner (29520: Banners, Banners Everywhere!)
    [ 72056] = "none",    -- Plump Frogs (29509: Putting the Crunch in the Frog)
    [ 72057] = "none",    -- Breaded Frog (29509: Putting the Crunch in the Frog)
    [157540] = "none",    -- Battered S.E.L.F.I.E. Camera (51092: Picturesque Boralus)
    [168482] = "none",    -- Benthic Sealant (56160: Plug the Geysers)
    [173691] = "target",  -- Anima Drainer (57932: Resource Drain)
    [173692] = "target",  -- Nemea's Javelin (58040: With Lance and Larion)
    [174043] = "none",    -- Phylactery of Arin'gore (61708: Drawing Out the Poison)
    [174197] = "target",  -- Loremaster's Notebook (58471: Aggressive Notation)
    [175055] = "none",    -- H'partho's Whistle (58830: Aqir Instincts)
    [175827] = "player",  -- Ani-Matter Orb (57245: Ani-Matter Animator
    [177836] = "target",  -- Wingpierce Javelin (59771: History of Corruption)
    [177880] = "player",  -- Primordial Muck (59808: Muck It Up)
    [178464] = "player",  -- Discarded Harp (60188: Go Beyond! [Lonely Matriarch])
    [178791] = "none",    -- Carved Cloudfeather Call (60366: WANTED: Darkwing)
    [180008] = "none",    -- Resonating Anima Core (60609: Who Devours the Devourers?)
    [180009] = "none",    -- Resonating Anima Mote (60609: Who Devours the Devourers?)
    [180274] = "none",    -- Torch (60770: Squish and Burn)
    [180607] = "none",    -- Cypher of Blinding (61075: A Spark of Light)
    [180876] = "player",  -- Aqueous Material Accumulator (61189: Further Gelatinous Research)
    [181284] = "none",    -- Gormling in a Bag (61394: Gormling Toss: Tranquil Pools)
    [182189] = "player",  -- Fae Flute (61717: Gormling Piper: Tranquil Pools)
    [182303] = "player",  -- Assassin's Soulcloak (61765: Words of Warding)
    [182457] = "none",    -- Mirror Fragment (61967: Remedial Lessons)
    [182600] = "none",    -- Gormling in a Bag (62051: Gormling Toss: Spirit Glen)
    [182611] = "player",  -- Fae Flute (62068: Gormling Piper: Crumbled Ridge)
    [183725] = "none",    -- Moth Net (62459: Go Beyond! [Selenia Moth])
    [184513] = "none",    -- Containment Orb (63040: Guaranteed Delivery)
    [184876] = "none",    -- Cohesion Crystal [63455: Dead On Their Feet]
    [185949] = "target",  -- Korayn's Spear (The Skyhunt)
    [186089] = "target",  -- Niya's Staff (63840: They Grow Up So Quickly)
    [186097] = "none",    -- Heirmir's Runeblade (63945: The Soul Blade)
    [186199] = "target",  -- Lady Moonberry's Wand (63971: Snail Stomping)
    [187999] = "none",    -- Fishing Portal (65102: Fish Eyes)
    [188134] = "player",  -- Bronze Timepiece (65118: How to Glide with Your Dragon)
    [188139] = "player",  -- Bronze Timepiece (65120: How to Dive with Your Dragon)
    [188169] = "player",  -- Bronze Timepiece (65133: How to Use Momentum with Your Dragon)
    [189384] = "target",  -- Ornithological Medical Kit (66071: Flying Rocs)
    [189454] = "target",  -- Feather-Plucker 3300 (65374: It's Plucking Time)
    [190188] = "player",  -- The Chirpsnide Auto-Excre-Collector (65490: Explosive Excrement)
    [191160] = "none",    -- Sweetsuckle Bloom (66020: Omens and Incense)
    [191681] = "player",  -- Im-PECK-able Screechflight Disguise (65778: Screechflight Potluck)
    [191763] = "player",  -- Im-PECK-able Screechflight Disguise v2 (66299: The Awaited Egg-splosion)
    [191952] = "none",    -- Ley Scepter (65709: Arcane Pruning)
    [191953] = "none",    -- Bag of Helpful Goods (65709: Arcane Pruning)
    [191978] = "none",    -- Bag of Helpful Goods (65852: Straight to the Top)
    [192191] = "none",    -- Tuskarr Fishing Net (66411: Troubled Waters)
    [192436] = "target",  -- Ruby Spear (66122: Proto-Fight)
    [192465] = "none",    -- Wulferd's Award-Winning Camera (66524: Amateur Photography / 66525: Competitive Photography / 66527: Professional Photography / 66529: A Thousand Words)
    [192471] = "target",  -- Arch Instructor's Wand (66489: Setting the Defense)
    [192475] = "none",    -- R.A.D.D.E.R.E.R. (66428: Friendship For Granted)
    [192545] = "none",    -- Primal Flame Fragment (66439: Rapid Fire Plans)
    [192555] = "player",  -- Borrowed Breath (66180: Wake the Ancients)
    [192743] = "target",  -- Wild Bushfruit (65907: Favorite Fruit)
    [193064] = "target",  -- Smoke Diffuser (66734: Leave Bee Alone)
    [193212] = "none",    -- Marmoni Rescue Pack (66833: Marmoni in Distress)
    [193826] = "none",    -- Trusty Dragonkin Rake (66827: Flowers of our Labor / 72991: Warm Dragonfruit Pie)
    [193892] = "target",  -- Wish's Whistle (66680: Counting Sheep)
    [193917] = "target",  -- Rejuvenating Draught (65996: Veteran Reinforcements)
    [193918] = "none",    -- Jar of Fireflies (66830: Hornswoggled!)
    [194434] = "target",  -- Pungent Salve (66893: Beaky Reclamation)
    [194441] = "none",    -- Bottled Water Elemental (66998: Fighting Fire with... Water)
    [194447] = "target",  -- Totem of Respite (66656: Definitely Eternal Slumber)
    [194891] = "target",  -- Arcane Hook (65752: Arcane Annoyances)
    [197805] = "target",  -- Suspicious Persons Scanner (69888: Unusual Suspects)
    [198855] = "none",    -- Throw Net (70438: Flying Fish [and other fish restock dailies])
    [199928] = "none",    -- Flamethrower Torch (70856: Kill it with Fire)
    [200153] = "target",  -- Aylaag Skinning Shear (70990: If There's Wool There's a Way)
    [200526] = "none",    -- Steria's Charm of Invisibility (70338: They Took the Kits)
    [200747] = "none",    -- Zikkori's Water Siphoning Device (70994: Drainage Solutions)
    [202271] = "target",  -- Pouch of Gold Coins (72530: Anyway, I Started Bribing)
    [202293] = "player",  -- Rusziona's Whistle (72459: What's a Duck?)
    [202409] = "none",    -- Zalethgos's Whistle (73007: New Lenses)
    [202642] = "target",  -- Proto-Killing Spear (73194: Up Close and Personal)
    [202714] = "target",  -- M.U.S.T (73221: A Clear State of Mind)
    [202874] = "target",  -- Healing Draught (73398: Too Far Forward)
    [203013] = "player",  -- Niffen Incense (73408: Sniffen 'em Out!)
    [203182] = "none",    -- Fish Food (72651: Carp Care)
    [203706] = "target",  -- Hurricane Scepter (74352: Whirling Zephyr)
    [203731] = "target",  -- Enchanted Bandage (74570: Aid Our Wounded)
    [204344] = "player",  -- Conductive Lodestone (74988: If You Can't Take the Heat)
    [204365] = "player",  -- Bundle of Ebon Spears (74991: We Have Returned)
    [204698] = "none",    -- Cataloging Camera (73044: Cataloging Horror)
    [205980] = "target",  -- Snail Lasso (72878: Slime Time Live)
    [208181] = "skip",    -- Shandris's Scouting Report (76317: Call of the Dream)
    [208182] = "player",  -- Bronze Timepiece (77345: The Need For Higher Velocities)
    [208206] = "none",    -- Teleportation Crystal (77408: Prophecy Stirs)
    [208841] = "none",    -- True Sight (76550: True Sight)
    [208983] = "none",    -- Yvelyn's Assistance (76520: A Shared Dream)
    [210014] = "none",    -- Mysterious Ageless Seeds (77209: Seed Legacy)
    [210227] = "target",  -- Q'onzu's Faerie Feather (76992: Fickle Judgment)
    [210454] = "skip",    -- Spare Hologem (78068: An Artificer's Appeal)
    [211302] = "target",  -- Slumberfruit (76993: Turtle Power)
    [223988] = "skip",    -- Dalaran Hearthstone (79009: The Harbinger)
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
            180008,       -- Resonating Anima Core
            {180009, 5},  -- Resonating Anima Mote
        }
    },
    -- Waking Shores sidequest: Rapid Fire Plans
    [66439] = {
        map = 2022,  -- Waking Shores
        items = {
            {192545, 8},  -- Primal Flame Fragment
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
                    local amount = 1
                    if type(quest_item) == "table" then
                        quest_item, amount = unpack(quest_item)
                    end
                    if GetItemCount(quest_item) >= amount then
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
                -- Explicitly exclude certain items from the button
                -- (generally items we don't want to use by accident,
                -- like warp items for scenario starting quests)
                if ITEM_TARGET[item] == "skip" then item = nil end
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

local MenuCursor = class()

function MenuCursor:__constructor()
    -- Is the player currently using gamepad input?  (Mirrors the
    -- GAME_PAD_ACTIVE_CHANGED event.)
    self.gamepad_active = false
    -- Frame which currently has the cursor's input focus, nil if none.
    self.focus = nil
    -- Stack of saved focus frames, used with PushFocus() and PopFocus().
    self.focus_stack = {}

    -- The following are only used when self.focus is not nil:

    -- List of subframes which are valid targets for cursor movement.
    self.targets = nil
    -- Subframe which the cursor is currently targeting.
    self.cur_target = nil
    -- Last targeted subframe, used when the cursor is temporarily hidden
    -- (such as due to mouse movement).
    self.saved_target = nil
    -- Function to call when the cancel button is pressed (receives self
    -- as an argument).  If nil, no action is taken.
    self.cancel_func = nil
    -- Subframe (button) to be clicked on a gamepad cancel button press,
    -- or nil for none.  If set, cancel_func is ignored.
    self.cancel_button = nil

    -- This is a SecureActionButtonTemplate only so that we can
    -- indirectly click the button pointed to by the cursor.
    local f = CreateFrame("Button", "WoWXIV_MenuCursor", UIParent,
                          "SecureActionButtonTemplate")
    self.frame = f
    f:Hide()
    f:SetFrameStrata("TOOLTIP")  -- Make sure it stays on top.
    f:SetSize(32, 32)
    f:SetScript("OnShow", function() self:OnShow() end)
    f:SetScript("OnHide", function() self:OnHide() end)
    f:SetScript("OnEvent", function(_,...) self:OnEvent(...) end)
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("GOSSIP_CLOSED")
    f:RegisterEvent("GOSSIP_SHOW")
    f:RegisterEvent("QUEST_COMPLETE")
    f:RegisterEvent("QUEST_DETAIL")
    f:RegisterEvent("QUEST_FINISHED")
    f:RegisterEvent("QUEST_GREETING")
    f:RegisterEvent("QUEST_PROGRESS")
    f:RegisterEvent("SHIPMENT_CRAFTER_CLOSED")
    f:RegisterEvent("SHIPMENT_CRAFTER_OPENED")
    f:SetAttribute("type1", "click")
    f:SetAttribute("type2", "click")
    f:SetAttribute("clickbutton1", nil)
    f:SetAttribute("clickbutton2", nil)
    f:HookScript("OnClick", function(_,...) self:OnClick(...) end)
    f:RegisterForClicks("AnyDown")

    for i = 1, STATICPOPUP_NUMDIALOGS do
        local frame_name = "StaticPopup" .. i
        local frame = _G[frame_name]
        assert(frame)
        self:HookShow(frame, "StaticPopup_SetShown")
    end
    if CovenantSanctumFrame then
        self:OnEvent("ADDON_LOADED", "Blizzard_CovenantSanctum")
    end
    if PlayerChoiceFrame then
        self:OnEvent("ADDON_LOADED", "Blizzard_PlayerChoice")
    end

    local texture = f:CreateTexture(nil, "ARTWORK")
    self.texture = texture
    texture:SetAllPoints()
    texture:SetTexture("Interface/CURSOR/Point")  -- Default mouse cursor image
    -- Flip it horizontally to distinguish it from the mouse cursor.
    texture:SetTexCoord(1, 0, 0, 1)
end

-- Hook a frame's Show/Hide/SetShown methods, calling OnEvent() with tne
-- given event name and the show/hide status (true = show, false = hide)
-- whenever one of the methods is called.  The frame itself is passed as
-- a second argument to the event, for use when handling multiple related
-- frames with a single event (like StaticPopups).
function MenuCursor:HookShow(frame, event)
    hooksecurefunc(frame, "Show", function()
        self:OnEvent(event, true, frame)
    end)
    hooksecurefunc(frame, "Hide", function()
        self:OnEvent(event, false, frame)
    end)
    hooksecurefunc(frame, "SetShown", function(_, shown)
        self:OnEvent(event, shown, frame)
    end)
end

-- Generic cancel_func to close a frame.
function MenuCursor:CancelFrame()
    local frame = self.focus
    self:ClearFocus()
    frame:Hide()
end

-- Generic cancel_func to close a UI frame.  Equivalent to CancelFrame()
-- but with calling HideUIPanel(focus) instead of focus:Hide().
function MenuCursor:CancelUIPanel()
    local frame = self.focus
    self:ClearFocus()
    HideUIPanel(frame)
end

-- Shared cancel_func used for quest frames.
function MenuCursor:CancelQuestFrame()
    self:ClearFocus()
    CloseQuest()
end

function MenuCursor:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "Blizzard_CovenantSanctum" then
            self:HookShow(CovenantSanctumFrame, "CovenantSanctumFrame_SetShown")
        elseif name == "Blizzard_PlayerChoice" then
            self:HookShow(PlayerChoiceFrame, "PlayerChoiceFrame_SetShown")
        end

    elseif event == "GAME_PAD_ACTIVE_CHANGED" then
        local active = ...
        self.gamepad_active = active
        self:UpdateCursor()

    elseif event == "PLAYER_REGEN_DISABLED" then
        self:UpdateCursor(true)

    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UpdateCursor(false)

    elseif event == "GOSSIP_CLOSED" then
        -- This event can fire even when the gossip window was never opened
        -- (generally when a menu opens instead), so don't assume we're in
        -- gossip menu state.
        if self.focus == GossipFrame then
            self:ClearFocus()
            self:UpdateCursor()
        end

    elseif event == "GOSSIP_SHOW" then
        if not GossipFrame:IsVisible() then
            return  -- Flight map, etc.
        end
        
        self:SetFocus(GossipFrame)
        self.cancel_func = self.CancelUIPanel
        local goodbye = GossipFrame.GreetingPanel.GoodbyeButton
        self.targets = {[goodbye] = {can_activate = true,
                                     lock_highlight = true}}
        -- FIXME: This logic to find the quest / dialogue option buttons is
        -- a bit kludgey and certainly won't work if the list is scrolled
        -- to the point where some elements move offscreen.  Is there any
        -- better way to get the positions of individual scroll list elements?
        local subframes = {GossipFrame.GreetingPanel.ScrollBox.ScrollTarget:GetChildren()}
        local first_button, last_button = nil, nil
        for index, f in ipairs(subframes) do
            if f.GetElementData then
                local data = f:GetElementData()
                if (data.availableQuestButton or
                    data.activeQuestButton or
                    data.titleOptionButton)
                then
                    self.targets[f] = {can_activate = true,
                                       lock_highlight = true}
                    local y = f:GetTop()
                    if not first_button then
                        first_button = f
                        last_button = f
                    else
                        if y > first_button:GetTop() then first_button = f end
                        if y < last_button:GetTop() then last_button = f end
                    end
                end
            end
        end
        self.targets[first_button or goodbye].is_default = true
        self:UpdateCursor()

    elseif event == "QUEST_COMPLETE" then
        assert(QuestFrame:IsVisible())
        self:SetFocus(QuestFrame)
        self.cancel_func = self.CancelQuestFrame
        self.targets = {
            -- We explicitly suppress right movement to avoid the cursor
            -- jumping up to the rewards line (which is still available
            -- with "up" movement).
            [QuestFrameCompleteQuestButton] =
                {is_default = true, can_activate = true, lock_highlight = true,
                 right = false}
        }
        for i = 1, 99 do
            local name = "QuestInfoRewardsFrameQuestInfoItem" .. i
            local reward_frame = _G[name]
            if not reward_frame or not reward_frame:IsShown() then break end
            self.targets[reward_frame] = {
                can_activate = GetNumQuestChoices() > 1,
                set_tooltip = function()
                    QuestInfoRewardItemCodeTemplate_OnEnter(reward_frame)
                end,
            }
        end
        self:UpdateCursor()

    elseif event == "QUEST_DETAIL" then
        if not QuestFrame:IsVisible() then
            -- FIXME: some map-based quests (e.g. Blue Dragonflight campaign)
            -- start a quest directly from the map; we should support those too
            return
        end
        self:SetFocus(QuestFrame)
        self.cancel_func = self.CancelQuestFrame
        self.targets = {
            [QuestFrameAcceptButton] = {can_activate = true,
                                        lock_highlight = true,
                                        is_default = true},
            [QuestFrameDeclineButton] = {can_activate = true,
                                        lock_highlight = true},
        }
        for i = 1, 99 do
            local name = "QuestInfoRewardsFrameQuestInfoItem" .. i
            local reward_frame = _G[name]
            if not reward_frame or not reward_frame:IsShown() then break end
            self.targets[reward_frame] = {
                set_tooltip = function()
                    QuestInfoRewardItemCodeTemplate_OnEnter(reward_frame)
                end,
            }
        end
        self:UpdateCursor()

    elseif event == "QUEST_FINISHED" then
        assert(self.focus == nil or self.focus == QuestFrame)
        self:ClearFocus()
        self:UpdateCursor()

    elseif event == "QUEST_GREETING" then
        assert(QuestFrame:IsVisible())
        self:SetFocus(QuestFrame)
        self.cancel_func = self.CancelQuestFrame
        local goodbye = QuestFrameGreetingGoodbyeButton
        self.targets = {[goodbye] = {can_activate = true,
                                     lock_highlight = true}}
        local first_button, last_button = nil, nil
        for button in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            local y = button:GetTop()
            if not first_button then
                first_button = button
                last_button = button
            else
                if y > first_button:GetTop() then first_button = button end
                if y < last_button:GetTop() then last_button = button end
            end
        end
        self.targets[first_button or goodbye].is_default = true
        self:UpdateCursor()

    elseif event == "QUEST_PROGRESS" then
        assert(QuestFrame:IsVisible())
        self:SetFocus(QuestFrame)
        self.cancel_func = self.CancelQuestFrame
        local can_complete = QuestFrameCompleteButton:IsEnabled()
        self.targets = {
            [QuestFrameCompleteButton] = {can_activate = true,
                                          lock_highlight = true,
                                          is_default = can_complete},
            [QuestFrameGoodbyeButton] = {can_activate = true,
                                         lock_highlight = true,
                                         is_default = not can_complete},
        }
        for i = 1, 99 do
            local name = "QuestProgressItem" .. i
            local item_frame = _G[name]
            if not item_frame or not item_frame:IsShown() then break end
            self.targets[item_frame] = {
                -- This logic is coded directly into the XML templates as
                -- part (but not all) of the OnEnter handler, so we have to
                -- reimplement it ourselves.
                set_tooltip = function()
                    if GameTooltip:IsForbidden() then return end
                    if item_frame.objectType == "item" then
                        GameTooltip:SetOwner(item_frame, "ANCHOR_RIGHT")
                        GameTooltip:SetQuestItem(item_frame.type, item_frame:GetID())
                        GameTooltip_ShowCompareItem(GameTooltip)
                    elseif item_frame.objectType == "currency" then
                        GameTooltip:SetOwner(item_frame, "ANCHOR_RIGHT")
                        GameTooltip:SetQuestCurrency(item_frame.type, item_frame:GetID())
                    end
                end,
            }
        end
        self:UpdateCursor()

    elseif event == "SHIPMENT_CRAFTER_CLOSED" then
        assert(self.focus == nil or self.focus == GarrisonCapacitiveDisplayFrame)
        self:ClearFocus()
        self:UpdateCursor()

    elseif event == "SHIPMENT_CRAFTER_OPENED" then
        assert(GarrisonCapacitiveDisplayFrame:IsVisible())
        self:SetFocus(GarrisonCapacitiveDisplayFrame)
        self.cancel_func = self.CancelUIPanel
        self.targets = {
            [GarrisonCapacitiveDisplayFrame.CreateAllWorkOrdersButton] =
                {can_activate = true, lock_highlight = true},
            [GarrisonCapacitiveDisplayFrame.DecrementButton] =
                {can_activate = true, lock_highlight = true},
            [GarrisonCapacitiveDisplayFrame.IncrementButton] =
                {can_activate = true, lock_highlight = true},
            [GarrisonCapacitiveDisplayFrame.StartWorkOrderButton] =
                {can_activate = true, lock_highlight = true,
                 is_default = true},
        }
        self:UpdateCursor()

    elseif event == "CovenantSanctumFrame_SetShown" then
        local shown = ...
        if shown then
            assert(CovenantSanctumFrame:IsVisible())
            self:SetFocus(CovenantSanctumFrame)
            self.cancel_func = self.CancelFrame
            local function ChooseTalent(button)
                button:OnMouseDown()
                self:OnEvent("CovenantSanctumFrame_ChooseTalent", button)
            end
            self.targets = {
                [CovenantSanctumFrame.UpgradesTab.TravelUpgrade] =
                    {set_tooltip = function(self) self:OnEnter() end,
                     on_click = function(self) ChooseTalent(self) end},
                [CovenantSanctumFrame.UpgradesTab.DiversionUpgrade] =
                    {set_tooltip = function(self) self:OnEnter() end,
                     on_click = function(self) ChooseTalent(self) end},
                [CovenantSanctumFrame.UpgradesTab.AdventureUpgrade] =
                    {set_tooltip = function(self) self:OnEnter() end,
                     on_click = function(self) ChooseTalent(self) end},
                [CovenantSanctumFrame.UpgradesTab.UniqueUpgrade] =
                    {set_tooltip = function(self) self:OnEnter() end,
                     on_click = function(self) ChooseTalent(self) end},
                [CovenantSanctumFrame.UpgradesTab.DepositButton] =
                    {set_tooltip = function(self)  -- copied from XML
                         GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                         GameTooltip_SetTitle(GameTooltip, COVENANT_SANCTUM_DEPOSIT_TOOLTIP)
                         GameTooltip:Show()
                     end,
                     can_activate = true, lock_highlight = true,
                     is_default = true},
            }
            self:UpdateCursor()
        else
            assert(self.focus == nil or self.focus == CovenantSanctumFrame)
            self:ClearFocus()
            self:UpdateCursor()
        end

    elseif event == "CovenantSanctumFrame_ChooseTalent" then
        local upgrade_button = ...
        self:PushFocus(self.focus)
        self.cancel_func = function(self) self:PopFocus(self.focus) end
        self.targets = {
            [CovenantSanctumFrame.UpgradesTab.TalentsList.UpgradeButton] =
                {can_activate = true, lock_highlight = true,
                 is_default = true},
        }
        for frame in CovenantSanctumFrame.UpgradesTab.TalentsList.talentPool:EnumerateActive() do
            self.targets[frame] =
                {set_tooltip = function(self) self:OnEnter() end}
        end
        self:UpdateCursor()

    elseif event == "PlayerChoiceFrame_SetShown" then
        local shown = ...
        if shown then
            local KNOWN_FORMATS = {  -- Only handle formats we've explicitly verified.
                -- Emissary boost choice, Last Hurrah quest choice, etc.
                PlayerChoiceNormalOptionTemplate = true,
                -- Cobalt anima powers Superbloom dreamfruit, etc.
                PlayerChoiceGenericPowerChoiceOptionTemplate = true,
                -- Torghast anima powers
                PlayerChoiceTorghastOptionTemplate = true,
            }
            if not KNOWN_FORMATS[PlayerChoiceFrame.optionFrameTemplate] then
                return  
            end
            assert(PlayerChoiceFrame:IsVisible())
            self:SetFocus(PlayerChoiceFrame)
            self.cancel_func = self.CancelFrame
            self.targets = {}
            local leftmost = nil
            for option in PlayerChoiceFrame.optionPools:EnumerateActiveByTemplate(PlayerChoiceFrame.optionFrameTemplate) do
                for button in option.OptionButtonsContainer.buttonPool:EnumerateActive() do
                    self.targets[button] = {can_activate = true,
                                            lock_highlight = true}
                    if PlayerChoiceFrame.optionFrameTemplate == "PlayerChoiceTorghastOptionTemplate" then
                        self.targets[button].set_tooltip = function()
                            if option.OptionText:IsTruncated() then
                                option:OnEnter()
                            end
                        end
                    else
                        self.targets[button].send_enter_leave = true
                    end
                    if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                        leftmost = button
                    end
                end
            end
            if leftmost then  -- i.e., if we found any buttons
                self:SetTarget(leftmost)
            else
                self:ClearFocus()
            end
            self:UpdateCursor()
        else
            assert(self.focus == nil or self.focus == PlayerChoiceFrame)
            self:ClearFocus()
            self:UpdateCursor()
        end

    elseif event == "StaticPopup_SetShown" then
        local shown, frame = ...
        if shown then
            if self.focus == frame then return end  -- Sanity check
            self:PushFocus(frame)
            self.targets = {}
            local leftmost = nil
            for i = 1, 5 do
                local name = i==5 and "extraButton" or "button"..i
                local button = frame[name]
                assert(button)
                if button:IsShown() then
                    self.targets[button] = {can_activate = true,
                                            lock_highlight = true}
                    if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                        leftmost = button
                    end
                end
            end
            if leftmost then  -- i.e., if we found any buttons
                self:SetTarget(leftmost)
                if frame.button2:IsShown() then
                    self.cancel_button = frame.button2
                end
            else
                self:PopFocus(frame)
            end
            self:UpdateCursor()
        else
            self:PopFocus(frame)
            self:UpdateCursor()
        end

    end
end

-- Set the focus frame to the given frame.  Any previous focus frame is
-- cleared.
function MenuCursor:SetFocus(frame)
    self.focus = frame
    self.cur_target = nil
    self.saved_target = nil
    self.cancel_func = nil
    self.cancel_button = nil
end

-- Clear any current focus frame, hiding the menu cursor if it is displayed.
function MenuCursor:ClearFocus()
    self:SetTarget(nil)
    self.focus = nil
end

-- Set the focus frame to the given frame, saving the current focus frame
-- state so that it will be restored on a call to PopFocus().
function MenuCursor:PushFocus(frame)
    if self.focus then
        local focus_state = {
            frame = self.focus, 
            targets = self.targets,
            cur_target = self.cur_target,
            saved_target = self.saved_target,
            cancel_func = self.cancel_func,
            cancel_button = self.cancel_button,
        }
        tinsert(self.focus_stack, focus_state)
        self:SetTarget(nil)  -- clear current button's highlight/tooltip
    end
    self:SetFocus(frame)
end

-- Pop the given frame from the focus stack, if it exists in the stack.
-- If the frame is the top frame, the previous focus state is restored.
-- If the frame is in the stack but not on top (such as if multiple
-- frames are hidden at once but not in the reverse order of being shown),
-- it is removed from the stack but the focus state remains unchanged.
function MenuCursor:PopFocus(frame)
    if self.focus == frame then
        if #self.focus_stack > 0 then
            self:SetTarget(nil)
            local focus_state = tremove(self.focus_stack)
            self.focus = focus_state.frame
            self.targets = focus_state.targets
            self.saved_target = focus_state.saved_target
            self.cancel_func = focus_state.cancel_func
            self.cancel_button = focus_state.cancel_button
            self:SetTarget(focus_state.cur_target)
        else
            self:ClearFocus()
        end
        self:UpdateCursor()
    else
        for i, focus_state in ipairs(self.focus_stack) do
            if focus_state.frame == frame then
                tremove(self.focus_stack, i)
                break
            end
        end
    end
end

function MenuCursor:SetTarget(target)
    local old_target = self.cur_target
    if old_target then
        local params = self.targets[old_target]
        if params.lock_highlight then
            old_target:UnlockHighlight()
        end
        if params.send_enter_leave then
            old_target:OnLeave()
        end
        if params.set_tooltip then
            if not GameTooltip:IsForbidden() then
                GameTooltip:Hide()
            end
        end
    end

    self.cur_target = target
    if target then
        local params = self.targets[target]
        if params.lock_highlight then
            target:LockHighlight()
        end
        if params.send_enter_leave then
            target:OnEnter()
        end
        if not GameTooltip:IsForbidden() then
            if self.targets[target].set_tooltip then
                self.targets[target].set_tooltip(target)
            else
                GameTooltip:Hide()
            end
        end
    end
end

function MenuCursor:UpdateCursor(in_combat)
    if in_combat == nil then
        in_combat = InCombatLockdown()
    end
    local f = self.frame

    if self.focus and not self.focus:IsVisible() then
        self:ClearFocus()
    end

    local target = self.cur_target
    if self.focus and self.gamepad_active and not in_combat then
        if not target then
            if self.saved_target then
                target = self.saved_target
            else
                for frame, params in pairs(self.targets) do
                    if params.is_default then
                        target = frame
                        break
                    end
                end
                if not target then
                    error("MenuCursor: no default target")
                    -- We make this a fatal error for now, but it would be
                    -- less intrusive to fall back to an arbitrary target,
                    -- hence we leave in this (currently unreachable) line.
                    target = next(self.targets)
                end
            end
            self:SetTarget(target)
        end
        self:SetCursorPoint(target)
        if self.targets[target].can_activate then
            f:SetAttribute("clickbutton1", target)
        else
            f:SetAttribute("clickbutton1", nil)
        end
        if self.cancel_button then
            f:SetAttribute("clickbutton2", self.cancel_button)
        else
            f:SetAttribute("clickbutton2", nil)
        end
        if not f:IsShown() then
            f:Show()
            f:SetScript("OnUpdate", function() self:OnUpdate() end)
            self:OnUpdate()
        else
            self:SetCancelBinding()
        end
        if not GameTooltip:IsForbidden() then
            if self.targets[target].set_tooltip then
                self.targets[target].set_tooltip(target)
            else
                GameTooltip:Hide()
            end
        end
    else
        if self.cur_target then
            self.saved_target = self.cur_target
            self:SetTarget(nil)
        end
        if f:IsShown() then  -- avoid unnecessary taint warnings
            f:Hide()
        end
        f:SetScript("OnUpdate", nil)
    end
end

function MenuCursor:SetCursorPoint(target)
    local f = self.frame
    f:ClearAllPoints()
    -- Work around frame reference limitations on secure buttons
    --f:SetPoint("TOPRIGHT", target, "LEFT")
    local x = target:GetLeft()
    local _, y = target:GetCenter()
    f:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", x, y-UIParent:GetHeight())
end

function MenuCursor:OnShow()
    local f = self.frame
    SetOverrideBinding(f, true, "PADDUP",
                       "CLICK WoWXIV_MenuCursor:DPadUp")
    SetOverrideBinding(f, true, "PADDDOWN",
                       "CLICK WoWXIV_MenuCursor:DPadDown")
    SetOverrideBinding(f, true, "PADDLEFT",
                       "CLICK WoWXIV_MenuCursor:DPadLeft")
    SetOverrideBinding(f, true, "PADDRIGHT",
                       "CLICK WoWXIV_MenuCursor:DPadRight")
    SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_confirm"],
                       "CLICK WoWXIV_MenuCursor:LeftButton")
    self:SetCancelBinding()
end

function MenuCursor:SetCancelBinding()
    local f = self.frame
    if self.cancel_button then
        SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_cancel"],
                           "CLICK WoWXIV_MenuCursor:RightButton")
    else
        SetOverrideBinding(f, true, WoWXIV_config["gamepad_menu_cancel"],
                           "CLICK WoWXIV_MenuCursor:Cancel")
    end
end

function MenuCursor:OnHide()
    ClearOverrideBindings(self.frame)
end

function MenuCursor:OnClick(button, down)
    if button == "DPadUp" then
        self:Move(0, 1, "up")
    elseif button == "DPadDown" then
        self:Move(0, -1, "down")
    elseif button == "DPadLeft" then
        self:Move(-1, 0, "left")
    elseif button == "DPadRight" then
        self:Move(1, 0, "right")
    elseif button == "LeftButton" then  -- i.e., confirm
        -- Click event is passed to target by SecureActionButtonTemplate.
        -- This code is called afterward, so it's possible that the target
        -- already closed our focus frame; avoid erroring in that case.
        if self.focus then
            local params = self.targets[self.cur_target]
            if params.on_click then params.on_click(self.cur_target) end
        end
    elseif button == "Cancel" then
        if self.cancel_func then
            self:cancel_func()
        end
        self:UpdateCursor()
    end
end

function MenuCursor:Move(dx, dy, dir)
    local cur_target = self.cur_target
    local params = self.targets[cur_target]
    if params[dir] ~= nil then
        -- A value of false indicates "suppress movement in this
        -- direction".  We have to use false and not nil because
        -- Lua can't distinguish between "key in table with nil value"
        -- and "key not in table".
        new_target = params[dir]
    else
        new_target = self:NextTarget(dx, dy)
    end
    if new_target then
        self:SetTarget(new_target)
        self:UpdateCursor()
    end
end

local function round(x) return math.floor(x+0.5) end
function MenuCursor:NextTarget(dx, dy)
    local cur_x0, cur_y0, cur_w, cur_h = self.cur_target:GetRect()
    local cur_x1 = cur_x0 + cur_w
    local cur_y1 = cur_y0 + cur_h
    local cur_cx = (cur_x0 + cur_x1) / 2
    local cur_cy = (cur_y0 + cur_y1) / 2
    --[[
         We attempt to choose the "best" movement target by selecting the
         target that (1) has the minimum angle from the movement direction
         and (2) within all targets matching (1), has the minimum parallel
         distance from the current cursor position.  Targets not in the
         movement direction (i.e., at least 90 degrees from the movement
         vector) are excluded.

         When calculating the angle and distance, we use the shortest
         distance between line segments through each frame perpendicular
         to the direction of movement: thus, for example, when moving
         vertically, we take the shortest distance between the horizontal
         center line of each frame.  Note that we do not need to consider
         overlap, since cases in which the segments overlap will be
         treated as "not in the direction of movement".
    ]]--
    local best, best_dx, best_dy = nil, nil, nil
    for frame, params in pairs(self.targets) do
        local f_x0, f_y0, f_w, f_h = frame:GetRect()
        local f_x1 = f_x0 + f_w
        local f_y1 = f_y0 + f_h
        local f_cx = (f_x0 + f_x1) / 2
        local f_cy = (f_y0 + f_y1) / 2
        local frame_dx, frame_dy
        if dx ~= 0 then
            frame_dx = f_cx - cur_cx
            if f_y1 < cur_y0 then
                frame_dy = f_y1 - cur_y0
            elseif f_y0 > cur_y1 then
                frame_dy = f_y0 - cur_y1
            else
                frame_dy = 0
            end
        else
            frame_dy = f_cy - cur_cy
            if f_x1 < cur_x0 then
                frame_dx = f_x1 - cur_x0
            elseif f_x0 > cur_x1 then
                frame_dx = f_x0 - cur_x1
            else
                frame_dx = 0
            end
        end
        if ((dx < 0 and frame_dx < 0)
         or (dx > 0 and frame_dx > 0)
         or (dy > 0 and frame_dy > 0)
         or (dy < 0 and frame_dy < 0))
        then
            frame_dx = math.abs(frame_dx)
            frame_dy = math.abs(frame_dy)
            local frame_dpar = dx~=0 and frame_dx or frame_dy  -- parallel
            local frame_dperp = dx~=0 and frame_dy or frame_dx -- perpendicular
            local best_dpar = dx~=0 and best_dx or best_dy
            local best_dperp = dx~=0 and best_dy or best_dx
            if not best then
                best_dpar, best_dperp = 1, 1e10  -- almost but not quite 90deg
            end
            if (frame_dperp / frame_dpar < best_dperp / best_dpar
                or (frame_dperp / frame_dpar == best_dperp / best_dpar
                    and frame_dpar < best_dpar))
            then
                best = frame
                best_dx = frame_dx
                best_dy = frame_dy
            end
        end
    end
    return best
end

function MenuCursor:OnUpdate()
    --[[
         Calling out to fetch the target's position and resetting the
         cursor anchor points every frame is not ideal, but we need to
         keep the cursor position updated when buttons change positions,
         such as:
            - Scrolling of gossip/quest text
            - BfA troop recruit frame on first open after /reload
            - Upgrade confirmation dialog for Shadowlands covenant sanctum
    ]]--
    self:SetCursorPoint(self.cur_target)
    local t = GetTime()
    t = t - math.floor(t)
    local xofs = -4 * math.sin(t * math.pi)
    self.texture:ClearPointsOffset()
    self.texture:AdjustPointsOffset(xofs, 0)
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
    -- Check for first-person view toggle.
    if MatchModifiedButton(button, WoWXIV_config["gamepad_toggle_fpv"]) then
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
    -- Handle zooming with modifier + camera up/down.
    if stick == "Camera" then
        local shift, ctrl, alt =
            ExtractModifiers(WoWXIV_config["gamepad_zoom_modifier"] .. "-")
        if IsModifier(shift, ctrl, alt) then
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
    WoWXIV.Gamepad.cursor = MenuCursor()
end

function WoWXIV.Gamepad.UpdateBindings()
    WoWXIV.Gamepad.qib:UpdateBinding()
    WoWXIV.Gamepad.lvb:UpdateBinding()
end
