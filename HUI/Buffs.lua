-- HUI - Restyle + move the default player buff/debuff icons
-- Blizzard's buttons are kept (right-click to cancel still works); only the look changes.

local A = HUI

local function Skin(b)
    if not b or b.atrSkinned then return end
    b.atrSkinned = true
    local name = b:GetName()

    A:CreateBorder(b, 0, 0, 0)

    local icon = _G[name .. "Icon"]
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetAllPoints(b)
    end

    local border = _G[name .. "Border"]
    if border then border:SetAlpha(0) end

    local dur = _G[name .. "Duration"]
    if dur then
        A:SetFontPx(dur, A.media.font, A:FS("buffs"), "OUTLINE")
        dur:SetShadowOffset(0, 0)
        dur:ClearAllPoints()
        dur:SetPoint("CENTER", b, "CENTER", 0, 0)
    end

    local count = _G[name .. "Count"]
    if count then
        A:SetFontPx(count, A.media.font, A:FS("buffs"), "OUTLINE")
        count:SetShadowOffset(0, 0)
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 2)
    end
end

local function Color(b, r, g, bl)
    if b.atrBorder then b.atrBorder:SetColor(r, g, bl) end
end

function A:PlaceBuffs()
    local h = self.buffHolder
    if not h then return end
    for _, f in ipairs({ BuffFrame, TemporaryEnchantFrame, ConsolidatedBuffs }) do
        if f then
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
        end
    end
end

local function ShortTime(t)
    if t >= 3600 then return math.floor(t / 3600 + 0.5) .. "h" end
    if t >= 60 then return math.floor(t / 60 + 0.5) .. "m" end
    return tostring(math.floor(t + 0.5))
end

-- Blizzard spaces the player auras 5px apart; lay them out again with the 1px gap
-- the rest of the UI uses. Order (right to left): consolidated icon, weapon enchants,
-- buffs; debuffs start on a new row underneath.
local laying
function A:LayoutBuffs()
    if laying or not BuffFrame then return end
    -- anchor to our holder, never to BuffFrame: Blizzard anchors BuffFrame to
    -- ConsolidatedBuffs, so ConsolidatedBuffs -> BuffFrame would be a loop
    local anchor = self.buffHolder
    if not anchor then return end
    laying = true
    local px = self:PX(BuffFrame)
    local gap = px
    local perRow, maxRows = 12, 3
    local list = {}
    if ConsolidatedBuffs and ConsolidatedBuffs:IsShown() then list[#list + 1] = ConsolidatedBuffs end
    for i = 1, 3 do
        local te = _G["TempEnchant" .. i]
        if te and te:IsShown() then list[#list + 1] = te end
    end
    for i = 1, (BUFF_MAX_DISPLAY or 32) do
        local b = _G["BuffButton" .. i]
        if b and b:IsShown() and not b.consolidated and b:GetParent() == BuffFrame then
            list[#list + 1] = b
        end
    end
    local size = (TempEnchant1 and TempEnchant1:GetHeight()) or 30
    local step = size + gap
    for n, b in ipairs(list) do
        local col, row = (n - 1) % perRow, math.floor((n - 1) / perRow)
        if row < maxRows then
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -col * step, -row * step)
        elseif b ~= ConsolidatedBuffs then
            b:Hide()               -- more than 3 rows: not shown
        end
    end
    self.buffStep, self.buffPerRow = step, perRow
    self.buffLaidAt = GetTime()
    local rows = math.min(math.ceil(#list / perRow), maxRows)
    -- debuffs have their own movable holder; by default it hangs under the
    -- last buff row with a 48px gap so the two groups read apart
    self.buffRowsH = rows * step * BuffFrame:GetScale()
    local dh = self.debuffHolder or anchor
    for i = 1, (DEBUFF_MAX_DISPLAY or 16) do
        local b = _G["DebuffButton" .. i]
        if b then
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", dh, "TOPRIGHT", -col * step, -row * step)
        end
    end
    local key = self.buffRowsH + (BuffFrame:GetScale() or 1) * 100000 + size * 0.001
    if self.debuffHolder and not self.db.positions.Debuffs and self.debuffPlacedKey ~= key then
        self.debuffPlacedKey = key
        self:ApplyPosition("Debuffs", self.debuffHolder)
    end
    laying = false
end

-- one debuff button that Blizzard just anchored: put only that one back
-- (Blizzard anchors them one at a time, and each used to lay out everything)
function A:PlaceDebuff(index)
    local b = index and _G["DebuffButton" .. index]
    local step, perRow = self.buffStep, self.buffPerRow
    if not (b and step) then return self:LayoutBuffs() end
    local dh = self.debuffHolder or self.buffHolder
    if not dh then return end
    local col, row = (index - 1) % perRow, math.floor((index - 1) / perRow)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", dh, "TOPRIGHT", -col * step, -row * step)
end

function A:SetBuffScale(v)
    self.db.buffScale = v
    for _, f in ipairs({ BuffFrame, TemporaryEnchantFrame, ConsolidatedBuffs }) do
        if f then f:SetScale(v) end
    end
end

function A:BuildBuffs()
    if AuraButton_Update then
        hooksecurefunc("AuraButton_Update", function(buttonName, index, filter)
            local b = _G[buttonName .. index]
            if not b then return end
            Skin(b)
            if filter == "HARMFUL" then
                local _, _, _, _, dtype = UnitAura(PlayerFrame and PlayerFrame.unit or "player", index, filter)
                local c = DebuffTypeColor[dtype or "none"] or DebuffTypeColor["none"]
                Color(b, c.r, c.g, c.b)
            end
        end)
    end

    if AuraButton_UpdateDuration then
        hooksecurefunc("AuraButton_UpdateDuration", A:PerfWrap("Buffs: duration text", function(button, timeLeft)
            if not button then return end
            local d = button.huiDur
            if d == nil then
                d = button.duration or _G[button:GetName() .. "Duration"] or false
                button.huiDur = d   -- looked up once, not by name every frame
            end
            if d and timeLeft and d:IsShown() then
                d:SetText(ShortTime(timeLeft))
                d:SetVertexColor(1, 1, 1)   -- always white (Blizzard turns it yellow/red)
                d:SetTextColor(1, 1, 1)
            end
        end))
    end

    for i = 1, 3 do
        local te = _G["TempEnchant" .. i]
        if te then
            Skin(te)
            Color(te, 0.6, 0.2, 0.9)
        end
    end
    for i = 1, (BUFF_MAX_DISPLAY or 32) do Skin(_G["BuffButton" .. i]) end
    for i = 1, (DEBUFF_MAX_DISPLAY or 16) do Skin(_G["DebuffButton" .. i]) end
    if ConsolidatedBuffs then
        local icon = ConsolidatedBuffsIcon
        -- the "folder" is the left half of a two-picture texture: cropping it
        -- like a spell icon cut across both pictures. Blizzard's own coords.
        if icon then icon:SetTexCoord(0, 0.5, 0, 1) end
    end

    local h = CreateFrame("Frame", "HUIBuffHolder", UIParent)
    self:Size(h, 300, 100)
    self.buffHolder = h
    self:RegisterMover("Buffs", h, "Buffs")
    local dh = CreateFrame("Frame", "HUIDebuffHolder", UIParent)
    self:Size(dh, 300, 60)
    self.debuffHolder = dh
    self:RegisterMover("Debuffs", dh, "Debuffs", function(p)
        dh:ClearAllPoints()
        if A.db.positions.Debuffs then
            dh:SetPoint(p[1], UIParent, p[2], A:Snap(dh, p[3]), A:Snap(dh, p[4]))
        elseif A.minimapHolder then
            -- left of the minimap: first row's bottom on the minimap's bottom line,
            -- more rows grow downwards
            local icon = (DebuffButton1 and DebuffButton1:GetHeight() or 30) * (BuffFrame and BuffFrame:GetScale() or 1)
            dh:SetPoint("TOPRIGHT", A.minimapHolder, "BOTTOMLEFT", -2 * A:PX(dh), icon)
        else
            dh:SetPoint(p[1], UIParent, p[2], A:Snap(dh, p[3]), A:Snap(dh, p[4]))
        end
    end)
    self:PlaceBuffs()
    self:SetBuffScale(self.db.buffScale)
    if UIParent_ManageFramePositions then
        hooksecurefunc("UIParent_ManageFramePositions", function() A:PlaceBuffs() end)
    end
    local function relayout() A:LayoutBuffs() end
    if BuffFrame_UpdateAllBuffAnchors then hooksecurefunc("BuffFrame_UpdateAllBuffAnchors", relayout) end
    -- BuffFrame_Update ends with BuffFrame_UpdateAllBuffAnchors: no second pass in the same frame
    if BuffFrame_Update then
        hooksecurefunc("BuffFrame_Update", function()
            if A.buffLaidAt ~= GetTime() then A:LayoutBuffs() end
        end)
    end
    if DebuffButton_UpdateAnchors then
        hooksecurefunc("DebuffButton_UpdateAnchors", function(_, index) A:PlaceDebuff(index) end)
    end
    -- weapon enchants appear/disappear from an OnUpdate; re-layout only when the count changes
    if TemporaryEnchantFrame then
        local last = -1
        TemporaryEnchantFrame:HookScript("OnUpdate", function()
            local n = BuffFrame.numEnchants or 0
            if n ~= last then last = n; relayout() end
        end)
    end
    if ConsolidatedBuffs then
        ConsolidatedBuffs:HookScript("OnShow", relayout)
        ConsolidatedBuffs:HookScript("OnHide", relayout)
    end
    self:LayoutBuffs()

    -- "Consolidate buffs" (Interface > Buffs and Debuffs) off by default, once;
    -- the game reads its option after addons load, so do it on entering the world
    local cf = CreateFrame("Frame")
    cf:RegisterEvent("PLAYER_ENTERING_WORLD")
    cf:SetScript("OnEvent", function(frame)
        frame:UnregisterAllEvents()
        if not A.db.consolidateOff then
            A.db.consolidateOff = true
            SetCVar("consolidateBuffs", "0")
            CONSOLIDATE_BUFFS = "0"
            if BuffFrame_Update then BuffFrame_Update() end
        end
    end)
end


-- Blizzard fades buffs/debuffs in and out ("breathing") when they are about to
-- expire. Keep them fully visible.
if AuraButton_OnUpdate then
    hooksecurefunc("AuraButton_OnUpdate", A:PerfWrap("Buffs: no fading", function(self)
        if A.db and A.db.modules.buffs and self:GetAlpha() < 1 then self:SetAlpha(1) end
    end))
end
