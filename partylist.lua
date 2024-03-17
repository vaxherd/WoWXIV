local WoWXIV = WoWXIV
WoWXIV.PartyList = {}

--------------------------------------------------------------------------

local Member = {}
Member.__index = Member

function Member:New(parent, unit, npc_guid)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.unit = unit
    new.npc_id = npc_guid
    new.missing = false

    local f = CreateFrame("Frame", nil, parent)
    new.frame = f
    f:SetSize(256, 40)

    if not new.npc_id then
        new.class_bg = f:CreateTexture(nil, "BORDER")
        new.class_bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
        new.class_bg:SetSize(31, 31)
        new.class_bg:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
        new.class_icon = f:CreateTexture(nil, "ARTWORK")
        new.class_icon:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
        new.class_icon:SetSize(22, 22)
    end

    new.name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    new.name:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -4)
    new.name:SetTextScale(1.1)

    new.hp = WoWXIV.UI.Gauge:New(f, 86)
    new.hp:SetBoxColor(0.416, 0.725, 0.890)
    new.hp:SetBarBackgroundColor(0.027, 0.161, 0.306)
    new.hp:SetBarColor(1, 1, 1)
    new.hp:SetShowOvershield(true)
    new.hp:SetShowValue(true)
    new.hp:SetPoint("TOPLEFT", f, "TOPLEFT", 32, -12)

    new.mp = WoWXIV.UI.Gauge:New(f, 86)
    new.mp:SetBoxColor(0.416, 0.725, 0.890)
    new.mp:SetBarBackgroundColor(0.027, 0.161, 0.306)
    new.mp:SetBarColor(1, 1, 1)
    new.mp:SetShowValue(true)
    new.mp:SetPoint("TOPLEFT", f, "TOPLEFT", 136, -12)

    new.buffbar = WoWXIV.UI.AuraBar:New(unit, "ALL", "LEFT", 9, f, 240, 0)

    new:Refresh()
    new:Update()
    return new
end

function Member:SetYPosition(parent, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
end

function Member:SetMissing(missing)
    self.missing = missing
    if self.missing then
        if self.buffbar then self.buffbar:Delete() end
        self.buffbar = nil
        self.frame:SetAlpha(0.5)
    else
        self.frame:SetAlpha(1.0)
    end
end

function Member:Refresh(new_unit)  -- optional new unit token
    if new_unit then
        self.unit = new_unit
        if self.buffbar then self.buffbar:Delete() end
        self.buffbar = WoWXIV.UI.AuraBar:New(unit, "ALL", "LEFT", 9, f, 240, 0)
    end

    self.name:SetText("Lv"..UnitLevel(self.unit)
                      .." "..UnitName(self.unit))

    if not self.npc_id then
        local _, class, classID = UnitClass(self.unit)
        local role = UnitGroupRolesAssigned(self.unit)
        local specID, iconID, class_role
        if classID then
            specID, _, _, iconID, class_role = GetSpecializationInfo(GetSpecialization())
            if not role or role == "NONE" then role = class_role end
        end
        if role == "TANK" then
            self.class_bg:Show()
            self.class_bg:SetTexCoord(128/256.0, 159/256.0, 16/256.0, 47/256.0)
            self.class_icon:SetVertexColor(1, 1, 1, 0.4)
        elseif role == "HEALER" then
            self.class_bg:Show()
            self.class_bg:SetTexCoord(160/256.0, 191/256.0, 16/256.0, 47/256.0)
            self.class_icon:SetVertexColor(1, 1, 1, 0.4)
        elseif role == "DAMAGER" then
            self.class_bg:Show()
            self.class_bg:SetTexCoord(192/256.0, 223/256.0, 16/256.0, 47/256.0)
            self.class_icon:SetVertexColor(1, 1, 1, 0.4)
        else
            self.class_bg:Hide()
            self.class_icon:SetVertexColor(1, 1, 1, 1)
        end
        if specID then
            self.class_icon:SetTexture(iconID)
            self.class_icon:SetTexCoord(0, 1, 0, 1)
        else
            local atlas = GetClassAtlas(class)
            if atlas then
                self.class_icon:Show()
                self.class_icon:SetAtlas(atlas)
            else
                self.class_icon:Hide()
            end
        end
    end
end

function Member:Update(updateLabel)
    self.hp:Update(UnitHealthMax(self.unit), UnitHealth(self.unit),
                   UnitGetTotalAbsorbs(self.unit))
    self.mp:Update(UnitPowerMax(self.unit), UnitPower(self.unit), 0)

    if updateLabel then
        self.name:SetText("Lv"..UnitLevel(self.unit)
                          .." "..UnitName(self.unit))
    end
end

function Member:Delete()
    WoWXIV.DestroyFrame(self.frame)
end

---------------------------------------------------------------------------

local PartyList = {}
PartyList.__index = PartyList

function PartyList:New()
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.party = {}  -- mapping from party token or NPC GUID to Member instance
    new.allies = {}  -- list of {guid, token} for each ally
    new.ally_map = {}  -- map from ally tokens to GUIDs

    -- We could use our CreateEventFrame helper, but most events we're
    -- interested in will follow the same code path, so we write our
    -- own OnEvent handler to be concise.
    local f = CreateFrame("Frame", "WoWXIV_PartyList", UIParent)
    new.frame = f
    f.owner = new
    f:Hide()
    f:SetPoint("TOPLEFT", 30, -24)
    f:SetSize(256, 43)

    new.bg_t = f:CreateTexture(nil, "BACKGROUND")
    new.bg_t:SetPoint("TOP", f)
    new.bg_t:SetSize(f:GetWidth(), 4)
    new.bg_t:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.bg_t:SetTexCoord(0, 1, 0/256.0, 4/256.0)
    new.bg_b = f:CreateTexture(nil, "BACKGROUND")
    new.bg_b:SetPoint("BOTTOM", f)
    new.bg_b:SetSize(f:GetWidth(), 4)
    new.bg_b:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.bg_b:SetTexCoord(0, 1, 7/256.0, 11/256.0)
    new.bg_c = f:CreateTexture(nil, "BACKGROUND")
    new.bg_c:SetPoint("TOPLEFT", new.bg_t, "BOTTOMLEFT")
    new.bg_c:SetPoint("BOTTOMRIGHT", new.bg_b, "TOPRIGHT")
    new.bg_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.bg_c:SetTexCoord(0, 1, 4/256.0, 7/256.0)

    function f:OnPartyChange()
        f.owner:SetParty()
    end

    function f:OnMemberUpdate(unit)
        f.owner:UpdateParty(unit, false)
    end

    function f:OnMemberUpdateName(unit)
        f.owner:UpdateParty(unit, true)
    end

    f.events = {}
    f.events["ACTIVE_PLAYER_SPECIALIZATION_CHANGED"] = f.OnPartyChange
    f.events["GROUP_ROSTER_UPDATE"] = f.OnPartyChange
    f.events["PARTY_LEADER_CHANGED"] = f.OnPartyChange
    f.events["UNIT_ABSORB_AMOUNT_CHANGED"] = f.OnMemberUpdate
    f.events["UNIT_AURA"] = f.OnMemberUpdate
    f.events["UNIT_ENTERED_VEHICLE"] = f.OnPartyChange
    f.events["UNIT_EXITED_VEHICLE"] = f.OnPartyChange
    f.events["UNIT_HEALTH"] = f.OnMemberUpdate
    f.events["UNIT_LEVEL"] = f.OnMemberUpdateName
    f.events["UNIT_MAXHEALTH"] = f.OnMemberUpdate
    f.events["UNIT_MAXPOWER"] = f.OnMemberUpdate
    f.events["UNIT_NAME_UPDATE"] = f.OnMemberUpdateName
    f.events["UNIT_POWER_UPDATE"] = f.OnMemberUpdate

    -- We could theoretically register the unit-specific events for just
    -- the units we're interested in, but that would require refreshing the
    -- registration on every party/ally change, and we'll generally be
    -- interested in most events anyway so it's probably not worth the effort.
    for event, _ in pairs(f.events) do
        f:RegisterEvent(event)
    end

    f:SetScript("OnEvent", function(self, event, ...)
        if self.events[event] then
            self.events[event](self, ...)
        end
    end)

    C_Timer.After(1, function() new:RefreshAllies() end)

    new:SetParty()
    f:Show()
    return new
end

function PartyList:SetParty()
    local f = self.frame
    local y = 0

    local old_party = self.party
    self.party = {}
    self.ally_map = {}

    local tokens = {"player", "vehicle", "party1", "party2", "party3", "party4"}
    for _, token in ipairs(tokens) do
        local id = UnitGUID(token)
        if id then
            if old_party[token] then
                self.party[token] = old_party[token]
                self.party[token]:Refresh()
                old_party[token] = nil
            else
                local npc_id = nil
                if token == "vehicle" then npc_id = id end
                self.party[token] = Member:New(f, token, npc_id)
            end
            self.party[token]:SetYPosition(f, y)
            y = y - 40
        end
    end

    for i, id_token in ipairs(self.allies) do
        local id = id_token[1]
        local token = id_token[2]
        if old_party[id] then
            self.party[id] = old_party[id]
            if token then
                self.party[id]:SetMissing(false)
                self.party[id]:Refresh(token)
            else
                self.party[id]:SetMissing(true)
            end
            old_party[id] = nil
        elseif token then
            self.party[id] = Member:New(f, token, id)
        end
        if self.party[id] then
            self.party[id]:SetYPosition(f, y)
            y = y - 40
        end
        if token then
            self.ally_map[token] = id
        end
    end

    for _, member in pairs(old_party) do
        if member then
            member:Delete()
        end
    end

    self.frame:SetHeight((-y)+3)
end

function PartyList:UpdateParty(unit, updateLabel)
    local token = unit
    if self.ally_map[unit] then token = self.ally_map[unit] end
    if not self.party[token] then return end
    self.party[token]:Update(updateLabel)
end

local function FindToken(unit_id)
    if UnitGUID("focus") == unit_id then return "focus" end
    for i = 1, 40 do
        local token = "nameplate"..i
        if UnitGUID(token) == unit_id then return token end
    end
    return nil
end

function PartyList:AddAlly(unit_id)
    for _, id_token in ipairs(self.allies) do
        if id_token[1] == unit_id then return end
    end
    local token = FindToken(unit_id)
    if not token then
        print("Target's unit token not found!")
        return
    end
    table.insert(self.allies, {unit_id, token})
    self:SetParty()
end

function PartyList:ClearAllies()
    self.allies = {}
    self:SetParty()
end

function PartyList:RefreshAllies()
    local changed = false
    for i, id_token in ipairs(self.allies) do
        local id = id_token[1]
        local token = id_token[2]
        if not token or UnitGUID(token) ~= id then
            local newtoken = FindToken(id)
            if newtoken then
                id_token[2] = newtoken
            else
                id_token[2] = nil
            end
            changed = true
        end
    end
    if changed then
        self:SetParty()
    end

    C_Timer.After(1, function() self:RefreshAllies() end)
end

---------------------------------------------------------------------------

-- Create the global party list instance.
function WoWXIV.PartyList.Create()
    WoWXIV.PartyList.list = PartyList:New()
end

-- Mark the given unit (must be a GUID) as an ally to be shown in the
-- party list.
function WoWXIV.PartyList.AddAlly(unit_id)
    WoWXIV.PartyList.list:AddAlly(unit_id)
end

-- Remove all allies from the party list.
function WoWXIV.PartyList.ClearAllies()
    WoWXIV.PartyList.list:ClearAllies()
end
