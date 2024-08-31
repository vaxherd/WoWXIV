local _, WoWXIV = ...
WoWXIV.LogWindow = {}

local class = WoWXIV.class

local CLM = WoWXIV.CombatLogManager
local UnitFlags = CLM.UnitFlags
local band = bit.band
local bor = bit.bor
local tinsert = tinsert

--------------------------------------------------------------------------

local LogWindow = class()

function LogWindow:__constructor()
    local frame = CreateFrame("ScrollingMessageFrame", "WoWXIV_LogWindow",
                              UIParent)
    self.frame = frame
    frame:SetSize(430, 120)
    -- FIXME: put above the native chat frame until we're done testing
    frame:SetPoint("BOTTOMLEFT", GeneralDockManager, "TOPLEFT")

    frame:SetTimeVisible(2*60)
    frame:SetMaxLines(WoWXIV_config["logwindow_history"])
    frame:SetFontObject(ChatFontNormal)
    frame:SetIndentedWordWrap(true)
    frame:SetJustifyH("LEFT")

    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histindex = WoWXIV_logwindow_hist_top
    for i = 1, histlen do
        local ts, text, r, g, b = unpack(history[histindex])
        frame:AddMessage(text, r, g, b, 0.5)
        histindex = (histindex == histlen) and 1 or histindex+1
    end

    frame:SetScript("OnHyperlinkClick",
                    function(frame, link, text, button)
                        SetItemRef(link, text, button, frame)
                    end)
    frame:SetHyperlinksEnabled(true)

    -- Stuff needed by the common chat code
    self.channelList = {}
    self.zoneChannelList = {}
    for index, name in pairs(DEFAULT_CHAT_FRAME.channelList) do
        self.channelList[index] = name
    end
    for index, name in pairs(DEFAULT_CHAT_FRAME.zoneChannelList) do
        self.zoneChannelList[index] = name
    end

    frame:SetScript("OnEvent", function(frame, event, ...)
                                   if self[event] then
                                       self[event](self, event, ...)
                                   end
                               end)
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHAT_MSG_CHANNEL")
    frame:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
    frame:RegisterEvent("CLUB_REMOVED")
    frame:RegisterEvent("UPDATE_INSTANCE_INFO")
    frame:RegisterEvent("UPDATE_CHAT_COLOR_NAME_BY_CLASS")
    frame:RegisterEvent("CHAT_SERVER_DISCONNECTED")
    frame:RegisterEvent("CHAT_SERVER_RECONNECTED")
    frame:RegisterEvent("BN_CONNECTED")
    frame:RegisterEvent("BN_DISCONNECTED")
    frame:RegisterEvent("PLAYER_REPORT_SUBMITTED")
    frame:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
    frame:RegisterEvent("ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED")
    frame:RegisterEvent("NEWCOMER_GRADUATION")
    frame:RegisterEvent("CHAT_REGIONAL_STATUS_CHANGED")
    frame:RegisterEvent("CHAT_REGIONAL_SEND_FAILED")
    frame:RegisterEvent("NOTIFY_CHAT_SUPPRESSED")

    local OnChatMsg = self.OnChatMsg
    local OnNonChatMsg = self.OnNonChatMsg
    self.CHAT_MSG_CHANNEL = OnChatMsg
    self.CHAT_MSG_COMMUNITIES_CHANNEL = OnChatMsg
    self.CLUB_REMOVED = OnNonChatMsg
    self.UPDATE_INSTANCE_INFO = OnNonChatMsg
    self.CHAT_SERVER_DISCONNECTED = OnNonChatMsg
    self.CHAT_SERVER_RECONNECTED = OnNonChatMsg
    self.BN_CONNECTED = OnNonChatMsg
    self.BN_DISCONNECTED = OnNonChatMsg
    self.PLAYER_REPORT_SUBMITTED = OnNonChatMsg
    self.CHAT_REGIONAL_STATUS_CHANGED = OnNonChatMsg
    self.CHAT_REGIONAL_SEND_FAILED = OnNonChatMsg
    self.NOTIFY_CHAT_SUPPRESSED = OnNonChatMsg
    local VALID_EVENT_TYPES = {  -- For sanity checking, see below.
        TIME_PLAYED_MSG = true,
        PLAYER_LEVEL_CHANGED = true,
        UNIT_LEVEL = true,
        CHARACTER_POINTS_CHANGED = true,
        DISPLAY_EVENT_TOAST_LINK = true,
        GUILD_MOTD = true,
    }
    -- Blizzard's ChatFrameBase module defines data for all the various types
    -- of chat messages, but then bizarrely hides them from direct iteration.
    -- We can still get the list via the metatable, though.
    for type, info in pairs(getmetatable(ChatTypeInfo).__index) do
        if type == "CHANNEL1" then type = "CHANNEL" end
        local group = ChatTypeGroup[type]
        if group then  -- false for CHANNEL2 and onward
            for _, event in ipairs(group) do
                if event:sub(1, 9) == "CHAT_MSG_" then
                    if not self[event] then self[event] = OnChatMsg end
                else
                    assert(VALID_EVENT_TYPES[event])
                    if not self[event] then self[event] = OnNonChatMsg end
                end
                frame:RegisterEvent(event)
            end
        end
    end
    -- FIXME: temp reduce spam until we have proper filter config
    frame:UnregisterEvent("CHAT_MSG_TRADESKILLS")

    local scrollbar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    self.scrollbar = scrollbar
    scrollbar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 3, 0)
    scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 3, 0)
    ScrollUtil.InitScrollingMessageFrameWithScrollBar(frame, scrollbar)
    scrollbar:Show()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    self.background = bg
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
    -- HACK: scrollbar frame is smaller than the actual visuals
    bg:SetPoint("BOTTOMRIGHT", scrollbar, "BOTTOMRIGHT", 5, -3)
    bg:SetColorTexture(0, 0, 0, 0.25)
end

function LogWindow:PLAYER_ENTERING_WORLD(event)
    self.lang_default = GetDefaultLanguage()
    self.lang_alt = GetAlternativeDefaultLanguage()
    ChatFrame_ConfigEventHandler(self, event)
end

function LogWindow:ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED(event)
    self.lang_alt = GetAlternativeDefaultLanguage()
    ChatFrame_ConfigEventHandler(self, event)
end

function LogWindow:UPDATE_CHAT_COLOR_NAME_BY_CLASS(event, ...)
    ChatFrame_ConfigEventHandler(self, event, ...)
end

function LogWindow:CHAT_MSG_CHANNEL_NOTICE(event, type, _, _, link_text, _, _, id, index, name)
    local link = "|Hchannel:channel:" .. index .. "|h[" .. link_text .. "]|h"
    local text
    if type == "YOU_CHANGED" then
        self.channelList[index] = name
        self.zoneChannelList[index] = id
        text = "Changed Channel: " .. link
    elseif type == "YOU_LEFT" or type == "SUSPENDED" then
        self.channelList[index] = nil
        self.zoneChannelList[index] = nil
        text = "Left Channel: " .. link
    else
        error("unknown type " .. type)
    end
    local chat_type = "CHANNEL" .. index
    local info = ChatTypeInfo[chat_type]
    self:AddMessage(text, info.r, info.g, info.b)
end

function LogWindow:OnChatMsg(event, ...)
    ChatFrame_MessageEventHandler(self, event, ...)
end

function LogWindow:OnNonChatMsg(event, ...)
    ChatFrame_SystemEventHandler(self, event, ...)
end

function LogWindow:AddHistoryEntry(text, r, g, b)
    local record = {time(), text, r, g, b}
    local histsize = WoWXIV_config["logwindow_history"]
    if #WoWXIV_logwindow_history < histsize then
        tinsert(WoWXIV_logwindow_history, record)
    else
        WoWXIV_logwindow_history[WoWXIV_logwindow_hist_top] = record
        WoWXIV_logwindow_hist_top = WoWXIV_logwindow_hist_top + 1
    end
end

-- Needed by ChatFrame_MessageEventHandler().
function LogWindow:GetID() return 1 end
function LogWindow:IsShown() return true end
function LogWindow:AddMessage(text, r, g, b)
    self.frame:AddMessage(text, r, g, b)
    self:AddHistoryEntry(text, r, g, b)
end

--------------------------------------------------------------------------

-- Create the global log window object.
function WoWXIV.LogWindow.Create()
    if not WoWXIV_config["logwindow_enable"] then return end

    WoWXIV_logwindow_history = WoWXIV_logwindow_history or {}
    WoWXIV_logwindow_hist_top = WoWXIV_logwindow_hist_top or 1
    WoWXIV.LogWindow.PruneHistory()

    WoWXIV.LogWindow.window = LogWindow()
    if false then  -- FIXME: keep native chat window around while testing
        WoWXIV.HideBlizzardFrame(GeneralDockManager)
        local index = 1
        while _G["ChatFrame"..index] do
            local frame = _G["ChatFrame"..index]
            WoWXIV.HideBlizzardFrame(frame)
        end
    end
end

-- Discard any log window history entries older than the current limit.
function WoWXIV.LogWindow.PruneHistory()
    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histsize = WoWXIV_config["logwindow_history"]
    if histlen > histsize then
        local new_history = {}
        local histindex = WoWXIV_logwindow_hist_top
        for i = 1, histsize do
            tinsert(new_history, history[histindex])
            histindex = (histindex == histlen) and 1 or histindex+1
        end
        WoWXIV_logwindow_history = new_history
        WoWXIV_logwindow_hist_top = 1
    end
end
