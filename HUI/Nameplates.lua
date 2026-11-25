-- HUI - Nameplates
-- Restyles the game's own 3.3.5 nameplates:
--   [debuff icons]                       (your debuffs, on your target's plate)
--   [ Name                 865M | 88% ]  health bar, name + health inside
--   [i][ Spell name                  ]   cast bar with spell icon
-- The plates stay the client's (clicking, targeting, stacking keep working).
-- Neutral plates can be hidden, and plates can be blacklisted by unit name.
-- Settings: /hui > Nameplates.

local A = HUI
local floor, format = math.floor, string.format
local SetTxt, lower = A.SetTxt, A.lower

local BORDER = "Interface\\Tooltips\\Nameplate-Border"
local GLOW = "Interface\\AddOns\\HUI\\media\\glowedge"   -- soft edge for the mouseover glow
local plates = {}          -- plate frame -> our parts
local plateSeq = 0         -- draw order tie-break (see SortByY)
-- the plates on screen right now, kept up to date by their OnShow / OnHide,
-- so the per-frame loops don't walk every plate the client ever made (a raid
-- leaves dozens of hidden ones behind)
local live, liveN = {}, 0
local function SetLive(p, on)
    if on then
        if p.liveIdx then return end
        liveN = liveN + 1
        live[liveN] = p
        p.liveIdx = liveN
    elseif p.liveIdx then
        local i = p.liveIdx
        local last = live[liveN]
        live[i] = last
        last.liveIdx = i
        live[liveN] = nil
        liveN = liveN - 1
        p.liveIdx = nil
    end
end
local numKids = 0
local MAX_AURAS = 6

local function DB() return A.db.nameplates end

local function IsPlate(f)
    if f:GetName() or f.atrPlate ~= nil then return f.atrPlate end
    local _, border = f:GetRegions()
    local ok = border and border.GetTexture and border:GetObjectType() == "Texture"
        and border:GetTexture() == BORDER
    f.atrPlate = ok and true or false
    return f.atrPlate
end

-- the client's own bar colour tells the reaction (we tint the texture, not the
-- bar colour, so this keeps reading the client's value)
local function Reaction(bar)
    local r, g, b = bar:GetStatusBarColor()
    if r > 0.9 and g < 0.2 and b < 0.2 then return "HOSTILE" end
    if r > 0.9 and g > 0.9 and b < 0.2 then return "NEUTRAL" end
    return "FRIENDLY"
end

local function Short(v)
    if v >= 1e9 then return format("%.0fB", v / 1e9) end
    if v >= 1e6 then return format("%.0fM", v / 1e6) end
    if v >= 1e4 then return format("%.0fK", v / 1e3) end
    if v >= 1e3 then return format("%.1fK", v / 1e3) end
    return tostring(floor(v))
end

-- long names that don't fit: "Scarlet Crusade Champion" -> "S. C. Champion",
-- then cut with ".." if it still doesn't fit
local function FitName(p, full)
    local fs = p.name
    fs.huiTxt = nil
    fs:SetText(full)
    if not DB().shortNames then return end
    -- room left between level and health text (anchored widths aren't ready yet on show)
    local px = A:PX(p.health)
    local room = (p.health:GetWidth() or 0) - 12 * px - (p.hp:IsShown() and p.hp:GetStringWidth() or 0)
    if p.lvl:IsShown() then room = room - p.lvl:GetStringWidth() - 4 * px end
    if room <= 0 or fs:GetStringWidth() <= room then return end
    local words = {}
    for w in full:gmatch("%S+") do words[#words + 1] = w end
    if #words > 1 then
        for i = 1, #words - 1 do
            words[i] = words[i]:sub(1, 1) .. "."
            fs:SetText(table.concat(words, " "))
            if fs:GetStringWidth() <= room then return end
        end
    end
    local s = fs:GetText()
    while #s > 1 do
        s = s:sub(1, -2)
        fs:SetText(s .. "..")
        if fs:GetStringWidth() <= room then return end
    end
end

local function UpdateHealthText(p)
    local db = DB()
    local bar = p.health
    local cur = bar:GetValue()
    local _, max = bar:GetMinMaxValues()
    if db.healthText == "NONE" or not max or max <= 0 then SetTxt(p.hp, ""); p.hpCur = nil return end
    if p.hpCur == cur and p.hpMax == max and p.hpMode == db.healthText and p.hp.huiTxt then return end
    p.hpCur, p.hpMax, p.hpMode = cur, max, db.healthText
    local pct = floor(cur / max * 100 + 0.5) .. "%"
    if db.healthText == "PERCENT" then SetTxt(p.hp, pct)
    elseif db.healthText == "VALUE" then SetTxt(p.hp, Short(cur))
    else SetTxt(p.hp, Short(cur) .. " | " .. pct) end
end

-- The target's plate is the one at full alpha with the target's name. Right
-- after a target change the client hasn't dimmed the others yet, so with
-- several same-named mobs more than one can match: then it's unknown (nil)
-- rather than a guess, so their debuffs don't get mixed up.
local targetPlate, targetStamp
local function TargetPlate()
    local now = GetTime()
    if targetStamp == now then return targetPlate end
    targetStamp, targetPlate = now, nil
    if not UnitExists("target") then return nil end
    local name = UnitName("target")
    for i = 1, liveN do
        local p = live[i]
        local frame = p.frame
        if p.oname:GetText() == name and frame:GetAlpha() > 0.99 then
            if targetPlate then targetPlate = nil; return nil end
            targetPlate = p
        end
    end
    return targetPlate
end

local function IsTarget(p)
    return TargetPlate() == p
end

-- one mob, one plate: giving a plate a GUID takes it away from any other
local function SetGuid(p, guid)
    if not guid or p.guid == guid then return end
    for _, q in pairs(plates) do
        if q ~= p and q.guid == guid then q.guid = nil end
    end
    p.guid = guid
end

-- size / position / visibility of every part, from the settings
-- the game re-anchors its cast bar now and then (its own, much taller
-- layout): its stored height stays the same, but its real edges move. Check
-- the real height on screen and what it hangs from.
local function CastMoved(p)
    local cast = p.cast
    local _, rel = cast:GetPoint(1)
    if rel ~= p.health or cast:GetNumPoints() ~= 2 then return true end
    local t, b = cast:GetTop(), cast:GetBottom()
    if t and b and math.abs((t - b) - (p.wantCH or 0)) > 0.5 then return true end
    local ic = p.icon
    if ic and ic:IsShown() then
        local it, ib = ic:GetTop(), ic:GetBottom()
        if it and ib and math.abs((it - ib) - (p.wantCH or 0)) > 0.5 then return true end
    end
    return false
end

local function Layout(p)
    local db = DB()
    local f, bar, cast = p.frame, p.health, p.cast
    local px = A:PX(bar)
    local w, h = A:Snap(bar, db.width), A:Snap(bar, db.height)
    local fs = db.fontSize

    bar:ClearAllPoints()
    bar:SetPoint("CENTER", f, "CENTER", 0, p.off or 0)
    bar:SetWidth(w)
    bar:SetHeight(h)
    p.wantW, p.wantH = w, h

    for _, t in ipairs({ p.name, p.hp, p.lvl, p.spell, p.fc and p.fc.text }) do
        A:SetFontPx(t, A.media.font, fs, "OUTLINE")
        t:SetJustifyV("MIDDLE")
    end
    -- inside the bar, all vertically centred: [level] [name ...] [health]
    p.hp:ClearAllPoints()
    p.hp:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4 * px, 0)
    p.hp:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4 * px, 0)
    p.lvl:ClearAllPoints()
    p.lvl:SetPoint("TOPLEFT", bar, "TOPLEFT", 4 * px, 0)
    p.lvl:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 4 * px, 0)
    p.name:ClearAllPoints()
    if db.showLevel then
        p.lvl:Show()
        p.name:SetPoint("TOPLEFT", p.lvl, "TOPRIGHT", 4 * px, 0)
        p.name:SetPoint("BOTTOMLEFT", p.lvl, "BOTTOMRIGHT", 4 * px, 0)
    else
        p.lvl:Hide()
        p.name:SetPoint("TOPLEFT", bar, "TOPLEFT", 4 * px, 0)
        p.name:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 4 * px, 0)
    end
    p.name:SetPoint("RIGHT", p.hp, "LEFT", -4 * px, 0)

    -- cast bar under the health bar: icon on the left, spell name inside
    local ch = A:Snap(cast, db.castHeight)
    cast:ClearAllPoints()
    cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", ch + px, -px)
    cast:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -px)
    cast:SetHeight(ch)
    p.wantCH = ch
    -- our own cast bar (mobs that aren't your target): the same spot and
    -- size, set here, not copied from the game's bar (the game can reset its
    -- bar to its own, much taller layout)
    if p.fc then
        local fc = p.fc
        fc:ClearAllPoints()
        fc:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", ch + px, -px)
        fc:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -px)
        fc:SetHeight(ch)
        fc.icon:SetWidth(ch)
    end
    p.spell:ClearAllPoints()
    p.spell:SetPoint("TOPLEFT", cast, "TOPLEFT", 4 * px, 0)
    p.spell:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -4 * px, 0)
    if p.icon then
        p.icon:ClearAllPoints()
        p.icon:SetPoint("TOPRIGHT", cast, "TOPLEFT", -px, 0)
        p.icon:SetWidth(ch)
        p.icon:SetHeight(ch)
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        p.iconBorder:ClearAllPoints()
        p.iconBorder:SetAllPoints(p.icon)
    end

    if p.raid then
        p.raid:ClearAllPoints()
        p.raid:SetPoint("RIGHT", bar, "LEFT", -4 * px, 0)
        p.raid:SetWidth(h + 4)
        p.raid:SetHeight(h + 4)
    end

    -- aura icons above the bar, left aligned
    local as = A:Snap(bar, db.auraSize)
    for i, a in ipairs(p.auras) do
        a:SetWidth(as)
        a:SetHeight(as)
        a:ClearAllPoints()
        a:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", (i - 1) * (as + px), px)
        A:SetFontPx(a.count, A.media.font, fs, "OUTLINE")
        A:SetFontPx(a.time, A.media.font, fs, "OUTLINE")
    end
end

local function AuraTime(left)
    if left >= 3600 then return floor(left / 3600) .. "h" end
    if left >= 60 then return floor(left / 60) .. "m" end
    return tostring(math.ceil(left))
end

-- Clock sweep without the client's cooldown model (which stops drawing while
-- the plate moves). The texture is dark on its left half only; rotating its
-- coordinates turns that edge into a line through the icon centre at angle a.
-- Each half of the icon shows the part of the sweep that falls inside it.
local HALF = "Interface\\AddOns\\HUI\\media\\halfplane"
local function HalfPlane(tex, theta, x0, x1)
    -- icon space: centre (0,0), corners at +-0.5; tex region x0..x1, y -0.5..0.5
    local s, c = math.sin(theta), math.cos(theta)
    local k = 1 / 1.5
    local function uv(x, y)
        -- n = (-cos, sin), d = (sin, cos); dark where n.p > 0  (u < 0.5)
        return 0.5 - k * (-c * x + s * y), 0.5 - k * (s * x + c * y)
    end
    local ulx, uly = uv(x0, 0.5)
    local llx, lly = uv(x0, -0.5)
    local urx, ury = uv(x1, 0.5)
    local lrx, lry = uv(x1, -0.5)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    tex:Show()
end

local warned
local function SetClock(a, frac)
    -- the image only loads after a full game restart; until then fall back to
    -- a dark fill growing from the top so there is always something
    if not a.halfOK then
        if not warned then
            warned = true
            A:Print("nameplate clock image not loaded yet: restart the game (not just /reload).")
        end
        a.wipeR:SetTexture(0, 0, 0, 0.6)
        a.wipeL:Hide()
        a.wipeR:SetTexCoord(0, 1, 0, 1)
        a.wipeR:ClearAllPoints()
        a.wipeR:SetPoint("TOPLEFT", a, "TOPLEFT")
        a.wipeR:SetPoint("TOPRIGHT", a, "TOPRIGHT")
        a.wipeR:SetHeight(math.max(0.01, (a:GetHeight() or 0) * math.min(frac, 1)))
        if frac > 0 then a.wipeR:Show() else a.wipeR:Hide() end
        a.fallback = true
        return
    end
    if frac <= 0 then a.wipeR:Hide(); a.wipeL:Hide() return end
    if frac >= 1 then frac = 0.9999 end
    local theta = frac * 2 * math.pi   -- clockwise from 12 o'clock
    if theta <= math.pi then
        HalfPlane(a.wipeR, theta, 0, 0.5)
        a.wipeL:Hide()
    else
        HalfPlane(a.wipeR, math.pi, 0, 0.5)
        HalfPlane(a.wipeL, theta, -0.5, 0)
    end
end

local function UpdateAuraTimes(p)
    local now = GetTime()
    for _, a in ipairs(p.auras) do
        if a:IsShown() and a.expires and a.expires > 0 then
            local left = a.expires - now
            SetTxt(a.time, left > 0 and AuraTime(left) or "")
            -- elapsed time darkened, sweeping clockwise like a clock
            local frac = (a.dur and a.dur > 0) and math.min(1, math.max(0, 1 - left / a.dur)) or 0
            SetClock(a, frac)
        elseif a.time and a.time.huiTxt ~= "" then
            SetTxt(a.time, "")
            if a.wipe then a.wipe:Hide() end
        end
    end
end

-- raid marks: which one a plate carries, read from the client's icon (one
-- texture with all eight, the shown one picked by its coordinates)
local markRecheck   -- seconds until plates are recoloured after a mark change
local MARK_COLORS = {
    { 1.00, 0.92, 0.00 },   -- 1 star
    { 0.98, 0.57, 0.00 },   -- 2 circle
    { 0.83, 0.22, 0.90 },   -- 3 diamond
    { 0.04, 0.95, 0.00 },   -- 4 triangle
    { 0.70, 0.82, 0.88 },   -- 5 moon
    { 0.00, 0.71, 1.00 },   -- 6 square
    { 1.00, 0.24, 0.17 },   -- 7 cross
    { 1.00, 1.00, 1.00 },   -- 8 skull
}
A.plateMarkColors = MARK_COLORS
local MARK_UNITS = { "target", "focus", "mouseover" }
local function RaidMark(p)
    -- the real mark, when the plate's mob is a unit the game can read
    -- (the plate's icon can lag behind a mark that was just removed)
    if IsTarget(p) and UnitExists("target") then return GetRaidTargetIndex("target") end
    if p.guid then
        for _, u in ipairs(MARK_UNITS) do
            if UnitExists(u) and UnitGUID(u) == p.guid then return GetRaidTargetIndex(u) end
        end
    end
    local r = p.raid
    if not (r and r.GetTexCoord and r:IsVisible() and r:GetAlpha() > 0 and r:GetTexture()) then return nil end
    local x, y = r:GetTexCoord()
    if not x then return nil end
    local col, row = floor(x * 4 + 0.5), floor(y * 4 + 0.5)
    local i = row * 4 + col + 1
    return (i >= 1 and i <= 8) and i or nil
end

-- p.colGen: bumped by RefreshNameplates so settings changes repaint
local colGen = 0
local function Colorize(p)
    local db = DB()
    -- threat: the client's glow texture is shown (and coloured) when you have aggro
    local threat = db.threatBorder and p.glow and p.glow:IsShown()
    local size = threat and db.threatSize or 1
    if p.borderSize ~= size then p.borderSize = size; p.health.atrBorder:SetThickness(size) end
    local br, bg_, bb = 0, 0, 0
    if threat then br, bg_, bb = p.glow:GetVertexColor() end
    if p.bcR ~= br or p.bcG ~= bg_ or p.bcB ~= bb then
        p.bcR, p.bcG, p.bcB = br, bg_, bb
        p.health.atrBorder:SetColor(br, bg_, bb, 1)
    end
    -- hostile plates in our colour (texture tint); others keep the client's
    local r, g, b = p.health:GetStatusBarColor()
    local reaction = Reaction(p.health)
    if db.customHostile and reaction == "HOSTILE" then
        local c = db.hostileColor
        r, g, b = c.r, c.g, c.b
    elseif db.customNeutral and reaction == "NEUTRAL" and db.neutralColor then
        local c = db.neutralColor
        r, g, b = c.r, c.g, c.b
    end
    -- raid marked: the bar takes the mark's colour (marks can be left out)
    local mark = db.raidColor and (p.previewMark or RaidMark(p))
    if mark and not (db.raidMarks and db.raidMarks[mark] == false) then
        local c = MARK_COLORS[mark]
        r, g, b = c[1], c[2], c[3]
    end
    -- (always: the client's own SetStatusBarColor resets the texture tint)
    local tex = p.health:GetStatusBarTexture()
    if tex then tex:SetVertexColor(r, g, b) end
    -- missing health: the background colour + opacity (General > Background)
    local bg = A.colors.backdrop
    if p.colGen ~= colGen or p.bgR ~= bg[1] or p.bgG ~= bg[2] or p.bgB ~= bg[3] or p.bgA ~= bg[4] then
        p.colGen, p.bgR, p.bgG, p.bgB, p.bgA = colGen, bg[1], bg[2], bg[3], bg[4]
        p.hbg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
        if p.cbg then p.cbg:SetVertexColor(bg[1], bg[2], bg[3], bg[4]) end
    end
end

-- your debuffs on your target's plate (3.3.5 can only read auras of real unit ids)
-- Your debuffs, remembered per mob (GUID) so plates you are not targeting keep
-- showing them (multi-dotting). 3.3.5 can only read auras of real unit ids
-- (target, focus, mouseover), so:
--  * reading those units fills the memory, with exact durations;
--  * the combat log keeps it up to date for everything else (applied, refreshed,
--    removed, died), using the duration last seen for that spell;
--  * a plate learns its mob's GUID when it is your target, under the mouse, or
--    the only plate with that name.
local cache = {}       -- guid -> { [spellName] = { icon, count, dur, expires } }
local spellDur = {}    -- spellName -> last seen duration
local MINE = { player = true, pet = true, vehicle = true }
local info = {}        -- guid -> { name, hp, max }: to find the mob's plate again later
local myGUID, petGUID   -- only your (and your pet's) debuffs are tracked

local function ReadUnit(unit)
    local guid = UnitExists(unit) and UnitGUID(unit)
    if not guid or not UnitCanAttack("player", unit) then return end
    local i = info[guid] or {}
    info[guid] = i
    i.name, i.hp, i.max = UnitName(unit), UnitHealth(unit), UnitHealthMax(unit)
    -- refill the mob's table in place (this runs several times a second)
    local t = cache[guid]
    if t then
        for _, e in pairs(t) do e.seen = nil end
    else
        t = {}
        cache[guid] = t
    end
    for i = 1, 40 do
        local name, _, icon, count, _, duration, expires, caster = UnitDebuff(unit, i)
        if not name then break end
        if caster and MINE[caster] then
            local e = t[name]
            if not e then e = {}; t[name] = e end
            e.icon, e.count, e.dur, e.expires, e.seen = icon, count, duration, expires, true
            if duration and duration > 0 then spellDur[name] = duration end
        end
    end
    for name, e in pairs(t) do
        if not e.seen then t[name] = nil end
    end
    return guid
end

local function PlateByName(name, onlyFree)
    local found
    for frame, p in pairs(plates) do
        if frame:IsShown() and p.oname:GetText() == name and (not onlyFree or not p.guid) then
            if found then return nil end   -- more than one: can't tell which
            found = p
        end
    end
    return found
end

-- A plate came back (or never knew its mob): find the mob among those you have
-- debuffs on, by name, max health and (estimated) current health.
local function Match(p, taken)
    if p.guid or not next(cache) then return end
    local name = p.oname:GetText()
    local hp = p.health:GetValue()
    local _, max = p.health:GetMinMaxValues()
    local best, bestD, second = nil, nil, nil
    local n = 0
    for guid, t in pairs(cache) do
        local i = info[guid]
        if next(t) and i and i.name == name and not taken[guid] and (not i.max or not max or i.max == max) then
            n = n + 1
            local d = math.abs((i.hp or hp) - hp)
            if not bestD or d < bestD then
                second, best, bestD = bestD, guid, d
            elseif not second or d < second then
                second = d
            end
        end
    end
    if not best then return end
    local tol = (max or 1) * 0.03
    -- the only candidate, or clearly the closest in health
    if n == 1 or (bestD <= tol and (second - bestD) > (max or 1) * 0.01) then
        SetGuid(p, best)
    end
end

-- Casts of mobs that aren't your target. The game only fills the cast bar of
-- your target's plate, so the others get ours, timed from the combat log:
-- guid -> { name, icon, start, endT, src }. Channels have no start event
-- with a length, so only normal casts show.
local casts = {}
local HOSTILE = (COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40) + (COMBATLOG_OBJECT_REACTION_NEUTRAL or 0x20)

local function OnCast(event, srcGUID, srcName, srcFlags, dstGUID, spellId, spellName)
    if event == "SPELL_CAST_START" then
        if not srcFlags or bit.band(srcFlags, HOSTILE) == 0 then return end
        local _, _, icon, _, _, _, castTime = GetSpellInfo(spellId)
        if not castTime or castTime <= 0 then return end
        local now = GetTime()
        casts[srcGUID] = { name = spellName, icon = icon, start = now, endT = now + castTime / 1000, src = srcName }
    elseif event == "SPELL_CAST_SUCCESS" or event == "SPELL_CAST_FAILED" then
        if casts[srcGUID] then casts[srcGUID] = nil end
    elseif event == "SPELL_INTERRUPT" or event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
        if casts[dstGUID] then casts[dstGUID] = nil end
    end
end

-- the cast to show on a plate (nil: none)
local function CastFor(p)
    local now = GetTime()
    if p.guid then
        local c = casts[p.guid]
        if c and now < c.endT then return c end
        return nil
    end
    -- mob not known yet: a caster with the plate's name, if only one plate has it
    local nm = p.oname:GetText()
    for g, c in pairs(casts) do
        if c.src == nm and now < c.endT then
            if PlateByName(nm, true) == p then SetGuid(p, g); return c end
            return nil
        end
    end
end

local function OnCombatLog(...)
    local _, event, srcGUID, srcName, srcFlags, dstGUID, dstName, _, spellId, spellName, _, auraType = ...
    if event:find("^SPELL_CAST_") or event == "SPELL_INTERRUPT" or event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
        OnCast(event, srcGUID, srcName, srcFlags, dstGUID, spellId, spellName)
    end
    -- quick exit for everything that isn't yours and isn't about a mob you dotted
    if srcGUID ~= myGUID and (not petGUID or srcGUID ~= petGUID) and not info[dstGUID] then return end
    if event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
        cache[dstGUID] = nil
        info[dstGUID] = nil
        return
    end
    -- keep an estimate of each known mob's health while its plate is away
    local i = info[dstGUID]
    if i and i.hp then
        local amount
        if event == "SWING_DAMAGE" then amount = select(9, ...)
        elseif event:find("_DAMAGE$") then amount = select(12, ...) end
        if amount then i.hp = math.max(0, i.hp - amount); return end
        if event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
            i.hp = math.min(i.max or i.hp, i.hp + (select(12, ...) or 0))
            return
        end
    end
    if auraType ~= "DEBUFF" then return end
    if srcGUID ~= myGUID and (not petGUID or srcGUID ~= petGUID) then return end
    if event == "SPELL_AURA_REMOVED" then
        if cache[dstGUID] then cache[dstGUID][spellName] = nil end
    elseif event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" or event == "SPELL_AURA_APPLIED_DOSE" then
        local t = cache[dstGUID] or {}
        cache[dstGUID] = t
        local e = t[spellName] or {}
        local _, _, icon = GetSpellInfo(spellName)
        e.icon = e.icon or icon
        if event == "SPELL_AURA_APPLIED_DOSE" then
            e.count = (e.count or 1) + 1
        else
            local d = spellDur[spellName]
            if d then e.dur, e.expires = d, GetTime() + d end
        end
        t[spellName] = e
        -- a single plate with that name and no mob yet: that's the one
        info[dstGUID] = info[dstGUID] or { name = dstName }
        local p = PlateByName(dstName)   -- nil when several plates share the name
        if p and not p.guid then SetGuid(p, dstGUID) end
    end
end

local sorted = {}
-- never on plates, whatever the settings say (lower-case names)
local PLATE_AURA_HIDE = {
    ["volley"] = true,
    ["misery"] = true,   -- shadow priests
}
do  -- the same names in the game's language
    local m = GetSpellInfo(33198)
    if m then PLATE_AURA_HIDE[m:lower()] = true end
end

local function UpdateAuras(p)
    local db = DB()
    local n = 0
    if db.showAuras then
        if IsTarget(p) then SetGuid(p, ReadUnit("target")) end
        local t = p.guid and cache[p.guid]
        if t then
            wipe(sorted)
            local now = GetTime()
            local hide = db.auraBlacklist or {}
            local fixed = PLATE_AURA_HIDE
            for name, e in pairs(t) do
                if e.expires and e.expires > 0 and e.expires < now - 0.5 then
                    t[name] = nil   -- ran out
                elseif not hide[lower[name]] and not fixed[lower[name]] then   -- debuffs you chose not to see, and the fixed list
                    sorted[#sorted + 1] = name
                end
            end
            table.sort(sorted)   -- stable order
            for _, name in ipairs(sorted) do
                local e = t[name]
                n = n + 1
                local a = p.auras[n]
                if a.tex ~= e.icon then a.icon:SetTexture(e.icon) end
                SetTxt(a.count, (e.count and e.count > 1) and e.count or "")
                if e.dur and e.dur > 0 and e.expires then
                    a.expires, a.dur = e.expires, e.dur
                else
                    a.expires, a.dur = nil, nil
                    a.wipe:Hide()
                end
                a.tex = e.icon
                if not a:IsShown() then a:Show() end
                if n >= MAX_AURAS then break end
            end
        end
    end
    for i = n + 1, MAX_AURAS do
        local a = p.auras[i]
        if a:IsShown() then a:Hide() end
        a.expires, a.dur, a.tex = nil, nil, nil
    end
end

-- the plate's cast bar has no spell name; your target's casts can be read
local function UpdateCastName(p)
    local name
    if p.cast:IsShown() and IsTarget(p) then
        name = UnitCastingInfo("target") or UnitChannelInfo("target")
    end
    SetTxt(p.spell, name or "")
end

-- hidden: neutral (if set) or blacklisted by name
local function Filtered(p)
    local db = DB()
    if db.hideNeutral and Reaction(p.health) == "NEUTRAL" then return true end
    local name = p.oname:GetText()
    return (name and db.blacklist[lower[name]]) and true or false
end

local function OnShow(self)
    local p = plates[self]
    if not p then return end
    for _, r in ipairs(p.parts or {}) do if r then r:SetAlpha(0); r:Hide() end end
    if Filtered(p) then
        self:Hide()
        return
    end
    p.off = nil   -- a reused plate starts from its own spot
    plateSeq = plateSeq + 1
    p.seq, p.sy = plateSeq, nil   -- and takes its place in the draw order anew
    p.bcR, p.colGen = nil, nil   -- another mob: paint everything again
    p.hp.huiTxt, p.spell.huiTxt = nil, nil
    Layout(p)   -- sets the fonts; text can only be set after that
    p.fullName = p.oname:GetText() or ""
    p.name.huiTxt = nil
    p.name:SetText(p.fullName)
    local lr, lg, lb = p.olevel:GetTextColor()
    p.lvl:SetText(p.olevel:GetText() or "")
    p.lvl:SetTextColor(lr, lg, lb)
    -- bosses ("??") and mobs above level 80: no level at all
    local ln = tonumber(p.olevel:GetText() or "")
    if (p.boss and p.boss:IsShown()) or (ln and ln > 80) then p.lvl:SetText("") end
    UpdateHealthText(p)
    FitName(p, p.fullName)
    Colorize(p)
    UpdateAuras(p)
    UpdateCastName(p)
end

-- our own parts on a plate (or on the options preview): backgrounds, 1px borders,
-- the texts and the aura icons
local function MakeParts(p)
    local health, cast, icon = p.health, p.cast, p.icon
    health:SetStatusBarTexture(A.media.bar)
    p.hbg = health:CreateTexture(nil, "BACKGROUND")
    p.hbg:SetAllPoints(health)
    p.hbg:SetTexture(A.media.blank)
    A:CreateBorder(health, 0, 0, 0)

    cast:SetStatusBarTexture(A.media.bar)
    local cbg = cast:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints(cast)
    cbg:SetTexture(A.media.blank)   -- coloured with the background setting (Colorize)
    p.cbg = cbg
    A:CreateBorder(cast, 0, 0, 0)
    -- light grey fill whatever colour the client gives the cast
    local ctex = cast:GetStatusBarTexture()
    cast:HookScript("OnValueChanged", function() if ctex then ctex:SetVertexColor(0.62, 0.62, 0.66) end end)
    if icon then
        local ib = CreateFrame("Frame", nil, cast)
        ib:SetFrameLevel(cast:GetFrameLevel() + 2)
        A:CreateBorder(ib, 0, 0, 0)
        p.iconBorder = ib
    end

    local over = CreateFrame("Frame", nil, health)
    over:SetAllPoints(health)
    over:SetFrameLevel(health:GetFrameLevel() + 3)
    local function FS(parent, justify)
        local t = parent:CreateFontString(nil, "OVERLAY")
        A:SetFontPx(t, A.media.font, DB().fontSize, "OUTLINE")
        t:SetShadowOffset(0, 0)
        t:SetJustifyH(justify)
        return t
    end
    -- mouseover highlight: a soft glow around the plate's border
    local gs = 5 * A:PX(health)
    p.hl = CreateFrame("Frame", nil, health)
    p.hl:SetFrameLevel(math.max(0, health:GetFrameLevel() - 1))
    p.hl:SetPoint("TOPLEFT", health, "TOPLEFT", -gs, gs)
    p.hl:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", gs, -gs)
    p.hl:SetBackdrop({ edgeFile = GLOW, edgeSize = gs })
    p.hl:SetBackdropBorderColor(1, 1, 1, 0.8)
    p.hl:Hide()
    p.name = FS(over, "LEFT")
    p.hp = FS(over, "RIGHT")
    p.lvl = FS(over, "RIGHT")
    local cover = CreateFrame("Frame", nil, cast)
    cover:SetAllPoints(cast)
    cover:SetFrameLevel(cast:GetFrameLevel() + 3)
    p.spell = FS(cover, "LEFT")

    -- our own cast bar for mobs that aren't your target (see CastFor): the
    -- same place and look as the game's, which only works for the target
    local px = A:PX(health)
    local fc = CreateFrame("StatusBar", nil, health)   -- placed in Layout
    fc:SetStatusBarTexture(A.media.bar)
    fc:GetStatusBarTexture():SetVertexColor(0.62, 0.62, 0.66)
    fc.bg = fc:CreateTexture(nil, "BACKGROUND")
    fc.bg:SetAllPoints(fc)
    fc.bg:SetTexture(A.media.blank)
    A:CreateBorder(fc, 0, 0, 0)
    fc.icon = fc:CreateTexture(nil, "ARTWORK")
    fc.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    fc.icon:SetPoint("TOPRIGHT", fc, "TOPLEFT", -px, 0)
    fc.icon:SetPoint("BOTTOMRIGHT", fc, "BOTTOMLEFT", -px, 0)
    local fib = CreateFrame("Frame", nil, fc)
    fib:SetAllPoints(fc.icon)
    fib:SetFrameLevel(fc:GetFrameLevel() + 2)
    A:CreateBorder(fib, 0, 0, 0)
    local ftop = CreateFrame("Frame", nil, fc)
    ftop:SetAllPoints(fc)
    ftop:SetFrameLevel(fc:GetFrameLevel() + 3)
    fc.text = FS(ftop, "LEFT")
    fc.text:SetPoint("TOPLEFT", fc, "TOPLEFT", 4 * px, 0)
    fc.text:SetPoint("BOTTOMRIGHT", fc, "BOTTOMRIGHT", -4 * px, 0)
    fc:Hide()
    p.fc = fc

    for i = 1, MAX_AURAS do
        local a = CreateFrame("Frame", nil, health)
        a:SetFrameLevel(health:GetFrameLevel() + 4)
        a.icon = a:CreateTexture(nil, "ARTWORK")
        a.icon:SetAllPoints(a)
        a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- The client's cooldown spiral stops drawing while a nameplate moves
        -- (it is a 3D model, and plates move whenever the camera does), so the
        -- elapsed time is shown as a dark fill that grows from the top instead.
        a.cd = CreateFrame("Frame", nil, a)   -- kept as a no-op for old callers
        a.cd:Hide()
        -- clock sweep drawn by hand: two half-icon textures showing a rotated
        -- half-plane (see SetClock)
        a.wipeR = a:CreateTexture(nil, "OVERLAY")
        a.halfOK = a.wipeR:SetTexture(HALF) and true or false   -- nil when the file isn't found
        a.wipeR:SetVertexColor(0, 0, 0, 0.6)
        a.wipeR:SetPoint("TOPLEFT", a, "TOP")
        a.wipeR:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT")
        a.wipeL = a:CreateTexture(nil, "OVERLAY")
        a.wipeL:SetTexture(HALF)
        a.wipeL:SetVertexColor(0, 0, 0, 0.6)
        a.wipeL:SetPoint("TOPLEFT", a, "TOPLEFT")
        a.wipeL:SetPoint("BOTTOMRIGHT", a, "BOTTOM")
        a.wipeR:Hide(); a.wipeL:Hide()
        a.wipe = { Hide = function() a.wipeR:Hide(); a.wipeL:Hide() end }
        local top = CreateFrame("Frame", nil, a)
        top:SetAllPoints(a)
        top:SetFrameLevel(a:GetFrameLevel() + 3)
        a.count = top:CreateFontString(nil, "OVERLAY")
        A:SetFontPx(a.count, A.media.font, DB().fontSize, "OUTLINE")
        a.count:SetShadowOffset(0, 0)
        a.count:SetPoint("TOPRIGHT", -1, -1)
        a.time = top:CreateFontString(nil, "OVERLAY")
        A:SetFontPx(a.time, A.media.font, DB().fontSize, "OUTLINE")
        a.time:SetShadowOffset(0, 0)
        a.time:SetPoint("CENTER", a, "CENTER", A:PX(a), 0)
        a.time:SetJustifyH("CENTER")
        A:CreateBorder(top, 0, 0, 0)
        a:Hide()
        p.auras[i] = a
    end

end

local function Kill(r)
    if not r then return end
    if r.SetTexture then r:SetTexture(nil) end
    r:SetAlpha(0)
end

-- Draw order between plates. Every plate sits on the same frame level, so
-- the parts of all plates interleave: the text of a plate behind was drawn
-- over the bar of the plate in front. Each plate's frames (the game's bars
-- and ours) are given their own band of levels instead, nearer plates
-- (lower on screen) above farther ones, your target above all.
local MAX_LEVEL = 126   -- the 3.3.5 client stores frame levels in a signed byte

local function CollectLayers(p)
    local base = p.frame:GetFrameLevel()
    local frames, offs = {}, {}
    local function walk(f)
        for _, c in ipairs({ f:GetChildren() }) do
            frames[#frames + 1] = c
            offs[#offs + 1] = math.max(0, c:GetFrameLevel() - base)
            walk(c)
        end
    end
    walk(p.frame)
    -- squeeze the levels together (same order, no gaps) so each plate needs
    -- as few levels as possible: the client allows only up to 127
    local distinct, seen = {}, {}
    for _, o in ipairs(offs) do
        if not seen[o] then seen[o] = true; distinct[#distinct + 1] = o end
    end
    table.sort(distinct)
    local idx = {}
    for i, o in ipairs(distinct) do idx[o] = i - 1 end
    local list = {}
    for i, c in ipairs(frames) do
        list[#list + 1] = c
        list[#list + 1] = idx[offs[i]]
    end
    p.layers, p.layerSpan, p.layerBase = list, math.max(1, #distinct), base
    for i = 1, #list, 2 do
        if list[i] == p.health then p.healthOff = list[i + 1] end
    end
end

-- bands start at level 1 whatever level the game gave the plate (frames are
-- ordered by level across the whole world frame, not per plate)
local function SetLayer(p, rank, span)
    local base = 1 + rank * span
    -- the game can put its own health bar back on the plate's level: check
    -- it every frame (one call) and lay the plate out again when it moved
    if p.layerRank == rank and p.layerSpanUsed == span
        and (not p.healthOff or p.health:GetFrameLevel() == math.min(MAX_LEVEL, base + p.healthOff)) then
        return
    end
    p.layerRank, p.layerSpanUsed = rank, span
    local l = p.layers
    for i = 1, #l, 2 do
        l[i]:SetFrameLevel(math.min(MAX_LEVEL, base + l[i + 1]))
    end
end

-- /run HUI:PlateLayers()  prints what the plates' frames are set to
function A:PlateLayers()
    for frame, p in pairs(plates) do
        if frame:IsShown() then
            print(format("%s: plate %d, health %d (want %s), rank %s, span %s, %d frames",
                tostring(p.oname:GetText()), frame:GetFrameLevel(), p.health:GetFrameLevel(),
                tostring(p.healthOff and (1 + (p.layerRank or 0) * (p.layerSpanUsed or 1) + p.healthOff)),
                tostring(p.layerRank), tostring(p.layerSpanUsed), p.layers and #p.layers / 2 or 0))
        end
    end
end

local function Skin(f)
    if plates[f] then return end
    local health, cast = f:GetChildren()
    local glow, border, castBorder, castShield, icon, highlight, name, level, boss, raid, elite = f:GetRegions()
    if not (health and cast and name) then return end
    local p = { frame = f, health = health, cast = cast, glow = glow, oname = name, olevel = level,
        icon = icon, raid = raid, boss = boss, auras = {} }
    plates[f] = p

    Kill(border); Kill(castBorder); Kill(castShield); Kill(elite)
    if glow then glow:SetTexCoord(0, 0, 0, 0) end   -- kept (threat colour) but draws nothing
    name:SetAlpha(0)
    level:SetAlpha(0)
    if boss then boss:SetAlpha(0) end
    if highlight then highlight:SetTexture(nil) end   -- the client's mouseover box (bigger than our bar)

    p.parts = { name, level, boss, elite, border, castBorder, castShield, highlight }
    MakeParts(p)
    CollectLayers(p)

    f:HookScript("OnShow", function() SetLive(p, true) end)
    f:HookScript("OnHide", function() SetLive(p, false) end)
    f:HookScript("OnShow", OnShow)
    f:HookScript("OnHide", function() p.guid = nil; p.hl:Hide(); p.fcRec = nil; p.fc:Hide(); p.fc.rec = nil end)   -- plates are reused for other mobs
    -- the client shows its own name / level / boss icon again and resizes the
    -- bar on every update: undo that every frame (cheap, only while visible)
    p.parts = { name, level, boss, elite, border, castBorder, castShield, highlight }
    -- the client's parts are hidden from the plate's own update (right after
    -- the client draws it); everything else is done once per frame for all
    -- plates in PlateTick, from the main driver
    -- (alpha 0 is enough to keep them invisible, shown or not: one call
    -- per part instead of two, and only the parts that exist)
    local parts, n = {}, 0
    for i = 1, 8 do
        local r = p.parts[i]
        if r then n = n + 1; parts[n] = r end
    end
    f:HookScript("OnUpdate", A:PerfWrap("Nameplates: each plate", function()
        for i = 1, n do
            local r = parts[i]
            if r:GetAlpha() > 0 then r:SetAlpha(0) end
        end
    end))
    health:HookScript("OnValueChanged", A:PerfWrap("Nameplates: health text", function() UpdateHealthText(p) end))
    -- the client re-anchors the cast bar each time a cast starts
    cast:HookScript("OnShow", function(self)
        if not DB().showCast then self:Hide() return end
        Layout(p)
        UpdateCastName(p)
    end)
    if f:IsShown() then SetLive(p, true) end
    OnShow(f)
end

-- per frame, every shown plate (values shared by all plates come in `sh`):
-- mouseover glow, fading the others, our cast bar, the size check
local sh = {}
local function PlateTick(p, f, sh)
    local db, health, cast = sh.db, p.health, p.cast
    -- mouseover highlight: the mob under the mouse, on the bar the mouse is over
    local hover = sh.moName and p.oname:GetText() == sh.moName and MouseIsOver(health)
    if hover then
        local c = db.glowColor or sh.white
        local ga = db.glowAlpha or 0.8
        if p.hlR ~= c.r or p.hlG ~= c.g or p.hlB ~= c.b or p.hlA ~= ga then
            p.hlR, p.hlG, p.hlB, p.hlA = c.r, c.g, c.b, ga
            p.hl:SetBackdropBorderColor(c.r, c.g, c.b, ga)
        end
        if not p.hl:IsShown() then p.hl:Show() end
    elseif p.hl:IsShown() then
        p.hl:Hide()
    end
    -- fade every plate but your target's (only while you have a target).
    -- The game dims the other plates a little itself (the whole plate):
    -- the health bar (and the auras / texts on it) takes the rest, so it
    -- ends at the chosen opacity. The cast bar is left alone: the game
    -- decides when it shows, and touching it kept it from showing.
    local a = 1
    if sh.fade and sh.tp ~= p then
        local fa = f:GetAlpha() or 1
        a = math.min(1, (db.fadeAlpha or 0.4) / math.max(fa, 0.01))
    end
    if (p.fadeA or 1) ~= a then
        p.fadeA = a
        health:SetAlpha(a)
    end
    -- our cast bar (mobs that aren't your target)
    local c, fc = p.fcRec, p.fc
    local castShown = cast:IsShown()
    if c and db.showCast and not castShown and sh.now < c.endT then
        if fc.rec ~= c then
            fc.rec = c
            fc.text:SetText(c.name or "")
            fc.icon:SetTexture(c.icon)
            fc:SetMinMaxValues(0, c.endT - c.start)
            if p.cbg then fc.bg:SetVertexColor(p.cbg:GetVertexColor()) end
        end
        fc:SetValue(sh.now - c.start)
        if not fc:IsShown() then fc:Show() end
    elseif fc.rec or fc:IsShown() then
        fc:Hide(); fc.rec = nil
    end
    -- size changed under us (the game resets its cast bar to its own,
    -- taller layout now and then): lay the plate out again
    if math.abs((health:GetHeight() or 0) - (p.wantH or 0)) > 0.01
        or math.abs((health:GetWidth() or 0) - (p.wantW or 0)) > 0.01
        or (castShown and CastMoved(p)) then
        Layout(p)
    end
end

local function Scan()
    local n = WorldFrame:GetNumChildren()
    if n == numKids then return end
    numKids = n
    for _, f in ipairs({ WorldFrame:GetChildren() }) do
        if not plates[f] and IsPlate(f) then Skin(f) end
    end
end

function A:RefreshNameplates()
    colGen = colGen + 1   -- settings may have changed: repaint the backgrounds
    if self.platePreview and self.platePreview:IsVisible() then self.platePreview.Refresh() end
    for _, p in pairs(plates) do
        if p.frame:IsShown() then OnShow(p.frame) end
    end
    local db = DB()
    SetCVar("nameplateShowEnemies", db.showEnemies and "1" or "0")
    -- the game only shows casts on nameplates with its own option on
    -- (Interface > Combat > enemy cast bars on nameplates): keep it on while
    -- HUI's "Show cast bar" is on
    if db.showCast and GetCVar("showVKeyCastbar") ~= "1" then SetCVar("showVKeyCastbar", "1") end
    -- our smooth stacking replaces the client's jumpy spreading
    if GetCVar("spreadnameplates") then
        SetCVar("spreadnameplates", (db.stack and not db.smoothStack) and "1" or "0")
    end
end

-- blacklist by unit name (case doesn't matter)
-- debuffs hidden from the plates (by name; a spell id is turned into its name)
function A:BlacklistPlateAura(name, add)
    name = name and tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return end
    local id = tonumber(name)
    if id then name = GetSpellInfo(id) or name end
    local db = DB()
    db.auraBlacklist = db.auraBlacklist or {}
    if add then db.auraBlacklist[name:lower()] = name else db.auraBlacklist[name:lower()] = nil end
    self:RefreshNameplates()
end

function A:BlacklistPlate(name, add)
    if not name or name == "" then return end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local key = name:lower()
    if add then DB().blacklist[key] = name else DB().blacklist[key] = nil end
    self:RefreshNameplates()
end

------------------------------------------------------------------------
-- Preview for the options window: a fake enemy plate built from the same parts
-- and laid out by the same code, scaled like the real plates, with a looping cast
------------------------------------------------------------------------
local PREVIEW_AURAS = {
    { "Interface\\Icons\\Spell_Shadow_ShadowWordPain", 0 },
    { "Interface\\Icons\\Spell_Shadow_UnstableAffliction_3", 0 },
    { "Interface\\Icons\\Spell_Shadow_AbominationExplosion", 3 },
}

function A:CreatePlatePreview(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(110)
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(holder)
    bg:SetTexture(0.16, 0.13, 0.1, 1)   -- something world-ish behind it

    local f = CreateFrame("Frame", nil, holder)
    f:SetWidth(1)
    f:SetHeight(1)
    local health = CreateFrame("StatusBar", nil, f)
    health:SetStatusBarTexture(A.media.bar)
    health:SetStatusBarColor(1, 0, 0)     -- hostile, as the client colours it
    health:SetMinMaxValues(0, 13600)
    health:SetValue(12000)
    local cast = CreateFrame("StatusBar", nil, f)
    cast:SetStatusBarTexture(A.media.bar)
    cast:SetMinMaxValues(0, 1)
    local icon = cast:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowBolt")
    local p = { frame = f, health = health, cast = cast, icon = icon, auras = {} }
    MakeParts(p)

    holder.Refresh = function()
        local db = DB()
        -- real plates live on the world frame: show the preview at that scale
        local s = WorldFrame:GetEffectiveScale() / math.max(holder:GetEffectiveScale(), 0.01)
        f:SetScale(s)
        f:ClearAllPoints()
        f:SetPoint("CENTER", holder, "CENTER", 0, (db.castHeight - db.auraSize) * s / 2 / s)
        Layout(p)
        p.lvl:SetText("78")
        p.lvl:SetTextColor(1, 0.82, 0)
        p.name:SetText("Sinewy Wolf")
        p.name:SetTextColor(1, 1, 1)
        UpdateHealthText(p)
        Colorize(p)
        p.spell:SetText("Shadow Bolt")
        if db.showCast then cast:Show() else cast:Hide() end
        for i, a in ipairs(p.auras) do
            local d = PREVIEW_AURAS[i]
            if d and db.showAuras then
                a.icon:SetTexture(d[1])
                a.count:SetText(d[2] > 1 and d[2] or "")
                a.cd:Hide()
                a.expires = nil
                SetClock(a, ({ 0.3, 0.7, 0.1 })[i] or 0)
                a.time:SetText(({ "12", "3", "1m" })[i] or "")
                a:Show()
            else
                a:Hide()
            end
        end
    end
    local t = 0
    holder:SetScript("OnUpdate", function(_, el)
        t = (t + el) % 2.5
        cast:SetValue(t / 2.5)
    end)
    holder:SetScript("OnShow", holder.Refresh)
    A.platePreview = holder
    return holder
end

------------------------------------------------------------------------
-- Smooth stacking: the client spreads plates by jumping them around (or lets them
-- overlap). Instead, plates that overlap on screen slide our bars apart, with
-- the lower plate staying put and the ones above easing upwards.
------------------------------------------------------------------------
local stackList = {}
-- Draw order follows the height on screen, but sticky: a plate's sort
-- height (sy) only follows its real height once it moved more than STICKY
-- units, so two plates at about the same height don't swap who is on top
-- every time the camera or the mobs move a pixel. Equal heights: the plate
-- seen first stays in front.
local STICKY = 8
local function SortByY(a, b)
    if a.sy ~= b.sy then return a.sy < b.sy end
    return a.seq < b.seq
end

local function Stack(el)
    local db = DB()
    local k = math.min(1, (el or 0.016) * 12)
    wipe(stackList)
    for i = 1, liveN do
        local p = live[i]
        do
            local x, y = p.frame:GetCenter()
            if x then
                p.x, p.y = x, y
                if not p.seq then plateSeq = plateSeq + 1; p.seq = plateSeq end
                if not p.sy or math.abs(y - p.sy) > STICKY then p.sy = y end
                stackList[#stackList + 1] = p
            end
        end
    end
    local n = #stackList
    if n == 0 then return end
    if n > 1 then table.sort(stackList, SortByY) end

    -- draw order: stackList runs from the lowest plate on screen (nearest)
    -- upwards; the nearest gets the highest band, the target the top one
    local span = 1
    for i = 1, n do
        local q = stackList[i]
        if (q.layerSpan or 1) > span then span = q.layerSpan end
    end
    -- how many bands fit under the client's limit: the nearest plates get
    -- their own, the farthest share the bottom one
    local bands = math.max(1, math.floor((MAX_LEVEL - 1) / span))
    local tp = UnitExists("target") and TargetPlate() or nil
    local top = bands - 1
    local rank = tp and top - 1 or top   -- the target takes the top band
    for i = 1, n do
        local p = stackList[i]
        if p.layers and p ~= tp then
            SetLayer(p, math.max(0, rank), span)
            rank = rank - 1
        end
    end
    if tp and tp.layers then SetLayer(tp, top, span) end

    if not db.smoothStack then
        -- no stacking: every bar just goes back to (and stays at) its own spot
        for i = 1, n do
            local p = stackList[i]
            local off = p.off
            if off and off ~= 0 then
                if math.abs(off) < 0.05 then off = 0 else off = off - off * k end
                p.off = off
                p.health:ClearAllPoints()
                p.health:SetPoint("CENTER", p.frame, "CENTER", 0, off)
            end
        end
        return
    end
    -- every plate has the same scale: sizes measured once
    local first = stackList[1].health
    local px = A:PX(first)
    local w = A:Snap(first, db.width)
    local h = A:Snap(first, db.height) + A:Snap(first, db.castHeight) + 3 * px
    local xgap = w + 2 * px
    for i = 1, n do
        local p = stackList[i]
        local final = p.y
        local x = p.x
        for j = 1, i - 1 do
            local q = stackList[j]
            local dx = x - q.x
            if dx < xgap and dx > -xgap and final < q.final + h and final > q.final - h then
                final = q.final + h
            end
        end
        p.final = final
        local want = final - p.y
        local off = p.off or 0
        if math.abs(want - off) < 0.05 then off = want else off = off + (want - off) * k end
        if off ~= p.off then
            p.off = off
            p.health:ClearAllPoints()
            p.health:SetPoint("CENTER", p.frame, "CENTER", 0, off)
        end
    end
end

Stack = A:PerfWrap("Nameplates: stacking (part of update)", Stack)

local takenBuf = {}   -- reused every quarter second
function A:BuildNameplates()
    local acc, slow, prune = 0, 0, 0
    myGUID, petGUID = UnitGUID("player"), UnitGUID("pet")
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", A:PerfWrap("Nameplates: update + stacking", function(_, el)
        Scan()
        if markRecheck then
            markRecheck = markRecheck - el
            if markRecheck <= 0 then
                markRecheck = nil
                for frame, p in pairs(plates) do
                    if frame:IsShown() then Colorize(p) end
                end
            end
        end
        -- link the target's plate as soon as it's known (before you switch away)
        local tp = TargetPlate()
        if tp and UnitExists("target") and UnitCanAttack("player", "target") then
            local g = UnitGUID("target")
            if tp.guid ~= g then SetGuid(tp, g); ReadUnit("target") end
        end
        Stack(el)
        -- per-plate work, with what every plate needs looked up once
        local db = DB()
        sh.db, sh.now, sh.white = db, GetTime(), sh.white or { r = 1, g = 1, b = 1 }
        sh.moName = db.mouseHighlight and UnitExists("mouseover") and UnitName("mouseover") or nil
        sh.fade = db.fadeOthers and UnitExists("target") and true or false
        sh.tp = sh.fade and TargetPlate() or nil
        for i = 1, liveN do
            local p = live[i]
            PlateTick(p, p.frame, sh)
        end
        acc = acc + el
        slow = slow + el
        if acc < 0.1 then return end
        acc = 0
        local auras = slow > 0.25
        if auras then slow = 0 end
        -- mobs already shown on a plate (for matching plates that came back)
        local taken
        if auras then
            taken = takenBuf
            wipe(taken)
            for fr, q in pairs(plates) do
                if q.guid and fr:IsShown() then taken[q.guid] = true end
            end
        end
        -- every few seconds forget ran-out debuffs and mobs with nothing left
        prune = prune + 0.1
        if prune > 5 then
            prune = 0
            local now = GetTime()
            for guid, t in pairs(cache) do
                for name, e in pairs(t) do
                    if e.expires and e.expires > 0 and e.expires < now - 1 then t[name] = nil end
                end
                if not next(t) then cache[guid] = nil end
            end
            for guid in pairs(info) do
                if not cache[guid] and not (taken and taken[guid]) then info[guid] = nil end
            end
            for guid, c in pairs(casts) do
                if c.endT < now then casts[guid] = nil end
            end
        end
        for frame, p in pairs(plates) do
            if frame:IsShown() then
                if Filtered(p) then
                    frame:Hide()
                else
                    Colorize(p)
                    p.fcRec = CastFor(p)
                    if auras then
                        if not p.guid then Match(p, taken) end
                        if p.guid and info[p.guid] then
                            local i = info[p.guid]
                            i.hp = p.health:GetValue()
                            local _, mx = p.health:GetMinMaxValues()
                            i.max = mx
                        end
                        UpdateAuras(p); UpdateCastName(p)
                    end
                    UpdateAuraTimes(p)
                end
            end
        end
    end))
    for _, e in ipairs({ "RAID_TARGET_UPDATE", "PLAYER_TARGET_CHANGED", "UNIT_AURA", "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_CHANNEL_START", "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED",
        "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", A:PerfWrap("Nameplates: events", function(_, event, unit, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog(unit, ...)
            return
        end
        if event == "RAID_TARGET_UPDATE" then
            -- a mark was set or removed: recolour now (the client updates the
            -- plate icons in the same frame, so look again a moment later too)
            for frame, p in pairs(plates) do
                if frame:IsShown() then Colorize(p) end
            end
            markRecheck = 0.15
            return
        end
        if event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
            myGUID, petGUID = UnitGUID("player"), UnitGUID("pet")
            return
        end
        if event == "UPDATE_MOUSEOVER_UNIT" then
            -- the plate under the mouse is this mob
            local guid = ReadUnit("mouseover")
            if guid then
                -- only when exactly one plate of that name is under the mouse
                local name, hit = UnitName("mouseover"), nil
                for frame, p in pairs(plates) do
                    if frame:IsShown() and MouseIsOver(frame) and p.oname:GetText() == name then
                        if hit then hit = false; break end
                        hit = p
                    end
                end
                if hit then SetGuid(hit, guid); UpdateAuras(hit) end
            end
            return
        end
        if event == "PLAYER_FOCUS_CHANGED" or (event == "UNIT_AURA" and unit == "focus") then
            local guid = ReadUnit("focus")
            if guid then
                local p = PlateByName(UnitName("focus"))
                if p then SetGuid(p, guid) end
            end
        end
        if event == "UNIT_AURA" and unit == "mouseover" then ReadUnit("mouseover") end
        if unit and unit ~= "target" and unit ~= "focus" then return end
        if unit then
            -- one unit changed: only its plate (and the target's) can show it
            local tp = TargetPlate()
            local guid = UnitGUID(unit)
            for frame, p in pairs(plates) do
                if frame:IsShown() and (p == tp or (guid and p.guid == guid)) then
                    UpdateAuras(p)
                    UpdateCastName(p)
                end
            end
            return
        end
        for frame, p in pairs(plates) do
            if frame:IsShown() then
                UpdateAuras(p)
                UpdateCastName(p)
            end
        end
    end))
    self:RefreshNameplates()
end
