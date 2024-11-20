local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local MenuFrame = MenuCursor.MenuFrame
local StandardMenuFrame = MenuCursor.StandardMenuFrame

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local AuctionHouseFrameHandler = class(MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(AuctionHouseFrameHandler)
local BuyTabHandler = class(StandardMenuFrame)
local ItemBuyFrameHandler = class(StandardMenuFrame)
local CommoditiesBuyFrameHandler = class(StandardMenuFrame)
local BuyDialogHandler = class(StandardMenuFrame)
local SellTabHandler = class(StandardMenuFrame)
local AuctionsTabHandler = class(StandardMenuFrame)


-------- Top-level frame

function AuctionHouseFrameHandler.Initialize(class, cursor)
    class:RegisterAddOnWatch("Blizzard_AuctionHouseUI")
end

function AuctionHouseFrameHandler.OnAddOnLoaded(class)
    local instance = class()
    class.instance = instance
    class.instance_BuyTab = BuyTabHandler()
    class.instance_ItemBuyFrame = ItemBuyFrameHandler()
    class.instance_CommoditiesBuyFrame = CommoditiesBuyFrameHandler()
    class.instance_BuyDialog = BuyDialogHandler()
    class.instance_SellTab = SellTabHandler()
    class.instance_AuctionsTab = AuctionsTabHandler()
end

function AuctionHouseFrameHandler:__constructor()
    self:__super(AuctionHouseFrame)
    -- AuctionHouseFrame itself is just a holder for the tabs and the
    -- individual tab content pages, so we don't have any menu behavior
    -- of our own.  We still HookShow() because the current tab page
    -- remains shown even while this frame is closed.
    self:HookShow(AuctionHouseFrame)
    -- This is never called because this frame is never set active,
    -- but subframe handler classes reference it.
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function AuctionHouseFrameHandler.CancelMenu()  -- Static method.
    HideUIPanel(AuctionHouseFrame)
end

function AuctionHouseFrameHandler:OnShow()
    if AuctionHouseFrame.BrowseResultsFrame:IsShown() then
        AuctionHouseFrameHandler.instance_BuyTab:OnShow()
    elseif AuctionHouseFrame.ItemSellFrame:IsShown() then
        AuctionHouseFrameHandler.instance_SellTab:OnShow()
    elseif AuctionHouseFrameAuctionsFrame:IsShown() then
        AuctionHouseFrameHandler.instance_AuctionsTab:OnShow()
    end
end

function AuctionHouseFrameHandler:OnHide()
    if AuctionHouseFrame.BrowseResultsFrame:IsShown() then
        AuctionHouseFrameHandler.instance_BuyTab:OnHide()
    elseif AuctionHouseFrame.ItemSellFrame:IsShown() then
        AuctionHouseFrameHandler.instance_SellTab:OnHide()
    elseif AuctionHouseFrameAuctionsFrame:IsShown() then
        AuctionHouseFrameHandler.instance_AuctionsTab:OnHide()
    end
    AuctionHouseFrameHandler.instance_BuyTab:ClearCurrent()
end

function AuctionHouseFrameHandler:OnTabCycle(direction)
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = #self.frame.Tabs
    elseif new_index > #self.frame.Tabs then
        new_index = 1
    end
    self.frame.Tabs[new_index]:OnClick("LeftButton", true)
end


-------- Auction search frame and results list

function BuyTabHandler:__constructor()
    self:__super(AuctionHouseFrame.BrowseResultsFrame)
    self.cancel_func = AuctionHouseFrameHandler.CancelMenu
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")

    -- NB: These might be useful in implementing local throttling:
    --self:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    --self:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
    --self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")

    -- Most recently selected index, for restoring cursor position.
    self.current_index = nil
end

function BuyTabHandler:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
    self:SetTarget(self:RefreshTargets())
end

function BuyTabHandler:AUCTION_HOUSE_BROWSE_RESULTS_ADDED(added_results)
    -- This event is intended to allow update optimization by indicating
    -- the set of newly added results, but since we don't need to fetch
    -- any external data anyway, we just ignore the argument and do a
    -- complete refresh.
    self:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
end

-- Called when AuctionHouseFrame is closed to reset the stored cursor
-- position.
function BuyTabHandler:ClearCurrent()
    self.current_index = nil
end

function BuyTabHandler:OnShow()
    assert(AuctionHouseFrame:IsShown())
    assert(AuctionHouseFrame.BrowseResultsFrame:IsShown())
    self.targets = {}
    self:Enable()
    RunNextFrame(function()
        self:SetTarget(self:RefreshTargets())
    end)
end

function BuyTabHandler:OnHide()
    self:Disable()
end

function BuyTabHandler:RefreshTargets()
    local SearchBar = AuctionHouseFrame.SearchBar
    local ItemList = AuctionHouseFrame.BrowseResultsFrame.ItemList

    self:ClearTarget()
    self.targets = {}

    self.targets[SearchBar.FavoritesSearchButton] = {
        can_activate = true, lock_highlight = true,
        up = false, down = false, left = SearchBar.SearchButton}
    self.targets[SearchBar.SearchBox] = {
        lock_highlight = true,  -- FIXME: implement click
        up = false, down = false}
    self.targets[SearchBar.FilterButton] = {
        lock_highlight = true,  -- FIXME: implement dropdown
        up = false, down = false}
    self.targets[SearchBar.SearchButton] = {
        can_activate = true, lock_highlight = true,
        up = false, down = false, right = SearchBar.FavoritesSearchButton}

    local ItemScroll = ItemList.ScrollBox
    -- The results list data provider is missing a ForEach method, so we
    -- have to roll our own.
    local function ForEachItem(callback)
        local frame = self.frame
        for _, index in ItemScroll:GetDataProvider():EnumerateEntireRange() do
            -- FIXME: any better way than peeking at private data?
            local element = frame.browseResults[index]
            callback(element)
        end
    end
    local function AddTarget(elementdata, index)
        local attributes = {can_activate = true, send_enter_leave = true,
                            left = false, right = false}
        return attributes, index == self.current_index
    end
    local top, bottom, initial =
        self:AddScrollBoxTargets(ItemScroll, AddTarget, ForEachItem)
    if top then
        self.targets[top].up = SearchBar.FavoritesSearchButton
        self.targets[bottom].down = SearchBar.FavoritesSearchButton
    end
    for _, target in ipairs({SearchBar.FavoritesSearchButton,
                             SearchBar.SearchBox,
                             SearchBar.FilterButton,
                             SearchBar.SearchButton}) do
        self.targets[target].down = top or false
        self.targets[target].up = bottom or false
    end
    return initial or top or SearchBar.FavoritesSearchButton
end

function BuyTabHandler:OnMove(old_target, new_target)
    if new_target and self.targets[new_target].is_scroll_box then
        self.current_index = new_target.index
    end
end


-------- Purchase window (individual items)

function ItemBuyFrameHandler:__constructor()
    self:__super(AuctionHouseFrame.ItemBuyFrame)
    self.cancel_func = nil
    self.cancel_button = self.frame.BackButton
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    self:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
end

function ItemBuyFrameHandler:ITEM_SEARCH_RESULTS_UPDATED()
    -- Looks like we have to wait a frame before the list finishes
    -- populating itself.
    RunNextFrame(function()
        local target = self:GetTarget()
        local index =
            target and self.targets[target].is_scroll_box and target.index
        self:ClearTarget()
        self:SetTarget(self:RefreshTargets(index or target))
    end)
end

function ItemBuyFrameHandler:ITEM_SEARCH_RESULTS_ADDED(added_results)
    -- See note in BuyTabHandler:AUCTION_HOUSE_BROWSE_RESULTS_ADDED().
    self:ITEM_SEARCH_RESULTS_UPDATED()
end

function ItemBuyFrameHandler:SetTargets()
    return self:RefreshTargets()
end

function ItemBuyFrameHandler:RefreshTargets(last_target)
    local frame = self.frame
    local BackButton = frame.BackButton
    local RefreshButton = frame.ItemList.RefreshFrame.RefreshButton
    local ItemButton = frame.ItemDisplay.ItemButton
    local BuyoutButton = frame.BuyoutFrame.BuyoutButton
    self.targets = {
        [BackButton] = {can_activate = true, lock_highlight = true,
                        up = BuyoutButton, down = ItemButton,
                        left = RefreshButton, right = RefreshButton},
        [RefreshButton] = {can_activate = true, lock_highlight = true,
                           up = false, down = false,
                           left = BackButton, right = BackButton},
        [ItemButton] = {send_enter_leave = true,
                        up = BackButton, down = BuyoutButton,
                        left = false, right = false},
        [BuyoutButton] = {can_activate = true, lock_highlight = true,
                          up = ItemButton, down = BackButton,
                          left = false, right = false, is_default = true},
    }
    local function OnClickItem(target)
        local button = self:GetTargetFrame(target)
        button:GetScript("OnClick")(button, "LeftButton", true)
        self:SetTarget(BuyoutButton)
    end
    local ItemScroll = frame.ItemList.ScrollBox
    local function ForEachItem(callback)
        for _, index in ItemScroll:GetDataProvider():EnumerateEntireRange() do
            local element =
                C_AuctionHouse.GetItemSearchResultInfo(frame.itemKey, index)
            callback(element)
        end
    end
    local function AddTarget(elementdata, index)
        local attributes = {on_click = OnClickItem, send_enter_leave = true,
                            left = false, right = false}
        return attributes, index == last_target
    end
    local top, bottom, initial =
        self:AddScrollBoxTargets(ItemScroll, AddTarget, ForEachItem)
    if top then
        self.targets[top].up = ItemButton
        self.targets[bottom].down = BuyoutButton
    end
    self.targets[ItemButton].down = top or BuyoutButton
    self.targets[BuyoutButton].up = bottom or ItemButton
    return (initial
            or top
            or (last_target and self.targets[last_target] and last_target)
            or BackButton)
end


-------- Purchase window (commodities)

function CommoditiesBuyFrameHandler:__constructor()
    self:__super(AuctionHouseFrame.CommoditiesBuyFrame)
    self.cancel_func = nil
    self.cancel_button = self.frame.BackButton
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
end

function CommoditiesBuyFrameHandler:OnHide()
    self:ToggleEditQuantity(true)
    StandardMenuFrame.OnHide(self)
end

function CommoditiesBuyFrameHandler:SetTargets()
    local BackButton = self.frame.BackButton
    local RefreshButton = self.frame.ItemList.RefreshFrame.RefreshButton
    local BuyDisplay = self.frame.BuyDisplay
    local ItemButton = BuyDisplay.ItemDisplay.ItemButton
    local InputBox = BuyDisplay.QuantityInput.InputBox
    local BuyButton = BuyDisplay.BuyButton
    self.targets = {
        [BackButton] = {can_activate = true, lock_highlight = true,
                        up = BuyButton, down = ItemButton,
                        left = RefreshButton, right = RefreshButton},
        [RefreshButton] = {can_activate = true, lock_highlight = true,
                           up = false, down = false,
                           left = BackButton, right = BackButton},
        [ItemButton] = {send_enter_leave = true,
                        up = BackButton, down = InputBox,
                        left = false, right = false},
        [InputBox] = {on_click = function() self:ToggleEditQuantity() end,
                      up = ItemButton, down = BuyButton,
                      left = false, right = false},
        [BuyButton] = {can_activate = true, lock_highlight = true,
                       up = InputBox, down = BackButton,
                       left = false, right = false, is_default = true},
    }
end

function CommoditiesBuyFrameHandler:ToggleEditQuantity(force_off)
    local BuyDisplay = self.frame.BuyDisplay
    local InputBox = BuyDisplay.QuantityInput.InputBox
    if not force_off and not self.targets[InputBox].dpad_override then
        local value = InputBox:GetNumber()
        if not value or value < 1 then
            value = 1
        end
        local item = BuyDisplay:GetItemID()
        if item then
            local limit = AuctionHouseUtil.AggregateSearchResultsByQuantity(
                item, math.huge)
            if limit and limit > 0 then
                self.targets[InputBox].dpad_override = true
                self.cancel_func = function() self:ToggleEditQuantity(true) end
                self.cancel_button = nil
                local text = tostring(value)
                self.edit_number_pos = 0
                self.edit_number_max = limit
                InputBox:SetText(text)
            end
        end
    elseif self.targets[InputBox] then
        if self.targets[InputBox].dpad_override then
            local callback = InputBox:GetInputChangedCallback()
            assert(callback)  -- Should be set by Blizzard code.
            callback()
        end
        self.targets[InputBox].dpad_override = false
        self.cancel_func = nil
        self.cancel_button = self.frame.BackButton
    end
end

function CommoditiesBuyFrameHandler:OnDPad(dir)
    local BuyDisplay = self.frame.BuyDisplay
    local InputBox = BuyDisplay.QuantityInput.InputBox
    assert(self.targets[InputBox].dpad_override)
    local text = InputBox:GetText()
    local value = tonumber(text)
    local pos = self.edit_number_pos
    local limit = self.edit_number_max
    if not pos or pos < 0 then pos = 0 end
    if pos >= #text then pos = #text-1 end
    local unit = 10^pos

    if dir == "up" then
        if value >= limit then
            value = 1
        else
            value = value + unit
            if value > limit then value = limit end
        end
        text = tostring(value)
    elseif dir == "down" then
        if value <= 1 then
            value = limit
        else
            value = value - unit
            if value < 1 then value = 1 end
        end
        text = tostring(value)
        while pos >= #text do
            text = "0"..text
        end
    elseif dir == "left" then
        if pos < #text-1 then
            pos = pos + 1
        elseif unit*10 <= limit then
            text = "0"..text
            pos = pos + 1
        else
            text = tostring(limit)
        end
    else assert(dir == "right")
        if pos == 0 then
            text = "1"
            pos = 1
        else
            if pos == #text-1 and strsub(text, 1, 1) == "0" then
                text = strsub(text, 2)
            end
            pos = pos - 1
        end
    end

    self.edit_number_pos = pos
    InputBox:SetText(text)
    local callback = InputBox:GetInputChangedCallback()
    assert(callback)  -- Should be set by Blizzard code.
    callback()
    InputBox:SetText(text)  -- Override any changes by the Blizzard callback.
end


-------- Buy dialog

function BuyDialogHandler:__constructor()
    self:__super(AuctionHouseFrame.BuyDialog, MenuFrame.MODAL)
end

function BuyDialogHandler:SetTargets()
    local frame = self.frame
    self.targets = {
        [frame.BuyNowButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            up = false, down = false,
            left = frame.CancelButton, right = frame.CancelButton},
        [frame.CancelButton] = {
            can_activate = true, lock_highlight = true,
            up = false, down = false,
            left = frame.BuyNowButton, right = frame.BuyNowButton},
    }
end


-------- Sell tab (FIXME: not yet implemented)

function SellTabHandler:__constructor()
    self:__super(AuctionHouseFrame.ItemSellFrame)
    self.cancel_func = AuctionHouseFrameHandler.CancelMenu
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
end


-------- Auctions list tab (FIXME: not yet implemented)

function AuctionsTabHandler:__constructor()
    self:__super(AuctionHouseFrameAuctionsFrame)
    self.cancel_func = AuctionHouseFrameHandler.CancelMenu
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
end
