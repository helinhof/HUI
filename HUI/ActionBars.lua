-- HUI - Action bars
-- Keeps Blizzard's own action buttons (so keybinds, paging, stances and vehicles keep
-- working), strips the art, restyles each button and lays them out in movable bars.

local A = HUI
local format = string.format
local floor, ipairs = math.floor, ipairs

A.bars = {}

local ART = {
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarPageNumber",
    "ActionBarUpButton", "ActionBarDownButton",
    "MainMenuXPBarTexture0", "MainMenuXPBarTexture1", "MainMenuXPBarTexture2", "MainMenuXPBarTexture3",
    "ReputationWatchBarTexture0", "ReputationWatchBarTexture1", "ReputationWatchBarTexture2", "ReputationWatchBarTexture3",
    "ReputationXPBarTexture0", "ReputationXPBarTexture1", "ReputationXPBarTexture2", "ReputationXPBarTexture3",
    "MainMenuBarMaxLevelBar", "MainMenuBarPerformanceBarFrame",
    "BonusActionBarTexture0", "BonusActionBarTexture1",
    "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
    "SlidingActionBarTexture0", "SlidingActionBarTexture1",
    "PossessBackground1", "PossessBackground2",
}

------------------------------------------------------------------------
-- Button skin
------------------------------------------------------------------------
local function Region(b, suffix) return _G[b:GetName() .. suffix] end

-- Skin approach (same idea as EllesmereUI): never put a backdrop on the button
-- itself (in 3.3.5 it draws over the BACKGROUND-layer icon). The icon fills the
-- button, a 1px border is drawn by 4 strips on a frame above it, and the dark
-- slot background lives on a separate frame behind the button.
local function HideMacro(b)
    local m = Region(b, "Name")
    if not m then return end
    if A.db.showMacro then m:Show() else m:Hide() end
end

function A:SkinActionButton(b)
    if not b then return end
    if not b.atrSkinned then
        b.atrSkinned = true
        local icon = Region(b, "Icon")
        if icon then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:ClearAllPoints()
            icon:SetAllPoints(b)
        end
        for _, s in ipairs({ "NormalTexture", "NormalTexture2", "Border", "FloatingBG" }) do
            local r = Region(b, s)
            if r then r:SetAlpha(0) end
        end
        -- Blizzard swaps the slot art back in (UI-Quickslot) on every update; keep it empty
        if b.SetNormalTexture then
            b:SetNormalTexture("")
            hooksecurefunc(b, "SetNormalTexture", function(self, tex)
                if tex ~= "" and not self.atrNT then
                    self.atrNT = true
                    self:SetNormalTexture("")
                    self.atrNT = nil
                end
            end)
        end

        local cd = Region(b, "Cooldown")
        if cd then
            cd:ClearAllPoints()
            cd:SetAllPoints(b)
        end
        local flash = Region(b, "Flash")
        if flash then
            flash:ClearAllPoints()
            flash:SetAllPoints(b)
            flash:SetTexture(0.9, 0.1, 0.1, 0.35)
        end
        for _, getter in ipairs({ "GetHighlightTexture", "GetPushedTexture", "GetCheckedTexture" }) do
            local t = b[getter] and b[getter](b)
            if t then
                if getter == "GetHighlightTexture" then t:SetTexture(1, 1, 1, 0.25)
                elseif getter == "GetPushedTexture" then t:SetTexture(1, 0.85, 0.2, 0.30)
                else t:SetTexture(0.3, 0.65, 1, 0.35) end
                t:ClearAllPoints()
                t:SetAllPoints(b)
            end
        end

        -- autocast markers on pet buttons are huge by default
        -- pet autocast corner marks: inside the slot, not hanging over its edge
        -- pet autocast: Blizzard's corner marks and sparkles are drawn for a 30px
        -- slot; replace them with our 1px border in gold while autocast is on
        local ac = Region(b, "AutoCastable")
        if ac then ac:SetTexture(nil); ac:SetAlpha(0) end
        -- Blizzard's green "equipped item" square is 62px whatever the button size;
        -- drop it and tint our own 1px border instead (see ActionButton_Update hook)
        local eq = Region(b, "Border")
        if eq then
            eq:SetTexture(nil)
            eq:SetAlpha(0)
            hooksecurefunc(eq, "Show", eq.Hide)
            eq:Hide()
        end
        local shine = Region(b, "AutoCast") or Region(b, "Shine")
        if shine then shine:SetAlpha(0) end

        self:CreateBorder(b, 0, 0, 0)

        -- dark slot behind the button (sibling frame, one level below)
        local bg = CreateFrame("Frame", nil, b:GetParent())
        bg:SetAllPoints(b)
        bg:SetFrameStrata(b:GetFrameStrata())
        bg:SetFrameLevel(math.max(b:GetFrameLevel() - 1, 0))
        local t = bg:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints(bg)
        t:SetTexture(0, 0, 0, 0.55)
        b:HookScript("OnShow", function() bg:Show() end)
        b:HookScript("OnHide", function() bg:Hide() end)
        if not b:IsShown() then bg:Hide() end
        b.atrBg = bg

        -- texts: keybind top right, charges / item count bottom right, macro name
        -- bottom left (stopping short of the count); each one line, clipped
        local fs = A:FS("actionbars")
        local hk = Region(b, "HotKey")
        if hk then
            A:SetFontPx(hk, self.media.font, fs - 1, "OUTLINE")
            hk:SetShadowOffset(0, 0)
            hk:ClearAllPoints()
            hk:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
            hk:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
            hk:SetHeight(fs + 1)
            hk:SetJustifyH("RIGHT")
            hk:SetJustifyV("TOP")
            -- full white keybinds (Blizzard uses grey); keep the red out-of-range tint
            hk:SetVertexColor(1, 1, 1)
            local busy
            hooksecurefunc(hk, "SetVertexColor", function(self, r, g, b)
                if busy then return end
                if r and g and b and math.abs(r - g) < 0.01 and math.abs(g - b) < 0.01 and r < 0.99 then
                    busy = true
                    self:SetVertexColor(1, 1, 1)
                    busy = false
                end
            end)
        end
        local count = Region(b, "Count")
        if count then
            A:SetFontPx(count, self.media.font, fs, "OUTLINE")
            count:SetShadowOffset(0, 0)
            count:ClearAllPoints()
            count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
            count:SetJustifyH("RIGHT")
        end
        local macro = Region(b, "Name")
        if macro then
            -- small, the full width of the button, cut to what fits (no "...")
            local mfs = math.max(7, fs - 3)
            A:SetFontPx(macro, self.media.font, mfs, "OUTLINE")
            macro:SetShadowOffset(0, 0)
            macro:ClearAllPoints()
            macro:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
            macro:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
            macro:SetHeight(mfs + 2)
            macro:SetJustifyH("LEFT")
            if not macro.huiFit then
                macro.huiFit = true
                local busy
                hooksecurefunc(macro, "SetText", function(self, text)
                    if busy or not text or text == "" then return end
                    local w = (self:GetWidth() or 0) + 0.5
                    if w <= 1 then return end
                    busy = true
                    -- measured on a hidden copy with no width limit
                    local m = b.huiMeasure
                    if not m then
                        m = b:CreateFontString(nil, "BACKGROUND")
                        m:SetPoint("TOPLEFT", b, "TOPLEFT")
                        m:Hide()
                        b.huiMeasure = m
                    end
                    m:SetFont(self:GetFont())
                    local t = text
                    m:SetText(t)
                    while #t > 1 and m:GetStringWidth() > w do
                        t = t:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")   -- drop the last letter
                        m:SetText(t)
                    end
                    if t ~= text then self:SetText(t) end
                    busy = false
                end)
                if macro:GetText() then macro:SetText(macro:GetText()) end
            end
        end
    end
    local hk = Region(b, "HotKey")
    if hk then hk:SetAlpha(self.db.showHotkeys and 1 or 0) end
    HideMacro(b)
    if b.atrBorder then b.atrBorder:SetThickness(self.db.abBorder) end
end

------------------------------------------------------------------------
-- Bars
------------------------------------------------------------------------
local function Buttons(prefix, n)
    local t = {}
    for i = 1, n do
        local b = _G[prefix .. i]
        if b then t[#t + 1] = b end
    end
    return t
end

-- Lays out a bar. BOTTOMLEFT anchors are used on purpose: Blizzard's
-- ShapeshiftBar_Update re-anchors with BOTTOMLEFT, so ours gets replaced cleanly.
function A:LayoutBar(bar)
    if InCombatLockdown() then
        self:RunOOC(function() A:LayoutBar(bar) end)
        return
    end
    local size = self:Snap(bar.holder, self.db.abSize * (bar.sizeMul or 1))   -- whole pixels
    local sp = self.db.abSpacing * self:PX(bar.holder)   -- spacing in real pixels
    local perRow = bar.perRow
    local n = bar.num
    local cols = bar.vertical and math.ceil(n / perRow) or math.min(n, perRow)
    local rows = bar.vertical and math.min(n, perRow) or math.ceil(n / perRow)
    local extra, extraPx = 0, 0
    -- bars beside the chat box take its height: button size from the rows that fit
    if bar.fitChat and self.chatBox and self.db.fitChatBars then
        local px = self:PX(bar.holder)
        local hpx = math.floor(self.chatBox:GetHeight() * self.chatBox:GetEffectiveScale()
            / bar.holder:GetEffectiveScale() / px + 0.5)
        local sizePx = math.floor((hpx - (rows - 1) * self.db.abSpacing) / rows)
        size = sizePx * px
        -- leftover pixels (0..rows-1) become 1px extra gaps between the lowest
        -- rows, so the block is exactly as tall as the chat and stays on whole pixels
        extra = math.max(0, math.min(rows - 1, hpx - rows * sizePx - (rows - 1) * self.db.abSpacing))
        extraPx = px
    end
    self:Size(bar.holder, cols * size + (cols - 1) * sp, rows * size + (rows - 1) * sp + extra * extraPx)

    for set = 1, #bar.sets do
        for i, b in ipairs(bar.sets[set]) do
            local col, row
            if bar.vertical then
                col, row = floor((i - 1) / perRow), (i - 1) % perRow
            else
                col, row = (i - 1) % perRow, floor((i - 1) / perRow)
            end
            self:SkinActionButton(b)
            -- Blizzard's bar frames can carry their own scale; convert our sizes
            -- (holder units) into the button's units so the block lines up exactly
            -- Blizzard's bar frames can carry their own scale; give each button the
            -- holder's scale so sizes and gaps land on whole screen pixels
            local parent = b:GetParent()
            local pe = parent and parent:GetEffectiveScale() or 1
            local want = bar.holder:GetEffectiveScale() / pe
            if math.abs(b:GetScale() - want) > 0.0001 then
                b:SetScale(want)
                if b.atrBorder then b.atrBorder:SetThickness(self.db.abBorder) end
            end
            b:SetWidth(size)
            b:SetHeight(size)
            b:ClearAllPoints()
            local r = rows - 1 - row
            b:SetPoint("BOTTOMLEFT", bar.holder, "BOTTOMLEFT",
                col * (size + sp), r * (size + sp) + math.min(r, extra) * extraPx)
        end
    end
end

function A:CreateBar(key, label, sets, opts)
    local holder = CreateFrame("Frame", "HUI" .. key, UIParent)
    local bar = {
        key = key, holder = holder, sets = sets,
        num = #sets[1], perRow = opts.perRow or 12, vertical = opts.vertical,
        sizeMul = opts.sizeMul, fitChat = opts.fitChat,
    }
    self.bars[key] = bar
    -- no plate behind the buttons: every gap (inside a bar, between rows and
    -- between bars) shows the same thing, so they all read as the same distance
    holder:SetFrameStrata("BACKGROUND")
    self:LayoutBar(bar)
    local apply
    if opts.attach then
        -- default position attached to another frame; a saved position wins
        apply = function(p)
            holder:ClearAllPoints()
            local ok = not A.db.positions[key] and opts.attach(holder)
            if not ok then
                A:AlignPoint(holder, p[1], UIParent, p[2], A:Snap(holder, p[3]), A:Snap(holder, p[4]))
            end
        end
    end
    self:RegisterMover(key, holder, label, apply)
    return bar
end

function A:RelayoutBars()
    self:UpdateBarDefaults()
    for _, bar in pairs(self.bars) do self:LayoutBar(bar) end
    -- main bar first: the others hang off it
    for _, key in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "PetBar", "StanceBar" }) do
        local bar = self.bars[key]
        if bar and not self.db.positions[key] and not InCombatLockdown() then self:ApplyPosition(key, bar.holder) end
    end
    if self.PlaceXPBars then self:PlaceXPBars() end
    -- the bag button sits beside bars 3 and 4 and takes their height
    if self.bagButton and not InCombatLockdown() then self:ApplyPosition("Bags", self.bagButton) end
end

------------------------------------------------------------------------
-- XP / reputation (thin bars under the main bar)
------------------------------------------------------------------------
-- XP bar at the top centre of the screen with "Level 28 - 39.6% (Rested: 2.6%)"
-- written on it; the reputation bar (when a faction is watched) sits under it
local XP_W, XP_H, REP_H = 316, 14, 8

local function XPText()
    local t = A.xpText
    if not t then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not max or max == 0 then t:SetText("") return end
    local s = format("Level %d - %.1f%%", UnitLevel("player"), cur / max * 100)
    local rest = GetXPExhaustion()
    if rest and rest > 0 then s = s .. format(" (Rested: %.1f%%)", rest / max * 100) end
    t:SetText(s)
end

local function RepText()
    local t = A.repText
    if not t then return end
    local name, standing, min, max, value = GetWatchedFactionInfo()
    if not name then t:SetText("") return end
    local label = _G["FACTION_STANDING_LABEL" .. standing] or ""
    local span = max - min
    t:SetText(format("%s - %s %.0f%%", name, label, span > 0 and (value - min) / span * 100 or 0))
end

function A:PlaceXPBars()
    local xp, rep = MainMenuExpBar, ReputationWatchBar
    local y = -2
    local function place(bar, h)
        bar:ClearAllPoints()
        bar:SetPoint("TOP", UIParent, "TOP", 0, A:Snap(UIParent, y) )
        bar:SetWidth(XP_W)
        bar:SetHeight(h)
        y = y - h - 3
    end
    if xp and xp:IsShown() then place(xp, XP_H) end
    if rep and rep:IsShown() then
        place(rep, (xp and xp:IsShown()) and REP_H or XP_H)
        if ReputationWatchStatusBar then
            ReputationWatchStatusBar:ClearAllPoints()
            ReputationWatchStatusBar:SetAllPoints(rep)
        end
    end
    XPText()
    RepText()
end

function A:BuildXPText()
    if self.xpText or not MainMenuExpBar then return end
    local function Overlay(bar, size)
        local o = CreateFrame("Frame", nil, bar)
        o:SetAllPoints(bar)
        o:SetFrameLevel(bar:GetFrameLevel() + 3)
        local t = o:CreateFontString(nil, "OVERLAY")
        A:SetFontPx(t, A.media.font, size, "OUTLINE")
        t:SetShadowOffset(0, 0)
        t:SetPoint("CENTER", 0, 0)
        return t
    end
    MainMenuExpBar:SetStatusBarColor(0.45, 0.33, 0.85)
    -- Blizzard recolours the bar blue/purple by rested state; keep ours
    local coloring
    hooksecurefunc(MainMenuExpBar, "SetStatusBarColor", function(bar)
        if coloring then return end
        coloring = true
        bar:SetStatusBarColor(0.45, 0.33, 0.85)
        coloring = false
    end)
    if ExhaustionLevelFillBar then ExhaustionLevelFillBar:SetVertexColor(0.3, 0.5, 1, 0.35) end
    if MainMenuBarExpText then MainMenuBarExpText:SetAlpha(0) end
    self.xpText = Overlay(MainMenuExpBar, 10)
    if ReputationWatchStatusBar then self.repText = Overlay(ReputationWatchStatusBar, 9) end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "UPDATE_FACTION" }) do
        ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", function()
        MainMenuExpBar:SetStatusBarColor(0.45, 0.33, 0.85)
        XPText()
        RepText()
    end)
end

local function StyleStatusBar(sb)
    if not sb or sb.atrBG then return end
    sb:SetStatusBarTexture(A.media.bar)
    local bg = CreateFrame("Frame", nil, sb)
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetFrameLevel(math.max(sb:GetFrameLevel() - 1, 0))
    A:SetTemplate(bg)
    sb.atrBG = bg
end

------------------------------------------------------------------------
-- Micro menu + bags
------------------------------------------------------------------------
function A:BuildMenus()
    -- the micro menu is gone: its buttons live in the minimap's middle-click list
    local MICRO = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
        "AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton", "PVPMicroButton",
        "LFDMicroButton", "MainMenuMicroButton", "HelpMicroButton" }
    local function hideMicro()
        for _, n in ipairs(MICRO) do
            local b = _G[n]
            if b and b:GetParent() ~= A.hider then b:SetParent(A.hider) end
        end
    end
    hideMicro()
    if MoveMicroButtons then hooksecurefunc("MoveMicroButtons", hideMicro) end
    if UpdateMicroButtons then hooksecurefunc("UpdateMicroButtons", hideMicro) end

    -- bags: one dark square instead of the five bag buttons + key ring.
    -- Left-click opens / closes the bags, right-click the key ring.
    for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
        "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton" }) do
        local f = _G[n]
        if f then f:SetParent(A.hider) end
    end
    local bags = CreateFrame("Button", "HUIBags", UIParent)
    local size = (self.db.abSize or 22) + 4
    self:Size(bags, size, size)
    bags:SetFrameStrata("MEDIUM")
    self:SetTemplate(bags)
    bags.icon = bags:CreateTexture(nil, "ARTWORK")
    bags.icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
    bags.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    bags.icon:SetPoint("TOPLEFT", A:PX(bags), -A:PX(bags))
    bags.icon:SetPoint("BOTTOMRIGHT", -A:PX(bags), A:PX(bags))
    bags:SetBackdropBorderColor(0, 0, 0)   -- coloured icon, black edge
    local hl = bags:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(bags.icon)
    hl:SetTexture(1, 1, 1, 0.12)
    bags.free = bags:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(bags.free, A.media.font, A:FS("actionbars"), "OUTLINE")
    bags.free:SetShadowOffset(0, 0)
    bags.free:SetPoint("BOTTOMRIGHT", -1, 2)
    local function Free()
        local free, total = 0, 0
        for b = 0, 4 do
            local n = GetContainerNumSlots(b) or 0
            total = total + n
            local f = GetContainerNumFreeSlots(b)
            free = free + (f or 0)
        end
        return free, total
    end
    local function UpdateFree()
        local free = Free()
        bags.free:SetText(free)
        if free == 0 then bags.free:SetTextColor(1, 0.3, 0.3) else bags.free:SetTextColor(1, 1, 1) end
    end
    bags:RegisterEvent("BAG_UPDATE")
    bags:RegisterEvent("PLAYER_ENTERING_WORLD")
    bags:SetScript("OnEvent", UpdateFree)
    bags:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bags:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ToggleKeyRing then ToggleKeyRing() end
        elseif A.ToggleBags then
            A:ToggleBags()
        elseif ToggleBackpack then
            ToggleBackpack()
        end
    end)
    bags:SetScript("OnEnter", function(self)
        local free, total = Free()
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Bags")
        GameTooltip:AddDoubleLine("Free slots", free .. " / " .. total, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine("Left-click: open / close", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: key ring", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    bags:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0)
        GameTooltip:Hide()
    end)
    -- default: 1px right of bars 3 and 4, as tall as the two of them (square);
    -- a position saved in unlock mode wins
    self:RegisterMover("Bags", bags, "Bags", function(p)
        bags:ClearAllPoints()
        local b3 = A.bars.Bar3 and A.bars.Bar3.holder
        local b4 = A.bars.Bar4 and A.bars.Bar4.holder
        local top, bottom = b4 and b4:GetTop(), b3 and b3:GetBottom()
        if A.db.positions.Bags or not (top and bottom) then
            A:AlignPoint(bags, p[1], UIParent, p[2], A:Snap(bags, p[3]), A:Snap(bags, p[4]))
            return
        end
        local s = bags:GetEffectiveScale()
        local h = (top * b4:GetEffectiveScale() - bottom * b3:GetEffectiveScale()) / s
        bags:SetWidth(h); bags:SetHeight(h)
        bags:SetPoint("BOTTOMLEFT", b3, "BOTTOMRIGHT", A:PX(bags), 0)
    end)
    self:ApplyPosition("Bags", bags)
    self.bagButton = bags

    -- only while the mouse is over it (setting: bag button on mouseover)
    local watch, acc = CreateFrame("Frame"), 0
    watch:SetScript("OnUpdate", A:PerfWrap("Action bars: watcher", function(_, el)
        acc = acc + el
        if acc < 0.1 then return end
        acc = 0
        local fade = A.db.menusMouseover and not A.unlocked
        A:FadeTo(bags, (not fade or MouseIsOver(bags)) and 1 or 0)
    end))
end

------------------------------------------------------------------------
-- Mouseover bars: a bar fades out until the mouse is over it.
-- Always fully shown while unlocked, in keybind mode or while dragging
-- a spell / item / macro on the cursor (so it can be dropped on a bar).
------------------------------------------------------------------------
A.BAR_KEYS = { "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "PetBar", "StanceBar" }
A.BAR_LABELS = {
    Bar1 = "Main bar", Bar2 = "Bar 2", Bar3 = "Bar 3", Bar4 = "Bar 4",
    Bar5 = "Bar 5 (beside chat)", PetBar = "Pet bar", StanceBar = "Stance bar",
}
local FADE_SPEED = 6   -- alpha per second (~0.17s full fade)

-- always on mouseover, whatever the mouseover settings say
A.BAR_ALWAYS_MOUSEOVER = { Bar5 = true, PetBar = true }

function A:BarMouseover(key)
    return self.BAR_ALWAYS_MOUSEOVER[key] or self.db.barMouseover[key] and true or false
end

function A:AllBarsMouseover()
    for _, k in ipairs(self.BAR_KEYS) do
        if not self.BAR_ALWAYS_MOUSEOVER[k] and not self.db.barMouseover[k] then return false end
    end
    return true
end

function A:SetAllBarsMouseover(on)
    for _, k in ipairs(self.BAR_KEYS) do
        if not self.BAR_ALWAYS_MOUSEOVER[k] then self.db.barMouseover[k] = on and true or false end
    end
end

local function BarHovered(bar)
    if MouseIsOver(bar.holder) then return true end
    for _, set in ipairs(bar.sets) do
        for _, b in ipairs(set) do
            if b:IsVisible() and MouseIsOver(b) then return true end
        end
    end
    return false
end

-- the plate shows only while the bar has buttons on screen
local function BarHasButtons(bar)
    for _, set in ipairs(bar.sets) do
        for _, b in ipairs(set) do
            if b:IsVisible() then return true end
        end
    end
    return false
end

local function SetBarAlpha(bar, a)
    if bar.bg then bar.bg:SetAlpha(a) end
    local bonusUp = bar.key == "Bar1" and BonusActionBarFrame and BonusActionBarFrame:IsShown()
    for s, set in ipairs(bar.sets) do
        for _, b in ipairs(set) do
            local ba = (bonusUp and s == 1) and 0 or a
            if b:GetAlpha() ~= ba then b:SetAlpha(ba) end
            if b.atrBg then b.atrBg:SetAlpha(a) end
            -- 3.3.5 cooldown spirals ignore the parent's alpha: hide them while faded out
            local cd = b.huiCD
            if cd == nil then cd = _G[b:GetName() .. "Cooldown"] or false; b.huiCD = cd end
            if cd then
                if a <= 0 then
                    if cd:IsShown() then cd:Hide(); cd.atrFaded = true end
                elseif cd.atrFaded then
                    cd.atrFaded = nil
                    if b.action and ActionButton_UpdateCooldown then
                        ActionButton_UpdateCooldown(b)
                    else
                        cd:Show()
                    end
                end
            end
        end
    end
end

local relayCheck
function A:BuildBarFader()
    local f = CreateFrame("Frame")
    local acc = 0
    local animating = false
    f:SetScript("OnUpdate", A:PerfWrap("Action bars: fading", function(_, el)
        acc = acc + el
        local check = acc >= 0.05
        -- between the 20-a-second checks only a bar that is fading needs work
        if not check and not animating then
            relayCheck = (relayCheck or 0) + el
            A.barBgAcc = (A.barBgAcc or 0) + el
            return
        end
        if check then acc = 0 end
        local db = A.db.barMouseover
        local forceShow = check and (A.unlocked or GetCursorInfo()
            or (HUIKeybindMode and HUIKeybindMode:IsShown()))
        animating = false
        -- whether a bar has buttons on screen: twice a second is plenty
        local bgAcc = (A.barBgAcc or 0) + el
        local bgCheck = bgAcc >= 0.5
        A.barBgAcc = bgCheck and 0 or bgAcc
        -- the game can rescale its own bar frames later (MainMenuBar ...):
        -- re-lay a bar whose buttons no longer match its holder's scale
        relayCheck = (relayCheck or 0) + el
        if relayCheck > 0.5 and not InCombatLockdown() then
            relayCheck = 0
            for _, bar in pairs(A.bars) do
                local b = bar.sets[1] and bar.sets[1][1]
                if b and math.abs(b:GetEffectiveScale() - bar.holder:GetEffectiveScale()) > 0.0001 then
                    A:LayoutBar(bar)
                end
            end
        end
        for key, bar in pairs(A.bars) do
            if bgCheck and bar.bg then
                local has = BarHasButtons(bar)
                if has ~= bar.bg:IsShown() then if has then bar.bg:Show() else bar.bg:Hide() end end
            end
            if db[key] or A.BAR_ALWAYS_MOUSEOVER[key] then
                if check then
                    bar.fadeTarget = (forceShow or BarHovered(bar)) and 1 or 0
                    -- keep new cooldown spirals hidden while the bar is faded out
                    if (bar.fadeAlpha or 1) <= 0 and bar.fadeTarget == 0 then SetBarAlpha(bar, 0) end
                end
                local target = bar.fadeTarget or 0
                local cur = bar.fadeAlpha or 1
                if cur ~= target then
                    -- (el since the last frame; between checks the accumulated wait)
                    if cur < target then cur = math.min(target, cur + el * FADE_SPEED)
                    else cur = math.max(target, cur - el * FADE_SPEED) end
                    bar.fadeAlpha = cur
                    SetBarAlpha(bar, cur)
                    if cur ~= target then animating = true end
                end
            elseif bar.fadeAlpha and bar.fadeAlpha ~= 1 then
                bar.fadeAlpha, bar.fadeTarget = 1, 1
                SetBarAlpha(bar, 1)
            end
        end
    end))
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function A:BuildActionBars()
    for _, n in ipairs(ART) do self:Remove(n) end
    -- the game's bar containers stay where Blizzard put them (the buttons are
    -- laid out on our own holders), invisible but still catching the mouse:
    -- a spell dropped on a button over one of them landed on the container
    -- instead. Only the buttons take the mouse.
    for _, n in ipairs({ "MainMenuBar", "MainMenuBarArtFrame", "BonusActionBarFrame",
        "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
        "ShapeshiftBarFrame", "PossessBarFrame", "PetActionBarFrame", "MultiCastActionBarFrame",
        "MainMenuBarOverlayFrame", "VehicleMenuBar" }) do
        local f = _G[n]
        if f and f.EnableMouse then f:EnableMouse(false) end
    end

    self:CreateBar("Bar1", "Main bar", { Buttons("ActionButton", 12), Buttons("BonusActionButton", 12) }, {})
    -- bars 2-4 hang off the main bar, exactly one button spacing apart, so every
    -- gap in the 2 x 24 block is the same (a saved position of their own still wins)
    local function gap(holder) return A.db.abSpacing * A:PX(holder) end
    local function main() return A.bars.Bar1 and A.bars.Bar1.holder end
    self:CreateBar("Bar3", "Bar 3", { Buttons("MultiBarBottomRightButton", 12) }, {
        attach = function(holder)
            if not main() then return false end
            holder:SetPoint("BOTTOMLEFT", main(), "BOTTOMRIGHT", gap(holder), 0)
            return true
        end,
    })
    self:CreateBar("Bar2", "Bar 2", { Buttons("MultiBarBottomLeftButton", 12) }, {
        attach = function(holder)
            if not main() then return false end
            holder:SetPoint("BOTTOMLEFT", main(), "TOPLEFT", 0, gap(holder))
            return true
        end,
    })
    self:CreateBar("Bar4", "Bar 4", { Buttons("MultiBarRightButton", 12) }, {
        attach = function(holder)
            local b2 = A.bars.Bar2 and A.bars.Bar2.holder
            if not b2 then return false end
            holder:SetPoint("BOTTOMLEFT", b2, "BOTTOMRIGHT", gap(holder), 0)
            return true
        end,
    })
    -- Bar 5: 2 x 5 block right of the chat box (buttons 11 and 12 are not used)
    for i = 11, 12 do
        local b = _G["MultiBarLeftButton" .. i]
        if b then b:SetParent(self.hider); b:Hide() end
    end
    self:CreateBar("Bar5", "Bar 5 (beside chat)", { Buttons("MultiBarLeftButton", 10) }, {
        perRow = 2, fitChat = true,
        attach = function(holder)
            if not A.chatBox then return false end
            holder:SetPoint("BOTTOMLEFT", A.chatBox, "BOTTOMRIGHT", math.max(A.db.abSpacing, 0) * A:PX(holder), 0)
            return true
        end,
    })
    -- pet bar: 2 x 5 block, mirrored on the right side
    self:CreateBar("PetBar", "Pet bar", { Buttons("PetActionButton", 10) }, {
        perRow = 2, fitChat = true,
        attach = function(holder)
            local px = A:PX(holder)
            local w = A.chatBox and A.chatBox:GetWidth()
            if not w then return false end
            -- mirrors the chat (same 2px edge margin, chat width + 1px in from the right)
            A:AlignPoint(holder, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
                -(A:Snap(holder, w) + (2 + math.max(A.db.abSpacing, 0)) * px), 2 * px)
            return true
        end,
    })
    self:CreateBar("StanceBar", "Stance bar", { Buttons("ShapeshiftButton", 10) }, { perRow = 10, sizeMul = 0.85 })

    -- main bar: empty slots stay on screen (dark slot + border) like bars 2-5.
    -- Blizzard hides an empty ActionButton unless its "showgrid" count is above
    -- 0 (bars 2-5 get that from "Always show action bars"); with a base count
    -- of 1, dragging a spell (+1 / -1) never drops it back to 0. Secure
    -- attribute: only out of combat, so a /reload in combat does it afterwards.
    local function MainGrid()
        if InCombatLockdown() then return false end
        for i = 1, 12 do
            local b = _G["ActionButton" .. i]
            if b then
                if (b:GetAttribute("showgrid") or 0) < 1 then b:SetAttribute("showgrid", 1) end
                if not b:IsShown() then b:Show() end
            end
        end
        return true
    end
    if not MainGrid() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self)
            if MainGrid() then self:UnregisterAllEvents() end
        end)
    end

    -- the stance/form bar (BonusActionBar) sits exactly on top of the main bar:
    -- keep it above, and fade the main buttons while it's up
    if BonusActionBarFrame then
        for i = 1, 12 do
            local main, bonus = _G["ActionButton" .. i], _G["BonusActionButton" .. i]
            if main and bonus then bonus:SetFrameLevel(main:GetFrameLevel() + 3) end
        end
        local function fade(alpha)
            for i = 1, 12 do
                local b = _G["ActionButton" .. i]
                if b then b:SetAlpha(alpha) end
            end
        end
        BonusActionBarFrame:HookScript("OnShow", function() fade(0) end)
        BonusActionBarFrame:HookScript("OnHide", function()
            local bar = A.bars.Bar1
            fade(bar and bar.fadeAlpha or 1)
        end)
        if BonusActionBarFrame:IsShown() then fade(0) end
    end

    if ShapeshiftBar_Update then
        hooksecurefunc("ShapeshiftBar_Update", function()
            if A.bars.StanceBar then A:LayoutBar(A.bars.StanceBar) end
        end)
    end
    -- shorter keybind labels: s-1, c-2, a-Q, M3, MU / MD, N5 ...
    local SHORT = {
        { "SHIFT%-", "s" }, { "CTRL%-", "c" }, { "ALT%-", "a" },
        { "Middle Mouse", "M3" }, { "Mouse Button ", "M" }, { "Mouse Wheel Up", "MU" },
        { "Mouse Wheel Down", "MD" }, { "Num Pad ", "N" }, { "Spacebar", "Spc" },
        { "Page Up", "PU" }, { "Page Down", "PD" }, { "Insert", "Ins" }, { "Delete", "Del" },
        { "Home", "Hm" }, { "Backspace", "Bs" }, { "Capslock", "Cap" },
        { "s%-", "s" }, { "c%-", "c" }, { "a%-", "a" },
    }
    local function ShortKey(hk)
        local t = hk and hk:GetText()
        if not t or t == "" or t == RANGE_INDICATOR then return end
        for _, r in ipairs(SHORT) do t = t:gsub(r[1], r[2]) end
        if t ~= hk:GetText() then hk:SetText(t) end
    end
    if ActionButton_UpdateHotkeys then
        hooksecurefunc("ActionButton_UpdateHotkeys", function(self)
            ShortKey(_G[self:GetName() .. "HotKey"])
        end)
    end
    for _, bar in pairs(self.bars) do
        for _, set in ipairs(bar.sets) do
            for _, b in ipairs(set) do ShortKey(_G[b:GetName() .. "HotKey"]) end
        end
    end

    if ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(self)
            local nt = _G[self:GetName() .. "NormalTexture"]
            if nt then nt:SetAlpha(0) end
            if self.atrSkinned then HideMacro(self) end
            -- a slot that turned empty while it was flashing (Attack / Auto
            -- Shot moved away, or the bar paged in a form change) keeps
            -- flashing: Blizzard only stops the flash on slots with an action
            if not (self.action and HasAction(self.action)) and self.flashing == 1 and ActionButton_StopFlash then
                ActionButton_StopFlash(self)
            end
            if self.atrBorder then
                if self.action and IsEquippedAction(self.action) then
                    self.atrBorder:SetColor(0.2, 0.85, 0.2, 1)
                else
                    self.atrBorder:SetColor(0, 0, 0, 1)
                end
            end
        end)
    end
    if PetActionBar_Update then
        hooksecurefunc("PetActionBar_Update", function()
            for i = 1, 10 do
                local nt = _G["PetActionButton" .. i .. "NormalTexture2"] or _G["PetActionButton" .. i .. "NormalTexture"]
                if nt then nt:SetAlpha(0) end
                local b = _G["PetActionButton" .. i]
                if b and b.atrBorder then
                    local _, _, _, _, _, _, autoOn = GetPetActionInfo(i)
                    if autoOn then b.atrBorder:SetColor(1, 0.82, 0, 1) else b.atrBorder:SetColor(0, 0, 0, 1) end
                end
            end
        end)
    end

    -- XP / rep
    StyleStatusBar(MainMenuExpBar)
    StyleStatusBar(ReputationWatchStatusBar)
    if ExhaustionTick then ExhaustionTick:SetAlpha(0) end
    if MainMenuBarExpText then A:SetFontPx(MainMenuBarExpText, self.media.font, A:FS("actionbars"), "OUTLINE") end
    self:BuildXPText()
    self:PlaceXPBars()
    if ReputationWatchBar_Update then hooksecurefunc("ReputationWatchBar_Update", function() A:PlaceXPBars() end) end
    if MainMenuExpBar then
        MainMenuExpBar:HookScript("OnShow", function() A:PlaceXPBars() end)
        MainMenuExpBar:HookScript("OnHide", function() A:PlaceXPBars() end)
    end

    self:BuildMenus()
    self:BuildBarFader()

    -- Blizzard re-anchors some of this when bars are toggled; put ours back
    if UIParent_ManageFramePositions then
        hooksecurefunc("UIParent_ManageFramePositions", function()
            if InCombatLockdown() then return end
            A:PlaceXPBars()
        end)
    end
end

------------------------------------------------------------------------
-- Quick keybind mode: hover an action button and press a key to bind it.
-- ESC on a hovered button clears its keys; ESC elsewhere (or "Done") leaves the mode.
------------------------------------------------------------------------
local BIND_PREFIX = {
    { "^ActionButton(%d+)$", "ACTIONBUTTON" },
    { "^BonusActionButton(%d+)$", "ACTIONBUTTON" },
    { "^MultiBarBottomLeftButton(%d+)$", "MULTIACTIONBAR1BUTTON" },
    { "^MultiBarBottomRightButton(%d+)$", "MULTIACTIONBAR2BUTTON" },
    { "^MultiBarRightButton(%d+)$", "MULTIACTIONBAR3BUTTON" },
    { "^MultiBarLeftButton(%d+)$", "MULTIACTIONBAR4BUTTON" },
    { "^ShapeshiftButton(%d+)$", "SHAPESHIFTBUTTON" },
    { "^PetActionButton(%d+)$", "BONUSACTIONBUTTON" },
}
local IGNORE_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true,
}

local function BindingCommand(b)
    local name = b and b:GetName()
    if not name then return end
    for _, p in ipairs(BIND_PREFIX) do
        local n = name:match(p[1])
        if n then return p[2] .. n end
    end
end

local kb   -- the keybind-mode frame

local function KeysText(cmd)
    local keys = { GetBindingKey(cmd) }
    if #keys == 0 then return "|cff888888not bound|r" end
    for i, k in ipairs(keys) do keys[i] = GetBindingText(k, "KEY_") end
    return "|cff33ff66" .. table.concat(keys, ", ") .. "|r"
end

local function UpdateInfo()
    local b = kb.hover
    local cmd = BindingCommand(b)
    if cmd then
        kb.info:SetText((b:GetName() or "") .. ":  " .. KeysText(cmd))
        kb.mark:ClearAllPoints()
        kb.mark:SetAllPoints(b)
        kb.mark:Show()
    else
        kb.info:SetText("|cffaaaaaaHover an action button|r")
        kb.mark:Hide()
    end
end

local function OnKey(self, key)
    if IGNORE_KEYS[key] then return end
    local cmd = BindingCommand(kb.hover)
    if key == "ESCAPE" then
        if cmd and MouseIsOver(kb.hover) then
            for _, k in ipairs({ GetBindingKey(cmd) }) do SetBinding(k) end
            SaveBindings(GetCurrentBindingSet())
            UpdateInfo()
        else
            A:StopKeybindMode()
        end
        return
    end
    if not cmd or not MouseIsOver(kb.hover) then return end
    local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
    SetBinding(combo, cmd)
    SaveBindings(GetCurrentBindingSet())
    UpdateInfo()
end

local function BuildKeybindFrame()
    kb = CreateFrame("Frame", "HUIKeybindMode", UIParent)
    kb:SetFrameStrata("FULLSCREEN_DIALOG")
    A:SetTemplate(kb, 0.95)
    A:Size(kb, 340, 64)
    kb:SetPoint("TOP", UIParent, "TOP", 0, -120)
    kb:EnableKeyboard(true)
    kb:SetScript("OnKeyDown", OnKey)
    kb:Hide()

    local title = A:Font(kb, 12, "CENTER")
    title:SetPoint("TOP", 0, -6)
    title:SetText("|cffc41f3bHUI|r keybind mode")
    local hint = A:Font(kb, 10, "CENTER")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -2)
    hint:SetText("|cffaaaaaaHover a button + press a key.  ESC on a button clears it.|r")
    kb.info = A:Font(kb, 10, "CENTER")
    kb.info:SetPoint("TOP", hint, "BOTTOM", 0, -4)
    local done = A:CreateButton(kb, "Done", 60, 16, function() A:StopKeybindMode() end)
    done:SetPoint("BOTTOMRIGHT", -4, 4)

    -- highlight on the hovered button
    kb.mark = CreateFrame("Frame", nil, UIParent)
    kb.mark:SetFrameStrata("FULLSCREEN_DIALOG")
    local t = kb.mark:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(kb.mark)
    t:SetTexture(0.3, 0.65, 1, 0.35)
    A:CreateBorder(kb.mark, 0.3, 0.65, 1)
    kb.mark:Hide()

    -- remember which action button the mouse is over
    for _, bar in pairs(A.bars) do
        for _, set in ipairs(bar.sets) do
            for _, b in ipairs(set) do
                b:HookScript("OnEnter", function(self)
                    if kb:IsShown() then
                        kb.hover = self
                        UpdateInfo()
                    end
                end)
            end
        end
    end
end

function A:StartKeybindMode()
    if InCombatLockdown() then return A:Print("can't change keybinds in combat.") end
    if not next(self.bars) then return A:Print("action bars module is disabled.") end
    if not kb then BuildKeybindFrame() end
    kb.hover = nil
    UpdateInfo()
    kb:Show()
end

function A:StopKeybindMode()
    if not kb then return end
    kb:Hide()
    kb.mark:Hide()
    kb.hover = nil
end

local kbCombat = CreateFrame("Frame")
kbCombat:RegisterEvent("PLAYER_REGEN_DISABLED")
kbCombat:SetScript("OnEvent", function() A:StopKeybindMode() end)


------------------------------------------------------------------------
-- Cooldown numbers, centred on every action / pet / stance button.
-- 3.3.5 has none built in: hook the cooldown spiral and count down ourselves.
------------------------------------------------------------------------
do
    local active = {}
    local function IsBarButton(name)
        return name and (name:find("^ActionButton%d") or name:find("^MultiBar") or name:find("^BonusActionButton%d")
            or name:find("^PetActionButton%d") or name:find("^ShapeshiftButton%d"))
    end
    local function Fmt(t)
        if t >= 3600 then return format("%dh", math.ceil(t / 3600)) end
        if t >= 60 then return format("%dm", math.ceil(t / 60)) end
        return format("%d", math.ceil(t))
    end
    local driver = CreateFrame("Frame")
    local acc = 0
    driver:SetScript("OnUpdate", A:PerfWrap("Action bars: cooldown numbers", function(self, el)
        acc = acc + el
        if acc < 0.1 then return end
        acc = 0
        local now, any = GetTime(), false
        for cd, o in pairs(active) do
            local left = o.start + o.duration - now
            if left <= 0 or not cd:IsVisible() then
                A.SetTxt(o.text, "")
                o.sec = nil
                if left <= 0 then active[cd] = nil end
                if left > 0 then any = true end
            else
                any = true
                -- a new string only when the shown number changes
                local sec = math.ceil(left)
                if o.sec ~= sec then
                    o.sec = sec
                    A.SetTxt(o.text, Fmt(left))
                end
                local red = left < 5
                if o.red ~= red then
                    o.red = red
                    if red then o.text:SetTextColor(1, 0.3, 0.3) else o.text:SetTextColor(1, 1, 1) end
                end
            end
        end
        if not any then self:Hide() end
    end))
    driver:Hide()

    local function Overlay(cd)
        local o = cd.atrCD
        if o then return o end
        local b = cd:GetParent()
        o = CreateFrame("Frame", nil, cd)
        o:SetAllPoints(b)
        o:SetFrameLevel(cd:GetFrameLevel() + 2)
        o.text = o:CreateFontString(nil, "OVERLAY")
        o.text:SetPoint("CENTER", 1, 0)
        o.text:SetJustifyH("CENTER")
        cd.atrCD = o
        return o
    end

    hooksecurefunc("CooldownFrame_SetTimer", A:PerfWrap("Action bars: cooldown numbers (hook)", function(cd, start, duration, enable)
        if not A.db or A.db.cdNumbers == false or not cd then return end
        -- this hook runs for every cooldown spiral in the UI: whether it sits
        -- on a bar button is worked out once per spiral
        local isBar = cd.huiIsBar
        if isBar == nil then
            local b = cd:GetParent()
            isBar = (b and IsBarButton(b:GetName())) and true or false
            cd.huiIsBar = isBar
        end
        if not isBar then return end
        local b = cd:GetParent()
        local o = Overlay(cd)
        local size = math.max(8, math.floor((b:GetWidth() or 22) * 0.5 + 0.5))
        if o.size ~= size then
            o.size = size
            A:SetFontPx(o.text, A.media.font, size, "OUTLINE")
            o.text:SetShadowOffset(0, 0)
        end
        if enable and enable ~= 0 and start and start > 0 and duration and duration > 1.5 then
            o.start, o.duration = start, duration
            active[cd] = o
            driver:Show()
        else
            active[cd] = nil
            A.SetTxt(o.text, "")
            o.sec = nil
        end
    end))
end
