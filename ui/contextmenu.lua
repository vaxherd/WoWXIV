local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
local list = WoWXIV.list
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

UI.ContextMenu = class(Frame)
UI.ContextMenuButton = class(Button)
local ContextMenu = UI.ContextMenu
local ContextMenuButton = UI.ContextMenuButton

---------------------------------------------------------------------------

function ContextMenu:__allocator()
    return __super("Frame", nil, UIParent)
end

function ContextMenu:__constructor()
    self.MIN_EDGE = 4      -- Don't get closer than this to the screen edge.
    self.SPACING = 1       -- Vertical spacing between buttons.
    self.buttons = list()  -- List of buttons currently shown in the layout.

    self:Hide()
    self:SetFrameStrata("DIALOG")
    self:SetScript("OnHide", self.OnHide)
    -- Immediately close the submenu on any mouse click, to reduce the
    -- risk of colliding operations.
    self:RegisterEvent("GLOBAL_MOUSE_UP")
    self:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_UP" and self:IsShown() then self:Hide() end
    end)

    self.background = self:CreateTexture(nil, "BACKGROUND")
    self.background:SetPoint("TOPLEFT", -14, 11)
    self.background:SetPoint("BOTTOMRIGHT", 14, -17)
    self.background:SetAtlas("common-dropdown-bg")
end

-- Open the context menu at the location of the given button.  Any
-- additional arguments are passed to Configure().
function ContextMenu:Open(button, ...)
    if self:IsShown() then
        self:Close()
    end

    self:ClearLayout()
    self:Configure(button, ...)
    self:FinishLayout()

    self:ClearAllPoints()
    local w, h = self:GetSize()
    local ix, iy, iw, ih = button:GetRect()
    local anchor, refpoint
    if (ix+iw) + w + self.MIN_EDGE <= UIParent:GetWidth() then
        anchor = "TOPLEFT"
        refpoint = "BOTTOMRIGHT"
    else
        -- Doesn't fit on the right side, move to the left.
        anchor = "TOPRIGHT"
        refpoint = "BOTTOMLEFT"
    end
    local y_offset = max((h + self.MIN_EDGE) - iy, 0)
    self:SetPoint(anchor, button, refpoint, 0, y_offset)
    self:Show()
end

-- Just a synonym for Hide().  Included for parallelism with Open().
function ContextMenu:Close()
    self:Hide()
end

function ContextMenu:OnHide()
    for button in self.buttons do
        button:Hide()
    end
    self.buttons:clear()
    self.bag, self.slot = nil, nil
end

function ContextMenu:ClearLayout()
    self.layout_prev = nil
    self.layout_width = 64  -- Set a sensible minimum width.
    self.layout_height = 0
    self.buttons:clear()
end

function ContextMenu:AppendLayout(element)
    local target, ref, offset
    if self.layout_prev then
        target = self.layout_prev
        ref = "BOTTOM"
        offset = self.SPACING
    else
        target = self
        ref = "TOP"
        offset = 0
    end
    element:ClearAllPoints()
    element:SetPoint("TOPLEFT", target, ref.."LEFT", 0, -offset)
    self.layout_width = max(self.layout_width, element:GetWidth())
    self.layout_height = self.layout_height + offset + element:GetHeight()
    self.layout_prev = element
end

function ContextMenu:AppendButton(button)
    self:AppendLayout(button)
    self.buttons:append(button)
    button:Show()
end

function ContextMenu:FinishLayout()
    self:SetSize(self.layout_width, self.layout_height)
    self.layout_prev = nil
end

-- Should be implemented by instances/subclasses.  Call self:AppendButton()
-- (or self:AppendLayout()) for each desired element in the menu.  Receives
-- all arguments passed to ContextMenu:Open().
function ContextMenu:Configure(button, ...)
end

-- Convenience functions for creating button instances.
--
-- CreateButton(text, [OnClick]) creates an insecure ContextMenuButton with
-- the given text and optionally sets its OnClick handler to the given
-- function.
--
-- CreateSecureButton(text, [attributes]) creates a secure ContextMenuButton
-- and sets its attributes from the given table of attributes, if any.
function ContextMenu:CreateButton(text, OnClick)
    local button = ContextMenuButton(self, text, false)
    if OnClick then
        button.OnClick = OnClick
    end
    return button
end
function ContextMenu:CreateSecureButton(text, attributes)
    local button = ContextMenuButton(self, text, false)
    for attrib, value in pairs(attributes or {}) do
        button:SetAttribute(attrib, value)
    end
    return button
end

---------------------------------------------------------------------------

-- ContextMenuButtons can be either secure (performing a secure action on
-- click, like SecureActionButtonTemplate) or insecure (calling a function
-- on click).  To create a secure button, pass secure=true when creating
-- the button instance; the caller is then responsible for setting
-- appropriate attributes for the secure action to be execute.  To create
-- an insecure button, pass secure=false (or omit the argument) and
-- implement the desired on-click behavior in button:OnClick().

function ContextMenuButton:__allocator(parent, text, secure)
    if secure then
        return __super("Button", nil, parent, "SecureActionButtonTemplate")
    else
        return __super("Button", nil, parent)
    end
end

function ContextMenuButton:__constructor(parent, text, secure)
    self:Hide()
    local label = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label = label
    label:SetPoint("LEFT", 2, 0)
    label:SetTextColor(WHITE_FONT_COLOR:GetRGB())
    label:SetTextScale(1.0)
    label:SetText(text)
    self:SetSize(label:GetStringWidth()+4, label:GetStringHeight()+2)
    self:RegisterForClicks("LeftButtonUp")
    self:SetAttribute("useOnKeyDown", false)  -- Indirect clicks are always up.
    self:HookScript("PostClick", function() parent:Hide() end)
    if not secure then
        -- We need to wrap the OnClick in a function because the function
        -- pointer might (and probably will) change later.
        self:SetScript("OnClick", function() self:OnClick() end)
    end
end

function ContextMenuButton:SetEnabled(enabled)
    __super(self, enabled)
    self.label:SetTextColor(
        (enabled and WHITE_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
end
-- Ensure all enable changes go through SetEnabled() to update the text color.
function ContextMenuButton:Enable() self:SetEnabled(true) end
function ContextMenuButton:Disable() self:SetEnabled(false) end

function ContextMenuButton:SetText(text)
    self.label:SetText(text)
end

-- Should be implemented by instances/subclasses for insecure buttons.
function ContextMenuButton:OnClick()
end
