local _, WoWXIV = ...
WoWXIV.PartyList = {}

local class = WoWXIV.class

local GameTooltip = GameTooltip
local strfind = string.find

-- Role type constants returned from ClassIcon:Set().
local ROLE_TANK = 1
local ROLE_HEALER = 2
local ROLE_DPS = 3

-- Background colors for each role.
local ROLE_COLORS = {
    [ROLE_TANK]   = {0.145, 0.212, 0.427},
    [ROLE_HEALER] = {0.184, 0.298, 0.141},
    [ROLE_DPS]    = {0.314, 0.180, 0.180},
}

--------------------------------------------------------------------------

local ClassIcon = class()

function ClassIcon:__constructor(parent)
    self.parent = parent
    self.tooltip_anchor = "BOTTOMRIGHT"

    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    f:SetSize(31, 31)
    f:HookScript("OnEnter", function() self:OnEnter() end)
    f:HookScript("OnLeave", function() self:OnLeave() end)

    self.bg = f:CreateTexture(nil, "BORDER")
    self.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    self.bg:SetSize(31, 31)
    self.bg:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")

    self.icon = f:CreateTexture(nil, "ARTWORK")
    self.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    self.icon:SetSize(22, 22)
end

function ClassIcon:OnEnter()
    if GameTooltip:IsForbidden() then return end
    if not self.frame:IsVisible() then return end
    GameTooltip:SetOwner(self.frame, "ANCHOR_"..self.tooltip_anchor)
    self:UpdateTooltip()
end

function ClassIcon:OnLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

function ClassIcon:UpdateTooltip()
    if GameTooltip:IsForbidden() or GameTooltip:GetOwner() ~= self.frame then
        return
    end
    if self.tooltip then
        GameTooltip:SetText(self.tooltip, HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

function ClassIcon:SetAnchor(anchor, x, y, tooltip_anchor)
    self.frame:SetPoint(anchor, self.parent, anchor, x, y)
    self.tooltip_anchor = tooltip_anchor
end

-- Returns detected role (ROLE_* constant) or nil.
function ClassIcon:Set(unit)
    local role_name, role_id, class_name, spec_name
    if unit then
        local role = UnitGroupRolesAssigned(unit)
        local class, class_id
        class_name, class, class_id = UnitClass(unit)
        local spec_index
        if class_id and unit == "player" then
            spec_index = GetSpecialization()
        end
        local spec_id, spec_icon
        if spec_index then
            local class_role
            spec_id, spec_name, _, spec_icon, class_role =
                GetSpecializationInfo(spec_index)
            if not role or role == "NONE" then role = class_role end
        end

        if role == "TANK" then
            role_id = ROLE_TANK
            role_name = " (Tank)"
            self.bg:Show()
            self.bg:SetTexCoord(128/256.0, 159/256.0, 16/256.0, 47/256.0)
            self.icon:SetVertexColor(1, 1, 1, 0.4)
        elseif role == "HEALER" then
            role_id = ROLE_HEALER
            role_name = " (Healer)"
            self.bg:Show()
            self.bg:SetTexCoord(160/256.0, 191/256.0, 16/256.0, 47/256.0)
            self.icon:SetVertexColor(1, 1, 1, 0.4)
        elseif role == "DAMAGER" then
            role_id = ROLE_DPS
            role_name = " (DPS)"
            self.bg:Show()
            self.bg:SetTexCoord(192/256.0, 223/256.0, 16/256.0, 47/256.0)
            self.icon:SetVertexColor(1, 1, 1, 0.4)
        else
            role_id = nil
            role_name = ""
            self.bg:Hide()
            self.icon:SetVertexColor(1, 1, 1, 1)
        end
        if spec_id then
            self.icon:SetTexture(spec_icon)
            self.icon:SetTexCoord(0, 1, 0, 1)
        else
            local atlas = class and GetClassAtlas(class) or nil
            if atlas then
                self.icon:Show()
                self.icon:SetAtlas(atlas)
            else
                self.icon:Hide()
            end
        end
    end  -- if unit

    if class_name then
        if spec_name then
            spec_name = spec_name .. " "
        else
            spec_name = ""
        end
        self.tooltip = spec_name .. class_name .. role_name
    else
        self.tooltip = nil
    end
    self:UpdateTooltip()

    return role_id
end

--------------------------------------------------------------------------

local Member = class()

local function NameForUnit(unit)
    local name = UnitName(unit)
    local level = UnitLevel(unit)
    if level > 0 then
        name = "Lv" .. level .. " " .. name
    end
    return name
end

function Member:__constructor(parent, unit, npc_guid)
    self.unit = unit
    self.npc_id = npc_guid
    self.missing = false

    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    f:SetSize(256, 40)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    self.bg = bg
    bg:SetAllPoints(f)
    bg:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    bg:SetTexCoord(0, 1, 4/256.0, 7/256.0)
    bg:SetVertexColor(0, 0, 0, 1)

    local highlight = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.highlight = highlight
    highlight:SetAllPoints(f)
    highlight:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    highlight:SetTexCoord(0, 1, 4/256.0, 7/256.0)
    highlight:SetVertexColor(1, 1, 1, 0.5)
    highlight:Hide()

    if not self.npc_id then
        self.class_icon = ClassIcon(f)
        self.class_icon:SetAnchor("TOPLEFT", 0, -5, "BOTTOMRIGHT")
    end

    local name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.name = name
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -3)
    name:SetTextScale(1.1)

    local hp = WoWXIV.UI.Gauge(f, 86)
    self.hp = hp
    hp:SetBoxColor(0.416, 0.725, 0.890)
    hp:SetBarBackgroundColor(0.027, 0.161, 0.306)
    hp:SetBarColor(1, 1, 1)
    hp:SetShowOvershield(true)
    hp:SetShowValue(true)
    hp:SetPoint("TOPLEFT", f, "TOPLEFT", 32, -11)

    local mp = WoWXIV.UI.Gauge(f, 86)
    self.mp = mp
    mp:SetBoxColor(0.416, 0.725, 0.890)
    mp:SetBarBackgroundColor(0.027, 0.161, 0.306)
    mp:SetBarColor(1, 1, 1)
    mp:SetShowValue(true)
    mp:SetPoint("TOPLEFT", f, "TOPLEFT", 136, -11)

    self.buffbar = WoWXIV.UI.AuraBar("ALL", "TOPLEFT", 9, 1, f, 240, -1)
    self.buffbar:SetUnit(unit)

    self:Refresh()
    self:Update()
end

function Member:SetYPosition(parent, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
end

function Member:SetMissing(missing)
    self.missing = missing
    if self.missing then
        self.buffbar:SetUnit(nil)
        self.frame:SetAlpha(0.5)
    else
        self.frame:SetAlpha(1.0)
    end
end

function Member:Refresh(new_unit)  -- optional new unit token
    if new_unit then
        self.unit = new_unit
        self.buffbar:SetUnit(new_unit)
    end

    self.name:SetText(NameForUnit(self.unit))

    local role_id
    if not self.npc_id then
        role_id = self.class_icon:Set(self.unit)
    end
    if WoWXIV_config["partylist_role_bg"] and role_id then
        local color = ROLE_COLORS[role_id]
        self.bg:SetVertexColor(color[1], color[2], color[3], 1)  -- FIXME: unpack doesn't work here?
    else
        self.bg:SetVertexColor(0, 0, 0, 1)
    end
end

function Member:Update(updateLabel)
    self.hp:Update(UnitHealthMax(self.unit), UnitHealth(self.unit),
                   UnitGetTotalAbsorbs(self.unit),
                   UnitGetTotalHealAbsorbs(self.unit))
    self.mp:Update(UnitPowerMax(self.unit), UnitPower(self.unit))

    if updateLabel then
        self.name:SetText(NameForUnit(self.unit))
    end

    if UnitIsUnit("target", self.unit=="vehicle" and "player" or self.unit) then
        self.highlight:Show()
    else
        self.highlight:Hide()
    end
end

---------------------------------------------------------------------------

local PartyList = class()

function PartyList:__constructor()
    self.party = {}  -- mapping from party token or NPC GUID to Member instance
    self.allies = {}  -- list of {guid, token} for each ally
    self.ally_map = {}  -- map from ally tokens to GUIDs

    -- We could use our CreateEventFrame helper, but most events we're
    -- interested in will follow the same code path, so we write our
    -- own OnEvent handler to be concise.
    local f = CreateFrame("Frame", "WoWXIV_PartyList", UIParent)
    self.frame = f
    f.owner = self
    f:Hide()
    f:SetPoint("TOPLEFT", 30, -24)
    f:SetSize(256, 48)

    self.bg_t = f:CreateTexture(nil, "BACKGROUND")
    self.bg_t:SetPoint("TOP", f)
    self.bg_t:SetSize(f:GetWidth(), 4)
    self.bg_t:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    self.bg_t:SetTexCoord(0, 1, 0/256.0, 4/256.0)
    self.bg_t:SetVertexColor(0, 0, 0, 1)
    self.bg_b = f:CreateTexture(nil, "BACKGROUND")
    self.bg_b:SetPoint("BOTTOM", f)
    self.bg_b:SetSize(f:GetWidth(), 4)
    self.bg_b:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    self.bg_b:SetTexCoord(0, 1, 7/256.0, 11/256.0)
    self.bg_b:SetVertexColor(0, 0, 0, 1)

    function f:OnPartyChange()
        f.owner:SetParty()
    end

    function f:OnTargetChange()
        for _, member in pairs(f.owner.party) do
            member:Update(false)
        end
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
    f.events["PLAYER_ENTERING_WORLD"] = f.OnPartyChange
    f.events["PLAYER_TARGET_CHANGED"] = f.OnTargetChange
    f.events["UNIT_ABSORB_AMOUNT_CHANGED"] = f.OnMemberUpdate
    f.events["UNIT_AURA"] = f.OnMemberUpdate
    f.events["UNIT_ENTERED_VEHICLE"] = f.OnPartyChange
    f.events["UNIT_EXITED_VEHICLE"] = f.OnPartyChange
    f.events["UNIT_HEALTH"] = f.OnMemberUpdate
    f.events["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"] = f.OnMemberUpdate
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

    C_Timer.After(1, function() self:RefreshAllies() end)

    self:SetParty()
    f:Show()
end

function PartyList:SetParty()
    local f = self.frame
    local y = -4

    local old_party = self.party
    self.party = {}
    self.ally_map = {}

    local tokens = {"player", "vehicle", "party1", "party2", "party3", "party4"}
    for _, token in ipairs(tokens) do
        local id = UnitGUID(token)
        if token == "vehicle" then
            -- Vehicles with "[DNT]" in the name are used when player
            -- movement is locked in certain events, such as the Ruby
            -- Lifeshrine sidequest "Stay a While".
            local name = UnitName(token)
            if name and strfind(name, "%[DNT]") then id = nil end
        end
        if id then
            if old_party[token] then
                self.party[token] = old_party[token]
                self.party[token]:Refresh()
                old_party[token] = nil
            else
                local npc_id = nil
                if token == "vehicle" then npc_id = id end
                self.party[token] = Member(f, token, npc_id)
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
            self.party[id] = Member(f, token, id)
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
            -- No way to destroy a frame!
        end
    end

    self.frame:SetHeight((-y)+4)
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
    WoWXIV.PartyList.list = PartyList()
    WoWXIV.HideBlizzardFrame(PartyFrame)
end

-- Refresh the party list.  Must be called to pick up config changes.
function WoWXIV.PartyList.Refresh()
    WoWXIV.PartyList.list:SetParty()
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
