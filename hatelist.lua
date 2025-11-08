local _, WoWXIV = ...
WoWXIV.HateList = {}

local class = WoWXIV.class
local list = WoWXIV.list
local Frame = WoWXIV.Frame

local CLM = WoWXIV.CombatLogManager
local UnitFlags = CLM.UnitFlags
local band = bit.band
local bor = bit.bor

--------------------------------------------------------------------------

local Enemy = class(Frame)

function Enemy:__allocator(parent, y)
    return __super("Frame", nil, parent)
end

function Enemy:__constructor(parent, y)
    self.guid = nil     -- GUID of currently monitored unit, nil if none
    self.name = ""      -- Name of unit (saved because we can't get it by GUID)
    self.token = nil    -- Token by which we can look up unit info, nil if none

    self:SetSize(200, 27)
    self:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    self:Hide()

    local hate_icon = self:CreateTexture(nil, "ARTWORK")
    self.hate_icon = hate_icon
    hate_icon:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -3)
    hate_icon:SetSize(19, 19)
    WoWXIV.SetUITexture(hate_icon)

    local name_label = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.name_label = name_label
    name_label:SetPoint("TOPLEFT", self, "TOPLEFT", 23, -1)
    name_label:SetTextScale(1.1)
    name_label:SetWordWrap(false)
    name_label:SetJustifyH("LEFT")
    name_label:SetWidth(self:GetWidth())

    local hp = WoWXIV.UI.Gauge(self, 52)
    self.hp = hp
    hp:SetBoxColor(0.533, 0.533, 0.533)
    hp:SetBarBackgroundColor(0.118, 0.118, 0.118)
    hp:SetBarColor(1, 1, 1)
    hp:SetSinglePoint("TOPLEFT", 19, -10)

    local cast_bar = WoWXIV.UI.CastBar(self, 110)
    self.cast_bar = cast_bar
    cast_bar:SetSinglePoint("TOPLEFT", 88, -4)
end

-- Pass unit_guid=nil (or no arguments) to clear a previously set enemy.
function Enemy:SetUnit(unit_guid, name)
    self.guid = unit_guid
    if unit_guid then
        self.token = nil  -- Force check in Update().
        self:Update(name)
        self:Show()
    else
        self.token = nil
        self:Hide()
    end
    self.cast_bar:SetUnit(self.token)
end

function Enemy:UnitGUID()
    return self.guid
end

function Enemy:UnitName()
    return self.name
end

function Enemy:CopyFrom(other)
    self:SetUnit(other.guid, other.name)
end

function Enemy:Update(new_name)
    if not self.guid then return end

    if not self.token or UnitGUID(self.token) ~= self.guid then
        self.token = UnitTokenFromGUID(self.guid)
        self.cast_bar:SetUnit(self.token)
    end
    if self.token then
        self:SetAlpha(1.0)
        self.hate_icon:Show()
        self.hp:Show()
        self.cast_bar:Show()
    else
        self:SetAlpha(0.5)
        self.hate_icon:Hide()
        self.hp:Hide()
        self.cast_bar:Hide()
    end

    if new_name then
        self.name = new_name
        local name_markup = new_name
        local class_atlas =
            (self.token and WoWXIV_config["hatelist_show_classification"]
             and WoWXIV.UnitClassificationIcon(self.token) or nil)
        if class_atlas then
            -- CreateAtlasMarkup() is defined in Blizzard's
            -- Interface/SharedXML/TextureUtil.lua
            local atlas_markup = CreateAtlasMarkup(class_atlas, 14, 14)
            -- It would be nice to insert a thin space here (a normal space
            -- is a bit overkill), but the default font unfortunately
            -- doesn't support U+2009 and friends, and it's not worth the
            -- effort of creating and managing an independent texture for
            -- the icon, so we suffer it being a bit tightly spaced.
            name_markup = atlas_markup .. name_markup
        end
        self.name_label:SetText(name_markup)
    end

    -- Despite API documentation claiming that UnitDetailedThreatSituation()
    -- takes a "mobGUID" as its second argument, GUIDs don't work and you
    -- have to pass a token ("target" etc) instead.  Likewise for the other
    -- (obsolete?) threat-related functions.
    if self.token then
        local is_target, _, _, hate = UnitDetailedThreatSituation("player", self.token)
        if not hate then hate = 0 end
        local hate_level
        if is_target then
            hate_level = 3
        elseif hate >= 100 then
            hate_level = 2
        elseif hate >= 50 then
            hate_level = 1
        else
            hate_level = 0
        end
        local v = 16 + hate_level*30
        WoWXIV.SetUITexCoord(self.hate_icon, 128, 157, v, v+29)
    end

    -- Despite the name, this function returns a real number from 0.0 to 1.0,
    -- not a percentage!
    local hp_frac = UnitPercentHealthFromGUID(self.guid) or 0
    self.hp:Update(1.0, hp_frac, 0, 0, 0)
end

--------------------------------------------------------------------------

local HateList = class(Frame)

function HateList:__allocator()
    return __super("Frame", "WoWXIV_HateList", UIParent)
end

function HateList:__constructor()
    self.enemies = list()        -- 1 per enemy slot (all precreated)
    self.guids = {}              -- Mapping from enemy GUID to enemies[] slot
    self.unit_not_seen = list()  -- Safety net, see OnPeriodicUpdate()

    self.base_y = -(UIParent:GetHeight()/2) -- May be pushed down by party list

    self:Hide()
    self:SetPoint("TOPLEFT", 30, base_y)
    self:SetSize(200, 31)
    self:SetScript("OnEvent", self.OnEvent)

    local bg = self:CreateTexture(nil, "BACKGROUND")
    self.bg = bg
    bg:SetAllPoints()
    WoWXIV.SetUITexture(bg, 0, 256, 0, 11)
    bg:SetTextureSliceMargins(32, 4, 32, 4)
    bg:SetVertexColor(0, 0, 0, 1)

    local highlight = self:CreateTexture(nil, "BACKGROUND")
    self.highlight = highlight
    highlight:SetSize(self:GetWidth(), self:GetHeight())
    highlight:SetPoint("TOPLEFT")
    WoWXIV.SetUITexture(highlight, 0, 256, 0, 11)
    highlight:SetTextureSliceMargins(32, 4, 32, 4)
    highlight:SetVertexColor(1, 1, 1, 0.5)
    highlight:Hide()

    for i = 1, 8 do
        local y = -2-27*(i-1)
        self.enemies:append(Enemy(self, y))
        self.unit_not_seen:append(0)
    end

    C_Timer.After(1, function() self:OnPeriodicUpdate() end)
end

function HateList:Enable(enable)
    if enable then
        self:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("UNIT_FLAGS")
        self:RegisterEvent("UNIT_HEALTH")
        self:RegisterEvent("UNIT_NAME_UPDATE")
        self:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        CLM.RegisterEventSubtype(self, self.OnAttack, "DAMAGE")
        CLM.RegisterEventSubtype(self, self.OnAttack, "PERIODIC_DAMAGE")
        CLM.RegisterEventSubtype(self, self.OnAttack, "MISS")
        CLM.RegisterEventCategory(self, self.OnUnitGone, "UNIT")
        self:Refresh(true)
    else
        self:Hide()
        self:UnregisterAllEvents()
        CLM.UnregisterAllEvents(self)
    end
end

function HateList:Refresh(rescan)
    if rescan then
        self.guids = {}
        self:InternalRefresh(1)
    else
        for enemy in self.enemies do
            if enemy:UnitGUID() then
                enemy:Update(enemy:UnitName())
            end
        end
    end
end

function HateList:InternalRefresh(index)
    local units = {"boss1", "boss2", "boss3", "boss4",
                   "boss5", "boss6", "boss7", "boss8",
                   "target", "focus", "softtarget", "softenemy"}
    for i = 1, 40+#units do
        local unit = i<=#units and units[i] or "nameplate"..(i-#units)
        local guid = UnitGUID(unit)
        if guid and not self.guids[guid] and not UnitIsDead(unit) then
            local name = UnitName(unit)
            local is_target, _, _, hate = UnitDetailedThreatSituation("player", unit)
            if is_target or hate then
                self:AddEnemy(guid, name, index)
                index = index+1
                if index > #self.enemies then break end
            end
        end
    end
    local count = index-1
    while index <= #self.enemies do
        self.enemies[index]:SetUnit(nil)
        index = index+1
    end
    self:ResizeFrame(count)
end

function HateList:OnEvent(event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        -- If we left combat, then by definition we have no aggro.
        assert(not InCombatLockdown())
        for enemy in self.enemies do
            enemy:SetUnit(nil)
        end
        self:ResizeFrame(0)
        self.guids = {}
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        self:UpdateTargetHighlight()
        return
    end

    local guid = UnitGUID(unit)
    local index = self.guids[guid]

    if event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" or event == "UNIT_THREAT_LIST_UPDATE" then
        local is_target, _, _, hate = UnitDetailedThreatSituation("player", unit)
        if (is_target or hate) and not index then
            local name, server = UnitName(unit)
            if server then name = name.."-"..server end
            self:AddEnemy(guid, name)
        end
    elseif UnitIsDead(unit) then
        if index then
            self:RemoveEnemy(index, guid)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" or event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED" then
        if index and UnitIsFriend("player", unit) then
            self:RemoveEnemy(index, guid)
        end
    else
        local name = (event == "UNIT_NAME_UPDATE") and UnitName(unit) or nil
        if index then
            self.enemies[index]:Update(name)
        end
    end
end

function HateList:OnAttack(event)
    local source = event.source
    local dest = event.dest
    local player_guid = UnitGUID("player")
    local vehicle_guid = UnitGUID("vehicle")
    if source == player_guid or source == vehicle_guid then
        local index = self.guids[dest]
        if index then
            self.enemies[index]:Update()
        elseif band(event.dest_flags, bor(UnitFlags.REACTION_HOSTILE, UnitFlags.REACTION_NEUTRAL)) ~= 0 then
            self:AddEnemy(dest, event.dest_name)
        end
    elseif dest == player_guid or dest == vehicle_guid then
        -- Don't add charmed (etc) party members into list.
        if band(event.source_flags, UnitFlags.AFFILIATION_OUTSIDER) ~= 0 then
            -- Avoid adding dead enemies into the list.  This is annoyingly
            -- complicated because UnitIsDead() only accepts tokens, not
            -- GUIDs, and dead enemies generally don't have tokens.
            local allow
            local token = UnitTokenFromGUID(source)
            if token then
                allow = not UnitIsDead(token)
            else
                allow = event.subtype ~= "PERIODIC_DAMAGE"
            end
            if allow then
                if not self.guids[source] then
                    self:AddEnemy(source, event.source_name)
                end
            end
         end
    end
    -- We should get UNIT_HEALTH updates for enemy health changes as well,
    -- but those seem to be delayed on occasion, so update health when we
    -- see hits here.
    local index = self.guids[source]
    if index then
        self.enemies[index]:Update()
    end
end

function HateList:OnUnitGone(event)
    -- Sanity check: make sure we're not surprised by newly added UNIT_* events
    assert(event.subtype == "DIED" or event.subtype == "DESTROYED")

    local guid = event.dest
    local index = self.guids[guid]
    if index then
        self:RemoveEnemy(index, guid)
    end
end

-- |index| is an optimization for when the first unused index is already
-- known (i.e. for calling from InternalRefresh()).
function HateList:AddEnemy(guid, name, index)
    if not index then
        for i = 1, #self.enemies do
            if not self.enemies[i]:UnitGUID() then
                index = i
                break
            end
        end
        if not index then
            return  -- No free slots.
        end
        self:ResizeFrame(index)
    end
    self.enemies[index]:SetUnit(guid, name)
    self.guids[guid] = index
    if UnitGUID("target") == guid then
        self:UpdateTargetHighlight()
    end
end

-- guid is passed for convenience, to delete it from the guids table.
function HateList:RemoveEnemy(index, guid)
    while index < #self.enemies and self.enemies[index+1]:UnitGUID() do
        self.enemies[index]:CopyFrom(self.enemies[index+1])
        self.guids[self.enemies[index]:UnitGUID()] = index
        index = index+1
    end

    -- If the list was full, there might be other enemies to bring into
    -- the newly-opened last slot, so search for one to add.
    if index == #self.enemies then
        self:InternalRefresh(index)
    else
        self.enemies[index]:SetUnit(nil)
        self:ResizeFrame(index-1)
    end
    self:UpdateTargetHighlight()

    -- Lua zealots don't want you to think about performance, so there's
    -- no way to explicitly remove a key from a table.  The Lua engine
    -- used in WoW may or may not expunge keys with nil values, but to
    -- avoid any risk of memory bloat, we explicitly recreate the table
    -- every 100 iterations.
    self.guids[guid] = nil
    self.guids_remove_count = (self.guids_remove_count or 0) + 1
    if self.guids_remove_count >= 100 then
        local new_guids = {}
        for k, v in pairs(self.guids) do
            if v then new_guids[k] = v end
        end
        self.guids = new_guids
        self.guids_remove_count = 0
    end
end

-- Called periodically as a fallback to ensure that enemies which
-- disappeared without us noticing are still removed.
function HateList:OnPeriodicUpdate()
    local index = 0
    while index < #self.enemies do
        index = index+1
        local enemy = self.enemies[index]
        local guid = enemy:UnitGUID()
        if not guid then
            self.unit_not_seen[index] = 0
        else
            local token = UnitTokenFromGUID(guid)
            if token and UnitIsDead(token) then
                self:RemoveEnemy(index, guid)
                index = index-1
            elseif not token then
                self.unit_not_seen[index] = self.unit_not_seen[index] + 1
                if self.unit_not_seen[index] >= 5 then
                    self:RemoveEnemy(index, guid)
                    index = index-1
                end
            end
        end
    end
    C_Timer.After(1, function() self:OnPeriodicUpdate() end)
end

function HateList:ResizeFrame(count)
    if count > 0 then
        self:SetHeight(4+27*count)
        self:Show()
    else
        self:Hide()
    end
end

function HateList:UpdateTargetHighlight()
    local highlight = self.highlight
    highlight:Hide()

    local target_guid = UnitGUID("target")
    if not target_guid then return end

    for index, enemy in ipairs(self.enemies) do
        if enemy:UnitGUID() == target_guid then
            highlight:ClearAllPoints()
            highlight:SetPoint("TOPLEFT", self, "TOPLEFT",
                               0, -1-27*(index-1))
            highlight:Show()
            return
        end
    end
end

function HateList:SetMinTop(y)
    if y > self.base_y then  -- Remember that Y coordinates are negative!
        y = self.base_y
    end
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", 30, y)
end

---------------------------------------------------------------------------

-- Create the global enmity list object.
function WoWXIV.HateList.Create()
    WoWXIV.HateList.list = HateList()
    WoWXIV.HateList.Enable(WoWXIV_config["hatelist_enable"])
end

-- Enable or disable the enmity list display.
function WoWXIV.HateList.Enable(enable)
    WoWXIV.HateList.list:Enable(enable)
end

-- Refresh the enmity list to reflect changed settings.
-- Pass rescan=true to clear the list and rescan for enemies; if false
-- or omitted, the list content will be preserved and only the display
-- content of enemies already on the list will be refreshed.
function WoWXIV.HateList.Refresh(rescan)
    WoWXIV.HateList.list:Refresh(rescan)
end

-- Record the bottom Y coordinate of the party list.  Called from
-- PartyList.SetParty() on party list update.
function WoWXIV.HateList.NotifyPartyListBottom(y)
    WoWXIV.HateList.list:SetMinTop(y-10)
end
