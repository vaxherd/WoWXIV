local module_name, WoWXIV = ...

local class = WoWXIV.class
local strfind = string.find
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local tinsert = tinsert

local FCT = function(...)
    FCT = WoWXIV.FormatColoredText
    return FCT(...)
end
local function Red(s)    return FCT(s, RED_FONT_COLOR:GetRGB())        end
local function Yellow(s) return FCT(s, YELLOW_FONT_COLOR:GetRGB())     end
local function Green(s)  return FCT(s, GREEN_FONT_COLOR:GetRGB())      end
local function Blue(s)   return FCT(s, BRIGHTBLUE_FONT_COLOR:GetRGB()) end


-- Maximum number of results to return in a single call.
local MAX_RESULTS = 20

-- Saved global for caching bank contents across sessions.
WoWXIV_isearch_cache = WoWXIV_isearch_cache or {}

-- Local flags indicating which cached bags are known to be up to date.
-- Only used if the cache is non-null (thus this need not be cleared when
-- clearing a bag's cache).
local isearch_cache_uptodate = {}

--------------------------------------------------------------------------
-- Helper routines
--------------------------------------------------------------------------

-- Returns the stack count of an inventory slot specified by item location,
-- or 0 if unknown.  If the slot contains a single item with multiple
-- charges, the negative of the charge count is returned.  If the
-- container item info is already available, pass it in |info|.
local function GetItemCountOrCharges(loc, info)
    local link = C_Item.GetItemLink(loc)
    local count
    if loc:IsBagAndSlot() then
        info = info or C_Container.GetContainerItemInfo(loc:GetBagAndSlot())
        count = info and info.stackCount or 0
    else
        count = C_Item.GetItemCount(link)
    end
    if count == 1 then
        local charges = C_Item.GetItemCount(link, false, true)
        -- FIXME: is there any way to programmatically check whether an
        -- item is a charge-counted item? (so we can report "1 charge"
        -- if this returns 1)
        if charges > 1 then
            count = -charges
        end
    end
    return count
end

--------------------------------------------------------------------------
-- Container getter interface
--------------------------------------------------------------------------

-- Generic interface for obtaining a container's contents.

local ContainerGetter = class()

-- Constructor.  Pass the C_Container bag ID (an Enum.BagIndex value).
function ContainerGetter:__constructor(bag_id)
    self.bag_id = bag_id
end

-- Returns the name of the container, for use in /itemsearch results.
function ContainerGetter:Name()
    return ""
end

-- Returns the size (number of slots) of the container, or 0 if the
-- container is unavailable.  During any given game update cycle, if
-- Contents() returns a table, the table will contain exactly this number
-- of elements, with keys numbered consecutively from 1.
function ContainerGetter:Size()
    return C_Container.GetContainerNumSlots(self.bag_id) or 0
end

-- Returns a list {item ID, count, link} for a single slot in the container,
-- or nil if there is no item in the slot (or the slot index is invalid).
-- The count value is 1 for a single item, >1 for a stack of items, or
-- <0 for a single item with charges (the charge count is the negative of
-- the value); 0 indicates that the stack or charge count is unavailable.
function ContainerGetter:Item(slot)
    local info = C_Container.GetContainerItemInfo(self.bag_id, slot)
    if info then
        local loc = ItemLocation:CreateFromBagAndSlot(self.bag_id, slot)
        return {info.itemID, GetItemCountOrCharges(loc, info), info.hyperlink}
    else
        return nil
    end
end

-- Returns the content of all slots in a container in a table, or nil if
-- the container is unavailable.  Each entry in the table is either the
-- item in that slot (as returned by Item()) or nil for an empty slot.
-- Implementations will typically not need to override this method.
function ContainerGetter:Contents()
    local size = self:Size()
    if size > 0 then
        local contents = {}
        for slot = 1, size do
            contents[slot] = self:Item(slot)
        end
        return contents
    else
        return nil
    end
end

-- Returns the name/size/contents of a container in a single function call.
-- Convenience wrapper for calling :Name(), :Size(), and :Contents().
function ContainerGetter:Get()
    return self:Name(), self:Size(), self:Contents()
end

-- Returns the bag ID for use in WoW API C_Container calls, or nil if none.
function ContainerGetter:BagID()
    return self.bag_id
end


-- Getter for inventory bags.
local BagGetter = class(ContainerGetter)
function BagGetter:__constructor(bag_id, name, append_bagname)
    __super(self, bag_id)
    self.name = name
    self.append_bagname = append_bagname
end
function BagGetter:Name()
    local name = self.name
    if self.append_bagname then
        local item_name = C_Container.GetBagName(self.bag_id)
        name = name .. " (" .. (item_name or "???") .. ")"
    end
    return name
end


-- Getter for bank tabs.
local BankTabGetter = class(ContainerGetter)
function BankTabGetter:__constructor(bank_type, tab_index, name)
    local bag_id_base
    if bank_type == Enum.BankType.Character then
        bag_id_base = Enum.BagIndex.CharacterBankTab_1
    else
        assert(bank_type == Enum.BankType.Account)
        bag_id_base = Enum.BagIndex.AccountBankTab_1
    end
    __super(self, bag_id_base + (tab_index - 1))
    self.bank_type = bank_type
    self.name = name
end
function BankTabGetter:Name()
    local name = self.name
    local tab_name = "???"
    local data = C_Bank.FetchPurchasedBankTabData(self.bank_type)
    if data then
        for _, tab_info in ipairs(data) do
            if tab_info.ID == self.bag_id then
                tab_name = tab_info.name
                break
            end
        end
    end
    return name .. " (" .. tab_name .. ")"
end

--------------------------------------------------------------------------
-- Other local data and utility routines
--------------------------------------------------------------------------

-- WoW provides the C_Container.GetBagName() API to get the bag item name
-- for a bag slot, but (1) that doesn't let us differentiate between
-- multiple bags of the same name and (2) it doesn't work for bank tabs,
-- so we use our own names here (but still append the bag item name for
-- player-created bags).
local function BAGDEF(getter, cache_id, in_combined)
    return {getter = getter, cache_id = cache_id, in_combined = in_combined}
end
local BAGS = {
    BAGDEF(BagGetter(Enum.BagIndex.Backpack, "Backpack", false), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_1, "Bag 1", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_2, "Bag 2", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_3, "Bag 3", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_4, "Bag 4", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.ReagentBag, "Reagent Bag", false)),
    BAGDEF(BankTabGetter(Enum.BankType.Character, 1, "Bank Tab 1"), "bank1"),
    BAGDEF(BankTabGetter(Enum.BankType.Character, 2, "Bank Tab 2"), "bank2"),
    BAGDEF(BankTabGetter(Enum.BankType.Character, 3, "Bank Tab 3"), "bank3"),
    BAGDEF(BankTabGetter(Enum.BankType.Character, 4, "Bank Tab 4"), "bank4"),
    BAGDEF(BankTabGetter(Enum.BankType.Character, 5, "Bank Tab 5"), "bank5"),
    BAGDEF(BankTabGetter(Enum.BankType.Character, 6, "Bank Tab 6"), "bank6"),
    BAGDEF(BankTabGetter(Enum.BankType.Account, 1, "Warband Bank Tab 1"), "warbank1"),
    BAGDEF(BankTabGetter(Enum.BankType.Account, 2, "Warband Bank Tab 2"), "warbank2"),
    BAGDEF(BankTabGetter(Enum.BankType.Account, 3, "Warband Bank Tab 3"), "warbank3"),
    BAGDEF(BankTabGetter(Enum.BankType.Account, 4, "Warband Bank Tab 4"), "warbank4"),
    BAGDEF(BankTabGetter(Enum.BankType.Account, 5, "Warband Bank Tab 5"), "warbank5"),
}

-- For equipment, names are available as global constants, but again they
-- don't provide a way to distinguish between multiple slots of the same type.
local function EQUIPDEF(id, name)
    return {id = id, name = name}
end
local EQUIPS = {
    EQUIPDEF("HEADSLOT", "Head"),
    EQUIPDEF("NECKSLOT", "Neck"),
    EQUIPDEF("SHOULDERSLOT", "Shoulders"),
    EQUIPDEF("BACKSLOT", "Back"),
    EQUIPDEF("CHESTSLOT", "Chest"),
    EQUIPDEF("SHIRTSLOT", "Shirt"),
    EQUIPDEF("TABARDSLOT", "Tabard"),
    EQUIPDEF("WRISTSLOT", "Wrists"),
    EQUIPDEF("HANDSSLOT", "Hands"),
    EQUIPDEF("WAISTSLOT", "Waist"),
    EQUIPDEF("LEGSSLOT", "Legs"),
    EQUIPDEF("FEETSLOT", "Feet"),
    EQUIPDEF("FINGER0SLOT", "Finger 1"),
    EQUIPDEF("FINGER1SLOT", "Finger 2"),
    EQUIPDEF("TRINKET0SLOT", "Trinket 1"),
    EQUIPDEF("TRINKET1SLOT", "Trinket 2"),
    EQUIPDEF("MAINHANDSLOT", "Main Hand"),
    EQUIPDEF("SECONDARYHANDSLOT", "Off Hand"),
    EQUIPDEF("PROF0TOOLSLOT", "Profession 1 Tool"),
    EQUIPDEF("PROF0GEAR0SLOT", "Profession 1 Accessory 1"),
    EQUIPDEF("PROF0GEAR1SLOT", "Profession 1 Accessory 2"),
    EQUIPDEF("PROF1TOOLSLOT", "Profession 2 Tool"),
    EQUIPDEF("PROF1GEAR0SLOT", "Profession 2 Accessory 1"),
    EQUIPDEF("PROF1GEAR1SLOT", "Profession 2 Accessory 2"),
    EQUIPDEF("COOKINGTOOLSLOT", "Cooking Tool"),
    EQUIPDEF("COOKINGGEAR0SLOT", "Cooking Accessory"),
    EQUIPDEF("FISHINGTOOLSLOT", "Fishing Rod"),
    EQUIPDEF("FISHINGGEAR0SLOT", "Fishing Accessory 1"),
    EQUIPDEF("FISHINGGEAR1SLOT", "Fishing Accessory 2"),
}

local function NameIsMatch(name, search_key)
    return name and strstr(name:lower(), search_key)
end

local function SlotString(slot_count)
    local slot, count = unpack(slot_count)
    if count > 1 then
        return slot .. " (×" .. count .. ")"
    elseif count <= 0 then
        local charges = -count
        local s = charges==1 and "charge" or "charges"
         return slot .. " (" .. charges .. " " .. s .. ")"
    else
        return "" .. slot  -- Force to string for consistency.
    end
end

local function SlotsString(slots)
    local s
    if #slots == 1 then
        s = " slot " .. SlotString(slots[1])
    else
        s = " slots " .. SlotString(slots[1])
        if #slots == 2 then
            s = s .. " and " .. SlotString(slots[2])
        else
            for i = 2, #slots-1 do
                s = s .. ", " .. SlotString(slots[i])
            end
            s = s .. ", and " .. SlotString(slots[#slots])
        end
    end
    return s
end

--------------------------------------------------------------------------
-- Asynchronous event handler
--------------------------------------------------------------------------

local isearch_event_frame = CreateFrame("Frame", "WoWXIV_IsearchEventFrame")
function isearch_event_frame:OnEvent(event, ...)
    if self[event] then self[event](self, ...) end
end
isearch_event_frame:SetScript("OnEvent", isearch_event_frame.OnEvent)

-- FIXME: surely there must be a way to get the combined state directly
-- rather than this hack of listening for changes (which doesn't work on
-- module load anyway)?
local is_combined_bags = false
isearch_event_frame:RegisterEvent("USE_COMBINED_BAGS_CHANGED")
function isearch_event_frame:USE_COMBINED_BAGS_CHANGED(enabled)
    is_combined_bags = enabled
end

isearch_event_frame:RegisterEvent("BAG_UPDATE")
function isearch_event_frame:BAG_UPDATE(bag_id)
    for _, bag in ipairs(BAGS) do
        local cache_id = bag.cache_id
        if cache_id and bag.getter:BagID() == bag_id then
            local bag_name, size, content = bag.getter:Get()
            if size > 0 then
                WoWXIV_isearch_cache[cache_id] = content
                WoWXIV_isearch_cache[cache_id .. "_size"] = size
                -- Special case to deal with account bank bag names not
                -- being available when this event fires due to crafting
                -- with reagents in the account bank.
                if (WoWXIV_isearch_cache[cache_id .. "_name"]
                    and not (cache_id:sub(1,7) == "warbank" and bag_name:sub(-5) == "(???)"))
                then
                    WoWXIV_isearch_cache[cache_id .. "_name"] = bag_name
                end
                isearch_cache_uptodate[cache_id] = true
            elseif self.bankframe_open then
                -- In all cases in which this event fires, a size of 0
                -- definitively indicates that no such bag exists.
                WoWXIV_isearch_cache[cache_id] = nil
                WoWXIV_isearch_cache[cache_id .. "_size"] = nil
                WoWXIV_isearch_cache[cache_id .. "_name"] = nil
            end
        end
    end
end

isearch_event_frame:RegisterEvent("BANKFRAME_OPENED")
function isearch_event_frame:BANKFRAME_OPENED()
    self.bankframe_open = true
    for _, bag in ipairs(BAGS) do
        local cache_id = bag.cache_id
        if cache_id and strstr(cache_id, "bank") then
            local bag_name, size, content = bag.getter:Get()
            if size > 0 then
                WoWXIV_isearch_cache[cache_id] = content
                WoWXIV_isearch_cache[cache_id .. "_size"] = size
                WoWXIV_isearch_cache[cache_id .. "_name"] = bag_name
                isearch_cache_uptodate[cache_id] = true
            else
                WoWXIV_isearch_cache[cache_id] = nil
                WoWXIV_isearch_cache[cache_id .. "_size"] = nil
                WoWXIV_isearch_cache[cache_id .. "_name"] = nil
            end
        end
    end
end

isearch_event_frame:RegisterEvent("BANKFRAME_CLOSED")
function isearch_event_frame:BANKFRAME_CLOSED()
    self.bankframe_open = false
end

isearch_event_frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
function isearch_event_frame:PLAYERBANKSLOTS_CHANGED(slot)
    self:BAG_UPDATE(Enum.BagIndex.Bank)
end


isearch_event_frame:RegisterEvent("ADDON_LOADED")
function isearch_event_frame:ADDON_LOADED(name)
    if name == module_name then
        if WoWXIV_isearch_cache.bank0 then
            -- Delete cache data from pre-11.2.0 bank bags and void storage.
            local tags = {"bank0", "bank1", "bank2", "bank3", "bank4", "bank5",
                          "bank6", "bank7", "bankR", "void1", "void2"}
            for _, tag in ipairs(tags) do
                WoWXIV_isearch_cache[tag] = nil
                WoWXIV_isearch_cache[tag.."_name"] = nil
                WoWXIV_isearch_cache[tag.."_size"] = nil
            end
        end
    end
end

--------------------------------------------------------------------------
-- /itemsearch implementation
--------------------------------------------------------------------------

function WoWXIV.isearch(arg)
    if not arg or arg == "" then
        print(Red("No item name given. Try \"/? itemsearch\" for help."))
        return
    end

    print("Searching for " .. Yellow(arg))
    search_key = arg:lower()

    local results = {}
    local used_cache = false

    if is_combined_bags then
        local found_slots = {}
        local offset = 0
        for i = #BAGS, 1, -1 do
            local bag = BAGS[i]
            if bag.in_combined then
                local bag_size = C_Container.GetContainerNumSlots(bag.id)
                for slot = 1, bag_size do
                    local loc = ItemLocation:CreateFromBagAndSlot(bag.id, slot)
                    if loc and loc:IsValid() then
                        local name = C_Item.GetItemName(loc)
                        if NameIsMatch(name, search_key) then
                            local link = C_Item.GetItemLink(loc)
                            local count = GetItemCountOrCharges(loc)
                            found_slots[link] = found_slots[link] or {}
                            tinsert(found_slots[link], {offset + slot, count})
                        end
                    end
                end
                offset = offset + bag_size
            end
        end
        -- Careful here: the "#" operator only works on lists, i.e.
        -- tables whose keys are consecutive integers starting at 1.
        -- Lua doesn't seem to have a direct way to test an arbitrary
        -- table for emptiness, but next() will do the trick.
        -- Lua really is not a great language, but it's what we've got...
        if next(found_slots, nil) then
            for item, slots in pairs(found_slots) do
                local s = SlotsString(slots)
                tinsert(results, {item, " found in " .. Blue("Combined Backpack" .. s)})
            end
        end
    end

    for _, bag in ipairs(BAGS) do
        if not (is_combined_bags and bag.in_combined) then
            local bag_name, size, content = bag.getter:Get()
            local cache_id = bag.cache_id
            local is_cached = false
            local found_slots = {}
            -- If not at a bank, we can still look up reagent bank item IDs
            -- but not individual stack counts per slot, so treat that as
            -- unavailable data.
            if size > 0 then
                for slot = 1, size do
                    local data = content[slot]
                    if data and data[2] == 0 then
                        size = 0
                        break
                    end
                end
            end
            if size > 0 then
                if cache_id then
                    WoWXIV_isearch_cache[cache_id] = content
                    WoWXIV_isearch_cache[cache_id .. "_size"] = size
                    WoWXIV_isearch_cache[cache_id .. "_name"] = bag_name
                    isearch_cache_uptodate[cache_id] = true
                end
            elseif cache_id then
                local cached_size = WoWXIV_isearch_cache[bag.cache_id .. "_size"]
                if cached_size then
                    size = cached_size
                    content = WoWXIV_isearch_cache[bag.cache_id]
                    bag_name = WoWXIV_isearch_cache[bag.cache_id .. "_name"]
                    is_cached = not isearch_cache_uptodate[cache_id]
                end
            end
            if content then
                for slot = 1, size do
                    local data = content[slot]
                    if data then
                        local item, count, link = unpack(data)
                        local name = item and C_Item.GetItemInfo(item)
                        if NameIsMatch(name, search_key) then
                            found_slots[link] = found_slots[link] or {}
                            tinsert(found_slots[link], {slot, count})
                            used_cache = used_cache or is_cached
                        end
                    end
                end
            end
            if next(found_slots, nil) then
                for item, slots in pairs(found_slots) do
                    local s = SlotsString(slots)
                    tinsert(results, {item, " found in " .. Blue(bag_name .. s)})
                end
            end
        end
    end

    for _, slot in ipairs(EQUIPS) do
        local slot_info = GetInventorySlotInfo(slot.id)
        assert(slot_info)
        local loc = ItemLocation:CreateFromEquipmentSlot(slot_info)
        if loc and loc:IsValid() then
            local name = C_Item.GetItemName(loc)
            if NameIsMatch(name, search_key) then
                local link = C_Item.GetItemLink(loc)
                tinsert(results, {link, " equipped on " .. Blue(slot.name)})
            end
        end
    end

    if #results > 0 then
        -- Lua apparently does not have a stable sort method, so we have
        -- to ensure stability manually.
        for i, v in ipairs(results) do
            tinsert(v, i)
        end
        table.sort(results, function(a,b) return a[1] < b[1] or (a[1] == b[1] and a[#a] < b[#b]) end)
        local count = 0
        for _, result in ipairs(results) do
            if count >= MAX_RESULTS then
                print(Red("More than "..MAX_RESULTS.." results, stopping here."))
                break
            end
            local namelink, location = unpack(result)
            print(" → " .. namelink .. location)
            count = count + 1
        end
        if used_cache then
            print(Red("Some results may be out of date. Visit the appropriate storage NPC to ensure current results."))
        end
    else
        print(Red(" → No matching items found."))
    end
end
