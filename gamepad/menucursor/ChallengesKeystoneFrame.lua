local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local ChallengesKeystoneFrameHandler = class(MenuCursor.AddOnMenuFrame)
ChallengesKeystoneFrameHandler.ADDON_NAME = "Blizzard_ChallengesUI"
MenuCursor.ChallengesKeystoneFrameHandler = ChallengesKeystoneFrameHandler  -- For exports.
MenuCursor.Cursor.RegisterFrameHandler(ChallengesKeystoneFrameHandler)

function ChallengesKeystoneFrameHandler:__constructor()
    __super(self, ChallengesKeystoneFrame)
    self.cursor_show_item = true
    hooksecurefunc(self.frame, "OnKeystoneSlotted",
                   function() self:RefreshTargets() end)

    -- Were we opened along with bag frames (the usual case)?  We use this
    -- to control whether we automatically close when the last bag frame is
    -- independently closed.
    self.opened_from_bags = false
end

function ChallengesKeystoneFrameHandler:RefreshTargets()
    local target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTargets()
    local f = self.frame
    if target == f.KeystoneSlot or target == f.StartButton then
        self:SetTarget(target)
    else
        self:SetTarget(self:GetDefaultTarget())
    end
end

function ChallengesKeystoneFrameHandler:SetTargets(old_target)
    local f = self.frame
    self.targets = {
        [f.KeystoneSlot] = {on_click = function() self:ClickSlot() end,
                            lock_highlight = true, send_enter_leave = true,
                            up = f.StartButton, left = false, right = false,
                            is_default = true},
        [f.StartButton] = {can_activate = true, lock_highlight = true,
                           down = f.KeystoneSlot, left = false, right = false},
    }
    if f.Affixes and f.Affixes[1] and f.Affixes[1]:IsShown() then
        self.targets[f.Affixes[1]] = {
            send_enter_leave = true, up = f.KeystoneSlot, down = f.StartButton,
            left = false, right = false}
        self.targets[f.KeystoneSlot].down = f.Affixes[1]
        self.targets[f.StartButton].up = f.Affixes[1]
        local i = 2
        while f.Affixes[i] and f.Affixes[i]:IsShown() do
            self.targets[f.Affixes[i]] = {
                send_enter_leave = true,
                up = f.KeystoneSlot, down = f.StartButton,
                left = f.Affixes[i-1], right = f.Affixes[1]}
            self.targets[f.Affixes[i-1]].right = f.Affixes[i]
            i = i + 1
        end
        self.targets[f.Affixes[1]].left = f.Affixes[i-1]
    end
end


function ChallengesKeystoneFrameHandler:OnShow()
    if self:IsEnabled() then return end
    assert(self.frame:IsVisible())
    -- Don't focus if any container bags are open, so the player can more
    -- easily select a keystone.
    if IsAnyStandardHeldBagOpen() then
        self.opened_from_bags = true
        self:EnableBackground(self:GetDefaultTarget())
    else
        self.opened_from_bags = false
        self:Enable(self:GetDefaultTarget())
    end
end

function ChallengesKeystoneFrameHandler:OnFocus()
    -- If we were opened along with bag frames, close ourselves when we
    -- receive focus from the last bag frame being closed (such as from
    -- pressing the cancel button while in the bag).
    if self.opened_from_bags and not IsAnyStandardHeldBagOpen() then
        self:CancelUIFrame()
    end
end

function ChallengesKeystoneFrameHandler:ClickSlot()
    local type, id = GetCursorInfo()
    if type then
        if type == "item" and C_Item.IsItemKeystoneByID(id) then
            C_ChallengeMode.SlotKeystone()
        else
            PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)
            ClearCursor()
        end
    end
    -- Surprisingly, the frame's OnKeystoneRemoved() callback is never
    -- referenced, so we can't clear the UI by calling
    -- C_ChallengeMode.RemoveKeystone() (which puts the keystone in the
    -- cursor, so we'd need to then ClearCursor() to fully return it to
    -- the bag it came from).  We could potentially call self.frame:Reset()
    -- to force an update, but that would introduce taint, so we just
    -- ignore confirm actions on a filled slot and require the user to
    -- close the frame to clear the slot.
end

---------------------------------------------------------------------------

-- Give input focus to ChallengesKeystoneFrame and put the cursor on the
-- Activate button.  The frame is assumed to be open.
function ChallengesKeystoneFrameHandler.FocusActivateButton()
    local instance = ChallengesKeystoneFrameHandler.instance
    assert(instance:IsEnabled())
    instance:SetTarget(ChallengesKeystoneFrame.ActivateButton)
    instance:Focus()
end
