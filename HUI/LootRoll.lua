-- HUI - Loot rolls: compact roll bars in place of the game's big roll
-- windows. Ported from ElvUI-WotLK (Modules/Misc/LootRoll.lua), drawn with
-- HUI's own look. Move them with "Loot rolls" in unlock mode; /hui rolltest
-- shows a few sample bars.

local A = HUI

local BAR_W, BAR_H, GAP = 230, 22, 4
local ICON = BAR_H
local BTN = BAR_H - 4

local locale = GetLocale()
local rollMessages = locale == "deDE" and {
	["(.*) passt automatisch bei (.+), weil [ersi]+ den Gegenstand nicht benutzen kann.$"] = 0,
	["(.*) würfelt nicht für: (.+|r)$"] = 0,
	["(.*) hat für (.+) 'Bedarf' ausgewählt"] = 1,
	["(.*) hat für (.+) 'Gier' ausgewählt"] = 2,
	["(.*) hat für '(.+)' Entzauberung gewählt."] = 3,
} or locale == "frFR" and {
	["(.*) a passé pour : (.+) parce qu'((il)|(elle)) ne peut pas ramasser cette objet.$"] = 0,
	["(.*) a passé pour : (.+)"] = 0,
	["(.*) a choisi Besoin pour : (.+)"] = 1,
	["(.*) a choisi Cupidité pour : (.+)"] = 2,
	["(.*) a choisi Désenchantement pour : (.+)"] = 3,
} or locale == "zhCN" and {
	["(.*)自动放弃了：(.+)，因为他无法拾取该物品$"] = 0,
	["(.*)自动放弃了：(.+)，因为她无法拾取该物品$"] = 0,
	["(.*)放弃了：(.+)"] = 0,
	["(.*)选择了需求取向：(.+)"] = 1,
	["(.*)选择了贪婪取向：(.+)"] = 2,
	["(.*)选择了分解取向：(.+)"] = 3,
} or locale == "zhTW" and {
	["(.*)自動放棄:(.+)，因為他無法拾取該物品$"] = 0,
	["(.*)自動放棄:(.+)，因為她無法拾取該物品$"] = 0,
	["(.*)放棄了:(.+)"] = 0,
	["(.*)選擇了需求:(.+)"] = 1,
	["(.*)選擇了貪婪:(.+)"] = 2,
	["(.*)選擇了分解:(.+)"] = 3,
} or locale == "ruRU" and {
	["(.*) автоматически передает предмет (.+), поскольку не может его забрать"] = 0,
	["(.*) пропускает розыгрыш предмета \"(.+)\", поскольку не может его забрать"] = 0,
	["(.*) отказывается от предмета (.+)%."] = 0,
	["Разыгрывается: (.+)%. (.*): \"Мне это нужно\""] = 1,
	["Разыгрывается: (.+)%. (.*): \"Не откажусь\""] = 2,
	["Разыгрывается: (.+)%. (.*): \"Распылить\""] = 3,
} or locale == "koKR" and {
	["(.*)님이 획득할 수 없는 아이템이어서 자동으로 주사위 굴리기를 포기했습니다: (.+)"] = 0,
	["(.*)님이 주사위 굴리기를 포기했습니다: (.+)"] = 0,
	["(.*)님이 입찰을 선택했습니다: (.+)"] = 1,
	["(.*)님이 차비를 선택했습니다: (.+)"] = 2,
	["(.*)님이 마력 추출을 선택했습니다: (.+)"] = 3,
} or locale == "esES" and {
	["^(.*) pasó automáticamente de: (.+) porque no puede despojar este objeto.$"] = 0,
	["^(.*) pasó de: (.+|r)$"] = 0,
	["(.*) eligió Necesidad para: (.+)"] = 1,
	["(.*) eligió Codicia para: (.+)"] = 2,
	["(.*) eligió Desencantar para: (.+)"] = 3,
} or locale == "esMX" and {
	["^(.*) pasó automáticamente de: (.+) porque no puede despojar este objeto.$"] = 0,
	["^(.*) pasó de: (.+|r)$"] = 0,
	["(.*) eligió Necesidad para: (.+)"] = 1,
	["(.*) eligió Codicia para: (.+)"] = 2,
	["(.*) eligió Desencantar para: (.+)"] = 3,
} or {
	["^(.*) automatically passed on: (.+) because s?he cannot loot that item.$"] = 0,
	["^(.*) passed on: (.+|r)$"] = 0,
	["(.*) has selected Need for: (.+)"] = 1,
	["(.*) has selected Greed for: (.+)"] = 2,
	["(.*) has selected Disenchant for: (.+)"] = 3
}


local rollTypes = {
    [0] = { tip = PASS, normal = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", pushed = "Interface\\Buttons\\UI-GroupLoot-Pass-Down" },
    [1] = { tip = NEED, newbie = NEED_NEWBIE, normal = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
            pushed = "Interface\\Buttons\\UI-GroupLoot-Dice-Down", highlight = "Interface\\Buttons\\UI-GroupLoot-Dice-Highlight" },
    [2] = { tip = GREED, newbie = GREED_NEWBIE, normal = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
            pushed = "Interface\\Buttons\\UI-GroupLoot-Coin-Down", highlight = "Interface\\Buttons\\UI-GroupLoot-Coin-Highlight" },
    [3] = { tip = ROLL_DISENCHANT, newbie = ROLL_DISENCHANT_NEWBIE, normal = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
            pushed = "Interface\\Buttons\\UI-GroupLoot-DE-Down", highlight = "Interface\\Buttons\\UI-GroupLoot-DE-Highlight" },
}

local reasons = {
    LOOT_ROLL_INELIGIBLE_REASON1, LOOT_ROLL_INELIGIBLE_REASON2, LOOT_ROLL_INELIGIBLE_REASON3,
    LOOT_ROLL_INELIGIBLE_REASON4, LOOT_ROLL_INELIGIBLE_REASON5,
}

local bars, holder = {}, nil

local function Font(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(fs, A.media.font, size, "OUTLINE")
    fs:SetShadowOffset(0, 0)
    return fs
end

------------------------------------------------------------------------
-- roll buttons
------------------------------------------------------------------------
local function ButtonOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tip)
    if self.newbie and SHOW_NEWBIE_TIPS == "1" then GameTooltip:AddLine(self.newbie, 1, 0.82, 0, true) end
    if self:IsEnabled() == 0 and self.reason then GameTooltip:AddLine(self.reason, 1, 0.1, 0.1, true) end
    for name, data in pairs(self.parent.results) do
        if data[1] == self.rollType then
            local c = data[2] and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[data[2]]) or RAID_CLASS_COLORS[data[2]])
            if c then GameTooltip:AddLine(name, c.r, c.g, c.b) else GameTooltip:AddLine(name, 1, 1, 1) end
        end
    end
    GameTooltip:Show()
end

local function ButtonOnLeave() GameTooltip:Hide() end

local function ButtonOnClick(self)
    local f = self.parent
    if f.fake then A.ReleaseRoll(f) return end
    if f.rollID then RollOnLoot(f.rollID, self.rollType) end
end

local function ToggleButton(b, on, reason, value)
    if on then
        b:Enable(); b:SetAlpha(1); b.reason = nil
        SetDesaturation(b:GetNormalTexture(), false)
    else
        b:Disable(); b:SetAlpha(0.25)
        b.reason = reason and reasons[reason] and (value and format(reasons[reason], value) or reasons[reason]) or nil
        SetDesaturation(b:GetNormalTexture(), true)
    end
end

local function CreateButton(f, rollType)
    local d = rollTypes[rollType]
    local b = CreateFrame("Button", nil, f)
    A:Size(b, BTN)
    b:SetNormalTexture(d.normal)
    b:SetPushedTexture(d.pushed)
    if d.highlight then b:SetHighlightTexture(d.highlight, "ADD") end
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", ButtonOnEnter)
    b:SetScript("OnLeave", ButtonOnLeave)
    b:SetScript("OnClick", ButtonOnClick)
    b.parent, b.rollType, b.tip, b.newbie = f, rollType, d.tip, d.newbie
    b.count = Font(b, 10)
    b.count:SetPoint("CENTER", 1, 0)
    return b
end

------------------------------------------------------------------------
-- item icon
------------------------------------------------------------------------
local function ItemOnEnter(self)
    if self.parent.fake then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetLootRollItem(self.parent.rollID)
    CursorUpdate(self)
end
local function ItemOnLeave() GameTooltip:Hide(); ResetCursor() end
local function ItemOnUpdate(self)
    if self.parent.fake then return end
    if GameTooltip:IsOwned(self) then
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetLootRollItem(self.parent.rollID)
    end
    CursorOnUpdate(self)
end
local function ItemOnClick(self)
    local link = self.parent.link
    if not link then return end
    if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link)
    elseif IsModifiedClick("DRESSUP") then DressUpItemLink(link) end
end

------------------------------------------------------------------------
-- one roll bar
------------------------------------------------------------------------
local function TimerOnUpdate(self, el)
    local f = self.parent
    local left
    if f.fake then
        f.fakeLeft = (f.fakeLeft or 0) - el * 1000
        if f.fakeLeft <= 0 then A.ReleaseRoll(f) return end
        left = f.fakeLeft
    else
        left = GetLootRollTimeLeft(f.rollID) or 0
    end
    if left < 0 or left > f.rollTime then left = 0 end
    self:SetValue(left)
    self.spark:SetPoint("CENTER", self, "LEFT", (left / f.rollTime) * self:GetWidth(), 0)
end

local function Layout()
    local px = A:PX(holder)
    local n = 0
    for _, f in ipairs(bars) do
        if f:IsShown() then
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -n * (A:Snap(f, BAR_H) + A:Snap(f, GAP)))
            n = n + 1
        end
    end
end

local function CreateBar()
    local f = CreateFrame("Frame", "HUILootRoll" .. (#bars + 1), holder)
    A:Size(f, BAR_W, BAR_H)
    A:SetTemplate(f)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    local px = A:PX(f)

    -- icon sits outside the bar, on its left
    local item = CreateFrame("Button", nil, f)
    A:Size(item, ICON)
    item:SetPoint("RIGHT", f, "LEFT", -A:Snap(f, 3), 0)
    A:SetTemplate(item)
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetPoint("TOPLEFT", px, -px)
    item.icon:SetPoint("BOTTOMRIGHT", -px, px)
    item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    item.parent, item.hasItem = f, 1
    item:SetScript("OnEnter", ItemOnEnter)
    item:SetScript("OnLeave", ItemOnLeave)
    item:SetScript("OnUpdate", ItemOnUpdate)
    item:SetScript("OnClick", ItemOnClick)
    f.item = item

    local timer = CreateFrame("StatusBar", nil, f)
    timer:SetPoint("TOPLEFT", px, -px)
    timer:SetPoint("BOTTOMRIGHT", -px, px)
    timer:SetStatusBarTexture(A.media.bar)
    timer:SetFrameLevel(f:GetFrameLevel() + 1)
    timer.parent = f
    timer.bg = timer:CreateTexture(nil, "BACKGROUND")
    timer.bg:SetAllPoints()
    timer.bg:SetTexture(A.media.blank)
    timer.bg:SetAlpha(0.1)
    timer.spark = timer:CreateTexture(nil, "OVERLAY")
    timer.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    timer.spark:SetBlendMode("ADD")
    timer.spark:SetWidth(12)
    timer.spark:SetHeight(BAR_H * 1.6)
    timer:SetScript("OnUpdate", TimerOnUpdate)
    f.timer = timer

    -- buttons and text above the bar
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints(f)
    top:SetFrameLevel(timer:GetFrameLevel() + 2)
    f.need = CreateButton(f, 1)
    f.greed = CreateButton(f, 2)
    f.de = CreateButton(f, 3)
    f.pass = CreateButton(f, 0)
    for _, b in ipairs({ f.need, f.greed, f.de, f.pass }) do b:SetFrameLevel(top:GetFrameLevel() + 1) end
    f.need:SetPoint("LEFT", f, "LEFT", A:Snap(f, 3), 0)
    f.greed:SetPoint("LEFT", f.need, "RIGHT", A:Snap(f, 1), 0)
    f.de:SetPoint("LEFT", f.greed, "RIGHT", A:Snap(f, 1), 0)
    f.pass:SetPoint("LEFT", f.de, "RIGHT", A:Snap(f, 1), 0)
    f.buttons = { [0] = f.pass, [1] = f.need, [2] = f.greed, [3] = f.de }

    f.bind = Font(top, 10)
    f.bind:SetPoint("LEFT", f.pass, "RIGHT", A:Snap(f, 3), 0)
    f.name = Font(top, 11)
    f.name:SetPoint("LEFT", f.bind, "RIGHT", A:Snap(f, 3), 0)
    f.name:SetPoint("RIGHT", f, "RIGHT", -A:Snap(f, 4), 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetHeight(BAR_H)

    f.results = {}
    bars[#bars + 1] = f
    return f
end

local function GetBar()
    for _, f in ipairs(bars) do
        if not f.rollID and not f.fake then return f end
    end
    return CreateBar()
end

function A.ReleaseRoll(f)
    f:Hide()
    f.rollID, f.rollTime, f.link, f.fake, f.fakeLeft = nil, nil, nil, nil, nil
    for i = 0, 3 do f.buttons[i].count:SetText("") end
    wipe(f.results)
    Layout()
end

local function Fill(f, rollID, rollTime, texture, name, count, quality, bop, canNeed, canGreed, canDE, rNeed, rGreed, rDE, deSkill)
    f.rollID, f.rollTime = rollID, rollTime
    f.item.icon:SetTexture(texture)
    if count and count > 1 then f.name:SetFormattedText("%dx %s", count, name or "") else f.name:SetText(name or "") end
    local c = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
    f.timer:SetMinMaxValues(0, rollTime)
    f.timer:SetValue(rollTime)
    f.timer:SetStatusBarColor(c.r, c.g, c.b, 0.55)
    f.timer.bg:SetVertexColor(c.r, c.g, c.b)
    f.item:SetBackdropBorderColor(c.r, c.g, c.b, 1)
    f.bind:SetText(bop and "BoP" or "BoE")
    if bop then f.bind:SetTextColor(1, 0.3, 0.1) else f.bind:SetTextColor(0.3, 1, 0.3) end
    ToggleButton(f.need, canNeed, rNeed)
    ToggleButton(f.greed, canGreed, rGreed)
    ToggleButton(f.de, canDE, rDE, deSkill)
    ToggleButton(f.pass, true)
    f:Show()
    Layout()
end

------------------------------------------------------------------------
-- events
------------------------------------------------------------------------
local function ParseRoll(msg)
    for pattern, rollType in pairs(rollMessages) do
        local _, _, who, item = msg:find(pattern)
        if who and item and who ~= "Everyone" then
            if locale == "ruRU" and rollType ~= 0 then who, item = item, who end
            return who, item, rollType
        end
    end
end

local function OnEvent(_, event, ...)
    if event == "START_LOOT_ROLL" then
        local rollID, rollTime = ...
        local f = GetBar()
        f.link = GetLootRollItemLink(rollID)
        Fill(f, rollID, rollTime, GetLootRollItemInfo(rollID))
    elseif event == "CANCEL_LOOT_ROLL" then
        local rollID = ...
        for _, f in ipairs(bars) do
            if f.rollID == rollID then
                A.ReleaseRoll(f)
                StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollID)
                break
            end
        end
    elseif event == "CHAT_MSG_LOOT" then
        local who, item, rollType = ParseRoll((...))
        if not who then return end
        local _, class = UnitClass(who)
        for _, f in ipairs(bars) do
            if f.rollID and f.link == item and not f.results[who] then
                f.results[who] = { rollType, class }
                local b = f.buttons[rollType]
                b.count:SetText((tonumber(b.count:GetText()) or 0) + 1)
                break
            end
        end
    end
end

function A:BuildLootRolls()
    if holder then return end
    holder = CreateFrame("Frame", "HUILootRollHolder", UIParent)
    A:Size(holder, BAR_W + ICON + 3, BAR_H)
    self:ApplyPosition("LootRoll", holder)
    self:RegisterMover("LootRoll", holder, "Loot rolls")

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("START_LOOT_ROLL")
    ev:RegisterEvent("CANCEL_LOOT_ROLL")
    ev:RegisterEvent("CHAT_MSG_LOOT")
    ev:SetScript("OnEvent", OnEvent)

    -- the game's roll windows stay off
    UIParent:UnregisterEvent("START_LOOT_ROLL")
    UIParent:UnregisterEvent("CANCEL_LOOT_ROLL")
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local g = _G["GroupLootFrame" .. i]
        if g then
            g:UnregisterAllEvents()
            g:Hide()
            g:SetParent(A.hider or UIParent)
        end
    end
end

-- sample bars, to see and place them
local samples = {
    { "Interface\\Icons\\INV_Weapon_ShortBlade_86", "Black Knight's Rondel", 1, 4, true, true, true, true },
    { "Interface\\Icons\\Spell_Frost_FrozenCore", "Frozen Orb", 1, 3, false, true, true, false, nil, nil, 1 },
    { "Interface\\Icons\\INV_Misc_Gem_Variety_01", "Cardinal Ruby", 2, 4, false, false, true, true, 2 },
}
function A:TestLootRolls()
    if not holder then self:BuildLootRolls() end
    for _, s in ipairs(samples) do
        local f = GetBar()
        f.fake, f.fakeLeft = true, 15000
        Fill(f, nil, 15000, unpack(s))
        f.rollID = nil
    end
end
