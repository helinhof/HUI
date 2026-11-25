-- HUI - Raid / party frames
-- One SecureGroupHeader per raid group, each group laid out as a row (like the screenshot).

local A = HUI
local pairs = pairs
local SetTxt, lower = A.SetTxt, A.lower

-- NOTE: button size must match Templates.xml
A.RAID_W, A.RAID_H, A.RAID_GAP = 72, 39, 1

A.raidButtons = {}
local pending = {}  -- buttons created in combat that still need secure setup

local function SecureSetup(b)
    -- whole-pixel button size at the current scale (crisp 1px borders)
    b:SetWidth(A.RAID_W)
    b:SetHeight(A.RAID_H)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "menu")
    b:SetAttribute("shift-type1", "focus")
end

local function UpdateBorder(self)
    local u = self.unit
    if not u or not UnitExists(u) then return end
    local d = self.dispelType or false
    if self.huiBorder == d then return end
    self.huiBorder = d
    if d then
        local c = DebuffTypeColor[d]
        self:SetBackdropBorderColor(c.r, c.g, c.b)
        return
    end
    self:SetBackdropBorderColor(0, 0, 0)   -- no highlight for your target
end

------------------------------------------------------------------------
-- Your heals and shields on the group frames: small icons along the right
-- edge (from the top), with a timer sweep. One list per class; Weakened Soul
-- shows whoever cast it (it blocks your shield).
------------------------------------------------------------------------
local function S(id) return (GetSpellInfo(id)) end
local TRACK = {
    PRIEST  = { { S(17) }, { S(6788), harm = true, any = true }, { S(41635) }, { S(139) },
                { S(47788) }, { S(33206) }, { S(47753) } },
    DRUID   = { { S(774) }, { S(8936) }, { S(33763) }, { S(48438) } },
    SHAMAN  = { { S(974) }, { S(61295) } },
    PALADIN = { { S(53563) }, { S(53601) } },
}
local _, myClass = UnitClass("player")
A.trackedAuras = TRACK[myClass] or {}

-- layout "column": down the right edge (raid); "row": along the top edge,
-- leftwards from the right corner (party)
function A:AddIndicators(f, size, count, layout)
    f.indicators = {}
    f.indSize = size
    local parent = f.health or f
    for i = 1, count or 3 do
        local ic = CreateFrame("Frame", nil, parent)
        ic:SetFrameLevel(parent:GetFrameLevel() + 4)
        self:Size(ic, size)
        self:SetTemplate(ic)
        ic.atrCustomBg = true
        ic:SetBackdropColor(0, 0, 0, 1)
        local px = self:PX(ic)
        ic.icon = ic:CreateTexture(nil, "ARTWORK")
        ic.icon:SetPoint("TOPLEFT", px, -px)
        ic.icon:SetPoint("BOTTOMRIGHT", -px, px)
        ic.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        ic.cd = CreateFrame("Cooldown", nil, ic)
        ic.cd:SetAllPoints(ic.icon)
        ic.cd:SetReverse(true)
        if layout == "slots" then
            -- placed in UpdateIndicators (around the edges, centre left free)
        elseif i == 1 then
            ic:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -px, -px)
        elseif layout == "row" then
            ic:SetPoint("RIGHT", f.indicators[i - 1], "LEFT", px, 0)
        else
            ic:SetPoint("TOP", f.indicators[i - 1], "BOTTOM", 0, px)
        end
        ic:Hide()
        f.indicators[i] = ic
    end
    f.indLayout = layout
end

-- raid "slots": 1 top-right corner, 2 right edge middle, 3 bottom-right
-- (left of the role icon when it shows), 4 top edge left of slot 1.
-- The middle of the button stays free.
local function PlaceSlots(A, f)
    local ind, parent = f.indicators, f.health or f
    -- only when something it depends on changed (it ran on every aura event)
    local roleShown = (f.roleIcon and f.roleIcon:IsShown()) and true or false
    if f.slotsRole == roleShown and f.slotsSize == f.indSize and f.slotsW == (f.roleIcon and f.roleIcon:GetWidth()) then return end
    f.slotsRole, f.slotsSize, f.slotsW = roleShown, f.indSize, f.roleIcon and f.roleIcon:GetWidth()
    local px = A:PX(parent)
    -- role icon: bottom-right, centred under the column of heal icons
    if f.roleIcon and f.indSize then
        local rw = f.roleIcon:GetWidth() or 0
        local x = A:Snap(parent, px + (f.indSize - rw) / 2)
        if f.roleX ~= x then
            f.roleX = x
            f.roleIcon:ClearAllPoints()
            f.roleIcon:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -x, 1)
        end
    end
    local role = f.roleIcon and f.roleIcon:IsShown() and f.roleIcon
    for i, ic in ipairs(ind) do ic:ClearAllPoints() end
    ind[1]:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -px, -px)
    ind[2]:SetPoint("RIGHT", parent, "RIGHT", -px, 0)
    if role then
        ind[3]:SetPoint("BOTTOMRIGHT", role, "BOTTOMLEFT", -px, 0)
    else
        ind[3]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -px, px)
    end
    ind[4]:SetPoint("TOPRIGHT", ind[1], "TOPLEFT", -px, 0)
end

-- resize the heal icons (raid: about a third of the button height)
function A:ResizeIndicators(f, size)
    if not f.indicators then return end
    f.indSize = size
    for _, ic in ipairs(f.indicators) do self:Size(ic, size) end
    self:UpdateIndicators(f)
end

local function IndSize(H, px)
    return math.max(9, math.floor((H / px - 4) / 3))
end

-- icons about to run out (last 3 seconds) blink
local blinking = {}
local blinkDriver
do
    local d = CreateFrame("Frame")
    blinkDriver = d
    local t = 0
    d:SetScript("OnUpdate", A:PerfWrap("Raid frames: blinking icons", function(self, el)
        t = t + el
        local now = GetTime()
        local any = false
        for ic in pairs(blinking) do
            local left = ic.exp and (ic.exp - now)
            if not left or left <= 0 then
                -- ran out / hidden (UpdateIndicators clears exp)
                if ic.blinkA then ic.blinkA = nil; ic:SetAlpha(1) end
                blinking[ic] = nil
            elseif left > 3 then
                -- not in the last 3 seconds yet: nothing to draw
                any = true
                if ic.blinkA then ic.blinkA = nil; ic:SetAlpha(1) end
            elseif not ic:IsShown() then
                if ic.blinkA then ic.blinkA = nil; ic:SetAlpha(1) end
                blinking[ic] = nil
            else
                any = true
                ic.blinkA = true
                ic:SetAlpha(0.3 + 0.7 * math.abs(math.cos(t * 5)))
            end
        end
        if not any then self:Hide() end
    end))
end

------------------------------------------------------------------------
-- Important debuffs (Raid Frames > "Important debuffs"): a list of debuff
-- names or spell IDs. Whoever has one gets it as a big icon in the middle
-- of their raid / party frame (the first in list order wins), with a timer
-- sweep and its stack count.
------------------------------------------------------------------------
-- Built-in list of important WotLK raid debuffs (by name, so every
-- difficulty's version matches), most dangerous first. Filled into the
-- list once and again with "Add WotLK defaults"; anything can be removed.
local IMPORTANT_GROUPS = {
    { "ICC", { "Dominate Mind", "Frost Beacon", "Ice Tomb", "Unchained Magic", "Necrotic Plague", "Harvest Soul",
        "Soul Reaper", "Mark of the Fallen Champion", "Pact of the Darkfallen", "Swarming Shadows",
        "Essence of the Blood Queen", "Frenzied Bloodthirst", "Uncontrollable Frenzy", "Volatile Ooze Adhesive",
        "Gaseous Bloat", "Unbound Plague", "Mutated Infection", "Gas Spore", "Vile Gas", "Impaled",
        "Boiling Blood", "Rune of Blood", "Shadow Prison", "Instability", "Infest", "Gastric Bloat" } },
    { "RS", { "Fiery Combustion", "Soul Consumption", "Conflagration" } },
    { "ToC", { "Mistress' Kiss", "Incinerate Flesh", "Legion Flame", "Touch of Light", "Touch of Darkness",
        "Penetrating Cold", "Paralytic Toxin", "Burning Bile", "Snobolled!", "Fire Bomb" } },
    { "Ulduar", { "Malady of the Mind", "Brain Link", "Squeeze", "Mark of the Faceless", "Slag Pot", "Gravity Bomb",
        "Searing Light", "Stone Grip", "Overwhelming Power", "Fusion Punch", "Iron Roots", "Nature's Fury",
        "Napalm Shell", "Biting Cold", "Unbalancing Strike", "Phase Punch" } },
    { "Naxx", { "Mutating Injection", "Web Wrap", "Frost Blast", "Chains of Kel'Thuzad", "Detonate Mana",
        "Life Drain", "Necrotic Aura" } },
    { "EoE", { "Surge of Power" } },
}
A.importantDefaults, A.importantSource = {}, {}   -- source: which raid a default comes from
for _, g in ipairs(IMPORTANT_GROUPS) do
    for _, name in ipairs(g[2]) do
        A.importantDefaults[#A.importantDefaults + 1] = name
        A.importantSource[name:lower()] = g[1]
    end
end

-- add the built-in ones that aren't in the list yet (returns how many)
function A:AddImportantDefaults()
    self.db.raidImportant = self.db.raidImportant or {}
    local list, have, added = self.db.raidImportant, {}, 0
    for _, v in ipairs(list) do if type(v) == "string" then have[v:lower()] = true end end
    for _, name in ipairs(self.importantDefaults) do
        if not have[name:lower()] then
            list[#list + 1] = name
            have[name:lower()] = true
            added = added + 1
        end
    end
    if self.RebuildImportantDebuffs then self:RebuildImportantDebuffs() end
    return added
end

local impById, impByName = {}, {}
local impIcon = {}   -- list position -> icon last seen on a real player
local impBuilt = false

function A:RebuildImportantDebuffs()
    impBuilt = true
    wipe(impById); wipe(impByName)
    self.db.raidImportant = self.db.raidImportant or {}
    for i, v in ipairs(self.db.raidImportant or {}) do
        if type(v) == "number" then
            if not impById[v] then impById[v] = i end
        elseif type(v) == "string" then
            local k = v:lower()
            if not impByName[k] then impByName[k] = i end
        end
    end
end

-- icons for names: the game only looks names up for spells you know, so a
-- boss debuff added by name is searched for once in the spell data and the
-- icon kept (db.raidImportantIcons, by lower-case name; false = not found)
local function IconCache()
    A.db.raidImportantIcons = A.db.raidImportantIcons or {}
    return A.db.raidImportantIcons
end

local function ScanIcon(name)
    local want = name:lower()
    for id = 1, 85000 do
        local n, _, icon = GetSpellInfo(id)
        if n and icon and n:lower() == want then return icon end
    end
end

local function NameIcon(name)
    local cache, key = IconCache(), name:lower()
    if cache[key] == nil then cache[key] = ScanIcon(name) or false end
    return cache[key] or nil
end

-- look up the icons of every listed name that has none yet, in the
-- background: one pass over the spell data, a few thousand spells a frame,
-- so nothing freezes. done() is called when it's finished.
do
    local scanner, want, nextId, callbacks
    local LAST, STEP = 85000, 4000
    function A:ScanImportantIcons(done)
        callbacks = callbacks or {}
        if done then callbacks[#callbacks + 1] = done end
        if scanner and scanner:IsShown() then return end
        local cache = IconCache()
        want = {}
        local n = 0
        for _, v in ipairs(self.db.raidImportant or {}) do
            if type(v) == "string" and not GetSpellInfo(v) and cache[v:lower()] == nil then
                want[v:lower()] = true
                n = n + 1
            end
        end
        if n == 0 then
            for _, cb in ipairs(callbacks) do cb() end
            wipe(callbacks)
            return
        end
        nextId = 1
        scanner = scanner or CreateFrame("Frame")
        scanner:SetScript("OnUpdate", function(self)
            local last = math.min(LAST, nextId + STEP - 1)
            for id = nextId, last do
                local name, _, icon = GetSpellInfo(id)
                if name and icon then
                    local k = name:lower()
                    if want[k] then cache[k] = icon; want[k] = nil end
                end
            end
            nextId = last + 1
            if nextId > LAST or not next(want) then
                for k in pairs(want) do cache[k] = false end   -- not in the spell data
                self:Hide()
                for _, cb in ipairs(callbacks) do cb() end
                wipe(callbacks)
            end
        end)
        scanner:Show()
    end
end

-- the icon of a list entry: its spell's icon, else the one found by name,
-- else the one last seen on a real player, else a question mark
function A:ImportantDebuffIcon(i, noScan)
    local v = (self.db.raidImportant or {})[i]
    if v == nil then return end
    local _, _, icon = GetSpellInfo(v)
    if not icon and type(v) == "string" then
        if noScan then icon = IconCache()[v:lower()] or nil else icon = NameIcon(v) end
    end
    return icon or impIcon[i] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- what the list shows for an entry: "Name (12345)" or the name as typed
function A:ImportantDebuffLabel(v)
    if type(v) == "number" then
        local n = GetSpellInfo(v)
        return n and (n .. "  (" .. v .. ")") or ("spell " .. v)
    end
    return tostring(v)
end

function A:AddImportantDebuff(text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "")
    if not text or text == "" then return end
    local v = tonumber(text) or text
    self.db.raidImportant = self.db.raidImportant or {}
    local list = self.db.raidImportant
    for _, e in ipairs(list) do
        if e == v or (type(e) == "string" and type(v) == "string" and e:lower() == v:lower()) then return end
    end
    list[#list + 1] = v
    if type(v) == "string" and not GetSpellInfo(v) then NameIcon(v) end
    self:RebuildImportantDebuffs()
    self:RefreshUnits()
    if self.RebuildFakeRaid then self:RebuildFakeRaid() end
end

-- move an entry up (-1) or down (+1): higher in the list wins
function A:MoveImportantDebuff(i, d)
    local list = self.db.raidImportant or {}
    local j = i + d
    if not (list[i] and list[j]) then return end
    list[i], list[j] = list[j], list[i]
    wipe(impIcon)
    self:RebuildImportantDebuffs()
    self:RefreshUnits()
    if self.RebuildFakeRaid then self:RebuildFakeRaid() end
end

function A:RemoveImportantDebuff(i)
    tremove(self.db.raidImportant, i)
    wipe(impIcon)
    self:RebuildImportantDebuffs()
    self:RefreshUnits()
    if self.RebuildFakeRaid then self:RebuildFakeRaid() end
end

local function ImportantIcon(A, f)
    local ic = f.importantIcon
    if ic then return ic end
    local parent = f.health or f
    ic = CreateFrame("Frame", nil, parent)
    ic:SetFrameLevel(parent:GetFrameLevel() + 6)
    A:SetTemplate(ic)
    ic.atrCustomBg = true
    ic:SetBackdropColor(0, 0, 0, 1)
    local px = A:PX(ic)
    ic.icon = ic:CreateTexture(nil, "ARTWORK")
    ic.icon:SetPoint("TOPLEFT", px, -px)
    ic.icon:SetPoint("BOTTOMRIGHT", -px, px)
    ic.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    ic.cd = CreateFrame("Cooldown", nil, ic)
    ic.cd:SetAllPoints(ic.icon)
    ic.cd:SetReverse(true)
    ic.count = ic:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(ic.count, A.media.font, 10, "OUTLINE")
    ic.count:SetShadowOffset(0, 0)
    ic.count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", -px, 2 * px)
    ic:SetPoint("CENTER", parent, "CENTER", 0, 0)
    ic:Hide()
    f.importantIcon = ic
    return ic
end

-- your own big single-target buffs: shown in the middle of the frame of the
-- player you cast them on (only yours; important debuffs come first)
local CENTER_BUFFS = {}
for _, id in ipairs({
    10060,  -- Power Infusion
    49016,  -- Hysteria (Unholy Frenzy)
    33206,  -- Pain Suppression
    47788,  -- Guardian Spirit
    6940,   -- Hand of Sacrifice
    10278,  -- Hand of Protection
    1044,   -- Hand of Freedom
    1038,   -- Hand of Salvation
    29166,  -- Innervate
    19752,  -- Divine Intervention
}) do
    local n = GetSpellInfo(id)
    if n then CENTER_BUFFS[n] = true end
end

local impBest = {}   -- reused: PaintImportant only reads it
function A:UpdateImportant(f)
    if not impBuilt then self:RebuildImportantDebuffs() end
    local u = f.unit
    local bi, bIcon, bCount, bDur, bExp, bIndex
    local exists = u and UnitExists(u)
    if exists and (next(impById) or next(impByName)) then
        for i = 1, 40 do
            local name, _, icon, count, _, duration, expires, _, _, _, spellId = UnitDebuff(u, i)
            if not name then break end
            local p = (spellId and impById[spellId]) or impByName[lower[name]]
            if p and (not bi or p < bi) then
                bi, bIcon, bCount, bDur, bExp, bIndex = p, icon, count, duration, expires, i
            end
        end
    end
    -- the debuff row (bottom left) leaves this one out: it's in the middle
    f.impIndex = bIndex
    local found = bi ~= nil
    -- no important debuff: your own big single-target buffs go in the middle
    if not found and exists then
        for i = 1, 40 do
            local name, _, icon, count, _, duration, expires, caster = UnitBuff(u, i)
            if not name then break end
            if CENTER_BUFFS[name] and (caster == "player" or caster == "pet" or caster == "vehicle") then
                found, bIcon, bCount, bDur, bExp = true, icon, count, duration, expires
                break
            end
        end
    end
    if bi then
        impIcon[bi] = bIcon   -- remembered for the raid test preview
        local v = self.db.raidImportant[bi]
        if type(v) == "string" then IconCache()[lower[v]] = bIcon end
    end
    local ic = f.importantIcon
    if not found then
        if ic and ic:IsShown() then ic:Hide() end
        if ic then ic.exp = nil end
        return
    end
    impBest.icon, impBest.count, impBest.duration, impBest.expires, impBest.index = bIcon, bCount, bDur, bExp, bIndex
    self:PaintImportant(f, impBest)
end

-- best = { icon, count, duration, expires }
-- where raid names start: just after the aggro square (the letters' own
-- left edge leaves the gap), and 2px higher than the old 1-unit inset
function A:RaidNameX(f)
    return (self:DP(self.RAID_THREAT_SIZE or 6) - 2) * self:PX(f)
end
function A:RaidNameY(f)
    return -1 + 2 * self:PX(f)
end

function A:PaintImportant(f, best)
    local ic = ImportantIcon(self, f)
    local parent = f.health or f
    local h = parent:GetHeight() or 0
    local px = self:PX(ic)
    local size, y
    if f.nameTop then
        -- raid: in the middle (2px lower), half the bar's height
        size = math.max(10 * px, h * 0.5)
        y = -2 * px
    else
        size = math.max(10 * px, h * 0.6)   -- 60% of the health bar's height
        y = 0
    end
    if not ic.huiSize or math.abs(ic.huiSize - size) > 0.01 then ic.huiSize = size; self:Size(ic, size) end
    if ic.huiY ~= y then
        ic.huiY = y
        ic:ClearAllPoints()
        ic:SetPoint("CENTER", parent, "CENTER", 0, self:Snap(parent, y))
    end
    if ic.tex ~= best.icon then ic.tex = best.icon; ic.icon:SetTexture(best.icon) end
    SetTxt(ic.count, best.count and best.count > 1 and best.count or "")
    if best.duration and best.duration > 0 and best.expires then
        if ic.exp ~= best.expires then ic.exp = best.expires; ic.cd:SetCooldown(best.expires - best.duration, best.duration) end
        ic.cd:Show()
    else
        ic.exp = nil
        ic.cd:Hide()
    end
    if not ic:IsShown() then ic:Show() end
end

function A:UpdateIndicators(f)
    self:UpdateImportant(f)
    local ind = f.indicators
    if not ind then return end
    local n = 0
    local u = f.unit
    local maxN = #ind
    if f.indLayout == "slots" then PlaceSlots(self, f) end
    if u and UnitExists(u) and self.db.raidIndicators ~= false then
        for _, t in ipairs(self.trackedAuras) do
            if n >= maxN then break end
            local name = t[1]
            if name then
                local filter = t.filter
                if not filter then
                    filter = (t.harm and "HARMFUL" or "HELPFUL") .. (t.any and "" or "|PLAYER")
                    t.filter = filter
                end
                local _, _, icon, _, _, duration, expires = UnitAura(u, name, nil, filter)
                if icon then
                    n = n + 1
                    local ic = ind[n]
                    if ic.tex ~= icon then ic.tex = icon; ic.icon:SetTexture(icon) end
                    if duration and duration > 0 and expires then
                        if ic.exp ~= expires then ic.exp = expires; ic.cd:SetCooldown(expires - duration, duration) end
                        ic.cd:Show()
                        if not blinking[ic] then blinking[ic] = true; blinkDriver:Show() end
                    else
                        ic.exp = nil
                        ic.cd:Hide()
                    end
                    if not ic:IsShown() then ic:Show() end
                end
            end
        end
    end
    for i = n + 1, #ind do
        local ic = ind[i]
        if ic:IsShown() then ic:Hide() end
        ic.exp = nil
        if ic.blinkA then ic.blinkA = nil; ic:SetAlpha(1) end
    end
    -- raid names use the full width unless heal icons sit on the top edge
    if f.nameRightFree and f.name then
        local onTop = (n >= 4) and 2 or (n >= 1 and 1 or 0)
        local key = onTop * 1000 + (f.indSize or 0)
        if f.nameRightKey ~= key then
            f.nameRightKey = key
            local px = self:PX(f)
            f.name:SetPoint("RIGHT", f.health, "RIGHT", onTop > 0 and -(onTop * (f.indSize + 1) + 2) * px or -2 * px, 0)
        end
        if f.onTopN ~= onTop then f.onTopN = onTop; self:FitName(f) end
    end
end

A.raidDefaults = {
    width      = 0,      -- 0 = five buttons span the chat box width
    height     = 39,
    gap        = 1,      -- pixels between buttons
    nameLen    = 12,
    layout     = "COLUMNS", -- COLUMNS: down, then right (a column per group) / ROWS: right, then down
    debuffNum  = 2,
    debuffSize = 14,
    lockAspect = true,   -- height follows the width (same shape as the reference layout)
}
A.RAID_ASPECT = 35 / 59  -- height / width, measured on the reference screenshot
local function L() return A.db.raidLayout end

function A:InitRaidButton(b)
    if b.atrInit then return end
    b.atrInit = true
    b.cfg = { hpFormat = "deficit", nameLen = L().nameLen, raid = true }
    b.unit = b:GetAttribute("unit")

    if InCombatLockdown() then
        pending[b] = true
    else
        SecureSetup(b)
    end
    b.menu = A.ShowMenu
    b.showmenu = A.ShowMenu
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[b] = true

    self:SetTemplate(b)

    local health = self:StatusBar(b)
    local px = self:PX(b)
    health:SetPoint("TOPLEFT", px, -px)
    health:SetPoint("BOTTOMRIGHT", -px, px)
    b.health = health

    b.name = self:Font(health, 11, "LEFT")
    -- the aggro square has its own spot in the top-left corner: the name
    -- always starts after it, so it neither moves nor gets covered
    b.threatReserve = true
    health:HookScript("OnSizeChanged", function() A:FitName(b) end)
    b.nameTop = true
    b.name:SetPoint("TOPLEFT", health, "TOPLEFT", A:RaidNameX(b), A:RaidNameY(b))
    b.name:SetPoint("RIGHT", health, "RIGHT", -2, 0)
    b.name:SetHeight(13)

    b.hpText = self:Font(health, 10, "RIGHT")
    b.hpText:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2, 2)

    self:AddIndicators(b, IndSize(A.RAID_H or 37, self:PX(b)), 4, "slots")

    -- role icon in the bottom-right corner
    b.roleIcon = health:CreateTexture(nil, "OVERLAY")
    self:Size(b.roleIcon, 11)
    b.roleIcon:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -1, 1)
    b.roleIcon:Hide()
    b.indAvoidRole = true   -- heal icons stop above it
    b.hpText:ClearAllPoints()
    b.hpText:SetPoint("BOTTOMRIGHT", b.roleIcon, "BOTTOMLEFT", -1, 1)
    b.name:SetPoint("RIGHT", health, "RIGHT", -2, 0)
    b.nameRightFree = true   -- moves left only while heal icons show

    b.raidIcon = health:CreateTexture(nil, "OVERLAY")
    self:Size(b.raidIcon, 12)
    b.raidIcon:SetPoint("TOPRIGHT", health, "TOPRIGHT", -1, -1)
    b.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    b.raidIcon:Hide()

    self:AddAuraGroup(b, {
        filter = "HARMFUL", num = L().debuffNum, size = L().debuffSize, spacing = 1,
        point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 2, y = 2,
        blacklist = true, trackDispel = true, mouse = false,
    })

    b.UpdateBorder = UpdateBorder
    b:SetScript("OnEnter", UnitFrame_OnEnter)
    b:SetScript("OnLeave", UnitFrame_OnLeave)
    b:HookScript("OnShow", function(self)
        self.unit = self:GetAttribute("unit")
        A:UpdateAll(self)
    end)
    b:HookScript("OnAttributeChanged", function(self, name, value)
        if name == "unit" then
            self.unit = value
            if value and self:IsVisible() then A:UpdateAll(self) end
        end
    end)

    self.raidButtons[b] = true
    self.allFrames[b] = true
end

-- called from the XML template's OnLoad
function HUI_InitRaidButton(self)
    A:InitRaidButton(self)
end

-- button size in screen pixels -> holder units (redone when the UI scale changes)
function A:RaidSizes()
    local lay, holder = self.db.raidLayout, self.raidHolder
    holder:SetScale(self.db.scale)
    local px = self:PX(holder)
    -- healer layout: buttons a bit bigger (same shape)
    local k = (self.raidHealerMode and (self.db.healerScale or 1.3)) or 1
    if lay.width and lay.width > 0 then
        self.RAID_W = lay.width * k
    else
        self.RAID_W = self:DP(self.RAID_BTN_PX * k) * px
    end
    self.RAID_H, self.RAID_GAP = lay.height * k, lay.gap
    if lay.lockAspect then self.RAID_H = self.RAID_W * A.RAID_ASPECT end
    local W, H = self:Snap(holder, self.RAID_W), self:Snap(holder, self.RAID_H)
    self.RAID_W, self.RAID_H = W, H
    local GAP = self.RAID_GAP * px
    local cols = lay.layout == "COLUMNS"
    self.raidDims = { W = W, H = H, GAP = GAP, cols = cols }
    -- only groups 1-5 show: the block is 5 x 5 either way
    self:Size(holder, 5 * (W + GAP) - GAP, 5 * (H + GAP) - GAP)
end

-- place the group headers and size every button (out of combat)
function A:LayoutRaid()
    if InCombatLockdown() or not self.raidHeaders then return end
    self:RaidSizes()
    local d, holder = self.raidDims, self.raidHolder
    -- buttons first: the headers lay their buttons out (and size themselves)
    -- from the button size when an attribute changes. With the old size the
    -- header ended up taller than its buttons, and buttons centred in it sat
    -- a pixel or two off.
    local isz = IndSize(d.H, self:PX(holder))
    for b in pairs(self.raidButtons) do
        b:SetWidth(d.W); b:SetHeight(d.H)
        self:SetTemplate(b)
        self:ResizeIndicators(b, isz)
    end
    for g, h in ipairs(self.raidHeaders) do
        h:ClearAllPoints()
        if d.cols then
            h:SetAttribute("point", "TOP")
            h:SetAttribute("xOffset", 0)
            h:SetAttribute("yOffset", -d.GAP)
            -- buttons hang off the header's horizontal middle: pin it to the column's
            h:SetPoint("TOP", holder, "TOPLEFT", (g - 1) * (d.W + d.GAP) + d.W / 2, 0)
            h:SetWidth(d.W)
        else
            h:SetAttribute("point", "LEFT")
            h:SetAttribute("yOffset", 0)
            h:SetAttribute("xOffset", d.GAP)
            -- the header's buttons hang off its vertical middle: pin that middle
            -- to the middle of the row, whatever height the header gives itself
            h:SetPoint("LEFT", holder, "TOPLEFT", 0, -((g - 1) * (d.H + d.GAP) + d.H / 2))
            h:SetHeight(d.H)
        end
    end
    if self.RebuildFakeRaid then self:RebuildFakeRaid() end
    self:ApplyPosition(self.raidPosKey or "Raid", holder)
    if self.layoutOverride and self.playerCastbar then self:ApplyPosition("PlayerCastbar", self.playerCastbar) end
end

function A:BuildRaid()
    local lay = A.CopyDefaults(A.raidDefaults, self.db.raidLayout)
    self.db.raidLayout = lay
    local holder = CreateFrame("Frame", "HUIRaidHolder", UIParent)
    holder:SetScale(self.db.scale)
    self.raidHolder = holder
    self:RaidSizes()
    self:ApplyPosition(self.raidPosKey or "Raid", holder)
    local partyOn = self.db.modules.party
    self:RegisterMover("Raid", holder, partyOn and "Raid" or "Raid / Party")
    self.raidHolder = holder

    self.raidHeaders = {}
    for g = 1, 8 do
        local h = CreateFrame("Frame", "HUIRaidGroup" .. g, holder, "SecureGroupHeaderTemplate")
        h:SetAttribute("template", "HUIRaidButtonTemplate")
        h:SetAttribute("groupFilter", tostring(g))
        h:SetAttribute("showRaid", true)
        -- with the party frames on, these only show in a raid
        h:SetAttribute("showParty", g == 1 and not partyOn)
        h:SetAttribute("showPlayer", true)
        h:SetAttribute("showSolo", false)
        h:SetAttribute("sortMethod", "INDEX")
        if g <= 5 then
            h:Show()
        else
            -- groups 6-8 (bench / 40-player) never show
            h:SetAttribute("showRaid", false)
            h:SetAttribute("showParty", false)
            h:SetAttribute("showPlayer", false)
            h:Hide()
        end
        self.raidHeaders[g] = h
    end
    self:LayoutRaid()

    -- finish secure setup for buttons that were created in combat
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        for b in pairs(pending) do SecureSetup(b) end
        wipe(pending)
    end)

    -- range / offline fade + status refresh
    local t = 0
    f:SetScript("OnUpdate", A:PerfWrap("Raid frames: range", function(_, el)
        t = t + el
        if t < 0.4 then return end
        t = 0
        for b in pairs(A.raidButtons) do
            local u = b.unit
            if u and b:IsVisible() and UnitExists(u) then
                local alpha = 1
                if not UnitIsConnected(u) then
                    alpha = 0.35
                elseif A.db.raidRange and not UnitIsUnit(u, "player") and not UnitInRange(u) then
                    alpha = 0.4
                end
                if b.huiAlpha ~= alpha then b.huiAlpha = alpha; b:SetAlpha(alpha) end
                A:UpdateHealth(b)
            end
        end
    end))
end


------------------------------------------------------------------------
-- Test: a fake 25-player raid (5 groups of 5) in the real layout, with health
-- changing now and then so smooth updates and colours can be judged.
------------------------------------------------------------------------
local FAKE = {
    { "Gdxo", "PALADIN", "HEALER" }, { "Triplesixp", "PALADIN" }, { "Sk", "DEATHKNIGHT", "TANK" },
    { "Dash", "ROGUE" }, { "Pyongyang", "SHAMAN" }, { "Hardyvoker", "PRIEST", "HEALER" },
    { "Tome", "MAGE" }, { "Turtle", "HUNTER" }, { "Tydraforce", "DRUID", "HEALER" },
    { "Flowbie", "WARRIOR", "TANK" }, { "Jacoblol", "SHAMAN", "HEALER" }, { "Fear", "WARLOCK" },
    { "Kads", "MAGE" }, { "Crypticzz", "DEATHKNIGHT" }, { "Hlt", "HUNTER" },
    { "Snibizard", "MAGE" }, { "Veepwakeup", "PRIEST" }, { "Caprisunfa", "ROGUE" },
    { "Twistedm", "DRUID", "HEALER" },
    { "Tuan", "WARRIOR" }, { "Esco", "ROGUE" }, { "Kira", "PRIEST", "HEALER" }, { "Dazzler", "MAGE" },
    { "Suprematist", "WARLOCK" }, { "Helinhof", "HUNTER" }, { "Andre", "PALADIN", "TANK" },
    { "Iqui", "SHAMAN" }, { "Acie", "DRUID" }, { "Merfin", "DEATHKNIGHT" }, { "Loriendal", "PRIEST" },
    { "Nomore", "WARRIOR" }, { "Rexbe", "HUNTER" }, { "Maryluh", "PALADIN", "HEALER" },
    { "Sixseven", "ROGUE" }, { "Keoo", "MAGE" }, { "Zidras", "WARLOCK" },
}
local fake

A.FAKE_RAID = FAKE

local function FakeColor(b)
    local bar, hp = b.health, b.hp
    local fill = bar:GetStatusBarTexture()
    local bg, m = A.colors.backdrop, A.db.missingColor
    if b.dead then
        local dr, dg, db = A:DeadColor()
        bar:SetStatusBarColor(dr, dg, db); if fill then fill:SetAlpha(1) end
    elseif A.db.classBars then
        local r, g, bl = A:ClassColor(b.class); bar:SetStatusBarColor(r, g, bl); if fill then fill:SetAlpha(1) end
    else
        bar:SetStatusBarColor(bg[1], bg[2], bg[3]); if fill then fill:SetAlpha(bg[4]) end
    end
    bar.bg:SetVertexColor(m.r, m.g, m.b, bg[4])
    b:SetBackdropColor(bg[1], bg[2], bg[3], 0)
end
A.FakeColor = FakeColor

local function BuildFake()
    local d = A.raidDims
    fake = CreateFrame("Frame", nil, A.raidHolder)
    fake:SetAllPoints(A.raidHolder)
    fake:SetFrameLevel(A.raidHolder:GetFrameLevel() + 10)
    fake.buttons = {}
    -- the 17 names from "Tuan" on are always in; the rest of the 25 are
    -- picked at random from the others, then everything is shuffled
    local must, rest, pool = {}, {}, {}
    local first
    for i, v in ipairs(FAKE) do if v[1] == "Tuan" then first = i end end
    for i, v in ipairs(FAKE) do
        if first and i >= first then must[#must + 1] = v else rest[#rest + 1] = v end
    end
    for i = #rest, 2, -1 do local j = math.random(i); rest[i], rest[j] = rest[j], rest[i] end
    for _, v in ipairs(must) do pool[#pool + 1] = v end
    for i = 1, 25 - #pool do pool[#pool + 1] = rest[i] end
    for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
    -- important debuffs from the list on a few random members (4 to 6)
    local imp = {}
    local nImp = #(A.db.raidImportant or {})
    if nImp > 0 then
        local slots = {}
        for i = 1, 25 do slots[i] = i end
        for i = 25, 2, -1 do local j = math.random(i); slots[i], slots[j] = slots[j], slots[i] end
        for k = 1, math.random(4, 6) do imp[slots[k]] = math.random(nImp) end
    end
    -- aggro on 3 to 5 random members, with mixed threat levels (1 to 3)
    local aggro = {}
    do
        local slots = {}
        for i = 1, 25 do slots[i] = i end
        for i = 25, 2, -1 do local j = math.random(i); slots[i], slots[j] = slots[j], slots[i] end
        for k = 1, math.random(3, 5) do aggro[slots[k]] = (k == 1) and 3 or math.random(1, 3) end
    end
    for i = 1, 25 do
        local info = pool[i]
        local g, n = math.floor((i - 1) / 5), (i - 1) % 5
        local b = CreateFrame("Frame", nil, fake)
        b:SetWidth(d.W); b:SetHeight(d.H)
        if d.cols then
            b:SetPoint("TOPLEFT", fake, "TOPLEFT", g * (d.W + d.GAP), -n * (d.H + d.GAP))
        else
            b:SetPoint("TOPLEFT", fake, "TOPLEFT", n * (d.W + d.GAP), -g * (d.H + d.GAP))
        end
        A:SetTemplate(b)
        b.atrCustomBg = true
        local px = A:PX(b)
        local health = A:StatusBar(b)
        health:SetPoint("TOPLEFT", px, -px)
        health:SetPoint("BOTTOMRIGHT", -px, px)
        b.health = health
        local r, gg, bl = A:ClassColor(info[2])
        local name = health:CreateFontString(nil, "OVERLAY")
        A:SetFontPx(name, A.media.font, A:FS("raid"), "OUTLINE")
        name:SetShadowOffset(0, 0)
        name:SetPoint("TOPLEFT", health, "TOPLEFT", A:RaidNameX(b), A:RaidNameY(b))
        name:SetPoint("RIGHT", health, "RIGHT", -2, 0)
        name:SetJustifyH("LEFT")
        b.name, b.nameTop, b.threatReserve = name, true, true
        -- aggro square on a few members (yellow / orange / red), to preview
        if aggro[i] then
            local sq = A:ThreatSquare(b)
            local r, g, bb = GetThreatStatusColor(aggro[i])
            sq.fill:SetVertexColor(r, g, bb)
            sq:Show()
        end
        name:SetHeight(13)
        b.huiNamePlain, b.huiNameColor = A:Truncate(info[1], A.db.raidLayout.nameLen or 8), A:Hex(r, gg, bl)
        name:SetText(b.huiNameColor .. b.huiNamePlain .. "|r")
        local role = health:CreateTexture(nil, "OVERLAY")
        A:Size(role, 11)
        role:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -1, 1)
        if info[3] then
            role:SetTexture("Interface\\AddOns\\HUI\\media\\role_" .. info[3]:lower()); role:Show()
        else
            role:Hide()
        end
        name:SetPoint("RIGHT", health, "RIGHT", -12, 0)
        -- a few of your trackable heals on some members, to preview
        A:AddIndicators(b, IndSize(d.H, A:PX(b)), 4, "slots")
        local tr = A.trackedAuras
        local k = 0
        for _, t in ipairs(tr) do
            if t[1] and math.random() < 0.35 and k < 4 then
                local _, _, ico = GetSpellInfo(t[1])
                if ico then
                    k = k + 1
                    local ic = b.indicators[k]
                    ic.icon:SetTexture(ico)
                    ic.cd:SetCooldown(GetTime() - math.random(0, 10), 15)
                    ic:Show()
                end
            end
        end
        b.roleIcon = role
        PlaceSlots(A, b)
        local onTop = (k >= 4) and 2 or (k >= 1 and 1 or 0)
        name:SetPoint("RIGHT", health, "RIGHT", onTop > 0 and -(onTop * (b.indSize + 1) + 2) or -2, 0)
        A:FitName(b)
        b.class, b.max = info[2], 20000 + math.random(0, 8000)
        b.role = info[3] and info[3]:upper() or nil
        if b.role == "TANK" then b.max = b.max + 15000 end
        b.hp = b.max * (0.85 + math.random() * 0.15)
        health:SetMinMaxValues(0, b.max)
        health:SetValue(b.hp)
        FakeColor(b)
        if imp[i] then
            local dur = math.random(10, 30)
            A:PaintImportant(b, {
                icon = A:ImportantDebuffIcon(imp[i]), count = (math.random() < 0.3) and math.random(2, 5) or 0,
                duration = dur, expires = GetTime() + math.random(3, dur),
            })
        end
        fake.buttons[i] = b
    end
    -- health moves like a raid fight (smooth updates, 4 times a second):
    --  * tanks take boss hits all the time and get healed hard
    --  * every 6-12 s a raid-wide hit takes 12-30% off most people
    --  * now and then one random player takes a big hit (15-45%)
    --  * healing comes in faster the lower someone is, plus a little
    --    regeneration (HoTs): tanks swing between ~60% and full, the rest
    --    sit mostly at 85-100% with dips to ~50% that recover within a few
    --    seconds. Nobody dies.
    local t, aoe = 0, 3 + math.random() * 4
    fake:SetScript("OnUpdate", function(self, el)
        if not self.namesFit then   -- sizes are only known once it's on screen
            self.namesFit = true
            for _, b in ipairs(self.buttons) do A:FitName(b) end
        end
        t = t + el
        aoe = aoe - el
        if t < 0.25 then return end
        t = 0
        local pulse = aoe <= 0
        if pulse then aoe = 6 + math.random() * 6 end
        for i, b in ipairs(self.buttons) do
            local m, tank = b.max, b.role == "TANK"
            local dmg = 0
            if tank then
                if math.random() < 0.45 then dmg = m * (0.04 + math.random() * 0.10) end
            elseif math.random() < 0.01 then
                dmg = m * (0.15 + math.random() * 0.30)
            end
            if pulse and math.random() < 0.85 then
                dmg = dmg + m * (tank and 0.06 or 0.12 + math.random() * 0.18)
            end
            b.hp = b.hp - dmg
            local deficit = 1 - b.hp / m
            if deficit > 0.01 then
                local chance = tank and (0.40 + deficit) or (0.06 + deficit * 0.7)
                if math.random() < chance then
                    b.hp = b.hp + m * (0.04 + math.random() * 0.08) * (0.5 + deficit)
                end
                b.hp = b.hp + m * (tank and 0.008 or 0.004)
            end
            b.hp = math.max(m * 0.15, math.min(m, b.hp))
            A:SetBarSmooth(b.health, b.hp, b.max, "fake" .. i)
            FakeColor(b)
        end
    end)
end

function A:RebuildFakeRaid()
    if not fake then return end
    local shown = fake:IsShown()
    fake:Hide()
    fake:SetScript("OnUpdate", nil)
    fake = nil
    if shown then BuildFake(); fake:Show() end
end

function A:SetRaidTest(on)
    if not self.raidHolder then return end
    self.raidTest = on and true or nil
    if on then
        if not fake then BuildFake() end
        fake:Show()
        self.raidHolder:Show()
    elseif fake then
        fake:Hide()
    end
end

------------------------------------------------------------------------
-- Roles: tank / healer icons. Read from the talent spec (inspecting group
-- members one at a time out of combat), bear form / frost presence, and the
-- raid's main tank assignment. The group finder role is only a fallback for
-- players not inspected yet, and only when it names a single role (it keeps
-- every role a player ticked in the queue, so it can't be trusted alone).
------------------------------------------------------------------------
local roleCache, roleTried, formSeen = {}, {}, {}
local ROLE_TTL = 300   -- re-inspect after 5 minutes (dual spec swaps)
local HEAL = { PALADIN = { [1] = true }, PRIEST = { [1] = true, [2] = true }, DRUID = { [3] = true }, SHAMAN = { [3] = true } }
local TANK = { WARRIOR = { [3] = true }, PALADIN = { [2] = true } }
local BEAR1, BEAR2, FROSTP = GetSpellInfo(9634), GetSpellInfo(5487), GetSpellInfo(48263)
local NATURAL_REACTION = GetSpellInfo(57878)   -- feral talent only bear tanks take

local function SpecRole(class, inspect)
    local group = GetActiveTalentGroup and GetActiveTalentGroup(inspect) or nil
    local best, pts, total = 0, -1, 0
    for tab = 1, 3 do
        local _, _, spent = GetTalentTabInfo(tab, inspect, false, group)
        spent = spent or 0
        total = total + spent
        if spent > pts then best, pts = tab, spent end
    end
    if total <= 0 then return nil end
    if HEAL[class] and HEAL[class][best] then return "HEALER" end
    if TANK[class] and TANK[class][best] then return "TANK" end
    if class == "DRUID" and best == 2 and NATURAL_REACTION then
        for i = 1, (GetNumTalents(2, inspect) or 0) do
            local name, _, _, _, rank = GetTalentInfo(2, i, inspect, false, group)
            if name == NATURAL_REACTION then
                if rank and rank > 0 then return "TANK" end
                break
            end
        end
    end
    return "DAMAGER"
end

function A:UnitRole(u)
    if not u or not UnitExists(u) or not UnitIsPlayer(u) then return nil end
    local _, class = UnitClass(u)
    if class == "DRUID" and ((BEAR1 and UnitAura(u, BEAR1)) or (BEAR2 and UnitAura(u, BEAR2))) then return "TANK" end
    if class == "DEATHKNIGHT" and FROSTP and UnitAura(u, FROSTP) then return "TANK" end
    if UnitIsUnit(u, "player") then return SpecRole(class, false) end
    if GetNumRaidMembers() > 0 and GetPartyAssignment and GetPartyAssignment("MAINTANK", u) then return "TANK" end
    local c = roleCache[UnitGUID(u) or ""]
    if c then return c.role end
    if UnitGroupRolesAssigned then
        local t, h, d = UnitGroupRolesAssigned(u)
        local n = (t and 1 or 0) + (h and 1 or 0) + (d and 1 or 0)
        if n == 1 then return (t and "TANK") or (h and "HEALER") or "DAMAGER" end
    end
    return nil
end

function A:UpdateRole(f)
    local icon = f.roleIcon
    if not icon or f.unit == "hui-test" then return end
    local r = self:UnitRole(f.unit)
    local show = r == "TANK" or r == "HEALER"
    local was = icon:IsShown()
    if show then
        icon:SetTexture("Interface\\AddOns\\HUI\\media\\role_" .. r:lower())
        icon:Show()
    else
        icon:Hide()
    end
    if f.indAvoidRole and was ~= show then self:UpdateIndicators(f) end
end

local function RefreshRoles()
    for f in pairs(A.allFrames) do
        if f.roleIcon and f:IsVisible() and f.unit then A:UpdateRole(f) end
    end
end

do
    local pending, pendingAt, acc = nil, 0, 0
    local ours = false
    -- another addon (or the inspect window) inspecting someone else in the
    -- meantime would hand us that player's talents: drop ours and retry later
    hooksecurefunc("NotifyInspect", function()
        if not ours and pending then
            roleTried[pending.guid] = GetTime() - 25
            pending = nil
        end
    end)
    local q = CreateFrame("Frame")
    q:RegisterEvent("INSPECT_TALENT_READY")
    q:RegisterEvent("PLAYER_TALENT_UPDATE")
    q:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    q:RegisterEvent("UNIT_AURA")
    q:RegisterEvent("PARTY_MEMBERS_CHANGED")
    q:RegisterEvent("RAID_ROSTER_UPDATE")
    q:SetScript("OnEvent", A:PerfWrap("Raid frames: roles", function(_, event, unit)
        if event == "INSPECT_TALENT_READY" then
            if not pending then return end
            local u = pending.unit
            if UnitExists(u) and UnitGUID(u) == pending.guid then
                local _, class = UnitClass(u)
                local r = SpecRole(class, true)
                if r then roleCache[pending.guid] = { role = r, t = GetTime() } end
            end
            pending = nil
            if not (InspectFrame and InspectFrame:IsShown()) and ClearInspectPlayer then ClearInspectPlayer() end
            RefreshRoles()
        elseif event == "UNIT_AURA" then
            -- bear form / frost presence switch: only druids and death knights
            -- can change role this way, and only a change needs a redraw
            if unit and (unit:find("^raid") or unit:find("^party") or unit == "player") then
                local _, class = UnitClass(unit)
                local form
                if class == "DRUID" then
                    form = ((BEAR1 and UnitAura(unit, BEAR1)) or (BEAR2 and UnitAura(unit, BEAR2))) and true or false
                elseif class == "DEATHKNIGHT" then
                    form = (FROSTP and UnitAura(unit, FROSTP)) and true or false
                else
                    return
                end
                local guid = UnitGUID(unit)
                if not guid or formSeen[guid] == form then return end
                formSeen[guid] = form
                for f in pairs(A.allFrames) do
                    if f.roleIcon and f.unit and f:IsVisible() and UnitIsUnit(f.unit, unit) then A:UpdateRole(f) end
                end
            end
        else
            RefreshRoles()
        end
    end))
    q:SetScript("OnUpdate", A:PerfWrap("Raid frames: role inspect", function(_, el)
        acc = acc + el
        if acc < 1.5 then return end
        acc = 0
        if pending and GetTime() - pendingAt > 4 then pending = nil end
        if pending or InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then return end
        local n, prefix = GetNumRaidMembers(), "raid"
        if n == 0 then n, prefix = GetNumPartyMembers(), "party" end
        local now = GetTime()
        for i = 1, n do
            local u = prefix .. i
            local guid = UnitExists(u) and UnitGUID(u)
            local c = guid and roleCache[guid]
            if guid and (not c or now - c.t > ROLE_TTL) and not UnitIsUnit(u, "player")
                and (not roleTried[guid] or now - roleTried[guid] > 30)
                and CanInspect(u) and CheckInteractDistance(u, 1) then
                roleTried[guid] = now
                pending, pendingAt = { unit = u, guid = guid }, now
                ours = true
                NotifyInspect(u)
                ours = false
                return
            end
        end
    end))
end

------------------------------------------------------------------------
-- Dual spec: in a healing spec the raid frames move to their own spot
-- (centred by default). The two positions are saved separately: move the
-- frames in unlock mode while in each spec.
------------------------------------------------------------------------
function A:MyRole()
    local _, class = UnitClass("player")
    return SpecRole(class, false)
end

-- where a frame sits in the normal layout (its saved / default position), in
-- screen pixels, measured on an invisible stand-in so the frame itself stays put
local proxy
local function NormalRect(key, frame)
    local p = A:GetPosition(key)
    if not (p and frame) then return end
    proxy = proxy or CreateFrame("Frame", nil, UIParent)
    proxy:SetScale(frame:GetScale())
    proxy:SetWidth(frame:GetWidth())
    proxy:SetHeight(frame:GetHeight())
    A:AlignPoint(proxy, p[1], UIParent, p[2], A:Snap(frame, p[3]), A:Snap(frame, p[4]))
    local s = proxy:GetEffectiveScale()
    local r, b, t = proxy:GetRight(), proxy:GetBottom(), proxy:GetTop()
    if not (r and b and t) then return end
    return r * s, b * s, t * s
end

-- DPS / tank: the player cast bar fills the gap between the player and target
-- frames, 1px from each, at its own height on screen (its saved / default spot)
local function FitCastbarOverride()
    local onCDM = A.CDM and A.CDM.CastbarActive and A.CDM:CastbarActive()
    if A.db.castbar and A.db.castbar.fitBetween == false and not onCDM then return nil end
    local pl, tg = A.units and A.units.Player, A.units and A.units.Target
    if not (pl and tg and A.playerCastbar) then return nil end
    return {
        PlayerCastbar = function(f)
            -- cooldown manager shown: the cast bar sits on top of it, same width
            if A.CDMPlaceCastbar and A:CDMPlaceCastbar(f) then return end
            if A.db.castbar and A.db.castbar.fitBetween == false then
                if f.atrNormalW then f:SetWidth(f.atrNormalW) end
                local p = A:GetPosition("PlayerCastbar")
                A:AlignPoint(f, p[1], UIParent, p[2], A:Snap(f, p[3]), A:Snap(f, p[4]))
                return
            end
            local px = A:PX(f)
            local _, b1 = NormalRect("PlayerCastbar", f)
            local r2, _, t2 = NormalRect("Player", pl)
            local s = f:GetEffectiveScale()
            local gap = (tg:GetLeft() or 0) * tg:GetEffectiveScale() - (pl:GetRight() or 0) * pl:GetEffectiveScale()
            if not (b1 and t2) or gap < 60 then
                -- frames too close (or not placed yet): the normal bar
                if f.atrNormalW then f:SetWidth(f.atrNormalW) end
                local p = A:GetPosition("PlayerCastbar")
                A:AlignPoint(f, p[1], UIParent, p[2], A:Snap(f, p[3]), A:Snap(f, p[4]))
                return
            end
            local dy = A:Snap(f, (b1 - t2) / s)
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", pl, "TOPRIGHT", px, dy)
            f:SetPoint("BOTTOMRIGHT", tg, "TOPLEFT", -px, dy)
        end,
    }
end

A.FitCastbarOverride = FitCastbarOverride

function A:UpdateRaidSpecPosition()
    if not self.raidHolder then
        -- no raid frames: only the DPS / tank cast bar fit
        self.layoutOverride = FitCastbarOverride()
        if self.playerCastbar then
            if not self.layoutOverride and self.playerCastbar.atrNormalW then
                self.playerCastbar:SetWidth(self.playerCastbar.atrNormalW)
            end
            self:ApplyPosition("PlayerCastbar", self.playerCastbar)
        end
        return
    end
    -- during loading screens the talents read as empty: keep the current layout
    -- and look again shortly, instead of falling back to the normal one
    local role = self:MyRole()
    if not role then
        self.raidSpecRetry = 1
        return
    end
    local healer = self.db.healerRaidPos ~= false and role == "HEALER"
    local key = healer and "RaidHealer" or "Raid"
    if key == self.raidPosKey then return end
    if InCombatLockdown() then self.raidSpecDirty = true return end
    self.raidPosKey = key
    -- healer mode: bigger raid buttons, laid out again
    local hl = healer and self.db.healerLayout ~= false
    if (self.raidHealerMode or false) ~= hl then
        self.raidHealerMode = hl
        self:LayoutRaid()
    end
    -- healer layout: player left of the raid frames, target right, cast bar on
    -- top with the same width, all 1px apart (they follow the raid frames)
    local holder = self.raidHolder
    if healer and self.db.healerLayout ~= false then
        self.layoutOverride = {
            Player = function(f)
                local gap = (A.db.healerGap or 1) * A:PX(f)
                f:ClearAllPoints()
                f:SetPoint("TOPRIGHT", holder, "TOPLEFT", -gap, 0)
            end,
            Target = function(f)
                local gap = (A.db.healerGap or 1) * A:PX(f)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", holder, "TOPRIGHT", gap, 0)
            end,
            PlayerCastbar = function(f)
                local px = A:PX(f)
                f:SetWidth(holder:GetWidth())
                f:ClearAllPoints()
                f:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, px)
            end,
            -- party frames follow the player frame, keeping the same offset
            -- from it as in the normal layout (stacked above it, edges lined up)
            Party = function(f)
                local pl = A.units and A.units.Player
                local r1, b1 = NormalRect("Party", f)
                local r2, _, t2 = NormalRect("Player", pl)
                if not (r1 and r2) then return end
                local s = f:GetEffectiveScale()
                f:ClearAllPoints()
                f:SetPoint("BOTTOMRIGHT", pl, "TOPRIGHT", A:Snap(f, (r1 - r2) / s), A:Snap(f, (b1 - t2) / s))
            end,
        }
    else
        -- DPS / tank: the cast bar between player and target (if on)
        self.layoutOverride = FitCastbarOverride()
        local cb = self.playerCastbar
        if not self.layoutOverride and cb and cb.atrNormalW then cb:SetWidth(cb.atrNormalW) end
    end
    self:ApplyPosition(key, holder)
    for _, k in ipairs({ "Player", "Target", "PlayerCastbar", "Party" }) do
        local fr = (k == "PlayerCastbar") and self.playerCastbar or (k == "Party") and self.partyHolder
            or (self.units and self.units[k])
        if fr then self:ApplyPosition(k, fr) end
        local mv = self.movers and self.movers[k]
        if mv and mv:IsShown() and self.PlaceMoverPublic then self:PlaceMoverPublic(mv) end
    end
    local m = self.movers and self.movers.Raid
    if m then
        m.key = key
        local base = self.db.modules.party and "Raid" or "Raid / Party"
        m.text:SetText(healer and (base .. "  (healer spec)") or base)
    end
    self:ApplyPosition(key, self.raidHolder)
    if m and m:IsShown() and self.PlaceMoverPublic then self:PlaceMoverPublic(m) end
end

do
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE",
        "CHARACTER_POINTS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not A.raidSpecDirty then return end
        A.raidSpecDirty = nil
        A:UpdateRaidSpecPosition()
    end)
    -- retry while the talents aren't readable yet (after zoning / login)
    local acc = 0
    f:SetScript("OnUpdate", function(_, el)
        if not A.raidSpecRetry then return end
        acc = acc + el
        if acc < 1 then return end
        acc = 0
        A.raidSpecRetry = A.raidSpecRetry + 1
        if A.raidSpecRetry > 30 then A.raidSpecRetry = nil return end
        if A:MyRole() then
            A.raidSpecRetry = nil
            A:UpdateRaidSpecPosition()
        end
    end)
end
