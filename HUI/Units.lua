-- HUI - Unit frames (player, target, focus, pet)

local A = HUI
local floor, pairs, ipairs = math.floor, pairs, ipairs
local SetTxt, lower = A.SetTxt, A.lower

A.allFrames = {}   -- every frame that displays a unit (unit frames + raid buttons)
A.units = {}       -- key -> unit frame

------------------------------------------------------------------------
-- Elements (shared with raid buttons)
------------------------------------------------------------------------
function A:UpdateName(f)
    if not f.name then return end
    local u = f.unit
    local r, g, b = self:UnitColor(u)
    local nameLen = f.cfg.nameLen or 20
    -- target of target after the name: "Name » ToT" (ToT in its class colour)
    local tot = ""
    if f.cfg.totName then
        local tu = u .. "target"
        if UnitExists(tu) then
            local tr, tg, tb = self:UnitColor(tu)
            nameLen = f.cfg.totNameLen or 14
            tot = " |cffbbbbbb\194\187|r " .. self:Hex(tr, tg, tb) .. self:Truncate(UnitName(tu) or "", f.cfg.totLen or 12) .. "|r"
        end
    end
    local name = self:Truncate(UnitName(u) or "", nameLen)
    local prefix = ""
    if f.cfg.showLevel then
        local lvl = UnitLevel(u)
        local cls = UnitClassification(u)
        local plus = (cls == "elite" or cls == "worldboss" or cls == "rareelite") and "+" or ""
        if cls == "rare" or cls == "rareelite" then plus = plus .. "R" end
        if lvl and (lvl < 0 or lvl > 80) then
            prefix = ""   -- bosses / mobs above 80: no "??" or level
        elseif lvl and (lvl ~= UnitLevel("player") or plus ~= "") then
            local fn = GetQuestDifficultyColor or GetDifficultyColor
            local c = fn and fn(lvl) or { r = 1, g = 0.82, b = 0 }
            prefix = self:Hex(c.r, c.g, c.b) .. lvl .. plus .. "|r "
        end
    end
    if f.threatReserve then
        -- raid: cut to the room there is, without the game's "..."
        f.huiNamePre, f.huiNamePlain, f.huiNameColor = prefix, name, self:Hex(r, g, b)
        self:FitName(f)
    else
        SetTxt(f.name, prefix .. self:Hex(r, g, b) .. name .. "|r" .. tot)
    end
end

-- Raid names: a name wider than its space is cut letter by letter (no "...",
-- which the game adds by itself when the text doesn't fit). Called again
-- when the space changes (heal icons on the top edge, frame size).
local function Utf8Len(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end
function A:FitName(f)
    local n, plain = f.name, f.huiNamePlain
    if not (n and plain) then return end
    local pre, col = f.huiNamePre or "", f.huiNameColor or ""
    local l, r = n:GetLeft(), n:GetRight()
    local room = (l and r) and (r - l + 0.5) or nil
    -- same name, colour and room as last time: already fitted
    if room and f.fitPlain == plain and f.fitPre == pre and f.fitCol == col and f.fitRoom == room then return end
    f.fitPlain, f.fitPre, f.fitCol, f.fitRoom = plain, pre, col, room
    n.huiTxt = nil
    n:SetText(pre .. col .. plain .. "|r")
    if not room then f.fitPlain = nil return end
    if n:GetStringWidth() <= room then return end
    for len = Utf8Len(plain) - 1, 1, -1 do
        n:SetText(pre .. col .. self:Truncate(plain, len) .. "|r")
        if n:GetStringWidth() <= room then return end
    end
end

-- Smooth health: the bar glides to the new value instead of jumping. A new
-- unit (target change, raid slot reuse) or a new maximum jumps straight there.
local smoothing = {}
local smoother = CreateFrame("Frame")
smoother:Hide()
smoother:SetScript("OnUpdate", A:PerfWrap("Unit frames: health smoothing", function(self, el)
    local k = math.min(1, el * 10)   -- ~0.3s to settle
    local any = false
    for bar, target in pairs(smoothing) do
        local cur = bar:GetValue()
        local max = bar.huiMax
        local nv = cur + (target - cur) * k
        if math.abs(target - nv) <= (max or 1) * 0.002 then
            bar:SetValue(target)
            smoothing[bar] = nil
        else
            bar:SetValue(nv)
            any = true
        end
    end
    if not any then self:Hide() end
end))

function A:SetBarSmooth(bar, value, max, owner)
    local oldMax = bar.huiMax
    if oldMax ~= max then
        bar.huiMax = max
        bar:SetMinMaxValues(0, max)
    end
    if not self.db.smoothHealth or bar.atrOwner ~= owner or oldMax ~= max or not bar:IsVisible() then
        bar.atrOwner = owner
        smoothing[bar] = nil
        bar:SetValue(value)
        return
    end
    if math.abs(bar:GetValue() - value) < 0.5 then smoothing[bar] = nil; return end
    smoothing[bar] = value
    smoother:Show()
end

function A:UpdateHealth(f)
    local u = f.unit
    local cur, max = UnitHealth(u), UnitHealthMax(u)
    if not max or max <= 0 then max = 1 end
    -- dead / offline: draw the bar full (it is coloured as a plain dark panel);
    -- an empty bar has no texture to hang the background off and looked broken
    local gone = not UnitIsConnected(u) or UnitIsDeadOrGhost(u)
    local guid = UnitGUID(u) or ""
    self:SetBarSmooth(f.health, gone and max or cur, max, gone and (guid .. "-gone") or guid)
    self:ColorHealth(f.health, u)

    -- raid frames: no "Dead" / "Ghost" text (the frame's dead colour says it)
    local deadRaid = f.cfg.raid and UnitIsConnected(u) and UnitIsDeadOrGhost(u)

    local t = f.hpText
    if not t then return end
    if deadRaid then
        SetTxt(t, "")
    elseif not UnitIsConnected(u) then
        SetTxt(t, "|cff999999Offline|r")
    elseif UnitIsGhost(u) then
        SetTxt(t, "|cff999999Ghost|r")
    elseif UnitIsDead(u) then
        SetTxt(t, "|cff999999Dead|r")
    else
        local fmt = f.cfg.hpFormat
        if fmt == "deficit" and f.cfg.raid and not self.db.raidDeficit then fmt = "none" end
        -- same numbers as last time: the text is already right
        if t.huiCur == cur and t.huiMaxV == max and t.huiFmt == fmt and t.huiTxt then return end
        t.huiCur, t.huiMaxV, t.huiFmt = cur, max, fmt
        local pct = floor(cur / max * 100 + 0.5)
        if fmt == "both" then
            SetTxt(t, self:Short(cur) .. " | " .. pct .. "%")
        elseif fmt == "pct" then
            SetTxt(t, pct .. "%")
        elseif fmt == "cur" then
            SetTxt(t, self:Short(cur))
        elseif fmt == "deficit" then
            local d = max - cur
            SetTxt(t, d > 0 and ("|cffff6666-" .. self:Short(d) .. "|r") or "")
        else
            SetTxt(t, "")
        end
        return
    end
    t.huiCur = nil
end

function A:UpdatePower(f)
    local p = f.power
    if not p and not f.powerText then return end
    local u = f.unit
    local max = UnitPowerMax(u)
    local pType, pToken = UnitPowerType(u)
    local c = (pToken and PowerBarColor[pToken]) or PowerBarColor[pType] or PowerBarColor["MANA"]
    -- mana uses the runic power colour
    if (pToken == "MANA" or pType == 0) and PowerBarColor["RUNIC_POWER"] then c = PowerBarColor["RUNIC_POWER"] end
    -- units without power (most NPCs): no empty strip, the health bar fills the frame
    local has = (max and max > 0) and true or false
    local dead = UnitIsConnected(u) and UnitIsDeadOrGhost(u) and true or false
    local pt = f.powerText
    if pt then
        if has and not dead then
            SetTxt(pt, floor(UnitPower(u) / max * 100 + 0.5) .. "%")
            if pt.huiCol ~= c then pt.huiCol = c; pt:SetTextColor(c.r, c.g, c.b) end
            if not pt:IsShown() then pt:Show() end
        elseif pt:IsShown() then
            pt:Hide()
        end
    end
    if not p then return end
    if f.healthH and has ~= f.hasPower then
        f.hasPower = has
        local h, px = f.health, self:PX(f)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", px, -px)
        h:SetPoint("TOPRIGHT", -px, -px)
        if has then
            h:SetHeight(self:Snap(f, f.cfg.height) - 2 * px - p:GetHeight() - px)
            p:Show()
            if f.powerSep then f.powerSep:Show() end
        else
            h:SetPoint("BOTTOM", f, "BOTTOM", 0, px)
            p:Hide()
            if f.powerSep then f.powerSep:Hide() end
        end
    end
    local pmax = has and max or 1
    if p.huiMax ~= pmax then p.huiMax = pmax; p:SetMinMaxValues(0, pmax) end
    p:SetValue(has and UnitPower(u) or 0)
    -- colours only when they change (the ticker calls this 10 times a second)
    local key = dead and "dead" or c
    if p.huiCol == key then return end
    p.huiCol = key
    if dead then
        -- dead: the power bar takes the dead colour with the rest of the frame
        local dr, dg, db = self:DeadColor()
        p:SetStatusBarColor(dr, dg, db)
        p.bg:SetVertexColor(dr, dg, db)
        if f.powerSep then f.powerSep:SetTexture(dr, dg, db, 1) end
        f.powerSepDead = true
    else
        p:SetStatusBarColor(c.r, c.g, c.b)
        p.bg:SetVertexColor(c.r * 0.2, c.g * 0.2, c.b * 0.2)
        if f.powerSepDead and f.powerSep then f.powerSep:SetTexture(0, 0, 0, 1); f.powerSepDead = nil end
    end
end

function A:UpdateRaidIcon(f)
    local icon = f.raidIcon
    if not icon then return end
    local idx = GetRaidTargetIndex(f.unit)
    if idx == icon.huiIdx then return end
    icon.huiIdx = idx
    if idx then
        SetRaidTargetIconTexture(icon, idx)
        icon:Show()
    else
        icon:Hide()
    end
end

------------------------------------------------------------------------
-- Auras
------------------------------------------------------------------------
A.auraBlacklist = {
    [6788] = true,   -- Weakened Soul
    [25771] = true,  -- Forbearance
    [57723] = true,  -- Exhaustion
    [57724] = true,  -- Sated
    [41425] = true,  -- Hypothermia
    [11196] = true,  -- Recently Bandaged
    [26013] = true,  -- Deserter
    [71041] = true,  -- Dungeon Deserter
    [69127] = true,  -- Chill of the Throne
    [74502] = true,  -- Enervating Brand (Ruby Sanctum, Baltharus)
}
-- by name too, so every difficulty's version of a debuff is caught
A.auraBlacklistNames = {
    ["Enervating Brand"] = true,
    ["Quel'Delar's Compulsion"] = true,   -- Quel'Delar quest line
    ["Strange Feeling"] = true,
}
for id in pairs(A.auraBlacklist) do
    local n = GetSpellInfo(id)
    if n then A.auraBlacklistNames[n] = true end
end

local function AuraOnEnter(self)
    if not self.unit or not self.index then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetUnitAura(self.unit, self.index, self.filter)
end
local function AuraOnLeave() GameTooltip:Hide() end

function A:CreateAuraIcon(parent, size, mouse)
    local b = CreateFrame("Frame", nil, parent)
    self:Size(b, self:Snap(parent, size))
    self:SetTemplate(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    local ipx = self:PX(parent)
    b.icon:SetPoint("TOPLEFT", ipx, -ipx)
    b.icon:SetPoint("BOTTOMRIGHT", -ipx, ipx)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetReverse(true)

    local ov = CreateFrame("Frame", nil, b)
    ov:SetAllPoints(b)
    ov:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.count = self:Font(ov, 10, "RIGHT")
    A:SetFontPx(b.count, A.media.font, A:FS("auras"), "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", 1, 1)

    b.time = self:Font(ov, 10, "CENTER")
    A:SetFontPx(b.time, A.media.font, A:FS("auras"), "OUTLINE")
    b.time:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.time:Hide()

    if mouse then
        b:EnableMouse(true)
        b:SetScript("OnEnter", AuraOnEnter)
        b:SetScript("OnLeave", AuraOnLeave)
    else
        b:EnableMouse(false)
    end
    return b
end

local dispelClasses = {
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    SHAMAN  = { Poison = true, Disease = true, Curse = true },
    DRUID   = { Curse = true, Poison = true },
    MAGE    = { Curse = true },
}
local _, playerClass = UnitClass("player")
A.canDispel = dispelClasses[playerClass] or {}

local function ShortTime(t)
    if t >= 3600 then return math.floor(t / 3600 + 0.5) .. "h" end
    if t >= 60 then return math.floor(t / 60 + 0.5) .. "m" end
    return tostring(math.floor(t + 0.5))
end
A.ShortTime = ShortTime

local function AuraTimeUpdate(b, el)
    b.atrT = (b.atrT or 0) + el
    if b.atrT < 0.1 then return end
    b.atrT = 0
    local left = (b.expires or 0) - GetTime()
    SetTxt(b.time, left > 0 and ShortTime(left) or "")
end

local function IsMine(caster)
    return caster == "player" or caster == "pet" or caster == "vehicle"
end

AuraTimeUpdate = A:PerfWrap("Unit frames: aura timers", AuraTimeUpdate)

function A:UpdateAuraGroup(f, g)
    local u = f.unit
    local shown, i = 0, 1
    local onlyMine = g.onlyMine or (g.onlyMineOption and self.db[g.onlyMineOption])
    -- "only my debuffs" is for enemies: on a friendly unit every debuff shows
    if onlyMine and g.onlyMineOption and u and not UnitCanAttack("player", u) then onlyMine = false end
    local harmful = g.filter == "HARMFUL"
    if (g.hideOption and self.db[g.hideOption])
        or (g.enemyOnly and u and UnitExists(u) and not UnitCanAttack("player", u)) then
        for _, b in ipairs(g.icons) do b:Hide() end
        return
    end
    while true do
        if shown >= g.num and not g.trackDispel then break end
        local name, _, icon, count, dtype, duration, expires, caster, _, _, spellId = UnitAura(u, i, g.filter)
        if not name then break end

        if harmful and g.trackDispel and dtype and self.canDispel[dtype] and not f.dispelType then
            f.dispelType = dtype
        end

        local ok = true
        if onlyMine and not IsMine(caster) then ok = false end
        if g.blacklist and ((spellId and self.auraBlacklist[spellId]) or self.auraBlacklistNames[name]) then ok = false end
        if g.hideNames and g.hideNames[name] then ok = false end
        -- your own list (Unit Frames > Target: hidden debuffs)
        if g.userHide then
            local list = self.db[g.userHide]
            if list and name and list[lower[name]] then ok = false end
        end
        -- shown big in the middle already (Raid Frames > Important debuffs)
        if harmful and g.filter == "HARMFUL" and f.impIndex == i then ok = false end

        if ok and shown < g.num then
            shown = shown + 1
            local b = g.icons[shown]
            if not b then
                b = self:CreateAuraIcon(g.parent or f, g.size, g.mouse)
                local col = (shown - 1) % g.perRow
                local row = floor((shown - 1) / g.perRow)
                local px = self:PX(f)
                local step = self:Snap(f, g.size) + g.spacing * px
                b:SetPoint(g.point, g.anchor or f, g.relPoint,
                    g.x * px + col * step * g.growX,
                    g.y * px + row * step * g.growY)
                g.icons[shown] = b
            end
            b.unit, b.index, b.filter = u, i, g.filter
            if b.tex ~= icon then b.tex = icon; b.icon:SetTexture(icon) end
            SetTxt(b.count, (count and count > 1) and count or "")
            if duration and duration > 0 and expires then
                -- the same aura as last time: leave the sweep running
                if b.cdExp ~= expires or b.cdDur ~= duration then
                    b.cdExp, b.cdDur = expires, duration
                    CooldownFrame_SetTimer(b.cd, expires - duration, duration, 1)
                end
                b.cd:Show()
            elseif b.cdExp then
                b.cdExp, b.cdDur = nil, nil
                b.cd:Hide()
            end
            if g.showTime and duration and duration > 0 and expires then
                b.expires = expires
                if not b.timing then
                    b.timing = true
                    b.time:Show()
                    b:SetScript("OnUpdate", AuraTimeUpdate)
                end
            elseif b.timing ~= false then
                b.timing = false
                b.expires = nil
                b.time:Hide()
                b:SetScript("OnUpdate", nil)
            end
            if not b.huiBorderSet then b.huiBorderSet = true; b:SetBackdropBorderColor(0, 0, 0) end
            if harmful then
                local desat = (g.desatOthers and not IsMine(caster)) and 1 or nil
                if b.desat ~= desat then b.desat = desat; b.icon:SetDesaturated(desat) end
            end
            if not b:IsShown() then b:Show() end
        end
        i = i + 1
    end
    for n = shown + 1, #g.icons do
        local b = g.icons[n]
        if b:IsShown() then b:Hide() end
    end
end

function A:UpdateAuras(f)
    if f.indicators then self:UpdateIndicators(f) end
    if not f.auraGroups then return end
    f.dispelType = nil
    for _, g in ipairs(f.auraGroups) do
        self:UpdateAuraGroup(f, g)
    end
    if f.UpdateBorder then f:UpdateBorder() end
end

function A:AddAuraGroup(f, g)
    g.icons = {}
    g.spacing = g.spacing or 1
    g.growX = g.growX or 1
    g.growY = g.growY or 1
    g.perRow = g.perRow or g.num
    f.auraGroups = f.auraGroups or {}
    table.insert(f.auraGroups, g)
end

------------------------------------------------------------------------
-- Combo points (target frame)
------------------------------------------------------------------------
function A:UpdateCombo(f)
    if not f.combo then return end
    local who = UnitHasVehicleUI("player") and "vehicle" or "player"
    local cp = GetComboPoints(who, "target") or 0
    if cp == f.combo.huiCP and (cp == 0) ~= f.combo:IsShown() then return end
    f.combo.huiCP = cp
    if cp == 0 then f.combo:Hide() return end
    f.combo:Show()
    for i = 1, 5 do
        if i <= cp then
            f.combo[i].fill:SetVertexColor(1, 0.85 - i * 0.12, 0.1)
            f.combo[i].fill:SetAlpha(1)
        else
            f.combo[i].fill:SetAlpha(0)
        end
    end
end

------------------------------------------------------------------------
-- Aggro: a small square in the top-left corner (yellow / orange / red)
------------------------------------------------------------------------
-- names that start in the top-left corner move right while the square shows,
-- so it never covers the first letters. Raid frames instead keep a small
-- square and leave room for it all the time (f.threatReserve), so their names
-- never move.
A.RAID_THREAT_SIZE = 6   -- raid square in screen pixels (1px edge + 4px colour)
local function ShiftName(f, on)
    if f.threatReserve then return end
    local n = f.name
    if not (n and n.GetPoint) then return end
    local p, rel, rp, x, y = n:GetPoint(1)
    if p ~= "TOPLEFT" then
        if n:GetNumPoints() < 2 then return end
        p, rel, rp, x, y = n:GetPoint(2)
        if p ~= "TOPLEFT" then return end
    end
    if on then
        local want = (f.huiNameBaseX or x) + A:DP(9) * A:PX(f)
        if not f.huiNameBaseX then f.huiNameBaseX = x end
        if math.abs(x - want) > 0.001 then n:SetPoint("TOPLEFT", rel, rp, want, y) end
    elseif f.huiNameBaseX then
        n:SetPoint("TOPLEFT", rel, rp, f.huiNameBaseX, y)
        f.huiNameBaseX = nil
    end
end

-- the square itself (made on first use); also used by the raid test preview
function A:ThreatSquare(f)
    local sq = f.atrThreat
    if sq then return sq end
    sq = CreateFrame("Frame", nil, f)
    sq:SetFrameLevel(f:GetFrameLevel() + 8)
    local px = self:PX(f)
    if f.threatReserve and f.health then
        -- raid: smaller, against the left edge of the health bar and centred
        -- on the name line (the name starts right after it)
        local s = A:DP(A.RAID_THREAT_SIZE) * px
        if f.name then
            -- centred on the letters: the game draws the name well below the
            -- middle of its box (measured in game: 6px lower than the box centre)
            sq:SetPoint("LEFT", f.health, "LEFT", -px, 0)
            sq:SetPoint("TOP", f.name, "TOP", 0, -(A:Snap(f, ((f.name:GetHeight() or 13) - s) / 2) + A:DP(6) * px))
        else
            sq:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, -px)
        end
        sq:SetWidth(s); sq:SetHeight(s)
    else
        sq:SetPoint("TOPLEFT", f, "TOPLEFT", A:DP(2) * px, -A:DP(2) * px)
        sq:SetWidth(A:DP(8) * px); sq:SetHeight(A:DP(8) * px)   -- 1px black edge around a 6px colour fill
    end
    sq.bd = sq:CreateTexture(nil, "BACKGROUND")
    sq.bd:SetTexture(0, 0, 0, 1)
    sq.bd:SetAllPoints(sq)
    sq.fill = sq:CreateTexture(nil, "ARTWORK")
    sq.fill:SetTexture(self.media.blank)
    sq.fill:SetPoint("TOPLEFT", px, -px)
    sq.fill:SetPoint("BOTTOMRIGHT", -px, px)
    f.atrThreat = sq
    return sq
end

function A:UpdateThreat(f)
    local u = f.unit
    local sq = f.atrThreat
    if not u or u == "targettarget" or u == "target" or not UnitExists(u) then
        if sq then sq:Hide(); ShiftName(f, false) end
        return
    end
    local status = UnitThreatSituation(u)
    if not status or status < 1 then
        if sq then sq:Hide(); ShiftName(f, false) end
        return
    end
    sq = sq or self:ThreatSquare(f)
    if sq.huiStatus ~= status or not sq:IsShown() then
        sq.huiStatus = status
        local r, g, b = GetThreatStatusColor(status)
        sq.fill:SetVertexColor(r, g, b)
        sq:Show()
        ShiftName(f, true)
    end
end

------------------------------------------------------------------------
-- Full update
------------------------------------------------------------------------
-- a full redraw: forget what the cheap paths remember (settings may have
-- changed, or test previews drew over the frame)
local function ClearCaches(f)
    if f.health then f.health.hcMode = nil; f.health.huiMax = nil end
    if f.power then f.power.huiCol = nil; f.power.huiMax = nil end
    if f.hpText then f.hpText.huiTxt = nil; f.hpText.huiCur = nil end
    if f.powerText then f.powerText.huiTxt = nil; f.powerText.huiCol = nil end
    if f.name then f.name.huiTxt = nil end
    if f.raidIcon then f.raidIcon.huiIdx = false end
    f.fitPlain = nil
    f.huiBorder = nil
end
A.ClearFrameCaches = ClearCaches

function A:UpdateAll(f)
    if not f.unit or not UnitExists(f.unit) then return end
    ClearCaches(f)
    self:UpdateName(f)
    self:UpdateHealth(f)
    self:UpdatePower(f)
    self:UpdateRaidIcon(f)
    self:UpdateAuras(f)
    if f.combo then self:UpdateCombo(f) end
    if f.UpdateBorder then f:UpdateBorder() end
    self:UpdateThreat(f)
    if f.roleIcon then self:UpdateRole(f) end
    if f.castbar then self:CastbarCheck(f.castbar) end
end

------------------------------------------------------------------------
-- Unit frame factory
------------------------------------------------------------------------
local function OnShow(self) A:UpdateAll(self) end

function A:CreateUnitFrame(key, unit, cfg)
    local f = CreateFrame("Button", "HUI" .. key, UIParent, "SecureUnitButtonTemplate")
    f.key, f.unit, f.cfg = key, unit, cfg
    f:SetAttribute("unit", unit)
    f:SetAttribute("toggleForVehicle", true)
    self:SetupClicks(f)
    self:Size(f, cfg.width, cfg.height)
    f:SetScale(self.db.scale)   -- scale first, so the 1px border is computed for it
    self:Size(f, self:Snap(f, cfg.width), self:Snap(f, cfg.height))
    self:SetTemplate(f)
    self:CreateBorder(f, 0, 0, 0)
    f:SetScript("OnEnter", UnitFrame_OnEnter)
    f:SetScript("OnLeave", UnitFrame_OnLeave)
    f:HookScript("OnShow", OnShow)

    local px = self:PX(f)
    -- power bars are optional; their thickness is in screen pixels (Unit Frames)
    local ph = (self.db.showPower and (cfg.power or 0) > 0) and math.max(1, self.db.powerHeight or 1) * px or 0
    local health = self:StatusBar(f)
    health:SetPoint("TOPLEFT", px, -px)
    health:SetPoint("TOPRIGHT", -px, -px)
    if ph > 0 then
        health:SetHeight(self:Snap(f, cfg.height) - 2 * px - ph - px)
    else
        health:SetPoint("BOTTOM", f, "BOTTOM", 0, px)
    end
    f.health = health

    if ph > 0 then
        local power = self:StatusBar(f)
        power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -px)
        power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -px)
        power:SetHeight(ph)
        -- 1px separator line between health and power
        local sep = f:CreateTexture(nil, "BORDER")
        sep:SetTexture(0, 0, 0, 1)
        sep:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", power, "TOPRIGHT", 0, 0)
        f.power, f.powerSep, f.healthH = power, sep, true
    end

    local fs = cfg.fontSize or 13
    if cfg.twoLine then
        -- name on top; health "cur | %" under it on the left; power % bottom right
        f.name = self:Font(health, fs, "LEFT")
        f.name:SetHeight(fs + 4)
        f.name:SetPoint("TOPLEFT", health, "TOPLEFT", 4, -1)
        f.name:SetPoint("TOPRIGHT", health, "TOPRIGHT", -4, -1)
        f.hpText = self:Font(health, fs, "LEFT")
        f.hpText:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 4, 3)
        if cfg.powerPct then
            f.powerText = self:Font(health, fs, "RIGHT")
            f.powerText:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -4, 3)
        end
    elseif cfg.hpFormat and cfg.hpFormat ~= "none" then
        f.hpText = self:Font(health, fs, "RIGHT")
        f.hpText:SetPoint("RIGHT", health, "RIGHT", -4, 0)
    end
    if not cfg.noName and not cfg.twoLine then
        f.name = self:Font(health, fs, cfg.nameCenter and "CENTER" or "LEFT")
        f.name:SetHeight(fs + 4)
        if cfg.nameCenter then
            -- centred names sit a pixel low (font ascent): lift them 1px
            local up = self:PX(health)
            f.name:SetPoint("LEFT", health, "LEFT", 2, up)
            f.name:SetPoint("RIGHT", health, "RIGHT", -2, up)
        else
            f.name:SetPoint("LEFT", health, "LEFT", 4, 0)
            if f.hpText then
                f.name:SetPoint("RIGHT", f.hpText, "LEFT", -4, 0)
            else
                f.name:SetPoint("RIGHT", health, "RIGHT", -4, 0)
            end
        end
    end

    f.raidIcon = health:CreateTexture(nil, "OVERLAY")
    self:Size(f.raidIcon, cfg.height >= 30 and 18 or 12)
    f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raidIcon:Hide()

    if unit ~= "player" then
        RegisterUnitWatch(f)
    end

    self.units[key] = f
    self.allFrames[f] = true
    self:ApplyPosition(key, f)
    return f
end

function A:AddCombo(f)
    local combo = CreateFrame("Frame", nil, f)
    local px = self:PX(f)
    combo:SetPoint("TOPLEFT", f, "TOPLEFT", px, -px)
    combo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -px, -px)
    combo:SetHeight(3)
    combo:SetFrameLevel(f:GetFrameLevel() + 6)
    local gap = px
    local w = (f.cfg.width - 2 * px - gap * 4) / 5
    for i = 1, 5 do
        local p = CreateFrame("Frame", nil, combo)
        self:Size(p, w, 3)
        p:SetPoint("LEFT", combo, "LEFT", (i - 1) * (w + gap), 0)
        p.fill = p:CreateTexture(nil, "OVERLAY")
        p.fill:SetAllPoints(p)
        p.fill:SetTexture(self.media.blank)
        combo[i] = p
    end
    combo:Hide()
    f.combo = combo
end

------------------------------------------------------------------------
-- Build all unit frames
------------------------------------------------------------------------
function A:BuildUnitFrames()
    local player = self:CreateUnitFrame("Player", "player", {
        width = 220, height = 38, power = 5, fontSize = 13,
        hpFormat = "both", noName = true,
    })
    -- in-combat icon (crossed swords) in the middle of the player health bar
    do
        local icon = player.health:CreateTexture(nil, "OVERLAY")
        icon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        icon:SetTexCoord(0.5, 1, 0, 0.49)
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.9, 0.9, 0.9)
        self:Size(icon, 20)
        icon:SetPoint("CENTER", player.health, "CENTER", 0, 0)
        icon:Hide()
        player.combatIcon = icon
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:SetScript("OnEvent", function() A:UpdateCombatIcon() end)
    end
    -- aura icons: x / y / spacing are in real screen pixels; size from settings
    local AS = self.db.auraSize
    self:AddAuraGroup(player, {   -- your debuffs above the player frame
        filter = "HARMFUL", num = 8, size = AS, perRow = 8,
        point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 0, y = 1, mouse = true, showTime = true,
        blacklist = true, hideOption = "hidePlayerDebuffs",
    })

    local target = self:CreateUnitFrame("Target", "target", {
        width = 220, height = 38, power = 5, fontSize = 13,
        hpFormat = "both", showLevel = true, nameLen = 22,
        twoLine = true, totName = true, powerPct = true,
    })
    local half = math.floor(220 / 2 / (AS + 1))
    local rows = math.max(1, math.floor(self.db.targetAuraRows or 1))   -- rows grow upwards
    self:AddAuraGroup(target, {   -- debuffs: top, left side
        filter = "HARMFUL", num = half * rows, size = AS, perRow = half,
        point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 0, y = 1,
        mouse = true, desatOthers = true, onlyMineOption = "onlyMyDebuffs", showTime = true,
        hideNames = { [GetSpellInfo(69127) or "Chill of the Throne"] = true,   -- Chill of the Throne (ICC)
            [GetSpellInfo(33198) or "Misery"] = true },                       -- Misery (shadow priests)
        userHide = "targetDebuffBlacklist",
    })
    self:AddAuraGroup(target, {   -- buffs: top, right side
        filter = "HELPFUL", num = half * rows, size = AS, perRow = half,
        point = "BOTTOMRIGHT", relPoint = "TOPRIGHT", x = 0, y = 1, growX = -1,
        mouse = true, showTime = true, enemyOnly = true,
    })

    local focus = self:CreateUnitFrame("Focus", "focus", {
        width = 170, height = 30, power = 3, fontSize = 12,
        hpFormat = "pct", nameLen = 16,
    })
    self:AddAuraGroup(focus, {
        filter = "HARMFUL", num = 6, size = AS, perRow = 6,
        point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 0, y = 1,
        mouse = true, onlyMine = true,
    })

    self:CreateUnitFrame("Pet", "pet", {
        width = 220, height = 12, power = 3, fontSize = 11,
        hpFormat = "none", noName = true,
    })

    -- boss frames (boss1-4): the target frame's look, the player frame's
    -- size, stacked downwards; one mover ("Boss") moves the whole stack
    do
        local BW, BH, GAP = 220, 38, 8
        local holder = CreateFrame("Frame", "HUIBossHolder", UIParent)
        holder:SetScale(self.db.scale)
        self:Size(holder, self:Snap(holder, BW), self:Snap(holder, BH) * 4 + self:Snap(holder, GAP) * 3)
        self.bossHolder = holder
        for i = 1, 4 do
            local b = self:CreateUnitFrame("Boss" .. i, "boss" .. i, {
                width = BW, height = BH, power = 5, fontSize = 13,
                hpFormat = "both", showLevel = true, nameLen = 22,
            })
            b:ClearAllPoints()
            b:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * (self:Snap(b, BH) + self:Snap(b, GAP)))
        end
        self:UpdateBossVisibility()
        -- default: 1px under the target's castbar, left edges lined up, the
        -- stack growing downwards (a position saved in unlock mode wins).
        -- Hung from the target frame at the castbar's offset, not from the
        -- castbar itself: anything a secure frame hangs from becomes protected,
        -- and the castbar could then not be shown / hidden in combat.
        self:RegisterMover("Boss", holder, "Boss frames", function(p)
            holder:ClearAllPoints()
            local cb, t = _G.HUITargetCastbar, A.units.Target
            if A.db.positions.Boss or not (cb and t) then
                A:AlignPoint(holder, p[1], UIParent, p[2], A:Snap(holder, p[3]), A:Snap(holder, p[4]))
            else
                -- the castbar sits 1px under the target frame; the boss stack 1px under it
                local hs = holder:GetEffectiveScale()
                local down = (A:PX(t) * t:GetEffectiveScale() + cb:GetHeight() * cb:GetEffectiveScale()) / hs
                holder:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -A:Snap(holder, down + A:PX(holder)))
            end
        end)
        self:ApplyPosition("Boss", holder)
    end

    for key, f in pairs(self.units) do
        if key:find("^Boss%d") then
            -- placed in the boss stack above
        elseif key == "Pet" then
            -- default: 1px under the player frame, same width (like the target castbar)
            self:RegisterMover(key, f, key, function(p)
                f:ClearAllPoints()
                if A.db.positions.Pet then
                    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
                else
                    f:SetPoint("TOPLEFT", A.units.Player, "BOTTOMLEFT", 0, -A:PX(A.units.Player))
                end
            end)
        else
            self:RegisterMover(key, f, key)
        end
    end
end

-- Boss frames only for fights with more than one boss (councils like the
-- Blood Prince Council): the first frame shows only while a second boss
-- exists. A secure visibility rule, so it also works in combat.
function A:UpdateBossVisibility()
    local b = self.units and self.units.Boss1
    if not b then return end
    if InCombatLockdown() then
        self:RunOOC(function() A:UpdateBossVisibility() end)
        return
    end
    if self.db.bossOnlyMulti ~= false then
        UnregisterUnitWatch(b)
        RegisterStateDriver(b, "visibility", "[target=boss2,exists] show; hide")
    else
        UnregisterStateDriver(b, "visibility")
        RegisterUnitWatch(b)
    end
end

-- debuffs hidden on the target frame (by name; a spell id becomes its name)
function A:BlacklistTargetDebuff(name, add)
    name = name and tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return end
    local id = tonumber(name)
    if id then name = GetSpellInfo(id) or name end
    self.db.targetDebuffBlacklist = self.db.targetDebuffBlacklist or {}
    self.db.targetDebuffBlacklist[name:lower()] = add and name or nil
    if self.units and self.units.Target then self:UpdateAuras(self.units.Target) end
end

-- Player frame shows the vehicle while you are in one
function A:UpdateVehicle()
    local inV = UnitHasVehicleUI("player")
    local p, pet = self.units.Player, self.units.Pet
    if p then p.unit = inV and "vehicle" or "player" end
    if pet then pet.unit = inV and "player" or "pet" end
    if self.playerCastbar then self.playerCastbar.unit = inV and "vehicle" or "player" end
    if p then self:UpdateAll(p) end
    if pet and pet:IsVisible() then self:UpdateAll(pet) end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local unitEvents = {
    UNIT_HEALTH = "UpdateHealth", UNIT_MAXHEALTH = "UpdateHealth",
    UNIT_MANA = "UpdatePower", UNIT_RAGE = "UpdatePower", UNIT_ENERGY = "UpdatePower",
    UNIT_FOCUS = "UpdatePower", UNIT_RUNIC_POWER = "UpdatePower",
    UNIT_MAXMANA = "UpdatePower", UNIT_MAXRAGE = "UpdatePower", UNIT_MAXENERGY = "UpdatePower",
    UNIT_MAXFOCUS = "UpdatePower", UNIT_MAXRUNIC_POWER = "UpdatePower",
    UNIT_DISPLAYPOWER = "UpdatePower",
    UNIT_AURA = "UpdateAuras",
    UNIT_NAME_UPDATE = "UpdateName", UNIT_LEVEL = "UpdateName",
    UNIT_FACTION = "UpdateAll",
}

local ev = CreateFrame("Frame")
A.eventFrame = ev

local function ForAll(method)
    for f in pairs(A.allFrames) do
        if f:IsVisible() and f.unit and UnitExists(f.unit) then A[method](A, f) end
    end
end

local function UpdateKey(key)
    local f = A.units[key]
    if f and f:IsVisible() then A:UpdateAll(f) end
end

local function UpdateRaidBorders()
    for f in pairs(A.allFrames) do
        if f.UpdateBorder and f:IsVisible() then f:UpdateBorder() end
    end
end

-- your own raid unit ("raidN"): found once per roster change instead of
-- asking UnitIsUnit for every raid button on every one of your events
local meRaid
local function FindMeRaid()
    meRaid = nil
    for i = 1, GetNumRaidMembers() do
        if UnitIsUnit("raid" .. i, "player") then meRaid = "raid" .. i return end
    end
end
FindMeRaid()

ev:SetScript("OnEvent", A:PerfWrap("Unit frames: events", function(self, event, unit)
    local m = unitEvents[event]
    if m then
        if not unit then return end
        -- your own changes can arrive only as "player": also update your
        -- raid button ("raidN") and party slot ("partyN" never is you)
        local alt = (unit == "player") and meRaid or nil
        local fn = A[m]
        for f in pairs(A.allFrames) do
            local fu = f.unit
            -- cheap string test first, the visibility call only for matches
            if (fu == unit or (alt and fu == alt)) and f:IsVisible() then
                fn(A, f)
            end
        end
        return
    end

    if event == "UNIT_THREAT_SITUATION_UPDATE" then
        for f in pairs(A.allFrames) do
            if f.unit == unit and f:IsVisible() then
                if f.UpdateBorder then f:UpdateBorder() end
                A:UpdateThreat(f)
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateKey("Target")
        UpdateRaidBorders()
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UpdateKey("Focus")
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 4 do UpdateKey("Boss" .. i) end
    elseif event == "UNIT_TARGET" then
        -- the target's target changed: redraw "Name » ToT"
        if unit == "target" and A.units.Target and A.units.Target:IsVisible() then A:UpdateName(A.units.Target) end
    elseif event == "UNIT_PET" then
        if unit == "player" then UpdateKey("Pet") end
        for f in pairs(A.allFrames) do
            if f.unit and f:IsVisible() and UnitExists(f.unit) and f.unit:find("pet") then A:UpdateAll(f) end
        end
    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        if unit == "player" then A:UpdateVehicle() end
    elseif event == "UNIT_COMBO_POINTS" then
        if A.units.Target then A:UpdateCombo(A.units.Target) end
    elseif event == "RAID_TARGET_UPDATE" then
        ForAll("UpdateRaidIcon")
    else -- roster / world changes
        FindMeRaid()
        if event == "PLAYER_ENTERING_WORLD" then A:UpdateVehicle() end
        ForAll("UpdateAll")
    end
end))

function A:RegisterUnitEvents()
    for e in pairs(unitEvents) do ev:RegisterEvent(e) end
    local list = {
        "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "UNIT_TARGET", "UNIT_PET", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
        "UNIT_COMBO_POINTS", "RAID_TARGET_UPDATE", "PLAYER_ENTERING_WORLD",
        "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
        "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    }
    for _, e in ipairs(list) do
        pcall(ev.RegisterEvent, ev, e)
    end
end

------------------------------------------------------------------------
-- Ticker: smooth health/power on main frames, refresh the target's "» ToT"
------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
local elapsedT, elapsedToT = 0, 0
ticker:SetScript("OnUpdate", A:PerfWrap("Unit frames: ticker", function(self, el)
    elapsedT = elapsedT + el
    elapsedToT = elapsedToT + el
    if elapsedT >= 0.1 then
        elapsedT = 0
        for _, f in pairs(A.units) do
            if f:IsVisible() and UnitExists(f.unit) then
                A:UpdateHealth(f)
                A:UpdatePower(f)
            end
        end
    end
    if elapsedToT >= 0.25 then
        elapsedToT = 0
        -- NPC target switches don't always fire UNIT_TARGET: refresh "» ToT"
        local t = A.units.Target
        if t and t:IsVisible() and UnitExists("target") then A:UpdateName(t) end
    end
end))

function A:UpdateCombatIcon()
    local f = self.units and (self.units.Player or self.units.player)
    local icon = f and f.combatIcon
    if not icon then return end
    if self.db.combatIcon and UnitAffectingCombat("player") then icon:Show() else icon:Hide() end
end
