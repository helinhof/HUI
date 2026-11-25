-- HUI - Quality of life (ported from the retail essentials addon to 3.3.5)
--   Automation: sell junk, repair, invites, resurrects, duels, quests, loot,
--               DELETE fill-in, cinematics, role checks, red error text
--   Move frames: drag Blizzard windows, optionally remember where they were put
--   Copy:        hover something + Ctrl+C for a copy box, and a chat copy button

local A = HUI
local floor, format, select = math.floor, string.format, select

local function Ev(handler, ...)
    local f = CreateFrame("Frame")
    for i = 1, select("#", ...) do f:RegisterEvent((select(i, ...))) end
    f:SetScript("OnEvent", handler)
    return f
end

local function Money(c)
    local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
    if g > 0 then return format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r", g, s, cp) end
    if s > 0 then return format("|cffc7c7cf%ds|r |cffeda55f%dc|r", s, cp) end
    return format("|cffeda55f%dc|r", cp)
end

------------------------------------------------------------------------
-- Automation
------------------------------------------------------------------------
local function DB() return A.db.auto end
local function On(key) local d = A.db.auto return d.enabled and d[key] end

local function SellJunkAndRepair()
    if On("sellJunk") then
        local total, n = 0, 0
        for bag = 0, 4 do
            for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(link)
                    if quality == 0 and price and price > 0 then
                        local _, count = GetContainerItemInfo(bag, slot)
                        total = total + price * (count or 1)
                        n = n + 1
                        UseContainerItem(bag, slot)
                    end
                end
            end
        end
        if n > 0 then A:Print(format("sold %d junk item%s for %s.", n, n == 1 and "" or "s", Money(total))) end
    end
    if On("repair") and CanMerchantRepair() then
        local cost, can = GetRepairAllCost()
        if can and cost and cost > 0 then
            local guild = DB().guildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
            if guild then
                local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
                if limit == -1 or limit >= cost then
                    RepairAllItems(1)
                    A:Print("repaired for " .. Money(cost) .. " |cff999999(guild bank)|r.")
                    return
                end
            end
            if GetMoney() >= cost then
                RepairAllItems()
                A:Print("repaired for " .. Money(cost) .. ".")
            else
                A:Print("not enough money to repair (" .. Money(cost) .. ").")
            end
        end
    end
end

local function IsFriendOrGuild(name)
    if not name then return false end
    name = name:match("^([^%-]+)") or name
    for i = 1, GetNumFriends() do
        if GetFriendInfo(i) == name then return true end
    end
    if IsInGuild() then
        if GuildRoster then GuildRoster() end
        for i = 1, GetNumGuildMembers(true) do
            local n = GetGuildRosterInfo(i)
            if n == name then return true end
        end
    end
    return false
end

-- quests: Shift held while talking to the NPC skips everything
local function QuestPaused() return DB().shiftSkips and IsShiftKeyDown() end

-- 3.3.5 gossip quest lists are flat (title, level, trivial[, complete]) groups
local function GossipStride(count, ...)
    if count == 0 then return 0 end
    return floor(select("#", ...) / count)
end

local function BestRewardIndex(n)
    local best, bestV = nil, -1
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        local price = link and select(11, GetItemInfo(link)) or 0
        local _, _, count = GetQuestItemInfo("choice", i)
        local v = (price or 0) * (count or 1)
        if v > bestV then best, bestV = i, v end
    end
    return best
end

local function OnQuestEvent(event)
    if not DB().enabled or QuestPaused() then return end
    local accept, turnin = On("acceptQuests"), On("turnInQuests")
    if event == "GOSSIP_SHOW" then
        if turnin then
            local n = GetNumGossipActiveQuests()
            local stride = GossipStride(n, GetGossipActiveQuests())
            if stride >= 4 then
                local t = { GetGossipActiveQuests() }
                for i = 1, n do
                    if t[(i - 1) * stride + 4] then SelectGossipActiveQuest(i) return end
                end
            end
        end
        if accept and GetNumGossipAvailableQuests() > 0 then SelectGossipAvailableQuest(1) end
    elseif event == "QUEST_GREETING" then
        if turnin then
            for i = 1, GetNumActiveQuests() do
                local _, complete = GetActiveTitle(i)
                if complete then SelectActiveQuest(i) return end
            end
        end
        if accept and GetNumAvailableQuests() > 0 then SelectAvailableQuest(1) end
    elseif event == "QUEST_DETAIL" then
        if accept then AcceptQuest() end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if accept and ConfirmAcceptQuest then ConfirmAcceptQuest(); StaticPopup_Hide("QUEST_ACCEPT") end
    elseif event == "QUEST_PROGRESS" then
        if turnin and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        if not turnin then return end
        local n = GetNumQuestChoices()
        if n <= 1 then
            GetQuestReward(n)
        elseif DB().bestReward then
            local best = BestRewardIndex(n)
            if best then GetQuestReward(best) end
        end
    end
end

local function FillDelete(popup)
    if not On("fillDelete") then return end
    local eb = popup and (popup.editBox or _G[popup:GetName() .. "EditBox"])
    if eb and DELETE_ITEM_CONFIRM_STRING then
        eb:SetText(DELETE_ITEM_CONFIRM_STRING)
        local b = popup.button1 or _G[popup:GetName() .. "Button1"]
        if b then b:Enable() end
    end
end

local errorsHidden
function A:UpdateErrorFilter()
    local mode = self.db.auto.enabled and self.db.auto.hideErrors or "NEVER"
    local hide = mode == "ALWAYS" or (mode == "COMBAT" and UnitAffectingCombat("player"))
    if hide and not errorsHidden then
        UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        errorsHidden = true
    elseif not hide and errorsHidden then
        UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        errorsHidden = false
    end
end

function A:ApplyAutoLoot()
    if self.db.auto.enabled and self.db.auto.autoLoot ~= nil then
        SetCVar("autoLootDefault", self.db.auto.autoLoot and "1" or "0")
    end
end

function A:BuildAutomation()
    Ev(function(_, event, ...)
        local d = DB()
        if not d.enabled then return end
        if event == "MERCHANT_SHOW" then
            if not IsShiftKeyDown() then SellJunkAndRepair() end
        elseif event == "PARTY_INVITE_REQUEST" then
            if not d.acceptInvites then return end
            if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then return end
            local name = ...
            if d.inviteFrom == "ANYONE" or IsFriendOrGuild(name) then
                AcceptGroup()
                self.inviteAccepted = true
            end
        elseif event == "PARTY_MEMBERS_CHANGED" then
            if self.inviteAccepted then StaticPopup_Hide("PARTY_INVITE"); self.inviteAccepted = nil end
        elseif event == "RESURRECT_REQUEST" then
            local who = ...
            local inCombat = who and UnitAffectingCombat(who)
            if (inCombat and d.acceptCombatRes) or (not inCombat and d.acceptRes) then
                AcceptResurrect()
                StaticPopup_Hide("RESURRECT")
                StaticPopup_Hide("RESURRECT_NO_SICKNESS")
                StaticPopup_Hide("RESURRECT_NO_TIMER")
            end
        elseif event == "DUEL_REQUESTED" then
            if d.declineDuels then CancelDuel(); StaticPopup_Hide("DUEL_REQUESTED") end
        elseif event == "LFG_ROLE_CHECK_SHOW" then
            if d.roleCheck and CompleteLFGRoleCheck then CompleteLFGRoleCheck(true) end
        elseif event == "CONFIRM_LOOT_ROLL" then
            if d.confirmRolls then
                local id, rollType = ...
                ConfirmLootRoll(id, rollType)
                StaticPopup_Hide("CONFIRM_LOOT_ROLL")
            end
        elseif event == "LOOT_BIND_CONFIRM" then
            if d.confirmBoP and GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
                local slot = ...
                ConfirmLootSlot(slot)
                StaticPopup_Hide("LOOT_BIND")
            end
        elseif event == "LOOT_OPENED" then
            if d.fastLoot then
                local auto = ...
                if auto == 1 or (GetCVar("autoLootDefault") == "1") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
                    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
                end
            end
        elseif event == "CINEMATIC_START" then
            if d.skipCinematics and not IsShiftKeyDown() then
                if CinematicFrame_CancelCinematic then CinematicFrame_CancelCinematic() else StopCinematic() end
            end
        elseif event == "CONFIRM_SUMMON" then
            if d.acceptSummon and not UnitAffectingCombat("player") then
                ConfirmSummon()
                StaticPopup_Hide("CONFIRM_SUMMON")
            end
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            A:UpdateErrorFilter()
        else
            OnQuestEvent(event)
        end
    end, "MERCHANT_SHOW", "PARTY_INVITE_REQUEST", "PARTY_MEMBERS_CHANGED", "RESURRECT_REQUEST",
        "DUEL_REQUESTED", "LFG_ROLE_CHECK_SHOW", "CONFIRM_LOOT_ROLL", "LOOT_BIND_CONFIRM", "LOOT_OPENED",
        "CINEMATIC_START", "CONFIRM_SUMMON", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS",
        "QUEST_COMPLETE")

    -- pre-rendered movies (MovieFrame) are skipped too
    if MovieFrame then
        MovieFrame:HookScript("OnShow", function(self)
            if On("skipCinematics") and not IsShiftKeyDown() then
                if GameMovieFinished then GameMovieFinished() end
                self:Hide()
            end
        end)
    end

    for _, which in ipairs({ "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM" }) do
        local d = StaticPopupDialogs[which]
        if d and d.OnShow then hooksecurefunc(d, "OnShow", FillDelete) end
    end

    self:UpdateErrorFilter()
    self:ApplyAutoLoot()
end

------------------------------------------------------------------------
-- Move frames: drag Blizzard windows with the left mouse button
------------------------------------------------------------------------
local MOVABLE = {
    [""] = {
        "CharacterFrame", "SpellBookFrame", "QuestLogFrame", "QuestLogDetailFrame", "FriendsFrame",
        "PVPParentFrame", "LFDParentFrame", "LFRParentFrame", "MerchantFrame", "GossipFrame",
        "QuestFrame", "MailFrame", "OpenMailFrame", "BankFrame", "TradeFrame", "TaxiFrame",
        "DressUpFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "ItemTextFrame",
        "HelpFrame", "InterfaceOptionsFrame", "VideoOptionsFrame", "AudioOptionsFrame",
        "ChatConfigFrame", "PetStableFrame", "ArenaFrame", "ArenaRegistrarFrame",
        "ReadyCheckFrame", "WorldStateScoreFrame", "RaidInfoFrame",
        "ColorPickerFrame", "GearManagerDialog", "StackSplitFrame", "BattlefieldFrame",
    },
    Blizzard_TalentUI       = { "PlayerTalentFrame" },
    Blizzard_GlyphUI        = { "GlyphFrame" },
    Blizzard_MacroUI        = { "MacroFrame" },
    Blizzard_BindingUI      = { "KeyBindingFrame" },
    Blizzard_AchievementUI  = { "AchievementFrame" },
    Blizzard_InspectUI      = { "InspectFrame" },
    Blizzard_TradeSkillUI   = { "TradeSkillFrame" },
    Blizzard_TrainerUI      = { "ClassTrainerFrame" },
    Blizzard_AuctionUI      = { "AuctionFrame" },
    Blizzard_GuildBankUI    = { "GuildBankFrame" },
    Blizzard_Calendar       = { "CalendarFrame" },
    Blizzard_TimeManager    = { "TimeManagerFrame" },
    Blizzard_BarbershopUI   = { "BarberShopFrame" },
    Blizzard_ItemSocketingUI = { "ItemSocketingFrame" },
}

local function ModifierOK()
    local m = A.db.moveFrames.modifier
    if m == "SHIFT" then return IsShiftKeyDown() end
    if m == "CTRL" then return IsControlKeyDown() end
    if m == "ALT" then return IsAltKeyDown() end
    return true
end

local function SavePos(f)
    local p, _, rp, x, y = f:GetPoint()
    if p then A.db.moveFrames.positions[f:GetName()] = { p, rp, floor(x + 0.5), floor(y + 0.5) } end
end

local function RestorePos(f)
    local db = A.db.moveFrames
    local p = db.enabled and db.remember and db.positions[f:GetName()]
    if not p then return end
    if f:IsProtected() and InCombatLockdown() then return end
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function StartDrag(win)
    if not A.db.moveFrames.enabled or not ModifierOK() then return end
    if win:IsProtected() and InCombatLockdown() then return end
    win.atrMoving = true
    win:StartMoving()
end

local function StopDrag(win)
    if not win.atrMoving then return end
    win.atrMoving = nil
    win:StopMovingOrSizing()
    win:SetUserPlaced(false)   -- don't let the layout cache keep it forever
    if A.db.moveFrames.remember then SavePos(win) end
end

-- Most windows are covered by inner panels (paper doll, spell list, quest
-- details...) that take the mouse, so a drag never reaches the window itself.
-- Plain frames inside the window pass their drags up; buttons, edit boxes and
-- sliders keep working as before.
local PASS = { Frame = true, ScrollFrame = true }
local function ForwardDrags(win, f, depth)
    for _, c in ipairs({ f:GetChildren() }) do
        if not c.atrDragFwd and PASS[c:GetObjectType()] and not (c:IsProtected() and InCombatLockdown()) then
            c.atrDragFwd = true
            if c:IsMouseEnabled() then
                c:RegisterForDrag("LeftButton")
                c:HookScript("OnDragStart", function() StartDrag(win) end)
                c:HookScript("OnDragStop", function() StopDrag(win) end)
            end
            if depth < 3 then ForwardDrags(win, c, depth + 1) end
        end
    end
end

local MakeMovable, ScaleWindow   -- ScaleWindow: see "Window scale" below
function MakeMovable(name)
    local f = _G[name]
    if not f or f.atrMovable or not f.SetMovable then return end
    -- protected windows (character sheet, spellbook) can be set up and moved
    -- out of combat only; StartDrag refuses them in combat
    if f:IsProtected() and InCombatLockdown() then
        A:RunOOC(function() MakeMovable(name) end)
        return
    end
    f.atrMovable = true
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:HookScript("OnDragStart", StartDrag)
    f:HookScript("OnDragStop", StopDrag)
    ForwardDrags(f, f, 1)
    -- the game re-anchors panels when they open; put remembered ones back after that,
    -- and pick up inner panels created since
    f:HookScript("OnShow", function(self)
        if not InCombatLockdown() then ForwardDrags(self, self, 1) end
        if not A.db.moveFrames.remember then return end
        local t = 0
        local d = self.atrDelay or CreateFrame("Frame")
        self.atrDelay = d
        d:SetScript("OnUpdate", function(s, el)
            t = t + el
            if t < 0.01 then return end
            s:SetScript("OnUpdate", nil)
            RestorePos(self)
        end)
    end)
end

function A:BuildMoveFrames()
    local function Process(list)
        for _, n in ipairs(list or {}) do pcall(MakeMovable, n) end
    end
    Process(MOVABLE[""])
    for addon, list in pairs(MOVABLE) do
        if addon ~= "" and IsAddOnLoaded(addon) then Process(list) end
    end
    Ev(function(_, _, addon)
        Process(MOVABLE[addon])
        for _, n in ipairs(MOVABLE[addon] or {}) do pcall(ScaleWindow, n) end
    end, "ADDON_LOADED")
end

------------------------------------------------------------------------
-- Window scale: every Blizzard window above (and the loot window) drawn a
-- bit smaller ("Window scale" on the General page). They all share one
-- scale, so the game still lays them out side by side as before.
------------------------------------------------------------------------
function ScaleWindow(name)
    local f = _G[name]
    if not (f and f.SetScale) then return end
    local s = A.db.windowScale or 1
    if math.abs(f:GetScale() - s) < 0.001 then return end
    if f:IsProtected() and InCombatLockdown() then
        A:RunOOC(function() ScaleWindow(name) end)
        return
    end
    f:SetScale(s)
end

function A:ApplyWindowScale()
    for addon, list in pairs(MOVABLE) do
        if addon == "" or IsAddOnLoaded(addon) then
            for _, n in ipairs(list) do pcall(ScaleWindow, n) end
        end
    end
    pcall(ScaleWindow, "LootFrame")
    if self.PlaceLootAnchor then self:PlaceLootAnchor() end
end

------------------------------------------------------------------------
-- Popup scale: confirmation popups (delete item, battleground entry, ...),
-- the dungeon finder "ready" and role check popups, the ready check and the
-- Esc menu ("Popup scale" on the General page).
------------------------------------------------------------------------
local POPUPS = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
    "LFDDungeonReadyPopup", "LFDRoleCheckPopup", "ReadyCheckFrame", "GameMenuFrame" }

-- raid warnings and boss emotes in the middle of the screen ("Raid warning
-- size" on the General page). The game animates their text height, so the
-- frames are scaled instead of given a smaller font.
function A:ApplyRaidWarningScale()
    local s = self.db.raidWarnScale or 1
    for _, f in ipairs({ RaidWarningFrame, RaidBossEmoteFrame }) do
        if f and f.SetScale then f:SetScale(s) end
    end
end

function A:ApplyPopupScale()
    local s = self.db.popupScale or 1
    for _, n in ipairs(POPUPS) do
        local f = _G[n]
        if f and f.SetScale and math.abs(f:GetScale() - s) > 0.001 then
            if f:IsProtected() and InCombatLockdown() then
                self:RunOOC(function() A:ApplyPopupScale() end)
                return
            end
            f:SetScale(s)
        end
    end
end

------------------------------------------------------------------------
-- Loot window: placed at its own mover ("Loot window" in unlock mode)
-- instead of the game's left panel slot. With the game's "loot under
-- mouse" option on it still opens at the cursor.
------------------------------------------------------------------------
local lootAnchor
-- the visible box of the loot window (the skin draws it inside a larger
-- frame) and its offset from the frame's top-left, in loot frame units
local function LootBox()
    local w, h = LootFrame:GetWidth(), LootFrame:GetHeight()
    if LootFrame.backdrop then return w - 16 - 77, h - 54 - 8, 16, 54 end
    return w, h, 0, 0
end

local function PlaceLoot()
    if not lootAnchor or GetCVar("lootUnderMouse") == "1" then return end
    local _, _, ox, oy = LootBox()
    LootFrame:ClearAllPoints()
    LootFrame:SetPoint("TOPLEFT", lootAnchor, "TOPLEFT", -ox, oy)
end

function A:PlaceLootAnchor()
    if not lootAnchor then return end
    local w, h = LootBox()
    local s = LootFrame:GetScale()
    lootAnchor:SetWidth(w * s)
    lootAnchor:SetHeight(h * s)
    self:ApplyPosition("Loot", lootAnchor)
    if LootFrame:IsShown() then PlaceLoot() end
end

function A:BuildLootMover()
    if not LootFrame or lootAnchor then return end
    lootAnchor = CreateFrame("Frame", "HUILootAnchor", UIParent)
    -- out of the game's panel layout so it isn't pushed around; Escape still closes it
    if UIPanelWindows then UIPanelWindows["LootFrame"] = nil end
    if UISpecialFrames then
        local listed
        for _, n in ipairs(UISpecialFrames) do if n == "LootFrame" then listed = true end end
        if not listed then tinsert(UISpecialFrames, "LootFrame") end
    end
    LootFrame:HookScript("OnShow", PlaceLoot)
    self:PlaceLootAnchor()
    self:RegisterMover("Loot", lootAnchor, "Loot window")
end

function A:ResetFramePositions()
    wipe(self.db.moveFrames.positions)
    self:Print("window positions reset. They go back to normal the next time they open.")
end

------------------------------------------------------------------------
-- Copy box (shared by Copy Anything and chat copy)
------------------------------------------------------------------------
local copyBox

local function CopyBox()
    if copyBox then return copyBox end
    local f = CreateFrame("Frame", "HUICopyFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    A:Size(f, 520, 300)
    f:SetPoint("CENTER")
    A:SetTemplate(f, 0.97)
    f:SetBackdropBorderColor(0.17, 0.17, 0.19, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "HUICopyFrame")

    local title = f:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(title, A.media.font, 12, "")
    title:SetShadowOffset(1, -1)
    title:SetPoint("TOPLEFT", 10, -8)
    f.title = title
    local hint = f:CreateFontString(nil, "OVERLAY")
    A:SetFontPx(hint, A.media.font, 11, "")
    hint:SetTextColor(0.55, 0.55, 0.6)
    hint:SetPoint("TOPRIGHT", -30, -9)
    hint:SetText("Ctrl+C to copy, Esc to close")
    f.hint = hint
    local close = A:CreateButton(f, "x", 18, 16, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)

    local sf = CreateFrame("ScrollFrame", "HUICopyScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -28)
    sf:SetPoint("BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    A:SetFontPx(eb, A.media.font, 12, "")
    eb:SetWidth(470)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function(self, user)
        if user and f.locked then self:SetText(f.text or "") self:HighlightText() end
    end)
    sf:SetScrollChild(eb)
    f.eb, f.sf = eb, sf
    copyBox = f
    return f
end

function A:ShowCopy(title, text, single)
    local f = CopyBox()
    if f.importBtn then f.importBtn:Hide() end
    if f.colorBtn then f.colorBtn:Hide() end
    f.hint:Show()
    f.title:SetText(title)
    f.text = text
    f.locked = true
    f:SetHeight(single and 64 or 300)
    f.eb:SetText(text)
    f:Show()
    f.eb:SetFocus()
    f.eb:HighlightText()
    if not single then
        f.sf:UpdateScrollChildRect()
        local maxV = f.sf:GetVerticalScrollRange()
        f.sf:SetVerticalScroll(maxV or 0)
    end
end

------------------------------------------------------------------------
-- Copy Anything: hover a spell, item, unit or tooltip and press Ctrl+C
------------------------------------------------------------------------
local function TooltipText()
    if not GameTooltip:IsShown() then return end
    local name, link = GameTooltip:GetItem()
    if link then
        local id = link:match("item:(%d+)")
        return name .. (id and ("  (item " .. id .. ")") or ""), link
    end
    local sname, rank = GameTooltip:GetSpell()
    if sname then return sname .. ((rank and rank ~= "") and (" (" .. rank .. ")") or "") end
    local uname = GameTooltip:GetUnit()
    if uname then return uname end
    local line = _G["GameTooltipTextLeft1"]
    return line and line:GetText()
end

local copyBtn
function A:UpdateCopyBinding()
    if not copyBtn then
        copyBtn = CreateFrame("Button", "HUICopyAnythingButton", UIParent)
        copyBtn:SetScript("OnClick", function()
            local text = TooltipText()
            if text and text ~= "" then
                A:ShowCopy("Copy", text, true)
            end
        end)
    end
    if InCombatLockdown() then
        self:RunOOC(function() A:UpdateCopyBinding() end)
        return
    end
    ClearOverrideBindings(copyBtn)
    local d = self.db.copy
    if d.enabled then
        SetOverrideBindingClick(copyBtn, true, (d.mod or "CTRL") .. "-C", "HUICopyAnythingButton")
    end
end

------------------------------------------------------------------------
-- Chat copy: every chat window remembers its last lines; a small button
-- in the chat header (on mouseover) opens them in the copy box
------------------------------------------------------------------------
local HISTORY = 300
local function Plain(s)
    s = s:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return s
end

-- the line as the chat shows it: in its channel colour, with the colours
-- inside it (class-coloured names, item quality ...). Links become their
-- visible text, icons are dropped. Every "|r" goes back to the line colour,
-- not to white.
local function Colored(e)
    local t = e.text:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    local r, g, b = e.r or 1, e.g or 1, e.b or 1
    local c = format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
    return c .. t:gsub("|r", "|r" .. c) .. "|r"
end

local function Remember(cf)
    if cf.atrHistory then return end
    -- a ring of the last HISTORY lines: dropping the oldest used to shift
    -- all 300 entries down on every chat line
    cf.atrHistory = { first = 1, last = 0 }
    hooksecurefunc(cf, "AddMessage", A:PerfWrap("Chat: copy history", function(self, text, r, g, b)
        if type(text) ~= "string" then return end
        -- text and colour in two plain arrays (no table per chat line)
        local h = self.atrHistory
        local last = h.last + 1
        h.last = last
        h[last] = text
        h.col = h.col or {}
        h.col[last] = (r and g and b) and (floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5)) or false
        if last - h.first + 1 > HISTORY then
            h[h.first] = nil
            h.col[h.first] = nil
            h.first = h.first + 1
        end
    end))
end

local function ChatText(cf, plain)
    local lines = {}
    local h = cf.atrHistory
    if h then
        for i = h.first or 1, h.last or #h do
            local text = h[i]
            if text then
                local c = h.col and h.col[i]
                local e = { text = text }
                if c then e.r, e.g, e.b = floor(c / 65536) / 255, floor(c / 256) % 256 / 255, c % 256 / 255 end
                lines[#lines + 1] = plain and Plain(e.text) or Colored(e)
            end
        end
    end
    return table.concat(lines, "\n")
end

function A:CopyChat(cf)
    cf = cf or SELECTED_CHAT_FRAME or ChatFrame1
    local plain = self.db.copy and self.db.copy.chatPlain
    self:ShowCopy("Chat: " .. (cf.name or cf:GetName()), ChatText(cf, plain))
    -- Colors / Plain switch (plain text pastes cleanly outside the game)
    local f = CopyBox()
    if not f.colorBtn then
        f.colorBtn = A:CreateButton(f, "", 64, 16, function()
            local d = A.db.copy
            d.chatPlain = not d.chatPlain
            A:CopyChat(f.chatFrame)
        end)
        f.colorBtn:SetPoint("RIGHT", f.hint, "LEFT", -10, 0)
    end
    f.chatFrame = cf
    local fs = f.colorBtn.text or f.colorBtn:GetFontString()
    if fs then fs:SetText(plain and "Plain" or "Colors") end
    f.colorBtn:Show()
end

function A:BuildChatCopy()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf ~= ChatFrame2 then Remember(cf) end
    end
    local parent = self.chatBox or ChatFrame1
    local b = CreateFrame("Button", "HUIChatCopyButton", parent)
    self:Size(b, 18, 16)
    if self.chatHeader then
        b:SetPoint("TOPRIGHT", self.chatHeader, "BOTTOMRIGHT", -3, -4)
    else
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -3)
    end
    b:SetFrameStrata("MEDIUM")
    self:SetTemplate(b, 0.9)
    b.text = self:Font(b, 10, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText("C")
    b:SetScript("OnClick", function() A:CopyChat() end)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(A.accent[1], A.accent[2], A.accent[3])
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Copy chat")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0); GameTooltip:Hide() end)
    self.chatCopyButton = b
    -- only on mouseover of the chat box
    local box = self.chatBox or ChatFrame1
    local acc = 0
    b:SetScript("OnUpdate", function(self, el)
        acc = acc + el
        if acc < 0.1 then return end
        acc = 0
        local show = A.db.copy.chatButton and (MouseIsOver(box) or MouseIsOver(self))
        A:FadeTo(self, show and 1 or 0)
        self:EnableMouse(show and true or false)
    end)
    if FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function()
            for i = 1, 20 do
                local cf = _G["ChatFrame" .. i]
                if cf and cf ~= ChatFrame2 then Remember(cf) end
            end
        end)
    end
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- Zone names in white (minimap and the big text when entering a zone,
-- with its "(Alliance Territory)" / "(Sanctuary)" line), instead of green /
-- red / yellow by PvP status
------------------------------------------------------------------------
function A:WhiteZoneText()
    for _, fs in ipairs({ MinimapZoneText, ZoneTextString, SubZoneTextString, PVPInfoTextString, PVPArenaTextString }) do
        if fs and not fs.huiWhite then
            fs.huiWhite = true
            local busy
            hooksecurefunc(fs, "SetTextColor", function(self)
                if busy or not A.db.zoneTextWhite then return end
                busy = true
                self:SetTextColor(1, 1, 1)
                busy = false
            end)
            if A.db.zoneTextWhite then fs:SetTextColor(1, 1, 1) end
        end
    end
end

function A:BuildQoL()
    self:Safe("zone text", function() self:WhiteZoneText() end)
    self:Safe("automation", function() A:BuildAutomation() end)
    self:Safe("move frames", function() A:BuildMoveFrames() end)
    self:Safe("loot window", function() A:BuildLootMover() end)
    self:Safe("loot rolls", function() A:BuildLootRolls() end)
    self:Safe("window scale", function() A:ApplyWindowScale() end)
    self:Safe("popup scale", function() A:ApplyPopupScale() end)
    self:Safe("raid warning scale", function() A:ApplyRaidWarningScale() end)
    self:Safe("copy", function() A:UpdateCopyBinding() end)
    self:Safe("chat copy", function() A:BuildChatCopy() end)
end


------------------------------------------------------------------------
-- Profile: every HUI setting (colours, sizes, positions, options) as one
-- text to copy, and the same text pasted back to load them.
------------------------------------------------------------------------
local SKIP = { barsToggledChars = true, msaaTried = true }   -- per character / per PC

local function Ser(v, ind)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        local out = { "{\n" }
        for _, k in ipairs(keys) do
            if not (ind == "" and SKIP[k]) then
                local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
                out[#out + 1] = ind .. "  " .. key .. " = " .. Ser(v[k], ind .. "  ") .. ",\n"
            end
        end
        out[#out + 1] = ind .. "}"
        return table.concat(out)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    end
    return "nil"
end

function A:ExportAll()
    local t = {}
    for k, v in pairs(HUIDB) do t[k] = v end
    return "-- HUI settings (" .. (GetAddOnMetadata("HUI", "Version") or "?") .. ")\n" .. Ser(t, "")
end

function A:ImportAll(text)
    if type(text) ~= "string" or not text:find("{") then return false, "no settings found in the text" end
    local body = text:sub(text:find("{"))
    local fn, err = loadstring("return " .. body)
    if not fn then return false, "the text is incomplete or damaged" end
    setfenv(fn, {})   -- data only: no access to anything
    local ok, t = pcall(fn)
    if not ok or type(t) ~= "table" then return false, "the text is incomplete or damaged" end
    local keep = {}
    for k in pairs(SKIP) do keep[k] = HUIDB[k] end
    wipe(HUIDB)
    for k, v in pairs(t) do HUIDB[k] = v end
    for k, v in pairs(keep) do HUIDB[k] = v end
    HUIDB.dbmState = nil   -- from settings exported by older versions
    return true
end

StaticPopupDialogs["HUI_IMPORT_DONE"] = {
    text = "HUI settings loaded. Reload the interface to apply them?",
    button1 = "Reload", button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function A:ShowExportAll()
    self:ShowCopy("All HUI settings  (Ctrl+A, Ctrl+C)", self:ExportAll())
end

function A:ShowImportAll()
    local f = CopyBox()
    f.title:SetText("Import HUI settings  (paste with Ctrl+V, then Import)")
    f.text, f.locked = "", false
    f:SetHeight(300)
    f.eb:SetText("")
    f.eb:SetMaxLetters(0)
    if not f.importBtn then
        f.importBtn = A:CreateButton(f, "Import", 90, 18, function()
            local ok, err = A:ImportAll(f.eb:GetText())
            if ok then
                f:Hide()
                StaticPopup_Show("HUI_IMPORT_DONE")
            else
                A:Print("import failed: " .. tostring(err) .. ".")
            end
        end)
        f.importBtn:SetPoint("TOPRIGHT", -28, -6)
    end
    f.importBtn:Show()
    f.hint:Hide()
    f:Show()
    f.eb:SetFocus()
end
