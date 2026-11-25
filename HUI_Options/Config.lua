-- HUI - Settings window (/hui)
-- Part of the load-on-demand addon HUI_Options: loaded the first time the
-- window (or the colour picker) opens, so it takes no memory before that.
-- Sidebar with grouped pages on the left; each page is a scrollable stack of
-- cards, and each card lays its controls out in a two-column grid.

local A = HUI
local floor, format, max, min = math.floor, string.format, math.max, math.min

------------------------------------------------------------------------
-- Live setters (also used outside the window)
------------------------------------------------------------------------
function A:SetScale(v)
    if InCombatLockdown() then return end
    self.db.scale = v
    for _, f in pairs(self.units) do f:SetScale(v) end
    if self.playerCastbar then self.playerCastbar:SetScale(v); self:SetTemplate(self.playerCastbar) end
    if self.raidHolder then self.raidHolder:SetScale(v) end
    if self.partyHolder then self.partyHolder:SetScale(v) end
    -- keep borders exactly 1 screen pixel at the new scale
    for f in pairs(self.allFrames) do
        self:SetTemplate(f)
        if f.atrBorder then f.atrBorder:SetThickness(1) end
    end
    self:RefreshUnits()
    if self.LayoutParty then self:LayoutParty() end
    if self.RefreshCDM then self:RefreshCDM() end
end

------------------------------------------------------------------------
-- Style
------------------------------------------------------------------------
local WIN_W, WIN_H = 880, 560
local TITLE_H, NAV_W, FOOT_H = 28, 150, 28
local PAD = 14                                   -- content padding
local CONTENT_W = WIN_W - NAV_W - PAD * 2 - 6    -- page width (6 = scrollbar)
local CARD_PAD, ROW_GAP = 10, 1
local INNER_W = CONTENT_W - CARD_PAD * 2
local COL_W = INNER_W                            -- one control per row
local ROW_H = 18                                 -- every setting is one row: label left, control right
local CTRL_W = 140                               -- width of the control column
local COL_GAP = 20                               -- gap between the two columns of a card
local TWO_COL_MIN = 600                          -- cards this wide put settings side by side
local FS_LABEL, FS_SMALL, FS_TITLE = 10, 9, 11

local C = {
    window  = { 0.05, 0.05, 0.058, 0.98 },
    side    = { 0.032, 0.032, 0.038, 1 },
    card    = { 0.07, 0.07, 0.08, 1 },
    cardBd  = { 0.12, 0.12, 0.135, 1 },
    ctrl    = { 0.025, 0.025, 0.03, 1 },
    ctrlBd  = { 0.2, 0.2, 0.225, 1 },
    line    = { 1, 1, 1, 0.045 },
    text    = { 0.84, 0.84, 0.86 },
    muted   = { 0.5, 0.5, 0.54 },
    faint   = { 0.34, 0.34, 0.38 },
}
local function AC() return A.accent[1], A.accent[2], A.accent[3] end

local function Text(parent, size, color, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    A:SetFontPx(fs, A.media.font, size, "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify or "LEFT")
    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function Solid(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(A.media.blank)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

local function Box(f, bg, bd)
    A:SetTemplate(f, 1)
    f.atrCustomBg = true   -- the settings window doesn't follow the background setting
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1)
end

local function Tooltip(owner, title, body)
    if not body then return end
    owner:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.75, 0.75, 0.78, true)
        GameTooltip:Show()
    end)
    owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a settings row: label on the left, the control is placed on the right by the caller
local function Row(parent, label, tip)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(ROW_H)
    local hl = f:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(f)
    hl:SetTexture(1, 1, 1, 0.025)
    hl:Hide()
    f.hl = hl
    local t = Text(f, FS_LABEL)
    t:SetPoint("LEFT", 2, 0)
    t:SetPoint("RIGHT", f, "RIGHT", -(CTRL_W + 10), 0)
    t:SetText(label)
    f.label = t
    -- a small "i" when there is more to read
    if tip then
        local i = Text(f, FS_SMALL, C.faint)
        i:SetText("?")
        f.info = i
        -- sits right after the label text, also when the label changes later
        local function place()
            i:ClearAllPoints()
            i:SetPoint("LEFT", t, "LEFT", t:GetStringWidth() + 5, 0)
        end
        place()
        hooksecurefunc(t, "SetText", place)
    end
    f:SetScript("OnEnter", function() hl:Show() end)
    f:SetScript("OnLeave", function() hl:Hide() end)
    Tooltip(f, label, tip)
    f.tipText = tip
    return f
end

------------------------------------------------------------------------
-- Controls. Each is one row (label left, control right).
------------------------------------------------------------------------
-- on / off switch
local function Check(parent, label, get, set, tip)
    local b = Row(parent, label, tip)
    local track = CreateFrame("Frame", nil, b)
    A:Size(track, 22, 10)
    track:SetPoint("RIGHT", -2, 0)
    Box(track, C.ctrl, C.ctrlBd)
    local fill = Solid(track, "ARTWORK", AC())
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    local knob = Solid(track, "OVERLAY", 0.92, 0.92, 0.94, 1)
    A:Size(knob, 8, 6)
    b.Refresh = function()
        knob:ClearAllPoints()
        if get() then
            fill:Show()
            knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
            track:SetBackdropBorderColor(AC())
        else
            fill:Hide()
            knob:SetPoint("LEFT", track, "LEFT", 2, 0)
            track:SetBackdropBorderColor(C.ctrlBd[1], C.ctrlBd[2], C.ctrlBd[3])
        end
        if b.OnRefresh then b.OnRefresh(b) end
    end
    b:SetScript("OnClick", function()
        set(not get())
        PlaySound("igMainMenuOptionCheckBoxOn")
        b.Refresh()
    end)
    b.Refresh()
    return b
end

-- thin slider with a value box you can type into
local function Slider(parent, label, minv, maxv, step, get, set, fmt, tip)
    fmt = fmt or "%d"
    local f = Row(parent, label, tip)
    local vbox = CreateFrame("EditBox", nil, f)
    A:Size(vbox, 32, 14)
    vbox:SetPoint("RIGHT", -2, 0)
    vbox:SetAutoFocus(false)
    vbox:SetJustifyH("CENTER")
    A:SetFontPx(vbox, A.media.font, FS_SMALL, "")
    vbox:SetTextColor(1, 1, 1)
    Box(vbox, C.ctrl, C.ctrlBd)

    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("RIGHT", vbox, "LEFT", -8, 0)
    s:SetWidth(CTRL_W - 42)
    s:SetHeight(12)
    s:SetMinMaxValues(minv, maxv)
    s:SetValueStep(step)
    s:SetThumbTexture(A.media.blank)
    s:EnableMouseWheel(true)
    local th = s:GetThumbTexture()
    th:SetWidth(3)
    th:SetHeight(10)
    th:SetVertexColor(0.92, 0.92, 0.94)
    local track = Solid(s, "BACKGROUND", 0.2, 0.2, 0.225, 1)
    track:SetHeight(1)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    local fill = Solid(s, "ARTWORK", AC())
    fill:SetHeight(1)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", th, "CENTER")

    local function round(x) return floor(x / step + 0.5) * step end
    local function show(x) if not vbox:HasFocus() then vbox:SetText(format(fmt, x)) end end
    s:SetScript("OnValueChanged", function(self, x)
        x = round(x)
        show(x)
        if not self.updating and x ~= self.last then
            self.last = x
            set(x)
        end
    end)
    s:SetScript("OnMouseWheel", function(self, d)
        self:SetValue(min(maxv, max(minv, round(self:GetValue()) + d * step)))
    end)
    vbox:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText())
        self:ClearFocus()
        if n then s:SetValue(min(maxv, max(minv, n))) end
        show(round(s:GetValue()))
    end)
    vbox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); show(round(s:GetValue())) end)
    vbox:SetScript("OnEditFocusGained", function(self) self:HighlightText(); self:SetBackdropBorderColor(AC()) end)
    vbox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); self:SetBackdropBorderColor(C.ctrlBd[1], C.ctrlBd[2], C.ctrlBd[3]) end)
    s:HookScript("OnEnter", function() th:SetVertexColor(AC()); f.hl:Show() end)
    s:HookScript("OnLeave", function() th:SetVertexColor(0.92, 0.92, 0.94); f.hl:Hide() end)
    Tooltip(s, label, tip)
    f.Refresh = function()
        s.updating = true
        s:SetValue(get())
        s.last = round(get())
        s.updating = false
        vbox:SetText(format(fmt, get()))
    end
    f.Refresh()
    return f
end

-- color swatch that opens the game's color picker (with opacity)
-- Hex / RGB fields on the game's colour picker. Each box takes typing or a paste:
-- hex ("#ff8000", "ff8000", "f80", "|cffff8000", "ffff8000") or three numbers
-- ("255, 128, 0" or "1 0.5 0"), in any of the boxes.
local function ParseColor(str)
    if not str then return end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local nums = {}
    for n in str:gmatch("[%d%.]+") do nums[#nums + 1] = tonumber(n) end
    if #nums >= 3 and str:find("[,;%s]") then
        local r, g, b = nums[1], nums[2], nums[3]
        if not (r and g and b) then return end
        local unit = r <= 1 and g <= 1 and b <= 1 and str:find("%.")
        if not unit then r, g, b = r / 255, g / 255, b / 255 end
        return math.min(math.max(r, 0), 1), math.min(math.max(g, 0), 1), math.min(math.max(b, 0), 1)
    end
    local hex = str:gsub("^|c", ""):gsub("^#", ""):gsub("^0[xX]", "")
    if not hex:find("^%x+$") then return end
    if #hex == 8 then hex = hex:sub(3) end
    if #hex == 3 then hex = hex:gsub("(%x)", "%1%1") end
    if #hex ~= 6 then return end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local pickerFields
local function EnhanceColorPicker()
    if pickerFields or not ColorPickerFrame then return end
    local cp = ColorPickerFrame
    cp:SetHeight(cp:GetHeight() + 30)
    local row = CreateFrame("Frame", nil, cp)
    row:SetHeight(20)
    row:SetPoint("BOTTOMLEFT", ColorPickerOkayButton or cp, ColorPickerOkayButton and "TOPLEFT" or "BOTTOMLEFT", 0, 8)
    row:SetPoint("RIGHT", cp, "RIGHT", -16, 0)
    pickerFields = {}

    local function Refresh(skip)
        local r, g, b = cp:GetColorRGB()
        local v = { hex = format("%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5),
            r = tostring(floor(r * 255 + 0.5)), g = tostring(floor(g * 255 + 0.5)), b = tostring(floor(b * 255 + 0.5)) }
        for key, eb in pairs(pickerFields) do
            if eb ~= skip and not eb:HasFocus() then eb:SetText(v[key]) end
        end
    end

    local function Field(key, label, width, anchor)
        local t = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetText(label)
        if anchor then t:SetPoint("LEFT", anchor, "RIGHT", 10, 0) else t:SetPoint("LEFT", row, "LEFT", 4, 0) end
        local eb = CreateFrame("EditBox", nil, row)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetJustifyH("CENTER")
        eb:SetMaxLetters(key == "hex" and 32 or 24)
        eb:SetWidth(width)
        eb:SetHeight(18)
        eb:SetPoint("LEFT", t, "RIGHT", 4, 0)
        eb:SetTextInsets(3, 3, 0, 0)
        eb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        eb:SetBackdropColor(0, 0, 0, 0.6)
        eb:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        local function apply(self)
            local txt = self:GetText()
            local r, g, b = ParseColor(txt)
            if not r and key ~= "hex" then
                -- a single number in R, G or B
                local n = tonumber(txt)
                if n then
                    n = math.min(math.max(n, 0), 255) / 255
                    r, g, b = cp:GetColorRGB()
                    if key == "r" then r = n elseif key == "g" then g = n else b = n end
                end
            end
            if r then cp:SetColorRGB(r, g, b) end
            Refresh()
        end
        eb:SetScript("OnEnterPressed", function(self) apply(self); self:ClearFocus() end)
        eb:SetScript("OnTabPressed", function(self) apply(self); self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Refresh() end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        eb:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); Refresh() end)
        -- a pasted hex or "r, g, b" applies at once
        eb:SetScript("OnTextChanged", function(self, user)
            if not user then return end
            local txt = self:GetText()
            if (key == "hex" and ParseColor(txt) and (#txt:gsub("[#%s]", "") >= 6)) or txt:find("[,;]%s*[%d%.]+[,;%s]+[%d%.]+") then
                local r, g, b = ParseColor(txt)
                if r then cp:SetColorRGB(r, g, b); Refresh(key == "hex" and self or nil) end
            end
        end)
        pickerFields[key] = eb
        return eb
    end
    local hex = Field("hex", "#", 64)
    local r = Field("r", "R", 32, hex)
    local g = Field("g", "G", 32, r)
    Field("b", "B", 32, g)

    cp:HookScript("OnColorSelect", function() Refresh() end)
    cp:HookScript("OnShow", function() Refresh() end)
end

local function Color(parent, label, get, set, tip)
    local b = Row(parent, label, tip)
    local sw = CreateFrame("Frame", nil, b)
    A:Size(sw, 34, 14)
    sw:SetPoint("RIGHT", -2, 0)
    Box(sw, C.ctrl, C.ctrlBd)
    local fill = Solid(sw, "OVERLAY", 1, 1, 1)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local hex = Text(b, FS_SMALL, C.muted, "RIGHT")
    hex:SetPoint("RIGHT", sw, "LEFT", -8, 0)
    local text = b.label
    b.Refresh = function()
        local r, g, bl, a = get()
        fill:SetVertexColor(r, g, bl, max(a or 1, 0.15))
        local h = format("#%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, bl * 255 + 0.5)
        if a and a < 0.999 then h = h .. format("  %d%%", a * 100 + 0.5) end
        hex:SetText(h)
    end
    b:SetScript("OnClick", function()
        local r, g, bl, a = get()
        local function apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
            set(nr, ng, nb, na)
            b.Refresh()
        end
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - (a or 1)
        ColorPickerFrame.previousValues = { r, g, bl, a }
        ColorPickerFrame.func = apply
        ColorPickerFrame.opacityFunc = apply
        ColorPickerFrame.cancelFunc = function(prev)
            prev = prev or ColorPickerFrame.previousValues
            set(prev[1], prev[2], prev[3], prev[4])
            b.Refresh()
        end
        if not A.ColorPickerAdvanced or not A.ColorPickerAdvanced.ui then EnhanceColorPicker() end
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetColorRGB(r, g, bl)
        ColorPickerFrame:Hide()
        ShowUIPanel(ColorPickerFrame)
    end)
    b:HookScript("OnEnter", function() sw:SetBackdropBorderColor(AC()) end)
    b:HookScript("OnLeave", function() sw:SetBackdropBorderColor(C.ctrlBd[1], C.ctrlBd[2], C.ctrlBd[3]) end)
    b.Refresh()
    return b
end

local function Btn(parent, label, onClick, primary, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(h or 18)
    b.isButton = true
    local function paint(hover)
        local r, g, bl = AC()
        if b.primary then
            local k = hover and 0.7 or 0.5
            b:SetBackdropColor(r * k, g * k, bl * k, 1)
            b:SetBackdropBorderColor(r, g, bl, 1)
        elseif hover then
            b:SetBackdropColor(0.14, 0.14, 0.16, 1)
            b:SetBackdropBorderColor(r, g, bl, 1)
        else
            b:SetBackdropColor(0.09, 0.09, 0.105, 1)
            b:SetBackdropBorderColor(C.ctrlBd[1], C.ctrlBd[2], C.ctrlBd[3], 1)
        end
    end
    A:SetTemplate(b, 1)
    b.atrCustomBg = true
    b.text = Text(b, FS_LABEL, { 1, 1, 1 }, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b.natW = max(70, floor(b.text:GetStringWidth() + 20))
    b:SetWidth(b.natW)
    b.SetPrimary = function(self, on) self.primary = on; paint(false) end
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", function(self)
        PlaySound("igMainMenuOptionCheckBoxOn")
        onClick(self)
    end)
    b.primary = primary
    paint(false)
    return b
end

-- dropdown: options = { { value, "Text" }, ... }; one shared list for all of them
local dropList, dropCatcher
local function CloseDrop()
    if dropList then dropList:Hide() end
    if dropCatcher then dropCatcher:Hide() end
end

local function OpenDrop(owner, options, get, set, onDone)
    if not dropList then
        dropCatcher = CreateFrame("Button", nil, UIParent)
        dropCatcher:SetAllPoints(UIParent)
        dropCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        dropCatcher:SetFrameLevel(1)
        dropCatcher:RegisterForClicks("AnyUp")
        dropCatcher:SetScript("OnClick", CloseDrop)
        dropList = CreateFrame("Frame", nil, UIParent)
        dropList:SetFrameStrata("FULLSCREEN_DIALOG")
        dropList:SetFrameLevel(20)
        Box(dropList, { 0.05, 0.05, 0.06, 0.98 }, C.ctrlBd)
        dropList.items = {}
    end
    for _, it in ipairs(dropList.items) do it:Hide() end
    local w = owner:GetWidth()
    for i, opt in ipairs(options) do
        local it = dropList.items[i]
        if not it then
            it = CreateFrame("Button", nil, dropList)
            it:SetHeight(18)
            local hl = it:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(it)
            hl:SetTexture(1, 1, 1, 0.07)
            it.mark = Solid(it, "ARTWORK", AC())
            it.mark:SetWidth(2)
            it.mark:SetPoint("TOPLEFT")
            it.mark:SetPoint("BOTTOMLEFT")
            it.text = Text(it, FS_LABEL)
            it.text:SetPoint("LEFT", 10, 0)
            dropList.items[i] = it
        end
        -- long lists wrap into columns of 14
        local rows = math.min(#options, 14)
        local col, row = math.floor((i - 1) / rows), (i - 1) % rows
        it:ClearAllPoints()
        it:SetWidth(w - 2)
        it:SetPoint("TOPLEFT", dropList, "TOPLEFT", 1 + col * w, -1 - row * 18)
        it.text:SetText(opt[2])
        local selected = get() == opt[1]
        if selected then it.mark:Show(); it.text:SetTextColor(1, 1, 1)
        else it.mark:Hide(); it.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        it:SetScript("OnClick", function()
            set(opt[1])
            PlaySound("igMainMenuOptionCheckBoxOn")
            CloseDrop()
            if onDone then onDone() end
        end)
        it:Show()
    end
    local rows = math.min(#options, 14)
    dropList:SetWidth(w * math.ceil(#options / rows))
    dropList:SetHeight(rows * 18 + 2)
    dropList:ClearAllPoints()
    dropList:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    dropList:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    dropCatcher:Show()
    dropList:Show()
end

local function Dropdown(parent, label, options, get, set, tip)
    local f = Row(parent, label, tip)
    local b = CreateFrame("Button", nil, f)
    A:Size(b, CTRL_W, 16)
    b:SetPoint("RIGHT", -2, 0)
    Box(b, C.ctrl, C.ctrlBd)
    local v = Text(b, FS_LABEL, { 1, 1, 1 })
    v:SetPoint("LEFT", 6, 0)
    v:SetPoint("RIGHT", -20, 0)
    local arrow = Text(b, FS_SMALL, C.muted, "RIGHT")
    arrow:SetPoint("RIGHT", -7, 0)
    arrow:SetText("v")
    f.Refresh = function()
        local cur = get()
        for _, o in ipairs(options) do
            if o[1] == cur then v:SetText(o[2]) return end
        end
        v:SetText(tostring(cur))
    end
    b:SetScript("OnClick", function(self)
        if dropList and dropList:IsShown() then CloseDrop() return end
        OpenDrop(self, options, get, set, f.Refresh)
    end)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(AC()); arrow:SetTextColor(1, 1, 1); f.hl:Show() end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.ctrlBd[1], C.ctrlBd[2], C.ctrlBd[3])
        arrow:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        f.hl:Hide()
    end)
    Tooltip(b, label, tip)
    f.Refresh()
    return f
end

-- Important debuffs: one box to type into (adds on Enter, and filters the
-- list while typing), then a scrolling list: priority, icon, name, raid, and
-- small buttons to move an entry up / down or remove it.
local function ImportantList(parent)
    local VISIBLE, RH = 10, 18
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(20 + 4 + VISIBLE * RH + 2)
    local offset, shown = 0, {}

    local box = CreateFrame("EditBox", nil, f)
    box:SetHeight(20)
    box:SetPoint("TOPLEFT")
    box:SetPoint("TOPRIGHT")
    box:SetAutoFocus(false)
    A:SetFontPx(box, A.media.font, FS_LABEL, "")
    box:SetTextColor(1, 1, 1)
    box:SetTextInsets(8, 70, 0, 0)
    Box(box, C.ctrl, C.ctrlBd)
    local hint = Text(box, FS_SMALL, C.faint)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText("Type a debuff name or spell ID: Enter adds it, typing also searches the list")
    local count = Text(box, FS_SMALL, C.muted, "RIGHT")
    count:SetPoint("RIGHT", -8, 0)

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
    list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
    list:SetHeight(VISIBLE * RH + 2)
    Box(list, C.ctrl, C.ctrlBd)
    list:EnableMouseWheel(true)
    local empty = Text(list, FS_SMALL, C.faint, "CENTER")
    empty:SetPoint("CENTER")

    local function Changed()
        A:RefreshUnits()
        if A.RebuildFakeRaid then A:RebuildFakeRaid() end
        f.Refresh()
    end

    local function SmallBtn(row, tex, text, onClick)
        local b = CreateFrame("Button", nil, row)
        b:SetWidth(14); b:SetHeight(14)
        if tex then
            b.t = b:CreateTexture(nil, "ARTWORK")
            b.t:SetTexture(tex)
            b.t:SetAllPoints(b)
            b.t:SetVertexColor(0.6, 0.6, 0.65)
        else
            b.t = Text(b, FS_LABEL, C.muted, "CENTER")
            b.t:SetPoint("CENTER", 0, 1)
            b.t:SetText(text)
        end
        b:SetScript("OnEnter", function(self)
            self.t:SetVertexColor(1, 1, 1); if self.t.SetTextColor then self.t:SetTextColor(1, 1, 1) end
            row.hl:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.t:SetVertexColor(0.6, 0.6, 0.65)
            if self.t.SetTextColor then self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
            row.hl:Hide()
        end)
        b:SetScript("OnClick", function() onClick(row.index) end)
        return b
    end

    local rows = {}
    for r = 1, VISIBLE do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(RH)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1 - (r - 1) * RH)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -1 - (r - 1) * RH)
        row:EnableMouse(true)
        row.hl = Solid(row, "BACKGROUND", 1, 1, 1, 0.04)
        row.hl:SetAllPoints(row)
        row.hl:Hide()
        -- lined up with the text in the box above (8px in)
        row.num = Text(row, FS_SMALL, C.faint, "LEFT")
        row.num:SetPoint("LEFT", 7, 0)
        row.num:SetWidth(16)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(14); row.icon:SetHeight(14)
        row.icon:SetPoint("LEFT", row.num, "RIGHT", 2, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.del = SmallBtn(row, nil, "x", function(i)
            if A.RemoveImportantDebuff then A:RemoveImportantDebuff(i); Changed() end
        end)
        row.del:SetPoint("RIGHT", -4, 0)
        row.down = SmallBtn(row, "Interface\\Buttons\\Arrow-Down-Up", nil, function(i)
            if A.MoveImportantDebuff then A:MoveImportantDebuff(i, 1); Changed() end
        end)
        row.down:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
        row.up = SmallBtn(row, "Interface\\Buttons\\Arrow-Up-Up", nil, function(i)
            if A.MoveImportantDebuff then A:MoveImportantDebuff(i, -1); Changed() end
        end)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        -- the game's arrow art sits in one half of each texture (down: top
        -- half, up: bottom half): show just that half, centred, same size
        for _, b in ipairs({ row.up, row.down }) do
            b.t:ClearAllPoints()
            b.t:SetPoint("CENTER")
            b.t:SetWidth(12); b.t:SetHeight(6)
        end
        row.down.t:SetTexCoord(0, 1, 0, 0.5)
        row.up.t:SetTexCoord(0, 1, 0.5, 1)
        row.tag = Text(row, FS_SMALL, C.muted, "RIGHT")
        row.tag:SetPoint("RIGHT", row.up, "LEFT", -10, 0)
        row.name = Text(row, FS_LABEL)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)
        row:SetScript("OnEnter", function(self) self.hl:Show() end)
        row:SetScript("OnLeave", function(self) self.hl:Hide() end)
        rows[r] = row
    end

    function f.Refresh()
        local all = A.db.raidImportant or {}
        local filter = (box:GetText() or ""):lower()
        wipe(shown)
        for i, v in ipairs(all) do
            local label = A.ImportantDebuffLabel and A:ImportantDebuffLabel(v) or tostring(v)
            if filter == "" or label:lower():find(filter, 1, true) then shown[#shown + 1] = i end
        end
        offset = max(0, min(offset, #shown - VISIBLE))
        for r, row in ipairs(rows) do
            local i = shown[r + offset]
            if i then
                local v = all[i]
                row.index = i
                row.num:SetText(i)
                row.icon:SetTexture(A.ImportantDebuffIcon and A:ImportantDebuffIcon(i, true) or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.name:SetText(A.ImportantDebuffLabel and A:ImportantDebuffLabel(v) or tostring(v))
                local name = type(v) == "number" and GetSpellInfo(v) or v
                row.tag:SetText(A.importantSource and type(name) == "string" and A.importantSource[name:lower()] or "")
                if i == 1 then row.up:Hide() else row.up:Show() end
                if i == #all then row.down:Hide() else row.down:Show() end
                row:Show()
            else
                row:Hide()
            end
        end
        if #all == 0 then
            empty:SetText("The list is empty. Type a debuff above and press Enter.")
        elseif #shown == 0 then
            empty:SetText("Nothing matches \"" .. box:GetText() .. "\". Press Enter to add it.")
        else
            empty:SetText("")
        end
        count:SetText(filter == "" and (#all .. " debuffs") or (#shown .. " of " .. #all))
        -- names without a known icon: look them up in the background, then redraw
        if not f.scanned and A.ScanImportantIcons then
            f.scanned = true
            A:ScanImportantIcons(function() if f:IsVisible() then f.Refresh() end end)
        end
        if box:GetText() == "" then hint:Show() else hint:Hide() end
    end

    list:SetScript("OnMouseWheel", function(_, d)
        offset = offset - d * 3
        f.Refresh()
    end)
    box:SetScript("OnTextChanged", function() offset = 0; f.Refresh() end)
    box:SetScript("OnEnterPressed", function(self)
        local t = self:GetText()
        if t and t:match("%S") and A.AddImportantDebuff then
            A:AddImportantDebuff(t)
            f.scanned = false   -- find the new one's icon too
            self:SetText("")
            offset = #(A.db.raidImportant or {})   -- show the new one at the end
        end
        self:ClearFocus()
        f.Refresh()
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(AC()) end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C.ctrlBd[1], C.ctrlBd[2], C.ctrlBd[3]) end)
    f.Refresh()
    return f
end

------------------------------------------------------------------------
-- Cards and pages
------------------------------------------------------------------------
-- a section: title, optional one-line explanation, then one row per setting
-- (buttons sit side by side on their own row)
local function NewCard(page, title, desc)
    local c = CreateFrame("Frame", nil, page)
    c:SetWidth(CONTENT_W)
    Box(c, C.card, C.cardBd)
    local t = Text(c, FS_TITLE, { 1, 1, 1 })
    t:SetPoint("TOPLEFT", CARD_PAD, -8)
    t:SetText(title)
    c.title = title
    table.insert(page.index, { w = c, text = title, extra = desc, card = title })
    local mark = Solid(c, "ARTWORK", AC())
    mark:SetWidth(2)
    mark:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -8)
    mark:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", -CARD_PAD, 0)
    local y = 8 + 15
    if desc then
        local d = Text(c, FS_SMALL, C.muted)
        d:SetPoint("TOPLEFT", CARD_PAD, -y)
        d:SetWidth(INNER_W)
        d:SetJustifyV("TOP")
        d:SetText(desc)
        y = y + d:GetStringHeight() + 2
    end
    y = y + 4
    local btnX, btnH, rows = nil, 0, 0
    -- wide cards: settings two to a row (left column, then right)
    local twoCol = INNER_W >= TWO_COL_MIN
    local colW = twoCol and floor((INNER_W - COL_GAP) / 2) or INNER_W
    local colOpen, colH = false, 0

    local function endCol()
        if colOpen then y = y + colH + ROW_GAP; colOpen, colH = false, 0 end
    end
    local function endButtons()
        if btnX then y = y + btnH + 6; btnX, btnH = nil, 0 end
    end
    local function line()
        if rows > 0 then
            local l = Solid(c, "ARTWORK", C.line[1], C.line[2], C.line[3], C.line[4])
            l:SetHeight(1)
            l:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -y)
            l:SetPoint("TOPRIGHT", c, "TOPRIGHT", -CARD_PAD, -y)
        end
        rows = rows + 1
    end

    function c:Add(widget, span)
        if widget.Refresh then table.insert(page.widgets, widget) end
        local label = (widget.label and widget.label.GetText and widget.label:GetText())
            or (widget.isButton and widget.text and widget.text:GetText()) or widget.searchText
        if label then table.insert(page.index, { w = widget, text = label, extra = widget.tipText, card = title }) end
        widget:ClearAllPoints()
        if widget.isButton then
            -- buttons flow left to right
            endCol()
            local w = widget.natW or widget:GetWidth()
            if btnX and btnX + w > INNER_W then endButtons() end
            if not btnX then btnX = 0; y = y + 4 end
            widget:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD + btnX, -y)
            widget:SetWidth(w)
            btnX = btnX + w + 6
            btnH = max(btnH, widget:GetHeight())
            return widget
        end
        endButtons()
        -- plain setting rows share a line two by two; anything else is full width
        if twoCol and widget.label and span ~= "full" then
            if colOpen then
                widget:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD + colW + COL_GAP, -y)
                widget:SetWidth(colW)
                colH = max(colH, widget:GetHeight())
                endCol()
            else
                line()
                widget:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -y)
                widget:SetWidth(colW)
                colOpen, colH = true, widget:GetHeight()
            end
            return widget
        end
        endCol()
        line()
        widget:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -y)
        widget:SetWidth(INNER_W)
        y = y + widget:GetHeight() + ROW_GAP
        return widget
    end
    function c:Break() endCol(); endButtons() end
    function c:Finish()
        endCol()
        endButtons()
        self:SetHeight(y + CARD_PAD - 4)
    end
    page:AddCard(c)
    return c
end

local function NewPage(scroll)
    local p = CreateFrame("Frame", nil, scroll)
    p:SetWidth(CONTENT_W)
    p:SetHeight(10)
    p:Hide()
    p.widgets, p.cards, p.index = {}, {}, {}
    function p:AddCard(card) table.insert(self.cards, card) end
    function p:Layout()
        local y = 0
        for _, card in ipairs(self.cards) do
            card:Finish()
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
            y = y + card:GetHeight() + 6
        end
        self:SetHeight(max(y - 6, 10))
    end
    function p:RefreshAll()
        for _, wd in ipairs(self.widgets) do wd.Refresh() end
    end
    p:SetScript("OnShow", p.RefreshAll)
    return p
end

------------------------------------------------------------------------
-- Page definitions
------------------------------------------------------------------------
local function NeedReload() if A.config then A.config.NeedReload() end end
local function RefreshPage() if A.config and A.config.RefreshPage then A.config.RefreshPage() end end
local function Relayout() if A.RelayoutBars then A:RelayoutBars() end end

local function ModuleCheck(card, key, label)
    return card:Add(Check(card, label,
        function() return A.db.modules[key] end,
        function(v) A.db.modules[key] = v; NeedReload() end,
        "Turning a module on or off needs a reload."))
end

local function FontSlider(card, key, label)
    return card:Add(Slider(card, label or "Font size", 8, 16, 1,
        function() return A:FS(key) end,
        function(v) A.db.fontSizes[key] = v; NeedReload() end, nil, "Applied after a reload."))
end

local PAGES = {
    { group = "General" },
    { name = "General", desc = "Layout, scale and text rendering.", build = function(p)
        local c = NewCard(p, "Layout", "Positions are saved per account and restored every login.")
        c:Add(Btn(c, "Unlock UI  (move frames)", function() A.config:Hide(); A:Unlock() end, true))
        c:Add(Btn(c, "Reset all positions", function() A:ResetPositions() end))
        c:Add(Slider(c, "Unit + raid frame scale", 0.6, 1.6, 0.05,
            function() return A.db.scale end,
            function(v) A:SetScale(v) end, "%.2f"), "full")

        c = NewCard(p, "Background", "One colour and opacity for every frame: unit, raid, cast bars, chat, bags, tooltips, minimap, menus. Also the dark mode health colour.")
        c:Add(Color(c, "Background colour",
            function() local d = A.db.bg return d.r, d.g, d.b, d.a end,
            function(r, g, b, a)
                local d = A.db.bg
                d.r, d.g, d.b = r, g, b
                if a then d.a = a end
                A:RefreshBackdrops()
            end, "Colour and transparency of all frame backgrounds."))
        c:Add(Slider(c, "Background opacity", 0, 1, 0.05,
            function() return A.db.bg.a end,
            function(v) A.db.bg.a = v; A:RefreshBackdrops() end, "%.2f"))
        c:Add(Btn(c, "Reset background", function()
            local d = A.defaults.bg; A.db.bg = { r = d.r, g = d.g, b = d.b, a = d.a }
            A:RefreshBackdrops(); RefreshPage()
        end))

        c = NewCard(p, "Text")
        c:Add(Check(c, "Sharp pixel fonts",
            function() return A.db.fontMono end,
            function(v) A.db.fontMono = v; NeedReload() end,
            "Text without smoothing: very crisp at small sizes, a bit jagged at large ones. Needs a reload."))
        c:Add(Check(c, "Shadow instead of outline",
            function() return A.db.textShadow end,
            function(v) A.db.textShadow = v; NeedReload() end,
            "A solid 1px shadow under the text instead of the game's thin outline. Cleaner on bright bars. Needs a reload."))
        c:Add(Check(c, "Text on whole pixels",
            function() return A.db.alignText end,
            function(v) A.db.alignText = v; NeedReload() end,
            "Moves text so it never sits between two pixel rows (which blurs it). Needs a reload."))
        c:Add(Slider(c, "Default font size", 8, 14, 1,
            function() return A.db.fontSize end,
            function(v) A.db.fontSize = v; NeedReload() end, nil, "Applied after a reload."))

        c = NewCard(p, "Profile", "Every HUI setting (colours, sizes, positions, options) as one text. Copy it to keep or share it; paste one in to load it.")
        c:Add(Btn(c, "Export all settings", function() A:ShowExportAll() end, true))
        c:Add(Btn(c, "Import settings", function() A:ShowImportAll() end))

        c = NewCard(p, "Blizzard windows", "Character, spellbook, talents, quests, inspect, merchants, mail, options and more get the dark panel instead of parchment.")
        ModuleCheck(c, "skins", "Dark Blizzard windows")
        c:Add(Slider(c, "Window scale", 0.5, 1.2, 0.05,
            function() return A.db.windowScale or 1 end,
            function(v) A.db.windowScale = v; if A.ApplyWindowScale then A:ApplyWindowScale() end end, "%.2f",
            "Size of the game's windows: character, spellbook, talents, quest log, loot, mail, merchants, bank, options and more. The loot window moves with the rest of the UI in unlock mode."))
        c:Add(Slider(c, "Popup scale", 0.5, 1.2, 0.05,
            function() return A.db.popupScale or 1 end,
            function(v) A.db.popupScale = v; if A.ApplyPopupScale then A:ApplyPopupScale() end end, "%.2f",
            "Size of the game's popups: confirmations (delete item, battleground entry, ...), the dungeon finder ready and role check popups, the ready check and the Esc menu."))
        c:Add(Slider(c, "Raid warning size", 0.5, 1.2, 0.05,
            function() return A.db.raidWarnScale or 1 end,
            function(v) A.db.raidWarnScale = v; if A.ApplyRaidWarningScale then A:ApplyRaidWarningScale() end end, "%.2f",
            "Size of raid warnings and boss emotes in the middle of the screen."))
    end },

    { group = "Frames" },
    { name = "Unit Frames", desc = "Player, target, focus and pet.", build = function(p)
        local c = NewCard(p, "Health", "Health colors also apply to raid frames.")
        c:Add(Check(c, "Class colored health",
            function() return A.db.classBars end,
            function(v) A.db.classBars = v; A:RefreshUnits() end,
            "Off is dark mode: health bars use the background colour (General > Background)."))
        c:Add(Color(c, "Missing health color",
            function() local d = A.db.missingColor return d.r, d.g, d.b, 1 end,
            function(r, g, b)
                local d = A.db.missingColor
                d.r, d.g, d.b = r, g, b
                A:RefreshUnits()
            end))
        c:Add(Color(c, "Dead unit color",
            function() return A:DeadColor() end,
            function(r, g, b)
                A.db.deadColor = { r = r, g = g, b = b }
                A:RefreshUnits()
            end, "The whole frame of a dead (or ghost) player or mob: player, target, focus, party, raid, boss..."))
        c:Add(Check(c, "Boss frames only with 2+ bosses",
            function() return A.db.bossOnlyMulti ~= false end,
            function(v) A.db.bossOnlyMulti = v; if A.UpdateBossVisibility then A:UpdateBossVisibility() end end,
            "Single-boss fights show no boss frames (your target frame has the boss); councils like the Blood Prince Council, Twin Val'kyr or Four Horsemen show all of them. Off: boss frames for every boss."))
        c:Add(Check(c, "Combat icon on player frame",
            function() return A.db.combatIcon end,
            function(v) A.db.combatIcon = v; if A.UpdateCombatIcon then A:UpdateCombatIcon() end end,
            "Crossed swords in the middle of your health bar while you are in combat."))
        c:Add(Check(c, "Smooth health bars",
            function() return A.db.smoothHealth end,
            function(v) A.db.smoothHealth = v end,
            "Health bars glide to the new value instead of jumping (unit, party and raid frames), and so does the cooldown manager's power bar."))
        c:Add(Check(c, "Show power bars",
            function() return A.db.showPower end,
            function(v) A.db.showPower = v; NeedReload() end,
            "Mana, energy, rage and runic power. Needs a reload."))
        c:Add(Slider(c, "Power bar thickness (pixels)", 1, 12, 1,
            function() return A.db.powerHeight or 1 end,
            function(v) A.db.powerHeight = v; NeedReload() end, nil,
            "Height of the power bars under the health, in screen pixels. Needs a reload."))

        c = NewCard(p, "Auras")
        c:Add(Check(c, "Target: only my debuffs",
            function() return A.db.onlyMyDebuffs end,
            function(v) A.db.onlyMyDebuffs = v; A:RefreshUnits() end,
            "On enemies only. A friendly target always shows all its debuffs."), "full")
        c:Add(Check(c, "Player: hide debuffs",
            function() return A.db.hidePlayerDebuffs end,
            function(v) A.db.hidePlayerDebuffs = v; A:RefreshUnits() end,
            "No debuff icons above the player frame."), "full")
        c:Add(Slider(c, "Target: aura rows", 1, 4, 1,
            function() return A.db.targetAuraRows or 1 end,
            function(v) A.db.targetAuraRows = v; NeedReload() end, nil,
            "Rows of debuffs (left) and buffs (right) above the target frame; extra rows stack upwards. Applied after a reload."))

        c = NewCard(p, "Target: hidden debuffs", "Debuffs with these names never show on the target frame. Type a name (or spell id) and press Enter or Add.")
        local tbox = CreateFrame("EditBox", nil, c)
        tbox:SetHeight(22)
        tbox:SetAutoFocus(false)
        A:SetFontPx(tbox, A.media.font, FS_LABEL, "")
        tbox:SetTextInsets(8, 8, 0, 0)
        Box(tbox, C.ctrl, C.ctrlBd)
        local function addT(n)
            if n and n ~= "" then A:BlacklistTargetDebuff(n, true); A.config.RebuildPage() end
        end
        tbox:SetScript("OnEnterPressed", function(self) addT(self:GetText()); self:SetText(""); self:ClearFocus() end)
        tbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        c:Add(tbox, "full")
        c:Add(Btn(c, "Add", function() addT(tbox:GetText()); tbox:SetText("") end, true))
        c:Add(Btn(c, "Add debuffs shown on target", function()
            if not UnitExists("target") then return end
            -- the ones the frame shows: only yours on an enemy with "only my debuffs"
            local mineOnly = A.db.onlyMyDebuffs and UnitCanAttack("player", "target")
            for i = 1, 40 do
                local name, _, _, _, _, _, _, caster = UnitDebuff("target", i)
                if not name then break end
                if not mineOnly or caster == "player" or caster == "pet" or caster == "vehicle" then
                    A:BlacklistTargetDebuff(name, true)
                end
            end
            A.config.RebuildPage()
        end, false))
        local tnames = {}
        for _, n in pairs(A.db.targetDebuffBlacklist or {}) do tnames[#tnames + 1] = n end
        table.sort(tnames)
        for _, n in ipairs(tnames) do
            c:Add(Btn(c, "x   " .. n, function() A:BlacklistTargetDebuff(n, false); A.config.RebuildPage() end))
        end
        c:Add(Slider(c, "Icon size", 14, 40, 1,
            function() return A.db.auraSize end,
            function(v) A.db.auraSize = v; NeedReload() end, nil, "Applied after a reload."))
        c:Add(Slider(c, "Aura font size", 8, 20, 1,
            function() return A:FS("auras") end,
            function(v) A.db.fontSizes.auras = v; NeedReload() end, nil, "Applied after a reload."))

        c = NewCard(p, "Cast bars", "Player, target and focus cast bars.")
        c:Add(Check(c, "Show total cast time",
            function() return A.db.castbar.showTotal end,
            function(v) A.db.castbar.showTotal = v end,
            "Time left and the whole cast, like \"0.5 / 2.3\". Off: only the time left."))
        c:Add(Check(c, "Channel ticks",
            function() return A.db.castbar.ticks end,
            function(v) A.db.castbar.ticks = v end,
            "Thin marks where each tick of a channelled spell lands: Mind Flay, Mind Sear, Penance, Drain Life / Soul, Hellfire, Arcane Missiles, Evocation, Blizzard, Tranquility, Hurricane, Volley, bandages... Shown from the next channel."))
        c:Add(Check(c, "Hide my cast bar",
            function() return A.db.castbar.hidePlayer end,
            function(v)
                A.db.castbar.hidePlayer = v
                if A.playerCastbar then
                    if v then A.playerCastbar:Hide() else A:CastbarCheck(A.playerCastbar) end
                end
            end, "Your own cast bar never shows. Target and focus cast bars stay."))
        c:Add(Check(c, "DPS / tank: fit between player and target",
            function() return A.db.castbar.fitBetween ~= false end,
            function(v)
                A.db.castbar.fitBetween = v
                A.raidPosKey = nil
                if A.UpdateRaidSpecPosition then A:UpdateRaidSpecPosition() end
            end, "Outside a healing spec your cast bar fills the gap between the player and target frames, 1px from each, at its own height (move it up or down in unlock mode). Off: its own size and spot. Healers keep the healer layout."))

        c = NewCard(p, "Text")
        FontSlider(c, "units")
    end },

    { name = "Cooldown Manager", desc = "Your spells between the player and target frames, under your cast bar: swing timers, a power bar and two rows of icons with cooldowns, your debuffs / buffs and proc glows. Loads in DPS and tank specs only; saved per character and talent spec.", build = function(p)
        local d = A.db.cdm
        local CDM = A.CDM
        local function Upd() if A.RefreshCDM then A:RefreshCDM() end end
        local top = NewCard(p, "Cooldown Manager")
        top:Add(Check(top, "Enable cooldown manager", function() return d.enabled end, function(v) d.enabled = v; Upd() end,
            "Off: no icons, power bar or swing timers in game, and your cast bar goes back to its own spot. Your layouts are kept."))
        if CDM then
            CDM:InitEditSpec()
            local c = NewCard(p, "Layout", "The live preview below is the real thing. Drag icons to reorder them or between rows, drag one off to remove it, right-click one for its conditions (glow when your debuff is missing, hide on cooldown...). Drop spells from your spellbook on the + slots.")
            c:Add(Dropdown(c, "Layout for spec", CDM:EditableSpecs(),
                function() return CDM.editSpec end,
                function(v) CDM:SetEditSpec(v) end,
                "Each talent tree has its own layout. Your current spec is the one shown in game."))
            local box = CDM:CreatePreviewBox(c, 190)
            box.searchText = "Preview"
            c:Add(box, "full")
            c:Add(Btn(c, "Reset spec to class default", function()
                if IsShiftKeyDown() then CDM:ResetSpec(CDM.editSpec) else A:Print("cooldown manager: hold Shift and click to replace this spec's layout with the class default.") end
            end))
            c:Add(Btn(c, "Export class layouts", function() A:CDMExportClass() end))

            c = NewCard(p, "Spells", "Click a spell to add it to the top row, Shift-click for the bottom row, click an added one (green dot) to remove it. Spells with a cooldown come first.")
            local list = CDM:CreatePicker(c, INNER_W)
            list.searchText = "Spell list"
            c:Add(list, "full")
        end

        local c = NewCard(p, "Appearance", "Unlock UI to move it in game (right-click its box there to put it back between the frames).")
        c:Add(Check(c, "Cast bar on top (same width)", function() return d.castbarOnTop end,
            function(v) d.castbarOnTop = v; Upd() end,
            "Your cast bar sits 1px above the cooldown manager (or its swing timers), as wide as it."))
        c:Add(Slider(c, "Top row icon size", 16, 64, 1, function() return d.size end, function(v) d.size = v; Upd() end))
        c:Add(Slider(c, "Bottom row icon size", 12, 64, 1, function() return d.smallSize end, function(v) d.smallSize = v; Upd() end))
        c:Add(Slider(c, "Spacing (pixels)", 0, 10, 1, function() return d.spacing end, function(v) d.spacing = v; Upd() end))
        c:Add(Slider(c, "Power bar height (0 = off)", 0, 30, 1, function() return d.powerHeight end, function(v) d.powerHeight = v; Upd() end))
        c:Add(Check(c, "Power text", function() return d.powerText end, function(v) d.powerText = v; Upd() end))
        c:Add(Dropdown(c, "Power text shows", { { "smart", "% for mana, else number" }, { "pct", "Percent" }, { "value", "Number" } },
            function() return d.powerFormat end, function(v) d.powerFormat = v; Upd() end,
            "Rage, energy and runic power read best as the number (76), mana as a percentage (66%)."))
        c:Add(Slider(c, "Out of combat opacity", 0, 1, 0.05, function() return d.oocAlpha end, function(v) d.oocAlpha = v; Upd() end, "%.2f"))
        c:Add(Check(c, "Hide in vehicles", function() return d.hideVehicle end, function(v) d.hideVehicle = v; Upd() end))

        c = NewCard(p, "Swing timers", "Above the power bar, same width: main hand, off hand when dual wielding, and ranged (Auto Shot) for hunters, who also get the melee bars for weaving. Melee bars are grey, orange while Heroic Strike (Maul, Raptor Strike, Rune Strike) is queued and green while Cleave is. Heroic Strike, Cleave, Maul, Raptor Strike and Slam reset the main hand.")
        c:Add(Check(c, "Show swing timers", function() return d.swing end, function(v) d.swing = v; Upd() end))
        c:Add(Slider(c, "Bar height", 2, 20, 1, function() return d.swingHeight end, function(v) d.swingHeight = v; Upd() end))
        c:Add(Check(c, "Seconds left on the bars", function() return d.swingText end, function(v) d.swingText = v end))
        c:Add(Check(c, "Wand bar for casters", function() return d.swingWand end, function(v) d.swingWand = v; Upd() end,
            "Mages, warlocks and priests: a ranged bar for wand Shoot."))

        c = NewCard(p, "Icons")
        c:Add(Check(c, "Grey while on cooldown", function() return d.desaturate end, function(v) d.desaturate = v end))
        c:Add(Check(c, "Global cooldown swipe", function() return d.showGCD end, function(v) d.showGCD = v end))
        c:Add(Check(c, "Red when out of range", function() return d.rangeColor end, function(v) d.rangeColor = v end))
        c:Add(Check(c, "Blue when out of power", function() return d.powerColor end, function(v) d.powerColor = v end))
        c:Add(Check(c, "Show my debuff / buff time", function() return d.auras end, function(v) d.auras = v end,
            "While the spell's debuff is on your target (yours only), or its buff on you or your pet, the icon shows the time left instead of the cooldown. Right-click an icon in the preview to track a different aura."))
        c:Add(Check(c, "Gold border while it's up", function() return d.auraBorder end, function(v) d.auraBorder = v end))

        c = NewCard(p, "Glow", "The same glows as WeakAuras.")
        c:Add(Dropdown(c, "Glow type", A.Glow and A.Glow.kinds or { { "button", "Action Button Glow" } },
            function() return d.glowType end, function(v) d.glowType = v; Upd() end))
        c:Add(Check(c, "Built-in proc glows", function() return d.procs end, function(v) d.procs = v end,
            "Rime, Killing Machine, Sudden Death, Bloodsurge, Sword and Board, Hot Streak, Brain Freeze, Fingers of Frost, Missile Barrage, Lock and Load, Art of War, Maelstrom Weapon x5, Eclipse, Molten Core, Decimation, Nightfall, Backlash... and reactive abilities (Revenge, Overpower, Execute, Victory Rush, Kill Shot, Hammer of Wrath, Rune Strike...)."))
        c:Add(Check(c, "Custom glow color", function() return d.glowCustom end, function(v) d.glowCustom = v; Upd() end))
        c:Add(Color(c, "Glow color",
            function() local k = d.glowColor return k.r, k.g, k.b, k.a or 1 end,
            function(r, g, b, a) local k = d.glowColor k.r, k.g, k.b, k.a = r, g, b, a or 1; Upd() end))
    end },
    { name = "Party Frames", desc = "Five frames like the player frame, stacked, with pets on the left. Shown in a party, hidden in a raid.", build = function(p)
        local function P() return A.db.party end
        local function Apply()
            if not A.LayoutParty then return end
            if InCombatLockdown() then A.partyDirty = true else A:LayoutParty() end
        end
        local function PS(c, label, key, lo, hi, step)
            return c:Add(Slider(c, label, lo, hi, step or 1,
                function() return P()[key] end,
                function(v) P()[key] = v; Apply() end))
        end
        local function PC(c, label, key, tip)
            return c:Add(Check(c, label,
                function() return P()[key] end,
                function(v) P()[key] = v; Apply() end, tip))
        end
        local c = NewCard(p, "Party frames", "Changes apply right away (after combat if you are fighting).")
        ModuleCheck(c, "party", "Enable party frames")
        if not A.db.party then
            c:Add(Btn(c, "Reload to set up the party frames", function() ReloadUI() end, true))
            return
        end
        c:Add(Btn(c, "Test: show all five", function()
            if A.SetPartyTest then A:SetPartyTest(not A.partyTest) end
        end, true))
        c:Add(Btn(c, "Unlock UI  (move them)", function() A.config:Hide(); A:Unlock() end))

        c = NewCard(p, "Size")
        PS(c, "Width", "width", 60, 320)
        PS(c, "Height", "height", 12, 80)
        PS(c, "Power bar height (0 = none)", "power", 0, 12)
        PS(c, "Gap between frames (px)", "gap", 0, 20)
        PC(c, "You are the first frame", "showPlayer")
        PC(c, "Grow upwards", "growUp", "Off: the first frame is on top.")
        PC(c, "Show when not in a group", "showSolo", "Shows your own frame (and pet) when solo.")
        PC(c, "Fade players out of range", "range", "Like the raid frames: out of range 40%, offline 35%. Pets fade with their owner.")

        c = NewCard(p, "Text")
        PS(c, "Font size", "fontSize", 8, 20)
        PS(c, "Name length", "nameLen", 4, 30)
        c:Add(Dropdown(c, "Health text", {
                { "both", "12.3K | 85%" }, { "pct", "85%" }, { "cur", "12.3K" },
                { "deficit", "-2.1K (missing)" }, { "none", "None" } },
            function() return P().hpFormat end,
            function(v) P().hpFormat = v; Apply() end))

        c = NewCard(p, "Pets", "Each member's pet sits on the left of their frame.")
        PC(c, "Show pets", "showPets")
        PS(c, "Pet width", "petWidth", 20, 160)
        PS(c, "Gap to the frame (px)", "petGap", 0, 20)

        c = NewCard(p, "Debuffs", "On the right of each frame. Debuffs you can dispel colour the border.")
        PC(c, "Show debuffs", "debuffs")
        PS(c, "Number", "debuffNum", 1, 8)
        PS(c, "Size", "debuffSize", 10, 48)
    end },

    { name = "Raid Frames", desc = "One row (or column) per raid group. With the party frames on, these show only in a raid.", build = function(p)
        local function R() return A.db.raidLayout or A.raidDefaults end
        local function RS(c, label, key, lo, hi, step, tip)
            return c:Add(Slider(c, label, lo, hi, step or 1,
                function() return R()[key] end,
                function(v) A.db.raidLayout = A.db.raidLayout or {}; A.db.raidLayout[key] = v; NeedReload() end, nil, tip))
        end
        local c = NewCard(p, "Raid frames", "Size and layout apply after a reload. Health colors follow the Unit Frames page.")
        ModuleCheck(c, "raid", "Enable raid frames")
        c:Add(Btn(c, "Test: 25-player raid", function()
            if A.SetRaidTest then A:SetRaidTest(not A.raidTest) end
        end, true))
        c:Add(Check(c, "Fade players out of range",
            function() return A.db.raidRange end,
            function(v) A.db.raidRange = v end))
        c:Add(Check(c, "Show missing health (-12.3K)",
            function() return A.db.raidDeficit end,
            function(v) A.db.raidDeficit = v; A:RefreshUnits() end))

        c = NewCard(p, "Important debuffs", "Debuffs that always show as a big icon in the middle of the raid and party frame of whoever has them. Higher in the list wins when someone has two: use the arrows to change the order.")
        local imp = c:Add(ImportantList(c), "full")
        c:Add(Btn(c, "Clear list", function()
            StaticPopupDialogs["HUI_CLEAR_IMPORTANT"] = StaticPopupDialogs["HUI_CLEAR_IMPORTANT"] or {
                text = "Remove every debuff from the important debuffs list?",
                button1 = YES, button2 = NO,
                timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
            }
            StaticPopupDialogs["HUI_CLEAR_IMPORTANT"].OnAccept = function()
                wipe(A.db.raidImportant or {})
                if A.RebuildImportantDebuffs then A:RebuildImportantDebuffs() end
                A:RefreshUnits()
                if A.RebuildFakeRaid then A:RebuildFakeRaid() end
                imp.Refresh()
            end
            StaticPopup_Show("HUI_CLEAR_IMPORTANT")
        end))

        c = NewCard(p, "Layout")
        RS(c, "Button width (0 = fit the chat width)", "width", 0, 200)
        c:Add(Check(c, "Keep the shape (height follows width)",
            function() return R().lockAspect ~= false end,
            function(v) A.db.raidLayout = A.db.raidLayout or {}; A.db.raidLayout.lockAspect = v; NeedReload() end,
            "Buttons keep the same width : height ratio at any width. Off: use the height below."))
        RS(c, "Button height (shape off)", "height", 16, 80)
        RS(c, "Gap (px)", "gap", 0, 10)
        c:Add(Dropdown(c, "Growth direction", { { "COLUMNS", "Down, then right" }, { "ROWS", "Right, then down" } },
            function() return R().layout end,
            function(v) A.db.raidLayout = A.db.raidLayout or {}; A.db.raidLayout.layout = v; NeedReload() end,
            "Down, then right: each group is a column, groups side by side. Right, then down: each group is a row, groups stacked. Needs a reload."))

        c = NewCard(p, "Text and debuffs")
        FontSlider(c, "raid")
        RS(c, "Name length", "nameLen", 3, 20)
        RS(c, "Debuffs", "debuffNum", 0, 6)
        RS(c, "Debuff size", "debuffSize", 8, 32)
    end },

    { group = "Interface" },
    { name = "Action Bars", desc = "Two rows of 24 at the bottom, bar 5 beside the chat, pet bar bottom right. Unlock UI to move them.", build = function(p)
        local c = NewCard(p, "Module")
        ModuleCheck(c, "actionbars", "Enable action bars")
        c:Add(Btn(c, "Quick keybind mode", function()
            A.config:Hide()
            if A.StartKeybindMode then A:StartKeybindMode() end
        end, true))

        c = NewCard(p, "Mouseover",
            "Bars on mouseover stay hidden until the mouse is over them. They also show while unlocked, in keybind mode and while dragging a spell. Bar 5 and the pet bar are always on mouseover.")
        c:Add(Check(c, "All action bars on mouseover",
            function() return A.AllBarsMouseover and A:AllBarsMouseover() end,
            function(v) if A.SetAllBarsMouseover then A:SetAllBarsMouseover(v) end; RefreshPage() end), "full")
        for _, key in ipairs(A.BAR_KEYS or {}) do
            if not (A.BAR_ALWAYS_MOUSEOVER and A.BAR_ALWAYS_MOUSEOVER[key]) then
            c:Add(Check(c, A.BAR_LABELS[key],
                function() return A.db.barMouseover[key] end,
                function(v) A.db.barMouseover[key] = v; RefreshPage() end))
            end
        end
        c:Add(Check(c, "Bag button on mouseover",
            function() return A.db.menusMouseover end,
            function(v) A.db.menusMouseover = v end), "full")

        c = NewCard(p, "Layout")
        c:Add(Slider(c, "Button size", 16, 44, 1,
            function() return A.db.abSize end,
            function(v) A.db.abSize = v; Relayout() end))
        c:Add(Slider(c, "Button spacing (-1 = shared border)", -1, 6, 1,
            function() return A.db.abSpacing end,
            function(v) A.db.abSpacing = v; Relayout() end))
        c:Add(Check(c, "Bar 5 and pet bar as tall as the chat",
            function() return A.db.fitChatBars end,
            function(v) A.db.fitChatBars = v; Relayout() end,
            "Their buttons grow so the 2 x 5 block matches the chat box height."))

        c = NewCard(p, "Text")
        c:Add(Check(c, "Cooldown numbers on buttons",
            function() return A.db.cdNumbers ~= false end,
            function(v) A.db.cdNumbers = v end,
            "Seconds left, centred on the button. Applies from the next cooldown."))
        c:Add(Check(c, "Show keybinds",
            function() return A.db.showHotkeys end,
            function(v) A.db.showHotkeys = v; Relayout() end))
        c:Add(Check(c, "Show macro names",
            function() return A.db.showMacro end,
            function(v) A.db.showMacro = v; Relayout() end))
        FontSlider(c, "actionbars")
    end },

    { name = "Buffs", desc = "Your buffs and debuffs next to the minimap. Right-click a buff to cancel it.", build = function(p)
        local c = NewCard(p, "Buffs")
        ModuleCheck(c, "buffs", "Enable buff skin")
        c:Break()
        c:Add(Slider(c, "Buff size", 0.6, 1.6, 0.05,
            function() return A.db.buffScale end,
            function(v) if A.SetBuffScale then A:SetBuffScale(v) else A.db.buffScale = v end end, "%.2f"))
        FontSlider(c, "buffs")
    end },

    { name = "Bags", desc = "All carried bags in one frame. Bank and keyring keep the default frames.", build = function(p)
        local c = NewCard(p, "Bags")
        ModuleCheck(c, "bags", "Enable one bag")
        c:Break()
        c:Add(Slider(c, "Columns", 8, 20, 1,
            function() return A.db.bagCols end,
            function(v) A.db.bagCols = v; if A.RefreshBags then A:RefreshBags() end end))
        c:Add(Check(c, "Search box", function() return A.db.bagSearch ~= false end,
            function(v) A.db.bagSearch = v; if A.RefreshBags then A:RefreshBags() end end,
            "Type to fade every item that doesn't match: by name, type, sub type or slot (\"potion\", \"plate\", \"trinket\"). Esc clears it."))
        c:Add(Check(c, "Item level on gear", function() return A.db.bagItemLevel end,
            function(v) A.db.bagItemLevel = v; if A.RefreshBags then A:RefreshBags() end end,
            "Item level in the top-left corner of armour and weapons, in the item's quality colour."))
        FontSlider(c, "bags")
    end },

    { name = "Chat", desc = "Dark chat box with a tab header. Mouse wheel scrolls, Shift jumps to top / bottom.", build = function(p)
        local function chatOn() return A.db.modules.chat end
        local c = NewCard(p, "Chat box")
        ModuleCheck(c, "chat", "Enable chat skin")
        c:Add(Check(c, "Same width as raid frames",
            function() return (A.db.chatWidth or 0) <= 0 end,
            function(v)
                local _, w = A:RaidChatWidths()
                A.db.chatWidth = v and 0 or floor(w + 0.5)
                if A.ResizeChat then A:ResizeChat() end
                RefreshPage()
            end, "Lines the chat box up with the raid frames above it."))
        c:Add(Slider(c, "Width", 200, 700, 1,
            function() local w = A.db.chatWidth or 0 if w <= 0 then local _, rw = A:RaidChatWidths() w = floor(rw + 0.5) end return w end,
            function(v) A.db.chatWidth = v; if A.ResizeChat then A:ResizeChat() end; RefreshPage() end))
        c:Add(Slider(c, "Height", 100, 400, 1,
            function() return A.db.chatHeight end,
            function(v) A.db.chatHeight = v; if A.ResizeChat then A:ResizeChat() end end))
        c:Add(Dropdown(c, "Edit box", { { "TOP", "Over the tabs" }, { "BOTTOM", "Below the chat box" } },
            function() return A.db.chatEditBox end,
            function(v) A.db.chatEditBox = v; if A.PlaceChatEditBoxes then A:PlaceChatEditBoxes() end end))

        c = NewCard(p, "Tabs", "Global, Loot, Guild, Whisper and Raid/Party.")
        c:Add(Check(c, "Set up tabs on new characters",
            function() return A.db.chatAutoTabs end,
            function(v) A.db.chatAutoTabs = v end, "Done once per character, the first time you log in with it."))
        c:Add(Btn(c, "Set up tabs now", function() if A.SetupChatTabs then A:SetupChatTabs() end end))
        c:Add(Check(c, "No combat log tab",
            function() return A.db.chatHideCombatLog end,
            function(v)
                A.db.chatHideCombatLog = v
                if v then A:HideCombatLog() elseif FCF_DockFrame and ChatFrame2 then
                    pcall(FCF_DockFrame, ChatFrame2, 2); ChatFrame2:Show(); if ChatFrame2Tab then ChatFrame2Tab:Show() end
                end
            end, "Closes the combat log window. Combat log events still work for other addons."))

        c = NewCard(p, "Messages")
        c:Add(Dropdown(c, "Timestamps", {
                { "NONE", "Off" }, { "HH:MM", "[14:05]" }, { "HH:MM:SS", "[14:05:09]" }, { "12H", "[02:05 PM]" } },
            function() return A.db.chatTimestamps end,
            function(v) A.db.chatTimestamps = v; if v ~= "NONE" then SetCVar("showTimestamps", "none") end end,
            "Applies to new messages."))
        c:Add(Color(c, "Timestamp color",
            function() local d = A.db.chatTsColor return d.r, d.g, d.b, 1 end,
            function(r, g, b) local d = A.db.chatTsColor d.r, d.g, d.b = r, g, b end))
        c:Add(Check(c, "Short channel names",
            function() return A.db.chatShortChannels end,
            function(v) A.db.chatShortChannels = v; if A.ApplyShortChannels then A:ApplyShortChannels() end end,
            "[2. Trade - City] becomes [2], [Guild] becomes [G], [Raid Leader] becomes [RL]."))
        c:Add(Check(c, "Hide opposing faction messages",
            function() return A.db.chatHideOtherFaction end,
            function(v) A.db.chatHideOtherFaction = v end,
            "Says, yells and emotes in a language you don't speak (\"[Orcish] AAZ GOLAR...\") are hidden. Channels, NPCs and your own faction are not touched."))
        c:Add(Check(c, "Clickable web links",
            function() return A.db.chatURLs end,
            function(v) A.db.chatURLs = v end, "Click a link in chat to get a box you can copy it from."))
        c:Add(Check(c, "Class colored names",
            function() return A.db.chatClassNames end,
            function(v) A.db.chatClassNames = v; if A.ApplyChatClassColors then A:ApplyChatClassColors() end end))
        c:Add(Check(c, "Keep tabs visible",
            function() return A.db.chatTabsVisible end,
            function(v) A.db.chatTabsVisible = v; if A.ApplyChatTabs then A:ApplyChatTabs() end end,
            "Tabs stay fully visible instead of fading when the mouse leaves the chat."))
        c:Add(Check(c, "Copy button (on mouseover)",
            function() return A.db.copy.chatButton end,
            function(v) A.db.copy.chatButton = v end, "A small C button in the chat box opens its text in a copy box."))
        c:Break()
        c:Add(Slider(c, "Chat font size", 8, 16, 1,
            function() return A.db.chatFontSize end,
            function(v)
                if A.SetChatFontSize and A.db.modules.chat then A:SetChatFontSize(v) else A.db.chatFontSize = v end
            end))
        c:Add(Slider(c, "Lines kept", 128, 1000, 1,
            function() return A.db.chatHistory end,
            function(v) A.db.chatHistory = v; NeedReload() end, nil, "Applied after a reload."))

        c = NewCard(p, "Fading")
        c:Add(Check(c, "Fade old messages",
            function() return A.db.chatFade end,
            function(v) A.db.chatFade = v; if A.ApplyChatFading then A:ApplyChatFading() end end))
        c:Add(Slider(c, "Seconds before fading", 5, 120, 1,
            function() return A.db.chatFadeTime end,
            function(v) A.db.chatFadeTime = v; if A.ApplyChatFading then A:ApplyChatFading() end end))
        local function Idle() if A.ResetChatIdle then A:ResetChatIdle() end end
        c:Add(Check(c, "Show only on mouseover",
            function() return A.db.chatMouseover end,
            function(v) A.db.chatMouseover = v; Idle() end,
            "The whole chat (box, messages, tabs) and the combat timer disappear after the time below. Hover where the chat is to bring it back; it also stays while you type."))
        c:Add(Slider(c, "Hide after (seconds)", 1, 60, 1,
            function() return A.db.chatMouseoverDelay end,
            function(v) A.db.chatMouseoverDelay = v; Idle() end, nil, "Counted from when the mouse leaves the chat."))
        c = NewCard(p, "Chat bubbles", "Speech bubbles as a dark box with a 1px black border.")
        c:Add(Check(c, "Skin chat bubbles", function() return A.db.bubbles end,
            function(v) A.db.bubbles = v; NeedReload() end, "Turning it off needs a reload."))
        c:Add(Slider(c, "Bubble font size", 8, 20, 1, function() return A.db.bubbleFontSize end,
            function(v) A.db.bubbleFontSize = v end, nil, "Applies to the next bubble that appears."))
    end },

    { name = "Minimap", desc = "Square minimap with mouse-wheel zoom. XP / rep bars hang underneath.", build = function(p)
        local function Resize() if A.ResizeMinimap then A:ResizeMinimap() end end
        local c = NewCard(p, "Minimap")
        ModuleCheck(c, "minimap", "Enable minimap skin")
        c:Add(Check(c, "White zone names", function() return A.db.zoneTextWhite end,
            function(v) A.db.zoneTextWhite = v; if v then A:WhiteZoneText(); if MinimapZoneText then MinimapZoneText:SetTextColor(1, 1, 1) end end end,
            "On the minimap and the big text when you enter a zone. Off: coloured by PvP status (after a zone change)."))
        c:Add(Slider(c, "Size", 100, 260, 1,
            function() return A.db.mmSize end,
            function(v) A.db.mmSize = v; Resize() end))
        c:Add(Dropdown(c, "Visibility", {
                { "ALWAYS", "Always" }, { "COMBAT", "Hide in combat" }, { "MOUSEOVER", "Only on mouseover" } },
            function() return A.db.mmVisibility end,
            function(v) A.db.mmVisibility = v end))

        c = NewCard(p, "Text")
        c:Add(Dropdown(c, "Zone name", { { "ALWAYS", "Always" }, { "MOUSEOVER", "On mouseover" }, { "HIDDEN", "Hidden" } },
            function() return A.db.mmZone end,
            function(v) A.db.mmZone = v end))
        c:Add(Dropdown(c, "Coordinates", { { "NEVER", "Off" }, { "HOVER", "On mouseover" }, { "ALWAYS", "Always" } },
            function() return A.db.mmCoords end,
            function(v) A.db.mmCoords = v end))
        c:Add(Check(c, "Clock / FPS / MS strip",
            function() return A.db.showInfo end,
            function(v) if A.SetMinimapInfo then A:SetMinimapInfo(v) else A.db.showInfo = v end end))
        c:Add(Check(c, "24-hour clock",
            function() return A.db.mmClock24 end,
            function(v) A.db.mmClock24 = v end))
        c:Add(Check(c, "Realm time (instead of local)",
            function() return A.db.mmClockRealm end,
            function(v) A.db.mmClockRealm = v end))
        c:Break()
        FontSlider(c, "minimap")

        c = NewCard(p, "Zoom and clicks")
        c:Add(Slider(c, "Reset zoom after (sec, 0 = off)", 0, 30, 1,
            function() return A.db.mmZoomReset end,
            function(v) A.db.mmZoomReset = v end))
        c:Break()
        c:Add(Check(c, "Right-click: tracking menu",
            function() return A.db.mmRightTracking end,
            function(v) A.db.mmRightTracking = v end))
        c:Add(Check(c, "Middle-click: game menu list",
            function() return A.db.mmMiddleMenu end,
            function(v) A.db.mmMiddleMenu = v end,
            "Character, spellbook, talents, quest log, social, calendar, game menu and so on (the old micro menu)."))

        c = NewCard(p, "Addon buttons", "Addon minimap buttons, the calendar and tracking sit in a row under the map.")
        c:Add(Check(c, "Only on mouseover",
            function() return A.db.grabberMouseover end,
            function(v) A.db.grabberMouseover = v end, "The row shows while the mouse is over the minimap or the row."))
    end },

    { name = "Nameplates", desc = "Health bar with name and health inside, cast bar with icon and spell name, your debuffs on your target.", build = function(p)
        local d = A.db.nameplates
        local function Upd() if A.RefreshNameplates then A:RefreshNameplates() end end
        local c = NewCard(p, "Preview", "Changes show here right away (and on the plates in the world).")
        if A.CreatePlatePreview then c:Add(A:CreatePlatePreview(c), "full") end

        c = NewCard(p, "Nameplates")
        ModuleCheck(c, "nameplates", "Enable nameplate skin")
        c:Add(Check(c, "Always show enemy nameplates", function() return d.showEnemies end,
            function(v) d.showEnemies = v; Upd() end, "Same as the game's enemy nameplate toggle (V)."))
        c:Add(Check(c, "Smooth stacking", function() return d.smoothStack end,
            function(v) d.smoothStack = v; Upd() end,
            "Plates that would overlap slide apart smoothly, the lower one stays put. Replaces the game's jumpy spreading."))
        c:Add(Check(c, "Game's own spreading (if smooth is off)", function() return d.stack end,
            function(v) d.stack = v; Upd() end, "Both off: plates overlap each other."))
        c:Add(Check(c, "Shorten long names", function() return d.shortNames end,
            function(v) d.shortNames = v; Upd() end,
            "Names that don't fit: \"Scarlet Crusade Champion\" becomes \"S. C. Champion\"."))
        c:Add(Check(c, "Hide neutral nameplates", function() return d.hideNeutral end,
            function(v) d.hideNeutral = v; Upd() end, "Yellow (neutral) units get no nameplate."))

        c = NewCard(p, "Health bar")
        c:Add(Slider(c, "Width", 60, 300, 1, function() return d.width end, function(v) d.width = v; Upd() end))
        c:Add(Slider(c, "Height", 4, 30, 1, function() return d.height end, function(v) d.height = v; Upd() end))
        c:Add(Check(c, "Own color for enemies", function() return d.customHostile end,
            function(v) d.customHostile = v; Upd() end, "Off: the game's bright red."))
        c:Add(Color(c, "Enemy bar color",
            function() local k = d.hostileColor return k.r, k.g, k.b, 1 end,
            function(r, g, b) local k = d.hostileColor k.r, k.g, k.b = r, g, b; Upd() end))
        c:Add(Check(c, "Own color for neutrals", function() return d.customNeutral end,
            function(v) d.customNeutral = v; Upd() end, "Off: the game's yellow."))
        c:Add(Color(c, "Neutral color",
            function() local k = d.neutralColor or { r = 0.75, g = 0.6, b = 0.15 } return k.r, k.g, k.b, 1 end,
            function(r, g, b)
                d.neutralColor = d.neutralColor or {}
                local k = d.neutralColor
                k.r, k.g, k.b = r, g, b
                d.customNeutral = true   -- picking a colour turns it on
                Upd()
            end, "Picking a colour also turns \"Own color for neutrals\" on."))
        c:Add(Dropdown(c, "Health text", { { "BOTH", "865M | 88%" }, { "VALUE", "865M" }, { "PERCENT", "88%" }, { "NONE", "Off" } },
            function() return d.healthText end, function(v) d.healthText = v; Upd() end))
        c:Add(Check(c, "Mouseover glow", function() return d.mouseHighlight end,
            function(v) d.mouseHighlight = v end, "A soft glow around the border of the plate under the mouse."))
        c:Add(Slider(c, "Glow strength (%)", 10, 100, 5,
            function() return floor((d.glowAlpha or 0.8) * 100 + 0.5) end,
            function(v) d.glowAlpha = v / 100 end))
        c:Add(Color(c, "Glow colour",
            function() local k = d.glowColor or { r = 1, g = 1, b = 1 } return k.r, k.g, k.b, 1 end,
            function(r, g, b) d.glowColor = { r = r, g = g, b = b } end))
        c:Add(Check(c, "Fade plates that are not your target", function() return d.fadeOthers end,
            function(v) d.fadeOthers = v end, "While you have a target, every other plate fades. Without a target all plates stay solid."))
        c:Add(Slider(c, "Faded opacity (%)", 10, 100, 5,
            function() return floor((d.fadeAlpha or 0.4) * 100 + 0.5) end,
            function(v) d.fadeAlpha = v / 100 end, nil, "How solid the other plates stay: lower is fainter."))

        c = NewCard(p, "Raid marks", "Marked plates take the colour of their mark. Switch off the marks that should keep the normal colour.")
        c:Add(Check(c, "Colour by raid mark", function() return d.raidColor end,
            function(v) d.raidColor = v; Upd() end, "Before the enemy / neutral colours."))
        c:Break()
        d.raidMarks = d.raidMarks or {}
        for i = 1, 8 do
            local col = A.plateMarkColors and A.plateMarkColors[i] or { 1, 1, 1 }
            local row = c:Add(Check(c, _G["RAID_TARGET_" .. i] or ("Mark " .. i), function() return d.raidMarks[i] ~= false end,
                function(v) d.raidMarks[i] = v; Upd() end))
            -- the mark as a real texture (inline icon codes drew stray marks
            -- next to the text), the name in the mark's colour
            local ic = row:CreateTexture(nil, "ARTWORK")
            A:Size(ic, 14, 14)
            ic:SetPoint("LEFT", row, "LEFT", 2, 0)
            ic:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
            row.label:SetPoint("LEFT", row, "LEFT", 22, 0)
            row.label:SetTextColor(col[1], col[2], col[3])
        end

        c = NewCard(p, "Text and icons")
        c:Add(Slider(c, "Font size", 6, 16, 1, function() return d.fontSize end, function(v) d.fontSize = v; Upd() end))
        c:Add(Check(c, "Show level", function() return d.showLevel end, function(v) d.showLevel = v; Upd() end,
            "On the bar, left of the name."))
        c:Add(Check(c, "Your debuffs on nameplates", function() return d.showAuras end,
            function(v) d.showAuras = v; Upd() end, "Remembered per mob, so plates you are not targeting keep their timers (multi-dotting). A plate needs to have been your target, under the mouse, or the only one with that name."))
        c:Add(Slider(c, "Debuff icon size", 8, 32, 1, function() return d.auraSize end, function(v) d.auraSize = v; Upd() end))

        c = NewCard(p, "Hidden debuffs", "Your debuffs with these names never show on nameplates. Type a name (or spell id) and press Enter or Add.")
        local abox = CreateFrame("EditBox", nil, c)
        abox:SetHeight(22)
        abox:SetAutoFocus(false)
        A:SetFontPx(abox, A.media.font, FS_LABEL, "")
        abox:SetTextInsets(8, 8, 0, 0)
        Box(abox, C.ctrl, C.ctrlBd)
        local function addAura(n)
            if n and n ~= "" then A:BlacklistPlateAura(n, true); A.config.RebuildPage() end
        end
        abox:SetScript("OnEnterPressed", function(self) addAura(self:GetText()); self:SetText(""); self:ClearFocus() end)
        abox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        c:Add(abox, "full")
        c:Add(Btn(c, "Add", function() addAura(abox:GetText()); abox:SetText("") end, true))
        c:Add(Btn(c, "Add my debuffs on target", function()
            if not UnitExists("target") then return end
            for i = 1, 40 do
                local name, _, _, _, _, _, _, caster = UnitDebuff("target", i)
                if not name then break end
                if caster == "player" or caster == "pet" or caster == "vehicle" then A:BlacklistPlateAura(name, true) end
            end
            A.config.RebuildPage()
        end, false))
        local anames = {}
        for _, n in pairs(d.auraBlacklist or {}) do anames[#anames + 1] = n end
        table.sort(anames)
        for _, n in ipairs(anames) do
            c:Add(Btn(c, "x   " .. n, function() A:BlacklistPlateAura(n, false); A.config.RebuildPage() end))
        end

        c = NewCard(p, "Cast bar")
        c:Add(Check(c, "Show cast bar", function() return d.showCast end, function(v) d.showCast = v; Upd() end))
        c:Add(Slider(c, "Height", 4, 24, 1, function() return d.castHeight end, function(v) d.castHeight = v; Upd() end))

        c = NewCard(p, "Blacklist", "Units with these names never get a nameplate. Type a name and press Enter or Add.")
        local box = CreateFrame("EditBox", nil, c)
        box:SetHeight(22)
        box:SetAutoFocus(false)
        A:SetFontPx(box, A.media.font, FS_LABEL, "")
        box:SetTextInsets(8, 8, 0, 0)
        Box(box, C.ctrl, C.ctrlBd)
        local function addName(n)
            if n and n ~= "" then A:BlacklistPlate(n, true); A.config.RebuildPage() end
        end
        box:SetScript("OnEnterPressed", function(self) addName(self:GetText()); self:SetText(""); self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        c:Add(box, "full")
        c:Add(Btn(c, "Add", function() addName(box:GetText()); box:SetText("") end, true))
        c:Add(Btn(c, "Add my target", function()
            if UnitExists("target") and not UnitIsPlayer("target") then addName(UnitName("target")) end
        end))
        local names = {}
        for _, n in pairs(d.blacklist) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            c:Add(Btn(c, "x   " .. n, function() A:BlacklistPlate(n, false); A.config.RebuildPage() end))
        end
    end },

    { name = "Tooltips", desc = "Dark tooltips and menus with item quality borders.", build = function(p)
        local c = NewCard(p, "Tooltips")
        ModuleCheck(c, "tooltips", "Enable tooltip skin")
        c:Add(Check(c, "Anchor to mouse cursor",
            function() return A.db.ttCursor end,
            function(v) A.db.ttCursor = v end))
        c:Add(Check(c, "Class colored player names",
            function() return A.db.ttClassNames end,
            function(v) A.db.ttClassNames = v end))
        c:Add(Check(c, "Hide tooltips in combat",
            function() return A.db.ttHideCombat end,
            function(v) A.db.ttHideCombat = v end,
            "No tooltips at all while in combat: unit frames, action bars, bags, the world. Links you click open in chat still show."))
        c:Break()
        c:Add(Slider(c, "Tooltip scale", 0.5, 1.2, 0.05,
            function() return A.db.ttScale end,
            function(v) A.db.ttScale = v end, "%.2f"))
        c:Add(Slider(c, "Font size", 8, 16, 1,
            function() return A:FS("tooltips") end,
            function(v) A.db.fontSizes.tooltips = v; if A.SetTooltipFonts then A:SetTooltipFonts() end end))
    end },

    { group = "Quality of Life" },
    { name = "Automation", desc = "Small chores done for you. Hold Shift at a vendor or NPC to skip them once.", build = function(p)
        local d = A.db.auto
        local function Auto(card, key, label, tip, after)
            return card:Add(Check(card, label,
                function() return d[key] end,
                function(v) d[key] = v; if after then after(v) end end, tip))
        end
        local c = NewCard(p, "Automation")
        Auto(c, "enabled", "Enable automation", "Master switch for everything on this page.", function()
            if A.UpdateErrorFilter then A:UpdateErrorFilter() end
            if A.ApplyAutoLoot then A:ApplyAutoLoot() end
        end)

        c = NewCard(p, "Merchant")
        Auto(c, "sellJunk", "Sell grey items")
        Auto(c, "repair", "Repair all gear")
        Auto(c, "guildRepair", "Use guild bank funds first", "When your guild lets you, repairs are paid from the guild bank.")

        c = NewCard(p, "Group and social")
        Auto(c, "acceptInvites", "Accept group invites")
        c:Add(Dropdown(c, "Accept invites from", { { "FRIENDS", "Friends and guild" }, { "ANYONE", "Anyone" } },
            function() return d.inviteFrom end, function(v) d.inviteFrom = v end))
        Auto(c, "acceptRes", "Accept resurrections")
        Auto(c, "acceptCombatRes", "Accept combat resurrections")
        Auto(c, "acceptSummon", "Accept summons", "Only out of combat.")
        Auto(c, "declineDuels", "Decline duels")
        Auto(c, "roleCheck", "Confirm dungeon role checks", "Keeps the roles you already have selected.")

        c = NewCard(p, "Quests")
        Auto(c, "acceptQuests", "Accept quests")
        Auto(c, "turnInQuests", "Turn in finished quests")
        Auto(c, "bestReward", "Pick the reward that sells for most", "When a quest offers several rewards. Off = you choose.")
        Auto(c, "shiftSkips", "Hold Shift to skip", "Holding Shift while talking to an NPC leaves the quest to you.")

        c = NewCard(p, "Loot")
        Auto(c, "autoLoot", "Auto loot", "Sets the game's auto loot option.", function() A:ApplyAutoLoot() end)
        Auto(c, "fastLoot", "Fast loot", "Takes everything at once instead of item by item.")
        Auto(c, "confirmRolls", "Confirm Need / Greed on bind-on-pickup")
        Auto(c, "confirmBoP", "Confirm bind-on-pickup loot when solo")

        c = NewCard(p, "Other")
        Auto(c, "fillDelete", "Type DELETE for you", "Fills in the word when destroying a good item; you still click Yes.")
        Auto(c, "skipCinematics", "Skip cinematics and movies", "Hold Shift to watch one.")
        c:Add(Dropdown(c, "Hide red error text", { { "NEVER", "Never" }, { "COMBAT", "In combat" }, { "ALWAYS", "Always" } },
            function() return d.hideErrors end,
            function(v) d.hideErrors = v; if A.UpdateErrorFilter then A:UpdateErrorFilter() end end,
            "\"Not enough rage\", \"Out of range\" and the like."))
    end },

    { name = "Cursor & Alerts", desc = "A ring around your cursor and a screen-edge warning when your health is low.", build = function(p)
        local d = A.db.cursor
        local function Upd() if A.UpdateCursorCircle then A:UpdateCursorCircle() end end
        local c = NewCard(p, "Cursor circle")
        c:Add(Check(c, "Enable cursor circle", function() return d.enabled end, function(v) d.enabled = v; Upd() end))
        c:Add(Dropdown(c, "Style", { { 1, "Thin ring" }, { 2, "Soft ring" }, { 3, "Glow" } },
            function() return d.texture end, function(v) d.texture = v; Upd() end))
        c:Add(Slider(c, "Size", 16, 120, 1, function() return d.size end, function(v) d.size = v; Upd() end))
        c:Add(Color(c, "Color",
            function() local k = d.color return k.r, k.g, k.b, k.a end,
            function(r, g, b, a) local k = d.color k.r, k.g, k.b, k.a = r, g, b, a; Upd() end))
        c:Add(Check(c, "Class color", function() return d.classColor end, function(v) d.classColor = v; Upd() end))
        c:Add(Check(c, "Only in combat", function() return d.combatOnly end, function(v) d.combatOnly = v end))
        c:Add(Dropdown(c, "Show", { { "ALWAYS", "Always" }, { "MOUSEDOWN", "While a mouse button is held" } },
            function() return d.visibility end, function(v) d.visibility = v end,
            "\"While held\" helps find the cursor when turning the camera."))

        local h = A.db.lowHealth
        local function UpdLH() if A.UpdateLowHealth then A:UpdateLowHealth() end end
        c = NewCard(p, "Low health warning", "A colored wash pulses at the screen edges while your health is low.")
        c:Add(Check(c, "Enable low health warning", function() return h.enabled end, function(v) h.enabled = v; UpdLH() end))
        c:Add(Btn(c, "Preview (3 sec)", function() if A.PreviewLowHealth then A:PreviewLowHealth() end end))
        c:Add(Slider(c, "Health threshold (%)", 5, 80, 1, function() return h.threshold end, function(v) h.threshold = v; UpdLH() end))
        c:Add(Slider(c, "Intensity", 0.1, 1, 0.05, function() return h.intensity end, function(v) h.intensity = v; UpdLH() end, "%.2f"))
        c:Add(Color(c, "Color",
            function() local k = h.color return k.r, k.g, k.b, 1 end,
            function(r, g, b) local k = h.color k.r, k.g, k.b = r, g, b; UpdLH() end))
        c:Add(Check(c, "Pulse", function() return h.pulse end, function(v) h.pulse = v end))
        c:Add(Check(c, "Play a sound", function() return h.sound end, function(v) h.sound = v end,
            "Raid warning sound, once each time your health drops under the line."))
    end },

    { name = "Combat", desc = "A combat timer and a marker in the middle of the screen. Move both with Unlock UI.", build = function(p)
        local t = A.db.combatTimer
        local function UpdT() if A.UpdateCombatTimer then A:UpdateCombatTimer() end end
        local c = NewCard(p, "Combat timer")
        c:Add(Check(c, "Enable combat timer", function() return t.enabled end, function(v) t.enabled = v; UpdT() end))
        c:Add(Check(c, "Hide out of combat", function() return t.hideOOC end, function(v) t.hideOOC = v; UpdT() end))
        c:Add(Check(c, "Print fight length to chat", function() return t.chat end, function(v) t.chat = v end))
        c:Add(Check(c, "Background", function() return t.background end, function(v) t.background = v; UpdT() end))
        c:Add(Dropdown(c, "Brackets", { { "SQUARE", "[01:23]" }, { "ROUND", "(01:23)" }, { "NONE", "01:23" } },
            function() return t.brackets end, function(v) t.brackets = v; UpdT() end))
        c:Add(Slider(c, "Font size", 10, 48, 1, function() return t.size end, function(v) t.size = v; UpdT() end))
        c:Add(Color(c, "Color in combat",
            function() local k = t.colorIn return k.r, k.g, k.b, k.a end,
            function(r, g, b, a) local k = t.colorIn k.r, k.g, k.b, k.a = r, g, b, a; UpdT() end))
        c:Add(Color(c, "Color out of combat",
            function() local k = t.colorOut return k.r, k.g, k.b, k.a end,
            function(r, g, b, a) local k = t.colorOut k.r, k.g, k.b, k.a = r, g, b, a; UpdT() end))

        local x = A.db.combatCross
        local function UpdX() if A.UpdateCombatCross then A:UpdateCombatCross() end end
        c = NewCard(p, "Combat cross", "A marker at your character's position while in combat.")
        c:Add(Check(c, "Enable combat cross", function() return x.enabled end, function(v) x.enabled = v; UpdX() end))
        c:Add(Check(c, "Show out of combat too", function() return x.alwaysShow end, function(v) x.alwaysShow = v end))
        c:Add(Dropdown(c, "Shape", { { "CROSS", "Cross" }, { "CIRCLE", "Circle" } },
            function() return x.shape end, function(v) x.shape = v; UpdX() end))
        c:Add(Color(c, "Color",
            function() local k = x.color return k.r, k.g, k.b, k.a end,
            function(r, g, b, a) local k = x.color k.r, k.g, k.b, k.a = r, g, b, a; UpdX() end))
        c:Add(Slider(c, "Size", 8, 64, 1, function() return x.size end, function(v) x.size = v; UpdX() end))
        c:Add(Slider(c, "Line thickness", 1, 8, 1, function() return x.thickness end, function(v) x.thickness = v; UpdX() end))
        c:Add(Check(c, "Black outline", function() return x.outline end, function(v) x.outline = v; UpdX() end))
        c:Break()
        c:Add(Dropdown(c, "Recolor when target is out of range", {
                { "NONE", "Off" }, { "MELEE", "Melee range (~10 yd)" }, { "RANGED", "Ranged (~28 yd)" } },
            function() return x.range end, function(v) x.range = v; UpdX() end))
        c:Add(Color(c, "Out of range color",
            function() local k = x.oorColor return k.r, k.g, k.b, k.a end,
            function(r, g, b, a) local k = x.oorColor k.r, k.g, k.b, k.a = r, g, b, a; UpdX() end))
        c:Add(Check(c, "Only show when out of range", function() return x.hideInRange end, function(v) x.hideInRange = v end))
    end },
}

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function A:BuildConfig()
    local w = CreateFrame("Frame", "HUIConfig", UIParent)
    self:Size(w, WIN_W, WIN_H)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    Box(w, C.window, { 0.17, 0.17, 0.19, 1 })
    w:EnableMouse(true)
    w:SetMovable(true)
    w:SetClampedToScreen(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:Hide()
    tinsert(UISpecialFrames, "HUIConfig")  -- ESC closes it
    w:HookScript("OnHide", CloseDrop)
    self.config = w
    local px = self:PX(w)

    -- title bar
    local top = Solid(w, "BORDER", C.side[1], C.side[2], C.side[3], 1)
    top:SetPoint("TOPLEFT", px, -px)
    top:SetPoint("TOPRIGHT", -px, -px)
    top:SetHeight(TITLE_H)
    local topLine = Solid(w, "ARTWORK", AC())
    topLine:SetHeight(px)
    topLine:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    topLine:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    topLine:SetAlpha(0.8)
    local title = Text(w, 13, { 1, 1, 1 })
    title:SetPoint("LEFT", top, "LEFT", 12, 0)
    title:SetText("|cffc41f3bHUI|r")
    local ver = Text(w, FS_SMALL, C.faint)
    ver:SetPoint("LEFT", title, "RIGHT", 8, -1)
    ver:SetText("v" .. (GetAddOnMetadata("HUI", "Version") or "?") .. "   settings")

    local close = CreateFrame("Button", nil, w)
    A:Size(close, TITLE_H, TITLE_H)
    close:SetPoint("TOPRIGHT", -px, -px)
    local closeBg = Solid(close, "BACKGROUND", AC())
    closeBg:SetAllPoints(close)
    closeBg:Hide()
    local cx = Text(close, 13, C.muted, "CENTER")
    cx:SetPoint("CENTER", 0, 1)
    cx:SetText("x")
    close:SetScript("OnEnter", function() closeBg:Show(); cx:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function() closeBg:Hide(); cx:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    close:SetScript("OnClick", function() w:Hide() end)

    -- sidebar
    local nav = CreateFrame("Frame", nil, w)
    nav:SetPoint("TOPLEFT", px, -(TITLE_H + 2 * px))
    nav:SetPoint("BOTTOMLEFT", px, px)
    nav:SetWidth(NAV_W)
    local navBg = Solid(nav, "BACKGROUND", C.side[1], C.side[2], C.side[3], 1)
    navBg:SetAllPoints(nav)
    local sep = Solid(w, "ARTWORK", 0.13, 0.13, 0.15, 1)
    sep:SetWidth(px)
    sep:SetPoint("TOPLEFT", nav, "TOPRIGHT")
    sep:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT")
    local hint = Text(nav, 9, C.faint)
    hint:SetPoint("BOTTOMLEFT", 12, 10)
    hint:SetText("/hui    /hui unlock")

    -- content header
    local head = CreateFrame("Frame", nil, w)
    head:SetPoint("TOPLEFT", nav, "TOPRIGHT", PAD, -12)
    head:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD, -(TITLE_H + 12))
    head:SetHeight(30)
    local pageTitle = Text(head, 14, { 1, 1, 1 })
    pageTitle:SetPoint("TOPLEFT")
    local pageDesc = Text(head, FS_SMALL, C.muted)
    pageDesc:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -4)
    pageDesc:SetPoint("RIGHT", head, "RIGHT")

    -- footer
    local foot = CreateFrame("Frame", nil, w)
    foot:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", px, 0)
    foot:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -px, px)
    foot:SetHeight(FOOT_H)
    local footBg = Solid(foot, "BACKGROUND", C.side[1], C.side[2], C.side[3], 1)
    footBg:SetAllPoints(foot)
    local footLine = Solid(foot, "ARTWORK", 0.13, 0.13, 0.15, 1)
    footLine:SetHeight(px)
    footLine:SetPoint("TOPLEFT")
    footLine:SetPoint("TOPRIGHT")
    local status = Text(foot, FS_SMALL, C.muted)
    status:SetPoint("LEFT", PAD, 0)
    status:SetText("Changes apply instantly unless marked otherwise.")
    local reload = Btn(foot, "Reload UI", function() ReloadUI() end, false, 20)
    reload:SetWidth(96)
    reload:SetPoint("RIGHT", -8, 0)
    function w.NeedReload()
        status:SetText("|cffff6060Some changes need a reload to apply.|r")
        reload:SetPrimary(true)
    end

    -- scrolling page area
    local scroll = CreateFrame("ScrollFrame", nil, w)
    scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", -(PAD + 6), 8)
    scroll:EnableMouseWheel(true)
    -- scroll bar: a thin thumb you can drag, and a track you can click
    local track = CreateFrame("Button", nil, w)
    track:SetWidth(8)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    local bar = CreateFrame("Button", nil, track)
    bar:SetWidth(8)
    local barTex = Solid(bar, "ARTWORK", 1, 1, 1, 0.18)
    barTex:SetWidth(3)
    barTex:SetPoint("TOP")
    barTex:SetPoint("BOTTOM")
    local function Range()
        local child = scroll:GetScrollChild()
        local viewH = scroll:GetHeight()
        local h = child and child:GetHeight() or 0
        return viewH, h
    end
    local function UpdateBar()
        local viewH, h = Range()
        if h <= viewH + 1 then bar:Hide(); track:Hide() return end
        track:Show()
        local thumbH = max(24, viewH * viewH / h)
        local pos = scroll:GetVerticalScroll() / (h - viewH)
        bar:ClearAllPoints()
        bar:SetHeight(thumbH)
        bar:SetPoint("TOP", track, "TOP", 0, -pos * (viewH - thumbH))
        bar:Show()
    end
    local function ScrollTo(v)
        local viewH, h = Range()
        scroll:SetVerticalScroll(min(max(0, h - viewH), max(0, v)))
        UpdateBar()
    end
    scroll:SetScript("OnMouseWheel", function(self, d)
        ScrollTo(self:GetVerticalScroll() - d * 40)
    end)
    -- dragging the thumb
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / track:GetEffectiveScale()
    end
    bar:SetScript("OnMouseDown", function(self)
        self.dragY, self.dragStart = CursorY(), scroll:GetVerticalScroll()
        barTex:SetVertexColor(AC())
        self:SetScript("OnUpdate", function(b)
            local viewH, h = Range()
            local thumbH = b:GetHeight()
            local travel = viewH - thumbH
            if travel <= 0 then return end
            local dy = b.dragY - CursorY()
            ScrollTo(b.dragStart + dy * (h - viewH) / travel)
        end)
    end)
    bar:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        barTex:SetVertexColor(1, 1, 1, MouseIsOver(self) and 0.35 or 0.18)
    end)
    bar:SetScript("OnEnter", function() if not bar:GetScript("OnUpdate") then barTex:SetVertexColor(1, 1, 1, 0.35) end end)
    bar:SetScript("OnLeave", function() if not bar:GetScript("OnUpdate") then barTex:SetVertexColor(1, 1, 1, 0.18) end end)
    -- clicking the track jumps there
    track:SetScript("OnClick", function()
        local viewH, h = Range()
        local top = track:GetTop()
        if not top then return end
        local frac = (top - CursorY()) / track:GetHeight()
        ScrollTo(frac * h - viewH / 2)
    end)

    -- navigation
    local navButtons, pages, current = {}, {}, nil
    local function Select(i)
        CloseDrop()
        current = i
        for j, b in pairs(navButtons) do
            if j == i then
                b.bg:Show(); b.strip:Show()
                b.text:SetTextColor(1, 1, 1)
            else
                b.bg:Hide(); b.strip:Hide()
                b.text:SetTextColor(0.68, 0.68, 0.72)
            end
        end
        for _, p in pairs(pages) do p:Hide() end
        if not pages[i] then
            local p = NewPage(scroll)
            PAGES[i].build(p)
            p:Layout()
            pages[i] = p
        end
        pageTitle:SetText(PAGES[i].name)
        pageDesc:SetText(PAGES[i].desc or "")
        scroll:SetScrollChild(pages[i])
        pages[i]:Show()
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(0)
        UpdateBar()
        A.configPage = i
    end
    function w.RefreshPage()
        if current and pages[current] then pages[current]:RefreshAll() end
    end
    -- rebuild the current page (lists that grow / shrink)
    function w.RebuildPage()
        if not current or not pages[current] then return end
        pages[current]:Hide()
        pages[current] = nil
        Select(current)
    end

    local y = 12
    for i, def in ipairs(PAGES) do
        if def.group then
            if i > 1 then y = y + 8 end
            local g = Text(nav, 9, C.faint)
            g:SetPoint("TOPLEFT", nav, "TOPLEFT", 14, -y)
            g:SetText(def.group:upper())
            y = y + 14
        else
            local b = CreateFrame("Button", nil, nav)
            b:SetHeight(20)
            b:SetPoint("TOPLEFT", nav, "TOPLEFT", 6, -y)
            b:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -6, -y)
            b.bg = Solid(b, "BACKGROUND", AC())
            b.bg:SetAlpha(0.16)
            b.bg:SetAllPoints(b)
            b.strip = Solid(b, "ARTWORK", AC())
            b.strip:SetWidth(2)
            b.strip:SetPoint("TOPLEFT")
            b.strip:SetPoint("BOTTOMLEFT")
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(b)
            hl:SetTexture(1, 1, 1, 0.05)
            b.text = Text(b, FS_LABEL)
            b.text:SetPoint("LEFT", 10, 0)
            b.text:SetText(def.name)
            b:SetScript("OnClick", function() Select(i) end)
            navButtons[i] = b
            y = y + 21
        end
    end

    function w.SelectPage(name)
        for i, def in ipairs(PAGES) do
            if def.name == name and def.build then Select(i) return true end
        end
    end

    ------------------------------------------------------------------
    -- Search (title bar): every setting on every page
    ------------------------------------------------------------------
    local search = CreateFrame("EditBox", nil, w)
    search:SetWidth(240); search:SetHeight(18)
    search:SetPoint("RIGHT", close, "LEFT", -10, 0)
    search:SetAutoFocus(false)
    A:SetFontPx(search, A.media.font, FS_LABEL, "")
    search:SetTextColor(1, 1, 1)
    search:SetTextInsets(7, 18, 0, 0)
    Box(search, C.ctrl, C.ctrlBd)
    local holderText = Text(search, FS_LABEL, C.faint)
    holderText:SetPoint("LEFT", 7, 0)
    holderText:SetText("Search settings...")
    local clear = CreateFrame("Button", nil, search)
    clear:SetWidth(16); clear:SetHeight(16)
    clear:SetPoint("RIGHT", -2, 0)
    local clearX = Text(clear, FS_LABEL, C.muted, "CENTER")
    clearX:SetPoint("CENTER", 0, 1)
    clearX:SetText("x")
    clear:Hide()

    local res = CreateFrame("Frame", nil, w)
    res:SetFrameLevel(w:GetFrameLevel() + 60)
    res:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
    res:SetWidth(420)
    Box(res, { 0.05, 0.05, 0.06, 0.98 }, C.ctrlBd)
    res:Hide()
    res.items = {}
    local MAXR = 14

    -- every page has to exist to be searched (built hidden, once)
    local function BuildAll()
        for i, def in ipairs(PAGES) do
            if def.build and not pages[i] then
                local p = NewPage(scroll)
                def.build(p)
                p:Layout()
                p:Hide()
                pages[i] = p
            end
        end
    end

    local flash = CreateFrame("Frame", nil, w)
    flash.tex = flash:CreateTexture(nil, "OVERLAY")
    flash.tex:SetAllPoints()
    flash.tex:SetTexture(A.media.blank)
    flash:Hide()
    flash:SetScript("OnUpdate", function(self, el)
        self.t = self.t + el
        local a = 0.45 * (1 - self.t / 1.6)
        if a <= 0 then self:Hide() return end
        local r, g, b = AC()
        self.tex:SetVertexColor(r, g, b, a)
    end)
    local function Flash(target)
        flash:SetParent(target)
        flash:ClearAllPoints()
        flash:SetAllPoints(target)
        flash:SetFrameLevel(target:GetFrameLevel() + 20)
        flash.t = 0
        flash:Show()
    end

    local jumper = CreateFrame("Frame", nil, w)
    jumper:Hide()
    jumper:SetScript("OnUpdate", function(self)
        self:Hide()
        local p, t = pages[self.page], self.target
        if not (p and t) then return end
        local pt, tt = p:GetTop(), t:GetTop()
        if pt and tt then ScrollTo((pt - tt) - 30) end
        Flash(t)
    end)
    local function Jump(hit)
        res:Hide()
        search:ClearFocus()
        Select(hit.page)
        jumper.page, jumper.target = hit.page, hit.w
        jumper:Show()
    end

    local hits = {}
    local function Find(q)
        wipe(hits)
        q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if #q < 2 then return end
        BuildAll()
        local weak = {}
        for i, def in ipairs(PAGES) do
            local p = pages[i]
            if p and def.name then
                if def.name:lower():find(q, 1, true) then
                    table.insert(hits, { page = i, w = p, text = def.name, where = "page" })
                end
                for _, it in ipairs(p.index) do
                    local t = it.text and it.text:lower() or ""
                    local hit = { page = i, w = it.w, text = it.text, where = def.name .. ((it.card and it.card ~= it.text) and ("  >  " .. it.card) or "") }
                    if t:find(q, 1, true) then
                        table.insert(hits, hit)
                    elseif it.extra and it.extra:lower():find(q, 1, true) then
                        table.insert(weak, hit)   -- found in the description: listed after
                    end
                end
            end
        end
        for _, h in ipairs(weak) do table.insert(hits, h) end
    end

    local function ShowHits()
        for _, it in ipairs(res.items) do it:Hide() end
        local n = min(#hits, MAXR)
        for i = 1, n do
            local it = res.items[i]
            if not it then
                it = CreateFrame("Button", nil, res)
                it:SetHeight(30)
                it:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 30)
                it:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 30)
                local hl = it:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(it)
                hl:SetTexture(1, 1, 1, 0.07)
                it.t1 = Text(it, FS_LABEL, { 1, 1, 1 })
                it.t1:SetPoint("TOPLEFT", 8, -4)
                it.t1:SetPoint("RIGHT", -8, 0)
                it.t2 = Text(it, FS_SMALL, C.muted)
                it.t2:SetPoint("TOPLEFT", it.t1, "BOTTOMLEFT", 0, -2)
                it.t2:SetPoint("RIGHT", -8, 0)
                it:SetScript("OnClick", function(self) if self.hit then Jump(self.hit) end end)
                res.items[i] = it
            end
            local h = hits[i]
            it.hit = h
            it.t1:SetText(h.text)
            it.t2:SetText(h.where == "page" and "Page" or h.where)
            it:Show()
        end
        if n == 0 then
            res.none = res.none or Text(res, FS_LABEL, C.muted)
            res.none:SetPoint("LEFT", 8, 0)
            res.none:SetText("Nothing found")
            res.none:Show()
            res:SetHeight(26)
        else
            if res.none then res.none:Hide() end
            res:SetHeight(n * 30 + 2)
        end
        res:Show()
    end

    search:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        if t == "" then holderText:Show(); clear:Hide() else holderText:Hide(); clear:Show() end
        Find(t)
        if #t >= 2 then ShowHits() else res:Hide() end
    end)
    search:SetScript("OnEnterPressed", function(self)
        if hits[1] then Jump(hits[1]) else self:ClearFocus() end
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); res:Hide() end)
    search:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(AC())
        if #(self:GetText() or "") >= 2 then ShowHits() end
    end)
    search:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(C.ctrlBd[1], C.ctrlBd[2], C.ctrlBd[3])
    end)
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus(); res:Hide() end)
    -- clicking anywhere else closes the list
    w:HookScript("OnMouseDown", function() res:Hide(); search:ClearFocus() end)
    w:HookScript("OnHide", function() res:Hide() end)

    -- resizable from every edge and corner. While dragging only the frame
    -- changes; on release the page is rebuilt to the new width.
    local MIN_W, MIN_H = 600, 380
    local function Widths()
        CONTENT_W = math.floor(w:GetWidth() - NAV_W - PAD * 2 - 6)
        INNER_W = CONTENT_W - CARD_PAD * 2
        COL_W = INNER_W
    end
    local function Reflow()
        Widths()
        for k, p in pairs(pages) do p:Hide(); pages[k] = nil end
        if current then Select(current) end
    end
    w:SetResizable(true)
    w:SetMinResize(MIN_W, MIN_H)
    w:SetMaxResize(UIParent:GetWidth() / w:GetScale() * UIParent:GetScale(), UIParent:GetHeight() / w:GetScale() * UIParent:GetScale())
    w:HookScript("OnSizeChanged", function() UpdateBar() end)
    local function Grip(point, a1, a2, x1, y1, x2, y2, wd, ht)
        local g = CreateFrame("Frame", nil, w)
        g:SetFrameLevel(w:GetFrameLevel() + 30)
        g:EnableMouse(true)
        g:SetPoint(a1, w, a1, x1, y1)
        if a2 then g:SetPoint(a2, w, a2, x2, y2) end
        if wd then g:SetWidth(wd) end
        if ht then g:SetHeight(ht) end
        g:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then w:StartSizing(point) end
        end)
        g:SetScript("OnMouseUp", function()
            w:StopMovingOrSizing()
            A.db.configSize = { math.floor(w:GetWidth() + 0.5), math.floor(w:GetHeight() + 0.5) }
            Reflow()
        end)
        return g
    end
    local E, K = 5, 12   -- edge thickness, corner size
    Grip("LEFT", "TOPLEFT", "BOTTOMLEFT", 0, -K, 0, K, E)
    Grip("RIGHT", "TOPRIGHT", "BOTTOMRIGHT", 0, -K, 0, K, E)
    Grip("TOP", "TOPLEFT", "TOPRIGHT", K, 0, -K, 0, nil, E)
    Grip("BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT", K, 0, -K, 0, nil, E)
    Grip("TOPLEFT", "TOPLEFT", nil, 0, 0, nil, nil, K, K)
    Grip("TOPRIGHT", "TOPRIGHT", nil, 0, 0, nil, nil, K, K)
    Grip("BOTTOMLEFT", "BOTTOMLEFT", nil, 0, 0, nil, nil, K, K)
    local br = Grip("BOTTOMRIGHT", "BOTTOMRIGHT", nil, 0, 0, nil, nil, K + 2, K + 2)
    -- a small grabber in the corner shows it can be resized
    local grab = br:CreateTexture(nil, "OVERLAY")
    grab:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grab:SetAllPoints(br)
    grab:SetAlpha(0.5)
    br:SetScript("OnEnter", function() grab:SetAlpha(1) end)
    br:SetScript("OnLeave", function() grab:SetAlpha(0.5) end)
    -- last size used
    local cs = A.db.configSize
    if type(cs) == "table" and cs[1] and cs[2] then
        w:SetWidth(math.max(MIN_W, cs[1]))
        w:SetHeight(math.max(MIN_H, cs[2]))
    end
    Widths()

    -- reopen on the last page used this session
    w:SetScript("OnShow", function()
        local i = A.configPage
        if not (i and PAGES[i] and PAGES[i].build) then
            for j, def in ipairs(PAGES) do if def.build then i = j break end end
        end
        Select(i)
    end)
end

function A:OpenConfigPage(name)
    if not self.config then self:BuildConfig() end
    for i, def in ipairs(PAGES) do
        if def.name == name and def.build then self.configPage = i end
    end
    if self.config:IsShown() then
        self.config.SelectPage(name)
    else
        self.config:Show()
    end
end

function A:ToggleConfig()
    if not self.config then self:BuildConfig() end
    if self.config:IsShown() then self.config:Hide() else self.config:Show() end
end

-- /hui findline: lists thin, wide things on screen (lines), named or not,
-- including ones the frame stack tool can't see (no mouse, plain textures).
-- Ones under the cursor are marked with *.
function A:FindLines()
    local ui = UIParent:GetEffectiveScale()
    local px = self:PX(UIParent)
    local cx, cy = GetCursorPosition()
    cx, cy = cx / ui, cy / ui
    local out = {}
    local function Name(o)
        local n = o.GetName and o:GetName()
        if n then return n end
        local p = o.GetParent and o:GetParent()
        local pn = p and (p:GetName() or (p.GetParent and p:GetParent() and p:GetParent():GetName() and (p:GetParent():GetName() .. ".child"))) or "?"
        return pn .. "." .. o:GetObjectType()
    end
    local function Check(o, scaleOf)
        if not (o.IsVisible and o:IsVisible()) then return end
        local l, b, w, h = o:GetLeft(), o:GetBottom(), o:GetWidth(), o:GetHeight()
        if not (l and b and w and h) then return end
        local s = scaleOf:GetEffectiveScale() / ui
        l, b, w, h = l * s, b * s, w * s, h * s
        if h > 5 * px or w < 60 or w > UIParent:GetWidth() * 0.95 then return end
        if o.GetEffectiveAlpha and o:GetEffectiveAlpha() < 0.05 then return end
        local tex = o.GetTexture and o:GetTexture()
        local under = cx >= l and cx <= l + w and math.abs(cy - (b + h / 2)) <= 6 * px
        out[#out + 1] = format("%s%s  %dx%d at %d,%d%s", under and "|cffffff00*|r " or "", Name(o),
            w / px + 0.5, h / px + 0.5, l / px + 0.5, b / px + 0.5, tex and ("  " .. tostring(tex)) or "")
    end
    local f = EnumerateFrames()
    while f do
        if f:IsVisible() then
            if f.GetBackdrop and f:GetBackdrop() then Check(f, f) end
            if f:GetObjectType() == "StatusBar" then Check(f, f) end
            for i = 1, f:GetNumRegions() do
                local r = select(i, f:GetRegions())
                if r and r.GetObjectType and r:GetObjectType() == "Texture" then Check(r, f) end
            end
        end
        f = EnumerateFrames(f)
    end
    if #out == 0 then self:Print("no thin lines found on screen.") return end
    self:Print(#out .. " thin line(s) found (* = under the cursor):")
    for i = 1, math.min(#out, 30) do DEFAULT_CHAT_FRAME:AddMessage("  " .. out[i]) end
end

