-- HUI - One bag
-- All carried bags (backpack + 4 bags) in a single dark frame.
-- Item buttons use Blizzard's ContainerFrameItemButtonTemplate, so clicking,
-- dragging, tooltips, selling and using items behave exactly like default bags.
-- Bank and keyring keep the default Blizzard frames.

local A = HUI
local floor, format = math.floor, string.format

local SIZE, GAP, PAD, HEADER = 32, 1, 4, 22
local BAGS = { 0, 1, 2, 3, 4 }

local frame, bagHolders, buttons = nil, {}, {}
local search = ""   -- lower-case text in the search box ("" = show everything)

------------------------------------------------------------------------
-- Item button
------------------------------------------------------------------------
local function Region(b, s) return _G[b:GetName() .. s] end

local function SkinItem(b)
    b:SetWidth(SIZE)
    b:SetHeight(SIZE)
    local icon = Region(b, "IconTexture")
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetAllPoints(b)
    end
    local nt = Region(b, "NormalTexture") or (b.GetNormalTexture and b:GetNormalTexture())
    if nt then nt:SetAlpha(0) end
    local cd = Region(b, "Cooldown")
    if cd then cd:ClearAllPoints(); cd:SetAllPoints(b) end
    local count = Region(b, "Count")
    if count then
        A:SetFontPx(count, A.media.font, A:FS("bags"), "OUTLINE")
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then hl:SetTexture(1, 1, 1, 0.25); hl:ClearAllPoints(); hl:SetAllPoints(b) end
    local pushed = b.GetPushedTexture and b:GetPushedTexture()
    if pushed then pushed:SetTexture(1, 0.85, 0.2, 0.3); pushed:ClearAllPoints(); pushed:SetAllPoints(b) end

    -- dark slot behind the icon (empty slots show just this)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetTexture(0.10, 0.10, 0.11, 1)

    A:CreateBorder(b, 0, 0, 0)

    -- item level, top left (armour and weapons only)
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(b)
    top:SetFrameLevel(b:GetFrameLevel() + 2)
    b.ilvl = top:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(b.ilvl, A.media.font, A:FS("bags"), "OUTLINE")
    b.ilvl:SetShadowOffset(0, 0)
    b.ilvl:SetPoint("TOPLEFT", 2, -2)
end

-- gear that has a meaningful item level (no shirts, tabards, bags, ammo)
local NO_ILVL = { [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true,
    INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_NON_EQUIP = true }
local function ItemLevel(link)
    local _, _, _, ilvl, _, _, _, _, equip = GetItemInfo(link)
    if ilvl and ilvl > 1 and equip and not NO_ILVL[equip] then return ilvl end
end

-- search: name, type, sub type or slot ("plate", "trinket", "potion" ...)
local function Matches(link)
    if search == "" then return true end
    if not link then return false end
    local name, _, _, _, _, itype, isub, _, equip = GetItemInfo(link)
    name = name or link:match("%[(.-)%]") or ""
    local slot = equip and equip ~= "" and _G[equip] or ""
    for _, t in ipairs({ name, itype or "", isub or "", slot }) do
        if t:lower():find(search, 1, true) then return true end
    end
    return false
end

local function GetButton(bag, slot)
    buttons[bag] = buttons[bag] or {}
    local b = buttons[bag][slot]
    if b then return b end
    b = CreateFrame("Button", "HUIBag" .. bag .. "Slot" .. slot, bagHolders[bag], "ContainerFrameItemButtonTemplate")
    b:SetID(slot)
    SkinItem(b)
    buttons[bag][slot] = b
    return b
end

local function UpdateSlot(bag, slot)
    local b = GetButton(bag, slot)
    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    SetItemButtonTexture(b, texture)
    SetItemButtonCount(b, count)
    SetItemButtonDesaturated(b, locked)
    b.hasItem = texture and 1 or nil

    local cd = Region(b, "Cooldown")
    if cd then
        if texture then
            local start, duration, enable = GetContainerItemCooldown(bag, slot)
            CooldownFrame_SetTimer(cd, start, duration, enable)
        else
            cd:Hide()
        end
    end

    local link = GetContainerItemLink(bag, slot)
    if link and (not quality or quality < 0) then
        quality = select(3, GetItemInfo(link))
    end
    if link and quality and quality > 1 and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        b.atrBorder:SetColor(c.r, c.g, c.b)
    else
        b.atrBorder:SetColor(0, 0, 0)
    end

    local il = A.db.bagItemLevel and link and ItemLevel(link)
    if il then
        local c = quality and ITEM_QUALITY_COLORS[quality]
        b.ilvl:SetText(il)
        if c then b.ilvl:SetTextColor(c.r, c.g, c.b) else b.ilvl:SetTextColor(1, 1, 1) end
    else
        b.ilvl:SetText("")
    end

    -- search: items that don't match are faded
    b:SetAlpha(Matches(link) and 1 or 0.2)
end

------------------------------------------------------------------------
-- Layout / update
------------------------------------------------------------------------
local function Layout()
    local COLS = A.db.bagCols
    local n = 0
    for _, bag in ipairs(BAGS) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local b = GetButton(bag, slot)
            local col, row = n % COLS, floor(n / COLS)
            b:ClearAllPoints()
            local g = GAP * A:PX(frame)
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * (SIZE + g), -(HEADER + PAD + row * (SIZE + g)))
            b:Show()
            n = n + 1
        end
        -- hide buttons of slots that no longer exist (bag swapped for a smaller one)
        if buttons[bag] then
            for slot = slots + 1, #buttons[bag] do buttons[bag][slot]:Hide() end
        end
    end
    local rows = math.max(1, math.ceil(n / COLS))
    frame:SetWidth(PAD * 2 + COLS * SIZE + (COLS - 1) * GAP)
    frame:SetHeight(HEADER + PAD * 2 + rows * SIZE + (rows - 1) * GAP + 18)
    frame.numSlots = n
end

local function MoneyText()
    local m = GetMoney()
    local g, s, c = floor(m / 10000), floor(m / 100) % 100, m % 100
    return format("|cffffd700%d|rg |cffc7c7cf%d|rs |cffeda55f%d|rc", g, s, c)
end

local function UpdateAll()
    if not frame or not frame:IsShown() then return end
    Layout()
    local free = 0
    for _, bag in ipairs(BAGS) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do UpdateSlot(bag, slot) end
        free = free + (GetContainerNumFreeSlots(bag) or 0)
    end
    frame.slots:SetText(format("%d/%d free", free, frame.numSlots or 0))
    frame.money:SetText(MoneyText())
end

------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------
function A:RefreshBags()
    if frame and frame.search then
        if A.db.bagSearch == false then
            frame.search:SetText(""); frame.search:ClearFocus(); frame.search:Hide()
        else
            frame.search:Show()
        end
    end
    UpdateAll()
end

function A:OpenBags()
    if not frame then return end
    frame:Show()
    UpdateAll()
end
function A:CloseBags() if frame then frame:Hide() end end
function A:ToggleBags()
    if frame and frame:IsShown() then self:CloseBags() else self:OpenBags() end
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function A:BuildBags()
    frame = CreateFrame("Frame", "HUIBag", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    self:SetTemplate(frame, 0.95)
    frame:Hide()
    tinsert(UISpecialFrames, "HUIBag")
    self.bagFrame = frame

    -- header
    local title = self:Font(frame, 12, "LEFT")
    title:SetPoint("TOPLEFT", PAD, -7)
    title:SetText("Bags")
    frame.slots = self:Font(frame, 11, "LEFT")
    frame.slots:SetPoint("LEFT", title, "RIGHT", 10, 0)
    frame.slots:SetTextColor(0.7, 0.7, 0.7)
    -- flat icon buttons: close, sort
    local function IconBtn(file, tip, onClick)
        local b = CreateFrame("Button", nil, frame)
        A:Size(b, 16, 16)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints(b)
        b.tex:SetTexture("Interface\\AddOns\\HUI\\media\\" .. file)
        b.tex:SetVertexColor(0.6, 0.6, 0.63)
        b:SetScript("OnEnter", function(self)
            self.tex:SetVertexColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) self.tex:SetVertexColor(0.6, 0.6, 0.63); GameTooltip:Hide() end)
        b:SetScript("OnClick", onClick)
        return b
    end
    local close = IconBtn("close", "Close", function() A:CloseBags() end)
    close:SetPoint("TOPRIGHT", -3, -3)
    local sort = IconBtn("sort", "Organize bags", function() A:SortBags() end)
    sort:SetPoint("RIGHT", close, "LEFT", -4, 0)
    -- search box between the header text and the buttons
    local sb = CreateFrame("EditBox", "HUIBagSearch", frame)
    sb:SetAutoFocus(false)
    sb:SetHeight(16)
    sb:SetPoint("RIGHT", sort, "LEFT", -6, 0)
    sb:SetPoint("LEFT", frame.slots, "RIGHT", 10, 0)
    sb:SetTextInsets(5, 5, 0, 0)
    A:SetFontPx(sb, A.media.font, 11, "")
    sb:SetTextColor(1, 1, 1)
    A:SetTemplate(sb)
    sb.hint = sb:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(sb.hint, A.media.font, 11, "")
    sb.hint:SetPoint("LEFT", 5, 0)
    sb.hint:SetTextColor(0.5, 0.5, 0.52)
    sb.hint:SetText(SEARCH or "Search")
    sb:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        if t == "" then self.hint:Show() else self.hint:Hide() end
        search = t:lower():gsub("^%s+", ""):gsub("%s+$", "")
        UpdateAll()
    end)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    sb:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    sb:SetScript("OnEditFocusLost", function(self) if (self:GetText() or "") == "" then self.hint:Show() end end)
    frame.search = sb
    if A.db.bagSearch == false then sb:Hide() end

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetTexture(0, 0, 0, 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 1, -HEADER + 2)
    line:SetPoint("TOPRIGHT", -1, -HEADER + 2)
    -- footer: gold
    frame.money = self:Font(frame, 11, "RIGHT")
    frame.money:SetPoint("BOTTOMRIGHT", -PAD, 5)

    for _, bag in ipairs(BAGS) do
        local h = CreateFrame("Frame", nil, frame)
        h:SetID(bag)              -- item buttons read their bag id from the parent
        h:SetAllPoints(frame)
        bagHolders[bag] = h
    end

    frame:SetScript("OnShow", function() UpdateAll() PlaySound("igBackPackOpen") end)
    frame:SetScript("OnHide", function()
        PlaySound("igBackPackClose")
        -- a new opening starts unfiltered
        if frame.search and (frame.search:GetText() or "") ~= "" then frame.search:SetText("") end
        if frame.search then frame.search:ClearFocus() end
    end)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "BAG_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
        "PLAYER_MONEY", "UNIT_INVENTORY_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        ev:RegisterEvent(e)
    end
    -- bursts of bag events (looting fires one per bag, cooldowns one per
    -- use) are drawn once, on the next frame; other players' gear changes
    -- (UNIT_INVENTORY_CHANGED for every raid member) are ignored
    ev:Hide()
    ev:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
        if frame and frame:IsShown() then self:Show() end
    end)
    ev:SetScript("OnUpdate", function(self)
        self:Hide()
        UpdateAll()
    end)

    -- route the default bag functions to our frame (bank bags / keyring stay Blizzard's)
    local origToggleBag, origCloseAll = ToggleBag, CloseAllBags
    ToggleBackpack = function() A:ToggleBags() end
    OpenBackpack = function() A:OpenBags() end
    CloseBackpack = function() A:CloseBags() end
    OpenAllBags = function(force)
        if force then A:OpenBags() else A:ToggleBags() end
    end
    ToggleBag = function(id)
        if id and id >= 0 and id <= 4 then A:ToggleBags() else origToggleBag(id) end
    end
    local origOpenBag = OpenBag
    OpenBag = function(id)
        if id and id >= 0 and id <= 4 then A:OpenBags() elseif origOpenBag then origOpenBag(id) end
    end
    CloseAllBags = function()
        A:CloseBags()
        if origCloseAll then origCloseAll() end
    end

    self:RegisterMover("BagFrame", frame, "Bags (open)")
    frame:SetWidth(PAD * 2 + A.db.bagCols * SIZE + (A.db.bagCols - 1) * GAP)
    frame:SetHeight(200)
end


------------------------------------------------------------------------
-- Organize: sorts the items of your normal bags (not profession bags) by
-- type, quality, item level and name. 3.3.5 has no sort function, so items
-- are swapped one pair at a time, waiting for each move to finish.
------------------------------------------------------------------------
local sorter = CreateFrame("Frame")
sorter:Hide()

local TYPE_ORDER = {}
for i, t in ipairs({ "Weapon", "Armor", "Consumable", "Container", "Gem", "Glyph", "Recipe",
    "Trade Goods", "Projectile", "Quiver", "Reagent", "Key", "Quest", "Miscellaneous" }) do
    TYPE_ORDER[t] = i
end

local function Slots()
    local list = {}
    for _, bag in ipairs(BAGS) do
        local n = GetContainerNumSlots(bag) or 0
        local _, family = GetContainerNumFreeSlots(bag)
        if n > 0 and (bag == 0 or family == 0) then
            for slot = 1, n do list[#list + 1] = { bag, slot } end
        end
    end
    return list
end

local function Key(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return nil end
    local _, count = GetContainerItemInfo(bag, slot)
    return link .. "#" .. (count or 1), link, count or 1
end

local plan
local function Plan()
    local slots = Slots()
    local items = {}
    for _, s in ipairs(slots) do
        local key, link, count = Key(s[1], s[2])
        if key then
            local name, _, quality, ilvl, _, itype, isub = GetItemInfo(link)
            local hearth = link:find("item:6948:") and 0 or 1   -- hearthstone first
            items[#items + 1] = { key = key, hearth = hearth, t = TYPE_ORDER[itype or ""] or 99,
                sub = isub or "", q = quality or 0, ilvl = ilvl or 0, name = name or "", count = count }
        end
    end
    table.sort(items, function(a, b)
        if a.hearth ~= b.hearth then return a.hearth < b.hearth end
        if a.t ~= b.t then return a.t < b.t end
        if a.q ~= b.q then return a.q > b.q end
        if a.sub ~= b.sub then return a.sub < b.sub end
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        if a.name ~= b.name then return a.name < b.name end
        return a.count > b.count
    end)
    local want = {}
    for i, it in ipairs(items) do want[i] = it.key end
    return { slots = slots, want = want }
end

local function Locked(bag, slot)
    local _, _, locked = GetContainerItemInfo(bag, slot)
    return locked
end

-- one swap per call; true when everything is in place
local function Step()
    local slots, want = plan.slots, plan.want
    for i, s in ipairs(slots) do
        if Locked(s[1], s[2]) then return false end
    end
    for i, s in ipairs(slots) do
        local key = want[i]
        if not key then return true end
        if Key(s[1], s[2]) ~= key then
            for j = i + 1, #slots do
                local t = slots[j]
                if Key(t[1], t[2]) == key then
                    ClearCursor()
                    PickupContainerItem(t[1], t[2])
                    PickupContainerItem(s[1], s[2])
                    ClearCursor()
                    return false
                end
            end
            return true   -- bags changed under us: stop
        end
    end
    return true
end

local wait = 0
sorter:SetScript("OnUpdate", function(self, el)
    wait = wait + el
    if wait < 0.05 then return end
    wait = 0
    if InCombatLockdown() or CursorHasItem() then return end
    plan.steps = (plan.steps or 0) + 1
    if Step() or plan.steps > 600 then
        self:Hide()
        plan = nil
    end
end)

function A:SortBags()
    if InCombatLockdown() then return A:Print("can't organize bags in combat.") end
    if sorter:IsShown() then return end
    plan = Plan()
    sorter:Show()
end

------------------------------------------------------------------------
-- Keyring: the game's own window, drawn like HUI's bag: plain dark panel,
-- title top-left, no bag portrait, the same 32px slots in a 4-wide grid
-- (in slot order), black edges unless the key is green or better.
-- The same Blizzard window is reused for bank bags: those get their own
-- look back when they open.
------------------------------------------------------------------------
do
    local KEY_COLS = 4
    local saved = {}

    local function Portrait(f)
        return _G[f:GetName() .. "PortraitButton"]
    end

    local function KeyBorders(f)
        for i = 1, (f.size or 0) do
            local item = _G[f:GetName() .. "Item" .. i]
            if item and item.SetBackdropBorderColor then
                local link = GetContainerItemLink(f:GetID(), item:GetID())
                local q = link and select(3, GetItemInfo(link))
                if q and q > 1 and ITEM_QUALITY_COLORS[q] then
                    local c = ITEM_QUALITY_COLORS[q]
                    item:SetBackdropBorderColor(c.r, c.g, c.b)
                else
                    item:SetBackdropBorderColor(0, 0, 0)
                end
            end
        end
    end

    local function Restore(f)
        local s = saved[f]
        if not s then return end
        saved[f] = nil
        local p = Portrait(f)
        if p then p:Show() end
        local bd = f.backdrop
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -4)
            bd:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 1)
        end
        local nm = _G[f:GetName() .. "Name"]
        if nm and s.name then
            nm:ClearAllPoints()
            nm:SetPoint(unpack(s.name))
            nm:SetJustifyH(s.justify or "CENTER")
        end
    end

    local function Keyring(f)
        local name = f:GetName()
        local bd = f.backdrop
        if not bd then return end
        local nm = _G[name .. "Name"]
        if not saved[f] then
            saved[f] = { name = nm and { nm:GetPoint(1) }, justify = nm and nm:GetJustifyH() }
        end
        local p = Portrait(f)
        if p then p:Hide() end

        local px = A:PX(bd)
        local g = GAP * px
        local n = f.size or 0
        local rows = math.max(1, math.ceil(n / KEY_COLS))
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -4)
        bd:SetWidth(PAD * 2 + KEY_COLS * SIZE + (KEY_COLS - 1) * g)
        bd:SetHeight(HEADER + PAD * 2 + rows * SIZE + (rows - 1) * g)
        A:SetTemplate(bd, 0.95)

        if nm then
            A:SetFontPx(nm, A.media.font, 12, "OUTLINE")
            nm:SetShadowOffset(0, 0)
            nm:SetTextColor(1, 1, 1)
            nm:ClearAllPoints()
            nm:SetPoint("TOPLEFT", bd, "TOPLEFT", PAD, -7)
            nm:SetJustifyH("LEFT")
        end

        for i = 1, n do
            local item = _G[name .. "Item" .. i]
            if item then
                item:SetWidth(SIZE); item:SetHeight(SIZE)
                local pos = item:GetID() - 1   -- slot order, left to right
                local col, row = pos % KEY_COLS, floor(pos / KEY_COLS)
                item:ClearAllPoints()
                item:SetPoint("TOPLEFT", bd, "TOPLEFT", PAD + col * (SIZE + g), -(HEADER + PAD + row * (SIZE + g)))
            end
        end
        KeyBorders(f)
    end

    local hooked = false
    local function Hook()
        if hooked or not ContainerFrame_GenerateFrame then return end
        hooked = true
        hooksecurefunc("ContainerFrame_GenerateFrame", function(f)
            if f:GetID() == KEYRING_CONTAINER then Keyring(f) else Restore(f) end
        end)
        -- after the dark skin colours the slots (it hooks this too, earlier)
        if ContainerFrame_Update then
            hooksecurefunc("ContainerFrame_Update", function(f)
                if f:GetID() == KEYRING_CONTAINER then KeyBorders(f) end
            end)
        end
    end
    -- hooked after login, so it runs after the window skin's own hooks
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Hook()
    end)
end
