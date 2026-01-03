local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor


---------------------------------------------------------------------------
-- Editor utility functions
---------------------------------------------------------------------------

-- Measure the character cell size of the (presumed monospace) font used by
-- the given FontString, and return the cell width and height in display
-- coordinate units.  On return, the FontString's text will be set to the
-- empty string.
function Editor.MeasureFont(fs)
    -- Measuring a single character doesn't seem to give us correct values,
    -- so measure the difference between two widths instead.
    fs:SetText("X")
    local w1 = fs:GetStringWidth()
    fs:SetText("XXXXXXXXXXX")
    local w11 = fs:GetStringWidth()
    -- FIXME: this sometimes returns the wrong size (50/6 instead of 55/6); why?
    local cell_w = (w11 - w1) / 10
    -- Add a bit of spacing so underlines don't overlap the line below.
    local cell_h = fs:GetStringHeight() + 1
    fs:SetText("")
    return cell_w, cell_h
end
