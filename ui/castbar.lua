local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
UI.CastBar = class()

local strsub = string.sub

------------------------------------------------------------------------

local CastBar = UI.CastBar

function CastBar:__constructor(parent, width, with_interruptible)
    self.width = width
    self.with_interruptible = with_interruptible
    self.unit = nil    -- Unit token of unit being monitored, or nil if none
    self.name = nil    -- Name of current cast, nil if no cast is active
    self.is_channel = false -- Is this a normal cast (false) or channel (true)?
    self.start = 0     -- Start timestamp of current cast
    self.duration = 0  -- Expected duration of current cast
    self.interruptible = false  -- Is current cast interruptible?
    self.interrupt_start = nil  -- Interruptible animation start timestamp

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

    if with_interruptible then
        local box_c = bar:GetBoxTexture()
        local interrupt_c_width = box_c:GetWidth()
        self.interrupt_c_width = interrupt_c_width

        local interrupt_c = f:CreateTexture(nil, "BORDER")
        self.interrupt_c = interrupt_c
        interrupt_c:SetPoint("CENTER", box_c, "CENTER")
        interrupt_c:SetSize(interrupt_c_width, 15)
        WoWXIV.SetUITexture(interrupt_c, 6, 90, 37, 52)
        interrupt_c:Hide()

        local interrupt_l = f:CreateTexture(nil, "BORDER")
        self.interrupt_l = interrupt_l
        interrupt_l:SetPoint("RIGHT", interrupt_c, "LEFT")
        interrupt_l:SetSize(6, 15)
        WoWXIV.SetUITexture(interrupt_l, 0, 6, 37, 52)
        interrupt_l:Hide()

        local interrupt_r = f:CreateTexture(nil, "BORDER")
        self.interrupt_r = interrupt_r
        interrupt_r:SetPoint("LEFT", interrupt_c, "RIGHT")
        interrupt_r:SetSize(6, 15)
        WoWXIV.SetUITexture(interrupt_r, 90, 96, 37, 52)
        interrupt_r:Hide()
    end
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

function CastBar:SetBoxColor(r, g, b)
    self.bar:SetBoxColor(r, g, b)
    if self.with_interruptible then
        self.interrupt_c:SetVertexColor(r, g, b)
        self.interrupt_l:SetVertexColor(r, g, b)
        self.interrupt_r:SetVertexColor(r, g, b)
    end
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
        -- We can't manipulate the display state directly here because
        -- we sometimes get STOP/START pairs during the cast (seems to
        -- happen particularly often with CHANNEL_START), so instead we
        -- just set fields and use OnUpdate() to apply the changes.
        -- What a well-programmed game this is...
        self.name = display_name
        self.is_channel = false
        self.start = start_ms / 1000
        self.duration = (end_ms - start_ms) / 1000
        self.interruptible = not not_interruptible
        self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)

    elseif event == "CHANNEL_START" then
        -- Return values are as for UnitCastingInfo(), except that the
        -- cast GUID return value is omitted because channeling doesn't
        -- have a GUID.
        local _, display_name, _, start_ms, end_ms, _, not_interruptible =
            UnitChannelInfo(unit)
        self.name = display_name
        self.is_channel = true
        self.start = start_ms / 1000
        self.duration = (end_ms - start_ms) / 1000
        self.interruptible = not not_interruptible
        self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)

    elseif event == "DELAYED" then
        local _, _, _, new_start, new_end =  UnitCastingInfo(unit)
        self.start = new_start
        self.duration = new_end - new_start

    elseif event == "INTERRUPTIBLE" then
        self.interruptible = true

    elseif event == "NOT_INTERRUPTIBLE" then
        self.interruptible = false

    elseif event == "STOP" or event == "CHANNEL_STOP" then
        self.name = nil

    end
end

function CastBar:OnUpdate()
    local bar = self.bar
    local label = self.label
    local label_bg = self.label_bg

    if not self.name then
        bar:Hide()
        label:Hide()
        label_bg:Hide()
        if self.with_interruptible then
            self.interruptible = false
            self.interrupt_c:Hide()
            self.interrupt_l:Hide()
            self.interrupt_r:Hide()
        end
        self.frame:SetScript("OnUpdate", nil)
        return
    end

    local completion = (GetTime() - self.start) / self.duration
    if completion < 0 then completion = 0 end
    if completion > 1 then completion = 1 end
    if self.is_channel then completion = 1 - completion end
    bar:Update(1, completion)
    if self.name ~= label:GetText() then
        label:SetText(self.name)
        label_bg:SetWidth(label:GetStringWidth() + 10*label:GetTextScale())
    end
    if not label:IsShown() then
        bar:Show()
        label:Show()
        label_bg:Show()
    end
    if self.with_interruptible then
        local interruptible = self.interruptible
        local interrupt_c = self.interrupt_c
        local interrupt_l = self.interrupt_l
        local interrupt_r = self.interrupt_r
        if not self.interruptible then
            if interrupt_c:IsShown() then
                interrupt_c:Hide()
                interrupt_l:Hide()
                interrupt_r:Hide()
            end
        else
            if not interrupt_c:IsShown() then
                self.interrupt_start = GetTime()
                self.interrupt_c:Show()
                self.interrupt_l:Show()
                self.interrupt_r:Show()
            end
            local t = (GetTime() - self.interrupt_start) / 0.75
            t = t - math.floor(t)
            local scale = 1 + 2*t
            local alpha = 1 - t*t
            interrupt_c:SetSize(self.interrupt_c_width + 18*(scale-1), 15*scale)
            interrupt_c:SetAlpha(alpha)
            interrupt_l:SetSize(6*scale, 15*scale)
            interrupt_l:SetAlpha(alpha)
            interrupt_r:SetSize(6*scale, 15*scale)
            interrupt_r:SetAlpha(alpha)
        end
    end
end
