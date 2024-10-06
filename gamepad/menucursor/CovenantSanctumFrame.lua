local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

local CovenantSanctumFrameHandler = class(AddOnMenuFrame)
CovenantSanctumFrameHandler.ADDON_NAME = "Blizzard_CovenantSanctum"
local CovenantSanctumTalentFrameHandler = class(MenuFrame)
Cursor.RegisterFrameHandler(CovenantSanctumFrameHandler)

function CovenantSanctumFrameHandler.OnAddOnLoaded(class)
    AddOnMenuHandler.OnAddOnLoaded(class)
    class.talent_instance = CovenantSanctumTalentFrameHandler()
end

function CovenantSanctumFrameHandler:__constructor()
    self:__super(CovenantSanctumFrame)
    local function ChooseTalent(button)
        self:OnChooseTalent(button)
    end
    self.targets = {
        [CovenantSanctumFrame.UpgradesTab.TravelUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.DiversionUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.AdventureUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.UniqueUpgrade] =
            {send_enter_leave = true, on_click = ChooseTalent},
        [CovenantSanctumFrame.UpgradesTab.DepositButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, is_default = true},
    }
end

function CovenantSanctumFrameHandler:OnChooseTalent(upgrade_button)
    upgrade_button:OnMouseDown()
    local talent_menu = CovenantSanctumFrameHandler.talent_instance
    talent_menu:Enable(talent_menu:SetTargets())
end

function CovenantSanctumTalentFrameHandler:__constructor()
    self:__super(CovenantSanctumFrame)
    self.cancel_func = function(self) self:Disable() end
end

function CovenantSanctumTalentFrameHandler:SetTargets()
    local TalentsList = CovenantSanctumFrame.UpgradesTab.TalentsList
    self.targets = {
        [TalentsList.UpgradeButton] =
            {can_activate = true, lock_highlight = true},
    }
    for frame in TalentsList.talentPool:EnumerateActive() do
        talent_menu.targets[frame] = {send_enter_leave = true}
    end
    return TalentsList.UpgradeButton
end
