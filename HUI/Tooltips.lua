-- HUI - Dark tooltips and menus

local A = HUI

local backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- HUI colours: dark background, black border (item quality colour on item
-- tooltips, kept in tt.huiBorder)
local painting = false
local function Paint(tt)
    painting = true
    local c = A.colors.backdrop
    tt:SetBackdropColor(c[1], c[2], c[3], c[4])
    local b = tt.huiBorder
    if b then tt:SetBackdropBorderColor(b[1], b[2], b[3], 1) else tt:SetBackdropBorderColor(0, 0, 0, 1) end
    painting = false
end

local function Dark(tt)
    if not tt then return end
    local s = A.db and A.db.ttScale or 1
    if math.abs(tt:GetScale() - s) > 0.001 then tt:SetScale(s) end
    local px = A:PX(tt)
    backdrop.edgeSize = px
    painting = true
    tt:SetBackdrop(backdrop)
    painting = false
    Paint(tt)
end

-- the game (and some addons) set the tooltip colours back to the default
-- navy + light border while a tooltip is open: paint ours straight over them
local function Guard(tt)
    if tt.huiGuarded then return end
    tt.huiGuarded = true
    hooksecurefunc(tt, "SetBackdropColor", function(self) if not painting then Paint(self) end end)
    hooksecurefunc(tt, "SetBackdropBorderColor", function(self) if not painting then Paint(self) end end)
    hooksecurefunc(tt, "SetBackdrop", function(self) if not painting then Dark(self) end end)
    -- the client itself also resets them on world units and corpses, without
    -- going through those functions: check while the tooltip is open
    if tt.GetBackdropColor then
        tt:HookScript("OnUpdate", A:PerfWrap("Tooltips: colour check", function(self)
            local c, b = A.colors.backdrop, self.huiBorder
            local r, g, bl, a = self:GetBackdropColor()
            local br, bg, bb = self:GetBackdropBorderColor()
            local wr, wg, wb = 0, 0, 0
            if b then wr, wg, wb = b[1], b[2], b[3] end
            if not r or math.abs(r - c[1]) > 0.01 or math.abs(g - c[2]) > 0.01 or math.abs(bl - c[3]) > 0.01
                or math.abs((a or 1) - (c[4] or 1)) > 0.01
                or not br or math.abs(br - wr) > 0.01 or math.abs(bg - wg) > 0.01 or math.abs(bb - wb) > 0.01 then
                Paint(self)
            end
        end))
    end
end

local TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "ItemRefShoppingTooltip3",
    "WorldMapTooltip", "WorldMapCompareTooltip1", "WorldMapCompareTooltip2",
    "FriendsTooltip", "SmallTextTooltip",
}

-- where tooltips without an owner position go: bottom right, 2px from the edge
local function DefaultAnchor(tt, parent)
    if A.db.ttCursor then
        tt:SetOwner(parent, "ANCHOR_CURSOR")
        return
    end
    tt:ClearAllPoints()
    local bag = A.bagFrame
    if bag and bag:IsShown() then
        tt:SetPoint("BOTTOMRIGHT", bag, "TOPRIGHT", 0, 4)
    else
        tt:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -2, 82)
    end
end

function A:SetTooltipFonts()
    local size, f = A:FS("tooltips"), A.media.font
    if GameTooltipHeaderText then A:SetFontPx(GameTooltipHeaderText, f, size + 1, "") end
    if GameTooltipText then A:SetFontPx(GameTooltipText, f, size, "") end
    if GameTooltipTextSmall then A:SetFontPx(GameTooltipTextSmall, f, size - 1, "") end
end

function A:BuildTooltips()
    self:SetTooltipFonts()
    for _, name in ipairs(TOOLTIPS) do
        local tt = _G[name]
        if tt then
            Dark(tt)
            Guard(tt)
            tt:HookScript("OnShow", Dark)
            tt:HookScript("OnHide", function(self) self.huiBorder = nil end)
            if tt:HasScript("OnTooltipCleared") then
                tt:HookScript("OnTooltipCleared", function(self) self.huiBorder = nil; Paint(self) end)
            end
        end
    end

    -- item tooltips: border in item quality color
    local function QualityBorder(tt)
        local _, link = tt:GetItem()
        local q = link and select(3, GetItemInfo(link))
        local c = q and q > 1 and ITEM_QUALITY_COLORS[q]
        tt.huiBorder = c and { c.r, c.g, c.b } or nil
        Paint(tt)
    end
    GameTooltip:HookScript("OnTooltipSetItem", QualityBorder)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", QualityBorder) end

    for _, script in ipairs({ "OnTooltipSetUnit", "OnTooltipSetSpell" }) do
        GameTooltip:HookScript(script, function(tt) if tt.huiBorder then tt.huiBorder = nil; Paint(tt) end end)
    end

    -- player names in class color
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
        if not A.db.ttClassNames then return end
        local _, unit = tt:GetUnit()
        if not unit or not UnitIsPlayer(unit) then return end
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c and GameTooltipTextLeft1 then GameTooltipTextLeft1:SetTextColor(c.r, c.g, c.b) end
    end)

    -- no health bar on unit tooltips
    local sb = GameTooltipStatusBar
    if sb then
        sb:Hide()
        sb:SetParent(A.hider)
        sb.Show = sb.Hide
    end

    GameTooltip:HookScript("OnShow", function(tt)
        if not tt:IsShown() then return end   -- just hidden by the combat rule below
        -- fade in like the mouseover bars, but only when it really appears: some
        -- windows (inspect, character slots) rebuild the tooltip every frame,
        -- and fading each time kept it invisible
        local now = GetTime()
        if not tt.atrHidAt or now - tt.atrHidAt > 0.2 then
            tt:SetAlpha(0)
            A:FadeTo(tt, 1)
        else
            A:FadeTo(tt, 1)
            tt:SetAlpha(1)
        end
    end)
    GameTooltip:HookScript("OnHide", function(tt) tt.atrHidAt = GetTime() end)

    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", DefaultAnchor)
    end

    -- right-click menus and dropdowns
    for i = 1, (UIDROPDOWNMENU_MAXLEVELS or 2) do
        for _, n in ipairs({ "DropDownList" .. i .. "Backdrop", "DropDownList" .. i .. "MenuBackdrop" }) do
            Dark(_G[n])
        end
    end
end


------------------------------------------------------------------------
-- No tooltips in combat (setting "Hide tooltips in combat"), whether or not
-- the tooltip skin is on. A tooltip is hidden whenever it opens, is shown
-- again or gets new content (moving from one unit or button to the next
-- keeps the same tooltip open), and a watcher that only runs in combat
-- catches any other way one appears. Clicked links (ItemRefTooltip) are
-- windows you open yourself and stay allowed.
------------------------------------------------------------------------
do
    local HOVER = {
        "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
        "WorldMapTooltip", "WorldMapCompareTooltip1", "WorldMapCompareTooltip2",
        "FriendsTooltip", "SmallTextTooltip",
    }
    local list = {}

    local function Blocked()
        return A.db and A.db.ttHideCombat and InCombatLockdown()
    end
    -- frames that keep their tooltip in combat (HUI's minimap button)
    local function Allowed(tt)
        local o = tt.GetOwner and tt:GetOwner()
        return o and o.huiAllowTooltip
    end
    local function Kill(tt)
        if Blocked() and tt:IsShown() and not Allowed(tt) then tt:Hide() end
    end

    for _, name in ipairs(HOVER) do
        local tt = _G[name]
        if tt then
            list[#list + 1] = tt
            tt:HookScript("OnShow", Kill)
            hooksecurefunc(tt, "Show", Kill)
            for _, script in ipairs({ "OnTooltipSetUnit", "OnTooltipSetItem", "OnTooltipSetSpell" }) do
                if tt:HasScript(script) then tt:HookScript(script, Kill) end
            end
        end
    end

    local watch = CreateFrame("Frame")
    watch:Hide()
    -- the Show / OnShow hooks above hide them right away; this only catches
    -- what the client shows without those, so 5 times a second is plenty
    local wacc = 0
    watch:SetScript("OnUpdate", A:PerfWrap("Tooltips: combat hide", function(_, el)
        wacc = wacc + el
        if wacc < 0.2 then return end
        wacc = 0
        if not Blocked() then return end
        for i = 1, #list do
            local tt = list[i]
            if tt:IsShown() and not Allowed(tt) then tt:Hide() end
        end
    end))
    watch:RegisterEvent("PLAYER_REGEN_DISABLED")
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    watch:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            self:Show()
            for i = 1, #list do Kill(list[i]) end
        else
            self:Hide()
        end
    end)
end
