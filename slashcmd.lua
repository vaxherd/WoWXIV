local _, WoWXIV = ...
WoWXIV.SlashCmd = {}

local tinsert = tinsert

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

---------------- /itemsearch (/isearch, /is)

DefineCommand("itemsearch", {"isearch", "is"}, Green("ItemName"),
              {"Searches your inventory and equipment for an item.",
               "Bag items equipped in inventory or bank slots are not listed.",
               "When using a combined backpack, slots count from the bottom right: slot 10 is the bottom left corner, 31 is the right side of the 4th row from the bottom, and so on.",
               "",
               "Unlike the search box in the default backpack UI, this command does not search item descriptions, so it can be useful in narrowing down the search when you know the item's name.",
               "",
               "Bank bags (other than the reagent bank) and void storage contents may be out of date if you log in from multiple computers. Visit the relevant NPC to update the cached data.",
               "",
               "Examples:",
               "    "..Yellow("/itemsearch Heart of Azeroth"),
               "     → Shows where your Heart of Azeroth is stored or equipped.",
               "    "..Yellow("/itemsearch wildercloth"),
               "     → Finds all items with \"Wildercloth\" in the name, excluding any Wildercloth Bags equipped as inventory or bank bags."},
              WoWXIV.isearch)

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
