-- HUI - Square minimap
-- Square map in a 160px frame. It never rotates: the game's "Rotate Minimap"
-- option is hidden and kept off.

local A = HUI
local format = string.format
local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"

function GetMinimapShape()
    return "SQUARE"
end

local function UpdateShape()
    if GetCVar("rotateMinimap") == "1" then
        SetCVar("rotateMinimap", "0")
        if Minimap_UpdateRotationSetting then Minimap_UpdateRotationSetting() end
    end
    Minimap:SetMaskTexture(SQUARE_MASK)
end

local holder

local function Place(f, point, rel, x, y)
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint(point, holder, rel, x, y)
end

------------------------------------------------------------------------
-- Info strip: clock left, FPS / MS right
------------------------------------------------------------------------
local function HideClock()
    if TimeManagerClockButton then
        TimeManagerClockButton:Hide()
        TimeManagerClockButton.Show = TimeManagerClockButton.Hide
    end
end

local function Colored(v, good, ok, invert)
    local c
    if invert then
        c = (v <= good and "33ff66") or (v <= ok and "ffd200") or "ff4444"
    else
        c = (v >= good and "33ff66") or (v >= ok and "ffd200") or "ff4444"
    end
    return "|cff" .. c .. v .. "|r"
end

local function BuildInfo()
    -- two lines in the lower left corner of the map, no background:
    --   10:14 AM
    --   139 FPS | 144 MS
    local info = CreateFrame("Button", "HUIMinimapInfo", holder)
    info:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 4, 3)
    info:SetWidth(150)
    info:SetHeight(28)
    info:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    info.stats = A:Font(info, 10, "LEFT")
    A:SetFontPx(info.stats, A.media.font, A:FS("minimap") - 1, "OUTLINE")
    info.stats:SetPoint("BOTTOMLEFT", 0, 0)
    info.time = A:Font(info, 10, "LEFT")
    A:SetFontPx(info.time, A.media.font, A:FS("minimap") - 1, "OUTLINE")
    info.time:SetPoint("BOTTOMLEFT", info.stats, "TOPLEFT", 0, 2)

    local LABEL = "|cff4da6ff%s|r"
    local t = 1
    info:SetScript("OnUpdate", A:PerfWrap("Minimap: clock / fps", function(self, el)
        t = t + el
        if t < 1 then return end
        t = 0
        self.time:SetText(A:ClockText())
        local fps = math.floor(GetFramerate() + 0.5)
        local _, _, ms = GetNetStats()
        self.stats:SetText(fps .. " " .. LABEL:format("FPS") .. " | " .. (ms or 0) .. " " .. LABEL:format("MS"))
    end))
    info:RegisterForClicks("AnyUp")
    info:SetScript("OnClick", function()
        if not TimeManagerFrame and LoadAddOn then LoadAddOn("Blizzard_TimeManager") end
        if TimeManager_Toggle then TimeManager_Toggle() end
    end)
    A.minimapInfo = info
    if not A.db.showInfo then info:Hide() end
end

function A:ClockText()
    local db = self.db
    local h, m
    if db.mmClockRealm then
        h, m = GetGameTime()
    else
        h, m = tonumber(date("%H")), tonumber(date("%M"))
    end
    if db.mmClock24 then return format("%02d:%02d", h, m) end
    local suffix = h >= 12 and " PM" or " AM"
    h = h % 12
    if h == 0 then h = 12 end
    return format("%d:%02d%s", h, m, suffix)
end

function A:SetMinimapInfo(show)
    self.db.showInfo = show
    if self.minimapInfo then
        if show then self.minimapInfo:Show() else self.minimapInfo:Hide() end
    end
    if self.UpdateMinimapText then self:UpdateMinimapText() end
end

------------------------------------------------------------------------
-- Addon button flyout: one small button on the minimap opens a panel with
-- every addon's minimap button (plus calendar and tracking)
------------------------------------------------------------------------
local IGNORE = {
    MiniMapTracking = true, MiniMapMailFrame = true, MiniMapBattlefieldFrame = true,
    MiniMapLFGFrame = true, MinimapZoomIn = true, MinimapZoomOut = true,
    MiniMapWorldMapButton = true, MinimapZoneTextButton = true, MiniMapInstanceDifficulty = true,
    MiniMapVoiceChatFrame = true, TimeManagerClockButton = true, MinimapBackdrop = true,
    MinimapPing = true, MinimapToggleButton = true, MiniMapRecordingButton = true,
    GameTimeFrame = true, MinimapNorthTag = true,
}
-- buttons of the addons HUI carries itself: never shown (their settings are in /hui)
local HIDE = { LibDBIcon10_DBM = true, LibDBIcon10_Skada = true, DBMMinimapButton = true }
local collected, flyout = {}, nil
local noop = function() end
local PER = 10
-- button size and gap in real screen pixels: squares, 1px apart, 1px under the map
local BTN_PX = 17
local function SZ() return A:DP(BTN_PX) * A:PX(flyout or holder) end
local function GP() return A:PX(flyout or holder) end

-- addon buttons in a row under the minimap, filling from the left
local function LayoutFlyout()
    if not flyout then return end
    local n = 0
    local sz, gp = SZ(), GP()
    for _, b in ipairs(collected) do
        if b:IsShown() or b.atrForceShow then
            local col, row = n % PER, math.floor(n / PER)
            -- every button the same size (sizes set before the UI scale applied
            -- were slightly off)
            b:SetScale(1)
            b:SetWidth(sz)
            b:SetHeight(sz)
            b.atrClearAllPoints(b)
            b.atrSetPoint(b, "TOPLEFT", flyout, "TOPLEFT", col * (sz + gp), -row * (sz + gp))
            n = n + 1
        end
    end
    local cols, rows = math.min(n, PER), math.ceil(n / PER)
    flyout:SetWidth(math.max(cols, 1) * (SZ() + GP()) - GP())
    flyout:SetHeight(math.max(rows, 1) * (SZ() + GP()) - GP())
end

-- each button becomes its own small dark square: round border / background art
-- removed, icon cropped to fill the square, 1px border around it
local function Style(b)
    if b.atrStyled then return end
    b.atrStyled = true
    b:SetScale(1)
    b:SetWidth(SZ())
    b:SetHeight(SZ())
    local icon = b.icon or b.Icon or (b:GetName() and _G[b:GetName() .. "Icon"])
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r ~= icon then
            local tex = r:GetTexture()
            tex = type(tex) == "string" and tex:lower() or ""
            if tex:find("border") or tex:find("background") or tex:find("minimap%-") then
                r:SetTexture(nil)
                r:Hide()
            elseif not icon and r:GetDrawLayer() ~= "HIGHLIGHT" then
                icon = r
            end
        end
    end
    if icon then
        icon:ClearAllPoints()
        local px = A:PX(b)
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", px, -px)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -px, px)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then
        hl:SetTexture(1, 1, 1, 0.15)
        hl:ClearAllPoints()
        hl:SetAllPoints(b)
    end
    A:SetTemplate(b, 0.9)
end

local function Grab(b)
    if not b or b.atrGrabbed then return end
    if HIDE[b:GetName() or ""] then
        b.atrGrabbed = true
        b:SetParent(A.hider)
        b:Hide()
        return
    end
    b.atrGrabbed = true
    b:SetParent(flyout)
    b.atrSetPoint, b.atrClearAllPoints = b.SetPoint, b.ClearAllPoints
    b.SetPoint, b.ClearAllPoints = noop, noop       -- addons can't drag it back onto the map
    b:SetScript("OnDragStart", nil)
    b:SetScript("OnDragStop", nil)
    Style(b)
    table.insert(collected, b)
end

local function Collect()
    for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
        if parent then
            for _, child in ipairs({ parent:GetChildren() }) do
                local name = child:GetName()
                if name and not IGNORE[name] and not name:find("^HUI")
                    and child:IsObjectType("Button") and (child:GetWidth() or 99) <= 40 then
                    Grab(child)
                end
            end
        end
    end
    LayoutFlyout()
end

local function BuildFlyout()
    -- addon buttons sit in a row under the minimap and show on mouseover
    flyout = CreateFrame("Frame", "HUIMinimapButtons", holder)
    flyout:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -A:PX(holder))
    flyout:SetFrameStrata("MEDIUM")
    flyout:SetWidth(SZ())
    flyout:SetHeight(SZ())

    -- this addon's own button: left-click settings, right-click unlock
    local own = CreateFrame("Button", "HUIMinimapButton", flyout)
    own.atrStyled = true
    own.atrForceShow = true
    own:SetWidth(SZ())
    own:SetHeight(SZ())
    A:SetTemplate(own, 0.95)
    own.atrCustomBg = true
    own:SetBackdropColor(0.08, 0.02, 0.03, 0.95)
    local ot = own:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(ot, A.media.font, 12, "OUTLINE")
    ot:SetShadowOffset(0, 0)
    ot:SetPoint("CENTER", own, "CENTER", 0, 0)
    ot:SetJustifyH("CENTER")
    ot:SetText("|cffc41f3bH|r")
    local ohl = own:CreateTexture(nil, "HIGHLIGHT")
    ohl:SetAllPoints(own)
    ohl:SetTexture(1, 1, 1, 0.15)
    own:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    own:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if A.unlocked then A:Lock() else A:Unlock() end
        else
            A:ToggleConfig()
        end
    end)
    -- the tooltip refreshes once a second while the mouse is on the button,
    -- in combat too (the "hide tooltips in combat" option lets this one through)
    own.huiAllowTooltip = true
    local function Fill(self, noCollect)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("|cffc41f3bHUI|r")
        GameTooltip:AddLine("Left-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: unlock / lock frames", 0.8, 0.8, 0.8)
        -- memory used by HUI (and all addons); garbage is only collected when
        -- the tooltip opens (a full collection every second would stutter)
        local r = A:MemoryReport(noCollect)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("HUI memory", A:FormatKB(r.total), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("All addons", A:FormatKB(r.all), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:Show()
    end
    local ttAcc = 0
    local function Tick(self, el)
        ttAcc = ttAcc + el
        if ttAcc < 1 then return end
        ttAcc = 0
        Fill(self, true)
    end
    own:SetScript("OnEnter", function(self)
        Fill(self)
        ttAcc = 0
        self:SetScript("OnUpdate", Tick)
    end)
    own:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
    Grab(own)

    local watch, acc = CreateFrame("Frame"), 0
    watch:SetScript("OnUpdate", A:PerfWrap("Minimap: watcher", function(_, el)
        acc = acc + el
        if acc < 0.1 then return end
        acc = 0
        local show = not A.db.grabberMouseover or A.unlocked or MouseIsOver(holder) or MouseIsOver(flyout)
        local a = (show and #collected > 0) and 1 or 0
        A:FadeTo(flyout, a)
    end))

    -- calendar and tracking buttons are not shown: middle-click the map for the
    -- calendar (game menu list), right-click it for the tracking menu
    for _, f in ipairs({ GameTimeFrame, MiniMapTracking }) do
        if f then f:SetParent(A.hider); f:Hide() end
    end

    -- addons create their buttons late; look again a few seconds after login
    local waited = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, el)
        waited = waited + el
        if waited > 5 then
            Collect()
            LayoutFlyout()
            self:SetScript("OnUpdate", nil)
        end
    end)
    LayoutFlyout()
    A.CollectMinimapButtons = Collect
    A.LayoutMinimapButtons = LayoutFlyout
end

------------------------------------------------------------------------
-- Size, border, visibility, zone text, coordinates, zoom reset, clicks
------------------------------------------------------------------------
local back, coords

function A:ResizeMinimap()
    if not holder then return end
    local size = self.db.mmSize
    self:Size(holder, size)
    local px = self:PX(holder)
    Minimap:SetWidth(size - 2 * px)
    Minimap:SetHeight(size - 2 * px)
    local z = Minimap:GetZoom()
    Minimap:SetZoom(z > 0 and z - 1 or z + 1)
    Minimap:SetZoom(z)
    if MinimapZoneTextButton then MinimapZoneTextButton:SetWidth(size - 30) end
    local c = self.db.mmBorderColor
    if holder.atrBorder then
        holder.atrBorder:SetColor(c.r, c.g, c.b, 1)
        holder.atrBorder:SetThickness(self.db.mmBorder)
    end
    -- buffs sit left of the minimap unless they were moved by hand
    if self.defaultPositions.Buffs then self.defaultPositions.Buffs[3] = -(self:Snap(UIParent, size) + 4 * self:PX(UIParent)) end
    if self.buffHolder and not self.db.positions.Buffs then self:ApplyPosition("Buffs", self.buffHolder) end
    if self.PlaceXPBars then self:PlaceXPBars() end
    self:UpdateMinimapText()
end

local function UpdateCoords()
    if not coords then return end
    local mode = A.db.mmCoords
    local show = mode == "ALWAYS" or (mode == "HOVER" and MouseIsOver(holder))
    if not show then coords:Hide() return end
    local x, y = GetPlayerMapPosition("player")
    if not x or (x == 0 and y == 0) then coords:Hide() return end
    A.SetTxt(coords, format("%.1f, %.1f", x * 100, y * 100))
    if not coords:IsShown() then coords:Show() end
end

function A:UpdateMinimapText()
    if not coords then return end
    A:SetFontPx(coords, self.media.font, A:FS("minimap"), "OUTLINE")
    coords:ClearAllPoints()
    coords:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 3)
    UpdateCoords()
end

local function BuildExtras()
    coords = holder:CreateFontString(nil, "OVERLAY")
    coords:SetShadowOffset(0, 0)
    coords:Hide()

    -- keep the map on the current zone so coordinates read right
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_ZOOM" }) do
        ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "MINIMAP_UPDATE_ZOOM" then
            holder.zoomT = 0
            return
        end
        if not (WorldMapFrame and WorldMapFrame:IsShown()) then SetMapToCurrentZone() end
    end)

    local acc = 0
    holder.zoomT = 0
    local watch = CreateFrame("Frame")
    watch:SetScript("OnUpdate", A:PerfWrap("Minimap: watcher 2", function(_, el)
        acc = acc + el
        holder.zoomT = holder.zoomT + el
        if acc < 0.1 then return end
        acc = 0
        local db = A.db
        -- visibility
        local vis = db.mmVisibility
        local hover = MouseIsOver(holder) or (flyout and flyout:IsShown())
        local a = 1
        if A.unlocked then a = 1
        elseif vis == "COMBAT" and UnitAffectingCombat("player") then a = 0
        elseif vis == "MOUSEOVER" and not hover then a = 0 end
        if holder:GetAlpha() ~= a then
            holder:SetAlpha(a)
            Minimap:SetAlpha(a)
            if back then back:SetAlpha(a) end
        end
        -- zone text
        local zt = MinimapZoneTextButton
        if zt then
            local za = (db.mmZone == "ALWAYS" or (db.mmZone == "MOUSEOVER" and hover)) and 1 or 0
            if zt:GetAlpha() ~= za then zt:SetAlpha(za) end
        end
        -- zoom reset
        if db.mmZoomReset > 0 and Minimap:GetZoom() ~= 0 and holder.zoomT > db.mmZoomReset then
            Minimap:SetZoom(0)
        end
        UpdateCoords()
    end))

    -- group dots: the client rebuilds party/raid blips only once a second while
    -- the player stands still (every frame only while the player moves). A zoom
    -- nudge flags the map as changed, so the blips are rebuilt on the next frame.
    -- Each nudge makes the client redraw the whole minimap (and tells every
    -- addon the zoom changed), so it is done 4 times a second, not 20
    local blipAcc = 0
    local blips = CreateFrame("Frame")
    blips:SetScript("OnUpdate", A:PerfWrap("Minimap: group dots", function(_, el)
        blipAcc = blipAcc + el
        if blipAcc < 0.25 then return end
        blipAcc = 0
        if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then return end
        if (GetUnitSpeed("player") or 0) > 0 or not Minimap:IsVisible() then return end
        local z = Minimap:GetZoom()
        Minimap:SetZoom(z > 0 and z - 1 or z + 1)
        Minimap:SetZoom(z)
    end))

    -- right-click: tracking menu, middle-click: calendar, left-click: ping
    Minimap:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and A.db.mmRightTracking and MiniMapTrackingDropDown then
            ToggleDropDownMenu(1, nil, MiniMapTrackingDropDown, "cursor")
        elseif button == "MiddleButton" and A.db.mmMiddleMenu then
            A:ToggleMicroList()
        elseif Minimap_OnClick then
            Minimap_OnClick(self, button)
        end
    end)
end

------------------------------------------------------------------------
-- Middle-click list: everything the micro menu used to open
------------------------------------------------------------------------
local function Call(fn, ...)
    if type(fn) == "function" then pcall(fn, ...) end
end

-- Entries backed by a Blizzard micro button are secure "click" buttons: the
-- window then opens exactly as if the micro button was pressed. Opening the
-- spellbook from addon code instead taints it, and casting from it is blocked.
-- (Character Info, PvP and Game Menu do their work on mouse down/up, not on click,
-- so a "click" button can't open them; they are opened directly.)
local MICRO_LIST = {
    { "Character Info", function() Call(ToggleCharacter, "PaperDollFrame") end },
    { "Spellbook & Abilities", "SpellbookMicroButton" },
    { "Talents", "TalentMicroButton" },
    { "Achievements", "AchievementMicroButton" },
    { "Quest Log", "QuestLogMicroButton" },
    false,
    { "Social", "SocialsMicroButton" },
    { "Guild", function()
        if IsInGuild() then Call(ToggleFriendsFrame, 3)
        else UIErrorsFrame:AddMessage(ERR_GUILD_PLAYER_NOT_IN_GUILD or "You are not in a guild.", 1, 0.1, 0.1) end
    end },
    { "Dungeon Finder", "LFDMicroButton" },
    -- the PvP micro button works on mouse down/up, not on click
    { "Player vs. Player", function() Call(TogglePVPFrame) end },
    { "Currency", function() Call(ToggleCharacter, "TokenFrame") end },
    { "Calendar", function() Call(ToggleCalendar) end },
    false,
    { "Game Menu", function()
        if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) else ShowUIPanel(GameMenuFrame) end
    end },
    { "Help", "HelpMicroButton" },
}

local list, catcher
local function BuildMicroList()
    if list then return end
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() list:Hide() end)
    catcher:Hide()

    list = CreateFrame("Frame", "HUIMicroList", UIParent)
    list:SetFrameStrata("DIALOG")
    list:SetFrameLevel(catcher:GetFrameLevel() + 5)
    A:SetTemplate(list, 0.95)
    list:Hide()
    tinsert(UISpecialFrames, "HUIMicroList")
    list:SetScript("OnHide", function() catcher:Hide() end)
    -- close it as combat starts (still allowed at that moment)
    list:RegisterEvent("PLAYER_REGEN_DISABLED")
    list:SetScript("OnEvent", function(self) if self:IsShown() then self:Hide() end end)

    local y, W, H = 4, 140, 16
    for _, item in ipairs(MICRO_LIST) do
        if item then
            local secure = type(item[2]) == "string" and _G[item[2]]
            local b = CreateFrame("Button", nil, list, secure and "SecureActionButtonTemplate" or nil)
            b:SetHeight(H)
            b:SetPoint("TOPLEFT", 1, -y)
            b:SetPoint("TOPRIGHT", -1, -y)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(b)
            hl:SetTexture(1, 1, 1, 0.07)
            local t = b:CreateFontString(nil, "OVERLAY")
            A:SetFontPx(t, A.media.font, A:FS("general"), "")
            t:SetShadowOffset(1, -1)
            t:SetPoint("LEFT", 8, 0)
            t:SetText(item[1])
            if secure then
                b:RegisterForClicks("AnyUp")
                b:SetAttribute("type", "click")
                b:SetAttribute("clickbutton", secure)
                b:HookScript("OnClick", function() list:Hide() end)
            else
                b:SetScript("OnClick", function() list:Hide(); item[2]() end)
            end
            y = y + H
        else
            local sep = list:CreateTexture(nil, "ARTWORK")
            sep:SetTexture(1, 1, 1, 0.12)
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", 6, -(y + 3))
            sep:SetPoint("TOPRIGHT", -6, -(y + 3))
            y = y + 7
        end
    end
    list:SetWidth(W)
    list:SetHeight(y + 4)
end

function A:ToggleMicroList()
    if InCombatLockdown() then
        -- the list holds secure buttons: it can't open or close in combat
        UIErrorsFrame:AddMessage("Not in combat.", 1, 0.3, 0.3)
        return
    end
    BuildMicroList()
    if list:IsShown() then list:Hide() return end
    list:ClearAllPoints()
    list:SetPoint("TOPRIGHT", holder or UIParent, "TOPLEFT", -2, 0)
    catcher:Show()
    list:Show()
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function A:BuildMinimap()
    local VIS = self.db.mmSize
    local M = Minimap

    holder = CreateFrame("Frame", "HUIMinimap", UIParent)
    self:Size(holder, VIS)
    holder:SetFrameStrata("MEDIUM")
    self.minimapHolder = holder
    self:CreateBorder(holder, 0, 0, 0)

    -- dark square behind the map (visible in the corners when rotating = round)
    back = CreateFrame("Frame", nil, UIParent)
    back:SetAllPoints(holder)
    back:SetFrameStrata("BACKGROUND")
    local bt = back:CreateTexture(nil, "BACKGROUND")
    bt:SetAllPoints(back)
    bt:SetTexture(0.06, 0.06, 0.07, 1)

    -- the engine can draw the map up to a pixel past its frame; keep it 1px inside
    -- the holder so any overdraw lands under the black border instead of outside it
    local px = self:PX(holder)
    M:ClearAllPoints()
    M:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
    M:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
    M:SetWidth(VIS - 2 * px)
    M:SetHeight(VIS - 2 * px)
    UpdateShape()
    local z = M:GetZoom()
    M:SetZoom(z > 0 and z - 1 or z + 1)
    M:SetZoom(z)

    for _, n in ipairs({
        "MinimapBorder", "MinimapBorderTop", "MinimapZoomIn", "MinimapZoomOut",
        "MiniMapWorldMapButton", "MinimapToggleButton", "MinimapNorthTag",
        "MiniMapVoiceChatFrame", "MiniMapTrackingBackground", "MiniMapTrackingButtonBorder",
        "MiniMapMailBorder", "MiniMapBattlefieldBorder", "MiniMapLFGFrameBorder",
        "MinimapCompassTexture",
    }) do
        self:Remove(n)
    end

    M:EnableMouseWheel(true)
    M:SetScript("OnMouseWheel", function(self, d)
        local nz = self:GetZoom() + (d > 0 and 1 or -1)
        if nz >= 0 and nz < self:GetZoomLevels() then self:SetZoom(nz) end
    end)

    if MinimapZoneTextButton then
        -- zone name centred at the top
        MinimapZoneTextButton:SetParent(holder)
        MinimapZoneTextButton:SetWidth(VIS - 30)
        MinimapZoneTextButton:SetHeight(14)
        MinimapZoneTextButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        Place(MinimapZoneTextButton, "TOP", "TOP", 0, -3)
        A:SetFontPx(MinimapZoneText, self.media.font, A:FS("minimap") - 1, "OUTLINE")
        MinimapZoneText:SetShadowOffset(0, 0)
        MinimapZoneText:ClearAllPoints()
        MinimapZoneText:SetAllPoints(MinimapZoneTextButton)
        MinimapZoneText:SetJustifyH("CENTER")
    end

    -- status icons stay on the map, inside the visible square
    for _, f in ipairs({ MiniMapMailFrame, MiniMapBattlefieldFrame, MiniMapLFGFrame, MiniMapInstanceDifficulty }) do
        if f then f:SetParent(holder) end
    end
    -- mail: a small plain envelope in the top-right corner
    if MiniMapMailFrame then
        local mf = MiniMapMailFrame
        A:Size(mf, 14)
        mf:SetFrameLevel(Minimap:GetFrameLevel() + 6)
        if MiniMapMailIcon then
            MiniMapMailIcon:ClearAllPoints()
            MiniMapMailIcon:SetAllPoints(mf)
            MiniMapMailIcon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")
            MiniMapMailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            MiniMapMailIcon:SetVertexColor(1, 1, 1)
        end
        for _, r in ipairs({ mf:GetRegions() }) do
            if r ~= MiniMapMailIcon and r.SetTexture then r:SetTexture(nil) end
        end
        Place(mf, "TOPRIGHT", "TOPRIGHT", -4, -4)
    end
    Place(MiniMapBattlefieldFrame, "BOTTOMLEFT", "BOTTOMLEFT", -2, 20)
    Place(MiniMapLFGFrame, "BOTTOMLEFT", "BOTTOMLEFT", -2, 20)
    if MiniMapInstanceDifficulty then MiniMapInstanceDifficulty:SetScale(0.8) end   -- a bit smaller
    Place(MiniMapInstanceDifficulty, "TOPLEFT", "TOPLEFT", -3, 2)

    BuildInfo()
    BuildFlyout()
    BuildExtras()
    -- zoom resets count from the last wheel turn
    local wheel = M:GetScript("OnMouseWheel")
    M:SetScript("OnMouseWheel", function(s, d) holder.zoomT = 0; wheel(s, d) end)
    HideClock()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("CVAR_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, name)
        if name == "Blizzard_TimeManager" then HideClock() end
        UpdateShape()
    end)
    -- the game's own "Rotate Minimap" checkbox (Interface > Display) is gone
    local rot = InterfaceOptionsDisplayPanelRotateMinimap
    if rot then
        rot:Hide()
        rot:HookScript("OnShow", rot.Hide)
    end

    self:RegisterMover("Minimap", holder, "Minimap")
    self:ResizeMinimap()
    BuildMicroList()
    -- the map can draw a pixel past its frame: keep the border on top of it
    if holder.atrBorder then
        holder.atrBorder:SetFrameStrata("HIGH")
    end
    -- debuffs hang off the minimap corner (buffs are built before the minimap)
    if self.debuffHolder and not self.db.positions.Debuffs then self:ApplyPosition("Debuffs", self.debuffHolder) end
end
