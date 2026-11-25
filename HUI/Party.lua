-- HUI - Party frames
-- Five frames built like the player frame, stacked on top of each other
-- (you + party1-4), each with its pet on the left. Shown in a party, hidden in a
-- raid (the raid frames take over). Everything moves as one block ("Party").

local A = HUI
local floor, ipairs = math.floor, ipairs

A.partyDefaults = {
    width       = 220,   -- frame size (same as the player frame)
    height      = 38,
    power       = 5,     -- power bar height (0 = none)
    gap         = 1,     -- pixels between frames
    fontSize    = 13,
    nameLen     = 16,
    hpFormat    = "both",   -- both / pct / cur / deficit / none
    showPlayer  = true,  -- you are the first of the five
    growUp      = false, -- false = first frame on top
    showPets    = true,
    petWidth    = 60,
    petGap      = 1,     -- pixels between pet and frame
    range       = true,  -- fade members out of range (like the raid frames)
    debuffs     = true,  -- debuffs to the right of each frame
    debuffNum   = 4,
    debuffSize  = 24,
    showSolo    = false, -- also show when not in a group
}

local function DB() return A.db.party end

local holder
local slots = {}   -- { frame, pet }

local function Units()
    local list = {}
    if DB().showPlayer then list[1] = "player" end
    for i = 1, 4 do list[#list + 1] = "party" .. i end
    return list
end

local function PetUnit(u)
    if u == "player" then return "pet" end
    return (u:gsub("^party", "partypet"))
end

-- size and inner layout of one frame (out of combat only)
local function LayoutFrame(f, w, h, power, fs, isPet)
    local px = A:PX(f)
    A:Size(f, A:Snap(f, w), A:Snap(f, h))
    local health = f.health
    health:ClearAllPoints()
    health:SetPoint("TOPLEFT", px, -px)
    health:SetPoint("TOPRIGHT", -px, -px)
    if f.power and power > 0 then
        health:SetHeight(A:Snap(f, h) - 2 * px - A:Snap(f, power) - px)
        f.power:SetHeight(A:Snap(f, power))
        f.power:Show()
        f.sep:Show()
    else
        health:SetPoint("BOTTOM", f, "BOTTOM", 0, px)
        if f.power then f.power:Hide(); f.sep:Hide() end
    end
    if f.name then A:SetFontPx(f.name, A.media.font, isPet and math.max(fs - 2, 8) or fs, "OUTLINE") end
    if f.hpText then A:SetFontPx(f.hpText, A.media.font, fs, "OUTLINE") end
end

local function MakeFrame(name, unit, isPet)
    local f = CreateFrame("Button", name, holder, "SecureUnitButtonTemplate")
    f.unit = unit
    f.cfg = isPet and { hpFormat = "none", nameLen = 8, nameCenter = true }
        or { hpFormat = DB().hpFormat, nameLen = DB().nameLen }
    f:SetAttribute("unit", unit)
    f:SetAttribute("toggleForVehicle", true)
    A:SetupClicks(f)
    A:SetTemplate(f)
    A:CreateBorder(f, 0, 0, 0)
    f:SetScript("OnEnter", UnitFrame_OnEnter)
    f:SetScript("OnLeave", UnitFrame_OnLeave)
    f:HookScript("OnShow", function(self) A:UpdateAll(self) end)

    f.health = A:StatusBar(f)
    if not isPet then
        local power = A:StatusBar(f)
        power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -A:PX(f))
        power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -A:PX(f))
        f.power = power
        local sep = f:CreateTexture(nil, "BORDER")
        sep:SetTexture(0, 0, 0, 1)
        sep:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", power, "TOPRIGHT", 0, 0)
        f.sep = sep
        f.hpText = f.health:CreateFontString(nil, "OVERLAY")
        f.hpText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0)
        f.hpText:SetJustifyH("RIGHT")
        f.hpText:SetShadowOffset(0, 0)
    end
    f.name = f.health:CreateFontString(nil, "OVERLAY")
    f.name:SetShadowOffset(0, 0)
    if isPet then
        f.name:SetPoint("LEFT", f.health, "LEFT", 2, 0)
        f.name:SetPoint("RIGHT", f.health, "RIGHT", -2, 0)
        f.name:SetJustifyH("CENTER")
    else
        f.name:SetPoint("LEFT", f.health, "LEFT", 19, 0)   -- after the role icon's spot, with or without one
        f.name:SetPoint("RIGHT", f.hpText, "LEFT", -4, 0)
        f.name:SetJustifyH("LEFT")
    end
    -- fonts must be set before any text
    A:SetFontPx(f.name, A.media.font, DB().fontSize, "OUTLINE")
    if f.hpText then A:SetFontPx(f.hpText, A.media.font, DB().fontSize, "OUTLINE") end

    if not isPet then
        A:AddIndicators(f, 15, 4, "row")
        f.roleIcon = f.health:CreateTexture(nil, "OVERLAY")
        A:Size(f.roleIcon, 13)
        f.roleIcon:SetPoint("LEFT", f.health, "LEFT", 3, 0)
        f.roleIcon:Hide()
    end

    f.raidIcon = f.health:CreateTexture(nil, "OVERLAY")
    A:Size(f.raidIcon, 14)
    f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raidIcon:Hide()

    -- dispellable debuff = its colour, otherwise black (aggro: corner square)
    f.UpdateBorder = function(self)
        local u = self.unit
        if not u or not UnitExists(u) then return end
        local b = self.atrBorder
        if self.dispelType then
            local c = DebuffTypeColor[self.dispelType]
            b:SetColor(c.r, c.g, c.b, 1)
        else
            b:SetColor(0, 0, 0, 1)
        end
    end

    RegisterUnitWatch(f)
    A.allFrames[f] = true
    return f
end

local function AddDebuffs(f)
    local db = DB()
    if f.auraGroups then
        for _, g in ipairs(f.auraGroups) do
            for _, b in ipairs(g.icons) do b:Hide() end
        end
        f.auraGroups = nil
    end
    if not db.debuffs then return end
    A:AddAuraGroup(f, {
        filter = "HARMFUL", num = db.debuffNum, size = db.debuffSize, perRow = db.debuffNum,
        point = "LEFT", relPoint = "RIGHT", x = 1, y = 0,
        mouse = true, showTime = true, blacklist = true, trackDispel = true,
    })
end

-- size, order and position of everything (out of combat only)
function A:LayoutParty()
    if not holder or InCombatLockdown() then return end
    local db = DB()
    local units = Units()
    local px = self:PX(holder)
    local W, H = self:Snap(holder, db.width), self:Snap(holder, db.height)
    local gap = db.gap * px
    local petW = db.showPets and (self:Snap(holder, db.petWidth) + db.petGap * px) or 0
    self:Size(holder, petW + W, 5 * H + 4 * gap)
    for i, s in ipairs(slots) do
        local f, pet = s.frame, s.pet
        local u = units[i]
        f.cfg.hpFormat, f.cfg.nameLen = db.hpFormat, db.nameLen
        LayoutFrame(f, db.width, db.height, db.power, db.fontSize)
        f:ClearAllPoints()
        local y = (i - 1) * (H + gap)
        if db.growUp then
            f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, y)
        else
            f:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
        end
        AddDebuffs(f)
        LayoutFrame(pet, db.petWidth, db.height, 0, db.fontSize, true)
        pet:ClearAllPoints()
        pet:SetPoint("TOPRIGHT", f, "TOPLEFT", -db.petGap * px, 0)
        if not self.partyTest then
            if u then
                f:SetAttribute("unit", u); f.unit = u
                RegisterUnitWatch(f)
                local pu = PetUnit(u)
                pet:SetAttribute("unit", pu); pet.unit = pu
                if db.showPets then RegisterUnitWatch(pet) else UnregisterUnitWatch(pet); pet:Hide() end
            else
                UnregisterUnitWatch(f); f:Hide()
                UnregisterUnitWatch(pet); pet:Hide()
            end
        end
        if f:IsVisible() then self:UpdateAll(f) end
        if pet:IsVisible() then self:UpdateAll(pet) end
    end
    if not self.partyTest then
        RegisterStateDriver(holder, "visibility",
            db.showSolo and "[group:raid] hide; show" or "[group:raid] hide; [group] show; hide")
    end
    self:ApplyPosition("Party", holder)
end

-- test mode: all five frames (and pets) show you, to set things up solo
-- test mode: five fake members (names from the raid test) with health that
-- moves now and then, and their pets, to set things up solo
local PETS = { HUNTER = "Wolf", WARLOCK = "Felhunter", DEATHKNIGHT = "Ghoul", MAGE = "Water Elemental" }
local POWER = { WARRIOR = "RAGE", ROGUE = "ENERGY", DEATHKNIGHT = "RUNIC_POWER" }
local testTicker

local function HpText(f, cur, max)
    local t = f.hpText
    if not t then return end
    local fmt = f.cfg.hpFormat
    local pct = math.floor(cur / max * 100 + 0.5)
    if f.dead then t:SetText("|cff999999Dead|r")
    elseif fmt == "both" then t:SetText(A:Short(cur) .. " | " .. pct .. "%")
    elseif fmt == "pct" then t:SetText(pct .. "%")
    elseif fmt == "cur" then t:SetText(A:Short(cur))
    elseif fmt == "deficit" then t:SetText(cur < max and ("|cffff6666-" .. A:Short(max - cur) .. "|r") or "")
    else t:SetText("") end
end

local function FakeMember(f, info, pet)
    f.unit = "hui-test"            -- no real unit: unit events leave it alone
    f.class, f.dead = info[2], nil
    f.max = pet and (8000 + math.random(0, 3000)) or (20000 + math.random(0, 8000))
    f.hp = f.max
    local r, g, b = A:ClassColor(info[2])
    if pet then r, g, b = 0.8, 0.8, 0.8 end
    f.name:SetText(A:Hex(r, g, b) .. A:Truncate(pet or info[1], f.cfg.nameLen or 16) .. "|r")
    f.health:SetMinMaxValues(0, f.max)
    f.health:SetValue(f.hp)
    if f.power then
        local c = PowerBarColor[POWER[info[2]] or "RUNIC_POWER"] or PowerBarColor.MANA
        f.power:SetMinMaxValues(0, 100); f.power:SetValue(100)
        f.power:SetStatusBarColor(c.r, c.g, c.b)
        f.power.bg:SetVertexColor(c.r * 0.2, c.g * 0.2, c.b * 0.2)
    end
    if f.roleIcon then
        local role = not pet and info[3]
        if role then f.roleIcon:SetTexture("Interface\\AddOns\\HUI\\media\\role_" .. role:lower()); f.roleIcon:Show() else f.roleIcon:Hide() end
    end
    if f.atrThreat then f.atrThreat:Hide() end
    A.FakeColor(f)
    HpText(f, f.hp, f.max)
end

function A:SetPartyTest(on)
    if not holder or InCombatLockdown() then return end
    self.partyTest = on and true or nil
    if on then
        UnregisterStateDriver(holder, "visibility")
        holder:Show()
        -- five names at random from the raid test list
        local pool = {}
        for i, v in ipairs(A.FAKE_RAID or {}) do pool[i] = v end
        for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
        for i, s in ipairs(slots) do
            local info = pool[i] or { "Member" .. i, "WARRIOR" }
            for _, f in ipairs({ s.frame, s.pet }) do
                UnregisterUnitWatch(f)
                f:SetAttribute("unit", "player")
            end
            s.frame:Show()
            FakeMember(s.frame, info)
            local petName = PETS[info[2]]
            if petName and DB().showPets then
                s.pet:Show()
                FakeMember(s.pet, info, petName)
            else
                s.pet:Hide()
            end
        end
        if not testTicker then
            testTicker = CreateFrame("Frame")
            local t = 0
            testTicker:SetScript("OnUpdate", function(_, el)
                if not A.partyTest then return end
                t = t + el
                if t < 0.7 then return end
                t = 0
                for i, s in ipairs(slots) do
                    for _, f in ipairs({ s.frame, s.pet }) do
                        if f:IsShown() and f.max then
                            if math.random() < 0.4 then
                                f.hp = math.max(f.max * 0.08, math.min(f.max, f.hp + math.random(-f.max * 0.35, f.max * 0.3)))
                            end
                            A:SetBarSmooth(f.health, f.hp, f.max, "partytest" .. i .. (f == s.pet and "p" or ""))
                            A.FakeColor(f)
                            HpText(f, f.hp, f.max)
                        end
                    end
                end
            end)
        end
    end
    self:LayoutParty()
    if not on then
        for _, s in ipairs(slots) do
            for _, f in ipairs({ s.frame, s.pet }) do
                f.max, f.hp = nil, nil
                if f:IsVisible() and f.unit and UnitExists(f.unit) then self:UpdateAll(f) end
            end
        end
    end
end

function A:BuildParty()
    local db = A.CopyDefaults(A.partyDefaults, self.db.party)
    self.db.party = db
    holder = CreateFrame("Frame", "HUIPartyHolder", UIParent, "SecureHandlerStateTemplate")
    holder:SetScale(self.db.scale)
    self.partyHolder = holder
    for i = 1, 5 do
        local f = MakeFrame("HUIParty" .. i, "party" .. i)
        local pet = MakeFrame("HUIPartyPet" .. i, "partypet" .. i, true)
        slots[i] = { frame = f, pet = pet }
    end
    self:RegisterMover("Party", holder, "Party")
    self:LayoutParty()
    -- leaving combat: apply anything changed while fighting
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("UNIT_PET")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            if A.partyDirty then A.partyDirty = nil; A:LayoutParty() end
            return
        end
        for _, s in ipairs(slots) do
            if s.pet:IsVisible() then A:UpdateAll(s.pet) end
        end
    end)

    -- range / offline fade, the same as the raid frames: offline 35%, out of
    -- range 40%. A pet takes its owner's fade (the game can't tell a pet's range).
    local t = 0
    ev:SetScript("OnUpdate", A:PerfWrap("Party frames: range", function(_, el)
        t = t + el
        if t < 0.4 then return end
        t = 0
        local on = DB().range ~= false
        for _, s in ipairs(slots) do
            local f, pet = s.frame, s.pet
            local alpha = 1
            local u = f.unit
            if not A.partyTest and u and f:IsVisible() and UnitExists(u) then
                if not UnitIsConnected(u) then
                    alpha = 0.35
                elseif on and not UnitIsUnit(u, "player") and not UnitInRange(u) then
                    alpha = 0.4
                end
            end
            if f:GetAlpha() ~= alpha then f:SetAlpha(alpha) end
            if pet:GetAlpha() ~= alpha then pet:SetAlpha(alpha) end
        end
    end))
end
