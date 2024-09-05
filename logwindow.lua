local _, WoWXIV = ...
WoWXIV.LogWindow = {}

local class = WoWXIV.class

local CLM = WoWXIV.CombatLogManager
local UnitFlags = CLM.UnitFlags
local band = bit.band
local bor = bit.bor
local tinsert = tinsert

-- Mapping from logical event types (as passed to the Tab constructor) to
-- raw event names.  This is similar to, though orgainzed differently than,
-- the ChatTypeGroup mapping in Blizzard's ChatFrameBase module.
local MESSAGE_TYPES = {
    System = {"CHAT_MSG_SYSTEM",
              "-",
              "CHARACTER_POINTS_CHANGED",
              "DISPLAY_EVENT_TOAST_LINK",
              "GUILD_MOTD",
              "PLAYER_LEVEL_CHANGED",
              "TIME_PLAYED_MSG",
              "UNIT_LEVEL",
              "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE"},

    Error = {"CHAT_MSG_RESTRICTED",
             "CHAT_MSG_FILTERED"},

    Ping = {"CHAT_MSG_PING"},

    Channel = {"CHAT_MSG_CHANNEL_JOIN",
               "CHAT_MSG_CHANNEL_LEAVE",
               "CHAT_MSG_CHANNEL_NOTICE",
               "CHAT_MSG_CHANNEL_NOTICE_USER",
               "CHAT_MSG_CHANNEL_LIST",
               "CHAT_MSG_COMMUNITIES_CHANNEL"},

    Chat_Channel = {"CHAT_MSG_CHANNEL"},

    Chat_Say = {"SAY"},

    Chat_Emote = {"CHAT_MSG_EMOTE",
                  "CHAT_MSG_TEXT_EMOTE"},

    Chat_Yell = {"CHAT_MSG_YELL"},

    Chat_Whisper = {"CHAT_MSG_WHISPER",
                    "CHAT_MSG_WHISPER_INFORM",
                    "CHAT_MSG_AFK",
                    "CHAT_MSG_DND",
                    "CHAT_MSG_IGNORED"},

    Chat_NPC = {"CHAT_MSG_MONSTER_SAY",
                "CHAT_MSG_MONSTER_YELL",
                "CHAT_MSG_MONSTER_EMOTE",
                "CHAT_MSG_MONSTER_WHISPER",
                "CHAT_MSG_RAID_BOSS_EMOTE",
                "CHAT_MSG_RAID_BOSS_WHISPER"},

    Chat_Party = {"CHAT_MSG_PARTY",
                  "CHAT_MSG_PARTY_LEADER",
                  "CHAT_MSG_MONSTER_PARTY"},

    Chat_Raid = {"CHAT_MSG_RAID",
                 "CHAT_MSG_RAID_LEADER",
                 "CHAT_MSG_RAID_WARNING"},

    Chat_Instance = {"CHAT_MSG_INSTANCE_CHAT",
                     "CHAT_MSG_INSTANCE_CHAT_LEADER"},

    Chat_Guild = {"CHAT_MSG_GUILD"},

    Chat_GuildOfficer = {"CHAT_MSG_OFFICER"},

    BNWhisper = {"CHAT_MSG_BN_WHISPER",
                 "CHAT_MSG_BN_WHISPER_INFORM"},

    BNInlineToast = {"CHAT_MSG_BN_INLINE_TOAST_ALERT",
                     "CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
                     "CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM"},

    Combat_Reward = {"CHAT_MSG_COMBAT_XP_GAIN",
                     "CHAT_MSG_COMBAT_HONOR_GAIN"},

    Combat_Faction = {"CHAT_MSG_COMBAT_FACTION_CHANGE"},

    Combat_Misc = {"CHAT_MSG_COMBAT_MISC_INFO"},

    TargetIcon = {"CHAT_MSG_TARGETICONS"},

    BG_Alliance = {"CHAT_MSG_BG_SYSTEM_ALLIANCE"},

    BG_Horde = {"CHAT_MSG_BG_SYSTEM_HORDE"},

    BG_Neutral = {"CHAT_MSG_BG_SYSTEM_NEUTRAL"},

    Skill = {"CHAT_MSG_SKILL"},

    Loot = {"CHAT_MSG_LOOT",
            "CHAT_MSG_CURRENCY",
            "CHAT_MSG_MONEY"},

    Gathering = {"CHAT_MSG_OPENING"},

    TradeSkill = {"CHAT_MSG_TRADESKILLS"},

    PetInfo = {"CHAT_MSG_PET_INFO"},

    Achievement = {"CHAT_MSG_ACHIEVEMENT"},

    Guild = {"GUILD_MOTD"},

    Guild_Achievement = {"CHAT_MSG_GUILD_ACHIEVEMENT",
                         "CHAT_MSG_GUILD_ITEM_LOOTED"},

    PetBattle = {"CHAT_MSG_PET_BATTLE_COMBAT_LOG",
                 "CHAT_MSG_PET_BATTLE_INFO"},

    VoiceText = {"CHAT_MSG_VOICE_TEXT"},
}

-- For testing: set to true to keep the native chat frame visible
local KEEP_NATIVE_FRAME = false

--------------------------------------------------------------------------

local Tab = class()

function Tab:__constructor(name, message_types)
    assert(type(message_types) == "table")
    assert(#message_types > 0)
    for i, msg_type in ipairs(message_types) do
        assert(type(msg_type) == "string",
               "wrong element type at message_types["..i.."]")
        assert(MESSAGE_TYPES[msg_type],
               msg_type.." is not a recognized message type")
    end

    self.name = name
    self.types = message_types
end

function Tab:GetName()
    return self.name
end

-- Returns true if the given message should be displayed in this tab.
function Tab:Filter(event, text)
    for _, msg_type in ipairs(self.types) do
        for _, match_event in ipairs(MESSAGE_TYPES[msg_type]) do
            if event == match_event then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------

local TabBar = class()

function TabBar:__constructor(parent)
    self.tabs = {}
    self.active_tab = nil
    self.size_scale = 5/6  -- gives the right size at 2560x1440 with default UI scaling

    local frame = CreateFrame("Frame", nil, parent)
    self.frame = frame
    frame:SetSize(parent:GetWidth(), 26*self.size_scale)
    frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT")

    local left = frame:CreateTexture(nil, "BACKGROUND")
    self.left = left
    WoWXIV.SetUITexture(left, 0, 21, 52, 78)
    left:SetSize(21*self.size_scale, frame:GetHeight())
    left:SetPoint("TOPLEFT")

    local right = frame:CreateTexture(nil, "BACKGROUND")
    self.right = right
    WoWXIV.SetUITexture(right, 72, 96, 52, 78)
    right:SetSize(24*self.size_scale, frame:GetHeight())
    right:SetPoint("LEFT", left, "RIGHT")

    frame:SetScript("OnMouseDown", function(frame) self:OnClick() end)

    self:AddTab(Tab("General", {
        "System", "Error", "Ping",
        "Channel", "Chat_Channel",
        "Chat_Say", "Chat_Emote", "Chat_Yell", "Chat_Whisper",
        -- FF14 puts NPC dialogue in a separate "Event" tab, but we leave
        -- this in the main tab both to stick with WoW defaults and because
        -- many world events are announced via NPC chats.
        "Chat_NPC",
        "Chat_Party", "Chat_Raid", "Chat_Instance",
        "Chat_Guild", "Chat_GuildOfficer",
        "BNWhisper", "BNInlineToast",
        "Combat_Reward", "Combat_Faction", "Combat_Misc", "TargetIcon",
        "BG_Alliance", "BG_Horde", "BG_Neutral",
        "Skill", "Loot", "Achievement",
        "Guild", "Guild_Achievement",
        "VoiceText"}))
    self:AddTab(Tab("Battle", {"PetBattle"}))
    -- FIXME: temporary tab to check that all events are caught
    self:AddTab(Tab("Other", {"Gathering", "TradeSkill", "PetInfo"}))

    self:SetActiveTab(1)
    frame:Show()
end

function TabBar:AddTab(tab)
    local frame = self.frame
    local name = tab:GetName()
    local last = #self.tabs > 0 and self.tabs[#self.tabs].frame or self.left
    local index = #self.tabs + 1

    local tab_frame = CreateFrame("Frame", nil, frame)
    tab_frame:SetHeight(frame:GetHeight())
    tab_frame:SetPoint("LEFT", last, "RIGHT")

    local header = tab_frame:CreateTexture(nil, "BACKGROUND")
    header:SetWidth(16*self.size_scale)
    header:SetPoint("TOPLEFT")
    header:SetPoint("BOTTOMLEFT")
    WoWXIV.SetUITexture(header, 46, 62, 52, 78)

    local bg = tab_frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", header, "TOPRIGHT")
    bg:SetPoint("BOTTOMRIGHT")
    WoWXIV.SetUITexture(bg, 62, 70, 52, 78)

    local label = tab_frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", bg)
    label:SetTextColor(WHITE_FONT_COLOR:GetRGB())
    label:SetText(name)

    tab_frame:SetWidth(header:GetWidth()
                       + label:GetStringWidth() + 14*self.size_scale)

    self.right:ClearAllPoints()
    self.right:SetPoint("LEFT", tab_frame, "RIGHT")

    self.tabs[index] = {tab = tab, frame = tab_frame,
                        label = label, header = header, bg = bg}
end

function TabBar:SetActiveTab(index)
    self.active_tab = index
    for i, tab_info in ipairs(self.tabs) do
        local u0 = (i == index) and 21 or 46
        WoWXIV.SetUITexCoord(tab_info.header, u0, u0+16, 52, 78)
    end
    EventRegistry:TriggerEvent("WoWXIV.LogWindow.OnActiveTabChanged", index)
end

function TabBar:GetActiveTab()
    return self.active_tab and self.tabs[self.active_tab].tab
end

function TabBar:OnClick(button, down)
    for index, tab_info in ipairs(self.tabs) do
        if tab_info.frame:IsMouseOver() then
            self:SetActiveTab(index)
            return
        end
    end
end

-- Returns true if any tab accepts the given message.  Mainly for debugging.
function TabBar:FilterAnyTab(event, text)
    for _, tab in ipairs(self.tabs) do
        if tab.tab:Filter(event, text) then return true end
    end
    return false
end

--------------------------------------------------------------------------

local LogWindow = class()

function LogWindow:__constructor()
    -- ID of the event currently being processed.  This is used to fill in
    -- the event field in history entries, since most messages will come
    -- from Blizzard code which does not pass down the event ID.
    self.current_event = nil

    local frame = CreateFrame("ScrollingMessageFrame", "WoWXIV_LogWindow",
                              UIParent)
    self.frame = frame
    frame:SetSize(430, 120)
    if not KEEP_NATIVE_FRAME then
        frame:SetPoint("BOTTOMLEFT", ChatFrame1EditBox, "TOPLEFT", 5, 17)
    else
        frame:SetPoint("BOTTOMLEFT", GeneralDockManager, "TOPLEFT", 0, 24)
    end

    frame:SetTimeVisible(2*60)
    frame:SetMaxLines(WoWXIV_config["logwindow_history"])
    frame:SetFontObject(ChatFontNormal)
    frame:SetIndentedWordWrap(true)
    frame:SetJustifyH("LEFT")

    frame:SetScript("OnHyperlinkClick",
                    function(frame, link, text, button)
                        SetItemRef(link, text, button, frame)
                    end)
    frame:SetHyperlinksEnabled(true)

    -- Stuff needed by the common chat code
    self.channelList = {}
    self.zoneChannelList = {}
    ChatFrame_RegisterForChannels(self, GetChatWindowChannels(1))

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

    local tab_bar = TabBar(frame)
    self.tab_bar = tab_bar
    EventRegistry:RegisterCallback(
        "WoWXIV.LogWindow.OnActiveTabChanged",
        function(_, index) self:OnActiveTabChanged(index) end)

    local tab = tab_bar:GetActiveTab()
    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histindex = WoWXIV_logwindow_hist_top
    for i = 1, histlen do
        local ts, event, text, r, g, b = unpack(history[histindex])
        if tab:Filter(event, text) then
            frame:AddMessage(text, r, g, b, 0.5)
        end
        histindex = (histindex == histlen) and 1 or histindex+1
    end
end

function LogWindow:PLAYER_ENTERING_WORLD(event)
    self.lang_default = GetDefaultLanguage()
    self.lang_alt = GetAlternativeDefaultLanguage()
    self.current_event = event
    ChatFrame_ConfigEventHandler(self, event)
    self.current_event = nil
end

function LogWindow:ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED(event)
    self.lang_alt = GetAlternativeDefaultLanguage()
    self.current_event = event
    ChatFrame_ConfigEventHandler(self, event)
    self.current_event = nil
end

function LogWindow:UPDATE_CHAT_COLOR_NAME_BY_CLASS(event, ...)
    self.current_event = event
    ChatFrame_ConfigEventHandler(self, event, ...)
    self.current_event = nil
end

function LogWindow:CHAT_MSG_CHANNEL_NOTICE(event, type, _, _, link_text, _, _, id, index, name)
    local link = "|Hchannel:CHANNEL:" .. index .. "|h[" .. link_text .. "]|h"
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
    self:AddMessage(event, text, info.r, info.g, info.b)
end

function LogWindow:OnChatMsg(event, ...)
    self.current_event = event
    ChatFrame_MessageEventHandler(self, event, ...)
    self.current_event = nil
end

function LogWindow:OnNonChatMsg(event, ...)
    self.current_event = event
    ChatFrame_SystemEventHandler(self, event, ...)
    self.current_event = nil
end

function LogWindow:AddHistoryEntry(event, text, r, g, b)
    local record = {WoWXIV.timePrecise(), event, text, r, g, b}
    local histsize = WoWXIV_config["logwindow_history"]
    if #WoWXIV_logwindow_history < histsize then
        assert(WoWXIV_logwindow_hist_top == 1)
        tinsert(WoWXIV_logwindow_history, record)
    else
        local histindex = WoWXIV_logwindow_hist_top
        WoWXIV_logwindow_history[histindex] = record
        if histindex == histsize then
            WoWXIV_logwindow_hist_top = 1
        else
            WoWXIV_logwindow_hist_top = histindex + 1
        end
    end
end

function LogWindow:OnActiveTabChanged(index)
    local tab = self.tab_bar:GetActiveTab()
    local frame = self.frame
    frame:RemoveMessagesByPredicate(function() return true end)
    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histindex = WoWXIV_logwindow_hist_top
    for i = 1, histlen do
        local ts, event, text, r, g, b = unpack(history[histindex])
        if not tab or tab:Filter(event, text) then
            frame:AddMessage(text, r, g, b)
        end
        histindex = (histindex == histlen) and 1 or histindex+1
    end
end

-- Various methods called on DEFAULT_CHAT_FRAME.
function LogWindow:GetID() return 1 end
function LogWindow:IsShown() return true end
function LogWindow:GetFont() return self.frame:GetFontObject() end
function LogWindow:SetHyperlinksEnabled(enable) end
function LogWindow:AddMessage(event, text, r, g, b)
    if type(text) ~= "string" then  -- event omitted (as from Blizzard code)
        event, text, r, g, b = (self.current_event or "-"), event, text, r, g
    end
    r = r or 1
    g = g or 1
    b = b or 1
    if not KEEP_NATIVE_FRAME then
        self.last_message = self.last_message or {0, 0, 0, 0, 0}
        self.saved_message = self.saved_message or {0, 0, 0, 0, 0}
        if event ~= "_" and text == self.saved_message[2] and r == self.saved_message[3] and g == self.saved_message[4] and b == self.saved_message[5] then
            self.saved_message[2] = 0
        end
        if self.saved_message[2] ~= 0 then
            local saved_event, saved_text, saved_r, saved_g, saved_b = unpack(self.saved_message)
            if saved_event == "_" then saved_event = "-" end
            self.saved_message[2] = 0
            self:AddMessage(saved_event, saved_text, saved_r, saved_g, saved_b)
        end
        if event == nil then return end  -- from RunNextFrame call below
        if event == "_" then
            if not (text == self.last_message[2] and r == self.last_message[3] and g == self.last_message[4] and b == self.last_message[5]) then
                self.saved_message[1] = event
                self.saved_message[2] = text
                self.saved_message[3] = r
                self.saved_message[4] = g
                self.saved_message[5] = b
                RunNextFrame(function() self:AddMessage(nil, text=="" and "-" or "") end)
            end
            return
        end
        self.last_message[1] = event
        self.last_message[2] = text
        self.last_message[3] = r
        self.last_message[4] = g
        self.last_message[5] = b
        RunNextFrame(function() self.last_message[2] = 0 end)
    end  -- if not KEEP_NATIVE_FRAME
    if self.tab_bar:GetActiveTab():Filter(event, text) then
        self.frame:AddMessage(text, r, g, b)
    end
    self:AddHistoryEntry(event, text, r, g, b)
    if not self.tab_bar:FilterAnyTab(event, text) then
        self.frame:AddMessage("[WoWXIV.LogWindow] Event not taken by any tab: ["..event.."] "..text)
    end
end

--------------------------------------------------------------------------

-- Create the global log window object.
function WoWXIV.LogWindow.Create()
    if not WoWXIV_config["logwindow_enable"] then return end

    WoWXIV_logwindow_history = WoWXIV_logwindow_history or {}
    WoWXIV_logwindow_hist_top = WoWXIV_logwindow_hist_top or 1
    WoWXIV.LogWindow.PruneHistory()

    WoWXIV.LogWindow.window = LogWindow()
    if not KEEP_NATIVE_FRAME then
        WoWXIV.HideBlizzardFrame(GeneralDockManager)
        local index = 1
        while _G["ChatFrame"..index] do
            local frame = _G["ChatFrame"..index]
            WoWXIV.HideBlizzardFrame(frame)
            index = index + 1
        end
        DEFAULT_CHAT_FRAME.AddMessage = function(frame, ...)
            WoWXIV.LogWindow.window:AddMessage(...)
        end
    else
        local saved_AddMessage = DEFAULT_CHAT_FRAME.AddMessage
        DEFAULT_CHAT_FRAME.AddMessage = function(frame, ...)
            saved_AddMessage(frame, ...)
            WoWXIV.LogWindow.window:AddMessage("_", ...)
        end
    end
end

-- Discard any log window history entries older than the current limit.
-- Also reorders the history buffer if needed for limit changes.
function WoWXIV.LogWindow.PruneHistory()
    local history = WoWXIV_logwindow_history
    local histlen = #history
    local histsize = WoWXIV_config["logwindow_history"]
    if histlen > histsize or (histlen < histsize and WoWXIV_logwindow_hist_top ~= 1) then
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
