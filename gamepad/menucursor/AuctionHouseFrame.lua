local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local MenuFrame = MenuCursor.MenuFrame
local StandardMenuFrame = MenuCursor.StandardMenuFrame

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local cache_SellDurationDropdown = {}

local AuctionHouseFrameHandler = class(MenuFrame)
MenuCursor.AuctionHouseFrameHandler = AuctionHouseFrameHandler  -- For exports.
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
    self.has_Button4 = true  -- Used to toggle favorites on and off.
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
    -- Clear the target now to call the OnLeave handler and thus clear the
    -- row highlight; otherwise, next time we return to the frame without a
    -- list refresh (such as after buying an item), scrolling the current
    -- item to the center of the frame will leave a highlight on the item's
    -- previous row.
    self:ClearTarget()
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
    if initial and not self:GetTargetFrame(initial) then
        ItemScroll:ScrollToElementDataIndex(initial.index)
    end
    return initial or top or SearchBar.FavoritesSearchButton
end

function BuyTabHandler:OnAction(button)
    assert(button == "Button4")
    local target = self:GetTarget()
    if target and self.targets[target].is_scroll_box then
        local button = self:GetTargetFrame(target)
        assert(button.cells)
        assert(button.cells[4])
        local favorite = button.cells[4].FavoriteButton
        assert(favorite)
        favorite:GetScript("OnClick")(favorite, "LeftButton", true)
    end
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
    self.has_Button3 = true  -- Used to trigger an item list refresh.
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    self:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
end

function ItemBuyFrameHandler:ITEM_SEARCH_RESULTS_UPDATED()
    if not self.frame:IsShown() then return end  -- suppress when selling
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

function ItemBuyFrameHandler:OnAction(button)
    assert(button == "Button3")
    local button = self.frame.ItemList.RefreshFrame.RefreshButton
    button:GetScript("OnClick")(button, "LeftButton", true)
end


-------- Purchase window (commodities)

function CommoditiesBuyFrameHandler:__constructor()
    self:__super(AuctionHouseFrame.CommoditiesBuyFrame)
    self.cancel_func = nil
    self.cancel_button = self.frame.BackButton
    self.has_Button3 = true  -- Used to trigger an auction list refresh.
    self.on_prev_page = function(dir) self:AdjustQuantity(dir) end
    self.on_next_page = self.on_prev_page
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
    local InputBox = self.frame.BuyDisplay.QuantityInput.InputBox
    self.quantity_input = MenuCursor.NumberInput(
        InputBox, function() self:OnQuantityChanged() end)
end

function CommoditiesBuyFrameHandler:OnHide()
    self.quantity_input:CancelEdit()
    StandardMenuFrame.OnHide(self)
end

function CommoditiesBuyFrameHandler:SetTargets()
    local BackButton = self.frame.BackButton
    local RefreshButton = self.frame.ItemList.RefreshFrame.RefreshButton
    local BuyDisplay = self.frame.BuyDisplay
    local ItemButton = BuyDisplay.ItemDisplay.ItemButton
    local InputBox = BuyDisplay.QuantityInput.InputBox
    local BuyButton = BuyDisplay.BuyButton
    local function ClickBuyButton()
        -- Work around Blizzard bug which can leave the quantity field empty.
        if InputBox:GetText() == "" then
            InputBox:SetText("1")
            self:OnQuantityChanged()
        end
        BuyButton:Click()
    end
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
        [InputBox] = {on_click = function() self:EditQuantity() end,
                      up = ItemButton, down = BuyButton,
                      left = false, right = false, is_default = true},
        [BuyButton] = {on_click = ClickBuyButton, lock_highlight = true,
                       up = InputBox, down = BackButton,
                       left = false, right = false},
    }
end

function CommoditiesBuyFrameHandler:GetMaxQuantity()
    local item = self.frame.BuyDisplay:GetItemID()
    return item and AuctionHouseUtil.AggregateSearchResultsByQuantity(item, math.huge)
end

function CommoditiesBuyFrameHandler:AdjustQuantity(amount)
    local InputBox = self.frame.BuyDisplay.QuantityInput.InputBox
    if self:GetTarget() == InputBox then
        local limit = self:GetMaxQuantity()
        if limit and limit > 0 then
            local value = tonumber(InputBox:GetText())
            if not value then
                value = 1
            else
                value = value + amount
                if value < 1 then value = 1 end
                if value > limit then value = limit end
            end
            InputBox:SetText(tostring(value))
            self:OnQuantityChanged()
        end
    end
end

function CommoditiesBuyFrameHandler:EditQuantity()
    local limit = self:GetMaxQuantity()
    if limit and limit > 0 then
        self.quantity_input:Edit(1, limit)
    end
end

function CommoditiesBuyFrameHandler:OnQuantityChanged()
    local InputBox = self.frame.BuyDisplay.QuantityInput.InputBox
    local callback = InputBox:GetInputChangedCallback()
    if callback then callback() end
end

function CommoditiesBuyFrameHandler:OnAction(button)
    assert(button == "Button3")
    local button = self.frame.ItemList.RefreshFrame.RefreshButton
    button:GetScript("OnClick")(button, "LeftButton", true)
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


-------- Sell tab

function SellTabHandler:__constructor()
    -- The sell tab is implemented as two separate but basically identical
    -- frames, ItemSellFrame and CommoditiesSellFrame.  Rather than
    -- implementing separate handlers for each, we just use a single
    -- handler and swap self.frame to whichever one happens to be shown
    -- at the moment.
    self:__super(nil)
    self:HookShow(AuctionHouseFrame.ItemSellFrame)
    self:HookShow(AuctionHouseFrame.CommoditiesSellFrame)
    self:HookShow(AuctionHouseFrame.CommoditiesSellFrame.QuantityInput,
                  self.RefreshTargets, self.RefreshTargets)

    self.cancel_func = AuctionHouseFrameHandler.CancelMenu
    self.has_Button3 = true  -- Used to trigger an auction list refresh.
    self.on_prev_page = function(dir) self:AdjustNumber(dir) end
    self.on_next_page = self.on_prev_page
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
    self.quantity_input = MenuCursor.NumberInput(  -- Commodities frame only.
        AuctionHouseFrame.CommoditiesSellFrame.QuantityInput.InputBox,
        function() self:OnQuantityChanged() end)
    -- We unfortunately need separate copies of this for each version of
    -- the frame... sigh.
    self.gold_input_i = MenuCursor.NumberInput(
        AuctionHouseFrame.ItemSellFrame.PriceInput.MoneyInputFrame.GoldBox,
        function() self:OnPriceChanged() end)
    self.silver_input_i = MenuCursor.NumberInput(
        AuctionHouseFrame.ItemSellFrame.PriceInput.MoneyInputFrame.SilverBox,
        function() self:OnPriceChanged() end)
    self.gold_input_c = MenuCursor.NumberInput(
        AuctionHouseFrame.CommoditiesSellFrame.PriceInput.MoneyInputFrame.GoldBox,
        function() self:OnPriceChanged() end)
    self.silver_input_c = MenuCursor.NumberInput(
        AuctionHouseFrame.CommoditiesSellFrame.PriceInput.MoneyInputFrame.SilverBox,
        function() self:OnPriceChanged() end)
end

function SellTabHandler:OnShow(frame)
    self:ClearTarget()
    self.frame = frame
    StandardMenuFrame.OnShow(self)
end

function SellTabHandler:OnHide(frame)
    self.quantity_input:CancelEdit()
    self.gold_input_i:CancelEdit()
    self.silver_input_i:CancelEdit()
    self.gold_input_c:CancelEdit()
    self.silver_input_c:CancelEdit()
    StandardMenuFrame.OnHide(self)
end

function SellTabHandler:RefreshTargets()
    if not self.frame or not self.frame:IsShown() then return end
    local target = self:GetTarget()
    self:ClearTarget()
    self:SetTargets()
    if not self.targets[target] then target = self:GetDefaultTarget() end
    self:SetTarget(target)
end

function SellTabHandler:SetTargets()
    local qi = self.frame.QuantityInput
    local pi = self.frame.PriceInput
    local QuantityBox = qi.InputBox
    local MaxButton = qi.MaxButton
    local GoldBox = pi.MoneyInputFrame.GoldBox
    local SilverBox = pi.MoneyInputFrame.SilverBox
    local Duration = self.frame.Duration.Dropdown
    local PostButton = self.frame.PostButton
    -- Buyout mode button skipped because I'd never use it (and supporting
    -- it means having to add support for the extra fields it needs).

    self.targets = {
        [GoldBox] = {on_click = function() self:EditGold() end,
                     up = PostButton, down = Duration,
                     left = SilverBox, right = SilverBox},
        [SilverBox] = {on_click = function() self:EditSilver() end,
                       up = PostButton, down = Duration,
                       left = GoldBox, right = GoldBox},
        [Duration] = {on_click = function() self:ToggleDurationDropdown() end,
                      lock_highlight = true, up = GoldBox, down = PostButton,
                      left = false, right = false},
        [PostButton] = {can_activate = true, lock_highlight = true,
                        up = Duration, down = GoldBox,
                        left = false, right = false, is_default = true},
    }
    if QuantityBox:IsVisible() then
        self.targets[QuantityBox] = {
            on_click = function() self:EditQuantity() end,
            up = PostButton, down = GoldBox,
            left = MaxButton, right = MaxButton}
        self.targets[MaxButton] = {
            can_activate = true, lock_highlight = true,
            up = PostButton, down = SilverBox,
            left = QuantityBox, right = QuantityBox}
        self.targets[GoldBox].up = QuantityBox
        self.targets[SilverBox].up = MaxButton
        self.targets[PostButton].down = QuantityBox
    end
end

function SellTabHandler:ToggleDurationDropdown()
    local dropdown = self.frame.Duration.Dropdown
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local menu, initial_target = self.SetupDropdownMenu(
            dropdown, cache_SellDurationDropdown,
            function(selection) return selection.data end)
        menu:Enable(initial_target)
    end
end

function SellTabHandler:GetMaxQuantity()
    return AuctionHouseFrame.CommoditiesSellFrame:GetMaxQuantity()
end

function SellTabHandler:AdjustNumber(amount)
    local target = self:GetTarget()
    local limit
    local qi = self.frame.QuantityInput
    local pi = self.frame.PriceInput
    if target == pi.MoneyInputFrame.GoldBox then
        limit = 9999999
    elseif target == pi.MoneyInputFrame.SilverBox then
        limit = 99
    elseif qi and target == qi.InputBox then
        limit = self:GetMaxQuantity()
    else
        return
    end
    local value = tonumber(target:GetText())
    if not value then
        value = 0
    else
        value = value + amount
        if value < 0 then value = 0 end
        if value > limit then value = limit end
    end
    target:SetText(tostring(value))
    if qi and target == qi.InputBox then
        self:OnQuantityChanged()
    else
        self:OnPriceChanged()
    end
end

function SellTabHandler:EditGold()
    local gold_input = (self.frame==AuctionHouseFrame.ItemSellFrame
                        and self.gold_input_i or self.gold_input_c)
    gold_input:Edit(0, 9999999)
end

function SellTabHandler:EditSilver()
    local silver_input = (self.frame==AuctionHouseFrame.ItemSellFrame
                          and self.silver_input_i or self.silver_input_c)
    silver_input:Edit(0, 99)
end

function SellTabHandler:OnPriceChanged()
    -- We can pass either GoldBox or SilverBox here; the function just
    -- takes the parent (MoneyInputFrame) and works with that.
    MoneyInputFrame_OnTextChanged(self.frame.PriceInput.MoneyInputFrame.GoldBox)
end

function SellTabHandler:EditQuantity()
    local limit = self:GetMaxQuantity()
    if limit and limit > 0 then
        self.quantity_input:Edit(1, limit)
    end
end

function SellTabHandler:OnQuantityChanged()
    local InputBox = self.frame.QuantityInput.InputBox
    local callback = InputBox:GetInputChangedCallback()
    if callback then callback() end
end

function SellTabHandler:OnAction(button)
    assert(button == "Button3")
    local button = self.frame.RefreshFrame.RefreshButton
    button:GetScript("OnClick")(button, "LeftButton", true)
end


-------- Auctions list tab

function AuctionsTabHandler:__constructor()
    self:__super(AuctionHouseFrameAuctionsFrame)
    self.cancel_func = AuctionHouseFrameHandler.CancelMenu
    self.has_Button3 = true  -- Used to trigger an auction list refresh.
    self.tab_handler = AuctionHouseFrameHandler.instance.tab_handler
    self:RegisterEvent("OWNED_AUCTIONS_UPDATED")
end

function AuctionsTabHandler:OWNED_AUCTIONS_UPDATED()
    local target = self:GetTarget()
    if target and self.targets[target].is_scroll_box then
        local index = target.index
        local info = index and C_AuctionHouse.GetOwnedAuctionInfo(index)
        target = info and info.auctionID
    end
    self:ClearTarget()
    self:SetTarget(self:RefreshTargets(target))
end

function AuctionsTabHandler:SetTargets()
    return self:RefreshTargets()
end

function AuctionsTabHandler:RefreshTargets(last_target)
    local frame = self.frame
    local CancelAuctionButton = frame.CancelAuctionButton
    self.targets = {
        [CancelAuctionButton] = {can_activate = true, lock_highlight = true,
                                 up = false, down = false,
                                 left = false, right = false},
    }
    local function OnClickItem(target)
        local button = self:GetTargetFrame(target)
        button:GetScript("OnClick")(button, "LeftButton", true)
        self:SetTarget(CancelAuctionButton)
    end
    local ItemScroll = frame.AllAuctionsList.ScrollBox
    local function ForEachItem(callback)
        for _, index in ItemScroll:GetDataProvider():EnumerateEntireRange() do
            local element = C_AuctionHouse.GetOwnedAuctionInfo(index)
            if element then
                callback(element)
            end
        end
    end
    local function AddTarget(elementdata, index)
        local attributes = {on_click = OnClickItem, send_enter_leave = true,
                            left = false, right = false}
        return attributes, elementdata.auctionID == last_target
    end
    local top, bottom, initial =
        self:AddScrollBoxTargets(ItemScroll, AddTarget, ForEachItem)
    if top then
        self.targets[top].up = CancelAuctionButton
        self.targets[bottom].down = CancelAuctionButton
    end
    self.targets[CancelAuctionButton].down = top or false
    self.targets[CancelAuctionButton].up = bottom or false
    return (initial
            or top
            or (last_target and self.targets[last_target] and last_target)
            or CancelAuctionButton)
end

function AuctionsTabHandler:OnAction(button)
    assert(button == "Button3")
    local button = self.frame.AllAuctionsList.RefreshFrame.RefreshButton
    button:GetScript("OnClick")(button, "LeftButton", true)
end

---------------------------------------------------------------------------

-- Exported function, called by ContainerFrame.  Focuses whichever sell
-- frame is visible, if any.
function AuctionHouseFrameHandler.FocusSellFrame()
    local frames = {AuctionHouseFrame.ItemSellFrame,
                    AuctionHouseFrame.CommoditiesSellFrame}
    for _, frame in ipairs(frames) do
        if frame:IsVisible() then
            AuctionHouseFrameHandler.instance_SellTab:OnShow(frame)
            return
        end
    end
end
