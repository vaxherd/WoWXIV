local WoWXIV = WoWXIV
WoWXIV.PartyList = {}

------------------------------------------------------------------------

local Gauge = {}
Gauge.__index = Gauge

function Gauge:New(parent)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.max = 1
    new.cur = 1
    new.shield = 0

    new.frame = CreateFrame("Frame", nil, parent)
    local f = new.frame
    f:SetWidth(96)
    f:SetHeight(30)

    local box = f:CreateTexture(nil, "BORDER")
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -3)
    box:SetWidth(96)
    box:SetHeight(13)
    box:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box:SetTexCoord(0/256.0, 96/256.0, 12/256.0, 25/256.0)

    new.shieldbar = f:CreateTexture(nil, "ARTWORK")  -- goes under main bar
    new.shieldbar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -7)
    new.shieldbar:SetWidth(86)
    new.shieldbar:SetHeight(5)
    new.shieldbar:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.shieldbar:SetTexCoord(5/256.0, 91/256.0, 35/256.0, 40/256.0)

    new.bar = f:CreateTexture(nil, "OVERLAY")
    new.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    new.bar:SetWidth(86)
    new.bar:SetHeight(5)
    new.bar:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.bar:SetTexCoord(5/256.0, 91/256.0, 27/256.0, 32/256.0)

    new.overshield_l = f:CreateTexture(nil, "OVERLAY")
    new.overshield_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    new.overshield_l:SetWidth(5)
    new.overshield_l:SetHeight(7)
    new.overshield_l:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.overshield_l:SetTexCoord(0/256.0, 5/256.0, 43/256.0, 50/256.0)
    new.overshield_c = f:CreateTexture(nil, "OVERLAY")
    new.overshield_c:SetPoint("TOPLEFT", f, "TOPLEFT", 5, 0)
    new.overshield_c:SetWidth(86)
    new.overshield_c:SetHeight(7)
    new.overshield_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.overshield_c:SetTexCoord(5/256.0, 91/256.0, 43/256.0, 50/256.0)
    new.overshield_r = f:CreateTexture(nil, "OVERLAY")
    new.overshield_r:SetPoint("TOPLEFT", f, "TOPLEFT", 91, 0)
    new.overshield_r:SetWidth(5)
    new.overshield_r:SetHeight(7)
    new.overshield_r:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.overshield_r:SetTexCoord(91/256.0, 96/256.0, 43/256.0, 50/256.0)

    new.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    new.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -13)
    new.value:SetTextScale(1.3)
    new.value:SetText("1")

    return new
end

function Gauge:Update(max, cur, shield)
    self.max = max
    self.cur = cur
    self.shield = shield

    local bar_rel, shield_rel, overshield_rel
    if max > 0 then
        bar_rel = cur / max
        shield_rel = (cur + shield) / max
        if shield_rel > 1 then
            overshield_rel = shield_rel - 1
            shield_rel = 1
        else
            overshield_rel = 0
        end
    else
        bar_rel = 0
        shield_rel = 0
        overshield_rel = 0
    end

    local SIZE = 86
    local bar_w = bar_rel * SIZE
    if bar_w == 0 then bar_w = 0.001 end  --  WoW can't deal with 0 width
    local shield_w = shield_rel * SIZE
    local overshield_w = overshield_rel * SIZE

    self.bar:SetWidth(bar_w)
    self.bar:SetTexCoord(5/256.0, (5+bar_w)/256.0, 27/256.0, 32/256.0)

    if shield_w > bar_w then
        self.shieldbar:Show()
        self.shieldbar:SetTexCoord(5/256.0, (5+shield_w)/256.0, 35/256.0, 40/256.0)
    else
        self.shieldbar:Hide()
    end

    if overshield_w > 0 then
        self.overshield_l:Show()
        self.overshield_c:Show()
        self.overshield_c:SetWidth(overshield_w)
        self.overshield_c:SetTexCoord(5/256.0, (5+overshield_w)/256.0, 43/256.0, 50/256.0)
        self.overshield_r:Show()
    else
        self.overshield_l:Hide()
        self.overshield_c:Hide()
        self.overshield_r:Hide()
    end

    self.value:SetText(cur)
end

--------------------------------------------------------------------------

local Aura = {}
Aura.__index = Aura

function Aura:New(parent, origin_x, origin_y)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.icon_id = nil
    new.is_helpful = nil
    new.stacks = nil
    new.time_str = nil
    new.expires = nil

    new.frame = CreateFrame("Frame", nil, parent)
    local f = new.frame
    f:Hide()
    f:SetWidth(24)
    f:SetHeight(40)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", origin_x, origin_y)

    new.icon = f:CreateTexture(nil, "ARTWORK")
    new.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
    new.icon:SetWidth(24)
    new.icon:SetHeight(24)

    new.border = f:CreateTexture(nil, "OVERLAY")
    new.border:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -3)
    new.border:SetWidth(22)
    new.border:SetHeight(26)
    new.border:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.border:SetTexCoord(99/256.0, 121/256.0, 14/256.0, 40/256.0)

    new.stack_label = f:CreateFontString(nil, "OVERLAY", "NumberFont_Shadow_Med")
    new.stack_label:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
    new.stack_label:SetTextScale(1)
    new.stack_label:SetText("")

    new.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    new.timer:SetPoint("BOTTOM", f, "BOTTOM", 0, 2)
    new.timer:SetTextScale(0.9)
    new.timer:SetText("")

    return new
end

function Aura:UpdateTimeLeft()
    local time_str
    local time_left
    if self.expires then
        time_left = self.expires - GetTime()
    else
        time_left = 0
    end
    local time_rounded = math.floor(time_left + 0.5)
    if time_left < 0.5 then
        time_str = nil
    elseif time_rounded < 60 then
        time_str = time_rounded
    elseif time_rounded < 3600 then
        time_str = math.floor(time_rounded/60) .. "m"
    else
        time_str = math.floor(time_rounded/3600) .. "h"
    end
    if time_str ~= self.time_str then
        self.timer:SetText(time_str)
        self.time_str = time_str
    end
end

-- Use icon_id = nil (or omitted) to hide the icon.
function Aura:Update(icon_id, is_helpful, stacks, expires)
    if not icon_id then
        if self.icon_id then
            self.frame:Hide()
            self.icon_id = nil
            self.is_helpful = nil
            self.stacks = nil
            self.stack_label:SetText("")
            self.time_left = nil
            self.timer:SetText("")
        end
        return
    end

    if icon_id ~= self.icon_id or is_helpful ~= self.is_helpful then
        if is_helpful then
            self.icon:SetMask("Interface\\Addons\\WowXIV\\textures\\buff-mask.png")
            self.border:SetTexCoord(99/256.0, 121/256.0, 14/256.0, 40/256.0)
        else
            self.icon:SetMask("Interface\\Addons\\WowXIV\\textures\\debuff-mask.png")
            self.border:SetTexCoord(99/256.0, 121/256.0, 40/256.0, 14/256.0)
        end
        self.icon:SetTexture(icon_id)  -- Must come _after_ SetMask()!
        if not self.icon_id then
            self.frame:Show()
        end
        self.icon_id = icon_id
        self.is_helpful = is_helpful
    end

    if stacks ~= self.stacks then
        if stacks > 0 then
            self.stack_label:SetText(stacks)
        else
            self.stack_label:SetText("")
        end
        self.stacks = stacks
    end

    if expires > 0 then
        self.expires = expires
    else
        self.expires = nil
    end
    self:UpdateTimeLeft()
end

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

    new.frame = CreateFrame("Frame", nil, parent)
    local f = new.frame
    f:SetWidth(256)
    f:SetHeight(40)

    if not new.npc_id then
        new.class_bg = f:CreateTexture(nil, "BORDER")
        new.class_bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
        new.class_bg:SetWidth(31)
        new.class_bg:SetHeight(31)
        new.class_bg:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
        new.class_icon = f:CreateTexture(nil, "ARTWORK")
        new.class_icon:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
        new.class_icon:SetWidth(22)
        new.class_icon:SetHeight(22)
    end

    new.name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    new.name:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -4)
    new.name:SetTextScale(1.1)

    new.hp = Gauge:New(f)
    new.hp.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 32, -12)

    new.mp = Gauge:New(f)
    new.mp.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 136, -12)

    new.auras = {}
    for i = 1, 9 do
        new.auras[i] = Aura:New(f, 240+(i-1)*24, 0)
    end

    f:SetScript("OnUpdate", function(self) new:OnUpdate() end)

    new:Refresh()
    new:Update()
    return new
end

function Member:OnUpdate()
    for _, aura in ipairs(self.auras) do
        if aura.time_str ~= "" then
            aura:UpdateTimeLeft()
        end
    end
end

function Member:SetYPosition(parent, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
end

function Member:SetMissing(missing)
    self.missing = missing
    if self.missing then
        self.frame:SetAlpha(0.5)
    else
        self.frame:SetAlpha(1.0)
    end
end

function Member:Refresh(new_unit)  -- optional new unit token
    if new_unit then
        self.unit = new_unit
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

    local aura_list = {}
    for i = 1, 9 do
        local data = C_UnitAuras.GetAuraDataByIndex(self.unit, i, "HARMFUL")
        if not data then break end
        table.insert(aura_list, data)
    end
    for i = 1, 9 do
        local data = C_UnitAuras.GetAuraDataByIndex(self.unit, i, "HELPFUL")
        if not data then break end
        table.insert(aura_list, data)
    end
    table.sort(aura_list, function(a,b)
        if a.isHelpful ~= b.isHelpful then
            return not a.isHelpful
        elseif (a.expirationTime ~= 0) ~= (b.expirationTime ~= 0) then
            return a.expirationTime ~= 0
        elseif a.expirationTime ~= 0 then
            return a.expirationTime < b.expirationTime
        else
            return a.spellId < b.spellId
        end
    end)
    for i = 1, 9 do
        if aura_list[i] then
            self.auras[i]:Update(aura_list[i].icon, aura_list[i].isHelpful, aura_list[i].applications, aura_list[i].expirationTime)
        else
            self.auras[i]:Update(nil)
        end
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
    new.frame = CreateFrame("Frame", "WoWXIV_PartyList", UIParent)
    local f = new.frame
    f.owner = new
    f:Hide()
    f:SetPoint("TOPLEFT", 30, -24)
    f:SetWidth(256)
    f:SetHeight(43)

    new.bg_t = f:CreateTexture(nil, "BACKGROUND")
    new.bg_t:SetPoint("TOP", f)
    new.bg_t:SetWidth(f:GetWidth())
    new.bg_t:SetHeight(4)
    new.bg_t:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.bg_t:SetTexCoord(0, 1, 0/256.0, 4/256.0)
    new.bg_b = f:CreateTexture(nil, "BACKGROUND")
    new.bg_b:SetPoint("BOTTOM", f)
    new.bg_b:SetWidth(f:GetWidth())
    new.bg_b:SetHeight(4)
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
