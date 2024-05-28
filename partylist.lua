local _, WoWXIV = ...
WoWXIV.PartyList = {}

local class = WoWXIV.class

local GameTooltip = GameTooltip
local strfind = string.find
local strsub = string.sub

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

    self.ring = f:CreateTexture(nil, "OVERLAY")
    self.ring:SetPoint("TOPLEFT", -4, 4)
    self.ring:SetSize(40, 40)
    self.ring:SetTexture("Interface/MINIMAP/minimap-trackingborder")
    self.ring:SetTexCoord(0, 40/64.0, 0, 38/64.0)

    self.icon = f:CreateTexture(nil, "ARTWORK")
    self.icon:SetPoint("TOPLEFT", 1.5, -2)
    self.icon:SetSize(29, 29)
    -- The name makes it look like this is a temporary or placeholder file,
    -- but this is the actual mask texture used in the generic "ringed
    -- button" template (RingedFrameWithTooltipTemplate).
    self.icon:SetMask("Interface/CHARACTERFRAME/TempPortraitAlphaMask")
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

function ClassIcon:Show()
    self.frame:Show()
end

function ClassIcon:Hide()
    self.frame:Hide()
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
            -- FIXME: is there no way to get other players' specs?
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
        elseif role == "HEALER" then
            role_id = ROLE_HEALER
            role_name = " (Healer)"
        elseif role == "DAMAGER" then
            role_id = ROLE_DPS
            role_name = " (DPS)"
        else
            role_id = nil
            role_name = ""
        end
        if spec_id then
            self.icon:SetTexture(spec_icon)
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
    f:SetSize(256, 37)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    self.bg = bg
    bg:SetAllPoints(f)
    WoWXIV.SetUITexture(bg, 0, 256, 4, 7)
    bg:SetVertexColor(0, 0, 0, 1)

    local highlight = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.highlight = highlight
    highlight:SetAllPoints(f)
    WoWXIV.SetUITexture(highlight, 0, 256, 4, 7)
    highlight:SetVertexColor(1, 1, 1, 0.5)
    highlight:Hide()

    if self.unit ~= "vehicle" then
        self.class_icon = ClassIcon(f)
        self.class_icon:SetAnchor("TOPLEFT", 0, -3, "BOTTOMRIGHT")
    end

    local name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.name = name
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -2)
    name:SetTextScale(1.1)
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")
    name:SetWidth(200)

    local hp = WoWXIV.UI.Gauge(f, 86)
    self.hp = hp
    hp:SetBoxColor(0.416, 0.725, 0.890)
    hp:SetBarBackgroundColor(0.027, 0.161, 0.306)
    hp:SetBarColor(1, 1, 1)
    hp:SetShowOvershield(true)
    hp:SetShowValue(true)
    hp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 32, -9)

    local mp = WoWXIV.UI.Gauge(f, 86)
    self.mp = mp
    mp:SetBoxColor(0.416, 0.725, 0.890)
    mp:SetBarBackgroundColor(0.027, 0.161, 0.306)
    mp:SetBarColor(1, 1, 1)
    mp:SetShowValue(true)
    mp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 136, -9)

    self.buffbar = WoWXIV.UI.AuraBar("ALL", "TOPLEFT", 9, 1, f, 240, 2)
    self.buffbar:SetUnit(unit)

    -- Hack to expose targeted state to secure code
    self.selected_frame = CreateFrame("Frame")
    self.selected_frame:Hide()

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
    local f = self.frame
    if narrow then
        self.class_icon:Hide()
        self.mp:Hide()
        f:SetWidth(228)
        self.name:SetWidth(127)
        self.name:ClearAllPoints()
        self.name:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -3)
        self.hp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 5, -11)
        self.buffbar:SetSize(5, 1)
        self.buffbar:SetRelPosition(100, -1)
    else
        self.class_icon:Show()
        self.mp:Show()
        f:SetWidth(256)
        self.name:SetWidth(200)
        self.name:ClearAllPoints()
        self.name:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -3)
        self.hp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 32, -11)
        self.mp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 136, -11)
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
        self.selected_frame:Show()
    else
        self.highlight:Hide()
        self.selected_frame:Hide()
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

    local f = CreateFrame("Button", "WoWXIV_PartyList", UIParent,
                          --"SecureHandlerClickTemplate")
                          --"SecureActionButtonTemplate")
                          "SecureUnitButtonTemplate, SecureHandlerBaseTemplate")
    self.frame = f
    f.owner = self
    f:Hide()
    f:SetPoint("TOPLEFT", 30, -24)
    f:SetSize(256, 44)
    f:SetAttribute("type", "target")
    f:SetAttribute("unit", nil)
    f:SetAttribute("unitlist", "")
    f:RegisterForClicks("LeftButtonDown")
    f:WrapScript(f, "OnClick", [[ -- (self, button, down)
        if PlayerInCombat() then return false end  -- FIXME: can't call IsShown() in combat
        local unitlist = self:GetAttribute("unitlist")
        local first, prev, target
        local pos = 1
        while pos < #unitlist do
            local delim = strfind(unitlist, " ", pos, true)
            local unit = strsub(unitlist, pos, delim-1)
            pos = delim+1
            first = first or unit
            local is_target = self:GetFrameRef("sel_"..unit):IsShown()
            if is_target then
                if button == "CycleBackward" then
                    if prev then
                        target = prev
                    else
                        while delim < #unitlist do
                            pos = delim+1
                            delim = strfind(unitlist, " ", pos, true)
                        end
                        target = strsub(unitlist, pos, delim-1)
                    end
                elseif pos < #unitlist then
                    delim = strfind(unitlist, " ", pos, true)
                    target = strsub(unitlist, pos, delim-1)
                else
                    target = first
                end
                break
            end
            prev = unit
        end
        if not target then
            target = "player"
        end
        self:SetAttribute("unit", target)
    ]])
    SetOverrideBinding(f, false, "PADDDOWN",
                       "CLICK WoWXIV_PartyList:CycleForward")
    SetOverrideBinding(f, false, "PADDUP",
                       "CLICK WoWXIV_PartyList:CycleBackward")

    local bg_t = f:CreateTexture(nil, "BACKGROUND")
    self.bg_t = bg_t
    bg_t:SetPoint("TOPLEFT")
    bg_t:SetSize(256, 4)
    WoWXIV.SetUITexture(bg_t, 0, 256, 0, 4)
    bg_t:SetVertexColor(0, 0, 0, 1)
    local bg_b = f:CreateTexture(nil, "BACKGROUND")
    self.bg_b = bg_b
    bg_b:SetPoint("BOTTOMLEFT")
    bg_b:SetSize(256, 4)
    WoWXIV.SetUITexture(bg_b, 0, 256, 7, 11)
    bg_b:SetVertexColor(0, 0, 0, 1)

    local bg2_t = f:CreateTexture(nil, "BACKGROUND")
    self.bg2_t = bg2_t
    bg2_t:SetPoint("TOPRIGHT")
    bg2_t:SetSize(256, 4)
    WoWXIV.SetUITexture(bg2_t, 0, 256, 0, 4)
    bg2_t:SetVertexColor(0, 0, 0, 1)
    bg2_t:Hide()
    local bg2_b = f:CreateTexture(nil, "BACKGROUND")
    self.bg2_b = bg2_b
    bg2_b:SetPoint("BOTTOMRIGHT")
    bg2_b:SetSize(256, 4)
    WoWXIV.SetUITexture(bg2_b, 0, 256, 7, 11)
    bg2_b:SetVertexColor(0, 0, 0, 1)
    bg2_b:Hide()

    for _, unit in ipairs(PARTY_UNIT_TOKENS) do
        self.party[unit] = Member(f, unit)
        f:SetFrameRef("sel_"..unit, self.party[unit].selected_frame)
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

    local player_id = UnitGUID("player")
    local is_raid = UnitInRaid("player")

    local narrow_condition = WoWXIV_config["partylist_narrow_condition"]
    local narrow
    if narrow_condition == "always" then
        narrow = true
    elseif narrow_condition == "raid" and is_raid then
        narrow = true
    elseif narrow_condition == "raidlarge" and is_raid then
        local raid_size = 1
        for i = 1, 40 do
            if UnitGUID("raid"..i) then raid_size = raid_size+1 end
        end
        narrow = (raid_size > 20)
    else
        narrow = false
    end

    local f = self.frame
    local unitlist = ""
    local col_width = narrow and 228 or 256
    local row_height = 37
    local col_spacing = col_width + (narrow and 0 or 8)
    local width, height = 0, 0
    local x0, y0 = 0, -4
    local row, col, ncols = 0, 0, 0
    for _, unit in ipairs(PARTY_UNIT_TOKENS) do
        local member = self.party[unit]
        assert(member)
        local id = UnitGUID(unit)
        if is_raid then
            -- raidN tokens cover _all_ raid members, including the player
            -- and the player's raid group (party1-4), so avoid duplicates.
            if strsub(unit, 1, 4) == "raid" then
                if id == player_id then id = nil end
            else
                if unit ~= "player" then id = nil end
            end
        else  -- not in a raid
            if unit == "vehicle" then
                -- Vehicles with "[DNT]" in the name are used when player
                -- movement is locked in certain events, such as the Ruby
                -- Lifeshrine sidequest "Stay a While".  These are
                -- presumably internal objects not intended to be shown
                -- to the player, so hide them from the list.
                local name = UnitName(unit)
                if name and strfind(name, "%[DNT]") then id = nil end
            end
        end
        if id then
            local x = x0 + col*(col_spacing)
            local y = y0 + row*(-row_height)
            member:SetRelPosition(f, x, y)
            member:SetNarrow(narrow)
            member:Refresh()
            member:Update()
            member:Show()
            local right = x + col_width
            local bottom = -y + row_height
            if right > width then width = right end
            if bottom > height then height = bottom end
            if col+1 > ncols then ncols = col+1 end
            row = row+1
            if row >= 20 then
                col = col+1
                row = 0
            end
            if unit ~= "vehicle" then
                unitlist = unitlist .. unit .. " "
            end
        else
            member:Hide()
        end
    end
    -- Note that unitlist ends with a trailing space; this is what we want,
    -- as it provides a convenient delimiter for strfind() rather than
    -- having to special-case the last entry in the list.
    f:SetAttribute("unitlist", unitlist)

    f:SetSize(width, height+4)
    self.bg_t:SetWidth(col_width)
    self.bg_b:SetWidth(col_width)
    if ncols > 1 then  -- assumed to be 2
        self.bg2_t:SetWidth(col_width)
        self.bg2_b:SetWidth(col_width)
        self.bg2_b:ClearAllPoints()
        local col2_y = y0 + row*(-40)
        self.bg2_b:SetPoint("BOTTOMRIGHT", 0, height - (-col2_y))
        self.bg2_t:Show()
        self.bg2_b:Show()
    else
        self.bg2_t:Hide()
        self.bg2_b:Hide()
    end
    local abs_y = select(5, f:GetPoint(1))
    WoWXIV.HateList.NotifyPartyListBottom(abs_y - f:GetHeight())
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
    WoWXIV.HideBlizzardFrame(RaidFrame)
end

-- Refresh the party list.  Must be called to pick up config changes.
function WoWXIV.PartyList.Refresh()
    WoWXIV.PartyList.list:SetParty()
end
