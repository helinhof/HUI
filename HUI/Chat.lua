-- HUI - Chat
-- One dark box (2px from the bottom-left corner by default): a header strip with
-- the tabs on top, chat text below. The edit box opens over the header strip.
-- Text uses the game's chat font at size 10.

local A = HUI
local format = string.format

local BOX_W, BOX_H, HEADER, CLBAR = 322, 180, 20, 18

-- chat text: the game chat font, size from settings, soft shadow instead of outline
local function ChatFont(cf, size)
    size = size or A.db.chatFontSize
    A:SetFontPx(cf, A.media.chatFont, size, "")
    cf:SetShadowOffset(1, -1)
    cf:SetShadowColor(0, 0, 0, 1)
end

function A:SetChatFontSize(size)
    self.db.chatFontSize = size
    for i = 1, (NUM_CHAT_WINDOWS or 7) do
        local cf = _G["ChatFrame" .. i]
        if cf then
            -- store it in the game's own chat settings too, so it isn't restored to 14/16 later
            if SetChatWindowSize then pcall(SetChatWindowSize, i, size) end
            ChatFont(cf, size)
        end
    end
end

local function NoShow(f)
    if not f then return end
    f:Hide()
    f.Show = f.Hide
end

local function OnWheel(self, d)
    if d > 0 then
        if IsShiftKeyDown() then self:ScrollToTop()
        elseif IsControlKeyDown() then for _ = 1, 3 do self:ScrollUp() end
        else self:ScrollUp() end
    else
        if IsShiftKeyDown() then self:ScrollToBottom()
        elseif IsControlKeyDown() then for _ = 1, 3 do self:ScrollDown() end
        else self:ScrollDown() end
    end
end

-- Tabs: compact labels sized to their text, muted grey; the selected tab is
-- white with an accent underline, a tab with new messages turns accent coloured.
local TAB_PAD = 7
local function TabText(tab)
    return _G[tab:GetName() .. "Text"] or (tab.GetFontString and tab:GetFontString())
end

-- short labels on the header; the chat windows keep their full names
local SHORT_TAB = { ["Whisper"] = "W", ["Raid/Party"] = "Raid" }
local function ShortTab(tab)
    if tab.atrShorting then return end
    local full = tab.GetText and tab:GetText()
    local short = full and SHORT_TAB[full]
    if short then
        tab.atrShorting = true
        tab:SetText(short)
        tab.atrShorting = nil
    end
end

local function TabIsSelected(tab)
    local cf = tab.huiCF
    if cf == nil then
        cf = _G[tab:GetName():gsub("Tab$", "")] or false
        tab.huiCF = cf
    end
    if not cf then return false end
    local dock = GENERAL_CHAT_DOCK
    if dock and dock.selected then return dock.selected == cf end
    return cf == SELECTED_CHAT_FRAME
end

-- the colour each tab should show; only touch the text when it changes
local function SetTabColor(tab, text, r, g, b)
    if tab.huiR == r and tab.huiG == g and tab.huiB == b then return end
    tab.huiR, tab.huiG, tab.huiB = r, g, b
    tab.atrPainting = true
    text:SetTextColor(r, g, b)
    tab.atrPainting = nil
end

local function PaintTab(tab)
    if not tab or not tab.atrSkinned then return end
    local text = TabText(tab)
    if not text then return end
    local sel = TabIsSelected(tab)
    if tab.atrAlert and not sel then
        local c = A.accent
        SetTabColor(tab, text, math.min(c[1] + 0.25, 1), math.min(c[2] + 0.25, 1), math.min(c[3] + 0.25, 1))
    elseif sel then
        SetTabColor(tab, text, 1, 1, 1)
    elseif tab.atrHover then
        SetTabColor(tab, text, 0.85, 0.85, 0.88)
    else
        SetTabColor(tab, text, 0.55, 0.55, 0.6)
    end
end
A.PaintChatTab = PaintTab

local function PaintAllTabs()
    for i = 1, 20 do PaintTab(_G["ChatFrame" .. i .. "Tab"]) end
end

local function SkinTab(tab)
    if not tab or tab.atrSkinned then return end
    tab.atrSkinned = true
    A:HideRegions(tab)
    if tab.GetHighlightTexture and tab:GetHighlightTexture() then tab:GetHighlightTexture():SetAlpha(0) end
    local glow = _G[tab:GetName() .. "Glow"] or tab.glow
    if glow then glow:SetTexture(nil) end
    tab:SetHeight(HEADER)

    local hover = tab:CreateTexture(nil, "BACKGROUND")
    hover:SetPoint("TOPLEFT", 1, 0)
    hover:SetPoint("BOTTOMRIGHT", -1, 0)
    hover:SetTexture(1, 1, 1, 0.05)
    hover:Hide()
    local line = tab:CreateTexture(nil, "OVERLAY")
    line:SetTexture(A.accent[1], A.accent[2], A.accent[3], 1)
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", 4, 0)
    line:SetPoint("BOTTOMRIGHT", -4, 0)
    line:Hide()
    tab.atrLine = line
    tab:HookScript("OnEnter", function(self) self.atrHover = true; hover:Show(); PaintTab(self) end)
    tab:HookScript("OnLeave", function(self) self.atrHover = nil; hover:Hide(); PaintTab(self) end)

    hooksecurefunc(tab, "SetText", ShortTab)
    ShortTab(tab)
    local text = TabText(tab)
    if text then
        A:SetFontPx(text, A.media.chatFont, A.db.chatFontSize, "")
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        -- Blizzard's template puts the text 5px below centre; centre it in the header
        local centering
        local function center()
            if centering then return end
            centering = true
            text:ClearAllPoints()
            text:SetPoint("CENTER", tab, "CENTER", 0, 1)
            centering = false
        end
        center()
        hooksecurefunc(text, "SetPoint", center)
        -- Blizzard recolours the text on every update; put ours back
        hooksecurefunc(text, "SetTextColor", function(_, r, g, b)
            if tab.atrPainting or not tab.huiR then return end
            if r == tab.huiR and g == tab.huiG and b == tab.huiB then return end
            tab.atrPainting = true
            text:SetTextColor(tab.huiR, tab.huiG, tab.huiB)
            tab.atrPainting = nil
        end)
    end
    PaintTab(tab)
end

-- width that fits the label (Blizzard stretches docked tabs to fill the row)
local function FitTab(tab)
    local text = tab and TabText(tab)
    if not text then return end
    local w = math.floor((text:GetStringWidth() or 20) + TAB_PAD * 2 + 0.5)
    if math.abs((tab:GetWidth() or 0) - w) > 0.5 then tab:SetWidth(w) end
end

local function SkinOverflow(ob)
    if not ob or ob.atrSkinned then return end
    ob.atrSkinned = true
    A:HideRegions(ob)
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local t = ob[g] and ob[g](ob)
        if t then t:SetAlpha(0) end
    end
    local t = ob:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(t, A.media.chatFont, 14, "")
    t:SetShadowOffset(1, -1)
    t:SetPoint("CENTER", 0, 0)
    t:SetText(">")
    t:SetTextColor(0.55, 0.55, 0.6)
    ob:HookScript("OnEnter", function() t:SetTextColor(1, 1, 1) end)
    ob:HookScript("OnLeave", function() t:SetTextColor(0.55, 0.55, 0.6) end)
end

local function SkinEditBox(eb)
    if not eb or eb.atrSkinned then return end
    eb.atrSkinned = true
    A:HideRegions(eb)
    A:SetTemplate(eb, 1)
    -- solid black while typing so the tabs underneath don't show through
    eb.atrCustomBg = true
    eb:SetBackdropColor(0, 0, 0, 1)
    eb:HookScript("OnShow", function(self) self:SetBackdropColor(0, 0, 0, 1) end)
    eb:SetAltArrowKeyMode(false)
    local placing
    local function place()
        if placing then return end
        placing = true
        eb:ClearAllPoints()
        if A.db.chatEditBox == "BOTTOM" and A.chatBox then
            eb:SetPoint("TOPLEFT", A.chatBox, "BOTTOMLEFT", 0, -A:PX(eb))
            eb:SetPoint("TOPRIGHT", A.chatBox, "BOTTOMRIGHT", 0, -A:PX(eb))
            eb:SetHeight(HEADER + 2)
        else
            eb:SetAllPoints(A.chatHeader)
        end
        placing = false
    end
    eb.atrPlace = place
    place()
    hooksecurefunc(eb, "SetPoint", place)
    eb:SetFrameStrata("DIALOG")
    A:SetFontPx(eb, A.media.chatFont, A.db.chatFontSize, "")
    eb:SetTextInsets(6, 6, 0, 0)
    local header = _G[eb:GetName() .. "Header"]
    if header then
        A:SetFontPx(header, A.media.chatFont, A.db.chatFontSize, "")
        header:ClearAllPoints()
        header:SetPoint("LEFT", eb, "LEFT", 6, 0)
    end

    -- blinking text caret
    local caret = eb:CreateTexture(nil, "OVERLAY")
    caret:SetTexture(1, 1, 1, 1)
    caret:Hide()
    eb.huiCaret = caret
    local cx, blink = 0, 0
    local function placeCaret()
        local px = A:PX(eb)
        local left = eb:GetTextInsets() or 0
        caret:ClearAllPoints()
        caret:SetWidth(px)
        caret:SetHeight(math.floor((A.db.chatFontSize or 12) + 0.5) * px)
        caret:SetPoint("LEFT", eb, "LEFT", A:Snap(eb, left + cx), 0)
    end
    -- the blink restarts only when the cursor index changes (typing / arrows);
    -- OnCursorChanged just records the pixel position
    eb:HookScript("OnCursorChanged", function(self, x)
        cx = x or 0
        placeCaret()
    end)
    local lastPos, t0 = -1, 0
    local driver = CreateFrame("Frame", nil, eb)
    driver:SetScript("OnUpdate", function()
        if not eb:HasFocus() then
            if caret:IsShown() then caret:Hide() end
            lastPos = -1
            return
        end
        local now = GetTime()
        local pos = eb:GetCursorPosition()
        if pos ~= lastPos then lastPos, t0 = pos, now end
        local on = math.floor((now - t0) * 2) % 2 == 0   -- 0.5s on / 0.5s off
        if on ~= (caret:IsShown() and true or false) then
            if on then caret:Show() else caret:Hide() end
        end
    end)
    eb:HookScript("OnEditFocusGained", function()
        lastPos = -1
        placeCaret()
    end)
    eb:HookScript("OnEditFocusLost", function() caret:Hide() end)
    eb:HookScript("OnHide", function() caret:Hide() end)
end

------------------------------------------------------------------------
-- Message processing: timestamps, short channel names, clickable URLs
------------------------------------------------------------------------
local TS_FORMATS = { ["HH:MM"] = "%H:%M", ["HH:MM:SS"] = "%H:%M:%S", ["12H"] = "%I:%M %p" }
local URL_PATTERNS = {
    "(%a[%w+.-]+://[^%s|\"<>]+)",
    "(www%.[%w_-]+%.[^%s|\"<>]+)",
    "(%d+%.%d+%.%d+%.%d+:?%d*/?[^%s|]*)",
}

local function Linkify(text)
    for _, pat in ipairs(URL_PATTERNS) do
        text = text:gsub(pat, function(url)
            -- strip trailing punctuation that is part of the sentence, not the link
            local tail = url:match("[%.,;:!%?%)]+$") or ""
            if tail ~= "" then url = url:sub(1, -#tail - 1) end
            return "|cff6fb3ff|Haturl:" .. url .. "|h[" .. url .. "]|h|r" .. tail
        end)
    end
    return text
end

local function Process(text)
    local db = A.db
    if db.chatShortChannels then
        -- [2. Trade - City] -> [2]
        text = text:gsub("|Hchannel:(.-)|h%[(%d+)%.[^%]]-%]|h", "|Hchannel:%1|h[%2]|h")
    end
    if db.chatURLs and text:find("[%./]") and not text:find("|Haturl:", 1, true) then
        text = Linkify(text)
    end
    local fmt = TS_FORMATS[db.chatTimestamps]
    if fmt then
        local c = db.chatTsColor
        local stamp = date(fmt)
        if db.chatTimestamps == "12H" then stamp = stamp:gsub("^0(%d)", "%1") end   -- 09:05 AM -> 9:05 AM
        text = format("|cff%02x%02x%02x%s|r %s", c.r * 255, c.g * 255, c.b * 255, stamp, text)
    end
    return text
end

local function Wrap(cf)
    if not cf or cf.atrWrapped or cf == ChatFrame2 then return end
    cf.atrWrapped = true
    local orig = cf.AddMessage
    cf.AddMessage = function(self, text, ...)
        if type(text) == "string" then
            local ok, out = pcall(Process, text)
            if ok then text = out end
        end
        return orig(self, text, ...)
    end
end

-- short names for the fixed chat types ([Guild] -> [G], ...)
local SHORT = {
    CHAT_GUILD_GET = "G", CHAT_OFFICER_GET = "O", CHAT_PARTY_GET = "P", CHAT_PARTY_LEADER_GET = "PL",
    CHAT_PARTY_GUIDE_GET = "PG", CHAT_RAID_GET = "R", CHAT_RAID_LEADER_GET = "RL",
    CHAT_RAID_WARNING_GET = "RW", CHAT_BATTLEGROUND_GET = "BG", CHAT_BATTLEGROUND_LEADER_GET = "BL",
}
local origStrings = {}
function A:ApplyShortChannels()
    for k, short in pairs(SHORT) do
        local cur = _G[k]
        if cur then
            origStrings[k] = origStrings[k] or cur
            -- only write when it changes: a global written by an addon is
            -- "tainted", and Blizzard code that reads it then runs (and allocates) as HUI
            local want = self.db.chatShortChannels
                and origStrings[k]:gsub("%[[^%]]+%]", "[" .. short .. "]", 1) or origStrings[k]
            if cur ~= want then _G[k] = want end
        end
    end
end

local CLASS_GROUPS = {
    "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "ACHIEVEMENT", "WHISPER",
    "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "BATTLEGROUND", "BATTLEGROUND_LEADER",
}
function A:ApplyChatClassColors()
    if not ToggleChatColorNamesByClassGroup then return end
    local on = self.db.chatClassNames and true or false
    for _, g in ipairs(CLASS_GROUPS) do ToggleChatColorNamesByClassGroup(on, g) end
    for i = 1, 10 do ToggleChatColorNamesByClassGroup(on, "CHANNEL" .. i) end
end

local tabAlphas
function A:ApplyChatTabs()
    if not tabAlphas then
        tabAlphas = {
            CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA,
            CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA,
        }
    end
    for k, v in pairs(tabAlphas) do
        local want = self.db.chatTabsVisible and 1 or v
        if v and _G[k] ~= want then _G[k] = want end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab:IsShown() and self.db.chatTabsVisible then tab:SetAlpha(1) end
    end
end

function A:ApplyChatFading()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then
            cf:SetFading(self.db.chatFade and true or false)
            cf:SetTimeVisible(self.db.chatFadeTime)
        end
    end
end

function A:ResizeChat()
    local box = self.chatBox
    if not box then return end
    local w = self.db.chatWidth
    if not w or w <= 0 then
        local _, chatW = self:RaidChatWidths()
        w = chatW
    end
    self:Size(box, w, self.db.chatHeight)
    box:SetBackdropColor(A.colors.backdrop[1], A.colors.backdrop[2], A.colors.backdrop[3], A.colors.backdrop[4])
    self:ApplyPosition("Chat", box)
    -- bars sized to the chat height, and frames whose default spot depends on it
    for _, key in ipairs({ "Bar5", "PetBar" }) do
        local bar = self.bars and self.bars[key]
        if bar then self:LayoutBar(bar) end
    end
    for _, key in ipairs({ "Bar5", "PetBar", "Bags", "CombatTimer" }) do
        local m = self.movers[key]
        if m and not self.db.positions[key] then self:ApplyPosition(key, m.frame) end
    end
end

function A:PlaceChatEditBoxes()
    for i = 1, 20 do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb and eb.atrPlace then eb.atrPlace() end
    end
    if ChatFrameEditBox and ChatFrameEditBox.atrPlace then ChatFrameEditBox.atrPlace() end
end

-- clickable URL links open a copy box instead of the item tooltip
local function HookURLs()
    if not ItemRefTooltip or ItemRefTooltip.atrURL then return end
    ItemRefTooltip.atrURL = true
    local orig = ItemRefTooltip.SetHyperlink
    ItemRefTooltip.SetHyperlink = function(self, link, ...)
        if type(link) == "string" and link:sub(1, 6) == "aturl:" then
            self:Hide()
            if A.ShowCopy then A:ShowCopy("Link", link:sub(7), true) end
            return
        end
        return orig(self, link, ...)
    end
end

local function SkinWindow(cf)
    if not cf or cf.atrSkinned then return end
    cf.atrSkinned = true
    local name = cf:GetName()
    NoShow(_G[name .. "UpButton"])
    NoShow(_G[name .. "DownButton"])
    NoShow(_G[name .. "BottomButton"])
    NoShow(_G[name .. "ButtonFrame"])
    cf:EnableMouseWheel(true)
    cf:SetScript("OnMouseWheel", OnWheel)
    ChatFont(cf)
    SkinTab(_G[name .. "Tab"])
    SkinEditBox(_G[name .. "EditBox"])
    Wrap(cf)
    if A.db.chatHistory and cf.SetMaxLines and cf ~= ChatFrame2 then cf:SetMaxLines(A.db.chatHistory) end
    cf:SetFading(A.db.chatFade and true or false)
    cf:SetTimeVisible(A.db.chatFadeTime)
    -- each window's own background is replaced by our box (texture removed, so the
    -- game's window-alpha setting can't bring it back)
    for _, s in ipairs({ "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture",
        "BottomRightTexture", "LeftTexture", "RightTexture", "TopTexture", "BottomTexture" }) do
        local t = _G[name .. s]
        if t then t:SetTexture(nil); t:SetAlpha(0) end
    end
end

-- Chat positioning: a watchdog instead of fighting Blizzard's code paths.
-- Every docked window (General, CL, Whisp, Raid, Guild, ...) gets the same two
-- anchors straight onto our box. Several times a second we compare each window's
-- actual anchors with the wanted ones and re-apply only if anything (chat-cache
-- restore, docking, combat log, other addons) changed them. Floating windows are
-- left where the player put them.
local function IsDocked(cf, id)
    if cf == ChatFrame1 then return true end
    if cf.isDocked then return true end
    local list = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    if list then
        for _, f in ipairs(list) do if f == cf then return true end end
    end
    if id and GetChatWindowInfo then
        local _, _, _, _, _, _, _, docked = GetChatWindowInfo(id)
        if docked and docked ~= 0 then return true end
    end
    return false
end

local function Same(f, want)
    if f:GetNumPoints() ~= #want then return false end
    for i = 1, #want do
        local w = want[i]
        local ok = false
        for j = 1, f:GetNumPoints() do
            local p, rel, rp, x, y = f:GetPoint(j)
            if p == w[1] and rel == w[2] and rp == w[3]
                and math.abs((x or 0) - w[4]) < 0.05 and math.abs((y or 0) - w[5]) < 0.05 then
                ok = true
                break
            end
        end
        if not ok then return false end
    end
    return true
end

local function Pin(f, want)
    if Same(f, want) then return end
    f:ClearAllPoints()
    for _, w in ipairs(want) do f:SetPoint(w[1], w[2], w[3], w[4], w[5]) end
end

local placing
local function Place()
    local box = A.chatBox
    if not box then return end
    local top = -(HEADER + 3)
    local bar = CombatLogQuickButtonFrame_Custom or CombatLogQuickButtonFrame
    for id = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. id]
        if cf and IsDocked(cf, id) then
            -- Blizzard clamps chat windows with a 35px/50px margin from the screen
            -- edge; that pushed every tab except General up and right of our box
            if cf:IsClampedToScreen() then cf:SetClampedToScreen(false) end
            cf:SetClampRectInsets(0, 0, 0, 0)
            local t = top
            if cf == ChatFrame2 and bar then t = top - (bar:GetHeight() or CLBAR) end
            Pin(cf, {
                { "TOPLEFT", box, "TOPLEFT", 4, t },
                { "BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4 },
            })
            if cf == ChatFrame2 and bar then
                Pin(bar, {
                    { "BOTTOMLEFT", cf, "TOPLEFT", 0, 0 },
                    { "BOTTOMRIGHT", cf, "TOPRIGHT", 0, 0 },
                })
            end
        end
    end
    local dock = GeneralDockManager
    if dock then
        Pin(dock, {
            { "TOPLEFT", A.chatHeader, "TOPLEFT", 0, 0 },
            { "BOTTOMRIGHT", A.chatHeader, "BOTTOMRIGHT", 0, 0 },
        })
        -- Blizzard lets the scrolling part of the tab row (every tab after the first
        -- ones) hang 5px below the dock, so those tab texts sat higher than the others.
        -- Make the scroll area exactly as tall as the header, and centre the arrow.
        local ob = dock.overflowButton or GeneralDockManagerOverflowButton
        if ob then
            if not ob.atrSized then
                ob.atrSized = true
                ob:SetWidth(HEADER - 4)
                ob:SetHeight(HEADER - 4)
            end
            Pin(ob, { { "RIGHT", dock, "RIGHT", 0, 0 } })
        end
        local sf = dock.scrollFrame or GeneralDockManagerScrollFrame
        if sf then
            local lastStatic
            local list = dock.DOCKED_CHAT_FRAMES or {}
            for _, f in ipairs(list) do
                if f.isStaticDocked then lastStatic = _G[f:GetName() .. "Tab"] end
            end
            local left = lastStatic and { "TOPLEFT", lastStatic, "TOPRIGHT", 0, 0 }
                or { "TOPLEFT", dock, "TOPLEFT", 0, 0 }
            local right = (ob and ob:IsShown()) and { "BOTTOMRIGHT", ob, "BOTTOMLEFT", 0, 0 }
                or { "BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, 0 }
            -- static tab is HEADER tall and centred on the dock, so its top is the dock top
            if lastStatic then left[2], left[3] = lastStatic, "TOPRIGHT" end
            Pin(sf, { left, right })
            local child = sf:GetScrollChild()
            if child and math.abs((child:GetHeight() or 0) - HEADER) > 0.5 then child:SetHeight(HEADER) end
        end
        -- tabs share the header width equally (full width / number of tabs)
        local tabs = {}
        for _, f in ipairs(dock.DOCKED_CHAT_FRAMES or {}) do
            local tab = _G[f:GetName() .. "Tab"]
            if tab and f ~= ChatFrame2 or (tab and not A.db.chatHideCombatLog) then
                tabs[#tabs + 1] = { tab = tab, static = f.isStaticDocked }
            end
        end
        local total = 0
        local dockW = dock:GetWidth() or 0
        if #tabs > 0 and dockW > 0 then
            local px = A:PX(dock)
            local wpx = math.floor(dockW / px + 0.5)
            local each = math.floor(wpx / #tabs)
            for i, t in ipairs(tabs) do
                local w = (i == #tabs) and (wpx - each * (#tabs - 1)) or each
                w = w * px
                if math.abs((t.tab:GetHeight() or 0) - HEADER) > 0.5 then t.tab:SetHeight(HEADER) end
                if math.abs((t.tab:GetWidth() or 0) - w) > 0.01 then t.tab:SetWidth(w) end
                if not t.static then total = total + w end
            end
        end
        -- Blizzard sized the scroll area for its own (wider) tabs and may have
        -- scrolled it; with our narrow tabs everything fits, so reset it
        if sf then
            local child = sf:GetScrollChild()
            if child and math.abs((child:GetWidth() or 0) - total) > 0.5 then child:SetWidth(math.max(total, 1)) end
            -- the tabs share the width, so they always fit: never scroll (a
            -- fraction of a pixel over made Blizzard scroll on every click)
            if sf:GetHorizontalScroll() ~= 0 then sf:SetHorizontalScroll(0) end
            if ob and ob:IsShown() then ob:Hide() end
            if not sf.atrNoScroll then
                sf.atrNoScroll = true
                hooksecurefunc(sf, "SetHorizontalScroll", function(self, v)
                    if v ~= 0 then self:SetHorizontalScroll(0) end
                end)
            end
        end
        SkinOverflow(ob)
    end
end

local function Anchor()
    if placing then return end
    placing = true
    local ok, err = pcall(Place)
    placing = false
    if not ok and A.debug then print("HUI chat: " .. tostring(err)) end
end

local function SkinCombatLog()
    local cl = CombatLogQuickButtonFrame_Custom
    if not cl or cl.atrSkinned then return end
    cl.atrSkinned = true
    A:HideRegions(cl)
    local bg = cl:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cl)
    bg:SetTexture(0.08, 0.08, 0.09, 1)
    for i = 1, 10 do
        local b = _G["CombatLogQuickButtonFrameButton" .. i]
        if b then
            local fs = b.GetFontString and b:GetFontString()
            if fs then A:SetFontPx(fs, A.media.chatFont, A.db.chatFontSize, "OUTLINE") end
        end
    end
    hooksecurefunc(cl, "SetPoint", Anchor)
    Anchor()
end

------------------------------------------------------------------------
-- Default chat tabs: Global, CL, Loot, Guild, Whisper, Raid/Party.
-- Done once per character (chat settings are per character in 3.3.5).
------------------------------------------------------------------------
local TABS = {
    { "Loot",       { "LOOT", "MONEY", "CURRENCY", "SKILL", "TRADESKILLS", "OPENING", "PET_INFO", "COMBAT_FACTION_CHANGE", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN" } },
    { "Guild",      { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
    { "Whisper",    { "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM", "BN_CONVERSATION", "AFK", "DND", "IGNORED" } },
    { "Raid/Party", { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "BATTLEGROUND", "BATTLEGROUND_LEADER" } },
}

local function CharKey() return (GetRealmName() or "?") .. "-" .. (UnitName("player") or "?") end

function A:SetupChatTabs()
    if InCombatLockdown() then
        self:RunOOC(function() A:SetupChatTabs() end)
        return
    end
    -- start from the game's two default windows (General + Combat Log)
    if FCF_ResetChatWindows then pcall(FCF_ResetChatWindows) end
    local function set(cf, name, groups)
        if not cf then return end
        FCF_SetWindowName(cf, name)
        if groups then
            ChatFrame_RemoveAllMessageGroups(cf)
            if ChatFrame_RemoveAllChannels then pcall(ChatFrame_RemoveAllChannels, cf) end
            for _, g in ipairs(groups) do ChatFrame_AddMessageGroup(cf, g) end
        end
    end
    set(ChatFrame1, "Global")
    set(ChatFrame2, "CL")
    -- everything that gets its own tab leaves the Global window
    for _, t in ipairs(TABS) do
        for _, g in ipairs(t[2]) do ChatFrame_RemoveMessageGroup(ChatFrame1, g) end
    end
    for _, t in ipairs(TABS) do
        local before = {}
        for i = 1, (NUM_CHAT_WINDOWS or 10) do before[i] = _G["ChatFrame" .. i] and _G["ChatFrame" .. i]:IsShown() end
        local cf = FCF_OpenNewWindow and FCF_OpenNewWindow(t[1])
        if not cf then
            -- 3.3.5 doesn't return the window: find the one that just opened
            for i = 3, (NUM_CHAT_WINDOWS or 10) do
                local f = _G["ChatFrame" .. i]
                if f and f:IsShown() and not before[i] then cf = f break end
            end
        end
        set(cf, t[1], t[2])
    end
    FCF_SelectDockFrame(ChatFrame1)
    self:HideCombatLog()
    self.db.chatSetupDone = self.db.chatSetupDone or {}
    self.db.chatSetupDone[CharKey()] = true
    self:SetChatFontSize(self.db.chatFontSize)
    self:Print("chat tabs set up: Global, Loot, Guild, Whisper, Raid/Party.")
end

-- the combat log window can't be removed from the game, but it can be closed:
-- no tab, nothing docked (combat log events keep working for other addons)
-- The game's combat log window keeps turning every combat event into a
-- coloured line of text even while it is closed: in a 25-man fight that is
-- hundreds of lines a second written nowhere visible. With the window off,
-- it stops listening (other addons' COMBAT_LOG_EVENT_UNFILTERED is untouched).
local combatLogMuted
function A:SetCombatLogListening(on)
    local cl = _G.COMBATLOG or ChatFrame2
    if not (cl and cl.UnregisterEvent) then return end
    if on then
        if combatLogMuted then combatLogMuted = nil; cl:RegisterEvent("COMBAT_LOG_EVENT") end
    elseif not combatLogMuted and cl:IsEventRegistered("COMBAT_LOG_EVENT") then
        combatLogMuted = true
        cl:UnregisterEvent("COMBAT_LOG_EVENT")
        -- the window opened again (settings, /combatlog ...): it listens again
        if not cl.huiLogHook then
            cl.huiLogHook = true
            cl:HookScript("OnShow", function() A:SetCombatLogListening(true) end)
        end
    end
end

function A:HideCombatLog()
    if not self.db.chatHideCombatLog or not ChatFrame2 then return end
    if ChatFrame2:IsShown() or ChatFrame2.isDocked then
        if FCF_Close then pcall(FCF_Close, ChatFrame2) end
    end
    if ChatFrame2Tab then ChatFrame2Tab:Hide() end
    if CombatLogQuickButtonFrame_Custom then CombatLogQuickButtonFrame_Custom:Hide() end
    self:SetCombatLogListening(false)
end

------------------------------------------------------------------------
-- Opposing faction: their says / yells / emotes come in a language you don't
-- speak ("[Orcish] AAZ GOLAR ..."); hide those. Channels, NPCs, your party /
-- raid and your own faction are not touched.
------------------------------------------------------------------------
local known
local function KnownLanguages()
    if known then return known end
    known = {}
    for i = 1, (GetNumLanguages and GetNumLanguages() or 0) do
        local l = GetLanguageByIndex(i)
        if l then known[l] = true end
    end
    return known
end
local function OtherFaction(_, _, msg, author, language, ...)
    if not A.db.chatHideOtherFaction then return false end
    if not language or language == "" then return false end
    if KnownLanguages()[language] then return false end
    return true
end
local otherFactionHooked
local function HookOtherFaction()
    if otherFactionHooked then return end
    otherFactionHooked = true
    for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE" }) do
        ChatFrame_AddMessageEventFilter(e, OtherFaction)
    end
    -- read the known languages again on each loading screen
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function() known = nil end)
end

function A:BuildChat()
    local box = CreateFrame("Frame", "HUIChat", UIParent)
    box:SetFrameStrata("BACKGROUND")
    local _, chatW = self:RaidChatWidths()
    self:Size(box, chatW, BOX_H)
    self:SetTemplate(box, 0.80)
    self.chatBox = box
    self:ApplyShortChannels()
    HookURLs()
    HookOtherFaction()
    if self.db.chatTimestamps ~= "NONE" then SetCVar("showTimestamps", "none") end

    local header = CreateFrame("Frame", "HUIChatHeader", box)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER)
    -- the header shares the chat box backdrop: no strip, no divider line
    self.chatHeader = header

    for i = 1, (NUM_CHAT_WINDOWS or 7) do SkinWindow(_G["ChatFrame" .. i]) end
    SkinEditBox(ChatFrameEditBox)  -- older single edit box
    NoShow(ChatFrameMenuButton)
    NoShow(FriendsMicroButton)
    if FCF_SetLocked then pcall(FCF_SetLocked, ChatFrame1, 1) end

    local function skinNew()
        for i = 1, 20 do SkinWindow(_G["ChatFrame" .. i]) end
    end
    if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", skinNew) end
    if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", skinNew) end

    Anchor()
    -- Blizzard re-applies saved chat positions / docking at login and on tab changes;
    -- every time any chat window is moved, re-pin the layout
    for i = 1, (NUM_CHAT_WINDOWS or 7) do
        local cf = _G["ChatFrame" .. i]
        if cf then hooksecurefunc(cf, "SetPoint", Anchor) end
    end
    for _, fn in ipairs({ "FCF_RestorePositionAndDimensions", "FCFDock_ForceReanchoring",
        "FCFDock_AddChatFrame", "FCF_DockFrame", "FCF_UnDockFrame" }) do
        if _G[fn] then hooksecurefunc(fn, Anchor) end
    end
    SkinCombatLog()
    -- re-pin and repaint after tab switches / dock changes, once, on the next frame.
    -- 3.3.5 bug: when the main chat window changes size, the dock retries
    -- FCFDock_UpdateTabs every frame until it gets a "done" answer, and once
    -- anything else has already tidied the dock that answer never comes, so the
    -- retry runs forever (and ran our re-pin every frame). We stop that retry;
    -- our tab row never scrolls, so there is nothing for it to finish.
    local later = CreateFrame("Frame")
    later:Hide()
    later:SetScript("OnUpdate", function(self)
        self:Hide()
        Anchor()
        PaintAllTabs()
    end)
    local function DockChanged()
        local dock = GENERAL_CHAT_DOCK
        if dock and not dock.isDirty and FCFDock_OnUpdate and dock:GetScript("OnUpdate") == FCFDock_OnUpdate then
            dock:SetScript("OnUpdate", nil)
            dock.leftTab = nil
        end
        later:Show()
    end
    for _, fn in ipairs({ "FCF_Tab_OnClick", "FCF_DockUpdate", "FCFDock_UpdateTabs", "FCF_SelectDockFrame", "FCFDock_SelectWindow" }) do
        if _G[fn] then hooksecurefunc(fn, DockChanged) end
    end
    if FCF_StartAlertFlash then
        hooksecurefunc("FCF_StartAlertFlash", function(cf)
            local tab = cf and _G[cf:GetName() .. "Tab"]
            if tab then tab.atrAlert = true; PaintTab(tab) end
        end)
    end
    if FCF_StopAlertFlash then
        hooksecurefunc("FCF_StopAlertFlash", function(cf)
            local tab = cf and _G[cf:GetName() .. "Tab"]
            if tab then tab.atrAlert = nil; PaintTab(tab) end
        end)
    end
    PaintAllTabs()
    local clw = CreateFrame("Frame")
    clw:RegisterEvent("ADDON_LOADED")
    clw:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_CombatLog" then SkinCombatLog(); A:HideCombatLog() end
    end)
    ChatFrame1:SetClampedToScreen(false)
    -- the game re-applies its saved chat font size; follow up with ours
    if FCF_SetChatWindowFontSize then
        hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame, size)
            chatFrame = chatFrame or (FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame())
            -- always our size: the game would otherwise restore its cached 14/16
            if chatFrame then ChatFont(chatFrame, A.db.chatFontSize) end
        end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("UPDATE_CHAT_WINDOWS")
    ev:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
    ev:SetScript("OnEvent", function()
        Anchor()
        A:SetChatFontSize(A.db.chatFontSize)
    end)
    -- watchdog: re-check all chat anchors (re-applies only on change). The
    -- hooks above catch Blizzard's own moves; this is the safety net, so in
    -- combat it only looks every 5 seconds (it builds tables every pass)
    local acc = 0
    ev:SetScript("OnUpdate", A:PerfWrap("Chat: updates", function(_, el)
        acc = acc + el
        if acc > 0.1 and (acc > 5 or not InCombatLockdown()) then acc = 0; Anchor() end
    end))
    self:SetChatFontSize(self.db.chatFontSize)

    self:RegisterMover("Chat", box, "Chat")
    self:ResizeChat()
    self:ApplyChatTabs()
    local cc = CreateFrame("Frame")
    cc:RegisterEvent("PLAYER_ENTERING_WORLD")
    cc:SetScript("OnEvent", function(f)
        f:UnregisterAllEvents()
        -- first time on this character: set the tabs up (a moment after login,
        -- once the game has restored its own chat windows)
        local done = A.db.chatSetupDone and A.db.chatSetupDone[CharKey()]
        if A.db.chatAutoTabs and not done then
            local t = 0
            f:SetScript("OnUpdate", function(self, el)
                t = t + el
                if t < 1.5 then return end
                self:SetScript("OnUpdate", nil)
                A:SetupChatTabs()
                A:ApplyChatClassColors()
                A:ApplyChatTabs()
            end)
        end
        A:ApplyChatClassColors()
        A:ApplyChatTabs()
        A:HideCombatLog()
    end)
end

------------------------------------------------------------------------
-- Mouseover chat (Chat > "Show only on mouseover"): X seconds after the
-- mouse leaves the chat, the whole thing fades out completely: box,
-- messages, tabs, the combat log buttons and the combat timer. Hovering
-- where the chat is brings it back, and it stays while you type.
------------------------------------------------------------------------
do
    local FADE_OUT, FADE_IN = 0.4, 0.12   -- seconds
    local k = 1                           -- current visibility, 1 = normal
    local lastActive = GetTime()
    local base = {}                       -- each frame's own alpha when the fade began
    local list = {}

    local function Add(f) if f then list[#list + 1] = f end end
    local function Frames()
        wipe(list)
        Add(A.chatBox)
        Add(GeneralDockManager)
        Add(_G.HUICombatTimer)
        Add(CombatLogQuickButtonFrame_Custom)
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf and cf:IsShown() then Add(cf) end
            local tab = _G["ChatFrame" .. i .. "Tab"]
            if tab and tab:IsShown() then Add(tab) end
        end
        return list
    end

    local function Typing()
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb and eb:IsShown() and eb:HasFocus() then return true end
        end
        local eb = _G.ChatFrameEditBox
        return eb and eb:IsShown() and eb:HasFocus()
    end

    local function Hovered()
        local box, t = A.chatBox, _G.HUICombatTimer
        return (box and MouseIsOver(box)) or (t and t:IsShown() and MouseIsOver(t))
    end

    local f = CreateFrame("Frame")
    local hoverAcc = 0
    f:SetScript("OnUpdate", A:PerfWrap("Chat: mouseover fade", function(_, el)
        local db = A.db
        if not (db and A.chatBox) then return end
        local now = GetTime()
        if not db.chatMouseover or A.unlocked then
            lastActive = now
        else
            -- hover / typing checked 20 times a second, not every frame
            hoverAcc = hoverAcc + el
            if hoverAcc >= 0.05 or k < 1 then
                hoverAcc = 0
                if Hovered() or Typing() then lastActive = now end
            end
        end
        local want = (db.chatMouseover and now - lastActive >= (db.chatMouseoverDelay or 1)) and 0 or 1
        if k >= 1 and want >= 1 then return end   -- normal: hands off
        if k > want then k = math.max(want, k - el / FADE_OUT) else k = math.min(want, k + el / FADE_IN) end
        for _, fr in ipairs(Frames()) do
            if not base[fr] then base[fr] = fr:GetAlpha() end
            fr:SetAlpha(base[fr] * k)
        end
        if k >= 1 then wipe(base) end   -- back to normal: their own alphas restored
    end))

    -- settings changed: start counting again from now
    function A:ResetChatIdle() lastActive = GetTime() end
end
