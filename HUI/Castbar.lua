-- HUI - Castbars

local A = HUI
local GetTime = GetTime

A.castbars = {}

local function DB() return A.db.castbar end

------------------------------------------------------------------------
-- Channel ticks: thin marks where each tick of a channelled spell lands.
-- 3.3.5 only gives the spell name, so the list is by spell id -> number of
-- ticks, turned into names in the client's language.
------------------------------------------------------------------------
local TICK_IDS = {
    [15407] = 3,   -- Mind Flay
    [48045] = 5,   -- Mind Sear
    [47540] = 2,   -- Penance (first bolt lands at once)
    [64843] = 4,   -- Divine Hymn
    [64901] = 4,   -- Hymn of Hope
    [689]   = 5,   -- Drain Life
    [1120]  = 5,   -- Drain Soul
    [5138]  = 5,   -- Drain Mana
    [1949]  = 15,  -- Hellfire
    [5740]  = 4,   -- Rain of Fire
    [5143]  = 5,   -- Arcane Missiles
    [12051] = 4,   -- Evocation
    [10]    = 8,   -- Blizzard
    [740]   = 4,   -- Tranquility
    [16914] = 10,  -- Hurricane
    [1510]  = 6,   -- Volley
    [45544] = 8,   -- First Aid (bandages)
}
local tickByName
local function TicksFor(name)
    if not tickByName then
        tickByName = {}
        for id, n in pairs(TICK_IDS) do
            local sn = GetSpellInfo(id)
            if sn then tickByName[sn] = n end
        end
    end
    return name and tickByName[name]
end

local function HideTicks(cb)
    for _, t in ipairs(cb.ticks or {}) do t:Hide() end
end

local function ShowTicks(cb, n)
    HideTicks(cb)
    if not n or n < 2 then return end
    cb.ticks = cb.ticks or {}
    local w = cb.bar:GetWidth() or 0
    if w <= 0 then return end
    local px = A:PX(cb.bar)
    for i = 1, n - 1 do
        local t = cb.ticks[i]
        if not t then
            t = cb.bar:CreateTexture(nil, "OVERLAY")
            t:SetTexture(A.media.blank)
            cb.ticks[i] = t
        end
        t:SetVertexColor(1, 1, 1, 0.6)
        t:ClearAllPoints()
        t:SetPoint("TOP", cb.bar, "TOPLEFT", A:Snap(cb.bar, w * i / n), 0)
        t:SetPoint("BOTTOM", cb.bar, "BOTTOMLEFT", A:Snap(cb.bar, w * i / n), 0)
        t:SetWidth(px)
        t:Show()
    end
end

-- normal casts use the unit frames' dark color (with its transparency); the
-- empty part of the bar uses the missing-health color. Uninterruptible casts and
-- failed/interrupted flashes keep their own colors so they stay readable.
local function SetColor(cb, c)
    local fill = cb.bar:GetStatusBarTexture()
    local bgc = A.colors.backdrop
    if c == A.colors.castbar then
        -- like dark mode health: the cast part is the background colour
        cb.bar:SetStatusBarColor(bgc[1], bgc[2], bgc[3])
        if fill then fill:SetAlpha(bgc[4]) end
    else
        cb.bar:SetStatusBarColor(c[1], c[2], c[3])
        if fill then fill:SetAlpha(1) end
    end
    local m = A.db.missingColor
    cb.bar.bg:SetVertexColor(m.r, m.g, m.b, A.colors.backdrop[4])
    -- the bar covers the frame: leave the frame background empty so the
    -- missing part keeps the background opacity
    local bg = A.colors.backdrop
    cb.atrCustomBg = true
    cb:SetBackdropColor(bg[1], bg[2], bg[3], 0)
end
A.SetCastbarColor = SetColor

local function Start(cb, channel)
    local name, text, tex, startT, endT, notInt, castID, _
    if channel then
        name, _, text, tex, startT, endT, _, notInt = UnitChannelInfo(cb.unit)
    else
        name, _, text, tex, startT, endT, _, castID, notInt = UnitCastingInfo(cb.unit)
    end
    if not name then return false end
    cb.castID = castID   -- the game's number for this cast (nil for channels)
    if cb == A.playerCastbar and DB().hidePlayer then cb:Hide() return false end
    cb.channel = channel
    cb.startT = startT / 1000
    cb.endT = endT / 1000
    cb.fading = nil
    cb.bar:SetMinMaxValues(0, cb.endT - cb.startT)
    cb.total = cb.endT - cb.startT
    if channel and DB().ticks then ShowTicks(cb, TicksFor(name)) else HideTicks(cb) end
    cb.text:SetText(name)
    cb.icon:SetTexture(tex)
    cb.tenths = nil
    -- every cast uses the dark background colour, like the other frames
    do
        SetColor(cb, A.colors.castbar)
    end
    cb:SetAlpha(1)
    cb:Show()
    return true
end

local function FadeOut(cb, failed)
    if not cb:IsShown() then return end
    if failed then
        SetColor(cb, A.colors.castFail)
        cb.text:SetText(failed)
        local _, max = cb.bar:GetMinMaxValues()
        cb.bar:SetValue(max)
    end
    cb.time:SetText("")
    cb.tenths = nil
    HideTicks(cb)
    cb.fading = 0.5
end

function A:CastbarCheck(cb)
    if not UnitExists(cb.unit) then cb:Hide() return end
    if not Start(cb, false) and not Start(cb, true) then
        cb.fading = nil
        cb:Hide()
    end
end

local function OnUpdate(cb, el)
    if cb.fading then
        cb.fading = cb.fading - el
        if cb.fading <= 0 then
            cb.fading = nil
            cb:Hide()
        else
            cb:SetAlpha(cb.fading / 0.5)
        end
        return
    end
    local now = GetTime()
    if now >= cb.endT then
        FadeOut(cb)
        return
    end
    if cb.channel then
        cb.bar:SetValue(cb.endT - now)
    else
        cb.bar:SetValue(now - cb.startT)
    end
    -- the text only when the tenths change (it was re-laid out every frame)
    local left = cb.endT - now
    local tenths = math.floor(left * 10 + 0.5)
    local total = DB().showTotal and true or false
    if cb.tenths ~= tenths or cb.tShowTotal ~= total then
        cb.tenths, cb.tShowTotal = tenths, total
        if total then
            cb.time:SetFormattedText("%.1f / %.1f", left, cb.total or 0)
        else
            cb.time:SetFormattedText("%.1f", left)
        end
    end
end

-- a failed / interrupted report about the cast the bar shows? (the game also
-- reports presses that never became a cast: next spell pressed too early,
-- on cooldown, out of range ... those must not mark the bar)
local function IsThisCast(cb, castID, allowFinished)
    if cb.fading and not allowFinished then return false end   -- already finished: it stays finished
    if castID and castID ~= 0 and cb.castID and castID ~= cb.castID then return false end
    return true
end

local function OnEvent(cb, event, unit, _, _, castID)
    if unit ~= cb.unit then return end
    if event == "UNIT_SPELLCAST_START" then
        Start(cb, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        Start(cb, true)
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        if cb:IsShown() and not cb.channel then Start(cb, false) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if cb:IsShown() and cb.channel then Start(cb, true) end
    elseif event == "UNIT_SPELLCAST_STOP" then
        if not cb.channel then FadeOut(cb) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if cb.channel then FadeOut(cb) end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        if not cb.channel and not UnitCastingInfo(unit) and IsThisCast(cb, castID) then
            FadeOut(cb, FAILED or "Failed")
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not UnitCastingInfo(unit) and not UnitChannelInfo(unit) and IsThisCast(cb, not cb.channel and castID or nil, true) then
            FadeOut(cb, INTERRUPTED or "Interrupted")
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        if cb:IsShown() and not cb.fading then SetColor(cb, A.colors.castbar) end
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if cb:IsShown() and not cb.fading then SetColor(cb, A.colors.castbar) end
    end
end

local events = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

function A:CreateCastbar(name, unit, width, height, parent)
    -- parented to its unit frame (if any) so it hides with it and inherits its scale
    local cb = CreateFrame("Frame", "HUI" .. name .. "Castbar", parent or UIParent)
    cb.unit = unit
    self:Size(cb, width, height)
    if not parent then cb:SetScale(self.db.scale) end
    self:Size(cb, self:Snap(cb, width), self:Snap(cb, height))
    self:SetTemplate(cb)

    cb.icon = cb:CreateTexture(nil, "ARTWORK")
    local px = self:PX(cb)
    cb.icon:SetPoint("TOPLEFT", px, -px)
    cb.icon:SetPoint("BOTTOMLEFT", px, px)
    cb.icon:SetWidth(self:Snap(cb, height) - 2 * px)
    cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cb.bar = self:StatusBar(cb)
    cb.bar:SetPoint("TOPLEFT", cb.icon, "TOPRIGHT", px, 0)
    cb.bar:SetPoint("BOTTOMRIGHT", -px, px)

    local fs = height >= 20 and 12 or 11
    cb.time = self:Font(cb.bar, fs, "RIGHT")
    -- text sits a pixel low in the bar (font ascent): lift it 1px
    cb.time:SetPoint("RIGHT", -4, px)
    cb.text = self:Font(cb.bar, fs, "LEFT")
    cb.text:SetPoint("LEFT", 4, px)
    cb.text:SetPoint("RIGHT", cb.time, "LEFT", -4, 0)
    cb.text:SetHeight(fs + 4)

    for _, e in ipairs(events) do pcall(cb.RegisterEvent, cb, e) end
    cb:SetScript("OnEvent", A:PerfWrap("Castbars: events", OnEvent))
    cb:SetScript("OnUpdate", A:PerfWrap("Castbars", OnUpdate))
    cb:Hide()
    self.castbars[name] = cb
    SetColor(cb, A.colors.castbar)
    return cb
end

function A:BuildCastbars()
    -- Player: standalone and movable
    local pcb = self:CreateCastbar("Player", "player", 260, 22)
    pcb.atrNormalW = pcb:GetWidth()
    pcb.useClassColor = true
    self:ApplyPosition("PlayerCastbar", pcb)
    self:RegisterMover("PlayerCastbar", pcb, "Player Castbar")
    self.playerCastbar = pcb

    -- Target: attached under the target frame (below combo points)
    local t = self.units.Target
    if t then
        local tcb = self:CreateCastbar("Target", "target", t.cfg.width, 18, t)
        tcb:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -A:PX(t))
        t.castbar = tcb
        -- the boss frames hang under it by default
        if self.bossHolder then self:ApplyPosition("Boss", self.bossHolder) end
    end

    -- Focus
    local f = self.units.Focus
    if f then
        local fcb = self:CreateCastbar("Focus", "focus", f.cfg.width, 16, f)
        fcb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -A:PX(f))
        f.castbar = fcb
    end
end
