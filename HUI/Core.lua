-- HUI - Core
-- WoW 3.3.5a (12340) / Lua 5.1

HUI = HUI or {}
local A = HUI

local floor, format, pairs, type = math.floor, string.format, pairs, type

------------------------------------------------------------------------
-- /hui perf: how much time HUI's busiest code takes. Type it once to start
-- recording, play (a big pull), type it again for the results. Nothing is
-- timed while it is off.
------------------------------------------------------------------------
local perf = { on = false, t = {}, n = {}, max = {}, kb = {} }
A.perfData = perf
local clock = debugprofilestop
local gcount = collectgarbage

-- time and memory a call took (memory: KB of new data it made; a garbage
-- collection step inside the call can make that negative: not counted)
local function PerfDone(key, t0, m0, ...)
    local d = clock() - t0
    local m = gcount("count") - m0
    perf.t[key] = (perf.t[key] or 0) + d
    perf.n[key] = (perf.n[key] or 0) + 1
    if m > 0 then perf.kb[key] = (perf.kb[key] or 0) + m end
    if d > (perf.max[key] or 0) then perf.max[key] = d end
    return ...
end

-- wrap a handler: only measured while recording, otherwise a plain call.
-- The same function always gets the same wrapper (no new closure each time
-- code sets a script again).
local wrapped = setmetatable({}, { __mode = "kv" })   -- (both weak: no leak for one-off functions)
function A:PerfWrap(key, fn)
    if type(fn) ~= "function" or not clock then return fn end
    local w = wrapped[fn]
    if w then return w end
    w = function(...)
        if not perf.on then return fn(...) end
        return PerfDone(key, clock(), gcount("count"), fn(...))
    end
    wrapped[fn] = w
    return w
end

-- "Interface action failed because of an AddOn": say which call it was, so
-- it can be fixed (the game only names the addon)
do
    local w = CreateFrame("Frame")
    w:RegisterEvent("ADDON_ACTION_BLOCKED")
    w:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    local seen = {}
    w:SetScript("OnEvent", function(_, event, addon, fn)
        if addon ~= "HUI" then return end
        local key = tostring(fn)
        if seen[key] then return end   -- once per call per session
        seen[key] = true
        DEFAULT_CHAT_FRAME:AddMessage(("|cff33aaffHUI|r: blocked in combat: %s (%s). Please send this line."):format(key,
            event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked"))
    end)
end

local counter
function A:PerfToggle()
    if not clock then self:Print("this client has no profiling timer.") return end
    if not perf.on then
        wipe(perf.t); wipe(perf.n); wipe(perf.max); wipe(perf.kb)
        -- the game's memory cleanup is paused while recording: every KB a
        -- handler makes is then counted exactly (cleanup steps inside a call
        -- used to hide it), and HUI's own total growth shows what the listed
        -- handlers miss. It restarts when recording ends (or after 2 minutes).
        collectgarbage("collect")
        collectgarbage("stop")
        UpdateAddOnMemoryUsage()
        perf.hui0 = GetAddOnMemoryUsage("HUI") or 0
        perf.on, perf.start, perf.frames = true, GetTime(), 0
        if not counter then
            counter = CreateFrame("Frame")
            counter:SetScript("OnUpdate", function()
                if not perf.on then return end
                perf.frames = perf.frames + 1
                if GetTime() - perf.start > 120 then A:PerfToggle() end   -- never leave the cleanup off
            end)
        end
        self:Print("recording performance. Play (a big pull is best), then type /hui perf again for the results.")
        return
    end
    perf.on = false
    UpdateAddOnMemoryUsage()
    local huiKB = (GetAddOnMemoryUsage("HUI") or 0) - (perf.hui0 or 0)
    collectgarbage("restart")
    local secs = math.max(0.001, GetTime() - perf.start)
    local keys, total, totalKB = {}, 0, 0
    for k, v in pairs(perf.t) do keys[#keys + 1] = k; total = total + v; totalKB = totalKB + (perf.kb[k] or 0) end
    table.sort(keys, function(a, b) return perf.t[a] > perf.t[b] end)
    self:Print(format("%.0f seconds at %.0f fps. Per second of play: time (1000 ms = all of it) and new memory made:",
        secs, perf.frames / secs))
    for i = 1, math.min(#keys, 15) do
        local k = keys[i]
        DEFAULT_CHAT_FRAME:AddMessage(format("  |cffffd100%6.1f ms/s|r  |cff88ccff%6.1f KB/s|r  peak %5.1f ms  %6d calls  %s",
            perf.t[k] / secs, (perf.kb[k] or 0) / secs, perf.max[k], perf.n[k], k))
    end
    -- the biggest memory makers, if they are not in the list above
    table.sort(keys, function(a, b) return (perf.kb[a] or 0) > (perf.kb[b] or 0) end)
    for i = 1, math.min(#keys, 5) do
        local k = keys[i]
        if (perf.kb[k] or 0) / secs >= 0.5 then
            DEFAULT_CHAT_FRAME:AddMessage(format("  memory: |cff88ccff%6.1f KB/s|r  %s", perf.kb[k] / secs, k))
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(format("  total measured: |cffffd100%.1f ms/s|r (%.1f%%), |cff88ccff%.1f KB/s|r new memory. Some lines include others.",
        total / secs, total / secs / 10, totalKB / secs))
    DEFAULT_CHAT_FRAME:AddMessage(format("  all of HUI: |cff88ccff%.1f KB/s|r new memory (%.0f KB in %.0f s); the part not in the lines above comes from code that isn't listed.",
        huiKB / secs, huiKB, secs))
end

------------------------------------------------------------------------
-- Cheap setters for busy code (health text, timers, colours): the client
-- re-lays out a font string on every SetText even when the text is the
-- same, so only call it when something changed. Code that sets the text
-- some other way clears fs.huiTxt (A.SetTxt(fs, nil) / fs.huiTxt = nil).
------------------------------------------------------------------------
function A.SetTxt(fs, s)
    if fs.huiTxt ~= s then
        fs.huiTxt = s
        fs:SetText(s)
    end
end

-- lower-case names without making a new string every time (aura names
-- are compared against lower-case lists on every aura event)
A.lower = setmetatable({}, { __index = function(t, k)
    local v = k:lower()
    t[k] = v
    return v
end })

------------------------------------------------------------------------
-- Memory (/hui mem, minimap tooltip). The game's number also counts
-- garbage not collected yet, so it is measured after a full collection
-- (out of combat only: that takes a moment).
------------------------------------------------------------------------
function A:MemoryReport(noCollect)
    if not noCollect and not InCombatLockdown() then collectgarbage("collect") end
    UpdateAddOnMemoryUsage()
    local all = 0
    for i = 1, GetNumAddOns() do all = all + (GetAddOnMemoryUsage(i) or 0) end
    return { total = GetAddOnMemoryUsage("HUI") or 0, all = all }
end

function A:FormatKB(kb)
    return kb >= 1024 and format("%.2f MB", kb / 1024) or format("%.0f KB", kb)
end

function A:PrintMemory()
    local r = self:MemoryReport()
    self:Print("memory " .. self:FormatKB(r.total) .. " (all addons " .. self:FormatKB(r.all) .. ").")
end

------------------------------------------------------------------------
-- Lua memory cleanup pace: left at the game's own value (110) unless
-- HUIDB.gcPause is set to a number. The client's Lua allocator (lmemPool)
-- keeps memory in chunks it never gives back and searches them one by one
-- on every allocation and free, so letting garbage pile up higher (a larger
-- pause) makes the pools bigger for the rest of the session and every
-- allocation slower. The game's aggressive cleanup is the better trade here.
------------------------------------------------------------------------
function A:ApplyGCPause()
    local p = tonumber(self.db and self.db.gcPause)
    if not p then return end
    if p < 100 then p = 100 elseif p > 400 then p = 400 end
    collectgarbage("setpause", p)
end

------------------------------------------------------------------------
-- Settings window + colour picker live in the load-on-demand addon
-- HUI_Options (its own folder next to HUI): nothing of them is in memory
-- until /hui or a colour swatch is opened.
------------------------------------------------------------------------
function A:RefreshUnits()
    for f in pairs(self.allFrames or {}) do
        if f:IsVisible() and f.unit and UnitExists(f.unit) then self:UpdateAll(f) end
    end
    -- castbars follow the same colors / transparency
    if self.SetCastbarColor then
        for _, cb in pairs(self.castbars or {}) do
            if not cb.fading then self.SetCastbarColor(cb, A.colors.castbar) end
        end
    end
end

function A:LoadOptions()
    if self.optionsLoaded then return true end
    local ok, why = LoadAddOn("HUI_Options")
    if not ok then
        self:Print("the settings window could not load (" .. tostring(why) .. "). The HUI_Options folder must sit in Interface\\AddOns, next to HUI, and be enabled.")
        return false
    end
    self.optionsLoaded = true
    return true
end

-- stand-ins until HUI_Options is loaded; it replaces them with the real ones
local function Stub(name)
    local stub
    stub = function(self, ...)
        if not A:LoadOptions() or A[name] == stub then return end
        return A[name](A, ...)
    end
    A[name] = stub
end
Stub("ToggleConfig")
Stub("OpenConfigPage")
Stub("FindLines")

-- the game's colour picker (any addon's colour swatch): load HUI's on first use
do
    local hooked
    function A:HookColorPicker()
        if hooked or not ColorPickerFrame then return end
        hooked = true
        ColorPickerFrame:HookScript("OnShow", function()
            local cp = A.ColorPickerAdvanced
            if cp and cp.initialized then return end   -- it hooks OnShow itself from then on
            if not (A.db and A.db.modules and A.db.modules.colorPicker ~= false) then return end
            if not A:LoadOptions() then return end
            cp = A.ColorPickerAdvanced
            if cp and cp:LateInit() then cp:Hooked_OnShow() end
        end)
    end
end

------------------------------------------------------------------------
-- Media / style
------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\HUI\\media\\"
A.media = {
    blank = "Interface\\Buttons\\WHITE8X8",
    bar   = MEDIA .. "bar",
    font  = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",   -- the game's own fonts
}
do
    local f = ChatFontNormal and ChatFontNormal:GetFont()
    A.media.chatFont = f or "Fonts\\ARIALN.TTF"
end

-- if the font file can't be loaded, fall back to the game font so text never breaks
do
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    probe:SetFont(A.media.font, 10, "OUTLINE")
    local ok = probe:GetFont() and pcall(probe.SetText, probe, "Ag")
    if not ok then A.media.font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
end

-- set a font at a whole number of screen pixels (in-between sizes render soft)
function A:SetFontPx(obj, path, size, flags)
    local px = self:PX(obj)
    local snapped = math.max(1, math.floor(size / px + 0.5)) * px
    flags = flags or ""
    -- "shadow instead of outline": a solid 1px shadow reads cleaner than the
    -- client's thin outline at small sizes, above all on bright bars
    local isFS = obj.GetObjectType and obj:GetObjectType() == "FontString"
    if isFS and self.db and self.db.textShadow and flags:find("OUTLINE", 1, true) then
        flags = flags:gsub("THICKOUTLINE", ""):gsub("OUTLINE", ""):gsub("^[,%s]+", ""):gsub("[,%s]+$", "")
        obj.atrShadow = true
    elseif isFS then
        obj.atrShadow = nil
    end
    obj:SetFont(path, snapped, self:FF(flags))
    if isFS then self:QueueText(obj) end
end

------------------------------------------------------------------------
-- Text on whole pixels. Centred text in a bar lands half a pixel off when the
-- bar and the text differ odd/even in height, and the client then smears the
-- letters (and their outline) over two pixel rows. After a font string is set
-- up and placed, shift it so its top edge sits on a whole screen pixel.
------------------------------------------------------------------------
do
    local queue = {}
    local driver = CreateFrame("Frame")
    driver:Hide()
    local internal = false

    local function Shadow(fs)
        if not fs.atrShadow then return end
        local px = A:PX(fs)
        internal = true
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(px, -px)
        internal = false
    end

    -- returns true when done (or nothing to do), false to try again later
    local function Align(fs)
        Shadow(fs)
        -- atrShift ~= nil marks the string as placed: later SetText calls
        -- (health text, timers ...) then don't queue it again
        if not (A.db and A.db.alignText) then fs.atrShift = fs.atrShift or 0; return true end
        local n = fs:GetNumPoints()
        if n == 0 then return false end
        -- only text hanging from a single point: with two or more points the
        -- addon may later move just one of them, and the shift would add up
        -- (text crept upwards on every update)
        if n > 1 then fs.atrShift = fs.atrShift or 0; return true end
        local px = A:PX(fs)
        local top = fs:GetTop()
        if not top or (fs:GetStringHeight() or 0) <= 0 then return false end
        local t = top / px
        local shift = (math.floor(t + 0.5) - t) * px
        if math.abs(shift) < px * 0.02 then fs.atrShift = fs.atrShift or 0; return true end
        shift = shift + (fs.atrShift or 0)
        local delta = shift - (fs.atrShift or 0)
        if math.abs(delta) < px * 0.02 then fs.atrShift = fs.atrShift or 0; return true end
        -- move every anchor by the difference
        local pts = {}
        for i = 1, n do pts[i] = { fs:GetPoint(i) } end
        internal = true
        fs:ClearAllPoints()
        for _, p in ipairs(pts) do
            fs:SetPoint(p[1], p[2], p[3], p[4] or 0, (p[5] or 0) + delta)
        end
        internal = false
        fs.atrShift = shift
        return true
    end

    -- text that arrives later (empty / hidden at first) still gets placed:
    -- SetText is only hooked for strings that could not be placed yet, so
    -- the busy texts (health, timers) don't run Lua on every SetText
    local function OnLateText(f)
        if f.atrShift == nil and not internal then queue[f] = queue[f] or 0; driver:Show() end
    end

    driver:SetScript("OnUpdate", A:PerfWrap("Text alignment", function(self)
        local any = false
        for fs, tries in pairs(queue) do
            if Align(fs) then
                queue[fs] = nil
            elseif tries > 30 then
                queue[fs] = nil
                if not fs.atrLateHooked then
                    fs.atrLateHooked = true
                    hooksecurefunc(fs, "SetText", OnLateText)
                end
            else
                queue[fs] = tries + 1
                any = true
            end
        end
        if not any then self:Hide() end
    end))

    local function Requeue(fs)
        if internal then return end
        fs.atrShift = nil   -- new anchors from the addon: start over
        queue[fs] = 0
        driver:Show()
    end

    function A:QueueText(fs)
        if not fs.atrTextHooked then
            fs.atrTextHooked = true
            hooksecurefunc(fs, "SetPoint", Requeue)
            hooksecurefunc(fs, "ClearAllPoints", Requeue)
            hooksecurefunc(fs, "SetShadowOffset", function(f) if not internal and f.atrShadow then queue[f] = queue[f] or 0; driver:Show() end end)
        end
        queue[fs] = 0
        driver:Show()
    end
end

function A:FF(flags)
    flags = flags or ""
    if self.db and self.db.fontMono and not flags:find("MONOCHROME", 1, true) then
        flags = (flags == "") and "MONOCHROME" or (flags .. ", MONOCHROME")
    end
    return flags
end

A.FONT_SIZE = 10   -- every text in the addon uses this size (set from db.fontSize)

A.colors = {
    backdrop   = { 0.06, 0.06, 0.07, 0.90 },
    border     = { 0, 0, 0, 1 },
    healthDark = { 0.13, 0.13, 0.14 },
    castbar    = { 0.30, 0.55, 0.95 },
    castNoInt  = { 0.55, 0.55, 0.55 },
    castFail   = { 0.85, 0.15, 0.15 },
}

-- colour of a dead / ghost unit's whole frame (Unit Frames > Health)
function A:DeadColor()
    local d = self.db and self.db.deadColor
    if d then return d.r, d.g, d.b end
    return 0xb8 / 255, 0x21 / 255, 0x21 / 255
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------
A.defaults = {
    classBars     = false,  -- false = dark mode (default)
    bg            = { r = 0.06, g = 0.06, b = 0.07, a = 0.85 },   -- background of every frame (colour + opacity)
    frameAlpha    = 0.95,   -- (old, replaced by bg.a)
    smoothHealth  = true,
    raidIndicators = true,  -- your heals / shields as small icons on group frames
    healerRaidPos = true,   -- raid frames use their own position in a healing spec
    healerLayout  = true,   -- and player / target / cast bar gather around them
    healerScale   = 1.3,    -- raid buttons that much bigger in the healer layout
    healerGap     = 1,      -- screen pixels between the raid frames and player / target   -- health bars glide to new values
    gridSize      = 32,     -- unlock mode grid, screen pixels (0 = off)
    snapping      = true,   -- unlock mode: snap boxes to each other / screen / grid
    frameMatchChat = true,  -- unit frames use the chat box background (colour + opacity)
    forceMSAA     = true,
    cdNumbers     = true,   -- cooldown numbers on action buttons   -- raise multisampling to 4x for clean 1px borders
    fontSizes     = { units = 12, raid = 10, actionbars = 10, buffs = 12, bags = 10, minimap = 10, tooltips = 10, auras = 14 },
    darkColor     = { r = 0, g = 0, b = 0, a = 0 },   -- dark mode: filled part shows the frame background
    showPower     = false,  -- mana / energy / rage / runic power bars on unit frames
    scale         = 0.8,     -- unit + raid frame scale
    fontSize      = 10,
    onlyMyDebuffs = true,
    hidePlayerDebuffs = false,
    powerHeight   = 1,      -- power bar thickness in screen pixels (when power bars are on)
    targetAuraRows = 1,     -- rows of buffs / debuffs above the target frame
    auraSize      = 32,
    bubbles       = true,    -- ElvUI style chat bubbles
    zoneTextWhite = true,    -- zone names in white
    bubbleFontSize = 10,
    castbar = {              -- player / target / focus castbars
        showTotal = false,   -- time as "0.5 / 2.3" (left / whole cast)
        ticks = true,        -- tick marks on channelled spells (Mind Flay, Evocation ...)
        hidePlayer = false,  -- no cast bar of your own
        fitBetween = true,   -- DPS / tank: your cast bar fills the gap between player and target
    },
    ttScale       = 0.86,
    missingColor  = { r = 0.5608, g = 0.5608, b = 0.5608 },  -- #8f8f8f, missing health on every frame
    bossOnlyMulti = true,
    targetDebuffBlacklist = {},   -- debuffs never shown on the target frame (lower-case name -> name)   -- boss frames only when there are 2+ bosses (councils)
    deadColor     = { r = 0xb8 / 255, g = 0x21 / 255, b = 0x21 / 255 },  -- #b82121, a dead unit's whole frame
    menusMouseover = true,   -- micro menu + bag buttons only show on mouseover
    grabberMouseover = true, -- minimap [<] button only on mouseover
    barMouseover  = {        -- action bars that stay hidden until moused over
        Bar1 = false, Bar2 = false, Bar3 = false, Bar4 = false, Bar5 = true,
        PetBar = true, StanceBar = false,
    },
    textShadow    = false,    -- 1px shadow instead of the client's thin outline
    alignText     = true,    -- move text onto whole screen pixels
    fontMono      = false,   -- sharp pixel fonts (no smoothing)
    ttClassNames  = true,    -- tooltips: player names in class color

    -- chat
    chatWidth     = 0,       -- 0 = same width as the raid frames
    chatHeight    = 130,
    chatAlpha     = 0.95,
    chatEditBox   = "TOP",   -- TOP (over the tabs) / BOTTOM (under the box)
    chatTimestamps = "NONE", -- NONE / HH:MM / HH:MM:SS / 12H
    chatMouseover = false,   -- whole chat (and combat timer) only shows on mouseover
    chatMouseoverDelay = 1,  -- seconds after the mouse leaves before it fades
    chatTsColor   = { r = 0.85, g = 0.85, b = 0.85 },
    chatShortChannels = true,
    chatURLs      = true,
    chatHideOtherFaction = true,   -- hide says / yells in a language you don't speak
    chatClassNames = true,
    chatTabsVisible = true,
    chatFade      = false,
    chatFadeTime  = 30,
    chatHistory   = 500,
    chatAutoTabs  = true,
    chatHideCombatLog = true, -- close the combat log window (no CL tab)    -- set up Global / CL / Loot / Guild / Whisper / Raid-Party once per character
    chatSetupDone = {},

    -- minimap
    mmSize        = 132,
    mmBorder      = 1,
    mmBorderColor = { r = 0, g = 0, b = 0 },
    mmVisibility  = "ALWAYS", -- ALWAYS / COMBAT (hidden in combat) / MOUSEOVER
    mmZone        = "ALWAYS", -- ALWAYS / MOUSEOVER / HIDDEN
    mmCoords      = "NEVER",  -- NEVER / HOVER / ALWAYS
    mmClock24     = true,
    mmClockRealm  = false,
    mmZoomReset   = 0,        -- seconds, 0 = off
    mmRightTracking = true,
    mmMiddleMenu  = true,     -- middle-click the map: game menu list
    mmButtonRow   = true,     -- addon buttons in a row under the map

    -- quality of life (the retail essentials addon ports)
    auto = {
        enabled = true, sellJunk = true, repair = true, guildRepair = true,
        acceptInvites = false, inviteFrom = "FRIENDS", acceptRes = false, acceptCombatRes = false,
        acceptSummon = false, declineDuels = false, roleCheck = false,
        acceptQuests = false, turnInQuests = false, bestReward = false, shiftSkips = true,
        fastLoot = false, autoLoot = true, confirmRolls = false, confirmBoP = false,
        fillDelete = true, skipCinematics = false, hideErrors = "ALWAYS",
    },
    cursor = {
        enabled = false, texture = 1, size = 40, color = { r = 1, g = 1, b = 1, a = 0.8 },
        classColor = false, visibility = "ALWAYS", combatOnly = false,
    },
    lowHealth = {
        enabled = true, threshold = 30, color = { r = 1, g = 0, b = 0 }, intensity = 0.6,
        pulse = true, sound = false,
    },
    combatTimer = {
        enabled = true, hideOOC = false, chat = true, brackets = "SQUARE", size = 10,
        background = false,
        colorIn = { r = 1, g = 1, b = 1, a = 1 }, colorOut = { r = 1, g = 1, b = 1, a = 1 },
    },
    combatCross = {
        enabled = false, shape = "CROSS", size = 12, thickness = 2, outline = true,
        color = { r = 0.251, g = 1, b = 0.251, a = 1 }, alwaysShow = true,   -- #40ff40
        range = "NONE", hideInRange = false, oorColor = { r = 1, g = 0, b = 0, a = 1 },
    },
    moveFrames = { enabled = true, modifier = "NONE", remember = false, positions = {} },
    copy = { enabled = false, mod = "CTRL", chatButton = true },
    nameplates = {
        width = 140, height = 18, fontSize = 10, castHeight = 16, auraSize = 18, threatSize = 2,
        showLevel = true, healthText = "BOTH", showCast = true, showAuras = true,
        threatBorder = true, customHostile = true, hostileColor = { r = 0.6, g = 0.12, b = 0.15 },
        customNeutral = true, neutralColor = { r = 1, g = 0.9608, b = 0.4118 },   -- #fff569
        showEnemies = true, stack = true, smoothStack = false, shortNames = true, hideNeutral = false, blacklist = {},
        raidColor = true,    -- raid marked plates take the mark's colour
        raidMarks = { true, true, true, true, true, true, true, true },   -- which marks (star .. skull)
        mouseHighlight = true, glowAlpha = 0.8, glowColor = { r = 1, g = 1, b = 1 },   -- glow around the plate under the mouse
        fadeOthers = false, fadeAlpha = 0.4,   -- plates that are not your target fade to this
        auraBlacklist = {},  -- debuffs never shown on plates (lower-case name -> name)
    },
    abSize        = 22,     -- action button size
    abSpacing     = 1,      -- 1px gap between buttons
    abBorder      = 1,      -- action button border size in px
    fitChatBars   = true,   -- bar 5 and the pet bar are as tall as the chat box
    pixelHeight   = 0,      -- real game window height in pixels; 0 = work it out
    showHotkeys   = true,
    showMacro     = true,
    chatFontSize  = 10,
    bagCols       = 12,
    bagSearch     = true,   -- search box in the bag header
    bagItemLevel  = true,   -- item level on armour / weapons in the bag
    buffScale     = 0.8,
    combatIcon    = true,   -- crossed swords on the player frame while in combat
    showInfo      = true,   -- FPS / MS strip on the minimap
    collectButtons = true,  -- addon minimap buttons go into a flyout
    raidDeficit   = false,
    raidRange     = true,
    raidImportant = {},      -- debuff names / spell IDs shown big in the middle of raid / party frames
    ttCursor      = true,
    ttHideCombat  = true,
    windowScale   = 0.85,   -- Blizzard windows (character, spellbook, loot...) drawn this much smaller
    popupScale    = 0.8,    -- confirmation / dungeon finder / ready check popups
    raidWarnScale = 0.8,    -- raid warnings / boss emotes in the middle of the screen
    modules = {
        raid = true, actionbars = true, buffs = true, chat = true, minimap = true,
        bags = true, tooltips = true, nameplates = true, colorPicker = true, party = true, skins = true,
    },
    positions     = {},
}

-- every element that touches a screen edge sits 2px from it
A.defaultPositions = {
    Player        = { "CENTER", "CENTER", -260, -170 },
    Target        = { "CENTER", "CENTER",  260, -170 },
    TargetTarget  = { "CENTER", "CENTER",  445, -170 },
    Focus         = { "LEFT", "LEFT", 335.80, 110.91 },
    Pet           = { "CENTER", "CENTER", -315, -235 },
    PlayerCastbar = { "CENTER", "CENTER",    0, -140 },
    Raid          = { "TOPLEFT", "TOPLEFT",   2,   -2 },
    Party         = { "CENTER", "CENTER", -290.72, 29.19 },
    RaidHealer    = { "TOP", "CENTER", 0, -150 },   -- raid frames while in a healing spec
    Bar1          = { "BOTTOM", "BOTTOM", 0, 2 },
    Bar2          = { "BOTTOM", "BOTTOM", 0, 37 },
    Bar3          = { "BOTTOM", "BOTTOM", 0, 72 },
    Bar4          = { "RIGHT", "RIGHT", -2, 0 },
    Bar5          = { "RIGHT", "RIGHT", -37, 0 },
    PetBar        = { "BOTTOM", "BOTTOM", 0, 108 },
    StanceBar     = { "BOTTOMLEFT", "BOTTOM", -208, 142 },
    MicroMenu     = { "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2 },
    Bags          = { "BOTTOMRIGHT", "BOTTOMRIGHT", -458.82, 10.27 },
    BagFrame      = { "RIGHT", "RIGHT", -1.54, -100.59 },
    Minimap       = { "TOPRIGHT", "TOPRIGHT", -2, -2 },
    Buffs         = { "TOPRIGHT", "TOPRIGHT", -166, -2 },
    Chat          = { "BOTTOMLEFT", "BOTTOMLEFT", 2, 2 },
    CombatTimer   = { "BOTTOMLEFT", "BOTTOMLEFT", 286.81, 154.30 },
    CombatCross   = { "CENTER", "CENTER", 0, -10 },
    Loot          = { "TOPLEFT", "TOPLEFT", 14, -150 },   -- the loot window (its visible box)
    Boss          = { "RIGHT", "RIGHT", -60, 160 },       -- boss frames (stack of up to 4)
    LootRoll      = { "TOP", "TOP", 0, -180 },            -- loot roll bars (stack downwards)
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
A.CopyDefaults = CopyDefaults

function A:LoadDB()
    -- A new HUI version always starts from the defaults: the version the saved
    -- settings were made with is stored, and when the addon's version (HUI.toc,
    -- "## Version") is different, everything is reset. Same version: your
    -- changes are kept.
    local version = GetAddOnMetadata and GetAddOnMetadata("HUI", "Version") or nil
    self.versionReset = false
    if version and type(HUIDB) == "table" and HUIDB.addonVersion ~= version then
        HUIDB = nil
        self.versionReset = true
    end
    -- v1.28: one full reset to the defaults (positions, sizes, toggles). Older
    -- migrations are marked done so they don't touch the fresh settings.
    if type(HUIDB) ~= "table" or not HUIDB.reset33 then
        HUIDB = { reset33 = true, barsToggled = false }
        for v = 15, 59 do HUIDB["v" .. v] = true end
    end
    HUIDB = CopyDefaults(self.defaults, HUIDB)
    HUIDB.addonVersion = version
    -- boss mods / damage meter are no longer part of HUI: drop their settings
    for _, k in ipairs({ "meter", "bm", "dbmState", "dbmStash", "dbmDefaultsApplied", "bmDebug" }) do HUIDB[k] = nil end
    if type(HUIDB.positions) == "table" then
        for _, k in ipairs({ "RangeCheck", "DBMAlerts" }) do HUIDB.positions[k] = nil end
    end
    self.db = HUIDB
    if self.db.raid ~= nil then  -- migrate v1.0 setting
        self.db.modules.raid = self.db.raid
        self.db.raid = nil
    end
    if not self.db.v15 then       -- v1.5: minimum padding + new chat/minimap layout
        self.db.v15 = true
        self.db.abSpacing = 1
        self.db.chatFontSize = 10
        self.db.positions.Chat = nil
        self.db.positions.Minimap = nil
        for _, k in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "PetBar", "StanceBar" }) do
            self.db.positions[k] = nil
        end
    end
    if not self.db.v16 then       -- v1.6: dark mode is the default look
        self.db.v16 = true
        self.db.classBars = false
    end
    if not self.db.v17 then       -- v1.7 defaults: black 25% dark mode, unit font 12
        self.db.v17 = true
        self.db.darkColor = { r = 0, g = 0, b = 0, a = 0.25 }
        self.db.fontSizes.units = 12
        self.db.fontSizes.tooltips = 12
        self.db.showPower = false
    end
    if not self.db.v20 then       -- v1.10: only my debuffs, pixel-exact default layout
        self.db.v20 = true
        self.db.onlyMyDebuffs = true
        for _, k in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "PetBar", "StanceBar", "Chat",
            "Minimap", "Buffs", "Raid", "MicroMenu", "Bags", "BagFrame", "TargetTarget" }) do
            self.db.positions[k] = nil
        end
    end
    if not self.db.v19 then       -- v1.9: target of target re-attached to the target frame
        self.db.v19 = true
        self.db.positions.TargetTarget = nil
    end
    if not self.db.v18 then       -- v1.8 defaults: small tooltips, hidden in combat
        self.db.v18 = true
        self.db.fontSizes.tooltips = 10
        self.db.ttHideCombat = true
    end
    if not self.db.v21 then       -- v1.11: bigger unit-frame auras with their own font size
        self.db.v21 = true
        self.db.auraSize = 32
        self.db.fontSizes.auras = self.db.fontSizes.auras or 10
        for _, k in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "PetBar", "StanceBar" }) do
            self.db.positions[k] = nil
        end
    end
    if not self.db.v23 then       -- v1.14: bars share one left edge, pet frame under player
        self.db.v23 = true
        for _, k in ipairs({ "Bar1", "Bar2", "Bar3", "PetBar", "StanceBar", "Pet" }) do
            self.db.positions[k] = nil
        end
    end
    if not self.db.v22 then       -- v1.13: bigger aura numbers, smaller tooltips, re-aligned bars
        self.db.v22 = true
        self.db.fontSizes.auras = 14
        self.db.ttScale = 0.75
        for _, k in ipairs({ "PetBar", "StanceBar", "Buffs" }) do self.db.positions[k] = nil end
    end
    if not self.db.v26 then       -- v1.17: menus next to the main bar
        self.db.v26 = true
        self.db.positions.MicroMenu = nil
        self.db.positions.Bags = nil
    end
    if not self.db.v25 then       -- v1.16: no missing-health text on raid frames
        self.db.v25 = true
        self.db.raidDeficit = false
    end
    if not self.db.v45 then       -- v1.55: one background colour + opacity for all frames
        self.db.v45 = true
        local a = self.db.chatAlpha or 0.95
        self.db.bg = { r = 0.06, g = 0.06, b = 0.07, a = a }
    end
    if not self.db.v46 then       -- v1.56: 85% backgrounds, missing health #cfcfcf
        self.db.v46 = true
        self.db.bg = self.db.bg or {}
        self.db.bg.a = 0.85
        self.db.missingColor = { r = 0.8118, g = 0.8118, b = 0.8118 }
    end
    if not self.db.v47 then       -- v1.58: missing health #8f8f8f
        self.db.v47 = true
        self.db.missingColor = { r = 0.5608, g = 0.5608, b = 0.5608 }
    end
    if not self.db.v48 then       -- v1.70: nameplate defaults
        self.db.v48 = true
        local n = self.db.nameplates
        if n then
            n.customNeutral = true
            n.neutralColor = { r = 1, g = 0.9608, b = 0.4118 }
            n.smoothStack = false
            n.shortNames = true
        end
    end
    if not self.db.v70 then       -- boss bar font default 10 -> 9 (unless changed by hand)
        self.db.v70 = true
        if type(self.db.bm) == "table" and self.db.bm.fontSize == 10 then self.db.bm.fontSize = 9 end
    end
    if not self.db.v69 then       -- dead colour default #6d1414 -> #b82121 (unless picked by hand)
        self.db.v69 = true
        local d = self.db.deadColor
        if type(d) == "table" and math.abs((d.r or 0) - 0x6d / 255) < 0.002
            and math.abs((d.g or 0) - 0x14 / 255) < 0.002 and math.abs((d.b or 0) - 0x14 / 255) < 0.002 then
            self.db.deadColor = { r = 0xb8 / 255, g = 0x21 / 255, b = 0x21 / 255 }
        end
    end
    if not self.db.v68 then       -- important debuffs: Soul Consumption next to Fiery Combustion (Halion)
        self.db.v68 = true
        local list = self.db.raidImportant
        if type(list) == "table" then
            for i = #list, 1, -1 do
                local v = list[i]
                if type(v) == "string" and (v:lower() == "soul consumption" or v:lower() == "soul comsumption") then
                    table.remove(list, i)
                end
            end
            local at = 1
            for i, v in ipairs(list) do
                if type(v) == "string" and v:lower() == "fiery combustion" then at = i + 1 break end
            end
            table.insert(list, at, "Soul Consumption")
            if self.db.raidImportantIcons then self.db.raidImportantIcons["soul comsumption"] = nil end
            if self.RebuildImportantDebuffs then self:RebuildImportantDebuffs() end
        end
    end
    if not self.db.v67 then       -- pet bar: back to its spot beside the damage meter
        self.db.v67 = true
        if self.db.positions then self.db.positions.PetBar = nil end
    end
    if not self.db.v66 then       -- macro names on the action buttons: on
        self.db.v66 = true
        self.db.showMacro = true
    end
    if not self.db.v65 then       -- raid frames grow down, then right
        self.db.v65 = true
        if type(self.db.raidLayout) == "table" then self.db.raidLayout.layout = "COLUMNS" end
    end
    if not self.db.v64 then       -- boss frames: back to their new spot under the target castbar
        self.db.v64 = true
        if self.db.positions then self.db.positions.Boss = nil end
    end
    if not self.db.v63 then       -- the Slug font option is gone
        self.db.v63 = true
        self.db.slugFonts = nil
    end
    if not self.db.v62 then       -- boss mods test: follow the instance you are in
        self.db.v62 = true
        if self.db.bm then self.db.bm.testInstance = "" end
    end
    if not self.db.v61 then       -- Enervating Brand is no longer an important debuff
        self.db.v61 = true
        local list = self.db.raidImportant
        if type(list) == "table" then
            for i = #list, 1, -1 do
                if type(list[i]) == "string" and list[i]:lower() == "enervating brand" then table.remove(list, i) end
            end
        end
    end
    if not self.db.v60 then       -- important raid debuffs: the WotLK list, once
        self.db.v60 = true
        if self.AddImportantDefaults then self:AddImportantDefaults() end
    end
    if not self.db.v59 then       -- v1.126.4: taller meter bars
        self.db.v59 = true
        if self.db.meter and self.db.meter.barHeight == 14 then self.db.meter.barHeight = 18 end
    end
    if not self.db.v58 then       -- v1.126.1: wider damage meter
        self.db.v58 = true
        if self.db.meter and (self.db.meter.width or 0) == 0 then self.db.meter.width = 440 end
    end
    if not self.db.v57 then       -- v1.125.2: smaller chat bubble text
        self.db.v57 = true
        self.db.bubbleFontSize = 10
    end
    if not self.db.v56 then       -- v1.120: taller boss bars, smaller text
        self.db.v56 = true
        if self.db.bm then self.db.bm.height, self.db.bm.fontSize = 22, 10 end
    end
    if not self.db.v55 then       -- v1.116: minimap coordinates off by default
        self.db.v55 = true
        self.db.mmCoords = "NEVER"
    end
    if not self.db.v54 then       -- v1.107: healer layout: bigger raid, 1px to player / target
        self.db.v54 = true
        self.db.healerScale, self.db.healerGap = 1.3, 1
    end
    if not self.db.v53 then       -- v1.105: longer raid names (they now use the full width)
        self.db.v53 = true
        if self.db.raidLayout and (self.db.raidLayout.nameLen or 8) < 12 then self.db.raidLayout.nameLen = 12 end
    end
    if not self.db.v52 then       -- v1.90: minimap the size of the reference (167 px)
        self.db.v52 = true
        self.db.mmSize = 132
    end
    if not self.db.v51 then       -- v1.87: smaller raid + chat (raid width), like the reference
        self.db.v51 = true
        self.db.chatWidth, self.db.chatHeight = 0, 130
        if self.db.raidLayout then self.db.raidLayout.width = 0 end
    end
    if not self.db.v50 then       -- v1.73: back to the outline, smooth fonts
        self.db.v50 = true
        self.db.textShadow, self.db.fontMono = false, false
    end
    if not self.db.v49 then       -- v1.72: cleaner text
        self.db.v49 = true
        self.db.textShadow, self.db.alignText, self.db.fontMono = true, true, true
        if self.db.nameplates and (self.db.nameplates.fontSize or 9) < 10 then self.db.nameplates.fontSize = 10 end
    end
    if not self.db.v44 then       -- v1.52: darker backgrounds, timer white out of combat
        self.db.v44 = true
        self.db.chatAlpha, self.db.frameAlpha = 0.95, 0.95
        self.db.combatTimer.colorOut = { r = 1, g = 1, b = 1, a = 1 }
    end
    if not self.db.v43 then       -- v1.50: unit frames match the chat background
        self.db.v43 = true
        self.db.frameMatchChat = true
        self.db.frameAlpha = 0.75
        self.db.darkColor = { r = 0, g = 0, b = 0, a = 0 }
    end
    if not self.db.v42 then       -- v1.48: brighter grey, tooltips skinned + on the cursor
        self.db.v42 = true
        self.db.missingColor = { r = 0.65, g = 0.65, b = 0.65 }
        self.db.modules.tooltips = true
        self.db.ttCursor = true
    end
    if not self.db.v41 then       -- v1.47: brighter missing-health grey
        self.db.v41 = true
        self.db.missingColor = { r = 0.55, g = 0.55, b = 0.55 }
    end
    if not self.db.v40 then       -- v1.45: taller plate + cast bar
        self.db.v40 = true
        local n = self.db.nameplates
        n.height, n.castHeight = 18, 16
    end
    if not self.db.v39 then       -- v1.44: narrower, taller plates with the level shown
        self.db.v39 = true
        local n = self.db.nameplates
        n.width, n.height, n.showLevel = 140, 17, true
    end
    if not self.db.v38 then       -- v1.43: taller nameplates
        self.db.v38 = true
        local n = self.db.nameplates
        n.height, n.fontSize, n.castHeight, n.auraSize = 15, 9, 11, 18
    end
    if not self.db.v37 then       -- v1.42: new nameplate look
        self.db.v37 = true
        local n = self.db.nameplates
        n.width, n.height, n.fontSize, n.castHeight = 170, 14, 8, 10
        n.showLevel, n.healthText = false, "BOTH"
    end
    if not self.db.v36 then       -- v1.40: bars 2-4 attach to the main bar
        self.db.v36 = true
        for _, k in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4" }) do self.db.positions[k] = nil end
    end
    if not self.db.v35 then       -- v1.36: chat + minimap 2px from the screen edges
        self.db.v35 = true
        for _, k in ipairs({ "Chat", "Minimap", "Buffs", "Debuffs", "PetBar", "Bar5", "Bags", "CombatTimer" }) do
            self.db.positions[k] = nil
        end
    end
    if not self.db.v34 then       -- v1.35: 1px gap between every slot
        self.db.v34 = true
        self.db.abSpacing = 1
    end
    if not self.db.v33 then       -- v1.34: single 1px divider between buttons
        self.db.v33 = true
        self.db.abSpacing = -1
    end
    if not self.db.v32 then       -- v1.33: action buttons touch (no world showing between them)
        self.db.v32 = true
        self.db.abSpacing = 0
    end
    if not self.db.v31 then       -- v1.27: sizes measured against the reference screenshot
        self.db.v31 = true
        local d = self.db
        d.abSize, d.abSpacing = 22, 1
        d.chatWidth, d.chatHeight = 308, 150
        d.mmSize = 156
        d.barsToggled = false
        for _, k in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "PetBar", "StanceBar", "Chat",
            "Minimap", "Buffs", "Debuffs", "Bags", "CombatTimer", "BagFrame" }) do
            d.positions[k] = nil
        end
    end
    if not self.db.v30 then       -- v1.26: compact layout
        self.db.v30 = true
        local d = self.db
        d.chatWidth, d.chatHeight, d.chatAlpha = 308, 150, 0.75
        if d.chatTimestamps == "NONE" then d.chatTimestamps = "12H" end
        d.chatTsColor = { r = 0.85, g = 0.85, b = 0.85 }
        d.mmSize, d.mmMiddleMenu, d.mmButtonRow = 156, true, true
        d.barMouseover.Bar5, d.barMouseover.PetBar = true, true
        d.ttClassNames = true
        for _, k in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "PetBar", "StanceBar", "Chat",
            "Minimap", "Buffs", "Debuffs", "Bags", "MicroMenu", "CombatTimer", "BagFrame" }) do
            d.positions[k] = nil
        end
    end
    if not self.db.v29 then       -- v1.25: smaller player buffs / debuffs
        self.db.v29 = true
        self.db.buffScale = 0.8
        self.db.fontSizes.buffs = 12
    end
    if not self.db.v28 then       -- v1.24: moving Blizzard windows is on for everyone
        self.db.v28 = true
        self.db.moveFrames.enabled = true
    end
    if not self.db.v27 then       -- v1.23: red errors hidden, combat timer on above the chat
        self.db.v27 = true
        self.db.auto.hideErrors = "ALWAYS"
        self.db.combatTimer.enabled = true
        self.db.combatTimer.size = 10
        self.db.positions.CombatTimer = nil
    end
    if not self.db.v24 then       -- v1.15: tooltips 15% bigger
        self.db.v24 = true
        self.db.ttScale = 0.86
    end
    -- fixed settings: no longer in the options, always these values
    local d = self.db
    d.modules.colorPicker = true
    d.forceMSAA, d.pixelHeight = true, 0
    d.raidIndicators, d.healerRaidPos, d.healerLayout = true, true, true
    d.healerScale, d.healerGap = 1.3, 1
    d.moveFrames.enabled, d.moveFrames.modifier, d.moveFrames.remember = true, "NONE", false
    d.copy.enabled, d.copy.chatButton = false, true
    -- borders: always 1px, black (the nameplate border still turns to the threat colour)
    d.abBorder, d.mmBorder = 1, 1
    d.mmBorderColor = { r = 0, g = 0, b = 0 }
    if d.nameplates then d.nameplates.threatBorder, d.nameplates.threatSize = true, 1 end

    self.FONT_SIZE = self.db.fontSize
    self:ApplyBgColor()
    self:UpdateBarDefaults()
end

-- default layout in real screen pixels: 2px from the screen edges, 1px between frames
function A:UpdateBarDefaults()
    local p = self:PX(UIParent)
    local E, G = 2 * p, 1 * p
    local size, sp = self:Snap(UIParent, self.db.abSize), self.db.abSpacing * p
    local step = size + sp
    local d = self.defaultPositions
    -- two rows of 24 buttons centred at the bottom: Bar1 + Bar3 underneath,
    -- Bar2 + Bar4 on top; the halves meet with the normal button spacing
    local wpx = 12 * math.floor(size / p + 0.5) + 11 * self.db.abSpacing
    local total = 2 * wpx + self.db.abSpacing
    local L = -math.floor(total / 2) * p
    local R = L + (wpx + self.db.abSpacing) * p
    d.Bar1 = { "BOTTOMLEFT", "BOTTOM", L, E }
    d.Bar3 = { "BOTTOMLEFT", "BOTTOM", R, E }
    d.Bar2 = { "BOTTOMLEFT", "BOTTOM", L, E + step }
    d.Bar4 = { "BOTTOMLEFT", "BOTTOM", R, E + step }
    d.StanceBar = { "BOTTOMLEFT", "BOTTOM", L, E + 2 * step + G }
    -- Bar5 (beside the chat) and the pet bar (bottom right) attach to other
    -- frames; these are only fallbacks
    d.Bar5 = { "BOTTOMLEFT", "BOTTOMLEFT", 440, 0 }
    d.PetBar = { "BOTTOMRIGHT", "BOTTOMRIGHT", -440, 0 }
    d.Raid = { "TOPLEFT", "TOPLEFT", E, -E }
    -- every element touching a screen edge sits 2px (E) from it
    d.Chat = { "BOTTOMLEFT", "BOTTOMLEFT", E, E }
    d.Minimap = { "TOPRIGHT", "TOPRIGHT", -E, -E }
    d.Buffs = { "TOPRIGHT", "TOPRIGHT", -(E + self:Snap(UIParent, self.db.mmSize or 160) + 2 * p), -E }
    d.Debuffs = { "TOPRIGHT", "TOPRIGHT", d.Buffs[3], -(E + 120) }   -- fallback; normally hangs under the buffs
    -- Bags, BagFrame and CombatTimer use the fixed defaults at the top
end

-- run something now, or after combat if we're locked down
A.oocQueue = {}
function A:RunOOC(fn)
    if InCombatLockdown() then
        table.insert(self.oocQueue, fn)
    else
        fn()
    end
end
local ooc = CreateFrame("Frame")
ooc:RegisterEvent("PLAYER_REGEN_ENABLED")
ooc:SetScript("OnEvent", function()
    local q = A.oocQueue
    A.oocQueue = {}
    for _, fn in ipairs(q) do pcall(fn) end
end)

-- run a setup step; report errors without breaking the other modules
function A:Safe(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        self:Print("|cffff5555error in " .. label .. ":|r " .. tostring(err))
    end
end

function A:HideRegions(frame)
    if not frame then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
end

-- hide a named Blizzard object for good (textures -> invisible, frames -> hidden parent)
function A:Remove(name)
    local o = name
    if type(name) == "string" then o = _G[name] end
    if not o or not o.GetObjectType then return end
    if o:GetObjectType() == "Texture" then
        o:SetAlpha(0)
    else
        if o.UnregisterAllEvents then o:UnregisterAllEvents() end
        o:Hide()
        o:SetParent(A.hider)
    end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function A:Print(...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffc41f3bHUI|r: " .. table.concat({ ... }, " "))
end

-- size of one real screen pixel in a frame's own units (pixel-perfect borders / gaps)
-- The real height of the game's drawing area, in pixels. gxResolution is what the
-- game was asked for; in windowed / maximized mode the window can be a few pixels
-- smaller, and then 1px lines drift (2px, 1px, 2px ... along a row of buttons).
--  * db.pixelHeight > 0: set by hand (/hui > General > Pixel grid)
--  * windowed: the UI keeps the window's shape, so height = width / aspect ratio
function A:ScreenHeight()
    local r = GetCVar("gxResolution") or ""
    local rw, rh = r:match("(%d+)x(%d+)")
    rw, rh = tonumber(rw) or 1920, tonumber(rh) or 1080
    local manual = self.db and self.db.pixelHeight
    if manual and manual > 0 then return manual end
    if GetCVar("gxWindow") == "1" then
        -- a maximized window loses the same few pixels in width and height
        -- (1920x1080 -> 1919x1079). The UI takes the window's real shape, so
        -- solve (rw - d) / (rh - d) = width / height of the UI for d.
        local sw, sh = GetScreenWidth(), GetScreenHeight()
        if sw and sh and sw > 0 and sh > 0 then
            local ratio = sw / sh
            if math.abs(ratio - 1) > 0.01 then
                local d = (rw - ratio * rh) / (1 - ratio)
                if d > 0.3 and d < 60 then return rh - math.floor(d + 0.5) end
                -- otherwise the window lost height only (title bar, taskbar):
                -- it keeps the screen's width, its height follows from its shape
                if ratio > rw / rh then
                    local h = math.floor(rw / ratio + 0.5)
                    if h > rh * 0.75 and h < rh then return h end
                end
            end
        end
    end
    return rh
end

function A:PX(frame)
    if not self.screenH then
        self.screenH = self.db and self:ScreenHeight() or nil
        if not self.screenH then
            local r = GetCVar("gxResolution")
            return 768 / ((tonumber(r and r:match("%d+x(%d+)")) or 1080) * (frame or UIParent):GetEffectiveScale())
        end
    end
    frame = frame or UIParent
    -- textures and font strings have no scale of their own: use their frame's;
    -- font objects (GameTooltipText ...) have no frame at all: use UIParent
    if not frame.GetEffectiveScale then
        frame = (frame.GetParent and frame:GetParent()) or UIParent
        if not frame.GetEffectiveScale then frame = UIParent end
    end
    local s = frame:GetEffectiveScale()
    return 768 / (self.screenH * s)
end

-- Layout is designed on a 1080p screen. UIParent is always 768 units tall (the UI
-- scale is locked, see A:LockUIScale), so everything sized in units already looks
-- the same at any resolution. Sizes picked in screen pixels (raid button width,
-- meter size ...) are "design pixels": n pixels at 1080p, scaled to this screen
-- and rounded to whole pixels. 1px borders and gaps stay 1 real pixel.
A.DESIGN_H = 1080
function A:DP(n)
    if not n or n == 0 then return 0 end
    local h = self.screenH or (self.db and self:ScreenHeight()) or self.DESIGN_H
    local v = math.floor(math.abs(n) * h / self.DESIGN_H + 0.5)
    if v < 1 then v = 1 end
    return n < 0 and -v or v
end

-- UIParent is 768 units tall on every machine: Blizzard's "Use UI Scale" would
-- make it taller or shorter and move / resize the whole layout, so it stays off.
-- the layout was made at UIParent scale 0.9 (what the game picks with "Use UI
-- Scale" off): UIParent is 853.3 units tall on every machine.
A.UI_SCALE = 0.9
function A:LockUIScale()
    if not self.UI_SCALE then self:ScaleProbe() return end
    if GetCVar("useUiScale") ~= "0" then pcall(SetCVar, "useUiScale", "0") end
    if not InCombatLockdown() and math.abs((UIParent:GetScale() or 1) - self.UI_SCALE) > 0.0001 then
        UIParent:SetScale(self.UI_SCALE)
    end
    if not self.uiScaleHidden then
        self.uiScaleHidden = true
        for _, n in ipairs({ "VideoOptionsResolutionPanelUseUIScale", "VideoOptionsResolutionPanelUIScaleSlider" }) do
            local f = _G[n]
            if f then f:Hide(); f:SetParent(self.hider) end
        end
    end
end

-- what scale the game gives the UI on this machine (saved for the next build)
function A:ScaleProbe()
    if not self.db then return end
    local p = {
        useUiScale = GetCVar("useUiScale"), uiScale = GetCVar("uiScale"),
        gxResolution = GetCVar("gxResolution"), gxWindow = GetCVar("gxWindow"),
        scale = UIParent:GetScale(), eff = UIParent:GetEffectiveScale(),
        w = GetScreenWidth(), h = GetScreenHeight(),
        uiw = UIParent:GetWidth(), uih = UIParent:GetHeight(),
        screenH = self.screenH, px = self:PX(UIParent),
    }
    self.db.scaleProbe = p
    return p
end

-- round a length (in the frame's units) to whole screen pixels
function A:Snap(frame, v)
    local px = self:PX(frame)
    return math.floor(v / px + 0.5) * px
end

A.CHAT_W = 322
-- raid button width (in real pixels) so that 5 buttons + 4 gaps span the chat box,
-- and the chat box width (UIParent units) snapped to that same whole-pixel total
-- raid buttons are RAID_BTN_PX screen pixels wide (5 per row, 1px apart);
-- the chat box takes the same total width by default
A.RAID_BTN_PX = 63
function A:RaidChatWidths()
    local p = self:PX(UIParent)
    local w = self:DP(self.RAID_BTN_PX)
    return w, (5 * w + 4 + 1) * p   -- +1: the chat box reaches the raid frames' outer edge
end

-- sizes land on whole screen pixels, so 1px borders never fall between pixels
function A:Size(f, w, h)
    f:SetWidth(self:Snap(f, w))
    f:SetHeight(self:Snap(f, h or w))
end

-- Anchor a frame and nudge it so its edges sit on whole screen pixels. A frame
-- centred on the screen with an odd pixel width otherwise ends up half a pixel
-- off, and the GPU drops one of its 1px border lines (the "missing side").
function A:AlignPoint(frame, point, rel, relPoint, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, rel, relPoint, x, y)
    local l, t = frame:GetLeft(), frame:GetTop()
    if l and t then
        local dx, dy = self:Snap(frame, l) - l, self:Snap(frame, t) - t
        if math.abs(dx) > 0.001 or math.abs(dy) > 0.001 then
            frame:SetPoint(point, rel, relPoint, x + dx, y + dy)
        end
    end
end

-- Smooth fades, the same speed as the mouseover action bars: A:FadeTo(frame, alpha)
do
    local SPEED = 6   -- alpha per second (~0.17s for a full fade)
    local fading = {}
    local driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", A:PerfWrap("Fades", function(self, el)
        local any = false
        for f, target in pairs(fading) do
            local cur = f:GetAlpha()
            if cur < target then cur = math.min(target, cur + el * SPEED)
            else cur = math.max(target, cur - el * SPEED) end
            f:SetAlpha(cur)
            if cur == target then fading[f] = nil else any = true end
        end
        if not any then self:Hide() end
    end))
    function A:FadeTo(f, target)
        if not f then return end
        if fading[f] == target then return end
        if math.abs(f:GetAlpha() - target) < 0.001 then fading[f] = nil; f:SetAlpha(target) return end
        fading[f] = target
        driver:Show()
    end
end

-- Every frame skinned here shares one background (General > Background):
-- colour and opacity come from db.bg, and changing it repaints them all.
A.bgFrames = setmetatable({}, { __mode = "k" })

function A:ApplyBgColor()
    local c = self.db and self.db.bg
    if not c then return end
    local b = A.colors.backdrop
    b[1], b[2], b[3], b[4] = c.r, c.g, c.b, c.a
    -- dark mode health / cast fill takes the same colour (its own transparency stays)
    local d = self.db.darkColor
    if d then d.r, d.g, d.b = c.r, c.g, c.b end
end

function A:RefreshBackdrops()
    self:ApplyBgColor()
    local c = A.colors.backdrop
    for f in pairs(A.bgFrames) do
        if not f.atrCustomBg and f.SetBackdropColor then f:SetBackdropColor(c[1], c[2], c[3], c[4]) end
    end
    if self.chatBox then self.chatBox:SetBackdropColor(c[1], c[2], c[3], c[4]) end
    if self.Elv and self.Elv[1].UpdateFrameTemplates then self.Elv[1]:UpdateFrameTemplates() end
    if self.RefreshUnits and self.allFrames then self:RefreshUnits() end
end

function A:SetTemplate(f, alpha)
    local px = self:PX(f)   -- exactly 1 screen pixel edge, whatever the frame's scale
    f:SetBackdrop({
        bgFile = A.media.blank, edgeFile = A.media.blank, edgeSize = px,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local c = A.colors.backdrop
    f:SetBackdropColor(c[1], c[2], c[3], c[4])
    f:SetBackdropBorderColor(0, 0, 0, 1)
    A.bgFrames[f] = true
    if f.health then f.health.hcMode = nil end   -- ColorHealth paints the backdrop again
    f.huiBorder = nil                             -- and the raid border colour
end

-- 1px border made of 4 texture strips on a frame above `frame`
-- (does not cover the frame's own textures, unlike a backdrop)
local function Strip(c)
    local t = c:CreateTexture(nil, "OVERLAY")
    t:SetTexture(A.media.blank)
    return t
end
local function SetBorderColor(c, r, g, b, a)
    for i = 1, 4 do c[i]:SetVertexColor(r, g, b, a or 1) end
end
-- border thickness in pixels (0 hides it)
local function SetBorderSize(c, px)
    if px <= 0 then c:Hide() return end
    c:Show()
    local t = px * A:PX(c)
    c[1]:SetHeight(t); c[2]:SetHeight(t); c[3]:SetWidth(t); c[4]:SetWidth(t)
end
function A:CreateBorder(frame, r, g, b)
    if frame.atrBorder then return frame.atrBorder end
    local c = CreateFrame("Frame", nil, frame)
    c:SetAllPoints(frame)
    c:SetFrameLevel(frame:GetFrameLevel() + 2)
    local top, bot, left, right = Strip(c), Strip(c), Strip(c), Strip(c)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    c[1], c[2], c[3], c[4] = top, bot, left, right
    c.SetColor = SetBorderColor
    c.SetThickness = SetBorderSize
    c:SetThickness(1)
    c:SetColor(r or 0, g or 0, b or 0, 1)
    frame.atrBorder = c
    return c
end

-- font size of an element ("units", "raid", "actionbars", ...); falls back to the general size
A.fontKey = "general"
function A:FS(key)
    local db = self.db
    if not db then return 10 end
    return (key and db.fontSizes and db.fontSizes[key]) or db.fontSize or 10
end

function A:Font(parent, size, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    A:SetFontPx(fs, A.media.font, A:FS(A.fontKey), "OUTLINE")
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

function A:StatusBar(parent)
    local sb = CreateFrame("StatusBar", nil, parent)
    sb:SetStatusBarTexture(A.media.bar)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(1)
    sb.bg = sb:CreateTexture(nil, "BACKGROUND")
    sb.bg:SetTexture(A.media.blank)   -- flat: the missing-health colour shows exactly as picked
    local fill = sb:GetStatusBarTexture()
    if fill then
        sb.bg:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        sb.bg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
    else
        sb.bg:SetAllPoints(sb)
    end
    return sb
end

function A:Short(v)
    if not v then return "" end
    if v >= 1e9 then return format("%.1fB", v / 1e9)
    elseif v >= 1e6 then return format("%.1fM", v / 1e6)
    elseif v >= 1e3 then return format("%.1fK", v / 1e3)
    end
    return tostring(floor(v))
end

-- UTF-8 safe truncation
function A:Truncate(s, n)
    if not s then return "" end
    local len, i, bytes = 0, 1, #s
    while i <= bytes do
        len = len + 1
        if len > n then return s:sub(1, i - 1) end
        local c = s:byte(i)
        if c >= 240 then i = i + 4 elseif c >= 224 then i = i + 3 elseif c >= 192 then i = i + 2 else i = i + 1 end
    end
    return s
end

function A:ClassColor(class)
    local t = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = class and t[class]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

function A:UnitColor(unit)
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        return self:ClassColor(class)
    end
    if UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) then
        return 0.6, 0.6, 0.6
    end
    local r = UnitReaction(unit, "player")
    -- neutral: the same colour as neutral nameplates (Nameplates page)
    local np = self.db and self.db.nameplates
    if r == 4 and np and np.customNeutral and np.neutralColor then
        local n = np.neutralColor
        return n.r, n.g, n.b
    end
    local c = r and FACTION_BAR_COLORS[r]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

function A:Hex(r, g, b)
    return format("|cff%02x%02x%02x", floor(r * 255), floor(g * 255), floor(b * 255))
end

-- Health coloring shared by unit + raid frames. Runs on every health
-- event: the colours are only sent to the client when they change
-- (bar.hcMode etc.; A:UpdateAll clears them so settings changes repaint).
function A:ColorHealth(bar, unit)
    local connected = UnitIsConnected(unit)
    local dead = connected and UnitIsDeadOrGhost(unit) and true or false
    local mode, r, g, b
    if dead then mode = 1
    elseif not connected then mode = 2
    elseif self.db.classBars then
        mode = 3
        r, g, b = self:UnitColor(unit)
    else mode = 4 end
    if bar.hcMode == mode and (mode ~= 3 or (bar.hcR == r and bar.hcG == g and bar.hcB == b)) then return end
    bar.hcMode, bar.hcR, bar.hcG, bar.hcB = mode, r, g, b

    local fill = bar:GetStatusBarTexture()
    local bg = A.colors.backdrop          -- shared background colour + opacity
    local m = self.db.missingColor
    if mode == 1 then
        -- dead / ghost: the whole frame in the dead colour (frame background
        -- here, the power bar in UpdatePower)
        local dr, dg, db = self:DeadColor()
        bar:SetStatusBarColor(dr, dg, db)
        if fill then fill:SetAlpha(1) end
        bar.bg:SetVertexColor(dr, dg, db, 1)
    elseif mode == 2 then
        -- offline: the whole bar is the plain background (no "missing"
        -- part), slightly darker, so the frame reads as a calm empty panel
        bar:SetStatusBarColor(bg[1] * 0.6, bg[2] * 0.6, bg[3] * 0.6)
        if fill then fill:SetAlpha(math.max(bg[4], 0.85)) end
        bar.bg:SetVertexColor(bg[1] * 0.6, bg[2] * 0.6, bg[3] * 0.6, math.max(bg[4], 0.85))
    elseif mode == 3 then
        bar:SetStatusBarColor(r, g, b)
        if fill then fill:SetAlpha(1) end
        bar.bg:SetVertexColor(m.r, m.g, m.b, bg[4])    -- missing health
    else
        -- dark mode: the health part is the background colour itself
        bar:SetStatusBarColor(bg[1], bg[2], bg[3])
        if fill then fill:SetAlpha(bg[4]) end
        bar.bg:SetVertexColor(m.r, m.g, m.b, bg[4])    -- missing health
    end
    -- The bar covers the whole frame, so the frame's own background is left
    -- empty: otherwise it would sit under the missing health and make it opaque.
    local f = bar:GetParent()
    if f and f.SetBackdropColor and f.health == bar then
        f.atrCustomBg = true
        if dead then
            local dr, dg, db = self:DeadColor()
            f:SetBackdropColor(dr, dg, db, 1)   -- the 1px gaps between the bars too
        else
            f:SetBackdropColor(bg[1], bg[2], bg[3], 0)
        end
        -- the power bar follows when someone dies / comes back
        if f.power and f.wasDead ~= dead then
            f.wasDead = dead
            if self.UpdatePower then self:UpdatePower(f) end
        end
    end
end

------------------------------------------------------------------------
-- Right-click unit menu
------------------------------------------------------------------------
local dropdown = CreateFrame("Frame", "HUIDropDown", UIParent, "UIDropDownMenuTemplate")

local function InitMenu(self)
    local unit = self.unit
    if not unit then return end
    local menu, name
    if UnitIsUnit(unit, "player") then
        menu = "SELF"
    elseif UnitIsUnit(unit, "vehicle") then
        menu = "VEHICLE"
    elseif UnitIsUnit(unit, "pet") then
        menu = "PET"
    elseif UnitIsPlayer(unit) then
        name = GetUnitName(unit, true)
        if UnitInRaid(unit) then
            menu = "RAID_PLAYER"
        elseif UnitInParty(unit) then
            menu = "PARTY"
        else
            menu = "PLAYER"
        end
    else
        menu = "TARGET"
        name = RAID_TARGET_ICON
    end
    if menu then
        UnitPopup_ShowMenu(self, menu, unit, name)
    end
end
UIDropDownMenu_Initialize(dropdown, InitMenu, "MENU")

-- "Set Focus" in a unit menu opened by an addon frame calls a protected
-- function from addon code, which the game blocks ("HUI has been
-- blocked from an action..."). Take the focus entries out of the menus; focus
-- is set with Shift + left-click on any of our unit / raid frames instead.
do
    local DROP = { SET_FOCUS = true, CLEAR_FOCUS = true, LOCK_FOCUS_FRAME = true,
        UNLOCK_FOCUS_FRAME = true, MOVE_FOCUS_FRAME = true, LARGE_FOCUS = true, FOCUS_FRAME_BUFFS_ON_TOP = true }
    for _, menu in pairs(UnitPopupMenus or {}) do
        for i = #menu, 1, -1 do
            if DROP[menu[i]] then table.remove(menu, i) end
        end
    end
end

function A.ShowMenu(self, unit)
    unit = (type(unit) == "string" and unit) or self.unit or self:GetAttribute("unit")
    if not unit then return end
    dropdown.unit = unit
    ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
end

-- Shared secure click setup (call out of combat)
function A:SetupClicks(f)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "menu")
    f:SetAttribute("shift-type1", "focus")
    f.menu = A.ShowMenu
    f.showmenu = A.ShowMenu
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[f] = true
end

------------------------------------------------------------------------
-- Hide Blizzard frames
------------------------------------------------------------------------
A.hider = CreateFrame("Frame")
A.hider:Hide()

local function Kill(f)
    if not f then return end
    f:UnregisterAllEvents()
    f:Hide()
    f:SetParent(A.hider)
end

function A:HideBlizzard()
    -- Keep class resources visible before parent frames are hidden
    if RuneFrame then Kill(RuneFrame) end   -- death knight runes: hidden
    if TotemFrame then
        pcall(function()
            TotemFrame:SetParent(UIParent)
            TotemFrame:ClearAllPoints()
            TotemFrame:SetPoint("TOPLEFT", HUIPlayer, "BOTTOMLEFT", -2, -2)
        end)
    end

    Kill(PlayerFrame)
    Kill(TargetFrame)
    Kill(FocusFrame)
    Kill(TargetFrameToT)
    Kill(PetFrame)
    Kill(ComboFrame)
    if CastingBarFrame then
        CastingBarFrame:UnregisterAllEvents()
        CastingBarFrame:Hide()
        CastingBarFrame:SetParent(A.hider)
    end
    for i = 1, 4 do
        Kill(_G["PartyMemberFrame" .. i])
        Kill(_G["Boss" .. i .. "TargetFrame"])   -- HUI's own boss frames instead
    end
    if PartyMemberBackground then PartyMemberBackground:SetParent(A.hider) end
end

------------------------------------------------------------------------
-- Movers (unlock mode). Positions are saved in HUIDB and
-- restored every login.
------------------------------------------------------------------------
A.movers = {}
A.applyFuncs = {}

function A:GetPosition(key)
    return self.db.positions[key] or self.defaultPositions[key]
end

function A:ApplyPosition(key, frame)
    -- a layout (e.g. the healer layout) can place some frames itself
    local o = self.layoutOverride and self.layoutOverride[key]
    if o then o(frame) return end
    local p = self:GetPosition(key)
    if not p then return end
    if self.applyFuncs[key] then
        self.applyFuncs[key](p)
        return
    end
    -- offsets land on whole screen pixels so 1px borders stay crisp
    self:AlignPoint(frame, p[1], UIParent, p[2], self:Snap(frame, p[3]), self:Snap(frame, p[4]))
end

local function Rect(m)
    local s = m:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local l, b, r, t = m:GetLeft(), m:GetBottom(), m:GetRight(), m:GetTop()
    if not l or not b then return end
    -- size from the edges: a box pinned at two corners can keep a stale width
    local w = (r and r > l) and (r - l) or m:GetWidth()
    local h = (t and t > b) and (t - b) or m:GetHeight()
    return l * s, b * s, w * s, h * s
end

-- save a box's spot (left / bottom / size in UIParent units) against the
-- nearest screen corner or side, like the game does; shared by drag and nudge
local function SaveRect(m, L, B, w, h)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local mx, my = L + w / 2, B + h / 2
    local hp = mx < W / 3 and "LEFT" or (mx > W * 2 / 3 and "RIGHT" or "")
    local vp = my < H / 3 and "BOTTOM" or (my > H * 2 / 3 and "TOP" or "")
    local point = (vp .. hp ~= "") and (vp .. hp) or "CENTER"
    local ax = (hp == "LEFT" and L) or (hp == "RIGHT" and L + w - W) or (mx - W / 2)
    local ay = (vp == "BOTTOM" and B) or (vp == "TOP" and B + h - H) or (my - H / 2)
    local s = UIParent:GetEffectiveScale() / m:GetEffectiveScale()
    A.db.positions[m.key] = { point, point, ax * s, ay * s }
end

local function PlaceMover(m)
    local p = A:GetPosition(m.key)
    local f = m.frame
    m:SetScale(f:GetScale())
    m:SetWidth(math.max(f:GetWidth(), 20))
    m:SetHeight(math.max(f:GetHeight(), 14))
    m:ClearAllPoints()
    if A.layoutOverride and A.layoutOverride[m.key] then
        -- placed by a layout (healer layout, cast bar between player and
        -- target): the box covers the frame exactly. Its stored width can be
        -- stale when it is stretched between two anchors, so pin both corners.
        local l, r = f:GetLeft(), f:GetRight()
        if l and r and r > l then m:SetWidth(r - l) end   -- keeps the size while dragged
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        m:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    elseif A.applyFuncs[m.key] and not A.db.positions[m.key] then
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)   -- attached frames: show the box where the frame is
    else
        A:AlignPoint(m, p[1], UIParent, p[2], p[3], p[4])
    end
end

-- apply: optional custom positioning function(p) for frames that need it
function A:RegisterMover(key, frame, label, apply)
    if apply then self.applyFuncs[key] = apply end
    local m = CreateFrame("Button", nil, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    A:SetTemplate(m, 0.6)
    m.atrCustomBg = true
    m:SetBackdropColor(0.2, 0.45, 0.9, 0.40)
    m:SetBackdropBorderColor(0.4, 0.7, 1, 1)
    m.text = A:Font(m, 11, "CENTER")
    m.text:SetPoint("CENTER")
    m.text:SetText(label or key)
    m:Hide()
    m.frame, m.key = frame, key

    m:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.6, 1, 0.65) end)
    m:SetScript("OnLeave", function(self) A:PaintMover(self) end)
    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        A:SelectMover(self)
        A:BeginMoverDrag(self)
    end)
    m:SetScript("OnDragStop", function(self)
        A:EndMoverDrag(self)
    end)
    m:SetScript("OnClick", function(self, button)  -- left: select, right: reset this piece
        if InCombatLockdown() then return end
        if button == "LeftButton" then
            A:SelectMover(self)
            return
        end
        A.db.positions[self.key] = nil
        A:ApplyPosition(self.key, self.frame)
        PlaceMover(self)
    end)
    A.movers[key] = m
    m.PlaceMe = PlaceMover
    self:ApplyPosition(key, frame)
end

------------------------------------------------------------------------
-- Selected mover + arrow key nudging (unlock mode). The arrow keys are
-- bound only while unlocked and something is selected.
------------------------------------------------------------------------
function A:PaintMover(m)
    if m == self.selectedMover then
        m:SetBackdropColor(0.95, 0.75, 0.15, 0.45)
        m:SetBackdropBorderColor(1, 0.85, 0.2, 1)
    else
        m:SetBackdropColor(0.2, 0.45, 0.9, 0.40)
        m:SetBackdropBorderColor(0.4, 0.7, 1, 1)
    end
end

local nudgeOwner
local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

local function BindNudge(on)
    if InCombatLockdown() then return end
    if not nudgeOwner then
        nudgeOwner = CreateFrame("Frame")
        for dir in pairs(NUDGE) do
            local b = CreateFrame("Button", "HUINudge" .. dir, UIParent)
            b:SetScript("OnClick", function() A:NudgeMover(dir, IsShiftKeyDown()) end)
        end
    end
    ClearOverrideBindings(nudgeOwner)
    if on then
        for dir in pairs(NUDGE) do
            SetOverrideBindingClick(nudgeOwner, true, dir, "HUINudge" .. dir)
            SetOverrideBindingClick(nudgeOwner, true, "SHIFT-" .. dir, "HUINudge" .. dir)
        end
    end
end

local function SelectionText()
    local t = A.toolbar
    if not t or not t.sel then return end
    local m = A.selectedMover
    if m then
        local p = A:GetPosition(m.key)
        local x, y = p and p[3] or 0, p and p[4] or 0
        t.sel:SetText(format("|cffffd200%s|r  x %.0f  y %.0f", m.text:GetText() or m.key, x, y))
    else
        t.sel:SetText("|cff777777nothing selected|r")
    end
end

function A:RefreshSelection() SelectionText() end

function A:SelectMover(m)
    local old = self.selectedMover
    self.selectedMover = m
    if old and old ~= m then self:PaintMover(old) end
    if m then self:PaintMover(m) end
    BindNudge(m ~= nil and self.unlocked)
    SelectionText()
end

function A:NudgeMover(dir, big)
    local m = self.selectedMover
    if not m or not self.unlocked or InCombatLockdown() then return end
    local d = NUDGE[dir]
    -- where the box really is on screen (it may be attached to another frame),
    -- shifted by whole screen pixels, saved the same way as a drag
    local l, b, w, h = Rect(m)
    if not l then return end
    local px = self:PX(UIParent)
    local step = px * (big and 10 or 1)
    local L = math.floor((l + d[1] * step) / px + 0.5) * px
    local B = math.floor((b + d[2] * step) / px + 0.5) * px
    SaveRect(m, L, B, w, h)
    self:ApplyPosition(m.key, m.frame)
    PlaceMover(m)
    SelectionText()
end

------------------------------------------------------------------------
-- Grid + smart snapping (unlock mode). Dragging is done by hand so the box can
-- snap while it moves: its edges and centre line up with other boxes (also
-- side by side, 1px apart), the screen edges / centre and the grid lines.
-- Hold Alt to drag freely.
------------------------------------------------------------------------
local SNAP_PX = 8   -- snap distance in screen pixels

local grid
local function DrawGrid()
    local size = A.db.gridSize or 0
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("FULLSCREEN")
        grid:EnableMouse(false)
        grid.lines = {}
    end
    for _, t in ipairs(grid.lines) do t:Hide() end
    if size <= 0 or not A.unlocked then grid:Hide() return end
    grid:Show()
    local px = A:PX(UIParent)
    local step = size * px
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local n = 0
    local function line(vertical, pos)
        n = n + 1
        local t = grid.lines[n]
        if not t then t = grid:CreateTexture(nil, "BACKGROUND"); grid.lines[n] = t end
        t:ClearAllPoints()
        t:SetTexture(1, 1, 1, 0.07)
        if vertical then
            t:SetWidth(px)
            t:SetPoint("TOPLEFT", grid, "TOPLEFT", pos, 0)
            t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", pos, 0)
        else
            t:SetHeight(px)
            t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, pos)
            t:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", 0, pos)
        end
        t:Show()
    end
    -- lines start from the screen centre so the centre lines are part of the grid
    local cx, cy = math.floor(W / 2 / px + 0.5) * px, math.floor(H / 2 / px + 0.5) * px
    for x = cx % step, W, step do line(true, x) end
    for y = cy % step, H, step do line(false, y) end
end
A.DrawGrid = DrawGrid

-- snap guide lines (shown while dragging)
local snapV, snapH
local function SnapGuides()
    if snapV then return end
    snapV = UIParent:CreateTexture(nil, "OVERLAY")
    snapV:SetTexture(1, 0.82, 0.2, 0.8)
    snapH = UIParent:CreateTexture(nil, "OVERLAY")
    snapH:SetTexture(1, 0.82, 0.2, 0.8)
end

-- edges of a mover in UIParent units

local function Candidates(self)
    local px = A:PX(UIParent)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local gap = 1 * px
    local xs, ys = {}, {}
    -- screen: edges, 2px in from the edges, centre
    for _, v in ipairs({ 0, 2 * px, W - 2 * px, W, W / 2 }) do xs[#xs + 1] = { v } end
    for _, v in ipairs({ 0, 2 * px, H - 2 * px, H, H / 2 }) do ys[#ys + 1] = { v } end
    -- other boxes: edges, centres, and "next to it, 1px apart"
    for _, o in pairs(A.movers) do
        if o ~= self and o:IsShown() then
            local l, b, w, h = Rect(o)
            if l then
                xs[#xs + 1] = { l }; xs[#xs + 1] = { l + w }; xs[#xs + 1] = { l + w / 2 }
                xs[#xs + 1] = { l - gap, "right" }; xs[#xs + 1] = { l + w + gap, "left" }
                ys[#ys + 1] = { b }; ys[#ys + 1] = { b + h }; ys[#ys + 1] = { b + h / 2 }
                ys[#ys + 1] = { b - gap, "top" }; ys[#ys + 1] = { b + h + gap, "bottom" }
            end
        end
    end
    -- grid lines
    local size = A.db.gridSize or 0
    if size > 0 then
        local step = size * px
        local cx, cy = math.floor(W / 2 / px + 0.5) * px, math.floor(H / 2 / px + 0.5) * px
        for x = cx % step, W, step do xs[#xs + 1] = { x } end
        for y = cy % step, H, step do ys[#ys + 1] = { y } end
    end
    return xs, ys
end

-- best shift so one of the box's lines (start, end, middle) lands on a candidate
local function Best(pos, size, list, thr, lowSide, highSide)
    local best, bestD, at
    local feats = { { pos, lowSide }, { pos + size, highSide }, { pos + size / 2 } }
    for _, c in ipairs(list) do
        for _, f in ipairs(feats) do
            -- "next to" candidates only match the matching side of the box
            if not c[2] or c[2] == f[2] then
                local d = c[1] - f[1]
                if math.abs(d) < thr and (not bestD or math.abs(d) < math.abs(bestD)) then
                    bestD, at = d, c[1]
                end
            end
        end
    end
    return bestD or 0, at
end

function A:BeginMoverDrag(m)
    local l, b, w, h = Rect(m)
    if not l then m:StartMoving(); m.atrNative = true; return end
    local ues = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    m.drag = { offX = cx / ues - l, offY = cy / ues - b, w = w, h = h }
    m.drag.xs, m.drag.ys = Candidates(m)
    SnapGuides()
    m:SetScript("OnUpdate", function(self)
        local d = self.drag
        if not d then return end
        local px = A:PX(UIParent)
        local x, y = GetCursorPosition()
        local L, B = x / ues - d.offX, y / ues - d.offY
        snapV:Hide(); snapH:Hide()
        if A.db.snapping ~= false and not IsAltKeyDown() then
            local thr = SNAP_PX * px
            local dx, ax = Best(L, d.w, d.xs, thr, "left", "right")
            local dy, ay = Best(B, d.h, d.ys, thr, "bottom", "top")
            L, B = L + dx, B + dy
            if ax then
                snapV:ClearAllPoints(); snapV:SetWidth(px)
                snapV:SetPoint("TOPLEFT", UIParent, "TOPLEFT", ax, 0)
                snapV:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ax, 0)
                snapV:Show()
            end
            if ay then
                snapH:ClearAllPoints(); snapH:SetHeight(px)
                snapH:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, ay)
                snapH:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, ay)
                snapH:Show()
            end
        end
        -- whole screen pixels
        L, B = math.floor(L / px + 0.5) * px, math.floor(B / px + 0.5) * px
        d.L, d.B = L, B
        local s = UIParent:GetEffectiveScale() / self:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", L * s, B * s)
    end)
end

function A:EndMoverDrag(m)
    m:SetScript("OnUpdate", nil)
    if snapV then snapV:Hide(); snapH:Hide() end
    local point, relPoint, x, y
    if m.atrNative then
        m.atrNative = nil
        m:StopMovingOrSizing()
        if InCombatLockdown() then return end
        local _
        point, _, relPoint, x, y = m:GetPoint()
    else
        local d = m.drag
        m.drag = nil
        if not d or not d.L or InCombatLockdown() then return end
        SaveRect(m, d.L, d.B, d.w, d.h)
        A:ApplyPosition(m.key, m.frame)
        PlaceMover(m)
        if A.RefreshSelection then A:RefreshSelection() end
        return
    end
    -- mover shares the frame's scale, so offsets map 1:1
    A.db.positions[m.key] = { point, relPoint, x, y }
    A:ApplyPosition(m.key, m.frame)
    PlaceMover(m)
    if A.RefreshSelection then A:RefreshSelection() end
end

local GRID_SIZES = { 0, 8, 16, 24, 32, 48, 64 }

local function BuildToolbar()
    local t = CreateFrame("Frame", "HUIUnlockBar", UIParent)
    t:SetFrameStrata("FULLSCREEN_DIALOG")
    t:SetFrameLevel(50)
    A:SetTemplate(t, 0.95)
    A:Size(t, 440, 96)
    t:SetPoint("TOP", UIParent, "TOP", 0, -120)
    t:EnableMouse(true)
    t:SetMovable(true)
    t:RegisterForDrag("LeftButton")
    t:SetScript("OnDragStart", t.StartMoving)
    t:SetScript("OnDragStop", t.StopMovingOrSizing)
    local title = A:Font(t, 13, "CENTER")
    title:SetPoint("TOP", 0, -7)
    title:SetText("|cffc41f3bHUI|r unlock mode")
    local hint = A:Font(t, 11, "CENTER")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -2)
    hint:SetText("|cffaaaaaaDrag or click a box, then arrow keys (Shift = 10px)  -  right-click resets|r\n|cffaaaaaaBoxes snap to each other, the screen and the grid  -  hold Alt to move freely|r")
    t.sel = A:Font(t, 11, "CENTER")
    t.sel:SetPoint("TOP", hint, "BOTTOM", 0, -3)
    local lock = A:CreateButton(t, "Lock", 100, 18, function() A:Lock() end)
    lock:SetPoint("BOTTOMRIGHT", t, "BOTTOM", -4, 6)
    local reset = A:CreateButton(t, "Reset all", 100, 18, function() A:ResetPositions() end)
    reset:SetPoint("LEFT", lock, "RIGHT", 4, 0)
    local gridBtn, snapBtn
    local function Labels()
        local g = A.db.gridSize or 0
        gridBtn.text:SetText(g > 0 and ("Grid  " .. g .. "px") or "Grid  off")
        snapBtn.text:SetText(A.db.snapping ~= false and "Snap  on" or "Snap  off")
    end
    gridBtn = A:CreateButton(t, "Grid", 100, 18, function()
        local g, nxt = A.db.gridSize or 0, GRID_SIZES[1]
        for i, v in ipairs(GRID_SIZES) do if v == g then nxt = GRID_SIZES[i % #GRID_SIZES + 1] end end
        A.db.gridSize = nxt
        Labels(); DrawGrid()
    end)
    gridBtn:SetPoint("LEFT", reset, "RIGHT", 4, 0)
    snapBtn = A:CreateButton(t, "Snap", 100, 18, function()
        A.db.snapping = A.db.snapping == false
        Labels()
    end)
    snapBtn:SetPoint("RIGHT", lock, "LEFT", -4, 0)
    Labels()


    -- alignment guides
    local v = UIParent:CreateTexture(nil, "OVERLAY")
    v:SetTexture(1, 1, 1, 0.25)
    v:SetWidth(1)
    v:SetPoint("TOP", UIParent, "TOP")
    v:SetPoint("BOTTOM", UIParent, "BOTTOM")
    local h = UIParent:CreateTexture(nil, "OVERLAY")
    h:SetTexture(1, 1, 1, 0.25)
    h:SetHeight(1)
    h:SetPoint("LEFT", UIParent, "LEFT")
    h:SetPoint("RIGHT", UIParent, "RIGHT")
    t.guides = { v, h }
    return t
end

function A:Unlock()
    if InCombatLockdown() then return A:Print("can't unlock in combat.") end
    for _, m in pairs(self.movers) do
        PlaceMover(m)
        m:Show()
    end
    self.toolbar = self.toolbar or BuildToolbar()
    self.toolbar:Show()
    for _, g in ipairs(self.toolbar.guides) do g:Show() end
    self.unlocked = true
    DrawGrid()
    self:SelectMover(nil)
end

function A:Lock()
    if self.selectedMover then
        local m = self.selectedMover
        self.selectedMover = nil
        self:PaintMover(m)
    end
    BindNudge(false)
    for _, m in pairs(self.movers) do m:Hide() end
    if self.toolbar then
        self.toolbar:Hide()
        for _, g in ipairs(self.toolbar.guides) do g:Hide() end
    end
    if self.unlocked then A:Print("positions saved.") end
    self.unlocked = false
    DrawGrid()
end

function A:ResetPositions()
    if InCombatLockdown() then return A:Print("can't do that in combat.") end
    wipe(self.db.positions)
    for key, m in pairs(self.movers) do
        self:ApplyPosition(m.key or key, m.frame)
        if m:IsShown() then PlaceMover(m) end
    end
    A:Print("positions reset.")
end

-- lock automatically when combat starts
local combatLock = CreateFrame("Frame")
combatLock:RegisterEvent("PLAYER_REGEN_DISABLED")
combatLock:SetScript("OnEvent", function() if A.unlocked then A:Lock() end end)

------------------------------------------------------------------------
-- Small styled widgets (used by the config window and toolbar)
------------------------------------------------------------------------
A.accent = { 0.77, 0.12, 0.23 }

function A:CreateButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    self:Size(b, w, h)
    self:SetTemplate(b, 1)
    b.atrCustomBg = true
    b:SetBackdropColor(0, 0, 0, 1)
    b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    b.text = self:Font(b, 12, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetScript("OnEnter", function(self)
        local c = A.accent
        self:SetBackdropBorderColor(c[1], c[2], c[3])
    end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3) end)
    b:SetScript("OnClick", onClick)
    return b
end

function A:PlaceMoverPublic(m) if m.PlaceMe then m.PlaceMe(m) end end

------------------------------------------------------------------------
-- Merfin WeakAuras without ElvUI: Merfin's class packs call
-- Merfin.GetProfileResolution(), which lives in MerfinUI, and MerfinUI only
-- loads with ElvUI. Without it, give them the same answer MerfinUI's default
-- would (screen width 2530+ = "QUAD_HD", else "FULL_HD"). MerfinUI, when it
-- loads, replaces this with its own.
------------------------------------------------------------------------
Merfin = Merfin or {}
if not Merfin.GetProfileResolution then
    Merfin.GetProfileResolution = function()
        local res = ({ GetScreenResolutions() })[GetCurrentResolution()] or ""
        local w = tonumber(res:match("^(%d+)x")) or 1920
        return w >= 2530 and "QUAD_HD" or "FULL_HD"
    end
end
