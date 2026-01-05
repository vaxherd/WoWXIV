local _, WoWXIV = ...
WoWXIV.SlashCmd = {}

local list = WoWXIV.list
local set = WoWXIV.set

local strfind = string.find
local strgmatch = string.gmatch
local strjoin = string.join
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub

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
            aliases[key] = list()
            -- Some core commands are defined multiple times (why?), so
            -- omit duplicates.
            local seen = set()
            local i = 1
            while _G["SLASH_"..key..i] do
                local cmd = _G["SLASH_"..key..i]
                if cmd and cmd:sub(1,1) == "/" then  -- Should always be true.
                    cmd = cmd:sub(2,-1)
                end
                if not seen:has(cmd) then
                    seen:add(cmd)
                    cmds[cmd] = key
                    aliases[key]:append(cmd)
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
        local found = list()
        for key, cmd in pairs(found_keys) do
            found:append(key)
        end
        if #found > 0 then
            found:sort(function(a,b) return found_keys[a] < found_keys[b] end)
            print(("Found %d command%s%s:"):format(
                      #found, #found==1 and "" or "s",
                      #arg>0 and " matching "..Yellow(arg) or ""))
            for key in found do
                local alias_str = Yellow("/"..found_keys[key])
                local first_alias = true
                for cmd in aliases[key] do
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

---------------- /itemsearch (/isearch, /is)

DefineCommand("itemsearch", {"isearch", "is"}, Green("ItemName"),
              {"Searches your inventory and equipment for an item.",
               "Bag items equipped in inventory bag slots are not listed.",
               "When using a combined backpack, slots count from the bottom right: slot 10 is the bottom left corner, 31 is the right side of the 4th row from the bottom, and so on.",
               "",
               "Unlike the search box in the default backpack UI, this command does not search item descriptions, so it can be useful in narrowing down the search when you know the item's name.",
               "",
               "Bank tab results may be out of date if you log in from multiple computers. Visit a bank to update the cached data.",
               "",
               "Examples:",
               "    "..Yellow("/itemsearch Heart of Azeroth"),
               "     → Shows where your Heart of Azeroth is stored or equipped.",
               "    "..Yellow("/itemsearch wildercloth"),
               "     → Finds all items with \"Wildercloth\" in the name, excluding any Wildercloth Bags equipped as inventory bags."},
function(arg)
    if not arg or arg == "" then
        print(Red("No item name given. Try \"/? itemsearch\" for help."))
        return
    end
    return WoWXIV.isearch(arg)
end)

---------------- /itemsort (/isort)

DefineCommand("itemsort", {"isort"}, Green("bag").." "..Green("subcommand"),
              {"Performs a customized sort on an inventory bag or bank tab.",
               "",
               "The "..Green("bag").." argument specifies which bag to sort, and can be either a numeric bag ID (from the "..Yellow("|Hapi:table:BagIndex:BagIndexConstants|h[Enum.BagIndex]|h").." enumeration) or one of the following:",
               "    "..Yellow("Backpack"),
               "    "..Yellow("Bag_1").." through "..Yellow("Bag_4"),
               "    "..Yellow("ReagentBag"),
               "    "..Yellow("CharacterBankTab_1").." through "..Yellow("CharacterBankTab_6"),
               "    "..Yellow("AccountBankTab_1").." through "..Yellow("AccountBankTab_5"),
               "",
               "The "..Green("subcommand").." can be any of the following:",
               "",
               Yellow("condition "..Green("condition").." "..Green("direction")),
               "→ Adds a sort condition for the given bag. If multiple conditions are given, they are executed in sequence, so that items which compare equal by the last condition will be sorted by the next-to-last condition, and so on. Items which compare equal by all conditions will remain in the same relative order (that is, the sorting operation is stable).",
               "   "..Green("condition").." may be any of the following:",
               "    - "..Yellow("id").." (numeric item ID)",
               "    - "..Yellow("stack").." (stack count)",
               "    - "..Yellow("expansion").." (expansion in which item was added)",
               "    - "..Yellow("category").." (item category)",
               "    - "..Yellow("quality").." (item quality)",
               "    - "..Yellow("craftquality").." (crafting/reagent quality)",
               "    - "..Yellow("itemlevel").." (item level)",
               "   "..Green("direction").." may be either "..Yellow("ascending").." ("..Yellow("asc")..") or "..Yellow("descending").." ("..Yellow("des")..").",
               "",
               Yellow("execute"),
               "→ Sorts the given bag. To sort bank tabs, you must have the bank window open. Note that sorts can take time to perform; manually moving items around or closing the bank window during a sort may interrupt the sort and leave items in an unspecified order.",
               "",
               Yellow("clear"),
               "→ Clears any previously set conditions for the given bag. If a sort is executed with no conditions set, nothing will be done. Note that performing an "..Yellow("execute").." on a bag implicitly clears all conditions for that bag.",
               "",
               "Examples:",
               "    "..Yellow("/itemsort Bag_4 condition id asc"),
               "    "..Yellow("/itemsort Bag_4 condition itemlevel des"),
               "    "..Yellow("/itemsort Bag_4 condition category asc"),
               "    "..Yellow("/itemsort Bag_4 execute"),
               "     → Sorts inventory bag 4 by item category in ascending order. Items of the same category are sorted in descending order by item level, and items which also have the same item level are sorted in ascending order by item ID."},
              WoWXIV.isort)

---------------- /wowxiv (/xiv)

DefineCommand("wowxiv", {"xiv"}, nil,
              "Opens the WoWXIV addon settings window.",
function(arg)
    WoWXIV.Config.Open()
end)

---------------- /xivedit (/xe)

DefineCommand("xivedit", {"xe"}, "["..Green("pathname").."]",
              "Opens a new editor window. With a "..Green("pathname")..", opens the file at that pathname; relative pathnames are taken to be relative to the addon root.",
function(arg)
    if arg and arg ~= "" then
        WoWXIV.Dev.Editor.Open(arg)
    else
        WoWXIV.Dev.Editor.New()
    end
end)

---------------- /xivfs (/xf)

local XIVFS_COMMANDS = {
    cat = function(args)
        local FS = WoWXIV.Dev.FS
        if #args ~= 1 then
            print(Red("Wrong number of arguments."))
            return
        end
        local path = args[1]
        local st = FS.Stat(path)
        if not st then
            print(Red(path..": No such file or directory"))
            return
        end
        if st.is_dir then
            print(Red(path..": Is a directory"))
            return
        end
        local data = FS.ReadFile(path)
        if not data then
            print(Red(path..": Read error"))
            return
        end
        local i = 1
        while i < #data do
            local eol = strstr(data, "\n", i) or #data+1
            local line = strsub(data, i, eol-1)
            print(line)
            i = eol+1
        end
    end,

    cp = function(args)
        local FS = WoWXIV.Dev.FS
        if #args ~= 2 then
            print(Red("Wrong number of arguments."))
            return
        end
        local source, dest = unpack(args)
        local st = FS.Stat(source)
        if not st then
            print(Red(source..": No such file or directory"))
            return
        end
        if st.is_dir then
            print(Red(source..": Is a directory"))
            return
        end
        local data = FS.ReadFile(source)
        if not data then
            print(Red(source..": Read error"))
            return
        end
        if not FS.WriteFile(dest, data) then
            print(Red(dest..": Write error"))
            return
        end
    end,

    ls = function(args)
        local FS = WoWXIV.Dev.FS
        if #args ~= 1 then
            print(Red("Wrong number of arguments."))
            return
        end
        local path = args[1]
        local st = FS.Stat(path)
        if not st then
            print(Red(path..": No such file or directory"))
            return
        end
        if not st.is_dir then
            print(Red(path..": Not a directory"))
            return
        end
        local names = FS.ListDirectory(path)
        if not names then
            print(Red(path..": Read error"))
            return
        end
        table.sort(names)
        for _, name in ipairs(names) do
            print(name)
        end
    end,

    mkdir = function(args)
        local FS = WoWXIV.Dev.FS
        if #args ~= 1 then
            print(Red("Wrong number of arguments."))
            return
        end
        local path = args[1]
        local st = FS.Stat(path)
        if st then
            print(Red(path..": File exists"))
            return
        end
        if not FS.CreateDirectory(path) then
            print(Red(path..": Failed to create directory"))
            return
        end
    end,

    rm = function(args)
        local FS = WoWXIV.Dev.FS
        if #args ~= 1 then
            print(Red("Wrong number of arguments."))
            return
        end
        local path = args[1]
        local st = FS.Stat(path)
        if not st then
            print(Red(path..": No such file or directory"))
            return
        end
        if st.is_dir then
            print(Red(path..": Is a directory"))
            return
        end
        if not FS.Remove(path) then
            print(Red(path..": Failed to remove"))
            return
        end
    end,

    rmdir = function(args)
        local FS = WoWXIV.Dev.FS
        if #args ~= 1 then
            print(Red("Wrong number of arguments."))
            return
        end
        local path = args[1]
        local st = FS.Stat(path)
        if not st then
            print(Red(path..": No such file or directory"))
            return
        end
        if not st.is_dir then
            print(Red(path..": Not a directory"))
            return
        end
        local names = FS.ListDirectory(path)
        if names and #names > 0 then
            print(Red(path..": Directory not empty"))
            return
        end
        if not FS.Remove(path) then
            print(Red(path..": Failed to remove"))
            return
        end
    end,
}

DefineCommand("xivfs", {"xf"}, Green("subcommand"),
              {"Performs an action on the development environment filesystem.",
               "",
               "The "..Green("subcommand").." can be any of the following:",
               "",
               Yellow("cat "..Green("pathname")),
               "Display the contents of the file "..Green("pathname").." in the chat log.",
               "",
               Yellow("cp "..Green("source").." "..Green("dest")),
               "Copy the file "..Green("source").." to the pathname "..Green("dest")..".",
               "",
               Yellow("ls "..Green("pathname")),
               "Display a list of files in the directory "..Green("pathname").." in the chat log.",
               "",
               Yellow("mkdir "..Green("pathname")),
               "Create a new directory at "..Green("pathname")..".",
               "",
               Yellow("rm "..Green("pathname")),
               "Remove the file "..Green("pathname")..".",
               "",
               Yellow("rmdir "..Green("pathname")),
               "Remove the directory "..Green("pathname")..". The directory must be empty."},
function(arg)
    local words = list()
    -- We don't support any sort of quoting because it should be
    -- unnecessary for our purposes.
    for word in strgmatch(arg, "%S+") do
        words:append(word)
    end
    if #words == 0 then
        print(Red("No subcommand given."))
    end
    print("[Command: " .. strjoin(" ", unpack(words)) .. "]")
    local command = words:pop(1)
    local func = XIVFS_COMMANDS[command]
    if func then
        func(words)
    else
        print(Red("Unknown subcommand."))
    end
end)

---------------- (debugging stuff)

if WoWXIV_config["DEBUG"] then

    StaticPopupDialogs["XIV_TEST1"] = {
        text = "Is this a test?",
        button1 = YES,
        button2 = NO,
        OnAccept = function() print("XIV_TEST1: accept") end,
        OnCancel = function() print("XIV_TEST1: cancel") end,
    }
    StaticPopupDialogs["XIV_TEST2"] = {
        text = "Are you sure?",
        button1 = YES,
        button2 = NO,
        OnAccept = function() print("XIV_TEST2: accept") end,
        OnCancel = function() print("XIV_TEST2: cancel") end,
    }
    StaticPopupDialogs["XIV_TEST3"] = {
        text = "Are you really, REALLY sure?",
        button1 = "Yes!!",
        button2 = "No...",
        button3 = "Mrgl?",
        OnAccept = function() print("XIV_TEST3: accept") end,
        OnCancel = function() print("XIV_TEST3: cancel") end,
        OnAlt = function()
            print("XIV_TEST3: alt")
            StaticPopup_Hide("XIV_TEST2")
        end,
    }

    DefineCommand("xivd", nil, nil, "WoWXIV debugging command.",
    function(arg)
        local space = strstr(arg, " ") or #arg+1
        local token = strsub(arg, 1, space-1)
        local rest = strsub(arg, space+1)
        if token == strsub("flytext", 1, #token) then
            WoWXIV.FlyText.Test()
        elseif token == strsub("popup", 1, #token) then
            local showhide = StaticPopup_Show
            if strsub(rest, 1, 1) == "-" then
                showhide = StaticPopup_Hide
                rest = strsub(rest, 2)
            end
            showhide("XIV_TEST"..rest)
        end
    end)

end  -- if WoWXIV_config["DEBUG"]

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
