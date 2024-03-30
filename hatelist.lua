local WoWXIV = WoWXIV
WoWXIV.HateList = {}

local CLM = WoWXIV.CombatLogManager
local UnitFlags = CLM.UnitFlags
local band = bit.band
local bor = bit.bor

--------------------------------------------------------------------------

local Enemy = {}
Enemy.__index = Enemy

function Enemy:New(parent, y)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.guid = nil    -- GUID of currently monitored unit, nil if none
    new.name = ""     -- Name of unit (saved because we can't get it by GUID)
    new.token = nil   -- Token by which we can look up unit info. nil if none

    local f = CreateFrame("Frame", nil, parent)
    new.frame = f
    f:SetSize(200, 30)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    f:Hide()

    local hate_icon = f:CreateTexture(nil, "ARTWORK")
    new.hate_icon = hate_icon
    hate_icon:SetPoint("TOPLEFT", f, "TOPLEFT")
    hate_icon:SetSize(19, 19)
    hate_icon:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")

    local name_label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    new.name_label = name_label
    name_label:SetPoint("TOPLEFT", f, "TOPLEFT", 23, -1)
    name_label:SetTextScale(1.1)

    local hp = WoWXIV.UI.Gauge:New(f, 52)
    new.hp = hp
    hp:SetBoxColor(0.533, 0.533, 0.533)
    hp:SetBarBackgroundColor(0.118, 0.118, 0.118)
    hp:SetBarColor(1, 1, 1)
    hp:SetPoint("TOPLEFT", f, "TOPLEFT", 19, -13)

    return new
end

-- Pass unit_guid=nil (or no arguments) to clear a previously set enemy.
function Enemy:SetUnit(unit_guid, name)
    self.guid = unit_guid
    if unit_guid then
        self:Update(name)
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

function Enemy:UnitGUID()
    return self.guid
end

function Enemy:CopyFrom(other)
    self:SetUnit(other.guid, other.name)
end

function Enemy:Update(new_name)
    if not self.guid then return end

    if self.token and UnitGUID(self.token) ~= self.guid then
        self.token = nil
    end
    if not self.token then
        self.token = UnitTokenFromGUID(self.guid)
    end

    if new_name then
        self.name = new_name
        self.name_label:SetText(new_name)
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
        local u = hate_level*20
        self.hate_icon:SetTexCoord(u/256.0, (u+19)/256.0, 38/256.0, 57/256.0)
    end

    -- Despite the name, this function returns a real number from 0.0 to 1.0,
    -- not a percentage!
    self.hp:Update(1.0, UnitPercentHealthFromGUID(self.guid) or 0, 0, 0)
end

--------------------------------------------------------------------------

local HateList = {}
HateList.__index = HateList

function HateList:New()
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.enemies = {}  -- 1 per enemy slot (all precreated)
    new.guids = {}    -- Mapping from enemy GUID to enemies[] slot
    new.unit_not_seen = {}  -- Safety net, see OnPeriodicUpdate()

    local f = CreateFrame("Frame", "WoWXIV_HateList", UIParent)
    new.frame = f
    f:Hide()
    f:SetPoint("TOPLEFT", 30, -(UIParent:GetHeight()/2))
    f:SetSize(200, 34)
    f:SetScript("OnEvent", function(self, ...) new:OnEvent(...) end)

    local bg_t = f:CreateTexture(nil, "BACKGROUND")
    new.bg_t = bg_t
    bg_t:SetPoint("TOP", f)
    bg_t:SetSize(f:GetWidth(), 4)
    bg_t:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    bg_t:SetTexCoord(0, 1, 0/256.0, 4/256.0)
    bg_t:SetVertexColor(0, 0, 0, 1)
    local bg_b = f:CreateTexture(nil, "BACKGROUND")
    new.bg_b = bg_b
    bg_b:SetPoint("BOTTOM", f)
    bg_b:SetSize(f:GetWidth(), 4)
    bg_b:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    bg_b:SetTexCoord(0, 1, 7/256.0, 11/256.0)
    bg_b:SetVertexColor(0, 0, 0, 1)
    local bg_c = f:CreateTexture(nil, "BACKGROUND")
    new.bg_c = bg_c
    bg_c:SetPoint("TOPLEFT", bg_t, "BOTTOMLEFT")
    bg_c:SetPoint("BOTTOMRIGHT", bg_b, "TOPRIGHT")
    bg_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    bg_c:SetTexCoord(0, 1, 4/256.0, 7/256.0)
    bg_c:SetVertexColor(0, 0, 0, 1)

    local highlight = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    new.highlight = highlight
    highlight:SetSize(200, 30)
    highlight:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    highlight:SetTexCoord(0, 1, 0/256.0, 11/256.0)
    highlight:SetVertexColor(1, 1, 1, 0.5)
    highlight:Hide()

    for i = 1, 8 do
        local y = -30*(i-1)
        tinsert(new.enemies, Enemy:New(f, y))
        tinsert(new.unit_not_seen, 0)
    end

    C_Timer.After(1, function() new:OnPeriodicUpdate() end)

    return new
end

function HateList:Enable(enable)
    local f = self.frame
    if enable then
        f:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")
        f:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
        f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        f:RegisterEvent("UNIT_FLAGS")
        f:RegisterEvent("UNIT_HEALTH")
        f:RegisterEvent("UNIT_NAME_UPDATE")
        f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        CLM.RegisterEventSubtype(self, self.OnAttack, "DAMAGE")
        CLM.RegisterEventSubtype(self, self.OnAttack, "PERIODIC_DAMAGE")
        CLM.RegisterEventSubtype(self, self.OnAttack, "MISS")
        CLM.RegisterEventCategory(self, self.OnUnitGone, "UNIT")
        self:Refresh()
    else
        f:Hide()
        f:UnregisterAllEvents()
        CLM.UnregisterAllEvents(self)
    end
end

function HateList:Refresh()
    self.guids = {}
    self:InternalRefresh(1)
end

function HateList:InternalRefresh(index)
    local units = {"target", "focus", "softtarget", "softenemy"}
    for i = 1, 40+#units do
        local unit = i<=#units and units[i] or "nameplate"..(i-#units)
        local guid = UnitGUID(unit)
        if guid and not self.guids[guid] then
            local name = UnitName(unit)
            local is_target, _, _, hate = UnitDetailedThreatSituation("player", unit)
            if is_target or hate then
                self.enemies[index]:SetUnit(guid, name)
                self.guids[guid] = index
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
    if event == "PLAYER_TARGET_CHANGED" then
        self:UpdateTargetHighlight()
        return
    end

    local guid = UnitGUID(unit)
    local index = self.guids[guid]

    if event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" or event == "UNIT_THREAT_LIST_UPDATE" then
        local is_target, _, _, hate = UnitDetailedThreatSituation("player", unit)
        if (is_target or hate) and not index then
            self:AddEnemy(guid, UnitName(unit))
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
    if UnitIsUnit(source, "player") or UnitIsUnit(source, "vehicle") then
        local index = self.guids[dest]
        if index then
            self.enemies[index]:Update(self)
        elseif band(event.dest_flags, bor(UnitFlags.REACTION_HOSTILE, UnitFlags.REACTION_NEUTRAL)) then
            self:AddEnemy(dest, event.dest_name)
        end
    elseif UnitIsUnit(dest, "player") or UnitIsUnit(dest, "vehicle") then
        -- Don't add charmed (etc) party members into list.
        if band(event.source_flags, UnitFlags.AFFILIATION_OUTSIDER) then
            if not self.guids[source] then
                self:AddEnemy(source, event.source_name)
            end
         end
    else
        -- We should get a UNIT_HEALTH update as well, but those seem to
        -- be delayed on occasion, so update health when we see hits here.
        local index = self.guids[source]
        if index then
            self.enemies[index]:Update()
        end
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

function HateList:AddEnemy(guid, name)
    for index = 1, #self.enemies do
        if not self.enemies[index]:UnitGUID() then
            self.enemies[index]:SetUnit(guid, name)
            self.guids[guid] = index
            self:ResizeFrame(index)
            break
        end
    end
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
    end

    self.enemies[index]:SetUnit(nil)
    self:ResizeFrame(index-1)
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

function HateList:UpdateTargetHighlight()
    local highlight = self.highlight
    highlight:Hide()

    local target_guid = UnitGUID("target")
    if not target_guid then return end

    for index, enemy in ipairs(self.enemies) do
        if enemy:UnitGUID() == target_guid then
            highlight:ClearAllPoints()
            highlight:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, (-30)*(index-1))
            highlight:Show()
            return
        end
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

-- Internal helper.
function HateList:ResizeFrame(count)
    if count > 0 then
        self.frame:SetHeight(4+30*count)
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------

-- Create the global enmity list object.
function WoWXIV.HateList.Create()
    WoWXIV.HateList.list = HateList:New()
    WoWXIV.HateList.Enable(WoWXIV_config["hatelist_enable"])
end

-- Enable or disable the enmity list display.
function WoWXIV.HateList.Enable(enable)
    WoWXIV.HateList.list:Enable(enable)
end
