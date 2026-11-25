-- HUI - Cursor circle, low health warning, combat timer, combat cross
-- Ported from the the retail essentials addon feature set to 3.3.5. Each piece builds
-- once and is switched on / off live from /hui > Cursor & Alerts.

local A = HUI
local floor, cos, pi, min, max = math.floor, math.cos, math.pi, math.min, math.max

local MEDIA = "Interface\\AddOns\\HUI\\media\\"
A.CURSOR_TEXTURES = { MEDIA .. "cursor1", MEDIA .. "cursor2", MEDIA .. "cursor3" }

local function PlayerClassColor()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Ev(handler, ...)
    local f = CreateFrame("Frame")
    for i = 1, select("#", ...) do f:RegisterEvent((select(i, ...))) end
    f:SetScript("OnEvent", handler)
    return f
end

------------------------------------------------------------------------
-- Cursor circle
------------------------------------------------------------------------
local cursor

function A:UpdateCursorCircle()
    local db = self.db.cursor
    if not db.enabled then
        if cursor then cursor:Hide() end
        return
    end
    if not cursor then
        cursor = CreateFrame("Frame", "HUICursorCircle", UIParent)
        cursor:SetFrameStrata("TOOLTIP")
        cursor:EnableMouse(false)
        cursor.tex = cursor:CreateTexture(nil, "OVERLAY")
        cursor.tex:SetAllPoints(cursor)
        cursor:SetScript("OnUpdate", A:PerfWrap("Cursor circle", function(self)
            local d = A.db.cursor
            local show = (not d.combatOnly or UnitAffectingCombat("player"))
                and (d.visibility ~= "MOUSEDOWN" or IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            if not show then
                if self.tex:IsShown() then self.tex:Hide() end
                return
            end
            if not self.tex:IsShown() then self.tex:Show() end
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
        end))
    end
    cursor.tex:SetTexture(self.CURSOR_TEXTURES[db.texture] or self.CURSOR_TEXTURES[1])
    local c = db.color
    if db.classColor then
        local r, g, b = PlayerClassColor()
        cursor.tex:SetVertexColor(r, g, b, c.a or 0.8)
    else
        cursor.tex:SetVertexColor(c.r, c.g, c.b, c.a or 0.8)
    end
    self:Size(cursor, db.size)
    cursor:Show()
end

------------------------------------------------------------------------
-- Low health warning: a coloured wash pulses at the screen edges while
-- your health is under the threshold (with an optional sound per drop)
------------------------------------------------------------------------
local lh
local MARGIN, DEPTH, PULSE_LOW, PULSE_TIME = 5, 0.14, 0.25, 0.6

local function LHPaint()
    local db = A.db.lowHealth
    local c, a = db.color, db.intensity
    lh.left:SetGradientAlpha("HORIZONTAL", c.r, c.g, c.b, a, c.r, c.g, c.b, 0)
    lh.right:SetGradientAlpha("HORIZONTAL", c.r, c.g, c.b, 0, c.r, c.g, c.b, a)
    lh.top:SetGradientAlpha("VERTICAL", c.r, c.g, c.b, 0, c.r, c.g, c.b, a)
    lh.bottom:SetGradientAlpha("VERTICAL", c.r, c.g, c.b, a, c.r, c.g, c.b, 0)
    local depth = floor((UIParent:GetHeight() or 768) * DEPTH + 0.5)
    lh.top:SetHeight(depth); lh.bottom:SetHeight(depth)
    lh.left:SetWidth(depth); lh.right:SetWidth(depth)
end

local function LHShow(on)
    if on then
        if not lh:IsShown() then lh.t = 0; lh:Show() end
    else
        lh:Hide()
    end
end

local function LHEvaluate()
    local db = A.db.lowHealth
    if not db.enabled or lh.preview then return end
    if UnitIsDeadOrGhost("player") then lh.wasAbove = false; return LHShow(false) end
    local cur, mx = UnitHealth("player"), UnitHealthMax("player")
    if not mx or mx <= 0 then return LHShow(false) end
    local pct = cur / mx * 100
    if pct < db.threshold then
        if lh.wasAbove ~= false and db.sound then PlaySoundFile("Sound\\Interface\\RaidWarning.wav") end
        lh.wasAbove = false
        LHShow(true)
    elseif pct >= db.threshold + MARGIN or not lh:IsShown() then
        lh.wasAbove = true
        LHShow(false)
    end
end

function A:UpdateLowHealth()
    local db = self.db.lowHealth
    if not lh then
        lh = CreateFrame("Frame", "HUILowHealth", UIParent)
        lh:SetAllPoints(UIParent)
        lh:SetFrameStrata("BACKGROUND")
        lh:SetFrameLevel(0)
        lh:EnableMouse(false)
        lh:Hide()
        local function Edge()
            local t = lh:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(A.media.blank)
            return t
        end
        lh.top, lh.bottom, lh.left, lh.right = Edge(), Edge(), Edge(), Edge()
        lh.top:SetPoint("TOPLEFT"); lh.top:SetPoint("TOPRIGHT")
        lh.bottom:SetPoint("BOTTOMLEFT"); lh.bottom:SetPoint("BOTTOMRIGHT")
        lh.left:SetPoint("TOPLEFT"); lh.left:SetPoint("BOTTOMLEFT")
        lh.right:SetPoint("TOPRIGHT"); lh.right:SetPoint("BOTTOMRIGHT")
        lh.t = 0
        lh:SetScript("OnUpdate", A:PerfWrap("Low health warning", function(self, el)
            self.t = self.t + el
            if self.preview and self.t > 3 then
                self.preview = nil
                self:Hide()
                LHEvaluate()
                return
            end
            if A.db.lowHealth.pulse then
                local k = 0.5 + 0.5 * cos(self.t * pi / PULSE_TIME)
                self:SetAlpha(PULSE_LOW + (1 - PULSE_LOW) * k)
            elseif self:GetAlpha() ~= 1 then
                self:SetAlpha(1)
            end
        end))
        lh.events = Ev(function(_, event, unit)
            if (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and unit ~= "player" then return end
            LHEvaluate()
        end, "UNIT_HEALTH", "UNIT_MAXHEALTH", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
            "PLAYER_ENTERING_WORLD")
    end
    LHPaint()
    if db.enabled then LHEvaluate() else LHShow(false) end
end

function A:PreviewLowHealth()
    if not lh then self:UpdateLowHealth() end
    LHPaint()
    lh.preview = true
    lh.t = 0
    lh:Show()
end

------------------------------------------------------------------------
-- Combat timer
------------------------------------------------------------------------
local timer
local BRACKETS = { SQUARE = { "[", "]" }, ROUND = { "(", ")" }, NONE = { "", "" } }

local function FormatTime(s)
    s = floor(s)
    return format("%02d:%02d", floor(s / 60), s % 60)
end

local function TimerText(s)
    local b = BRACKETS[A.db.combatTimer.brackets] or BRACKETS.SQUARE
    return b[1] .. FormatTime(s) .. b[2]
end

local function TimerColor()
    local db = A.db.combatTimer
    local c = timer.inCombat and db.colorIn or db.colorOut
    timer.text:SetTextColor(c.r, c.g, c.b, c.a or 1)
end

local function TimerVisibility()
    local db = A.db.combatTimer
    if db.enabled and (timer.inCombat or not db.hideOOC or A.unlocked) then
        timer:Show()
    else
        timer:Hide()
    end
end

function A:UpdateCombatTimer()
    local db = self.db.combatTimer
    if not timer then
        timer = CreateFrame("Frame", "HUICombatTimer", UIParent)
        timer:SetFrameStrata("HIGH")
        timer.bg = timer:CreateTexture(nil, "BACKGROUND")
        timer.bg:SetAllPoints(timer)
        timer.bg:SetTexture(0, 0, 0, 0.55)
        timer.text = timer:CreateFontString(nil, "OVERLAY")
        A:SetFontPx(timer.text, self.media.font, db.size, "OUTLINE")
        timer.text:SetPoint("CENTER")
        timer.elapsed = 0
        timer.acc = 0
        timer:SetScript("OnUpdate", A:PerfWrap("Combat timer", function(self, el)
            if not self.inCombat then return end
            self.acc = self.acc + el
            if self.acc < 0.2 then return end
            self.acc = 0
            self.elapsed = GetTime() - self.start
            self.text:SetText(TimerText(self.elapsed))
        end))
        Ev(function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                timer.inCombat = true
                timer.start = GetTime()
                timer.elapsed = 0
                timer.text:SetText(TimerText(0))
            else
                if not timer.inCombat then return end
                timer.inCombat = false
                timer.elapsed = GetTime() - (timer.start or GetTime())
                timer.text:SetText(TimerText(timer.elapsed))
                if A.db.combatTimer.enabled and A.db.combatTimer.chat and timer.elapsed >= 1 then
                    A:Print("combat lasted " .. FormatTime(timer.elapsed) .. ".")
                end
            end
            TimerColor()
            TimerVisibility()
        end, "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED")
        -- default: on top of the chat box, right edges lined up
        self:RegisterMover("CombatTimer", timer, "Combat timer")
        timer.text:SetText(TimerText(0))
    end
    A:SetFontPx(timer.text, self.media.font, db.size, "OUTLINE")
    timer.text:SetShadowOffset(0, 0)
    timer.text:SetText(TimerText(0))
    local w = timer.text:GetStringWidth()
    timer:SetWidth(floor(w + (db.background and 12 or 2)))
    timer:SetHeight(floor(db.size + (db.background and 8 or 4)))
    timer.text:ClearAllPoints()
    timer.text:SetPoint(db.background and "CENTER" or "RIGHT")
    timer.text:SetText(TimerText(timer.elapsed or 0))
    if db.background then timer.bg:Show() else timer.bg:Hide() end
    TimerColor()
    TimerVisibility()
end

------------------------------------------------------------------------
-- Combat cross: a marker at the centre of the screen while in combat,
-- optionally recoloured when the target is out of range
------------------------------------------------------------------------
local cross

local function CrossColor(oor)
    local db = A.db.combatCross
    local c = oor and db.oorColor or db.color
    for _, t in ipairs(cross.lines) do t:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
    cross.circle:SetVertexColor(c.r, c.g, c.b, c.a or 1)
end

local function OutOfRange()
    local mode = A.db.combatCross.range
    if mode == "NONE" or not UnitExists("target") or UnitIsDeadOrGhost("target")
        or not UnitCanAttack("player", "target") then
        return false
    end
    -- 3 = duel range (~10 yd, melee), 4 = follow range (~28 yd, ranged)
    return not CheckInteractDistance("target", mode == "MELEE" and 3 or 4)
end

local function CrossTick()
    local db = A.db.combatCross
    local active = db.enabled and (UnitAffectingCombat("player") or db.alwaysShow)
    local oor = active and OutOfRange()
    if active and db.range ~= "NONE" and db.hideInRange and not oor then active = false end
    if A.unlocked and db.enabled then active = true end
    if active then
        if cross.oor ~= oor then cross.oor = oor; CrossColor(oor) end
        if not cross.body:IsShown() then cross.body:Show() end
    elseif cross.body:IsShown() then
        cross.body:Hide()
    end
end

function A:UpdateCombatCross()
    local db = self.db.combatCross
    if not cross then
        cross = CreateFrame("Frame", "HUICombatCross", UIParent)
        cross:SetFrameStrata("HIGH")
        cross:EnableMouse(false)
        cross.body = CreateFrame("Frame", nil, cross)
        cross.body:SetAllPoints(cross)
        local function Tex(layer)
            local t = cross.body:CreateTexture(nil, layer)
            t:SetTexture(A.media.blank)
            return t
        end
        cross.outline = { Tex("BORDER"), Tex("BORDER") }
        cross.lines = { Tex("ARTWORK"), Tex("ARTWORK") }
        for _, t in ipairs(cross.outline) do t:SetVertexColor(0, 0, 0, 1) end
        cross.circle = cross.body:CreateTexture(nil, "ARTWORK")
        cross.circle:SetAllPoints(cross)
        cross.circle:SetTexture(A.CURSOR_TEXTURES[1])
        local acc = 0
        cross:SetScript("OnUpdate", A:PerfWrap("Combat cross", function(_, el)
            acc = acc + el
            if acc < 0.1 then return end
            acc = 0
            CrossTick()
        end))
        self:RegisterMover("CombatCross", cross, "Cross")
    end
    local size, th = db.size, db.thickness
    self:Size(cross, size)
    local h, v = cross.lines[1], cross.lines[2]
    local oh, ov = cross.outline[1], cross.outline[2]
    h:ClearAllPoints(); h:SetPoint("CENTER"); h:SetWidth(size); h:SetHeight(th)
    v:ClearAllPoints(); v:SetPoint("CENTER"); v:SetWidth(th); v:SetHeight(size)
    oh:ClearAllPoints(); oh:SetPoint("CENTER"); oh:SetWidth(size + 2); oh:SetHeight(th + 2)
    ov:ClearAllPoints(); ov:SetPoint("CENTER"); ov:SetWidth(th + 2); ov:SetHeight(size + 2)
    local isCross = db.shape ~= "CIRCLE"
    for _, t in ipairs(cross.lines) do if isCross then t:Show() else t:Hide() end end
    for _, t in ipairs(cross.outline) do if isCross and db.outline then t:Show() else t:Hide() end end
    if isCross then cross.circle:Hide() else cross.circle:Show() end
    cross.oor = nil
    CrossColor(false)
    if db.enabled then cross:Show() else cross:Hide() end
    CrossTick()
end

------------------------------------------------------------------------
function A:BuildCombatExtras()
    self:UpdateCursorCircle()
    self:UpdateLowHealth()
    self:UpdateCombatTimer()
    self:UpdateCombatCross()
    -- unlock mode shows the timer / cross even when they'd be hidden
    if not self.extrasLockHooked then
        self.extrasLockHooked = true
        hooksecurefunc(self, "Unlock", function() TimerVisibility(); if cross then CrossTick() end end)
        hooksecurefunc(self, "Lock", function() TimerVisibility(); if cross then CrossTick() end end)
    end
end
