local module_name, WoWXIV = ...

local class = WoWXIV.class
local strsub = string.sub
local tinsert = tinsert

local FCT = function(...)
    FCT = WoWXIV.FormatColoredText
    return FCT(...)
end
local function Red(s)    return FCT(s, RED_FONT_COLOR:GetRGB())        end
local function Yellow(s) return FCT(s, YELLOW_FONT_COLOR:GetRGB())     end
local function Green(s)  return FCT(s, GREEN_FONT_COLOR:GetRGB())      end
local function Blue(s)   return FCT(s, BRIGHTBLUE_FONT_COLOR:GetRGB()) end

-- Void storage constants which don't seem to be available via the API.
local VOID_MAX_TABS = 2
local VOID_MAX_SLOTS = 80  -- per tab


-- Saved global for caching bank contents across sessions.
WoWXIV_isearch_cache = WoWXIV_isearch_cache or {}

-- Local flags indicating which cached bags are known to be up to date.
local isearch_cache_uptodate = {}

--------------------------------------------------------------------------
-- Container getter interface
--------------------------------------------------------------------------

-- Generic interface for obtaining a container's contents.

local ContainerGetter = class()

-- Returns the name of the container, for use in /itemsearch results.
function ContainerGetter:Name()
    return ""
end

-- Returns the size (number of slots) of the container, or 0 if the
-- container is unavailable.  During any given game update cycle, if
-- Contents() returns a table, the table will contain exactly this number
-- of elements, with keys numbered consecutively from 1.
function ContainerGetter:Size()
    return 0
end

-- Returns the item ID of a single slot in the container, or nil if there
-- is no item in the slot (or the slot index is invalid).
function ContainerGetter:Item(slot)
    return nil
end

-- Returns the content of all slots in a container in a table (each element
-- is the item ID of the item in that slot, nil if the slot is empty), or
-- nil if the container is unavailable.  Implementations will typically not
-- need to override this method.
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
    return nil
end


-- Getter for inventory and bank bags.
local BagGetter = class(ContainerGetter)
function BagGetter:__constructor(bag_id, name, append_bagname)
    self.id = bag_id
    self.name = name
    self.append_bagname = append_bagname
end
function BagGetter:Name()
    local name = self.name
    if self.append_bagname then
        local item_name = C_Container.GetBagName(self.id)
        name = name .. " (" .. (item_name or "???") .. ")"
    end
    return name
end
function BagGetter:Size()
    return C_Container.GetContainerNumSlots(self.id) or 0
end
function BagGetter:Item(slot)
    local loc = ItemLocation:CreateFromBagAndSlot(self.id, slot)
    if loc and loc:IsValid() then
        return C_Item.GetItemID(loc)
    else
        return nil
    end
end
function BagGetter:BagID()
    return self.id
end


-- Getter for void storage tabs.
local VoidGetter = class(ContainerGetter)
function VoidGetter:__constructor(tab_index)
    self.tab = tab_index
end
function VoidGetter:Name()
    return "Void Storage tab " .. self.tab
end
function VoidGetter:Size()
    return IsVoidStorageReady() and VOID_MAX_SLOTS or 0
end
function VoidGetter:Item(slot)
    return GetVoidItemInfo(self.tab, slot)
end

--------------------------------------------------------------------------
-- Other local data and utility routines
--------------------------------------------------------------------------

-- WoW provides the C_Container.GetBagName() API to get the bag item name
-- for a bag slot, but (1) that doesn't let us differentiate between
-- multiple bags of the same name and (2) it doesn't work for special bags
-- like the main bank bag, so we use our own names here (but still append
-- the bag item name for player-created bags).
function BAGDEF(getter, cache_id, in_combined)
    return {getter = getter, cache_id = cache_id, in_combined = in_combined}
end
local BAGS = {
    BAGDEF(BagGetter(Enum.BagIndex.Backpack, "Backpack", false), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_1, "Bag 1", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_2, "Bag 2", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_3, "Bag 3", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.Bag_4, "Bag 4", true), nil, true),
    BAGDEF(BagGetter(Enum.BagIndex.ReagentBag, "Reagent Bag", false)),
    BAGDEF(BagGetter(Enum.BagIndex.Bank, "Bank", false), "bank0"),
    BAGDEF(BagGetter(Enum.BagIndex.BankBag_1, "Bank Bag 1", true), "bank1"),
    BAGDEF(BagGetter(Enum.BagIndex.BankBag_2, "Bank Bag 2", true), "bank2"),
    BAGDEF(BagGetter(Enum.BagIndex.BankBag_3, "Bank Bag 3", true), "bank3"),
    BAGDEF(BagGetter(Enum.BagIndex.BankBag_4, "Bank Bag 4", true), "bank4"),
    BAGDEF(BagGetter(Enum.BagIndex.BankBag_5, "Bank Bag 5", true), "bank5"),
    BAGDEF(BagGetter(Enum.BagIndex.BankBag_6, "Bank Bag 6", true), "bank6"),
    BAGDEF(BagGetter(Enum.BagIndex.BankBag_7, "Bank Bag 7", true), "bank7"),
    BAGDEF(BagGetter(Enum.BagIndex.Reagentbank, "Bank Reagent Bag", false)),
}
for tab = 1, VOID_MAX_TABS do
    tinsert(BAGS, BAGDEF(VoidGetter(tab), "void"..tab))
end

-- For equipment, names are available as global constants, but again they
-- don't provide a way to distinguish between multiple slots of the same type.
function EQUIPDEF(id, name)
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

local function SlotsString(slots)
    local s
    if #slots == 1 then
        s = " slot " .. slots[1]
    else
        s = " slots " .. slots[1]
        if #slots == 2 then
            s = s .. " and " .. slots[2]
        else
            for i = 2, #slots-1 do
                s = s .. ", " .. slots[i]
            end
            s = s .. ", and " .. slots[#slots]
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
                WoWXIV_isearch_cache[cache_id .. "_name"] = bag_name
                isearch_cache_uptodate[cache_id] = true
            elseif self.bankframe_open then
                -- If we're in the bank UI, we know for certain that a
                -- size of 0 means that no such bag exists.
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
        if cache_id and strsub(cache_id, 1, 4) == "bank" then
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

isearch_event_frame:RegisterEvent("VOID_STORAGE_UPDATE")
isearch_event_frame:RegisterEvent("VOID_STORAGE_CONTENTS_UPDATE")
function isearch_event_frame:VOID_STORAGE_UPDATE()
    for _, bag in ipairs(BAGS) do
        local cache_id = bag.cache_id
        if cache_id and strsub(cache_id, 1, 4) == "void" then
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
function isearch_event_frame:VOID_STORAGE_CONTENTS_UPDATE()
    for _, bag in ipairs(BAGS) do
        local cache_id = bag.cache_id
        if cache_id and strsub(cache_id, 1, 4) == "void" then
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

isearch_event_frame:RegisterEvent("ADDON_LOADED")
function isearch_event_frame:ADDON_LOADED(name)
    if name == module_name then
        if IsVoidStorageReady() then
            self:VOID_STORAGE_UPDATE()
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
                        if name:lower():find(search_key, 1, true) then
                            found_slots[name] = found_slots[name] or {}
                            tinsert(found_slots[name], offset + slot)
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
            if size > 0 then
                if cache_id then
                    WoWXIV_isearch_cache[cache_id] = content
                    WoWXIV_isearch_cache[cache_id .. "_size"] = size
                    WoWXIV_isearch_cache[cache_id .. "_name"] = bag_name
                    isearch_cache_uptodate[cache_id] = true
                end
            elseif cache_id then
                size = WoWXIV_isearch_cache[bag.cache_id .. "_size"]
                if size then
                    content = WoWXIV_isearch_cache[bag.cache_id]
                    bag_name = WoWXIV_isearch_cache[bag.cache_id .. "_name"]
                    is_cached = not isearch_cache_uptodate[cache_id]
                end
            end
            if content then
                for slot = 1, size do
                    local item = content[slot]
                    local name = item and C_Item.GetItemInfo(item)
                    if name and name:lower():find(search_key, 1, true) then
                        found_slots[name] = found_slots[name] or {}
                        tinsert(found_slots[name], slot)
                        used_cache = used_cache or is_cached
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
            if name:lower():find(search_key, 1, true) then
                tinsert(results, {name, " equipped on " .. Blue(slot.name)})
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
        for _, result in ipairs(results) do
            local name, location = unpack(result)
            print(" → " .. Yellow(name) .. location)
        end
        if used_cache then
            print(Red("Some results may be out of date. Visit the appropriate storage NPC to ensure current results."))
        end
    else
        print(Red(" → No matching items found."))
    end
end
