-- HUI - Cooldown manager (DPS / tank specs)
--
-- A small WeakAuras of your own spells, under your cast bar, between the
-- player and target frames (top edge level with theirs):
--   swing timers   main hand / off hand (dual wield) / ranged (Auto Shot)
--   power bar      as wide as the top row, with a percentage
--   top row        big icons
--   bottom row     smaller icons
-- Each icon shows its cooldown, your debuff on the target (or your buff)
-- with time left, stacks, range / power tint, and glows for procs (Rime, Hot
-- Streak, Sudden Death...) and reactive abilities (Revenge, Overpower...).
--
-- Spells are picked, ordered and given conditions ("glow when my debuff is
-- missing on the target", "hide while on cooldown"...) in the settings page
-- (/hui cdm), with a live preview. Saved per character and talent spec; a
-- spec used for the first time starts from its class default (CDMDefaults.lua).
-- Healing specs never load it.

local A = HUI
local CDM = {}
A.CDM = CDM

local floor, ceil, max, min, abs, format = math.floor, math.ceil, math.max, math.min, math.abs, string.format
local tinsert, tremove, ipairs, pairs = table.insert, table.remove, ipairs, pairs
local SetTxt = A.SetTxt
local playerName = UnitName("player")

local defaults = {
    enabled = true,
    size = 37,            -- top row icons (frame units, like the unit frames)
    smallSize = 30,       -- bottom row icons
    spacing = 0,          -- screen pixels between everything
    powerHeight = 10,     -- 0 = no power bar
    powerText = false,
    powerFormat = "smart",   -- "smart": % for mana, the number for rage / energy / runic power; "pct"; "value"
    castbarOnTop = true,  -- your cast bar sits on top, same width
    desaturate = true,    -- grey while on cooldown
    showGCD = true,       -- global cooldown swipe
    rangeColor = true,    -- red when the target is out of range
    powerColor = true,    -- blue when you lack mana / rage / energy
    auras = true,         -- your debuff on the target / your buff with time left
    auraBorder = true,    -- gold border while that aura is up
    procs = true,         -- built-in proc / reactive glows
    glowType = "button",
    glowCustom = false,
    glowColor = { r = 0.95, g = 0.95, b = 0.32, a = 1 },
    oocAlpha = 1,         -- opacity out of combat
    hideVehicle = true,
    swing = true,         -- swing timers on top of the power bar
    swingHeight = 10,
    comboBar = true,      -- rogues and cat druids: combo points above the power bar
    runeBar = true,       -- death knights: the six runes above the runic power bar
    swingWand = false,    -- casters: a ranged bar for wand "Shoot"
    swingText = false,    -- seconds left on the swing bars
    layouts = {},         -- [character][talent tree] = { { top row }, { bottom row } }
}

------------------------------------------------------------------------
-- Built-in knowledge (spell ids -> localized names when the module loads)
------------------------------------------------------------------------
-- spell -> the aura it puts up, when the names differ
local AURA_IDS = {
    [45462] = 55078,   -- Plague Strike -> Blood Plague
    [45477] = 55095,   -- Icy Touch -> Frost Fever
    [20243] = 7386,    -- Devastate -> Sunder Armor
}
-- spells whose own aura shares its name with another one: matched by spell
-- id. Berserk (feral, 50334): the Berserking weapon enchant's proc buff
-- (59620) is also called "Berserk".
local EXACT_AURA_IDS = { [50334] = 50334 }
-- spell -> buffs on you that make it glow ({ id, stacks })
local PROC_IDS = {
    [5308]  = { { 52437 } },                 -- Execute: Sudden Death
    [1464]  = { { 46916 } },                 -- Slam: Bloodsurge ("Slam!")
    [23922] = { { 50227 } },                 -- Shield Slam: Sword and Board
    [7384]  = { { 60503 } },                 -- Overpower: Taste for Blood
    [49184] = { { 59052 }, { 51124 } },      -- Howling Blast: Rime, Killing Machine
    [49143] = { { 51124 } },                 -- Frost Strike: Killing Machine
    [53301] = { { 56453 } },                 -- Explosive Shot: Lock and Load
    [3044]  = { { 56453 }, { 53220 } },      -- Arcane Shot: Lock and Load, Improved Steady Shot
    [19434] = { { 53220 } },                 -- Aimed Shot: Improved Steady Shot
    [53209] = { { 53220 } },                 -- Chimera Shot: Improved Steady Shot
    [11366] = { { 48108 } },                 -- Pyroblast: Hot Streak
    [133]   = { { 57761 } },                 -- Fireball: Brain Freeze
    [44614] = { { 57761 } },                 -- Frostfire Bolt: Brain Freeze
    [30455] = { { 44544 } },                 -- Ice Lance: Fingers of Frost
    [44572] = { { 44544 } },                 -- Deep Freeze: Fingers of Frost
    [5143]  = { { 44401 } },                 -- Arcane Missiles: Missile Barrage
    [2120]  = { { 54741 } },                 -- Flamestrike: Firestarter
    [6353]  = { { 63167 } },                 -- Soul Fire: Decimation
    [29722] = { { 71165 }, { 34936 } },      -- Incinerate: Molten Core, Backlash
    [686]   = { { 17941 }, { 34936 } },      -- Shadow Bolt: Shadow Trance (Nightfall), Backlash
    [403]   = { { 53817, 5 } },              -- Lightning Bolt: Maelstrom Weapon x5
    [421]   = { { 53817, 5 } },              -- Chain Lightning: Maelstrom Weapon x5
    [879]   = { { 59578 } },                 -- Exorcism: The Art of War
    [2912]  = { { 48518 } },                 -- Starfire: Eclipse (Lunar)
    [5176]  = { { 48517 } },                 -- Wrath: Eclipse (Solar)
}
-- usable only after something happened: glow while usable and ready
local REACTIVE_IDS = { 6572, 7384, 5308, 34428, 53351, 19306, 1495, 24275, 56815, 14251 }
-- abilities that replace the next main hand swing (reset its timer when they hit)
local NEXT_MELEE_IDS = { 78, 845, 6807, 2973, 56815 }   -- Heroic Strike, Cleave, Maul, Raptor Strike, Rune Strike
-- next-swing abilities with a cooldown of their own: tracked here too, for
-- servers that don't always send the cooldown (or the hit) to the client
local OWN_CD_IDS = { [2973] = 6, [6807] = 3 }   -- Raptor Strike 6s, Maul 3s
local SLAM_ID = 1464
local RANGED_IDS = { 75, 2480, 7918, 7919, 2764, 3018 }   -- Auto Shot, Shoot Bow / Gun / Crossbow, Throw, Shoot
local WAND_ID = 5019

local auraByName, procByName, reactiveByName, nextMelee, rangedNames = {}, {}, {}, {}, {}
local ownCD = {}        -- name -> seconds
CDM.ownCDStart = {}     -- name -> when it last went off
local SLAM, WAND, CLEAVE, HEROIC, OVERPOWER, SWIPE_CAT, AUTOSHOT, BERSERK, SHRED
local function N(id) return id and (GetSpellInfo(id)) end
local function BuildMaps()
    for s, a in pairs(AURA_IDS) do local n, an = N(s), N(a); if n and an then auraByName[n] = an end end
    for s, list in pairs(PROC_IDS) do
        local n = N(s)
        if n then
            procByName[n] = procByName[n] or {}
            for _, p in ipairs(list) do
                local bn = N(p[1])
                if bn then tinsert(procByName[n], { name = bn, stacks = p[2] }) end
            end
        end
    end
    for _, id in ipairs(REACTIVE_IDS) do local n = N(id); if n then reactiveByName[n] = true end end
    for _, id in ipairs(NEXT_MELEE_IDS) do local n = N(id); if n then nextMelee[n] = true end end
    for _, id in ipairs(RANGED_IDS) do local n = N(id); if n then rangedNames[n] = true end end
    for id, d in pairs(OWN_CD_IDS) do local n = N(id); if n then ownCD[n] = d end end
    SLAM, WAND = N(SLAM_ID), N(WAND_ID)
    CLEAVE = N(845)
    HEROIC = N(78)
    OVERPOWER = N(7384)
    SWIPE_CAT = N(62078)   -- Swipe (Cat): green like Cleave if it's ever queued
    AUTOSHOT = N(75)
    BERSERK = N(50334)
    SHRED = N(5221)
end

------------------------------------------------------------------------
-- Spec / storage
------------------------------------------------------------------------
local _, myClass = UnitClass("player")

-- the talent tree with the most points (0 below level 10), nil while unreadable
local function SpecTab()
    local group = GetActiveTalentGroup and GetActiveTalentGroup() or nil
    local best, pts, total = 0, -1, 0
    for tab = 1, 3 do
        local _, _, spent = GetTalentTabInfo(tab, false, false, group)
        spent = spent or 0
        total = total + spent
        if spent > pts then best, pts = tab, spent end
    end
    if total <= 0 then
        if (UnitLevel("player") or 0) < 10 then return 0 end
        return nil
    end
    return best
end

local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

-- old entries (glow / readyGlow) become conditions
local function Normalize(e)
    if e.glow then
        if e.glow == "none" then e.procs = false
        else
            e.rules = e.rules or {}
            tinsert(e.rules, { c = "buff_up", aura = e.glow, a = "glow" })
        end
        e.glow = nil
    end
    if e.readyGlow then
        e.rules = e.rules or {}
        tinsert(e.rules, { c = "ready", a = "glow" })
        e.readyGlow = nil
    end
    return e
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

-- a default entry: a spell id, { id, id } (the first one you know), or a table
local function KnownName(id)
    local n = id and GetSpellInfo(id)
    return n and GetSpellInfo(n) and n
end
local function MakeEntry(x)
    if type(x) == "number" then
        return { t = "spell", id = x, n = GetSpellInfo(x) }
    elseif type(x) == "table" then
        if x.t == "item" then return Copy(x) end
        local id = x.id
        if not id and x[1] then
            id = x[1]
            for _, alt in ipairs(x) do if KnownName(alt) then id = alt break end end
        end
        if not id then return nil end
        local e = { t = "spell", id = id, n = GetSpellInfo(id) }
        for k, v in pairs(x) do
            if type(k) == "string" and k ~= "id" then e[k] = Copy(v) end
        end
        return Normalize(e)
    end
end

-- Horde racials on the bottom row of every layout: Berserking (troll),
-- Blood Fury (orc; the attack power, mixed or spell power version by class)
local function RacialId()
    local _, race = UnitRace("player")
    if race == "Troll" then return 26297 end
    if race == "Orc" then
        if myClass == "SHAMAN" then return 33697 end
        if myClass == "WARLOCK" or myClass == "MAGE" then return 33702 end
        return 20572
    end
end
local function AddRacial(L)
    local id = RacialId()
    if not id or not (L and L[1]) then return end
    local name = GetSpellInfo(id)
    for r = 1, 2 do
        for _, e in ipairs(L[r] or {}) do
            if e.id == id or (name and e.n == name) then return end
        end
    end
    L[2] = L[2] or {}
    tinsert(L[2], { t = "spell", id = id, n = name })
end

-- false: the defaults file isn't loaded (added to the addon without a game
-- restart), so the spec stays unmarked and gets its default next time
function CDM:SeedLayout(L, spec)
    if not A.CDMClassDefaults then
        if not self.warnedDefaults then
            self.warnedDefaults = true
            A:Print("cooldown manager: the class defaults didn't load. Restart the game (a /reload doesn't load new addon files).")
        end
        return false
    end
    local d = A.CDMClassDefaults[myClass]
    d = d and d[spec]
    L.seeded = true
    if not d then return true end
    for r = 1, 2 do
        for _, x in ipairs(d[r] or {}) do
            local e = MakeEntry(x)
            if e then tinsert(L[r], e) end
        end
    end
    AddRacial(L)
end

function CDM:GetLayout(spec)
    spec = spec or self:ViewSpec()
    if not spec then return nil end
    local db = A.db.cdm
    local c = db.layouts[CharKey()]
    if not c then c = {}; db.layouts[CharKey()] = c end
    c.class = myClass   -- so exports can be turned into class defaults
    local key = tostring(spec)
    local L = c[key]
    if not L then L = { {}, {} }; c[key] = L end
    L[1], L[2] = L[1] or {}, L[2] or {}
    -- first time this spec is used: the class default
    if not L.seeded then
        if spec > 0 and #L[1] == 0 and #L[2] == 0 then
            self:SeedLayout(L, spec)
        else
            L.seeded = true
        end
    end
    for r = 1, 2 do for _, e in ipairs(L[r]) do Normalize(e) end end
    return L
end

-- the spec whose layout is shown: the one picked in the settings preview, or yours
function CDM:ViewSpec()
    if self.previewing and self.editSpec then return self.editSpec end
    return self.spec
end

function CDM:ResetSpec(spec)
    spec = spec or self:ViewSpec()
    local L = self:GetLayout(spec)
    if not L then return end
    wipe(L[1]); wipe(L[2])
    self:SeedLayout(L, spec)
    self:Changed()
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local holder, power, swingBox, combo, runes
local rows = { {}, {} }       -- icon buttons per row
local spare = {}              -- icons not in use
local plus = {}               -- "+" drop slots (edit mode)
local swingBars = {}          -- "mh", "oh", "rg"
local dirty = true

local function PX() return A:PX(holder) end

local function SetFont(fs, size)
    A:SetFontPx(fs, A.media.font, size, "OUTLINE")
    fs:SetShadowOffset(0, 0)
end

-- a font string that already has a font (SetText errors on one without)
local function NewFS(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetFont(fs, size or 12)
    return fs
end

-- whole numbers only (no decimals on the icons): 1:04, 12, 3
local function FmtTime(t)
    if t >= 3600 then return format("%dh", ceil(t / 3600)) end
    local c = ceil(t)
    if c >= 60 then
        local m = floor(c / 60)
        return format("%d:%02d", m, c - m * 60)
    end
    return format("%d", c)
end

local function IconTip(b)
    local e = b.entry
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    if e.t == "item" then
        GameTooltip:SetHyperlink("item:" .. e.id)
    elseif e.id then
        GameTooltip:SetHyperlink("spell:" .. e.id)
    else
        GameTooltip:AddLine(e.n or "?", 1, 1, 1)
    end
    if CDM.editing then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag to move, drag off to remove", 0.6, 0.8, 1)
        GameTooltip:AddLine("Right-click: options", 0.6, 0.8, 1)
    end
    GameTooltip:Show()
end

local function CreateIcon()
    local b = CreateFrame("Button", nil, holder)
    A:SetTemplate(b)
    b.atrCustomBg = true
    b:SetBackdropColor(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:Hide()
    -- coloured border (aura up, or a condition's border colour): a ring just
    -- inside the black outline, over the icon's edge, so a neighbour sharing
    -- that outline (0px spacing) can never cover it
    b.ring = CreateFrame("Frame", nil, b)
    b.ring:SetAllPoints(b)
    b.ring:SetFrameLevel(b:GetFrameLevel() + 3)   -- above the cooldown swipe
    b.ring.edges = {}
    for i = 1, 4 do
        local t = b.ring:CreateTexture(nil, "OVERLAY")
        t:SetTexture(A.media.blank)
        b.ring.edges[i] = t
    end
    b.ring:Hide()
    b.ov = CreateFrame("Frame", nil, b)
    b.ov:SetAllPoints(b)
    b.ov:SetFrameLevel(b:GetFrameLevel() + 6)   -- above the glow (+4): timers stay readable
    b.text = NewFS(b.ov, 14)
    b.text:SetPoint("CENTER", b.ov, "CENTER", 0, 0)   -- centred on the icon
    b.text:SetJustifyH("CENTER")
    b.count = NewFS(b.ov, 11)
    b.count:SetPoint("BOTTOMRIGHT", -1, 2)
    b.count:SetJustifyH("RIGHT")
    b.countPos = "right"
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self) if CDM.editing then IconTip(self) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self) if CDM.editing and not GetCursorInfo() then CDM:BeginDrag(self) end end)
    b:SetScript("OnDragStop", function() CDM:EndDrag() end)
    b:SetScript("OnReceiveDrag", function(self) CDM:DropCursor(self.row, self.index) end)
    b:SetScript("OnClick", function(self, button)
        if not CDM.editing then return end
        if GetCursorInfo() then CDM:DropCursor(self.row, self.index) return end
        if button == "RightButton" then CDM:OpenMenu(self) end
    end)
    b:EnableMouse(false)
    return b
end

local function CreatePlus(row)
    local p = CreateFrame("Button", nil, holder)
    A:SetTemplate(p)
    p.atrCustomBg = true
    p:SetBackdropColor(1, 1, 1, 0.06)
    p:SetBackdropBorderColor(0.4, 0.7, 1, 0.9)
    p.text = NewFS(p, 20)
    p.text:SetPoint("CENTER", 1, 0)
    p.text:SetText("+")
    p.text:SetTextColor(0.6, 0.85, 1)
    p.row = row
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p:SetScript("OnReceiveDrag", function(self) CDM:DropCursor(self.row) end)
    p:SetScript("OnClick", function(self) if GetCursorInfo() then CDM:DropCursor(self.row) end end)
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.row == 1 and "Top row" or "Bottom row", 1, 1, 1)
        GameTooltip:AddLine("Drop a spell or item here (from your spellbook, bags", 0.75, 0.75, 0.78)
        GameTooltip:AddLine("or the spell list), or drag an icon here.", 0.75, 0.75, 0.78)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:Hide()
    return p
end

-- a flat status bar fill; the background re-anchored to the (new) fill texture
local function FlatBar(sb)
    sb:SetStatusBarTexture(A.media.blank)
    local fill = sb:GetStatusBarTexture()
    if fill and sb.bg then
        sb.bg:ClearAllPoints()
        sb.bg:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        sb.bg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
    end
end

local function CreateSwingBar(key, r, g, b)
    local f = CreateFrame("Frame", nil, swingBox)
    A:SetTemplate(f)
    f.bar = A:StatusBar(f)
    -- flat fill: the bar texture's shaded top / bottom rows sit right on the
    -- shared 1px borders and make them look twice as thick where it fills
    FlatBar(f.bar)
    f.bar:SetStatusBarColor(r, g, b)
    f.bar.bg:SetVertexColor(0, 0, 0, 0)   -- no tinted background: the see-through black shows
    f.color = { r, g, b }
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(0)
    f.text = NewFS(f.bar, 10)
    f.text:SetPoint("RIGHT", -2, 0)
    f.key = key
    f:Hide()
    swingBars[key] = f
    return f
end

------------------------------------------------------------------------
-- Swing timers
------------------------------------------------------------------------
local SW = { mh = {}, oh = {}, rg = {} }
local playerGUID

-- which bars this character uses: melee classes / specs, dual wield, ranged
local IsCatForm
local function SwingKinds()
    local k = {}
    local spec = CDM:ViewSpec() or 0
    -- combo points (rogues, druids in cat form): the bottom of the stack,
    -- right on the power bar
    local function addCombo()
        if A.db.cdm.comboBar and (myClass == "ROGUE" or IsCatForm()) then tinsert(k, "cp") end
        -- death knights: the six runes, right on the runic power bar
        if A.db.cdm.runeBar ~= false and myClass == "DEATHKNIGHT" then tinsert(k, "rn") end
    end
    -- swing timers only in combat (always in the settings preview)
    local fighting = CDM.inCombat
    if fighting == nil then fighting = UnitAffectingCombat("player") and true or false end
    if not A.db.cdm.swing or (not fighting and not CDM.previewing) then addCombo() return k end
    -- hunters melee weave: main hand (and off hand) too, above the ranged bar
    local melee = myClass == "WARRIOR" or myClass == "ROGUE" or myClass == "PALADIN" or myClass == "DEATHKNIGHT"
        or myClass == "HUNTER" or (myClass == "SHAMAN" and spec == 2) or (myClass == "DRUID" and spec == 2)
    if melee then
        tinsert(k, "mh")
        local _, oh = UnitAttackSpeed("player")
        if oh and oh > 0 then tinsert(k, "oh") end
    end
    if myClass == "HUNTER" then
        tinsert(k, "rg")
    elseif A.db.cdm.swingWand and (myClass == "MAGE" or myClass == "WARLOCK" or myClass == "PRIEST") then
        tinsert(k, "rg")
    end
    addCombo()
    return k
end

-- a druid in cat form (energy); the settings preview of the Feral layout counts too
IsCatForm = function()
    if myClass ~= "DRUID" then return false end
    if CDM.previewing then return (CDM:ViewSpec() or 0) == 2 end
    local _, token = UnitPowerType("player")
    return token == "ENERGY"
end

local function StartSwing(key, dur)
    if not dur or dur <= 0 then return end
    local s = SW[key]
    s.start, s.dur = GetTime(), dur
end

-- time until a hand is ready (0 when idle / ready)
local function Until(key, now)
    local s = SW[key]
    if not s.start then return 0 end
    local left = s.start + s.dur - now
    return left > 0 and left or 0
end

-- a next-swing ability went off (from the log, or seen leaving the queue):
-- the main hand swing restarts, and its own cooldown starts. Both ways can
-- report the same hit: the second one within a moment is ignored.
local function NextSwingFired(name)
    local now = GetTime()
    local last = CDM.ownCDStart[name]
    if last and now - last < 0.5 then return end
    if ownCD[name] then CDM.ownCDStart[name] = now end
    StartSwing("mh", (UnitAttackSpeed("player")))
end

local function MeleeSwing()
    local mh, oh = UnitAttackSpeed("player")
    if oh and oh > 0 then
        -- 3.3.5's combat log doesn't say which hand: the one due soonest swung
        local now = GetTime()
        if Until("oh", now) < Until("mh", now) then
            StartSwing("oh", oh)
            return
        end
    end
    StartSwing("mh", mh)
end

-- Some servers leave melee swings out of the combat log now and then (seen
-- on hunters: 2 swings logged out of many). While you auto attack (between
-- PLAYER_ENTER_COMBAT and PLAYER_LEAVE_COMBAT) and the target is in melee
-- range, a hand whose swing is overdue swings anyway; a logged swing still
-- puts the timer right whenever one comes.
local MELEE_RANGE_IDS = { 2973, 78, 1752, 6807, 45902, 35395, 17364, 5221 }   -- Raptor Strike, Heroic Strike, Sinister Strike, Maul, Blood Strike, Crusader Strike, Stormstrike, Shred
local PREDICT_GRACE = 0.2   -- seconds a swing may be late before it's taken as missing from the log
local function MeleeRangeSpell()
    if CDM.meleeRangeName == nil then
        CDM.meleeRangeName = false
        for _, id in ipairs(MELEE_RANGE_IDS) do
            local n = GetSpellInfo(id)
            if n and GetSpellInfo(n) then CDM.meleeRangeName = n break end   -- (by name: only spells you know)
        end
    end
    return CDM.meleeRangeName
end
local function InMeleeRange()
    if not (UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")) then return false end
    local n = MeleeRangeSpell()
    if n then
        local r = IsSpellInRange(n, "target")
        if r ~= nil then return r == 1 end
    end
    return CheckInteractDistance("target", 3) and true or false
end
local function PredictHand(key, spd, now)
    if not spd or spd <= 0 then return end
    local s = SW[key]
    if not s.start then
        s.start, s.dur = now, spd
    else
        local due = s.start + s.dur
        if now - due < PREDICT_GRACE then return end
        -- the swing went off when it was due (unless that's long ago: then now)
        s.start = (now - due < spd) and due or now
        s.dur = spd
    end
    CDM.swingPredicted = (CDM.swingPredicted or 0) + 1
end
local function PredictMelee(now)
    if not CDM.autoMelee or not InMeleeRange() then return end
    local mh, oh = UnitAttackSpeed("player")
    PredictHand("mh", mh, now)
    if oh and oh > 0 then PredictHand("oh", oh, now) end
end

-- haste changes: keep the fraction done, stretch the rest
local function Rescale(key, newDur)
    local s = SW[key]
    if not (s.start and newDur and newDur > 0 and s.dur and s.dur > 0) then return end
    local now = GetTime()
    local frac = (now - s.start) / s.dur
    if frac >= 1 then return end
    s.start, s.dur = now - frac * newDur, newDur
end

CDM.igniteTick = {}
local swingEv = CreateFrame("Frame")
swingEv:SetScript("OnEvent", A:PerfWrap("Cooldown manager: combat log / swings", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, ev, src, srcName = ...
        -- this runs for every combat log event in the raid: only a counter
        -- for everyone else (the client-bug check below compares it)
        CDM.clAny = (CDM.clAny or 0) + 1
        -- you: by GUID, or by name (some servers send the GUID in another form)
        if src ~= playerGUID and srcName ~= playerName then return end
        CDM.clTime = GetTime()
        CDM.clSeen = (CDM.clSeen or 0) + 1
        CDM.clLast = ev   -- (for /hui cdm status; it used to build a new string on every hit)
        -- the target dodged you: Overpower is open for 5 seconds (shown in
        -- any stance; the game itself only calls it usable in Battle Stance)
        if (ev == "SWING_MISSED" and select(9, ...) == "DODGE")
            or ((ev == "SPELL_MISSED" or ev == "RANGE_MISSED") and select(12, ...) == "DODGE") then
            CDM.opUntil = GetTime() + 5
            CDM.dodges = (CDM.dodges or 0) + 1
        end
        -- Ignite ticks (yours), per target
        if ev == "SPELL_PERIODIC_DAMAGE" and select(9, ...) == 12654 then
            CDM.igniteTick[select(6, ...)] = select(12, ...)
        elseif ev == "SPELL_AURA_REMOVED" and select(9, ...) == 12654 then
            CDM.igniteTick[select(6, ...)] = nil
        end
        if ev == "SWING_DAMAGE" or ev == "SWING_MISSED" then
            CDM.swingSeen = (CDM.swingSeen or 0) + 1
            MeleeSwing()
        elseif ev == "SPELL_DAMAGE" or ev == "SPELL_MISSED" then
            local id, name = select(9, ...)
            if id == 6603 then   -- auto attack logged as a spell (some servers)
                CDM.swingSeen = (CDM.swingSeen or 0) + 1
                MeleeSwing()
            elseif name and nextMelee[name] then
                NextSwingFired(name)
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, name = ...
        if unit ~= "player" or not name then return end
        -- the 3.3.5 client's combat log can stop delivering events (a known
        -- client bug; addons like CL_Fix work around it): you cast something,
        -- and no combat log event came within a second -> clear it, which
        -- starts it again
        CDM.castTime = GetTime()
        CDM.castCL = CDM.clAny or 0
        if rangedNames[name] or (name == WAND and A.db.cdm.swingWand) then
            StartSwing("rg", (UnitRangedDamage("player")))
        elseif name == OVERPOWER then
            CDM.opUntil = nil   -- used up
        elseif name == SLAM then
            StartSwing("mh", (UnitAttackSpeed("player")))   -- Slam restarts the swing
        end
    elseif event == "UNIT_ATTACK_SPEED" then
        if (...) ~= "player" then return end
        local mh, oh = UnitAttackSpeed("player")
        Rescale("mh", mh); Rescale("oh", oh)
        -- an off hand weapon put on / taken off: add / drop its bar
        local hasOH = (oh and oh > 0) and true or false
        if hasOH ~= CDM.hasOH then CDM.hasOH = hasOH; CDM:Layout() end
    elseif event == "UNIT_RANGEDDAMAGE" then
        if (...) ~= "player" then return end
        Rescale("rg", (UnitRangedDamage("player")))
    elseif event == "PLAYER_ENTER_COMBAT" then
        CDM.autoMelee = true    -- auto attack started
    elseif event == "PLAYER_LEAVE_COMBAT" then
        CDM.autoMelee = false   -- auto attack stopped
    elseif event == "PLAYER_REGEN_ENABLED" then
        for _, s in pairs(SW) do s.start = nil end
        CDM.inCombat = false
        CDM:Layout()   -- the swing timers go away out of combat
    elseif event == "PLAYER_REGEN_DISABLED" then
        CDM.inCombat = true
        CDM:Layout()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if (...) == "player" then CDM:Layout() end
    end
end))

-- handles for /dump debugging
CDM.debug = { swing = SW, rows = rows, bars = swingBars, swingEv = swingEv }

-- Heroic Strike / Cleave (Maul, Raptor Strike, Rune Strike) waiting for the
-- next swing, asked through the spell's spellbook slot. (Not through action
-- buttons: a "/startattack + Heroic Strike" macro has the same icon and stays
-- lit the whole time you auto attack.)
-- melee bars: grey when nothing is queued, orange for Heroic Strike (and the
-- other single-target next-swing abilities), soft green for Cleave
local SWING_IDLE   = { 0.6, 0.6, 0.6 }
local SWING_SINGLE = { 0.95, 0.6, 0.2 }
local SWING_CLEAVE = { 0.55, 0.9, 0.55 }
local queueBook, queueSlots = {}, {}
local queueDirty = true
local function ScanQueueSpells()
    queueDirty = false
    wipe(queueBook); wipe(queueSlots)
    local icons = {}
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if nextMelee[name] or name == SWIPE_CAT then
            queueBook[name] = i   -- the last one is the highest rank
            local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
            if tex then icons[tex] = true end
        end
        i = i + 1
    end
end
CDM.ScanQueueSpells = ScanQueueSpells

function CDM:QueuedReport()
    if queueDirty then ScanQueueSpells() end
    local out = {}
    for name, idx in pairs(queueBook) do
        tinsert(out, name .. "#" .. idx .. "=" .. tostring(IsCurrentSpell(idx, BOOKTYPE_SPELL)))
    end
    return #out > 0 and table.concat(out, ", ") or "none known"
end

-- the queued next-swing spell's name, or nil
local function NextSwingQueued()
    if queueDirty then ScanQueueSpells() end
    for name, idx in pairs(queueBook) do
        if IsCurrentSpell(idx, BOOKTYPE_SPELL) then return name end
    end
end

local function SetSwingColor(f, c)
    if f.shownColor == c then return end
    f.shownColor = c
    local r, g, b = c[1], c[2], c[3]
    f.bar:SetStatusBarColor(r, g, b)
    f.bar.bg:SetVertexColor(0, 0, 0, 0)   -- no tinted background: the see-through black shows
end

local SWING_RANGED = { 0.45, 0.9, 0.45 }
local SWING_NOSHOT = { 0.85, 0.2, 0.2 }   -- hunter too close to shoot

local function UpdateSwing(now)
    if not swingBox:IsShown() then return end
    if swingBars.mh:IsShown() then PredictMelee(now) end
    local showText = A.db.cdm.swingText
    local inCombat = UnitAffectingCombat("player")
    -- both melee bars: what's queued for the next swing. Only in combat: a
    -- Heroic Strike left queued after a fight stays "current" until the next
    -- swing, which kept the bars coloured out of combat.
    local q = inCombat and (swingBars.mh:IsShown() or swingBars.oh:IsShown()) and NextSwingQueued()
    -- Raptor Strike / Maul left the queue while you stood in melee range:
    -- it hit (or missed) - even if the log never said so
    local was = CDM.lastQueued
    if was and was ~= q and ownCD[was] and InMeleeRange() then NextSwingFired(was) end
    CDM.lastQueued = q or nil
    local c = SWING_IDLE
    if q then c = (q == CLEAVE or q == SWIPE_CAT) and SWING_CLEAVE or SWING_SINGLE end
    local f = swingBars.mh
    if f:IsShown() then SetSwingColor(f, c) end
    f = swingBars.oh
    if f:IsShown() then SetSwingColor(f, c) end
    -- ranged (hunters): red while Auto Shot can't fire (melee range / too far)
    local rg = swingBars.rg
    if rg:IsShown() then
        local red = AUTOSHOT and UnitExists("target") and UnitCanAttack("player", "target")
            and not UnitIsDead("target") and IsSpellInRange(AUTOSHOT, "target") == 0
        SetSwingColor(rg, red and SWING_NOSHOT or SWING_RANGED)
    end
    for key, f in pairs(swingBars) do
        if f:IsShown() then
            local s = SW[key]
            local v, left = 0, 0
            if s.start and s.dur and s.dur > 0 then
                left = s.start + s.dur - now
                if left <= 0 then v, left = 1, 0 else v = (now - s.start) / s.dur end
            end
            f.bar:SetValue(v)
            -- the text only when the tenths change (not a new string every frame)
            local tenths = (showText and left > 0) and ceil(left * 10 - 0.5) or -1
            if f.tenths ~= tenths then
                f.tenths = tenths
                f.text:SetText(tenths >= 0 and format("%.1f", tenths / 10) or "")
            end
        end
    end
end

------------------------------------------------------------------------
-- Layout: sizes, rows, width, position
------------------------------------------------------------------------
function CDM:Layout()
    if not holder then return end
    CDM.iconGen = (CDM.iconGen or 0) + 1   -- icons repaint everything on their next update
    local db = A.db.cdm
    if not self.previewing then holder:SetScale(A.db.scale or 1) end
    local px = PX()
    -- scale / resolution changed: borders back to exactly 1 screen pixel
    if holder.atrPX and abs(holder.atrPX - px) > 0.0001 then
        A:SetTemplate(power)
        for _, f in pairs(swingBars) do A:SetTemplate(f) end
        A:SetTemplate(combo)
        A:SetTemplate(runes)
        for r = 1, 2 do
            for _, b in ipairs(rows[r]) do A:SetTemplate(b); b:SetBackdropColor(0, 0, 0, 1) end
            A:SetTemplate(plus[r]); plus[r]:SetBackdropColor(1, 1, 1, 0.06); plus[r]:SetBackdropBorderColor(0.4, 0.7, 1, 0.9)
        end
        for r = 1, 2 do for _, b in ipairs(rows[r]) do b.fs, b.cs = nil, nil end end
    end
    holder.atrPX = px
    -- spacing 0: neighbours overlap by one pixel, so touching borders share a
    -- single 1px line (instead of two lines side by side = a 2px border)
    local sp = max(0, db.spacing or 1)
    local g = sp == 0 and -px or sp * px
    local S1, S2 = A:Snap(holder, db.size), A:Snap(holder, db.smallSize)
    local L = self:GetLayout() or { {}, {} }
    local n1, n2 = #L[1], #L[2]
    local editing = self.editing

    local w1 = n1 > 0 and (n1 * S1 + (n1 - 1) * g) or 0
    local w2 = n2 > 0 and (n2 * S2 + (n2 - 1) * g) or 0
    local W = (n1 > 0 and w1) or (n2 > 0 and w2) or (6 * S1 + 5 * g)
    holder:SetWidth(W)

    -- power bar (its top edge is the module's top edge)
    local y = 0
    local ph = A:Snap(holder, db.powerHeight or 0)
    if ph > 0 then
        power:ClearAllPoints()
        power:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        power:SetWidth(W)
        power:SetHeight(ph)
        power.bar:ClearAllPoints()
        power.bar:SetPoint("TOPLEFT", px, -px)
        power.bar:SetPoint("BOTTOMRIGHT", -px, px)
        SetFont(power.text, max(8, min(A:FS("units"), ph - 2)))
        power.text:ClearAllPoints()
        power.text:SetPoint("CENTER", px, px)   -- 1px up: sits centred on the letters
        if db.powerText then power.text:Show() else power.text:Hide() end
        power:Show()
        y = ph + g
    else
        power:Hide()
    end

    -- rows
    -- each icon stays with its spell, so a reorder moves the icon (and can
    -- slide) instead of swapping pictures between fixed slots
    do
        local all, byEntry, used = {}, {}, {}
        for r = 1, 2 do for _, b in ipairs(rows[r]) do tinsert(all, b) end end
        for _, b in ipairs(spare) do tinsert(all, b) end
        for _, b in ipairs(all) do if b.entry then byEntry[b.entry] = b end end
        local new = { {}, {} }
        for r = 1, 2 do
            for i, e in ipairs(L[r]) do
                local b = byEntry[e]
                if b and not used[b] then used[b] = true; new[r][i] = b end
            end
        end
        local free = {}
        for _, b in ipairs(all) do if not used[b] then tinsert(free, b) end end
        for r = 1, 2 do
            for i = 1, #L[r] do
                if not new[r][i] then
                    local b = tremove(free, 1)
                    if b then b.ax = nil else b = CreateIcon() end   -- a new spell appears in place
                    new[r][i] = b
                end
            end
        end
        wipe(spare)
        for _, b in ipairs(free) do
            A.Glow.Stop(b); b.glowing = nil
            b.entry, b.ax, b.ay, b.tx, b.ty = nil, nil, nil, nil, nil
            b:Hide()
            tinsert(spare, b)
        end
        for r = 1, 2 do
            wipe(rows[r])
            for i, b in ipairs(new[r]) do rows[r][i] = b end
        end
    end

    local function placeRow(r, list, S, n, w, top)
        local x0 = A:Snap(holder, (W - (n > 0 and w or S)) / 2)
        if r == 1 and n > 0 then x0 = 0 end
        local fs = max(8, floor(S * 0.4 + 0.5))
        local cs = max(8, floor(S * 0.3 + 0.5))
        for i = 1, n do
            local b = rows[r][i]
            b.row, b.index = r, i
            b:SetWidth(S); b:SetHeight(S)
            local x, y = x0 + (i - 1) * (S + g), -top
            if b.ax and b:IsShown() and (b.ax ~= x or b.ay ~= y) then
                b.tx, b.ty = x, y          -- slides there (CDM:Animate)
                CDM.animating = true
            else
                b.ax, b.ay, b.tx, b.ty = x, y, nil, nil
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
            end
            b.icon:ClearAllPoints()
            b.icon:SetPoint("TOPLEFT", px, -px)
            b.icon:SetPoint("BOTTOMRIGHT", -px, px)
            -- the coloured ring: 1px, right inside the black outline
            local e = b.ring.edges
            e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", px, -px); e[1]:SetPoint("TOPRIGHT", -px, -px); e[1]:SetHeight(px)
            e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", px, px); e[2]:SetPoint("BOTTOMRIGHT", -px, px); e[2]:SetHeight(px)
            e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", px, -2 * px); e[3]:SetPoint("BOTTOMLEFT", px, 2 * px); e[3]:SetWidth(px)
            e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", -px, -2 * px); e[4]:SetPoint("BOTTOMRIGHT", -px, 2 * px); e[4]:SetWidth(px)
            if b.fs ~= fs then b.fs = fs; SetFont(b.text, fs) end
            if b.cs ~= cs then b.cs = cs; b.countFs = nil end
            CDM:SetEntry(b, list[i])
            b:EnableMouse(editing and true or false)
            b:Show()
        end
        -- edit mode: a "+" slot after the row
        local p = plus[r]
        if editing then
            p:SetWidth(S); p:SetHeight(S)
            p:ClearAllPoints()
            local px0 = n > 0 and (x0 + n * (S + g)) or x0
            p:SetPoint("TOPLEFT", holder, "TOPLEFT", px0, -top)
            SetFont(p.text, max(10, floor(S * 0.6)))
            p:Show()
        else
            p:Hide()
        end
    end
    if n1 > 0 or editing then
        placeRow(1, L[1], S1, n1, w1, y)
        y = y + S1 + g
    else
        placeRow(1, L[1], S1, 0, 0, y)
    end
    if n2 > 0 or editing then
        placeRow(2, L[2], S2, n2, w2, y)
        y = y + S2 + g
    else
        placeRow(2, L[2], S2, 0, 0, y)
    end
    holder:SetHeight(max(px, y - g))

    -- swing timers: stacked upwards from the power bar, same width
    local kinds = SwingKinds()
    local sh = A:Snap(holder, max(2, db.swingHeight or 6))
    for _, f in pairs(swingBars) do f:Hide() end
    if #kinds > 0 then
        swingBox:SetWidth(W)
        -- each bar's height and top (the rune bar is twice as tall)
        local hOf, topOf, total = {}, {}, 0
        for i, key in ipairs(kinds) do
            hOf[i] = (key == "rn") and (2 * sh) or sh
            topOf[i] = total
            total = total + hOf[i] + g
        end
        swingBox:SetHeight(total - g)
        swingBox:ClearAllPoints()
        swingBox:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, g)
        -- top to bottom: main hand, off hand, ranged (the last sits on the power bar)
        combo:Hide(); runes:Hide()
        -- n boxes as wide as the module: inside the outline, n equal parts
        -- (whole pixels) with a 1px black line between each
        local function LayoutSegs(bar, n, i, vertical)
            local bh = hOf[i]
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", swingBox, "TOPLEFT", 0, -topOf[i])
            bar:SetWidth(W); bar:SetHeight(bh)
            bar.innerH = bh - 2 * px
            local inner = W - 2 * px
            local edges = {}
            for k = 0, n do edges[k] = px + floor(k * (inner + px) / n / px + 0.5) * px end
            for k = 1, n do
                local seg = bar.segs[k]
                local right = (k < n) and (edges[k] - px) or (W - px)
                seg.w = max(px, right - edges[k - 1])
                seg.fill:ClearAllPoints()
                if vertical then
                    -- fills from the bottom up (RuneUpdate sets the height)
                    seg.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", edges[k - 1], px)
                    seg.fill:SetHeight(bar.innerH)
                    seg.uH = nil   -- RuneUpdate sets it again
                else
                    seg.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", edges[k - 1], -px)
                    seg.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", edges[k - 1], px)
                end
                seg.fill:SetWidth(seg.w)
                if seg.text then
                    seg.text:ClearAllPoints()
                    seg.text:SetPoint("CENTER", bar, "BOTTOMLEFT", edges[k - 1] + seg.w / 2, bh / 2)
                    SetFont(seg.text, max(8, floor(bh * 0.55 + 0.5)))
                end
            end
            for k = 1, n - 1 do
                local l = bar.lines[k]
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", bar, "TOPLEFT", edges[k] - px, -px)
                l:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", edges[k] - px, px)
                l:SetWidth(px)
            end
            bar.px = px
            bar:Show()
        end
        for i, key in ipairs(kinds) do
            if key == "cp" then
                LayoutSegs(combo, 5, i)
            elseif key == "rn" then
                LayoutSegs(runes, 6, i, true)
            else
                local f = swingBars[key]
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", swingBox, "TOPLEFT", 0, -topOf[i])
                f:SetWidth(W); f:SetHeight(sh)
                f.bar:ClearAllPoints()
                f.bar:SetPoint("TOPLEFT", px, -px)
                f.bar:SetPoint("BOTTOMRIGHT", -px, px)
                SetFont(f.text, max(8, min(A:FS("units"), sh)))
                f:Show()
            end
        end
        -- the line under each bar of the stack (the last one is the line
        -- shared with the power bar): drawn black on a layer above every bar,
        -- so no bar's fill can cover a shared border, whatever the draw order
        local lines = swingBox.lines
        for i = 1, #kinds do
            local l = lines[i]
            if not l then
                l = swingBox.over:CreateTexture(nil, "OVERLAY")
                l:SetTexture(A.media.blank)
                l:SetVertexColor(0, 0, 0, 1)
                lines[i] = l
            end
            local bottom = -(topOf[i] + hOf[i] - px)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", swingBox, "TOPLEFT", 0, bottom)
            l:SetWidth(W); l:SetHeight(px)
            l:Show()
        end
        for i = #kinds + 1, #lines do lines[i]:Hide() end
        swingBox.over:SetFrameLevel(swingBox:GetFrameLevel() + 10)
        swingBox:Show()
    else
        swingBox:Hide()
    end

    if self.previewing then self:FitPreview() else self:Place() end
    dirty = true
end

-- icons sliding to their new places after a change (reorder, add, remove,
-- size, spacing): eased, about 0.2 seconds, ending on whole pixels
function CDM:Animate(el)
    if not self.animating then return end
    local k = min(1, el * 14)
    local px = PX()
    local moving = false
    for r = 1, 2 do
        for _, b in ipairs(rows[r]) do
            if b.tx then
                local dx, dy = b.tx - b.ax, b.ty - b.ay
                if abs(dx) < px * 0.5 and abs(dy) < px * 0.5 then
                    b.ax, b.ay, b.tx, b.ty = b.tx, b.ty, nil, nil
                else
                    b.ax, b.ay = b.ax + dx * k, b.ay + dy * k
                    moving = true
                end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", holder, "TOPLEFT", b.ax, b.ay)
            end
        end
    end
    self.animating = moving
end

-- what the cast bar sits on: the swing timers, or the module itself
function CDM:TopFrame()
    if swingBox and swingBox:IsShown() then return swingBox end
    return holder
end

-- centred between the player and target frames, top edge level with theirs
function CDM:PlaceAuto()
    local pl, tg = A.units and A.units.Player, A.units and A.units.Target
    local hs = holder:GetEffectiveScale()
    if pl and tg and pl:GetRight() and tg:GetLeft() then
        local plR = pl:GetRight() * pl:GetEffectiveScale() / hs
        local tgL = tg:GetLeft() * tg:GetEffectiveScale() / hs
        local gap = tgL - plR
        if gap > holder:GetWidth() then
            holder:ClearAllPoints()
            holder:SetPoint("TOPLEFT", pl, "TOPRIGHT", A:Snap(holder, (gap - holder:GetWidth()) / 2), 0)
            return
        end
    end
    local p = A.defaultPositions.CDM
    A:AlignPoint(holder, p[1], UIParent, p[2], A:Snap(holder, p[3]), A:Snap(holder, p[4]))
end

-- the module's top-left corner on a whole screen pixel. Anchored to the
-- unit frames it can land between two pixels; then every 1px line inside
-- (the borders the bars share) falls on a pixel boundary and the card
-- draws it on neither row, or the bar next to it takes the row.
function CDM:SnapToPixels()
    local l, t = holder:GetLeft(), holder:GetTop()
    if not l or not t then return end
    local px = PX()
    local sl, st = floor(l / px + 0.5) * px, floor(t / px + 0.5) * px
    if math.abs(sl - l) < px * 0.01 and math.abs(st - t) < px * 0.01 then return end
    -- keep whatever it is anchored to (the preview box, the unit frames):
    -- only shift that anchor's offsets by the fraction of a pixel.
    -- GetLeft / GetTop and the offsets are both in the holder's own units.
    if holder:GetNumPoints() ~= 1 then return end
    local p, rel, rp, x, y = holder:GetPoint(1)
    holder:ClearAllPoints()
    holder:SetPoint(p, rel, rp, (x or 0) + (sl - l), (y or 0) + (st - t))
end

function CDM:Place()
    if not holder then return end
    A:ApplyPosition("CDM", holder)
    self:SnapToPixels()
    local m = A.movers and A.movers.CDM
    if m and m:IsShown() and A.PlaceMoverPublic then A:PlaceMoverPublic(m) end
    self:RefreshCastbar()
end

-- the player cast bar on top of the module (DPS / tank layout)
function CDM:CastbarActive()
    return holder and holder:IsShown() and not self.previewing and A.db.cdm.castbarOnTop and true or false
end

function A:CDMPlaceCastbar(f)
    if not CDM:CastbarActive() then return false end
    local top = CDM:TopFrame()
    local px = A:PX(f)
    -- same spacing as inside the module (0: the borders share one line)
    local sp = max(0, A.db.cdm.spacing or 1)
    local gap = sp == 0 and -px or sp * px
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 0, gap)
    f:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", 0, gap)
    return true
end

function CDM:RefreshCastbar()
    local cb = A.playerCastbar
    if not cb or A.raidPosKey == "RaidHealer" then return end
    if A.FitCastbarOverride then
        A.layoutOverride = A.FitCastbarOverride()
    end
    if not A.layoutOverride and cb.atrNormalW then cb:SetWidth(cb.atrNormalW) end
    A:ApplyPosition("PlayerCastbar", cb)
    local m = A.movers and A.movers.PlayerCastbar
    if m and m:IsShown() and A.PlaceMoverPublic then A:PlaceMoverPublic(m) end
end

------------------------------------------------------------------------
-- Conditions ("when X, then Y"), per icon. Names left empty mean the
-- icon's tracked aura.
------------------------------------------------------------------------
CDM.CONDS = {
    { "ready",          "Ready (off cooldown and usable)" },
    { "oncd",           "On cooldown" },
    { "cd_below",       "Cooldown ends in less than (sec)", num = true },
    { "usable",         "Usable" },
    { "unusable",       "Not usable" },
    { "spell_oncd",     "Spell on cooldown", text = true },
    { "spell_ready",    "Spell off cooldown", text = true },
    { "nopower",        "Not enough power" },
    { "oor",            "Target out of range" },
    { "aura_up",        "Tracked aura is up" },
    { "aura_missing",   "Tracked aura is missing" },
    { "aura_below",     "Tracked aura missing or ends in < (sec)", num = true },
    { "debuff_missing", "My debuff missing on target", text = true },
    { "debuff_up",      "My debuff on target", text = true },
    { "buff_missing",   "Buff missing on me", text = true },
    { "buff_up",        "Buff on me", text = true },
    { "stacks",         "Buff on me with stacks at least", text = true, num = true },
    { "target_hp",      "Target health at or below (%)", num = true },
    { "player_hp",      "My health below (%)", num = true },
    { "power_above",    "My power at least", num = true },
    { "power_below",    "My power below", num = true },
    { "combat",         "In combat" },
    { "nocombat",       "Out of combat" },
}
CDM.ACTIONS = {
    { "glow",   "Glow" },
    { "noglow", "Never glow" },
    { "hide",   "Hide" },
    { "dim",    "Fade" },
    { "desat",  "Grey out" },
    { "tint",   "Tint icon", color = true },
    { "border", "Border color", color = true },
}
local condInfo, actInfo = {}, {}
for _, c in ipairs(CDM.CONDS) do condInfo[c[1]] = c end
for _, a in ipairs(CDM.ACTIONS) do actInfo[a[1]] = a end

-- one-click presets in the right-click menu
CDM.PRESETS = {
    { "Glow when ready", { c = "ready", a = "glow" } },
    { "Glow when my debuff is missing on target", { c = "debuff_missing", a = "glow" } },
    { "Glow when my buff is missing", { c = "buff_missing", a = "glow" } },
    { "Glow to refresh (missing or < 3 sec)", { c = "aura_below", v = 3, a = "glow" } },
    { "Hide while on cooldown", { c = "oncd", a = "hide" } },
    { "Fade when not usable", { c = "unusable", a = "dim" } },
}

local function SameRule(x, y)
    return x.c == y.c and x.a == y.a and (x.v or 0) == (y.v or 0) and (x.aura or "") == (y.aura or "")
end
function CDM:HasRule(e, r)
    for i, x in ipairs(e.rules or {}) do if SameRule(x, r) then return i end end
end
function CDM:ToggleRule(e, r)
    e.rules = e.rules or {}
    local i = self:HasRule(e, r)
    if i then tremove(e.rules, i) else tinsert(e.rules, Copy(r)) end
    if #e.rules == 0 then e.rules = nil end
    self:Changed()
end

------------------------------------------------------------------------
-- Entries
------------------------------------------------------------------------
function CDM:SetEntry(b, e)
    if b.entry ~= e then
        b.entry = e
        b.cdS, b.cdD = nil, nil
        b.cd:Hide()
        if b.glowing then A.Glow.Stop(b); b.glowing = nil end
    end
    if e.t == "item" then
        b.spellName = nil
        b.icon:SetTexture(GetItemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.uDesat, b.uR = nil, nil
        b.autoAura = GetItemSpell(e.id)
    else
        local name, _, icon = nil, nil, nil
        if e.id then name, _, icon = GetSpellInfo(e.id) end
        name = name or e.n
        if not icon and name then icon = GetSpellTexture(name) end
        b.spellName = name
        b.baseTex = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        b.icon:SetTexture(b.baseTex)
        b.shownTex = b.baseTex
        b.uDesat, b.uR = nil, nil   -- a new picture: send grey / tint again
        b.autoAura = name and (auraByName[name] or name)
    end
    -- the aura(s) this icon tracks: its own name, or what you set (several
    -- allowed: "Mangle (Cat);Mangle (Bear)", or spell ids)
    b.exactAura = nil
    if e.aura and e.aura ~= "" and e.aura ~= "none" then
        b.trackNames = CDM.NameList(e.aura)
    else
        b.trackNames = { b.autoAura }
        if e.t ~= "item" and e.id then b.exactAura = EXACT_AURA_IDS[e.id] end
    end
    b.trackName = b.trackNames[1]
end

-- your auras, read once per update: your debuffs on the target, your buffs on
-- you and your pet. Checked by who cast them, not by the "PLAYER" filter, which
-- 3.3.5 doesn't honour when looking an aura up by name (someone else's Sunder
-- Armor stacks counted as yours).
local MINE = { player = true, pet = true, vehicle = true }
local myAuras = { target = {}, player = {}, pet = {} }
local anyTarget = {}   -- every debuff on the target, whoever cast it
local anyPlayer = {}   -- every buff on you, whoever cast it (Horn of Winter)
-- your auras from EXACT_AURA_IDS, by spell id (same layout as myAuras)
local myById = { target = {}, player = {}, pet = {} }
local exactWatch = {}
for _, id in pairs(EXACT_AURA_IDS) do exactWatch[id] = true end
local function Keep(into, key, n, c, d, x, t)
    local o = into[key]
    if not o then o = {}; into[key] = o end
    if not o.n or (x or 0) > (o.x or 0) then o.n, o.c, o.d, o.x, o.t = n, c, d, x, t end
end
local function ScanMine(unit, filter, into, all, byId)
    for _, v in pairs(into) do v.n = nil end
    if all then for _, v in pairs(all) do v.n = nil end end
    for _, v in pairs(byId) do v.n = nil end
    if not UnitExists(unit) then return end
    -- every aura, not just the first 40: a raid boss easily carries 40+
    -- debuffs from 25 players, and yours could sit past slot 40
    for i = 1, 255 do
        local n, _, t, c, _, d, x, caster, _, _, sid = UnitAura(unit, i, filter)
        if not n then break end
        if caster and MINE[caster] then
            Keep(into, n, n, c, d, x, t)
            if sid and exactWatch[sid] then Keep(byId, sid, n, c, d, x, t) end
        end
        if all then Keep(all, n, n, c, d, x, t) end
    end
end
local function ScanMyAuras()
    ScanMine("target", "HARMFUL", myAuras.target, anyTarget, myById.target)
    ScanMine("player", "HELPFUL", myAuras.player, anyPlayer, myById.player)
    ScanMine("pet", "HELPFUL", myAuras.pet, nil, myById.pet)
end
-- your aura from one exact spell id (EXACT_AURA_IDS)
local function FindAuraById(id, noPet)
    local o, where = myById.player[id], "player"
    if not (o and o.n) then o, where = myById.target[id], "target" end
    if not (o and o.n) and not noPet then o, where = myById.pet[id], "pet" end
    if o and o.n then return o.n, o.c, o.d, o.x, where, o.t end
end
-- a buff on you with this exact spell id (not just its name)
local function PlayerHasAuraId(id)
    for i = 1, 255 do
        local n, _, _, _, _, _, _, _, _, _, sid = UnitAura("player", i, "HELPFUL")
        if not n then return false end
        if sid == id then return true end
    end
    return false
end

-- a list of aura names from: a name, "name;name", a spell id, or a table of those
local nameListCache = {}
function CDM.NameList(x, fresh)
    -- the same text always gives the same list: keep it (Test() asked for it
    -- on every icon update). Callers that change the list pass fresh = true.
    if not fresh and type(x) == "string" then
        local c = nameListCache[x]
        if c then return c end
        c = CDM.NameList(x, true)
        nameListCache[x] = c
        return c
    end
    local out = {}
    if type(x) == "table" then
        for _, v in ipairs(x) do
            local n = CDM.ResolveName(v)
            if n then tinsert(out, n) end
        end
    elseif type(x) == "string" and x:find(";", 1, true) then
        for part in x:gmatch("[^;]+") do
            part = part:gsub("^%s+", ""):gsub("%s+$", "")
            if part ~= "" then tinsert(out, CDM.ResolveName(part) or part) end
        end
    elseif x ~= nil then
        tinsert(out, CDM.ResolveName(x) or x)
    end
    return out
end

-- returns name, stacks, duration, expires, and where: "target" / "player" / "pet".
-- Yours first; with any = true, someone else's on the target counts too
-- (Hunter's Mark, Mangle, Faerie Fire).
-- "newest" lookups: one shared helper instead of a new function every call
local nBest, nStart, nWhere
local function Consider(o, where)
    if not (o and o.n) then return end
    local st = (o.x and o.d and o.d > 0) and (o.x - o.d) or 0
    if not nBest or st > nStart then nBest, nStart, nWhere = o, st, where end
end

local function FindAura(names, any, newest, noPet, byName)
    if type(names) ~= "table" then names = { names } end
    -- byName: the list is a priority order - the first name that's up, from
    -- anyone, wins (Expose Armor over Sunder Armor)
    if byName then
        for _, name in ipairs(names) do
            local o, where = myAuras.target[name], "target"
            if not (o and o.n) then o, where = myAuras.player[name], "player" end
            if not (o and o.n) and not noPet then o, where = myAuras.pet[name], "pet" end
            if not (o and o.n) and any then o, where = anyTarget[name], "target" end
            if o and o.n then return o.n, o.c, o.d, o.x, where, o.t end
        end
        return
    end
    -- newest: of all the listed auras that are up, the one applied last
    -- (Improved Scorch / Shadow Mastery: the same 5% crit debuff)
    if newest then
        nBest, nStart, nWhere = nil, nil, nil
        for _, name in ipairs(names) do
            Consider(myAuras.target[name], "target")
            Consider(myAuras.player[name], "player")
            if not noPet then Consider(myAuras.pet[name], "pet") end
            if any then Consider(anyTarget[name], "target"); Consider(anyPlayer[name], "player") end
        end
        local best = nBest
        if best then return best.n, best.c, best.d, best.x, nWhere, best.t end
        return
    end
    for _, name in ipairs(names) do
        local o, where = myAuras.target[name], "target"
        if not (o and o.n) then o, where = myAuras.player[name], "player" end
        if not (o and o.n) and not noPet then o, where = myAuras.pet[name], "pet" end
        if o and o.n then return o.n, o.c, o.d, o.x, where, o.t end
    end
    if any then
        for _, name in ipairs(names) do
            local o = anyTarget[name]
            if o and o.n then return o.n, o.c, o.d, o.x, "target", o.t end
            o = anyPlayer[name]
            if o and o.n then return o.n, o.c, o.d, o.x, "player", o.t end
        end
    end
end

local function HasBuff(name, stacks)
    if type(name) == "table" then
        for _, n in ipairs(name) do if HasBuff(n, stacks) then return true end end
        return false
    end
    local n, _, _, c = UnitAura("player", name, nil, "HELPFUL")
    if not n then return false end
    return not stacks or (c or 0) >= stacks
end

local function MyDebuff(names, any)
    if type(names) ~= "table" then names = { names } end
    for _, name in ipairs(names) do
        local o = myAuras.target[name]
        if o and o.n then return o.n end
        if any then
            o = anyTarget[name]
            if o and o.n then return o.n end
        end
    end
end

local function GlowColor()
    local db = A.db.cdm
    if not db.glowCustom then return nil end
    local c = db.glowColor
    return { c.r, c.g, c.b, c.a or 1 }
end

-- death knight spells: the runes they cost (blood, frost, unholy), and how
-- long until you have them (a death rune stands in for any kind)
local RUNE_COST_IDS = {
    [43265] = { 1, 1, 1 },   -- Death and Decay
    [45902] = { 1, 0, 0 },   -- Blood Strike
    [55090] = { 0, 1, 1 },   -- Scourge Strike
    [49020] = { 0, 1, 1 },   -- Obliterate
    [49184] = { 0, 1, 1 },   -- Howling Blast
    [49998] = { 0, 1, 1 },   -- Death Strike
    [45477] = { 0, 1, 0 },   -- Icy Touch
    [45462] = { 0, 0, 1 },   -- Plague Strike
    [55050] = { 1, 0, 0 },   -- Heart Strike
    [50842] = { 1, 0, 0 },   -- Pestilence
    [48721] = { 1, 0, 0 },   -- Blood Boil
}
local runeCostByName
local runeKinds = { {}, {}, {}, {} }   -- reused by RuneWait
local RUNE_SLOT_KIND = { 1, 1, 3, 3, 2, 2 }   -- slot -> 1 blood / 2 frost / 3 unholy (game: 3-4 unholy, 5-6 frost)
local function RuneWait(name, now)
    if myClass ~= "DEATHKNIGHT" or not GetRuneCooldown or not name then return nil end
    if not runeCostByName then
        runeCostByName = {}
        for id, c in pairs(RUNE_COST_IDS) do
            local n = GetSpellInfo(id)
            if n then runeCostByName[n] = c end
        end
    end
    local cost = runeCostByName[name]
    if not cost then return nil end
    -- when each rune is ready, by kind (1 blood, 2 frost, 3 unholy, 4 death)
    local byKind = runeKinds
    for k = 1, 4 do wipe(byKind[k]) end
    for slot = 1, 6 do
        local st, d, ready = GetRuneCooldown(slot)
        local at = (ready or not st or not d or d <= 0) and now or (st + d)
        local t = GetRuneType and GetRuneType(slot)
        local kind = (t == 4) and 4 or RUNE_SLOT_KIND[slot]
        tinsert(byKind[kind], at)
    end
    for k = 1, 4 do table.sort(byKind[k]) end
    local deaths, di = byKind[4], 1
    local wait = now
    for kind = 1, 3 do
        local list, li = byKind[kind], 1
        for _ = 1, cost[kind] do
            -- the soonest of: this kind's next rune, or the next death rune
            local a, d = list[li], deaths[di]
            local at
            if a and (not d or a <= d) then at, li = a, li + 1
            elseif d then at, di = d, di + 1
            else return nil end
            if at > wait then wait = at end
        end
    end
    return wait - now
end

local function IsRuneCD(start, dur)
    if myClass ~= "DEATHKNIGHT" or not GetRuneCooldown then return false end
    for i = 1, 6 do
        local s, d = GetRuneCooldown(i)
        if s and d and d > 0 and abs(s - start) < 0.01 and abs(d - dur) < 0.01 then return true end
    end
    return false
end

local function Pct(cur, mx) return (mx and mx > 0) and (cur / mx * 100) or 100 end

-- a name typed or saved as text, or a spell id (the defaults use ids, so they
-- work in every language)
local function ResolveName(x)
    if type(x) == "number" then return (GetSpellInfo(x)) end
    if type(x) == "string" and x:match("^%d+$") then return (GetSpellInfo(tonumber(x))) or x end
    return x
end
CDM.ResolveName = ResolveName

-- another spell on cooldown (the global cooldown and empty runes don't count)
local function SpellOnCD(name)
    local s, d, en = GetSpellCooldown(name)
    if not s or en ~= 1 or s <= 0 or not d or d <= 1.5 then return false end
    return not IsRuneCD(s, d)
end

-- is one condition true right now?
local function Test(r, st, b)
    local c = r.c
    local v = tonumber(r.v) or 0
    local name = (r.aura and r.aura ~= "") and CDM.NameList(r.aura) or b.trackNames
    if name and #name == 0 then name = nil end
    local any = b.entry and b.entry.anyCaster
    if c == "ready" then return st.ready
    elseif c == "oncd" then return st.onCD
    elseif c == "cd_below" then return st.onCD and st.cdLeft < v
    elseif c == "usable" then return st.known and st.usable and true or false
    elseif c == "unusable" then return st.known and not st.usable
    elseif c == "spell_oncd" then
        local sp = (r.aura and r.aura ~= "") and ResolveName(r.aura) or b.spellName
        return sp and SpellOnCD(sp) or false
    elseif c == "spell_ready" then
        local sp = (r.aura and r.aura ~= "") and ResolveName(r.aura) or b.spellName
        return sp and GetSpellCooldown(sp) ~= nil and not SpellOnCD(sp) or false
    elseif c == "nopower" then return st.noPower and true or false
    elseif c == "oor" then return st.inRange == 0
    elseif c == "aura_up" then return st.aura ~= nil
    elseif c == "aura_missing" then return st.aura == nil
    elseif c == "aura_below" then
        if not st.aura then return true end
        return st.auraLeft ~= nil and st.auraLeft < v
    elseif c == "debuff_missing" then
        -- only with something to put it on
        if not (name and UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")) then return false end
        return MyDebuff(name, any) == nil
    elseif c == "debuff_up" then return name and MyDebuff(name, any) ~= nil
    elseif c == "buff_missing" then return name and not HasBuff(name)
    elseif c == "buff_up" then return name and HasBuff(name)
    elseif c == "stacks" then return name and HasBuff(name, max(1, v))
    elseif c == "target_hp" then
        return UnitExists("target") and not UnitIsDead("target") and Pct(UnitHealth("target"), UnitHealthMax("target")) <= v
    elseif c == "player_hp" then return Pct(UnitHealth("player"), UnitHealthMax("player")) < v
    elseif c == "power_above" then return (UnitPower("player") or 0) >= v
    elseif c == "power_below" then return (UnitPower("player") or 0) < v
    elseif c == "combat" then return UnitAffectingCombat("player") and true or false
    elseif c == "nocombat" then return not UnitAffectingCombat("player")
    end
    return false
end

local ruleState = {}   -- reused for every icon's conditions
local function UpdateIcon(b, now)
    local e = b.entry
    if not e then return end
    local db = A.db.cdm
    -- what was last sent to the client (only changes are sent again); a new
    -- layout, entry or drag clears it
    if b.gen ~= CDM.iconGen or b.genEntry ~= e then
        b.gen, b.genEntry = CDM.iconGen, e
        -- nil = unknown: the next update sends everything again. (false here
        -- meant "known not grey", so an icon that was grey when the layout
        -- changed - every combat start - stayed grey until it went grey again)
        b.uDesat, b.uR, b.uG, b.uB, b.uAlpha, b.uRing, b.uSec, b.uTxtWhite = nil, nil, nil, nil, nil, nil, nil, nil
        b.text.huiTxt, b.count.huiTxt = nil, nil
    end
    local start, dur, enable, usable, noPower, inRange, known, count
    local hasTarget = UnitExists("target")
    if e.t == "item" then
        start, dur, enable = GetItemCooldown(e.id)
        usable = IsUsableItem(e.id)
        if hasTarget then inRange = IsItemInRange(e.id, "target") end
        local have = GetItemCount(e.id) or 0
        known = have > 0 or IsEquippedItem(e.id)
        if IsConsumableItem(e.id) then count = have end
    elseif e.presence then
        -- which presence (stance / form) you're in: its picture, in colour
        start, dur, enable, known, usable = 0, 0, 1, true, true
        local tex
        for i = 1, (GetNumShapeshiftForms and GetNumShapeshiftForms() or 0) do
            local t, _, active = GetShapeshiftFormInfo(i)
            if active then tex = t end
        end
        tex = tex or b.baseTex
        if tex and b.shownTex ~= tex then b.shownTex = tex; b.icon:SetTexture(tex); b.uDesat, b.uR = nil, nil end
    elseif e.tracker then
        -- a debuff to watch, not a spell to press (Ignite): no cooldown
        start, dur, enable, known, usable = 0, 0, 1, true, true
    else
        local name = b.spellName
        if name then start, dur, enable = GetSpellCooldown(name) end
        known = start ~= nil
        -- Raptor Strike / Maul: the cooldown tracked here when the game has none
        local oc = known and ownCD[name]
        if oc and not (enable == 1 and start > 0 and dur > 1.5) then
            local os = CDM.ownCDStart[name]
            if os and now - os < oc then start, dur, enable = os, oc, 1 end
        end
        if known then
            usable, noPower = IsUsableSpell(name)
            if hasTarget then inRange = IsSpellInRange(name, "target") end
            if name == OVERPOWER and CDM.opUntil then
                if GetTime() < CDM.opUntil then usable, noPower = true, nil else CDM.opUntil = nil end
            end
        end
    end
    local running = known and enable == 1 and start and start > 0 and dur and dur > 0
    local onCD = running and dur > 1.5
    if onCD and IsRuneCD(start, dur) then onCD = false end
    local gcd = running and not onCD

    -- your aura from this spell: on the target, on you, or on your pet
    local aura, aCount, aDur, aExp, aWhere, aTex
    if known and b.exactAura then
        aura, aCount, aDur, aExp, aWhere, aTex = FindAuraById(b.exactAura, e.noPet)
    elseif known and e.aura ~= "none" and b.trackNames and b.trackNames[1] then
        aura, aCount, aDur, aExp, aWhere, aTex = FindAura(b.trackNames, e.anyCaster, e.newest, e.noPet, e.byName)
    end
    -- a spell on cooldown shows its cooldown, not the debuff it left on the
    -- target (Aimed Shot, Mortal Strike, Black Arrow...). Buffs on you / your
    -- pet still win: Death Wish shows how long it lasts, then its cooldown.
    local showAura = aura and db.auras and not (onCD and aWhere == "target")

    local sS, sD, left
    if showAura then
        -- stacksOnly (Bone Shield): just the charges, no timer
        -- (noText: a self buff shown only by colour - Inner Fire, Vampiric Embrace)
        if aDur and aDur > 0 and aExp and not e.stacksOnly and not e.noText then sS, sD, left = aExp - aDur, aDur, aExp - now end
    elseif onCD then
        sS, sD, left = start, dur, start + dur - now
    elseif gcd and db.showGCD and not e.noGCD then
        sS, sD = start, dur
    end
    if sS then
        -- an aura just applied starts in full colour and darkens as it runs
        -- out; a cooldown starts dark and brightens as it comes back
        local rev = showAura and true or false
        if b.cdS ~= sS or b.cdD ~= sD or b.cdRev ~= rev then
            b.cdS, b.cdD, b.cdRev = sS, sD, rev
            if b.cd.SetReverse then b.cd:SetReverse(rev) end
            b.cd:SetCooldown(sS, sD)
            b.cd:Show()
        end
    elseif b.cdS then
        b.cdS, b.cdD = nil, nil
        b.cd:Hide()
    end
    -- death knight strikes waiting for runes: how long until you can
    -- (numbers only)
    if not left and not usable and not onCD and not showAura then
        local w = RuneWait(b.spellName, now)
        if w and w > 0 then left = w end
    end
    -- the text only changes once a second (whole seconds): no new string otherwise
    local sec = (left and left > 0) and ceil(left) or 0
    if left and left >= 3600 then sec = -ceil(left / 3600) end   -- hours
    if b.uSec ~= sec then
        b.uSec = sec
        SetTxt(b.text, sec ~= 0 and FmtTime(left) or "")
    end
    if not b.uTxtWhite then b.uTxtWhite = true; b.text:SetTextColor(1, 1, 1) end   -- white for cooldowns and aura timers alike

    -- stacks; "countAlways" shows 1 too (Slam! charges)
    local c = (aCount and (aCount > 1 or (e.countAlways and aCount > 0))) and aCount or count
    -- the count's place: bottom right; Ignite's damage centred at the bottom
    -- stacksOnly (Bone Shield): the charges in the middle, at the timer's size
    local pos = e.ignite and "center" or (e.stacksOnly and "middle") or "right"
    local want = (pos == "middle") and b.fs or b.cs
    if want and b.countFs ~= want then b.countFs = want; SetFont(b.count, want) end
    if b.countPos ~= pos then
        b.countPos = pos
        b.count:ClearAllPoints()
        if pos == "middle" then
            b.count:SetPoint("CENTER", b, "CENTER", 0, 0)
            b.count:SetJustifyH("CENTER")
        elseif pos == "center" then
            b.count:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
            b.count:SetJustifyH("CENTER")
        else
            b.count:SetPoint("BOTTOMRIGHT", -1, 2)
            b.count:SetJustifyH("RIGHT")
        end
    end
    if e.noText then
        SetTxt(b.count, "")
    elseif e.ignite then
        -- Ignite: how much its last tick did on this target (it grows as
        -- crits roll into it)
        local g = aura and UnitGUID("target")
        local v = g and CDM.igniteTick[g]
        local txt = ""
        if v then
            if v >= 1e6 then txt = format("%.1fM", v / 1e6)
            elseif v >= 1e4 then txt = format("%.0fK", v / 1e3)
            elseif v >= 1e3 then txt = format("%.1fK", v / 1e3)
            else txt = tostring(floor(v)) end
        end
        SetTxt(b.count, txt)
    else
        SetTxt(b.count, c and (c > 1 or e.t == "item" or e.countAlways) and c or "")
    end

    -- base look: only something you can press now is in colour. On cooldown
    -- or not usable (wrong stance, target too healthy for Kill Shot...): grey.
    -- Out of power: grey with a blue tint. Ready but out of range: red.
    -- (While its aura is up the icon stays in colour: it shows that timer.)
    local desat = not known
    local tr, tg, tb = 1, 1, 1
    local alpha = 1
    if not known then
        tr, tg, tb = 0.5, 0.5, 0.5
        alpha = CDM.editing and 0.6 or 0.4
    elseif showAura then
        -- aura timer: full colour
    elseif onCD then
        if db.desaturate then desat = true; tr, tg, tb = 0.75, 0.75, 0.75 end
    elseif not usable and not (noPower and e.ignorePower) then
        -- (ignorePower: in colour whenever it's off cooldown, even without
        -- the rage for it: Death Wish, Bloodthirst, Whirlwind)
        desat = true
        if noPower and db.powerColor then tr, tg, tb = 0.45, 0.55, 1 else tr, tg, tb = 0.6, 0.6, 0.6 end
    elseif db.rangeColor and inRange == 0 then
        tr, tg, tb = 0.95, 0.3, 0.3
    end
    local br, bg, bb = 0, 0, 0
    -- gold ring only for big cooldowns while their buff is up (Berserk,
    -- Death Wish, Rapid Fire, Icy Veins...): a buff on you / your pet from a
    -- spell with a cooldown of a minute or more. Debuffs on the target and
    -- short or no-cooldown buffs (Savage Roar, Tiger's Fury) get none.
    if showAura and db.auraBorder and aWhere ~= "target" and onCD and dur >= 60 and not e.stacksOnly and not e.noText then
        br, bg, bb = 1, 0.8, 0.2
    end

    -- built-in glows: procs and reactive abilities
    local glow = false
    if known and e.procs ~= false and db.procs and b.spellName then
        local list = procByName[b.spellName]
        if list then
            for _, p in ipairs(list) do
                if HasBuff(p.name, p.stacks) then glow = true break end
            end
        end
        if not glow and reactiveByName[b.spellName] and usable and not onCD then glow = true end
    end

    local glowOOC, glowCD = false, false
    -- your conditions, in order (later ones win)
    if e.rules and known then
        local st = ruleState
        st.known, st.usable, st.noPower, st.inRange = known, usable, noPower, inRange
        st.onCD, st.cdLeft = onCD, onCD and (start + dur - now) or 0
        st.ready = (usable and not onCD) and true or false
        st.aura, st.auraLeft = aura, (aExp and aDur and aDur > 0) and (aExp - now) or nil
        local rules, n, i = e.rules, #e.rules, 1
        while i <= n do
            local j = i
            local ok = Test(rules[i], st, b)
            while j < n and rules[j + 1].andPrev do
                j = j + 1
                ok = ok and Test(rules[j], st, b)
            end
            local r = rules[j]
            i = j + 1
            if ok then
                local a = r.a
                if a == "glow" then glow = true; if r.ooc then glowOOC = true end; if r.evenCD then glowCD = true end
                elseif a == "noglow" then glow = false; glowOOC = false; glowCD = false
                elseif a == "hide" then alpha = CDM.editing and 0.25 or 0
                elseif a == "dim" then alpha = min(alpha, 0.35)
                elseif a == "desat" then desat = true
                elseif a == "tint" and r.col then tr, tg, tb = r.col.r, r.col.g, r.col.b
                elseif a == "border" and r.col then br, bg, bb = r.col.r, r.col.g, r.col.b
                end
            end
        end
    end

    -- the picture: Heroic Strike shows Cleave's while Cleave is queued; an
    -- icon tracking the newest of several debuffs shows that debuff's
    if b.baseTex and ((b.spellName and b.spellName == HEROIC) or e.newest or e.byName) then
        local tex = b.baseTex
        if e.newest or e.byName then
            if aura and aTex then tex = aTex end
        elseif CLEAVE and UnitAffectingCombat("player") and NextSwingQueued() == CLEAVE then
            tex = GetSpellTexture(CLEAVE) or tex
        end
        if b.shownTex ~= tex then b.shownTex = tex; b.icon:SetTexture(tex); b.uDesat, b.uR = nil, nil end
    end
    -- out of range: red, whatever else the icon shows (a debuff timer, grey
    -- for "not applied"...), as long as it isn't on cooldown
    -- (not greyed then: the game can drop the tint on a desaturated picture)
    if db.rangeColor and inRange == 0 and known and not onCD then
        tr, tg, tb = 0.95, 0.3, 0.3
        desat = false
    end
    desat = desat and true or false
    if b.uDesat ~= desat then b.uDesat = desat; b.icon:SetDesaturated(desat and 1 or nil) end
    if b.uR ~= tr or b.uG ~= tg or b.uB ~= tb then b.uR, b.uG, b.uB = tr, tg, tb; b.icon:SetVertexColor(tr, tg, tb) end
    if b.uAlpha ~= alpha then
        b.uAlpha = alpha
        b:SetAlpha(alpha)
        b:SetBackdropBorderColor(0, 0, 0, 1)   -- the outline itself stays black
    end
    local ringKey = (br ~= 0 or bg ~= 0 or bb ~= 0) and (br * 65536 + bg * 256 + bb) or false
    if b.uRing ~= ringKey then
        b.uRing = ringKey
        if ringKey then
            for _, t in ipairs(b.ring.edges) do t:SetVertexColor(br, bg, bb, 1) end
            b.ring:Show()
        else
            b.ring:Hide()
        end
    end
    if alpha == 0 then glow = false end
    -- never draw the eye to something you can't press: no glow while this
    -- spell is on its own cooldown (the global cooldown doesn't count)
    -- (a missing-buff reminder can ask to glow anyway: Horn of Winter)
    if onCD and not glowCD then glow = false end
    -- glows only in combat (the settings preview shows them any time), unless
    -- the condition that lit it says "out of combat too" (Hunter's Mark)
    if glow and not glowOOC and not CDM.previewing and not UnitAffectingCombat("player") then glow = false end

    if glow then
        local kind = db.glowType or "button"
        -- atrGlowKind is only set once a glow really started: Glow.Start skips
        -- an icon that has no size yet (just laid out / still growing in), and
        -- marking it as glowing anyway left it dark for good. Try again then.
        if b.glowing ~= kind or b.atrGlowKind ~= kind or CDM.glowRestart then
            A.Glow.Start(b, kind, GlowColor(), 4)
            b.glowing = b.atrGlowKind
        end
    elseif b.glowing then
        A.Glow.Stop(b)
        b.glowing = nil
    end
end

local RAGE_COLOR = { r = 0.78, g = 0.25, b = 0.25 }
local RP_COLOR = { r = 0x40 / 255, g = 1, b = 1 }

-- runes, in the game's order: blood, frost, unholy (slots 1-2, 5-6, 3-4)
local RUNE_ORDER = { 1, 2, 5, 6, 3, 4 }
local RUNE_COLOR = {
    [1] = { 253 / 255, 0, 0 },              -- blood
    [2] = { 48 / 255, 180 / 255, 92 / 255 }, -- unholy
    [3] = { 67 / 255, 133 / 255, 1 },       -- frost
    [4] = { 243 / 255, 41 / 255, 241 / 255 }, -- death
}
local function RuneUpdate(now)
    if not (runes and runes:IsShown()) then return end
    local px = runes.px or PX()
    -- smooth: each fill eases toward where it should be (a spent rune drops,
    -- a changed rune slides) instead of jumping
    local el = runes.lastNow and (now - runes.lastNow) or 1
    runes.lastNow = now
    local ease = min(1, max(0, el) * 14)
    for k = 1, 6 do
        local slot = RUNE_ORDER[k]
        local seg = runes.segs[k]
        local start, dur, ready = 0, 0, true
        if GetRuneCooldown then start, dur, ready = GetRuneCooldown(slot) end
        local kind = (GetRuneType and GetRuneType(slot)) or (slot <= 2 and 1 or slot <= 4 and 2 or 3)
        local c = RUNE_COLOR[kind] or RUNE_COLOR[1]
        local frac = 1
        if not ready and start and dur and dur > 0 then
            frac = (now - start) / dur
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        end
        if CDM.previewing and not GetRuneCooldown then frac = 1 end
        -- fills from the bottom up as the rune comes back, the seconds left on it
        local target = (runes.innerH or 0) * frac
        local cur = seg.cur or target
        cur = cur + (target - cur) * ease
        if abs(target - cur) < px * 0.25 then cur = target end
        seg.cur = cur
        -- colour: eases too (a rune turning into a death rune fades to purple)
        local cc = seg.col or { c[1], c[2], c[3] }
        local moved = false
        for j = 1, 3 do
            local d = c[j] - cc[j]
            if d ~= 0 then
                if abs(d) < 0.002 then cc[j] = c[j] else cc[j] = cc[j] + d * ease end
                moved = true
            end
        end
        seg.col = cc
        if cur < px * 0.5 then
            if seg.uShown ~= false then seg.uShown = false; seg.fill:Hide() end
        else
            if moved or seg.uShown ~= true then seg.fill:SetVertexColor(cc[1], cc[2], cc[3], 1) end
            if seg.uH ~= cur then seg.uH = cur; seg.fill:SetHeight(cur) end
            if seg.uShown ~= true then seg.uShown = true; seg.fill:Show() end
        end
        if seg.text then
            local sec = (frac < 1 and start and dur) and ceil(start + dur - now) or false
            if seg.uSec ~= sec then
                seg.uSec = sec
                seg.text:SetText(sec and format("%d", sec) or "")
            end
        end
    end
end

-- combo points: yellow at 1, turning red by 5
local function ComboUpdate()
    if not (combo and combo:IsShown()) then return end
    local n = 0
    if UnitExists("target") then n = GetComboPoints("player", "target") or 0 end
    if CDM.previewing and n == 0 then n = 3 end   -- something to look at in the settings
    local t = n > 1 and (n - 1) / 4 or 0
    local r, g, b = 1, 0.85 - 0.7 * t, 0.1
    for k = 1, 5 do
        local seg = combo.segs[k]
        if k <= n then
            seg.fill:SetVertexColor(r, g, b, 1)
            seg.fill:Show()
        else
            seg.fill:Hide()
        end
    end
end

-- cat energy: its own colour, and black ticks at every Shred's worth
-- (42, 84; with Berserk up it costs half: 21, 42, 63, 84)
local CAT_ENERGY = { r = 0xb8 / 255, g = 0x57 / 255, b = 0x27 / 255 }   -- every energy bar (rogue, cat)
local SHRED_COST = 42
local function EnergyTicks(show, maxp, fixedCost, black)
    local ticks = power.ticks
    if not show or not maxp or maxp <= 0 then
        for _, t in ipairs(ticks) do t:Hide() end
        power.tickKey = nil
        return
    end
    local cost = fixedCost or SHRED_COST
    if not fixedCost and BERSERK and PlayerHasAuraId(50334) then cost = cost / 2 end
    local w = power.bar:GetWidth() or 0
    black = black and true or false
    if power.tickKey and power.tkCost == cost and power.tkMax == maxp and power.tkW == w and power.tkBlack == black then return end
    power.tickKey, power.tkCost, power.tkMax, power.tkW, power.tkBlack = true, cost, maxp, w, black
    local px = PX()
    local n = 0
    local k = 1
    while k * cost < maxp do
        n = n + 1
        local t = ticks[n]
        if not t then
            t = power.tickLayer:CreateTexture(nil, "OVERLAY")
            t:SetTexture(A.media.blank)
            ticks[n] = t
        end
        if black then t:SetVertexColor(0, 0, 0, 1) else t:SetVertexColor(1, 1, 1, 1) end
        -- 2px wide, centred on the exact energy
        local x = floor(w * (k * cost / maxp) / px + 0.5) * px
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", power.bar, "TOPLEFT", x - px, 0)
        t:SetPoint("BOTTOMLEFT", power.bar, "BOTTOMLEFT", x - px, 0)
        t:SetWidth(2 * px)
        t:Show()
        k = k + 1
    end
    for i = n + 1, #ticks do ticks[i]:Hide() end
end

local function PowerUpdate()
    if not power:IsShown() then return end
    local u = UnitHasVehicleUI("player") and "vehicle" or "player"
    local maxp, cur = UnitPowerMax(u) or 0, UnitPower(u) or 0
    local pType, pToken = UnitPowerType(u)
    local c = (pToken and PowerBarColor[pToken]) or PowerBarColor[pType] or PowerBarColor["MANA"]
    if (pToken == "MANA" or pType == 0) and PowerBarColor["RUNIC_POWER"] then c = PowerBarColor["RUNIC_POWER"] end
    -- the game's rage colour is pure red: a softer, darker red reads better
    if pToken == "RAGE" or pType == 1 then c = RAGE_COLOR end
    local energy = pToken == "ENERGY" or pType == 3
    local cat = myClass == "DRUID" and energy
    if energy then c = CAT_ENERGY end
    -- runic power: ff40ffff
    if myClass == "DEATHKNIGHT" and (pToken == "RUNIC_POWER" or pType == 6) then c = RP_COLOR end
    if power.uCol ~= c then
        power.uCol = c
        power.bar:SetStatusBarColor(c.r, c.g, c.b)
        power.bar.bg:SetVertexColor(0, 0, 0, 0)   -- no tinted background: the see-through black shows
    end
    local key = pToken or pType
    if power.uKey ~= key then power.uKey = key; power.uOwner = "cdm-" .. tostring(key) end
    A:SetBarSmooth(power.bar, cur, maxp > 0 and maxp or 1, power.uOwner)
    -- death knights: a tick for every Death Coil (40 runic power)
    local rp = myClass == "DEATHKNIGHT" and (pToken == "RUNIC_POWER" or pType == 6)
    -- (Frost: a tick for every Frost Strike instead, 32 runic power)
    if rp then EnergyTicks(true, maxp, (CDM:ViewSpec() == 2) and 32 or 40, true) else EnergyTicks(cat, maxp) end

    local fmt = A.db.cdm.powerFormat or "smart"
    local pct = fmt == "pct" or (fmt == "smart" and (pToken == "MANA" or pType == 0))
    if maxp <= 0 then SetTxt(power.text, "")
    elseif pct then SetTxt(power.text, floor(cur / maxp * 100 + 0.5) .. "%")
    else SetTxt(power.text, cur) end
end

function CDM:UpdateAll()
    local now = GetTime()
    if CDM.auraDirty ~= false or now - (CDM.auraScanT or 0) > 0.5 or self.previewing then
        CDM.auraDirty, CDM.auraScanT = false, now
        ScanMyAuras()
    end
    PowerUpdate()
    ComboUpdate()
    for r = 1, 2 do
        for _, b in ipairs(rows[r]) do
            if b:IsShown() then UpdateIcon(b, now) end
        end
    end
    self.glowRestart = nil
    local a = 1
    if not self.previewing and not UnitAffectingCombat("player") then a = A.db.cdm.oocAlpha or 1 end
    holder:SetAlpha(a)
end

------------------------------------------------------------------------
-- Visibility: DPS / tank specs only (always in the settings preview)
------------------------------------------------------------------------
local HEAL_TREES = { PALADIN = { [1] = true }, PRIEST = { [1] = true, [2] = true }, DRUID = { [3] = true }, SHAMAN = { [3] = true } }
function CDM:IsHealTree(tab) return HEAL_TREES[myClass] and HEAL_TREES[myClass][tab] or false end

-- the trees a layout can be made for (healing trees left out)
function CDM:EditableSpecs()
    local out = {}
    for tab = 1, 3 do
        if not self:IsHealTree(tab) then
            local name = GetTalentTabInfo(tab)
            tinsert(out, { tab, name or ("Tree " .. tab) })
        end
    end
    return out
end

function CDM:UpdateVisibility()
    if not holder then return end
    local db = A.db.cdm
    local spec = SpecTab()
    local role = spec == 0 and "DAMAGER" or (spec and A.MyRole and A:MyRole())
    if spec ~= self.spec and spec ~= nil then
        self.spec = spec
        self:Layout()
    end
    -- talents not readable yet (login / zoning): look again in a moment
    if spec == nil or role == nil then self.retry = 1 else self.retry = nil end
    self.mounted = IsMounted() and true or false
    if self.previewing then holder:Show() return end
    local show = db.enabled and self.spec ~= nil and role ~= nil and role ~= "HEALER"
    if show and db.hideVehicle and UnitHasVehicleUI("player") then show = false end
    if self.mounted then show = false end   -- never while mounted
    local was = holder:IsShown()
    if show then holder:Show() else holder:Hide() end
    if was ~= (show and true or false) then
        self:RefreshCastbar()
        dirty = true
    end
end

------------------------------------------------------------------------
-- Editing (in the settings preview)
------------------------------------------------------------------------
local function CursorEntry()
    local kind, a, b = GetCursorInfo()
    if kind == "spell" then
        if b == "pet" or b == BOOKTYPE_PET then return nil, "pet spells can't be tracked" end
        local name = GetSpellName(a, b)
        local link = GetSpellLink(a, b)
        local id = link and tonumber(link:match("spell:(%d+)"))
        if not name then return end
        return { t = "spell", id = id, n = name }
    elseif kind == "item" then
        return { t = "item", id = a }
    elseif kind then
        return nil, "only spells and items can be added"
    end
end

local function SameEntry(x, y)
    if x.t ~= y.t then return false end
    if x.t == "item" then return x.id == y.id end
    local nx = x.id and GetSpellInfo(x.id) or x.n
    local ny = y.id and GetSpellInfo(y.id) or y.n
    return nx == ny
end

function CDM:Find(e)
    local L = self:GetLayout()
    if not L then return end
    for r = 1, 2 do
        for i, x in ipairs(L[r]) do
            if SameEntry(x, e) then return r, i end
        end
    end
end

function CDM:Add(e, row, index)
    local L = self:GetLayout()
    if not L or not e then return end
    local r, i = self:Find(e)
    if r then
        self:Move(r, i, row, index or (#L[row] + 1))   -- already there: move it
        return
    end
    index = min(index or (#L[row] + 1), #L[row] + 1)
    tinsert(L[row], index, e)
    self:Changed()
end

function CDM:Remove(row, index)
    local L = self:GetLayout()
    if not L or not L[row][index] then return end
    tremove(L[row], index)
    self:Changed()
end

function CDM:Move(fromRow, fromIdx, toRow, toIdx)
    local L = self:GetLayout()
    if not L or not L[fromRow][fromIdx] then return end
    local e = tremove(L[fromRow], fromIdx)
    if fromRow == toRow and toIdx > fromIdx then toIdx = toIdx - 1 end
    toIdx = max(1, min(toIdx, #L[toRow] + 1))
    tinsert(L[toRow], toIdx, e)
    self:Changed()
end

function CDM:Changed()
    self:Layout()
    if self.picker and self.picker:IsVisible() then self:RefreshPicker() end
    if self.rulesWin and self.rulesWin:IsShown() then self:RefreshRules() end
end

function CDM:DropCursor(row, index)
    local e, err = CursorEntry()
    if not e then
        if err then A:Print("cooldown manager: " .. err .. ".") end
        return
    end
    ClearCursor()
    self:Add(e, row, index)
end

-- dragging icons around (our own drag: the cursor stays free)
local ghost
function CDM:BeginDrag(b)
    if not b.entry then return end
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        A:Size(ghost, 30)
        ghost.tex = ghost:CreateTexture(nil, "OVERLAY")
        ghost.tex:SetAllPoints()
        ghost.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ghost:SetAlpha(0.8)
        ghost:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
        end)
    end
    ghost.tex:SetTexture(b.icon:GetTexture())
    ghost:Show()
    self.held = { row = b.row, index = b.index }
    b:SetAlpha(0.3)
    GameTooltip:Hide()
end

function CDM:EndDrag()
    if not self.held then return end
    local h = self.held
    self.held = nil
    if ghost then ghost:Hide() end
    -- over an icon: before / after it (by cursor side); over "+": end of that row
    for r = 1, 2 do
        for i, b in ipairs(rows[r]) do
            if b:IsShown() and MouseIsOver(b) then
                local x = GetCursorPosition() / b:GetEffectiveScale()
                local cx = b:GetCenter()
                local to = (cx and x > cx) and (i + 1) or i
                if not (r == h.row and (to == h.index or to == h.index + 1)) then
                    self:Move(h.row, h.index, r, to)
                else
                    self:Layout()
                end
                return
            end
        end
        if plus[r]:IsShown() and MouseIsOver(plus[r]) then
            self:Move(h.row, h.index, r, 999)
            return
        end
    end
    -- dropped on the preview / spell list: nothing; anywhere else: removed
    local keep = MouseIsOver(holder) or (swingBox:IsShown() and MouseIsOver(swingBox))
        or (self.previewBox and self.previewBox:IsVisible() and MouseIsOver(self.previewBox))
        or (self.picker and self.picker:IsVisible() and MouseIsOver(self.picker))
    if keep then self:Layout() return end
    self:Remove(h.row, h.index)
end

------------------------------------------------------------------------
-- Pop-up lists (right-click menu, condition / action pickers)
------------------------------------------------------------------------
local menu, catcher
local function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
CDM.CloseMenu = CloseMenu

-- opts: { { text, fn, [header] }, ... }; anchor: a frame (below it) or nil (cursor)
function CDM:PopupList(opts, anchor, width)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(1)
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(20)
        A:SetTemplate(menu)
        menu.atrCustomBg = true
        menu:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
        menu:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
        menu.items = {}
    end
    for _, it in ipairs(menu.items) do it:Hide() end
    for i, o in ipairs(opts) do
        local it = menu.items[i]
        if not it then
            it = CreateFrame("Button", nil, menu)
            it:SetHeight(18)
            it.hl = it:CreateTexture(nil, "HIGHLIGHT")
            it.hl:SetAllPoints()
            it.hl:SetTexture(1, 1, 1, 0.08)
            it.text = A:Font(it, 11, "LEFT")
            it.text:SetPoint("LEFT", 8, 0)
            it.text:SetPoint("RIGHT", -8, 0)
            it:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -1 - (i - 1) * 18)
            it:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -1 - (i - 1) * 18)
            menu.items[i] = it
        end
        it.text:SetText(o[1])
        if o.header then
            it.text:SetTextColor(0.55, 0.55, 0.6)
            it:EnableMouse(false)
        else
            it.text:SetTextColor(0.9, 0.9, 0.92)
            it:EnableMouse(true)
        end
        it:SetScript("OnClick", function() CloseMenu(); if o[2] then o[2]() end end)
        it:Show()
    end
    menu:SetWidth(width or 270)
    menu:SetHeight(#opts * 18 + 2)
    menu:ClearAllPoints()
    if anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
    end
    menu:SetClampedToScreen(true)
    catcher:Show()
    menu:Show()
end

function CDM:OpenMenu(b)
    local e = b.entry
    if not e then return end
    local row, idx = b.row, b.index
    local opts = {
        { (b.spellName or (e.t == "item" and (GetItemInfo(e.id) or "Item")) or "?"), nil, header = true },
        { row == 1 and "Move to bottom row" or "Move to top row", function() CDM:Move(row, idx, row == 1 and 2 or 1, 999) end },
        { "Conditions and aura tracking...", function() CDM:OpenRules(e) end },
        { "Presets", nil, header = true },
    }
    for _, p in ipairs(CDM.PRESETS) do
        local on = CDM:HasRule(e, p[2])
        tinsert(opts, { (on and "|cff66ff66[x]|r " or "[  ] ") .. p[1], function() CDM:ToggleRule(e, p[2]) end })
    end
    tinsert(opts, { (e.procs == false and "[  ] " or "|cff66ff66[x]|r ") .. "Built-in proc glows", function()
        if e.procs == false then e.procs = nil else e.procs = false end
        CDM:Changed()
    end })
    tinsert(opts, { "|cffff6666Remove|r", function() CDM:Remove(row, idx) end })
    self:PopupList(opts, nil, 290)
end

------------------------------------------------------------------------
-- Conditions window: tracked aura, then "When ... Then ..." rows
------------------------------------------------------------------------
local function EditBox(parent, w)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetWidth(w); eb:SetHeight(18)
    eb:SetAutoFocus(false)
    A:SetFontPx(eb, A.media.font, 11, "")
    eb:SetTextColor(1, 1, 1)
    eb:SetTextInsets(4, 4, 0, 0)
    A:SetTemplate(eb)
    eb.atrCustomBg = true
    eb:SetBackdropColor(0.025, 0.025, 0.03, 1)
    eb:SetBackdropBorderColor(0.2, 0.2, 0.225, 1)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self) local c = A.accent self:SetBackdropBorderColor(c[1], c[2], c[3], 1) end)
    return eb
end

local function PickColor(cur, set)
    local r, g, b = cur and cur.r or 1, cur and cur.g or 0.2, cur and cur.b or 0.2
    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r, g, b }
    ColorPickerFrame.func = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); set(nr, ng, nb) end
    ColorPickerFrame.cancelFunc = function(prev) if prev then set(prev[1], prev[2], prev[3]) end end
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:Show()
end

local MAX_RULES = 10
function CDM:BuildRules()
    local w = CreateFrame("Frame", "HUICDMRules", UIParent)
    w:SetFrameStrata("FULLSCREEN")
    w:SetToplevel(true)
    w:SetWidth(560); w:SetHeight(120)
    w:SetPoint("CENTER", 0, 80)
    A:SetTemplate(w)
    w.atrCustomBg = true
    w:SetBackdropColor(0.05, 0.05, 0.058, 0.98)
    w:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:SetClampedToScreen(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    tinsert(UISpecialFrames, "HUICDMRules")
    w:Hide()

    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetWidth(20); w.icon:SetHeight(20)
    w.icon:SetPoint("TOPLEFT", 10, -9)
    w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    w.title = A:Font(w, 12, "LEFT")
    w.title:SetPoint("LEFT", w.icon, "RIGHT", 8, 0)
    w.title:SetTextColor(1, 1, 1)
    w.close = A:CreateButton(w, "Close", 70, 18, function() w:Hide() end)
    w.close:SetPoint("TOPRIGHT", -8, -10)

    -- tracked aura
    local t = A:Font(w, 10, "LEFT")
    t:SetPoint("TOPLEFT", 10, -40)
    t:SetText("Tracked aura")
    t:SetTextColor(0.75, 0.75, 0.78)
    w.aura = EditBox(w, 200)
    w.aura:SetPoint("LEFT", t, "LEFT", 90, 0)
    w.aura:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.2, 0.2, 0.225, 1)
        local e = CDM.ruleEntry
        if not e then return end
        local v = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if v == "" then e.aura = nil else e.aura = v end
        CDM:Changed()
    end)
    -- whose aura counts: only yours, or anyone's (Hunter's Mark, Mangle...)
    w.any = A:CreateButton(w, "", 92, 18, function()
        local e = CDM.ruleEntry
        if not e then return end
        e.anyCaster = not e.anyCaster or nil
        CDM:Changed()
    end)
    w.any:SetPoint("LEFT", w.aura, "RIGHT", 6, 0)
    w.any:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Whose debuff on the target counts", 1, 1, 1)
        GameTooltip:AddLine("Mine only, or anyone's (one Hunter's Mark, Mangle or Faerie Fire is enough for the raid).", 0.75, 0.75, 0.78, true)
        GameTooltip:Show()
    end)
    w.any:HookScript("OnLeave", function() GameTooltip:Hide() end)
    w.auraHint = A:Font(w, 10, "LEFT")
    w.auraHint:SetPoint("LEFT", w.any, "RIGHT", 8, 0)
    w.auraHint:SetPoint("RIGHT", w, "RIGHT", -10, 0)
    w.auraHint:SetTextColor(0.5, 0.5, 0.54)

    local h = A:Font(w, 10, "LEFT")
    h:SetPoint("TOPLEFT", 10, -64)
    h:SetText("When ...                                                              Then ...")
    h:SetTextColor(0.5, 0.5, 0.54)

    w.rows = {}
    for i = 1, MAX_RULES do
        local r = CreateFrame("Frame", nil, w)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 10, -80 - (i - 1) * 22)
        r:SetPoint("RIGHT", w, "RIGHT", -10, 0)
        r.join = A:CreateButton(r, "and", 30, 18, function()
            local rule = CDM.ruleEntry and CDM.ruleEntry.rules and CDM.ruleEntry.rules[i]
            if not rule or i == 1 then return end
            rule.andPrev = not rule.andPrev or nil
            CDM:Changed()
        end)
        r.join:SetPoint("LEFT", 0, 0)
        r.join:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Join the row above", 1, 1, 1)
            GameTooltip:AddLine("Lit: this row and the one above must both be true; the last row of the group says what happens.", 0.75, 0.75, 0.78, true)
            GameTooltip:Show()
        end)
        r.join:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r.cond = A:CreateButton(r, "", 206, 18, function(self) CDM:PickCond(i, self) end)
        r.cond:SetPoint("LEFT", r.join, "RIGHT", 4, 0)
        r.cond.text:ClearAllPoints()
        r.cond.text:SetPoint("LEFT", 6, 0)
        r.cond.text:SetPoint("RIGHT", -6, 0)
        r.cond.text:SetJustifyH("LEFT")
        r.text = EditBox(r, 100)
        r.text:SetPoint("LEFT", r.cond, "RIGHT", 4, 0)
        r.num = EditBox(r, 40)
        r.num:SetJustifyH("CENTER")
        r.act = A:CreateButton(r, "", 100, 18, function(self) CDM:PickAction(i, self) end)
        r.swatch = CreateFrame("Button", nil, r)
        r.swatch:SetWidth(18); r.swatch:SetHeight(18)
        A:SetTemplate(r.swatch)
        r.swatch.atrCustomBg = true
        r.swatch:SetScript("OnClick", function()
            local rule = CDM.ruleEntry and CDM.ruleEntry.rules and CDM.ruleEntry.rules[i]
            if not rule then return end
            PickColor(rule.col, function(cr, cg, cb) rule.col = { r = cr, g = cg, b = cb }; CDM:RefreshRules() end)
        end)
        -- glow rules: also out of combat?
        r.ooc = A:CreateButton(r, "", 30, 18, function()
            local rule = CDM.ruleEntry and CDM.ruleEntry.rules and CDM.ruleEntry.rules[i]
            if not rule then return end
            rule.ooc = not rule.ooc or nil
            CDM:Changed()
        end)
        r.ooc:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Glow out of combat too", 1, 1, 1)
            GameTooltip:AddLine("Glows normally only show in combat. Lit: this one shows any time (\"put Hunter's Mark up\").", 0.75, 0.75, 0.78, true)
            GameTooltip:Show()
        end)
        r.ooc:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r.del = A:CreateButton(r, "x", 18, 18, function()
            local e = CDM.ruleEntry
            if e and e.rules then tremove(e.rules, i); if #e.rules == 0 then e.rules = nil end end
            CDM:Changed()
        end)
        r.del:SetPoint("RIGHT", 0, 0)
        local function commit()
            local e = CDM.ruleEntry
            local rule = e and e.rules and e.rules[i]
            if not rule then return end
            local tv = (r.text:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if tv == "" then rule.aura = nil
            elseif type(rule.aura) == "number" and ResolveName(rule.aura) == tv then -- unchanged id
            else rule.aura = tv end
            rule.v = tonumber(r.num:GetText())
        end
        for _, eb in ipairs({ r.text, r.num }) do
            eb:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.2, 0.2, 0.225, 1); commit() end)
        end
        r:Hide()
        w.rows[i] = r
    end
    w.add = A:CreateButton(w, "+ Add condition", 120, 18, function()
        local e = CDM.ruleEntry
        if not e then return end
        e.rules = e.rules or {}
        if #e.rules >= MAX_RULES then return end
        tinsert(e.rules, { c = "ready", a = "glow" })
        CDM:Changed()
    end)
    w.help = A:Font(w, 10, "LEFT")
    w.help:SetTextColor(0.5, 0.5, 0.54)
    w.help:SetText("Top to bottom, lower rows win. \"and\" joins a row to the one above. Names: empty = this spell / its aura; a spell id works too.")
    self.rulesWin = w
end

function CDM:OpenRules(e)
    if not self.rulesWin then self:BuildRules() end
    self.ruleEntry = e
    self:RefreshRules()
    self.rulesWin:Show()
    self.rulesWin:Raise()
end

function CDM:RefreshRules()
    local w, e = self.rulesWin, self.ruleEntry
    if not (w and e) then return end
    local name, icon
    if e.t == "item" then
        name, icon = GetItemInfo(e.id), GetItemIcon(e.id)
    else
        name, _, icon = GetSpellInfo(e.id or e.n)
        name = name or e.n
    end
    w.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    w.title:SetText((name or "?") .. "  |cff888888conditions|r")
    if not w.aura:HasFocus() then
        local a = e.aura
        if type(a) == "table" then a = table.concat(CDM.NameList(a), ";")
        elseif type(a) == "number" then a = CDM.ResolveName(a) end
        w.aura:SetText((a and a ~= "") and a or "")
    end
    w.any.text:SetText(e.anyCaster and "Anyone's" or "Mine only")
    if e.anyCaster then w.any.text:SetTextColor(1, 1, 1) else w.any.text:SetTextColor(0.6, 0.6, 0.64) end
    local auto = e.t == "item" and GetItemSpell(e.id) or (name and (auraByName[name] or name))
    w.auraHint:SetText("empty = " .. (auto or "-") .. ",  \"none\" = no aura timer")
    local rules = e.rules or {}
    for i, r in ipairs(w.rows) do
        local rule = rules[i]
        if rule then
            local ci = condInfo[rule.c] or CDM.CONDS[1]
            local ai = actInfo[rule.a] or CDM.ACTIONS[1]
            r.cond.text:SetText(ci[2])
            local x = r.cond
            if ci.text then
                r.text:Show()
                if not r.text:HasFocus() then r.text:SetText(rule.aura and ResolveName(rule.aura) or "") end
                x = r.text
            else
                r.text:Hide()
            end
            if ci.num then
                r.num:ClearAllPoints()
                r.num:SetPoint("LEFT", x, "RIGHT", 4, 0)
                r.num:Show()
                if not r.num:HasFocus() then r.num:SetText(rule.v and tostring(rule.v) or "") end
                x = r.num
            else
                r.num:Hide()
            end
            -- "and" toggle: lit when joined to the row above
            if i == 1 then r.join:Hide() else
                r.join:Show()
                local c = A.accent
                if rule.andPrev then
                    r.join.text:SetTextColor(1, 1, 1)
                    r.join:SetBackdropColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
                else
                    r.join.text:SetTextColor(0.45, 0.45, 0.5)
                    r.join:SetBackdropColor(0, 0, 0, 1)
                end
            end
            -- only the last row of a joined group has an action
            local joinedNext = rules[i + 1] and rules[i + 1].andPrev
            r.act:ClearAllPoints()
            r.act:SetPoint("LEFT", r.cond, "LEFT", 206 + 4 + 100 + 4 + 40 + 8, 0)
            r.act.text:SetText(ai[2])
            if joinedNext then r.act:Hide() else r.act:Show() end
            -- glow: "ooc" switch where a colour swatch would be
            if rule.a == "glow" and not joinedNext then
                r.ooc:ClearAllPoints()
                r.ooc:SetPoint("LEFT", r.act, "RIGHT", 4, 0)
                r.ooc.text:SetText("ooc")
                if rule.ooc then r.ooc.text:SetTextColor(1, 1, 1) else r.ooc.text:SetTextColor(0.4, 0.4, 0.45) end
                r.ooc:Show()
            else
                r.ooc:Hide()
            end
            if ai.color and not joinedNext then
                local c = rule.col or { r = 1, g = 0.2, b = 0.2 }
                rule.col = rule.col or c
                r.swatch:SetBackdropColor(c.r, c.g, c.b, 1)
                r.swatch:ClearAllPoints()
                r.swatch:SetPoint("LEFT", r.act, "RIGHT", 4, 0)
                r.swatch:Show()
            else
                r.swatch:Hide()
            end
            r:Show()
        else
            r:Hide()
        end
    end
    local n = #rules
    w.add:ClearAllPoints()
    w.add:SetPoint("TOPLEFT", 10, -80 - n * 22 - 4)
    if n >= MAX_RULES then w.add:Hide() else w.add:Show() end
    w.help:ClearAllPoints()
    w.help:SetPoint("LEFT", w.add, "RIGHT", 10, 0)
    w.help:SetPoint("RIGHT", w, "RIGHT", -10, 0)
    w:SetHeight(80 + n * 22 + 34)
end

function CDM:PickCond(i, owner)
    local e = self.ruleEntry
    local rule = e and e.rules and e.rules[i]
    if not rule then return end
    local opts = {}
    for _, c in ipairs(CDM.CONDS) do
        tinsert(opts, { (c[1] == rule.c and "|cff66ff66" or "") .. c[2], function() rule.c = c[1]; CDM:Changed() end })
    end
    self:PopupList(opts, owner, 280)
end

function CDM:PickAction(i, owner)
    local e = self.ruleEntry
    local rule = e and e.rules and e.rules[i]
    if not rule then return end
    local opts = {}
    for _, a in ipairs(CDM.ACTIONS) do
        tinsert(opts, { (a[1] == rule.a and "|cff66ff66" or "") .. a[2], function() rule.a = a[1]; CDM:Changed() end })
    end
    self:PopupList(opts, owner, 140)
end

------------------------------------------------------------------------
-- Spell list (in the settings page): your spellbook, cooldowns first
------------------------------------------------------------------------
local scan
local cdPatterns
local function CooldownText(i)
    if not scan then
        scan = CreateFrame("GameTooltip", "HUICDMScanTip", nil, "GameTooltipTemplate")
        cdPatterns = {}
        for _, g in ipairs({ "SPELL_RECAST_TIME_MIN", "SPELL_RECAST_TIME_SEC", "SPELL_RECAST_TIME_HOURS" }) do
            local s = _G[g]
            if type(s) == "string" then
                s = s:gsub("%%%.3g", "\001"):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("\001", "[%%d%%.]+")
                tinsert(cdPatterns, "^" .. s .. "$")
            end
        end
    end
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetSpell(i, BOOKTYPE_SPELL)
    for l = 1, scan:NumLines() do
        for _, side in ipairs({ "Right", "Left" }) do
            local fs = _G["HUICDMScanTipText" .. side .. l]
            local t = fs and fs:GetText()
            if t then
                for _, p in ipairs(cdPatterns) do
                    if t:match(p) then return t end
                end
                if #cdPatterns == 0 and t:lower():find("cooldown") then return t end
            end
        end
    end
end

local function SpellList()
    local out, seen = {}, {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, num = GetSpellTabInfo(tab)
        for i = offset + 1, offset + num do
            local name = GetSpellName(i, BOOKTYPE_SPELL)
            if name and not IsPassiveSpell(i, BOOKTYPE_SPELL) then
                local cd = CooldownText(i)
                if tab > 1 or cd then
                    local link = GetSpellLink(i, BOOKTYPE_SPELL)
                    local id = link and tonumber(link:match("spell:(%d+)"))
                    local e = { t = "spell", id = id, n = name, cd = cd, idx = i, icon = GetSpellTexture(i, BOOKTYPE_SPELL) }
                    if seen[name] then out[seen[name]] = e else tinsert(out, e); seen[name] = #out end
                end
            end
        end
    end
    for _, slot in ipairs({ 13, 14 }) do   -- equipped trinkets with a use effect
        local link = GetInventoryItemLink("player", slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and GetItemSpell(id) then
            tinsert(out, { t = "item", id = id, cd = "Trinket", icon = GetItemIcon(id) })
        end
    end
    local a, b = {}, {}   -- spells with a cooldown first
    for _, e in ipairs(out) do tinsert(e.cd and a or b, e) end
    for _, e in ipairs(b) do tinsert(a, e) end
    return a
end

local PROWS, PSIZE = 4, 28
-- the spell list widget for the settings page (width in its units)
function CDM:CreatePicker(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    local cols = max(6, floor((width + 2) / (PSIZE + 2)))
    f:SetHeight(PROWS * (PSIZE + 2) + 26)
    f.buttons = {}
    for i = 1, cols * PROWS do
        local b = CreateFrame("Button", nil, f)
        A:Size(b, PSIZE)
        A:SetTemplate(b)
        b.atrCustomBg = true
        b:SetBackdropColor(0, 0, 0, 1)
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", c * (PSIZE + 2), -r * (PSIZE + 2))
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.mark = b:CreateTexture(nil, "OVERLAY")
        b.mark:SetTexture(A.media.blank)
        b.mark:SetVertexColor(0.3, 1, 0.4)
        b.mark:SetPoint("BOTTOMRIGHT", -1, 1)
        b.mark:SetWidth(6); b.mark:SetHeight(6)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(self)
            local e = self.e
            if not e then return end
            local r, idx = CDM:Find(e)
            if r then CDM:Remove(r, idx) return end
            CDM:Add({ t = e.t, id = e.id, n = e.n }, IsShiftKeyDown() and 2 or 1)
        end)
        b:SetScript("OnDragStart", function(self)
            local e = self.e
            if not e then return end
            if e.t == "item" then PickupItem(e.id) elseif e.idx then PickupSpell(e.idx, BOOKTYPE_SPELL) end   -- 3.3.5: by spellbook slot
        end)
        b:SetScript("OnEnter", function(self)
            local e = self.e
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e.t == "item" then GameTooltip:SetHyperlink("item:" .. e.id)
            elseif e.id then GameTooltip:SetHyperlink("spell:" .. e.id)
            else GameTooltip:AddLine(e.n, 1, 1, 1) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(CDM:Find(e) and "Click to remove" or "Click: top row   Shift-click: bottom row", 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.buttons[i] = b
    end
    f.prev = A:CreateButton(f, "<", 24, 18, function() CDM.page = max(1, (CDM.page or 1) - 1); CDM:RefreshPicker() end)
    f.prev:SetPoint("BOTTOMLEFT", 0, 0)
    f.next = A:CreateButton(f, ">", 24, 18, function() CDM.page = (CDM.page or 1) + 1; CDM:RefreshPicker() end)
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.pageText = A:Font(f, 10, "LEFT")
    f.pageText:SetPoint("LEFT", f.next, "RIGHT", 8, 0)
    f.pageText:SetTextColor(0.6, 0.6, 0.64)
    f:SetScript("OnShow", function(self) CDM.picker = self; CDM:FillPicker() end)
    self.picker = f
    return f
end

function CDM:FillPicker()
    self.spellList = SpellList()
    self:RefreshPicker()
end

function CDM:RefreshPicker()
    local p = self.picker
    if not p then return end
    local list = self.spellList or {}
    local per = #p.buttons
    local pages = max(1, ceil(#list / per))
    self.page = max(1, min(self.page or 1, pages))
    for i, b in ipairs(p.buttons) do
        local e = list[(self.page - 1) * per + i]
        b.e = e
        if e then
            b.icon:SetTexture(e.icon or (e.t == "item" and GetItemIcon(e.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local added = self:Find(e) ~= nil
            b.icon:SetDesaturated(added and 1 or nil)
            b.icon:SetAlpha(added and 0.45 or 1)
            if added then b.mark:Show() else b.mark:Hide() end
            b:SetBackdropBorderColor(e.cd and 0 or 0.18, e.cd and 0 or 0.18, e.cd and 0 or 0.2, 1)
            b:Show()
        else
            b:Hide()
        end
    end
    p.pageText:SetText(format("Page %d / %d    (cooldowns first, then the rest of your spellbook)", self.page, pages))
end

------------------------------------------------------------------------
-- Live preview in the settings page: the real module, moved into a box
------------------------------------------------------------------------
-- frame levels (and strata) of a frame and everything in it, keeping the
-- children's order: the module drawn above the settings window, or back
local function Relevel(f, level, strata)
    local old = f:GetFrameLevel()
    if strata then f:SetFrameStrata(strata) end
    f:SetFrameLevel(level)
    for _, c in ipairs({ f:GetChildren() }) do
        local rel = c.atrRel or max(1, c:GetFrameLevel() - old)
        c.atrRel = rel
        Relevel(c, level + rel, strata)
    end
end

local PREVIEW_BG = "Interface\\AddOns\\HUI\\media\\cdm_preview"
local PREVIEW_BG_ASPECT = 535 / 319   -- the picture's real shape (the file is stretched to 512x256)

-- show the middle of the picture at its real shape, filling the box
local function CropBackground(box)
    local w, h = box:GetWidth(), box:GetHeight()
    if not (w and h) or w <= 0 or h <= 0 then return end
    local r = w / h
    local l, rr, t, b = 0, 1, 0, 1
    if r > PREVIEW_BG_ASPECT then
        local v = PREVIEW_BG_ASPECT / r          -- box wider: use a band of the height
        t, b = (1 - v) / 2, (1 + v) / 2
    else
        local u = r / PREVIEW_BG_ASPECT          -- box taller: use a band of the width
        l, rr = (1 - u) / 2, (1 + u) / 2
    end
    box.bg:SetTexCoord(l, rr, t, b)
end

-- the box for the settings page (height in its units)
function CDM:CreatePreviewBox(parent, height)
    local box = CreateFrame("Frame", nil, parent)
    box:SetHeight(height)
    -- a scene from the game behind the preview, darkened a little so the
    -- icons stand out; cropped to fill the box (never stretched)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetTexture(PREVIEW_BG)
    box.shade = box:CreateTexture(nil, "BORDER")
    box.shade:SetAllPoints()
    box.shade:SetTexture(0, 0, 0, 0.3)
    -- a stand-in cast bar, so the stack reads like it does in game
    box.cast = CreateFrame("Frame", nil, box)
    A:SetTemplate(box.cast)
    box.cast.bar = A:StatusBar(box.cast)
    box.cast.bar:SetPoint("TOPLEFT", 1, -1)
    box.cast.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    local c = A.colors and A.colors.castbar or { 0.3, 0.55, 0.95 }
    box.cast.bar:SetStatusBarColor(c[1], c[2], c[3])
    box.cast.bar:SetValue(0.6)
    box.cast.text = NewFS(box.cast.bar, 11)
    box.cast.text:SetPoint("LEFT", 4, 0)
    box.cast.text:SetText("Cast bar")
    box:SetScript("OnShow", function(self) CDM:StartPreview(self) end)
    box:SetScript("OnHide", function() CDM:StopPreview() end)
    self.previewBox = box
    return box
end

function CDM:StartPreview(box)
    if not holder then return end
    self.previewBox = box
    if self.previewing then self:Layout() return end
    self.previewing, self.editing = true, true
    self:InitEditSpec()
    holder:SetParent(box)
    Relevel(holder, box:GetFrameLevel() + 2, box:GetFrameStrata())
    holder:Show()
    self:RefreshCastbar()   -- the real cast bar goes back to its own spot
    self:Layout()
end

function CDM:FitPreview()
    local box = self.previewBox
    if not box then return end
    CropBackground(box)
    local db = A.db.cdm
    -- natural size at the unit frame scale, then shrunk to fit the box
    local hs = box:GetEffectiveScale()
    holder:SetScale(A.db.scale or 1)
    local w = holder:GetWidth()
    local sp = max(0, db.spacing or 1)
    local top = (swingBox:IsShown() and (swingBox:GetHeight() + (sp == 0 and -PX() or sp * PX())) or 0)
    local castH = 18
    local total = holder:GetHeight() + top + castH + 4
    local s = A.db.scale or 1
    local fit = min(1, (box:GetHeight() - 16) / (total * s), (box:GetWidth() - 16) / (w * s))
    if fit < 1 then holder:SetScale(s * fit) end
    holder:ClearAllPoints()
    local k = holder:GetEffectiveScale() / hs   -- holder units -> box units
    local stackH = (holder:GetHeight() + top) * k + castH * k + 2
    local y = -(box:GetHeight() - stackH) / 2 - (castH * k + 2 + top * k)
    holder:SetPoint("TOP", box, "TOP", 0, y / k)   -- offsets are in the holder's own units
    self:SnapToPixels()
    Relevel(holder, box:GetFrameLevel() + 2, box:GetFrameStrata())
    -- stand-in cast bar on top, same width
    box.cast:ClearAllPoints()
    box.cast:SetPoint("BOTTOMLEFT", self:TopFrame(), "TOPLEFT", 0, 1)
    box.cast:SetPoint("BOTTOMRIGHT", self:TopFrame(), "TOPRIGHT", 0, 1)
    box.cast:SetHeight(castH * k)
    box.cast:SetFrameLevel(box:GetFrameLevel() + 2)
end

function CDM:StopPreview()
    if not self.previewing then return end
    self.previewing, self.editing = false, false
    CloseMenu()
    if self.rulesWin then self.rulesWin:Hide() end
    if self.held then self.held = nil; if ghost then ghost:Hide() end end
    holder:SetParent(UIParent)
    holder:SetScale(A.db.scale or 1)
    Relevel(holder, 1, "LOW")
    self:Layout()
    self:UpdateVisibility()
end

-- the spec shown in the settings preview: yours, unless it's a healing tree
function CDM:InitEditSpec()
    if self.editSpec and not self:IsHealTree(self.editSpec) then return self.editSpec end
    self.editSpec = (self.spec and self.spec > 0 and not self:IsHealTree(self.spec)) and self.spec or nil
    if not self.editSpec then
        local list = self:EditableSpecs()
        self.editSpec = list[1] and list[1][1]
    end
    return self.editSpec
end

function CDM:SetEditSpec(tab)
    self.editSpec = tab
    self:Layout()
    if self.picker and self.picker:IsVisible() then self:RefreshPicker() end
end

-- /hui cdm status: why it is (not) showing
function A:CDMStatus()
    local h = CDM.holder
    local spec = SpecTab()
    local role = spec == 0 and "DAMAGER" or (spec and A.MyRole and A:MyRole())
    local L = CDM.spec and CDM:GetLayout(CDM.spec)
    local l, t = h and h:GetLeft(), h and h:GetTop()
    A:Print(format("cdm: enabled=%s spec=%s/%s role=%s mounted=%s vehicle=%s preview=%s",
        tostring(A.db.cdm.enabled), tostring(spec), tostring(CDM.spec), tostring(role),
        tostring(IsMounted() and true or false), tostring(UnitHasVehicleUI("player") and true or false), tostring(CDM.previewing)))
    A:Print(format("cdm: shown=%s visible=%s alpha=%.2f size=%.0fx%.0f at %s,%s  parent=%s strata=%s  icons=%d/%d  defaults=%s",
        tostring(h and h:IsShown()), tostring(h and h:IsVisible()), h and h:GetEffectiveAlpha() or 0,
        h and h:GetWidth() or 0, h and h:GetHeight() or 0, tostring(l and floor(l)), tostring(t and floor(t)),
        tostring(h and h:GetParent() and (h:GetParent():GetName() or "?")), tostring(h and h:GetFrameStrata()),
        L and #L[1] or -1, L and #L[2] or -1, tostring(A.CDMClassDefaults ~= nil)))
    A:Print("cdm: next-swing queue: " .. CDM:QueuedReport())
    local kinds = {}
    for k, f in pairs(swingBars) do if f:IsShown() then tinsert(kinds, k) end end
    local mh, oh = UnitAttackSpeed("player")
    A:Print(format("cdm: swing bars shown=%s  melee swings seen=%d  filled in=%d  auto attack=%s  in melee range=%s  mh start=%s dur=%s  speed=%s/%s  guid ok=%s",
        table.concat(kinds, ","), CDM.swingSeen or 0, CDM.swingPredicted or 0, tostring(CDM.autoMelee),
        tostring(InMeleeRange()), tostring(SW.mh.start), tostring(SW.mh.dur),
        tostring(mh), tostring(oh), tostring(playerGUID == UnitGUID("player"))))
    -- every icon: what it tracks, and whether that's up right now
    ScanMyAuras()
    for r = 1, 2 do
        local parts = {}
        for _, b in ipairs(rows[r]) do
            local e = b.entry
            if e then
                local names = b.trackNames and table.concat(b.trackNames, "/") or "-"
                local au, _, _, x, where = nil
                if e.aura ~= "none" and b.trackNames and b.trackNames[1] then
                    au, _, _, x, where = FindAura(b.trackNames, e.anyCaster, e.newest, e.noPet, e.byName)
                end
                local g = b.atrGlowKind and ("glow " .. b.atrGlowKind
                    .. ((b._ProcGlow and not b._ProcGlow:IsVisible() or b._ButtonGlow and not b._ButtonGlow:IsVisible()) and " hidden" or ""))
                    or (b.glowing and "glow failed") or ""
                tinsert(parts, format("%s[%s:%s%s%s]", tostring(b.spellName), names, au and (where or "?") or "no",
                    g ~= "" and " " or "", g))
            end
        end
        A:Print("cdm row " .. r .. ": " .. table.concat(parts, " "))
    end
    if myClass == "WARRIOR" then
        A:Print(format("cdm: dodges seen=%d  overpower window=%s  usable now=%s",
            CDM.dodges or 0, CDM.opUntil and format("%.1fs", CDM.opUntil - GetTime()) or "closed",
            tostring((IsUsableSpell(GetSpellInfo(7384) or "Overpower")))))
    end
    A:Print(format("cdm: combat log events=%d (yours %d, restarts %d)  last: %s",
        CDM.clAny or 0, CDM.clSeen or 0, CDM.clFixes or 0, tostring(CDM.clLast)))
    A:Print(format("pixel grid: gxResolution=%s window=%s ui=%.1fx%.1f  screen height used=%s  (set it by hand in General > Pixel grid if it is not your real game height)",
        tostring(GetCVar("gxResolution")), tostring(GetCVar("gxWindow")), GetScreenWidth(), GetScreenHeight(), tostring(A.screenH)))
end

-- /hui cdm: straight to the settings page
function A:CDMEdit()
    if A.OpenConfigPage then A:OpenConfigPage("Cooldown Manager") end
end

------------------------------------------------------------------------
-- Export: this character's layouts as class defaults (CDMDefaults.lua)
------------------------------------------------------------------------
local function SerVal(v)
    local t = type(v)
    if t == "string" then return format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then
        local parts, keys = {}, {}
        for k in pairs(v) do tinsert(keys, k) end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local key = type(k) == "number" and ("[" .. k .. "]") or k
            tinsert(parts, key .. " = " .. SerVal(v[k]))
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    return "nil"
end

local function SerEntry(e)
    local extra = {}
    for k, v in pairs(e) do
        if k ~= "t" and k ~= "id" and k ~= "n" then extra[k] = v end
    end
    if e.t == "item" then
        extra.t, extra.id = "item", e.id
        return SerVal(extra)
    end
    local id = e.id or e.n
    if not next(extra) then return type(id) == "number" and tostring(id) or SerVal({ id = id }) end
    extra.id = id
    return SerVal(extra)
end

function CDM:ExportClass()
    local c = A.db.cdm.layouts[CharKey()] or {}
    local out = { "-- HUI cooldown manager: " .. myClass .. " (" .. CharKey() .. ")", "-- paste into CDMDefaults.lua", myClass .. " = {" }
    for tab = 1, 3 do
        local L = c[tostring(tab)]
        if L and not self:IsHealTree(tab) then
            local name = GetTalentTabInfo(tab) or ("Tree " .. tab)
            tinsert(out, "    [" .. tab .. "] = {   -- " .. name)
            for r = 1, 2 do
                local items = {}
                for _, e in ipairs(L[r] or {}) do tinsert(items, SerEntry(e)) end
                tinsert(out, "        { " .. table.concat(items, ", ") .. " },   -- " .. (r == 1 and "top row" or "bottom row"))
            end
            tinsert(out, "    },")
        end
    end
    tinsert(out, "},")
    return table.concat(out, "\n")
end

function A:CDMExportClass()
    if A.ShowCopy then A:ShowCopy("Cooldown manager: " .. myClass .. " layouts  (Ctrl+A, Ctrl+C)", CDM:ExportClass()) end
end

------------------------------------------------------------------------
-- Build + events
------------------------------------------------------------------------
A.defaultPositions.CDM = { "TOP", "CENTER", 0, -151 }

function A:RefreshCDM()
    if not holder then return end
    CDM.glowRestart = true
    CDM:UpdateVisibility()
    CDM:Layout()
end

function A:BuildCDM()
    -- fresh settings (new install / version reset): the one-time fixes below
    -- are for older saved settings, mark them done
    local fresh = type(self.db.cdm) ~= "table"
    self.db.cdm = A.CopyDefaults(defaults, self.db.cdm)
    if fresh then
        for _, k in ipairs({ "v2", "v4", "v5", "v6" }) do self.db.cdm[k] = true end
    end
    if not self.db.cdm.v2 then self.db.cdm.v2 = true end
    if not self.db.cdm.v4 then self.db.cdm.v4 = true; self.db.cdm.spacing = 1 end
    if not self.db.cdm.v5 then self.db.cdm.v5 = true; self.db.cdm.swingHeight = (self.db.cdm.swingHeight or 6) + 2 end
    if not self.db.cdm.v6 then self.db.cdm.v6 = true; self.db.cdm.spacing = 0 end
    -- the first Fury default, never touched: the new Fury layout
    local fury = self.db.cdm.layouts[CharKey()]
    fury = fury and fury["2"]
    if myClass == "WARRIOR" and fury and not fury.v6 then
        fury.v6 = true
        local function ids(list)
            local t = {}
            for _, e in ipairs(list or {}) do t[#t + 1] = tostring(e.id) end
            return table.concat(t, ",")
        end
        if ids(fury[1]) == "23881,1680,1464,5308,78,845" and ids(fury[2]) == "12292,1719,2687,18499,6552,20252" then
            wipe(fury[1]); wipe(fury[2]); fury.seeded = nil
        end
    end
    -- Fury: Sunder Armor on the top row, Pummel on the bottom (swapped once)
    if myClass == "WARRIOR" and fury and not fury.v7 then
        fury.v7 = true
        local function at(row, id)
            for i, e in ipairs(row or {}) do if e.id == id then return i end end
        end
        local p, sd = at(fury[1], 6552), at(fury[2], 7386)
        if p and sd then
            fury[1][p], fury[2][sd] = fury[2][sd], fury[1][p]
        end
    end
    -- the global cooldown swipe on for everyone (once)
    if not self.db.cdm.v7 then self.db.cdm.v7 = true; self.db.cdm.showGCD = true end
    -- Fury: no Battle Shout; Sunder grey with no stacks; Bloodthirst and
    -- Whirlwind glow when ready; Execute glows at 20% (once)
    if myClass == "WARRIOR" and fury and not fury.v8 then
        fury.v8 = true
        local function addRule(e, rule)
            e.rules = e.rules or {}
            for _, ru in ipairs(e.rules) do
                if ru.c == rule.c and ru.a == rule.a then return end
            end
            tinsert(e.rules, rule)
        end
        for r = 1, 2 do
            local row = fury[r] or {}
            for i = #row, 1, -1 do
                local e = row[i]
                if e.id == 23881 or e.id == 1680 or e.id == 12292 then e.ignorePower = true end
                if e.id == 6673 then tremove(row, i)
                elseif e.id == 7386 then addRule(e, { c = "aura_missing", a = "desat" })
                elseif e.id == 23881 or e.id == 1680 then addRule(e, { c = "ready", a = "glow" })
                elseif e.id == 5308 then addRule(e, { c = "target_hp", v = 20, a = "glow" })
                end
            end
        end
    end
    -- Fury: Death Wish, Bloodthirst, Whirlwind in colour off cooldown, rage or not (once)
    if myClass == "WARRIOR" and fury and not fury.v9 then
        fury.v9 = true
        for r = 1, 2 do
            for _, e in ipairs(fury[r] or {}) do
                if e.id == 23881 or e.id == 1680 or e.id == 12292 then e.ignorePower = true end
            end
        end
    end
    -- Fury: Overpower to the end of the bottom row, Rend (grey until it's on
    -- the target) where Overpower was (once)
    if myClass == "WARRIOR" and fury and not fury.v10 then
        fury.v10 = true
        local top, bottom = fury[1] or {}, fury[2] or {}
        local opAt
        for i, e in ipairs(top) do if e.id == 7384 then opAt = i end end
        local hasRend
        for r = 1, 2 do for _, e in ipairs(fury[r] or {}) do if e.id == 772 then hasRend = true end end end
        if opAt then
            local op = tremove(top, opAt)
            tinsert(bottom, op)
            if not hasRend then
                tinsert(top, opAt, { t = "spell", id = 772, n = GetSpellInfo(772), rules = { { c = "aura_missing", a = "desat" } } })
            end
        end
    end
    -- mages (once): Mirror Image tracks Quad Core (its T10 buff); Fire: no
    -- Fireball, Living Bomb grey until it's on the target, Scorch tracks the
    -- 5% crit debuff (Improved Scorch or Shadow Mastery, the newest one)
    local mineM = self.db.cdm.layouts[CharKey()]
    if myClass == "MAGE" and mineM and not mineM.v13 then
        mineM.v13 = true
        for key, L in pairs(mineM) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    local row = L[r] or {}
                    for i = #row, 1, -1 do
                        local e = row[i]
                        if e.id == 133 and key == "2" then tremove(row, i)
                        elseif e.id == 55342 and (not e.aura or e.aura == "") then
                            e.aura = { 70747, "Quad Core" }
                        elseif e.id == 44457 or e.id == 2948 then
                            if e.id == 2948 then
                                e.aura, e.anyCaster, e.newest = { 22959, 17800 }, true, true
                            end
                            e.rules = e.rules or {}
                            local has
                            for _, ru in ipairs(e.rules) do if ru.c == "aura_missing" and ru.a == "desat" then has = true end end
                            if not has then tinsert(e.rules, { c = "aura_missing", a = "desat" }) end
                        end
                    end
                end
            end
        end
    end
    -- trolls and orcs: their racial on the bottom row of the layouts they
    -- already have (once)
    local mineR = self.db.cdm.layouts[CharKey()]
    if mineR and not mineR.racial1 then
        mineR.racial1 = true
        for _, L in pairs(mineR) do
            if type(L) == "table" and L[1] and (#L[1] > 0 or #(L[2] or {}) > 0) then AddRacial(L) end
        end
    end
    -- Fire mages: Ignite (its last tick's damage) in Fire Blast's place (once)
    if myClass == "MAGE" and mineM and not mineM.v14 then
        mineM.v14 = true
        local L = mineM["2"]
        if type(L) == "table" and L[1] then
            for r = 1, 2 do
                for i, e in ipairs(L[r] or {}) do
                    if e.id == 2136 then
                        L[r][i] = { t = "spell", id = 12654, n = GetSpellInfo(12654), tracker = true, ignite = true,
                            rules = { { c = "aura_missing", a = "desat" } } }
                    end
                end
            end
        end
    end
    -- Fire mages (once): Pyroblast grey without Hot Streak; Pushing the Limit
    -- (T10 2-piece haste buff) at the end of the top row, grey when not up
    if myClass == "MAGE" and mineM and not mineM.v15 then
        mineM.v15 = true
        local L = mineM["2"]
        if type(L) == "table" and L[1] and (#L[1] > 0 or #(L[2] or {}) > 0) then
            local hasPTL
            for r = 1, 2 do
                for _, e in ipairs(L[r] or {}) do
                    if e.id == 11366 then
                        e.aura, e.noGCD = 48108, true   -- Hot Streak's timer, not the DoT
                        local has
                        for _, ru in ipairs(e.rules) do if ru.c == "buff_missing" and ru.a == "desat" then has = true end end
                        if not has then tinsert(e.rules, { c = "buff_missing", aura = 48108, a = "desat" }) end
                    end
                    if e.id == 70753 then hasPTL = true end
                end
            end
            if not hasPTL then
                tinsert(L[1], { t = "spell", id = 70753, n = GetSpellInfo(70753), tracker = true,
                    aura = { 70753, "Pushing the Limit" }, rules = { { c = "aura_missing", a = "desat" } } })
            end
        end
    end
    -- Fire mages: Pyroblast shows Hot Streak (its timer, in colour) and
    -- nothing at all without it: no DoT timer, no global cooldown (once)
    if myClass == "MAGE" and mineM and not mineM.v16 then
        mineM.v16 = true
        for _, L in pairs(mineM) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 11366 then e.aura, e.noGCD = 48108, true end
                    end
                end
            end
        end
    end
    -- Fire mages: Pushing the Limit and Scorch swap places (once)
    if myClass == "MAGE" and mineM and not mineM.v17 then
        mineM.v17 = true
        local L = mineM["2"]
        if type(L) == "table" and L[1] then
            local pr, pi, sr, si
            for r = 1, 2 do
                for i, e in ipairs(L[r] or {}) do
                    if e.id == 70753 then pr, pi = r, i end
                    if e.id == 2948 then sr, si = r, i end
                end
            end
            if pr and sr then L[pr][pi], L[sr][si] = L[sr][si], L[pr][pi] end
        end
    end
    -- Unholy death knights: the new Unholy layout (once)
    local mineD = self.db.cdm.layouts[CharKey()]
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v18 then
        mineD.v18 = true
        local L = mineD["3"]
        if type(L) == "table" then wipe(L[1] or {}); wipe(L[2] or {}); L.seeded = nil end
    end
    -- death knights: Bone Shield grey when it's not up (once)
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v19 then
        mineD.v19 = true
        for _, L in pairs(mineD) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 49222 then
                            e.rules = e.rules or {}
                            local has
                            for _, ru in ipairs(e.rules) do if ru.c == "aura_missing" and ru.a == "desat" then has = true end end
                            if not has then tinsert(e.rules, { c = "aura_missing", a = "desat" }) end
                        end
                    end
                end
            end
        end
    end
    -- death knights: Horn of Winter grey while the buff isn't on you (once)
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v20 then
        mineD.v20 = true
        for _, L in pairs(mineD) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 57330 then
                            e.anyCaster = true
                            e.rules = e.rules or {}
                            local has
                            for _, ru in ipairs(e.rules) do if ru.c == "aura_missing" and ru.a == "desat" then has = true end end
                            if not has then tinsert(e.rules, { c = "aura_missing", a = "desat" }) end
                        end
                    end
                end
            end
        end
    end
    -- death knights: Horn of Winter glows when missing even while on its
    -- cooldown (once)
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v21 then
        mineD.v21 = true
        for _, L in pairs(mineD) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 57330 then
                            e.noPet = true
                            local found
                            for _, ru in ipairs(e.rules or {}) do
                                if ru.a == "glow" and (ru.c == "aura_missing" or ru.c == "buff_missing") then ru.evenCD, ru.ooc, found = true, true, true end
                            end
                            if not found then
                                e.rules = e.rules or {}
                                tinsert(e.rules, 1, { c = "aura_missing", a = "glow", ooc = true, evenCD = true })
                            end
                        end
                    end
                end
            end
        end
    end
    -- death knights: Horn of Winter counts only on you, not on your ghoul (once)
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v22 then
        mineD.v22 = true
        for _, L in pairs(mineD) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 57330 then e.noPet = true end
                    end
                end
            end
        end
    end
    -- death knights, every spec (once): Icy Touch / Plague Strike grey without
    -- your disease; Horn of Winter as in Unholy; Frost gets the presence icon
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v23 then
        mineD.v23 = true
        local function addRule(e, rule)
            e.rules = e.rules or {}
            for _, ru in ipairs(e.rules) do if ru.c == rule.c and ru.a == rule.a then
                for k, v in pairs(rule) do ru[k] = v end
                return
            end end
            tinsert(e.rules, rule)
        end
        for key, L in pairs(mineD) do
            if type(L) == "table" and L[1] then
                local hasPresence
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 45477 or e.id == 45462 then addRule(e, { c = "aura_missing", a = "desat" }) end
                        if e.id == 57330 then
                            e.anyCaster, e.noPet = true, true
                            addRule(e, { c = "aura_missing", a = "glow", ooc = true, evenCD = true })
                            addRule(e, { c = "aura_missing", a = "desat" })
                        end
                        if e.presence then hasPresence = true end
                    end
                end
                if key == "2" and not hasPresence and #L[1] > 0 then
                    tinsert(L[1], { t = "spell", id = 48265, n = GetSpellInfo(48265), presence = true })
                end
            end
        end
    end
    -- Frost death knights: Icy Touch and Plague Strike right after Obliterate (once)
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v24 then
        mineD.v24 = true
        local L = mineD["2"]
        if type(L) == "table" and L[1] then
            local row = L[1]
            local function take(id)
                for i, e in ipairs(row) do if e.id == id then return tremove(row, i) end end
            end
            local oi
            for i, e in ipairs(row) do if e.id == 49020 then oi = i end end
            if oi then
                local it, ps = take(45477), take(45462)
                for i, e in ipairs(row) do if e.id == 49020 then oi = i end end
                if ps then tinsert(row, oi + 1, ps) end
                if it then tinsert(row, oi + 1, it) end
            end
        end
    end
    -- Unholy death knights: the Desolation buff in Death Coil's place (once)
    if myClass == "DEATHKNIGHT" and mineD and not mineD.v25 then
        mineD.v25 = true
        local L = mineD["3"]
        if type(L) == "table" and L[1] then
            for r = 1, 2 do
                for i, e in ipairs(L[r] or {}) do
                    if e.id == 47541 then
                        L[r][i] = { t = "spell", id = 66803, n = GetSpellInfo(66803), tracker = true,
                            aura = { 66803, "Desolation" }, rules = { { c = "aura_missing", a = "desat" } } }
                    end
                end
            end
        end
    end
    -- every other class / spec (once): debuffs and maintenance buffs grey while
    -- they're not up. Left alone: the specs already set up one by one (Fury,
    -- Marksmanship, Fire, Feral, Frost / Unholy death knight).
    local GREY_IDS = {
        WARRIOR = { 772, 6343, 20243 },                      -- Rend, Thunder Clap, Devastate (Sunder)
        PALADIN = { 20925 },                                 -- Holy Shield
        HUNTER  = { 3674, 1978 },                            -- Black Arrow, Serpent Sting
        ROGUE   = { 1943, 703, 5171, 32645, 51662, 16511 },  -- Rupture, Garrote, Slice and Dice, Envenom, Hunger for Blood, Hemorrhage
        PRIEST  = { 34914, 589, 2944, 15286 },               -- Vampiric Touch, Pain, Devouring Plague, Vampiric Embrace
        SHAMAN  = { 8050, 17364 },                           -- Flame Shock, Stormstrike
        WARLOCK = { 48181, 30108, 172, 980, 348, 603 },      -- Haunt, UA, Corruption, Agony, Immolate, Doom
    }
    local SKIP_SPEC = { WARRIOR = { ["2"] = true }, HUNTER = { ["2"] = true }, MAGE = { ["2"] = true },
        DRUID = { ["2"] = true }, DEATHKNIGHT = { ["2"] = true, ["3"] = true } }
    local mineG = self.db.cdm.layouts[CharKey()]
    if mineG and not mineG.v26 and GREY_IDS[myClass] then
        mineG.v26 = true
        local want = {}
        for _, id in ipairs(GREY_IDS[myClass]) do want[id] = true end
        for key, L in pairs(mineG) do
            if type(L) == "table" and L[1] and not (SKIP_SPEC[myClass] and SKIP_SPEC[myClass][key]) then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if want[e.id] and e.aura ~= "none" then
                            e.rules = e.rules or {}
                            local has
                            for _, ru in ipairs(e.rules) do if ru.c == "aura_missing" and ru.a == "desat" then has = true end end
                            if not has then tinsert(e.rules, { c = "aura_missing", a = "desat" }) end
                        end
                    end
                end
            end
        end
    end
    -- Shadow priests (once): Vampiric Embrace and Inner Fire as self-buff
    -- reminders - in colour when up, grey and glowing when missing, no text
    local mineP = self.db.cdm.layouts[CharKey()]
    if myClass == "PRIEST" and mineP and not mineP.v27 then
        mineP.v27 = true
        local L = mineP["3"]
        if type(L) == "table" and L[1] then
            local function setup(e)
                e.noText, e.noPet = true, true
                e.rules = { { c = "aura_missing", a = "glow", ooc = true, evenCD = true }, { c = "aura_missing", a = "desat" } }
            end
            local hasIF
            for r = 1, 2 do
                for _, e in ipairs(L[r] or {}) do
                    if e.id == 15286 then setup(e) end
                    if e.id == 588 then setup(e); hasIF = true end
                end
            end
            if not hasIF and (#L[1] > 0 or #(L[2] or {}) > 0) then
                L[2] = L[2] or {}
                local e = { t = "spell", id = 588, n = GetSpellInfo(588) }
                setup(e)
                tinsert(L[2], e)
            end
        end
    end
    -- warriors (once): Sunder Armor from anyone, Expose Armor (a rogue's)
    -- first when it's up - its picture and time instead
    local mineW = self.db.cdm.layouts[CharKey()]
    if myClass == "WARRIOR" and mineW and not mineW.v28 then
        mineW.v28 = true
        for _, L in pairs(mineW) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 7386 or e.id == 20243 then
                            e.aura, e.anyCaster, e.byName = { 8647, 7386 }, true, true
                        end
                    end
                end
            end
        end
    end
    -- warlocks (once): Shadow Bolt tracks the 5% crit debuff like the fire
    -- mage's Scorch (Shadow Mastery or Improved Scorch, the newest one's
    -- picture and time; grey with neither)
    local mineL = self.db.cdm.layouts[CharKey()]
    if myClass == "WARLOCK" and mineL and not mineL.wl1 then
        mineL.wl1 = true
        for _, L in pairs(mineL) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 686 and (not e.aura or e.aura == "") then
                            e.aura, e.anyCaster, e.newest = { 22959, 17800 }, true, true
                            e.rules = e.rules or {}
                            local has
                            for _, ru in ipairs(e.rules) do if ru.c == "aura_missing" and ru.a == "desat" then has = true end end
                            if not has then tinsert(e.rules, { c = "aura_missing", a = "desat" }) end
                        end
                    end
                end
            end
        end
    end
    -- hunters: Raptor Strike on the top row instead of Steady Shot (once)
    local mineH = self.db.cdm.layouts[CharKey()]
    if myClass == "HUNTER" and mineH and not mineH.v8 then
        mineH.v8 = true
        for key, L in pairs(mineH) do
            if type(L) == "table" and L[1] then
                local has
                for r = 1, 2 do
                    for i = #(L[r] or {}), 1, -1 do
                        if L[r][i].id == 56641 then tremove(L[r], i) end
                    end
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 2973 then has = true end
                    end
                end
                if not has and (#L[1] > 0 or #(L[2] or {}) > 0) then tinsert(L[1], { t = "spell", id = 2973 }) end
            end
        end
    end
    -- hunters: Aimed Shot and Multi-Shot in one split icon, Explosive Trap
    -- where Multi-Shot was (once)
    if myClass == "HUNTER" and mineH and not mineH.v9 then
        mineH.v9 = true
        for key, L in pairs(mineH) do
            if type(L) == "table" and L[1] then
                local aimed, multi
                for r = 1, 2 do
                    for i, e in ipairs(L[r] or {}) do
                        if e.id == 19434 then aimed = e end
                        if e.id == 2643 then multi = { r, i } end
                    end
                end
                if aimed and multi then
                    aimed.pair = 2643
                    local has
                    for r = 1, 2 do for _, e in ipairs(L[r] or {}) do if e.id == 13813 then has = true end end end
                    if has then tremove(L[multi[1]], multi[2])
                    else L[multi[1]][multi[2]] = { t = "spell", id = 13813, n = GetSpellInfo(13813) } end
                end
            end
        end
    end
    -- the split Aimed Shot / Multi-Shot icon was dropped: Aimed Shot alone
    if myClass == "HUNTER" and mineH and not mineH.v10 then
        mineH.v10 = true
        for _, L in pairs(mineH) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do for _, e in ipairs(L[r] or {}) do e.pair = nil end end
            end
        end
    end
    -- hunters: Serpent Sting and Hunter's Mark grey while not on the target (once)
    if myClass == "HUNTER" and mineH and not mineH.v11 then
        mineH.v11 = true
        for _, L in pairs(mineH) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 1978 or e.id == 1130 then
                            e.rules = e.rules or {}
                            local has
                            for _, ru in ipairs(e.rules) do
                                if ru.c == "aura_missing" and ru.a == "desat" then has = true end
                            end
                            if not has then tinsert(e.rules, { c = "aura_missing", a = "desat" }) end
                        end
                    end
                end
            end
        end
    end
    -- hunters: Aimed Shot is only its cooldown, not its debuff (once)
    if myClass == "HUNTER" and mineH and not mineH.v12 then
        mineH.v12 = true
        for _, L in pairs(mineH) do
            if type(L) == "table" and L[1] then
                for r = 1, 2 do
                    for _, e in ipairs(L[r] or {}) do
                        if e.id == 19434 and (not e.aura or e.aura == "") then e.aura = "none" end
                    end
                end
            end
        end
    end
    -- specs left empty by a load without the defaults file: fill them now
    local mine = self.db.cdm.layouts[CharKey()]
    if mine and not mine.v3 then
        mine.v3 = true
        for k, L in pairs(mine) do
            if type(L) == "table" and L[1] and #L[1] == 0 and #(L[2] or {}) == 0 then L.seeded = nil end
        end
    end
    BuildMaps()
    playerGUID, playerName = UnitGUID("player"), UnitName("player")

    holder = CreateFrame("Frame", "HUICDM", UIParent)
    holder:SetScale(self.db.scale or 1)
    holder:SetWidth(100); holder:SetHeight(20)
    holder:SetFrameStrata("LOW")
    holder:Hide()
    CDM.holder = holder

    power = CreateFrame("Frame", nil, holder)
    A:SetTemplate(power)
    power.bar = A:StatusBar(power)
    FlatBar(power.bar)   -- flat, like the bars stacked on it
    -- at 0 a status bar still draws a sliver of fill: hide it when empty
    power.bar:SetScript("OnValueChanged", function(bar, v)
        local lo, hi = bar:GetMinMaxValues()
        local t = bar:GetStatusBarTexture()
        if t then t:SetAlpha((v and hi and hi > lo and (v - lo) / (hi - lo) > 0.002) and 1 or 0) end
    end)
    -- energy ticks above the bar fill, the text above the ticks
    power.ticks = {}
    power.tickLayer = CreateFrame("Frame", nil, power.bar)
    power.tickLayer:SetAllPoints(power.bar)
    power.tickLayer:SetFrameLevel(power.bar:GetFrameLevel() + 1)
    power.textLayer = CreateFrame("Frame", nil, power.bar)
    power.textLayer:SetAllPoints(power.bar)
    power.textLayer:SetFrameLevel(power.bar:GetFrameLevel() + 2)
    power.text = NewFS(power.textLayer, 12)
    power.text:SetPoint("CENTER", 1, 0)

    swingBox = CreateFrame("Frame", nil, holder)
    swingBox:SetWidth(10); swingBox:SetHeight(10)
    swingBox.over = CreateFrame("Frame", nil, swingBox)   -- the shared black lines
    swingBox.over:SetAllPoints(swingBox)
    swingBox.lines = {}
    CreateSwingBar("mh", 0.95, 0.75, 0.3)
    CreateSwingBar("oh", 0.55, 0.75, 1)
    CreateSwingBar("rg", 0.45, 0.9, 0.45)

    -- combo points: one bar with one outline (shared with its neighbours like
    -- the swing / power bars), 5 fills inside split by 1px black lines
    combo = CreateFrame("Frame", nil, swingBox)
    A:SetTemplate(combo)   -- the standard see-through background, like the swing bars
    combo.segs, combo.lines = {}, {}
    for k = 1, 5 do
        local fill = combo:CreateTexture(nil, "ARTWORK")
        fill:SetTexture(A.media.blank)   -- flat, like the swing bars
        fill:Hide()
        combo.segs[k] = { fill = fill }
    end
    for k = 1, 4 do
        local l = combo:CreateTexture(nil, "OVERLAY")
        l:SetTexture(A.media.blank)
        l:SetVertexColor(0, 0, 0, 1)
        combo.lines[k] = l
    end
    combo:Hide()

    -- runes (death knights): 6 boxes like the combo points, each filling as
    -- its rune comes back; red / green / blue, purple for a death rune
    runes = CreateFrame("Frame", nil, swingBox)
    A:SetTemplate(runes)
    runes.segs, runes.lines = {}, {}
    for k = 1, 6 do
        local fill = runes:CreateTexture(nil, "ARTWORK")
        fill:SetTexture(A.media.blank)
        fill:Hide()
        runes.segs[k] = { fill = fill }
    end
    for k = 1, 5 do
        local l = runes:CreateTexture(nil, "OVERLAY")
        l:SetTexture(A.media.blank)
        l:SetVertexColor(0, 0, 0, 1)
        runes.lines[k] = l
    end
    -- the seconds left on each recharging rune, above the fills and lines
    runes.textLayer = CreateFrame("Frame", nil, runes)
    runes.textLayer:SetAllPoints(runes)
    runes.textLayer:SetFrameLevel(runes:GetFrameLevel() + 2)
    for k = 1, 6 do
        runes.segs[k].text = NewFS(runes.textLayer, 12)
        runes.segs[k].text:SetTextColor(1, 1, 1)
    end
    runes:Hide()
    CDM.debug.runes = runes

    plus[1], plus[2] = CreatePlus(1), CreatePlus(2)

    local acc = 0
    holder:SetScript("OnUpdate", A:PerfWrap("Cooldown manager", function(_, el)
        local now = GetTime()
        RuneUpdate(now)
        local ct = CDM.castTime
        if ct and now - ct > 1 then
            CDM.castTime = nil
            if (CDM.clAny or 0) == (CDM.castCL or 0) then
                CDM.clFixes = (CDM.clFixes or 0) + 1
                if CombatLogClearEntries then CombatLogClearEntries() end
            end
        end
        UpdateSwing(now)
        CDM:Animate(el)
        acc = acc + el
        -- events mark it dirty many times a second in a fight (energy, rage,
        -- cooldowns, auras): redraw at most 20 times a second for them, and
        -- every 0.1s anyway for the timers
        if (dirty and acc >= 0.05) or acc >= 0.1 then
            dirty, acc = false, 0
            -- anything that moved the module (target / player frame
            -- changes, movers, layout changes) can leave it between two
            -- pixels: put it back on the grid
            if not CDM.animating then CDM:SnapToPixels() end
            CDM:UpdateAll()
        end
    end))

    self:RegisterMover("CDM", holder, "Cooldown Manager", function(p)
        if CDM.previewing then return end
        if A.db.positions.CDM then
            A:AlignPoint(holder, p[1], UIParent, p[2], A:Snap(holder, p[3]), A:Snap(holder, p[4]))
        else
            CDM:PlaceAuto()
        end
    end)

    -- follow the player / target frames when they move
    hooksecurefunc(A, "ApplyPosition", function(_, key)
        if CDM.previewing then return end
        if key == "Player" or key == "Target" then
            A:ApplyPosition("CDM", holder)
            CDM:RefreshCastbar()
        end
    end)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({
        "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN",
        "UNIT_AURA", "PLAYER_TARGET_CHANGED", "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_RUNIC_POWER",
        "UNIT_FOCUS", "UNIT_DISPLAYPOWER", "UNIT_MAXMANA", "UNIT_MAXRAGE", "UNIT_MAXENERGY", "UNIT_MAXRUNIC_POWER",
        "UNIT_HEALTH", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "RUNE_POWER_UPDATE", "BAG_UPDATE",
        "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
        "CHARACTER_POINTS_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_LEVEL_UP",
        "COMPANION_UPDATE", "ACTIONBAR_SLOT_CHANGED", "UNIT_COMBO_POINTS", "UPDATE_SHAPESHIFT_FORM",
    }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", A:PerfWrap("Cooldown manager: events", function(_, event, unit)
        if (event == "UNIT_AURA" or event == "UNIT_HEALTH") and unit ~= "player" and unit ~= "target" and unit ~= "pet" then return end
        -- power events of other units (party / raid / target mana ...) change nothing here
        if unit and unit ~= "player" and unit ~= "target" and unit ~= "pet" and unit ~= "vehicle"
            and event:find("^UNIT_") then return end
        if event == "UNIT_AURA" or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD"
            or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
            CDM.auraDirty = true
        end
        -- mounting / dismounting shows up as an aura change on you
        if (event == "UNIT_AURA" and unit == "player") or event == "COMPANION_UPDATE" then
            if (IsMounted() and true or false) ~= CDM.mounted then CDM:UpdateVisibility() end
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED"
            or event == "CHARACTER_POINTS_CHANGED" or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE"
            or event == "PLAYER_LEVEL_UP" then
            playerGUID, playerName = UnitGUID("player"), UnitName("player")
            if event == "PLAYER_ENTERING_WORLD" then queueDirty = true end
            CDM:UpdateVisibility()
            CDM:Layout()
        elseif event == "UPDATE_SHAPESHIFT_FORM" or (event == "UNIT_DISPLAYPOWER" and unit == "player") then
            CDM:Layout()   -- cat form: the combo point boxes come and go
        elseif event == "ACTIONBAR_SLOT_CHANGED" then
            queueDirty = true   -- looked at again when the swing bars next draw
        elseif event == "SPELLS_CHANGED" then
            queueDirty = true
            CDM.meleeRangeName = nil
            for r = 1, 2 do for _, b in ipairs(rows[r]) do if b.entry then CDM:SetEntry(b, b.entry) end end end
            if CDM.picker and CDM.picker:IsVisible() then CDM.spellList = SpellList(); CDM:RefreshPicker() end
        end
        dirty = true
    end))

    for _, e in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_ATTACK_SPEED",
        "UNIT_RANGEDDAMAGE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_INVENTORY_CHANGED",
        "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT" }) do
        pcall(swingEv.RegisterEvent, swingEv, e)
    end

    -- mounting: IsMounted() turns true a moment after the mount's aura event,
    -- so look for the change directly (cheap: one call, 20 times a second)
    local mount = CreateFrame("Frame")
    local macc = 0
    mount:SetScript("OnUpdate", function(_, el)
        macc = macc + el
        if macc < 0.05 then return end
        macc = 0
        if (IsMounted() and true or false) ~= CDM.mounted then CDM:UpdateVisibility() end
    end)

    -- talents read as empty during loading screens: retry for a while
    local retry = CreateFrame("Frame")
    local racc = 0
    retry:SetScript("OnUpdate", function(_, el)
        if not CDM.retry then return end
        racc = racc + el
        if racc < 1 then return end
        racc = 0
        CDM.retry = CDM.retry + 1
        if CDM.retry > 60 then CDM.retry = nil return end
        CDM:UpdateVisibility()
    end)

    CDM:UpdateVisibility()
    CDM:Layout()
end
