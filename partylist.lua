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
    [ROLE_TANK]   = CreateColor(0.145, 0.212, 0.427),
    [ROLE_HEALER] = CreateColor(0.184, 0.298, 0.141),
    [ROLE_DPS]    = CreateColor(0.314, 0.180, 0.180),
}

-- Background and text colors for each class.  We adjust these a bit
-- from the defaults for visibility's sake.
local CLASS_TEXT_COLORS, CLASS_BG_COLORS = {}, {}
for class, color in pairs(RAID_CLASS_COLORS) do
    -- The Shaman color is a bit dark on a red (DPS) background, so
    -- brighten it a bit.
    if class == "SHAMAN" then
        CLASS_TEXT_COLORS[class] = CreateColor(0.2, 0.552, 0.896)
    else
        CLASS_TEXT_COLORS[class] = color
    end
    -- Dim the class color for background use so we can more easily read
    -- text on top.
    CLASS_BG_COLORS[class] = CreateColor(color.r/2, color.g/2, color.b/2)
end

-- Default party member background color (black).
local DEFAULT_BG_COLOR = CreateColor(0, 0, 0)

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

-- Returns detected role (ROLE_* constant) and class ("PRIEST" etc) or nil.
function ClassIcon:Set(unit)
    local role_name, role_id, class_name, class, spec_name
    if unit then
        local role = UnitGroupRolesAssigned(unit)
        local class_id
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

    return role_id, class
end

--------------------------------------------------------------------------

local Member = class()

local function NameForUnit(unit, with_level)
    local name = UnitName(unit)
    if with_level then
        local level = UnitLevel(unit)
        if level > 0 then
            name = "Lv" .. level .. " " .. name
        end
    end
    return name
end

function Member:__constructor(parent, unit)
    self.unit = unit
    self.shown = false
    self.narrow = false
    self.missing = false

    -- Use SecureUnitButtonTemplate to allow targeting the member on click.
    -- Note that SecureActionButtonTemplate doesn't work here for some reason;
    -- the button still responds to clicks (as can be verified by hooking the
    -- OnClick event) and still highlights the associated unit on mouseover,
    -- but the "target" action doesn't fire.
    local f = CreateFrame("Button", "WoWXIV_PartyListMember_"..unit, parent,
                          "SecureUnitButtonTemplate")
    self.frame = f
    f:SetAttribute("type1", "target")
    f:SetAttribute("unit", unit=="vehicle" and "player" or unit)
    f:RegisterForClicks("LeftButtonDown")
    f:Hide()
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

    if self.unit ~= "vehicle" then
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

function Member:Show()
    self.frame:Show()
    self.shown = true
end

function Member:Hide()
    self.frame:Hide()
    self.shown = false
end

function Member:SetRelPosition(parent, x, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

function Member:SetNarrow(narrow)
    if narrow == self.narrow then return end
    self.narrow = narrow
    if narrow then
        self.mp:Hide()
        self.buffbar:SetSize(5, 1)
        self.buffbar:SetRelPosition(136, -1)
    else
        self.mp:Show()
        self.buffbar:SetSize(9, 1)
        self.buffbar:SetRelPosition(240, -1)
    end
    self.buffbar:Refresh()
    self:Refresh()
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

function Member:Refresh()
    self.name:SetText(NameForUnit(self.unit, not self.narrow))

    local role_id, class
    if self.unit ~= "vehicle" then
        role_id, class = self.class_icon:Set(self.unit)
    end
    local role_color = role_id and ROLE_COLORS[role_id]
    local class_bg_color = class and CLASS_BG_COLORS[class]
    local class_text_color = class and CLASS_TEXT_COLORS[class]
    local colors = WoWXIV_config["partylist_colors"]
    local bg_color, name_color
    if colors == "role" then
        bg_color = role_color
    elseif colors == "role+class" then
        bg_color = role_color
        name_color = class_text_color
    elseif colors == "class" then
        bg_color = class_bg_color
    end
    self.bg:SetVertexColor((bg_color or DEFAULT_BG_COLOR):GetRGBA())
    self.name:SetTextColor((name_color or NORMAL_FONT_COLOR):GetRGB())
end

function Member:Update(updateLabel)
    self.hp:Update(UnitHealthMax(self.unit), UnitHealth(self.unit),
                   UnitGetTotalAbsorbs(self.unit),
                   UnitGetTotalHealAbsorbs(self.unit))
    self.mp:Update(UnitPowerMax(self.unit), UnitPower(self.unit))

    if updateLabel then
        self.name:SetText(NameForUnit(self.unit, not self.narrow))
    end

    if UnitIsUnit("target", self.unit=="vehicle" and "player" or self.unit) then
        self.highlight:Show()
    else
        self.highlight:Hide()
    end
end

---------------------------------------------------------------------------

local PartyList = class()

local PARTY_UNIT_TOKENS = {"player", "vehicle"}
for i = 1, 4 do tinsert(PARTY_UNIT_TOKENS, "party"..i) end
for i = 1, 40 do tinsert(PARTY_UNIT_TOKENS, "raid"..i) end

function PartyList:__constructor()
    self.party = {}  -- mapping from unit token to Member instance
    self.pending_SetParty = false  -- see SetParty()

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
    self.bg_t:SetPoint("TOP")
    self.bg_t:SetSize(f:GetWidth(), 4)
    self.bg_t:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    self.bg_t:SetTexCoord(0, 1, 0/256.0, 4/256.0)
    self.bg_t:SetVertexColor(0, 0, 0, 1)
    self.bg_b = f:CreateTexture(nil, "BACKGROUND")
    self.bg_b:SetPoint("BOTTOM")
    self.bg_b:SetSize(f:GetWidth(), 4)
    self.bg_b:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    self.bg_b:SetTexCoord(0, 1, 7/256.0, 11/256.0)
    self.bg_b:SetVertexColor(0, 0, 0, 1)

    for _, unit in ipairs(PARTY_UNIT_TOKENS) do
        self.party[unit] = Member(f, unit)
    end

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

    self:SetParty()
    f:Show()
end

function PartyList:SetParty(is_retry)
    -- Normally party change events can never occur during combat, but
    -- some quests will put the player into or out of a vehicle while
    -- in combat, so we check here to be safe.
    if not is_retry and self.pending_SetParty then return end
    if InCombatLockdown() then
        self.pending_SetParty = true
        C_Timer.After(1, function() self:SetParty(true) end)
        return
    end
    self.pending_SetParty = false

    local narrow_condition = WoWXIV_config["partylist_narrow_condition"]
    local narrow
    if narrow_condition == "always" then
        narrow = true
    elseif narrow_condition == "raid" and UnitInRaid("player") then
        narrow = true
    elseif narrow_condition == "raidlarge" and UnitInRaid("player") then
        local raid_size = 1
        for i = 1, 40 do
            if UnitGUID("raid"..i) then raid_size = raid_size+1 end
        end
        narrow = (raid_size > 20)
    else
        narrow = false
    end

    local f = self.frame
    local width, height = 0, 0
    local x0, y0 = 0, -4
    local row, col = 0, 0
    for _, unit in ipairs(PARTY_UNIT_TOKENS) do
        local member = self.party[unit]
        assert(member)
        local id = UnitGUID(unit)
        if unit == "vehicle" then
            -- Vehicles with "[DNT]" in the name are used when player
            -- movement is locked in certain events, such as the Ruby
            -- Lifeshrine sidequest "Stay a While".
            local name = UnitName(unit)
            if name and strfind(name, "%[DNT]") then id = nil end
        end
        if id then
            local x = x0 + col*264
            local y = y0 + row*(-40)
            member:SetRelPosition(f, x, y)
            member:SetNarrow(narrow)
            member:Refresh()
            member:Show()
            local bottom = -y+40
            if bottom > height then height = bottom end
            row = row+1
            if narrow and row >= 20 then
                col = col+1
                row = 0
            end
        else
            member:Hide()
        end
    end
    f:SetHeight(height+4)
end

function PartyList:UpdateParty(unit, updateLabel)
    local member = self.party[unit]
    if not member then return end
    member:Update(updateLabel)
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
