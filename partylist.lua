local _, WoWXIV = ...
WoWXIV.PartyList = {}

local class = WoWXIV.class
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

local GameTooltip = GameTooltip
local strfind = string.find
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub
local tinsert = tinsert

-- Role type constants returned from ClassIcon:Set() and Member:GetRole().
local ROLE_UNKNOWN = 0
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

-- Party list enable conditions.
-- These could technically be updated dynamically without a reload,
-- but we can't dynamically unhide the native party/raid frames, so
-- for consistency we make these set-on-load as well.
local enable_solo
local enable_party
local enable_raid

--------------------------------------------------------------------------

local ClassIcon = class(Frame)

function ClassIcon:__allocator(parent)
    return Frame.__allocator("Frame", nil, parent)
end

function ClassIcon:__constructor(parent)
    self.parent = parent
    self.tooltip_anchor = "BOTTOMRIGHT"

    self:SetSize(31, 31)
    self:HookScript("OnEnter", self.OnEnter)
    self:HookScript("OnLeave", self.OnLeave)

    self.ring = self:CreateTexture(nil, "OVERLAY")
    self.ring:SetPoint("TOPLEFT", -4, 4)
    self.ring:SetSize(40, 40)
    self.ring:SetTexture("Interface/MINIMAP/minimap-trackingborder")
    self.ring:SetTexCoord(0, 40/64.0, 0, 38/64.0)

    self.icon = self:CreateTexture(nil, "ARTWORK")
    self.icon:SetPoint("TOPLEFT", 1.5, -2)
    self.icon:SetSize(29, 29)
    -- The name makes it look like this is a temporary or placeholder file,
    -- but this is the actual mask texture used in the generic "ringed
    -- button" template (RingedFrameWithTooltipTemplate).
    self.icon:SetMask("Interface/CHARACTERFRAME/TempPortraitAlphaMask")
end

function ClassIcon:OnEnter()
    if GameTooltip:IsForbidden() then return end
    if not self:IsVisible() then return end
    GameTooltip:SetOwner(self, "ANCHOR_"..self.tooltip_anchor)
    self:UpdateTooltip()
end

function ClassIcon:OnLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

function ClassIcon:UpdateTooltip()
    if GameTooltip:IsForbidden() or GameTooltip:GetOwner() ~= self then
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
    self:SetPoint(anchor, self.parent, anchor, x, y)
    self.tooltip_anchor = tooltip_anchor
end

if select(4, GetBuildInfo()) >= 110200 then  -- FIXME: 11.2.0
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
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
            -- NOTE: GetSpecializationInfo() seems to not return any data
            -- immediately after login / UI reload, so we explicitly call
            -- the ...ForClassID() version.
            spec_id, spec_name, _, spec_icon, class_role =
                GetSpecializationInfoForClassID(class_id, spec_index)
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

-- Ideally this would be a subclass of UI.Gauge, but that may not be
-- available yet depending on load order.
local HateGauge = class()

local HATE_GAUGE_COLORS = {
    -- Red (current threat target)
    {{1, 0.604, 0.604}, {1, 0.753, 0.761}, {0.302, 0.094, 0.094}},
    -- Yellow (highest threat of non-targeted characters)
    {{0.88, 0.62, 0.17}, {1, 1, 0.94}, {0.118, 0.118, 0.11}},
    -- Blue (all others)
    {{0.416, 0.725, 0.890}, {1, 1, 1}, {0, 0, 0}},
}

function HateGauge:__constructor(parent, width)
    self.gauge = WoWXIV.UI.Gauge(parent, width)
    self.gauge:Hide()
    self.order_color = 0  -- 0 if not shown, else 1/2/3 indicating color
    local status_text =
        self.gauge.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.status_text = status_text
    status_text:SetPoint("BOTTOM", parent, "BOTTOMLEFT", 0, -6)
    status_text:SetTextColor(1, 1, 1)
end

function HateGauge:SetFrameLevel(level)
    self.gauge.frame:SetFrameLevel(level)
end

function HateGauge:SetSinglePoint(...)
    self.gauge:SetSinglePoint(...)
end

-- Parameters:
--     order: threat order (1 = highest threat)
--     is_target: true if unit is enemy's current threat target
--     value: normalized threat value (1.0 = max raw threat among all units)
-- Call with no or nil arguments to indicate "no threat".
function HateGauge:Update(order, is_target, value)
    if value then
        local gauge = self.gauge
        local status_text = self.status_text
        gauge:Update(1, value)
        status_text:SetText(is_target and "A" or order)
        if self.order_color == 0 then
            gauge:Show()
            status_text:Show()
        end
        local order_color = order>=3 and 3 or order
        if order_color ~= self.order_color then
            local colors = HATE_GAUGE_COLORS[order_color]
            gauge:SetBoxColor(unpack(colors[1]))
            gauge:SetBarColor(unpack(colors[2]))
            gauge:SetBarBackgroundColor(unpack(colors[3]))
            status_text:SetTextScale(order==1 and 1.3 or 1.2)
            self.order_color = order_color
        end
    else
        if self.order_color ~= 0 then
            self.status_text:Hide()
            self.gauge:Hide()
            self.order_color = 0
        end
    end
end

--------------------------------------------------------------------------

-- We can't make this derive from Button because the wrapped script used
-- by PartyCursor will refuse to access the frame.
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

local function UnitAlternatePowerType(unit)
    -- This is apparently the official way (see AlternatePowerBar.lua in
    -- the Blizzard_UnitFrame module) to get the additional power type for
    -- classes with two power types, e.g. Shadow Priest (insanity/mana).
    -- There's a UnitPowerType() API function which takes an optional
    -- second parameter "index", which one would think lets you enumerate
    -- all power types of a unit, but in fact it only ever returns data for
    -- index 0, and even Blizzard's own code never passes a second argument.
    local _, class = UnitClass(unit)
    local class_info = ALT_POWER_BAR_PAIR_DISPLAY_INFO[class]
    if class_info then
        local power_info = class_info[UnitPowerType(unit)]
        if power_info then
            return power_info.powerType, power_info.powerName
        end
    end
    return nil, nil
end

-- Height of a single party member entry.
Member.HEIGHT = 37

function Member:__constructor(parent, unit)
    self.unit = unit
    self.role = ROLE_UNKNOWN
    self.shown = false
    self.narrow = false
    self.missing = false
    self.fn_index = nil

    -- Cached ID of and data for current unit to avoid expensive refreshes.
    self.current_id = nil
    self.current_spec_role = nil
    self.alt_power_type = nil

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
    f:SetSize(240, self.HEIGHT)

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
        local class_icon = ClassIcon(f)
        self.class_icon = class_icon
        class_icon:SetAnchor("TOPLEFT", 0, -3, "BOTTOMRIGHT")
        local hate_gauge = HateGauge(class_icon, class_icon:GetWidth())
        self.hate_gauge = hate_gauge
        hate_gauge:SetFrameLevel(class_icon:GetFrameLevel() + 1)
        hate_gauge:SetSinglePoint("BOTTOMLEFT", -4, -20)
    end

    local name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.name = name
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -1)
    name:SetTextScale(1.1)
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")
    name:SetWidth(200)

    local hp = WoWXIV.UI.Gauge(f, 86)
    self.hp = hp
    hp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 32, -9)
    hp:SetBoxColor(0.416, 0.725, 0.890)
    hp:SetBarBackgroundColor(0.027, 0.161, 0.306)
    hp:SetBarColor(1, 1, 1)
    hp:SetShowOvershield(true)
    hp:SetShowValue(true)

    local power = WoWXIV.UI.Gauge(f, 86)
    self.power = power
    power:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 136, -9)
    power:SetBoxColor(0.416, 0.725, 0.890)
    power:SetBarBackgroundColor(0.027, 0.161, 0.306)
    power:SetBarColor(1, 1, 1)
    power:SetShowValue(true)

    local alt_power = WoWXIV.UI.Gauge(f, 86)
    self.alt_power = alt_power
    alt_power:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 136, -15)
    alt_power:SetBoxColor(0.416, 0.725, 0.890)
    alt_power:SetBarBackgroundColor(0.027, 0.161, 0.306)
    alt_power:SetBarColor(1, 1, 1)
    alt_power:SetShowValue(true)
    -- Raise power bar over alternate so borders display properly.
    power:SetFrameLevel(alt_power:GetFrameLevel() + 1)

    self.buffbar = WoWXIV.UI.AuraBar("ALL", "TOPLEFT", 9, 1, f, 240, 2)
    self.buffbar:SetUnit(unit)

    self:Refresh()
    self:Update()
end

function Member:GetUnit()
    return self.unit
end

function Member:GetFrame()
    return self.frame
end

function Member:Show()
    self.frame:Show()
    if not self.shown and self.fn_index then
        self:InternalBindKey(self.fn_index)
    end
    self.shown = true
end

function Member:Hide()
    self.frame:Hide()
    if self.shown and self.fn_index then
        self:InternalUnbindKey()
    end
    self.shown = false
end

function Member:IsShown()
    return self.shown
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
        self.power:Hide()
        self.alt_power:Hide()
        f:SetWidth(100)
        self.name:SetWidth(127)
        self.name:ClearAllPoints()
        self.name:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -1)
        self.hp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 5, -9)
        self.buffbar:SetSize(5, 1)
        self.buffbar:SetRelPosition(100, -1)
    else
        self.class_icon:Show()
        self.power:Show()
        self.alt_power:SetShown(self.alt_power_type ~= nil)
        f:SetWidth(240)
        self.name:SetWidth(200)
        self.name:ClearAllPoints()
        self.name:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -1)
        self.hp:SetSinglePoint("TOPLEFT", f, "TOPLEFT", 32, -9)
        self.power:SetShowValue(true, self.alt_power_type ~= nil)
        self.buffbar:SetSize(9, 1)
        self.buffbar:SetRelPosition(240, -1)
    end
    self.buffbar:Refresh()
    if UnitGUID(self.unit) then
        self:UpdateLabel()
    end
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

function Member:SetBinding(enable, index)
    self.fn_index = enable and index
    if self.shown then
        if enable then
            self:InternalBindKey(index)
        else
            self:InternalUnbindKey()
        end
    end
end

function Member:InternalBindKey(index)
    local key = "F" .. ((index-1) % 10 + 1)
    if index >= 31 then
        key = "CTRL-SHIFT-"..key
    elseif index >= 21 then
        key = "CTRL-"..key
    elseif index >= 11 then
        key = "SHIFT-"..key
    end
    SetOverrideBinding(self.frame, false, key,
                       "CLICK "..self.frame:GetName()..":LeftButton")
end

function Member:InternalUnbindKey(index)
    ClearOverrideBindings(self.frame)
end

function Member:Refresh()
    local unit = self.unit

    local id = UnitGUID(unit)
    if not id then return end
    local spec_role = (unit=="player" and GetSpecialization()
                                      or UnitGroupRolesAssigned(unit))
    local alt_power_type = UnitAlternatePowerType(unit)
    if (id == self.current_id
        and spec_role == self.current_spec_role 
        and alt_power_type == self.alt_power_type)
    then
        return
    end
    self.current_id = id
    self.current_spec_role = spec_role
    self.alt_power_type = alt_power_type

    local role_id, class
    if unit ~= "vehicle" then
        role_id, class = self.class_icon:Set(unit)
    end
    self.role = role_id or ROLE_UNKNOWN
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
    self.power:SetShowValue(true, self.alt_power_type ~= nil)
    if not self.narrow then
        self.alt_power:SetShown(self.alt_power_type ~= nil)
    end
    self:Update(true)
end

function Member:GetRole()
    return self.role
end

function Member:Update(updateLabel)
    local unit = self.unit
    local hpmax = UnitHealthMax(unit)
    local hpmax_mod = GetUnitMaxHealthModifier(unit)
    if not (hpmax_mod and hpmax_mod > 0) then hpmax_mod = 1 end
    local true_hpmax = hpmax / hpmax_mod
    self.hp:Update(hpmax, UnitHealth(unit), true_hpmax,
                   UnitGetTotalAbsorbs(unit),
                   UnitGetTotalHealAbsorbs(unit))
    self.power:Update(UnitPowerMax(unit), UnitPower(unit))
    if self.alt_power_type then
        self.alt_power:Update(UnitPowerMax(unit, self.alt_power_type),
                              UnitPower(unit, self.alt_power_type))
    end

    if updateLabel then
        self:UpdateLabel()
    end

    if UnitIsUnit("target", unit=="vehicle" and "player" or unit) then
        self.highlight:Show()
    else
        self.highlight:Hide()
    end
end

function Member:UpdateLabel()
    self.name:SetText(NameForUnit(self.unit, not self.narrow))
end

function Member:UpdateHate(order, is_target, value)
    self.hate_gauge:Update(order, is_target, value)
end

---------------------------------------------------------------------------

local PartyCursor = class()

function PartyCursor:__constructor(frame_level)
    local f = CreateFrame("Button", "WoWXIV_PartyCursor", UIParent,
                          "SecureUnitButtonTemplate, SecureHandlerBaseTemplate")
    self.frame = f
    f:SetFrameLevel(frame_level)
    f:Hide()

    local texture = f:CreateTexture(nil, "OVERLAY")
    self.texture = texture
    texture:SetAllPoints()
    WoWXIV.SetUITexture(texture, 160, 208, 15, 63)
    texture:SetTextureSliceMargins(12, 12, 12, 12)

    f:SetAttribute("type", "target")
    f:SetAttribute("unit", nil)
    f:SetAttribute("unitlist", "")
    f:SetAttribute("cur_unit", "")
    f:RegisterForClicks("LeftButtonDown")
    f:WrapScript(f, "OnClick", [[ -- (self, button, down)
        local cur_unit = self:GetAttribute("cur_unit")
        if button == "Confirm" then
            self:SetAttribute("unit", cur_unit)
            self:SetAttribute("cur_unit", "")
            self:Hide()
            -- Returning here continues with standard OnClick behavior,
            -- which ignores the button type except for modified attribute
            -- selection (which we don't use, so we don't need to
            -- explicitly return LeftButton).
            return
        end
        -- Suppress target setting in all other cases.
        self:SetAttribute("unit", nil)
        if button == "Cancel" then
            self:SetAttribute("cur_unit", "")
            self:Hide()
            return
        elseif button ~= "CycleForward" and button ~= "CycleBackward" then
            -- Should be impossible, but just in case.
            return
        end
        -- Note that we need our own copies of these str* locals because
        -- this snippet is run in the restricted environment.  Also note
        -- that the restricted environment disallows local func definitions
        -- (and in fact any use of that literal word, even in comments), so
        -- we have to remember to pass true to strfind() instead of using
        -- the strstr() wrapper.
        local strfind = string.find
        local strsub = string.sub
        local unitlist = self:GetAttribute("unitlist")
        local first, prev, new_unit
        local pos = 1
        while pos < #unitlist do
            local delim = strfind(unitlist, " ", pos, true)
            local unit = strsub(unitlist, pos, delim-1)
            pos = delim+1
            first = first or unit
            local is_current = (unit == cur_unit)
            if is_current then
                if button == "CycleBackward" then
                    if prev then
                        new_unit = prev
                    else
                        while delim < #unitlist do
                            pos = delim+1
                            delim = strfind(unitlist, " ", pos, true)
                        end
                        if delim > pos then
                            new_unit = strsub(unitlist, pos, delim-1)
                        else
                            new_unit = unit  -- Must be the only one.
                        end
                    end
                elseif pos < #unitlist then
                    delim = strfind(unitlist, " ", pos, true)
                    new_unit = strsub(unitlist, pos, delim-1)
                else
                    new_unit = first
                end
                break
            end
            prev = unit
        end
        if not new_unit then
            new_unit = "player"
        end
        self:SetAttribute("cur_unit", new_unit)
        self:ClearAllPoints()
        local unit_frame = self:GetFrameRef("frame_"..new_unit)
        self:SetPoint("TOPLEFT", unit_frame, "TOPLEFT", -6, 6)
        self:SetPoint("BOTTOMRIGHT", unit_frame, "BOTTOMRIGHT", 6, -6)
        self:Show()
    ]])

    SetOverrideBinding(f, false, "PADDDOWN",
                       "CLICK WoWXIV_PartyCursor:CycleForward")
    SetOverrideBinding(f, false, "PADDUP",
                       "CLICK WoWXIV_PartyCursor:CycleBackward")
    SetOverrideBinding(f, false, "ALT-"..WoWXIV.Config.GamePadConfirmButton(),
                       "CLICK WoWXIV_PartyCursor:Confirm")
    SetOverrideBinding(f, false, "ALT-"..WoWXIV.Config.GamePadCancelButton(),
                       "CLICK WoWXIV_PartyCursor:Cancel")
end

function PartyCursor:OnShow()
    local f = self.frame
    ClearOverrideBindings(f)
end

function PartyCursor:OnHide()
    local f = self.frame
    ClearOverrideBindings(f)
    SetOverrideBinding(f, false, "PADDDOWN",
                       "CLICK WoWXIV_PartyCursor:CycleForward")
    SetOverrideBinding(f, false, "PADDUP",
                       "CLICK WoWXIV_PartyCursor:CycleBackward")
end

-- Pass list of Member instances.
function PartyCursor:SetPartyList(party_list)
    local f = self.frame
    local cur_unit = f:GetAttribute("cur_unit")
    local have_cur_unit = false
    local unitlist = ""
    for _, member in ipairs(party_list) do
        local unit = member:GetUnit()
        unitlist = unitlist .. unit .. " "
        f:SetFrameRef("frame_"..unit, member:GetFrame())
        have_cur_unit = have_cur_unit or unit == cur_unit
    end
    -- Note that unitlist ends with a trailing space; this is what we want,
    -- as it provides a convenient delimiter for strstr() rather than
    -- having to special-case the last entry in the list.
    f:SetAttribute("unitlist", unitlist)
    -- Clear the cursor if the unit it was on disappeared.
    if not have_cur_unit then
        f:SetAttribute("cur_unit", "")
        f:Hide()
    end
end

---------------------------------------------------------------------------

local PartyList = class(Frame)

local PARTY_UNIT_TOKENS = {"player", "vehicle"}
for i = 1, 4 do tinsert(PARTY_UNIT_TOKENS, "party"..i) end
for i = 1, 40 do tinsert(PARTY_UNIT_TOKENS, "raid"..i) end
local PARTY_UNIT_ORDER = {}
for i, token in ipairs(PARTY_UNIT_TOKENS) do
    PARTY_UNIT_ORDER[token] = i
end

function PartyList:__allocator()
    return Frame.__allocator("Frame", "WoWXIV_PartyList", UIParent)
end

function PartyList:__constructor()
    self.enabled = false  -- currently enabled?
    self.party = {}  -- mapping from unit token to Member instance
    self.pending_SetParty = false  -- see SetParty()

    self:Hide()
    self:SetPoint("TOPLEFT", 30, -24)
    self:SetSize(256, 44)

    local bg_t = self:CreateTexture(nil, "BACKGROUND")
    self.bg_t = bg_t
    bg_t:SetPoint("TOPLEFT")
    bg_t:SetSize(256, 4)
    WoWXIV.SetUITexture(bg_t, 0, 256, 0, 4)
    bg_t:SetVertexColor(0, 0, 0, 1)
    local bg_b = self:CreateTexture(nil, "BACKGROUND")
    self.bg_b = bg_b
    bg_b:SetPoint("BOTTOMLEFT")
    bg_b:SetSize(256, 4)
    WoWXIV.SetUITexture(bg_b, 0, 256, 7, 11)
    bg_b:SetVertexColor(0, 0, 0, 1)

    local bg2_t = self:CreateTexture(nil, "BACKGROUND")
    self.bg2_t = bg2_t
    bg2_t:SetPoint("TOPRIGHT")
    bg2_t:SetSize(256, 4)
    WoWXIV.SetUITexture(bg2_t, 0, 256, 0, 4)
    bg2_t:SetVertexColor(0, 0, 0, 1)
    bg2_t:Hide()
    local bg2_b = self:CreateTexture(nil, "BACKGROUND")
    self.bg2_b = bg2_b
    bg2_b:SetPoint("BOTTOMRIGHT")
    bg2_b:SetSize(256, 4)
    WoWXIV.SetUITexture(bg2_b, 0, 256, 7, 11)
    bg2_b:SetVertexColor(0, 0, 0, 1)
    bg2_b:Hide()

    for _, unit in ipairs(PARTY_UNIT_TOKENS) do
        self.party[unit] = Member(self, unit)
    end

    self.events = {}
    self.events["ACTIVE_PLAYER_SPECIALIZATION_CHANGED"] = self.OnPartyChange
    self.events["GROUP_ROSTER_UPDATE"] = self.OnPartyChange
    self.events["PARTY_LEADER_CHANGED"] = self.OnPartyChange
    self.events["PLAYER_ENTERING_WORLD"] = self.OnPartyChange
    self.events["PLAYER_ROLES_ASSIGNED"] = self.OnPartyChange
    self.events["PLAYER_TARGET_CHANGED"] = self.OnTargetChange
    self.events["UNIT_ABSORB_AMOUNT_CHANGED"] = self.OnMemberUpdate
    self.events["UNIT_AURA"] = self.OnMemberUpdate
    self.events["UNIT_ENTERED_VEHICLE"] = self.OnPartyChange
    self.events["UNIT_EXITED_VEHICLE"] = self.OnPartyChange
    self.events["UNIT_HEALTH"] = self.OnMemberUpdate
    self.events["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"] = self.OnMemberUpdate
    self.events["UNIT_LEVEL"] = self.OnMemberUpdateName
    self.events["UNIT_MAXHEALTH"] = self.OnMemberUpdate
    self.events["UNIT_MAXPOWER"] = self.OnMemberUpdate
    self.events["UNIT_MAX_HEALTH_MODIFIERS_CHANGED"] = self.OnMemberUpdate
    self.events["UNIT_NAME_UPDATE"] = self.OnMemberUpdateName
    self.events["UNIT_POWER_FREQUENT"] = self.OnMemberUpdate
    self.events["UNIT_POWER_UPDATE"] = self.OnMemberUpdate

    -- We could theoretically register the unit-specific events for just
    -- the units we're interested in, but that would require refreshing the
    -- registration on every party/ally change, and we'll generally be
    -- interested in most events anyway so it's probably not worth the effort.
    for event, _ in pairs(self.events) do
        self:RegisterEvent(event)
    end

    -- However, we only ever want to see threat updates for the current
    -- target, and if there are a lot of enemies around, a blanket Register
    -- will result in a lot of spam.
    self.events["UNIT_THREAT_LIST_UPDATE"] = self.OnTargetHateUpdate
    self:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", "target")

    self:SetScript("OnEvent", function(self, event, ...)
        if self.events[event] then
            self.events[event](self, ...)
        end
    end)

    -- Ensure cursor is over everything (Member instance, class icon, auras)
    self.cursor = PartyCursor(self:GetFrameLevel() + 4)

    self:SetParty()
    self:Show()
end

function PartyList:OnPartyChange()
    self:SetParty()
end

function PartyList:OnTargetChange()
    for _, member in pairs(self.party) do
        member:Update(false)
    end
    self:UpdateHate()
end

function PartyList:OnTargetHateUpdate()
    self:UpdateHate()
end

function PartyList:OnMemberUpdate(unit)
    self:UpdateParty(unit, false)
end

function PartyList:OnMemberUpdateName(unit)
    self:UpdateParty(unit, true)
end

function PartyList:SetParty(is_retry)
    -- Normally party change events can never occur during combat, but
    -- some quests will put the player into or out of a vehicle while
    -- in combat, so we check here to be safe.
    if not is_retry and self.pending_SetParty then return end
    if InCombatLockdown() then
        self.pending_SetParty = true
        RunNextFrame(function() self:SetParty(true) end)
        return
    end
    self.pending_SetParty = false

    local player_id = UnitGUID("player")
    local is_party = UnitInParty("player")
    local is_raid = UnitInRaid("player")

    local enable
    if is_raid then
        enable = enable_raid
    elseif is_party then
        enable = enable_party
    else
        enable = enable_solo
    end
    self.enabled = enable
    if enable then
        self:Show()
    else
        self:Hide()
        return
    end

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

    local party_order = {}
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
                if name and strstr(name, "[DNT]") then id = nil end
            end
        end
        if id then
            tinsert(party_order,
                    {member, unit=="player" and -2 or
                             unit=="vehicle" and -1 or member:GetRole()})
        else
            member:Hide()
        end
    end

    local do_sort = WoWXIV_config["partylist_sort"]
    local do_bindkeys = do_sort and WoWXIV_config["partylist_fn_override"]
    if do_sort then
        table.sort(party_order, function(a,b) return a[2] < b[2] end)
    end

    local cursor_list = {}
    local col_width = narrow and 228 or 256
    local row_height = Member.HEIGHT
    local col_spacing = col_width + (narrow and 0 or 8)
    local width, height = 0, 0
    local x0, y0 = 0, -4
    local row, col, ncols = 0, 0, 0
    local index = 1
    for _, v in ipairs(party_order) do
        local member = v[1]
        member:SetBinding(do_bindkeys, index)
        local x = x0 + col*(col_spacing)
        local y = y0 + row*(-row_height)
        member:SetRelPosition(self, x, y)
        member:SetNarrow(narrow)
        member:Refresh()
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
            tinsert(cursor_list, member)
            index = index + 1
        end
    end

    self.cursor:SetPartyList(cursor_list)

    self:SetSize(width, height+4)
    self.bg_t:SetWidth(col_width)
    self.bg_b:SetWidth(col_width)
    if ncols > 1 then  -- assumed to be 2
        self.bg2_t:SetWidth(col_width)
        self.bg2_b:SetWidth(col_width)
        self.bg2_b:ClearAllPoints()
        local col2_y = y0 + row*(-row_height)
        self.bg2_b:SetPoint("BOTTOMRIGHT", 0, height - (-col2_y))
        self.bg2_t:Show()
        self.bg2_b:Show()
    else
        self.bg2_t:Hide()
        self.bg2_b:Hide()
    end
    local abs_y = select(5, self:GetPoint(1))
    WoWXIV.HateList.NotifyPartyListBottom(abs_y - self:GetHeight())
end

function PartyList:UpdateParty(unit, updateLabel)
    if not self.enabled then return end
    local member = self.party[unit]
    if not member then return end
    member:Update(updateLabel)

end

local function HateSort(a, b)  -- Helper for UpdateHate().
    if a[3] > b[3] then
        return true
    elseif a[3] == b[3] then
        return PARTY_UNIT_ORDER[a[1]] < PARTY_UNIT_ORDER[b[1]]
    else
        return false
    end
end

function PartyList:UpdateHate(unit)
    local hate = {}
    for token, member in pairs(self.party) do
        if token ~= "vehicle" and member:IsShown() then
            local is_target, _, _, _, threat =
                UnitDetailedThreatSituation(token, "target")
            tinsert(hate, {token, is_target, threat or -1})
        end
    end
    table.sort(hate, HateSort)
    local max_threat = hate[1][3]
    if max_threat < 1 then max_threat = 1 end
    for index, data in ipairs(hate) do
        local token, is_target, threat = unpack(data)
        local member = self.party[token]
        if threat < 0 then
            threat = nil
        else
            threat = threat / max_threat
        end
        self.party[token]:UpdateHate(index, is_target, threat)
    end
end

---------------------------------------------------------------------------

-- Create the global party list instance.
function WoWXIV.PartyList.Create()
    local enable = "," .. WoWXIV_config["partylist_enable"] .. ","
    enable_solo  = (strstr(enable, ",solo,") ~= nil)
    enable_party = (strstr(enable, ",party,") ~= nil)
    enable_raid  = (strstr(enable, ",raid,") ~= nil)
    if not (enable_solo or enable_party or enable_raid) then
        return
    end

    WoWXIV.PartyList.list = PartyList()
    
    if enable_party then
        WoWXIV.HideBlizzardFrame(PartyFrame)
        -- Technically not needed, but avoids tons and tons of taint errors:
        WoWXIV.HideBlizzardFrame(CompactPartyFrame)
        function CompactPartyFrame:RefreshMembers() end
        -- We don't really want to touch arena frames, but they proc taint
        -- on vehicle transitions via CompactUnitFrame_OnEvent().  We could
        -- probably expand the party list to handle arena parties (if
        -- there's in fact any difference), but that would require me to
        -- care at all about PvP...
        WoWXIV.HideBlizzardFrame(CompactArenaFrame)
        function CompactArenaFrame:RefreshMembers() end
        for i = 1, 5 do
            WoWXIV.HideBlizzardFrame(_G["CompactPartyFrameMember"..i])
            WoWXIV.HideBlizzardFrame(_G["CompactPartyFramePet"..i])
            WoWXIV.HideBlizzardFrame(_G["CompactArenaFrameMember"..i])
        end
    end
    if enable_raid then
        WoWXIV.HideBlizzardFrame(CompactRaidFrameContainer)
    end
end

-- Refresh the party list.  Must be called to pick up config changes.
function WoWXIV.PartyList.Refresh()
    WoWXIV.PartyList.list:SetParty()
end
