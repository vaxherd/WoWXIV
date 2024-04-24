local _, WoWXIV = ...
WoWXIV.SlashCmd = {}

local FCT = function(...)
    FCT = WoWXIV.FormatColoredText
    return FCT(...)
end
local function Red(s)    return FCT(s, RED_FONT_COLOR:GetRGB())        end
local function Yellow(s) return FCT(s, YELLOW_FONT_COLOR:GetRGB())     end
local function Green(s)  return FCT(s, GREEN_FONT_COLOR:GetRGB())      end
local function Blue(s)   return FCT(s, BRIGHTBLUE_FONT_COLOR:GetRGB()) end

------------------------------------------------------------------------

local cmds = {}

local function DefineCommand(name, aliases, func)
    cmds[name] = {
        aliases = aliases,
        func = func,
    }
end

----------------

DefineCommand("echo", nil, function(arg)
    print(arg)
end)

----------------

-- WoW provides the C_Container.GetBagName() API to get the bag item name
-- for a bag slot, but (1) that doesn't let us differentiate between
-- multiple bags of the same name and (2) it doesn't work for special bags
-- like the main bank bag, so we use our own names here (but still append
-- the bag item name for player-created bags).
function BAGDEF(id, name, append_bagname, max_slots)
    return {id = id, name = name, append_bagname = append_bagname,
            max_slots = max_slots}
end
local BAGS = {
    BAGDEF(Enum.BagIndex.Backpack, "Backpack", false, 20),
    BAGDEF(Enum.BagIndex.Bag_1, "Bag 1", true, 36),
    BAGDEF(Enum.BagIndex.Bag_2, "Bag 2", true, 36),
    BAGDEF(Enum.BagIndex.Bag_3, "Bag 3", true, 36),
    BAGDEF(Enum.BagIndex.Bag_4, "Bag 4", true, 36),
    BAGDEF(Enum.BagIndex.ReagentBag, "Reagent Bag", false, 38),
    BAGDEF(Enum.BagIndex.Bank, "Bank", false, 28),
    BAGDEF(Enum.BagIndex.BankBag_1, "Bank Bag 1", true, 36),
    BAGDEF(Enum.BagIndex.BankBag_2, "Bank Bag 2", true, 36),
    BAGDEF(Enum.BagIndex.BankBag_3, "Bank Bag 3", true, 36),
    BAGDEF(Enum.BagIndex.BankBag_4, "Bank Bag 4", true, 36),
    BAGDEF(Enum.BagIndex.BankBag_5, "Bank Bag 5", true, 36),
    BAGDEF(Enum.BagIndex.BankBag_6, "Bank Bag 6", true, 36),
    BAGDEF(Enum.BagIndex.BankBag_7, "Bank Bag 7", true, 36),
    BAGDEF(Enum.BagIndex.Reagentbank, "Bank Reagent Bag", true, 98),
}

-- Void storage is handled by a separate subsystem, which just needs the
-- tab and slot index.
local VOID_MAX_TABS = 2
local VOID_MAX_SLOTS = 80  -- per tab

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

DefineCommand("isearch", {"is"}, function(arg)
    if not arg or arg == "" then
        print("Usage: "..Yellow("/isearch").." ("..Yellow("/is")..") "..Green("Item Name"))
        print("    Searches your inventory and equipment for an item.")
        print("    The bank UI must be open to search bank bags.")
        print("    (The bank reagent bag is always available.)")
        print("    Similarly, the void storage UI must be open to search void storage.")
        print(" ")
        print("    Examples:")
        print("        "..Yellow("/isearch Dragonspring Water"))
        print("         → Lists all bags containing the item \"Dragonspring Water\".")
        print("        "..Yellow("/isearch Heart of Azeroth"))
        print("         → Shows where your Heart of Azeroth is located, whether in bags or equipped.")
        return
    end

    local item_name = arg
    print("Searching for " .. Yellow(item_name))

    local found = false

    for _, bag in ipairs(BAGS) do
        local found_slots = {}
        for i = 1, bag.max_slots do
            local loc = ItemLocation:CreateFromBagAndSlot(bag.id, i)
            if loc and loc:IsValid() then
                local name = C_Item.GetItemName(loc)
                if name:lower() == item_name:lower() then
                    tinsert(found_slots, i)
                end
            end
        end
        if #found_slots > 0 then
            local s = SlotsString(found_slots)
            local bag_name = bag.name
            if bag.append_bagname then
                bag_name = bag_name .. " (" .. C_Container.GetBagName(bag.id) .. ")"
            end
            print(" → Found in " .. Blue(bag_name .. s))
            found = true
        end
    end

    if CanUseVoidStorage() and IsVoidStorageReady() then
        for tab = 1, VOID_MAX_TABS do
            local found_slots = {}
            for slot = 1, VOID_MAX_SLOTS do
                local item = GetVoidItemInfo(tab, slot)
                if item then
                    local name = C_Item.GetItemInfo(item)
                    if name and name:lower() == item_name:lower() then
                        tinsert(found_slots, slot)
                    end
                end
            end
            if #found_slots > 0 then
                local s = SlotsString(found_slots)
                print(" → Found in " .. Blue("Void Storage tab " .. tab .. s))
                found = true
            end
        end
    end

    for _, slot in ipairs(EQUIPS) do
        local slot_info = GetInventorySlotInfo(slot.id)
        assert(slot_info)
        local loc = ItemLocation:CreateFromEquipmentSlot(slot_info)
        if loc and loc:IsValid() then
            local name = C_Item.GetItemName(loc)
            if name:lower() == item_name:lower() then
                print(" → Equipped on " .. Blue(slot.name))
                found = true
            end
        end
    end

    if not found then
        print(Red(" → Not found."))
    end
end)

----------------

DefineCommand("wowxiv", {"xiv"}, function(arg)
    if not arg or arg == "" then
        WoWXIV.Config.Open()
    else
        print("Usage: "..Yellow("/wowxiv (/xiv)"))
        print("   Opens the addon settings window.")
    end
end)

------------------------------------------------------------------------

function WoWXIV.SlashCmd.Init()
    for cmd, data in pairs(cmds) do
        local var = "SLASH_" .. cmd:upper()
        _G[var.."1"] = "/"..cmd
        if data.aliases then
            for i = 1, #data.aliases do
                _G[var..(i+1)] = "/"..(data.aliases[i])
            end
        end
        SlashCmdList[cmd:upper()] = data.func
    end
end
