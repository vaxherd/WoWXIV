local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
local Gamepad = WoWXIV.Gamepad

assert(Gamepad.GamepadBoundButton)  -- Ensure proper load order.

local class = WoWXIV.class

local GameTooltip = GameTooltip
local GetItemCount = C_Item.GetItemCount
local GetItemInfo = C_Item.GetItemInfo
local IsHarmfulItem = C_Item.IsHarmfulItem
local IsHelpfulItem = C_Item.IsHelpfulItem

------------------------------------------------------------------------

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
    [167231] = "none",    -- Delormi's Synchronous Thread (53807: A Stitch in Time)
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
    [180249] = "none",    -- Stone Fiend Tracker (60655: A Stolen Stone Fiend)
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
    [186474] = "target",  -- Korayn's Javelin (64080: Down to Earth)
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
    [203621] = "none",    -- Posidriss's Whistle (73014: A Green Who Can't Sleep?)
    [203706] = "target",  -- Hurricane Scepter (74352: Whirling Zephyr)
    [203731] = "target",  -- Enchanted Bandage (74570: Aid Our Wounded / 75374: To Defend the Span)
    [204343] = "none",    -- Trusty Dragonkin Rake (66989: Helpful Harvest)
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
    [210454] = "skip",    -- Spare Hologem (78068: An Artificer's Appeal / 78070: Pressing Deadlines / 78075: Moving Past / 78081: Pain Recedes)
    [211302] = "target",  -- Slumberfruit (76993: Turtle Power)
    [223988] = "skip",    -- Dalaran Hearthstone (79009: The Harbinger)
    [227669] = "skip",    -- Teleportation Scroll (81930: The War Within)
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

------------------------------------------------------------------------

-- Custom button used to securely activate quest items.
Gamepad.QuestItemButton = class(Gamepad.GamepadBoundButton)
local QuestItemButton = Gamepad.QuestItemButton

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
