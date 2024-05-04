local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
UI.CastBar = class()

local strsub = string.sub

------------------------------------------------------------------------

local CastBar = UI.CastBar

function CastBar:__constructor(parent, width)
    self.width = width
    self.unit = nil    -- Unit token of unit being monitored, or nil if none
    self.cast = nil    -- Current cast GUID, or nil if none
    self.is_channel = false -- Is this a normal cast (false) or channel (true)?
    self.start = 0     -- Start timestamp of current cast
    self.duration = 0  -- Expected duration of current cast

    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    f:SetSize(width+8, 15)
    f:SetScript("OnEvent", function(frame,...) self:OnEvent(...) end)

    local bar = UI.Gauge(f, width)
    self.bar = bar
    bar:SetBoxColor(0.533, 0.533, 0.533)
    bar:SetBarBackgroundColor(0.118, 0.118, 0.118)
    bar:SetBarColor(0.8, 0.8, 0.8)
    bar:SetSinglePoint("TOPLEFT", 0, -6)
    bar:Hide()

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label = label
    label:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -4, -12)
    label:SetTextScale(1)
    label:SetTextColor(1, 1, 1)
    label:SetWordWrap(false)
    label:SetJustifyH("RIGHT")
    label:SetWidth(width)
    label:Hide()

    local label_bg = f:CreateTexture(nil, "BACKGROUND")
    self.label_bg = label_bg
    WoWXIV.SetUITexture(label_bg, 0, 256, 0, 11)
    label_bg:SetVertexColor(0, 0, 0, 1)
    label_bg:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 1, -14)
    label_bg:SetHeight(16)
    label_bg:Hide()
end

function CastBar:Show()
    self.frame:Show()
end

function CastBar:Hide()
    self.frame:Hide()
end

function CastBar:SetAlpha(alpha)
    self.frame:SetAlpha(alpha)
end

function CastBar:SetSinglePoint(...)
    self.frame:ClearAllPoints()
    self.frame:SetPoint(...)
end

function CastBar:SetBoxColor(...)
    self.bar:SetBoxColor(...)
end

function CastBar:SetBarBackgroundColor(...)
    self.bar:SetBarBackgroundColor(...)
end

function CastBar:SetBarColor(r, g, b)
    self.bar:SetBarColor(r, g, b)
    self.label:SetTextColor(r, g, b)
end

function CastBar:SetTextScale(scale)
    self.label:SetTextScale(scale)
    self.label_bg:SetHeight(16*scale)
end

function CastBar:SetUnit(unit)
    self:OnEvent("UNIT_SPELLCAST_STOP")
    self.unit = unit
    local f = self.frame
    if unit then
        f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
        f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
        local _, _, _, _, _, _, cast_guid = UnitCastingInfo(unit)
        if cast_guid then
            self:OnEvent("UNIT_SPELLCAST_START", unit, cast_guid)
        elseif UnitChannelInfo(unit) then
            self:OnEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
        end
    else
        f:UnregisterAllEvents()
    end
end

function CastBar:OnEvent(event, unit)
    event = strsub(event, 16, -1)  -- strip "UNIT_SPELLCAST_"

    if event == "START" then
        -- We're given an additional cast_guid argument with this event,
        -- but depending on timing (such as when the event occurs just as
        -- the enemy dies) it may be nil or UnitCastingInfo() may return
        -- no data, so it's not actually useful.  We don't make use of the
        -- cast GUID anyway, so just take what UnitCastingInfo() gives us.
        local name, display_name, icon, start_ms, end_ms, is_trade_skill,
              cast_guid, not_interruptible, spell_id, is_empowered,
              empower_stages = UnitCastingInfo(unit)
        if not cast_guid then return end  -- Enemy is already gone, etc.
        self.is_channel = false
        self.start = start_ms / 1000
        self.duration = (end_ms - start_ms) / 1000
        self.bar:Update(1, 0)
        self.bar:Show()
        self.label:SetText(display_name)
        self.label:Show()
        self.label_bg:SetWidth(self.label:GetStringWidth() + 10*self.label:GetTextScale())
        self.label_bg:Show()
        self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)

    elseif event == "CHANNEL_START" then
        -- Return values are as for UnitCastingInfo(), except that the
        -- cast GUID return value is omitted because channeling doesn't
        -- have a GUID.
        local _, display_name, _, start_ms, end_ms = UnitChannelInfo(unit)
        self.is_channel = true
        self.start = start_ms / 1000
        self.duration = (end_ms - start_ms) / 1000
        self.bar:Update(1, 1)
        self.bar:Show()
        self.label:SetText(display_name)
        self.label:Show()
        self.label_bg:SetWidth(self.label:GetWidth() + 10*self.label:GetTextScale())
        self.label_bg:Show()
        self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)

    elseif event == "DELAYED" then
        local _, _, _, new_start, new_end =  UnitCastingInfo(unit)
        self.start = new_start
        self.duration = new_end - new_start

    elseif event == "STOP" or event == "CHANNEL_STOP" then
        self.bar:Hide()
        self.label:Hide()
        self.label_bg:Hide()
        self.frame:SetScript("OnUpdate", nil)

    end
end

function CastBar:OnUpdate()
    local completion = (GetTime() - self.start) / self.duration
    if completion > 1 then completion = 1 end
    if self.is_channel then completion = 1 - completion end
    self.bar:Update(1, completion)
end
