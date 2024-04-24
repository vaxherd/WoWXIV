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

-- We take the admittedly brazen step here of defining a global symbol
-- "SlashCmdHelp" for help-related data, with the intent that external
-- modules can also use it to register their own help strings.
-- Each key should be the uppercase name of a slash command (as for
-- SlashCmdList), and its value should be a table with the following
-- keys:
--    args: A string describing the arguments to the command.  May be
--        nil if the command takes no arguments.  In this module, we
--        highlight individual arguments in green, but such highlighting
--        is up to the individual command definition.
--    help: A string describing the behavior of the command.  For a
--        multiple-line description, use a table containing each line as
--        a single entry (see the "/help" help text below for an example).
-- The /help (/?) command defined here will automatically pick up
-- aliases by searching for global variables named SLASH_CMD2, SLASH_CMD3,
-- etc.
SlashCmdHelp = SlashCmdHelp or {}

------------------------------------------------------------------------

local cmds = {}

local function DefineCommand(name, aliases, args, help, func)
    cmds[name] = {
        aliases = aliases,
        args = args,
        help = help,
        func = func,
    }
end

-- FormatColoredText() won't be available until after loading completes,
-- so defer these definitions until that point.
local function DefineAllCommands()  -- wraps all DefineCommand() calls

---------------- /?

-- Helper for SlashCmdList iteration.  WoW seems to use a layered
-- structure for SlashCmdList, perhaps so each module's definitions
-- remain available to it regardless of overlaying by other modules,
-- so we have to read through base tables to find all commands.
local function deep_next(t, i)
    i = i or {t, nil}
    local k, v = next(i[1], i[2])
    if v then
        i[2] = k
        return i, v
    end
    local mt = getmetatable(i[1])
    if mt and type(mt.__index) == "table" then
        i[1] = mt.__index
        i[2] = nil
        return deep_next(t, i)
    end
    return nil
end
local function deep_pairs(t, i)
    return deep_next, t, nil
end

DefineCommand("?", nil, Green("command"),
              {"Displays usage information for the given command.",
               "If no command exactly matches the given name, instead displays a list of all commands starting with the given string.",
               "Append an asterisk (*) to the command name to force the listing behavior even if a command of that name exists.",
               "Note that basic builtin commands like \"/sit\" are hidden by the game client and will not be listed.",
               "",
               "Examples:",
               "    "..Yellow("/? ?"),
               "     → Displays this text.",
               "    "..Yellow("/? ap*"),
               "     → Lists all commands whose names start with \"/ap\".",
               "    "..Yellow("/? *"),
               "     → Lists all known (non-builtin) commands."},
function(arg)
    -- This command doesn't particularly require speed of execution, so we
    -- just rebuild the reverse lookup list on each call.
    local cmds = {}
    local aliases = {}
    for table_key, func in deep_pairs(SlashCmdList) do
        local key = table_key[2]
        if func then
            aliases[key] = {}
            -- Some core commands are defined multiple times (why?), so
            -- omit duplicates.
            local seen = {}
            local i = 1
            while _G["SLASH_"..key..i] do
                local cmd = _G["SLASH_"..key..i]
                if cmd and cmd:sub(1,1) == "/" then  -- Should always be true.
                    cmd = cmd:sub(2,-1)
                end
                if not seen[cmd] then
                    seen[cmd] = true
                    cmds[cmd] = key
                    tinsert(aliases[key], cmd)
                end
                i = i+1
            end
        end
    end

    if not arg or arg == "" then
        arg = "?"  -- Default to displaying help on ourselves.
    end

    if arg:sub(-1,-1) ~= "*" and cmds[arg] then
        local key = cmds[arg]
        local help = SlashCmdHelp[key] or {args="...", help=nil}
        local usage_str = Yellow("/"..aliases[key][1])
        if #aliases[key] > 1 then
            for i = 2, #aliases[key] do
                usage_str = (usage_str .. (i==2 and " (" or ", ")
                                       .. Yellow("/"..aliases[key][i]))
            end
            usage_str = usage_str .. ")"
        end
        if help.args and type(help.args) == "string" then
            usage_str = usage_str .. " " .. help.args
        end
        print("Usage: " .. usage_str)
        if type(help.help) == "table" and type(help.help[1]) == "string" then
            for _,s in ipairs(help.help) do
                if type(s) == "string" then
                    print("    " .. s)
                end
            end
        elseif type(help.help) == "string" then
            print("    " .. help.help)
        else
            print("    No help is available for this command.")
        end

    else  -- no exact match or command list explicitly requested
        if arg:sub(-1,-1) == "*" then
            arg = arg:sub(1,-2)
        end
        local found_keys = {}
        for cmd, key in pairs(cmds) do
            if cmd:sub(1,#arg) == arg then
                if not found_keys[key] or cmd < found_keys[key] then
                    found_keys[key] = cmd
                end
            end
        end
        local list = {}
        for key, cmd in pairs(found_keys) do
            tinsert(list, key)
        end
        table.sort(list, function(a,b) return found_keys[a] < found_keys[b] end)
        if #list > 0 then
            print(("Found %d command%s%s:"):format(
                      #list, #list==1 and "" or "s",
                      #arg>0 and " matching "..Yellow(arg) or ""))
            for _,key in ipairs(list) do
                local alias_str = Yellow("/"..found_keys[key])
                local first_alias = true
                for _,cmd in ipairs(aliases[key]) do
                    if cmd ~= found_keys[key] then
                        if first_alias then
                            alias_str = alias_str .. " ("
                            first_alias = false
                        else
                            alias_str = alias_str .. ", "
                        end
                        alias_str = alias_str .. Yellow("/"..cmd)
                    end
                end
                if not first_alias then  -- i.e., if any aliases were found
                    alias_str = alias_str .. ")"
                end
                print("    " .. alias_str)
            end
        else
            print(Red("No commands matching "..Yellow(arg).." found."))
        end
    end
end)

---------------- /echo

DefineCommand("echo", nil, Green("text"),
              "Prints \""..Green("text").." to the chat log.",
function(arg)
    print(arg)
end)

---------------- /isearch (/is)

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

DefineCommand("isearch", {"is"}, Green("ItemName"),
        {"Searches your inventory and equipment for an item.",
         "The bank UI must be open to search bank bags other than the bank reagent bag.",
         "Similarly, the void storage UI must be open to search void storage.",
         "",
         "Examples:",
         "    "..Yellow("/isearch Dragonspring Water"),
         "     → Lists all bags containing the item \"Dragonspring Water\".",
         "    "..Yellow("/isearch Heart of Azeroth"),
         "     → Shows where your Heart of Azeroth is located, whether in bags or equipped."},
function(arg)
    if not arg or arg == "" then
        print(Red("No item name given. Try \"/? isearch\" for help."))
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

---------------- /wowxiv (/xiv)

DefineCommand("wowxiv", {"xiv"}, nil,
              "Opens the WoWXIV addon settings window.",
function(arg)
    WoWXIV.Config.Open()
end)

---------------- (end of commands)

end  -- DefineAllCommands()

------------------------------------------------------------------------

function WoWXIV.SlashCmd.Init()
    DefineAllCommands()
    for cmd, data in pairs(cmds) do
        local key = (cmd=="?" and "XIVHELP" or cmd:upper())
        local var = "SLASH_" .. key
        _G[var.."1"] = "/"..cmd
        if data.aliases then
            for i = 1, #data.aliases do
                _G[var..(i+1)] = "/"..(data.aliases[i])
            end
        end
        SlashCmdList[key] = data.func
        SlashCmdHelp[key] = {args = data.args, help = data.help}
    end
end
