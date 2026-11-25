-- HUI - Dark skin for the Blizzard windows
-- Parchment, wood and metal art is removed and replaced by the same dark panel
-- (1px black border, background colour) as the rest of the UI. Tabs, close
-- buttons, panel buttons and icon slots get the flat style too, and texts that
-- were black on parchment are turned light so they stay readable.

local A = HUI
local ipairs, pairs, select = ipairs, pairs, select

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
-- hide every texture region of a frame (not its children), except those whose
-- name matches `keep`
function A:StripTextures(f, keep)
    if not f or not f.GetRegions then return end
    for i = 1, select("#", f:GetRegions()) do
        local r = select(i, f:GetRegions())
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            local n = r:GetName()
            if not (keep and n and n:find(keep)) then
                r:SetTexture(nil)
                r:SetAlpha(0)
            end
        end
    end
end

-- dark panel behind a frame; l, t, r, b are the insets of the visible area
local function Panel(f, l, t, r, b)
    if not f or f.atrPanel then return end
    local bg = CreateFrame("Frame", nil, f)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", l or 0, t or 0)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", r or 0, b or 0)
    bg:SetFrameLevel(math.max(0, f:GetFrameLevel()))
    A:SetTemplate(bg)
    f.atrPanel = bg
    return bg
end
A.SkinPanel = Panel

local CLOSE = "Interface\\AddOns\\HUI\\media\\close"
local function SkinClose(b, anchor)
    if not b or b.atrSkinned then return end
    b.atrSkinned = true
    b:SetNormalTexture("")
    b:SetPushedTexture("")
    b:SetHighlightTexture("")
    if b.SetDisabledTexture then b:SetDisabledTexture("") end
    b:SetWidth(18); b:SetHeight(18)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetTexture(CLOSE)
    t:SetAllPoints(b)
    t:SetVertexColor(0.6, 0.6, 0.63)
    b:HookScript("OnEnter", function() t:SetVertexColor(1, 1, 1) end)
    b:HookScript("OnLeave", function() t:SetVertexColor(0.6, 0.6, 0.63) end)
    if anchor then
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -3, -3)
    end
end
A.SkinClose = SkinClose

-- standard red panel buttons (UIPanelButtonTemplate and friends)
local function SkinButton(b)
    if not b or b.atrSkinned then return end
    b.atrSkinned = true
    local n = b:GetName()
    for _, part in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        local t = n and _G[n .. part]
        if t then t:SetTexture(nil); t:SetAlpha(0) end
    end
    if b.GetNormalTexture and b:GetNormalTexture() then b:GetNormalTexture():SetAlpha(0) end
    if b.GetPushedTexture and b:GetPushedTexture() then b:GetPushedTexture():SetAlpha(0) end
    if b.GetDisabledTexture and b:GetDisabledTexture() then b:GetDisabledTexture():SetAlpha(0) end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then hl:SetTexture(1, 1, 1, 0.08); hl:SetAllPoints(b) end
    A:SetTemplate(b)
    b.atrCustomBg = true
    b:SetBackdropColor(0.1, 0.1, 0.115, 1)
    b:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(A.accent[1], A.accent[2], A.accent[3]) end)
    b:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0) end)
end
A.SkinButton = SkinButton

-- bottom tabs (CharacterFrameTab1 ...)
local function SkinTab(tab)
    if not tab or tab.atrSkinned then return end
    tab.atrSkinned = true
    A:StripTextures(tab)
    local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
    if hl then hl:SetTexture(nil) end
    local bg = CreateFrame("Frame", nil, tab)
    bg:SetPoint("TOPLEFT", tab, "TOPLEFT", 10, -3)
    bg:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -10, 3)
    bg:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
    A:SetTemplate(bg)
    tab.atrBg = bg
    tab:HookScript("OnEnter", function() bg:SetBackdropBorderColor(A.accent[1], A.accent[2], A.accent[3]) end)
    tab:HookScript("OnLeave", function() bg:SetBackdropBorderColor(0, 0, 0) end)
end
A.SkinTab = SkinTab

-- square icon buttons (item slots, spell buttons): cropped icon + 1px border
local function SkinIcon(b, icon)
    if not b or b.atrSkinned then return end
    b.atrSkinned = true
    local n = b:GetName()
    icon = icon or (n and (_G[n .. "IconTexture"] or _G[n .. "Icon"]))
    for i = 1, select("#", b:GetRegions()) do
        local r = select(i, b:GetRegions())
        if r and r:GetObjectType() == "Texture" and r ~= icon
            and r ~= (b.GetHighlightTexture and b:GetHighlightTexture())
            and r ~= (b.GetCheckedTexture and b:GetCheckedTexture()) then
            local dl = r:GetDrawLayer()
            if dl == "BACKGROUND" or dl == "BORDER" then r:SetTexture(nil); r:SetAlpha(0) end
        end
    end
    if b.GetNormalTexture and b:GetNormalTexture() then b:GetNormalTexture():SetTexture(nil) end
    if b.GetPushedTexture and b:GetPushedTexture() then b:GetPushedTexture():SetTexture(1, 1, 1, 0.15) end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then hl:SetTexture(1, 1, 1, 0.12) end
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        if hl then hl:SetAllPoints(icon) end
    end
    A:SetTemplate(b)
end
A.SkinIcon = SkinIcon

-- icon tabs on the side of a window (spellbook schools, dual spec): keep the
-- icon, drop the round frame around it, 1px border instead
local function SideTab(t)
    if not t or t.atrSkinned then return end
    t.atrSkinned = true
    local nt = t.GetNormalTexture and t:GetNormalTexture()
    local hl = t.GetHighlightTexture and t:GetHighlightTexture()
    local ck = t.GetCheckedTexture and t:GetCheckedTexture()
    for j = 1, select("#", t:GetRegions()) do
        local r = select(j, t:GetRegions())
        if r and r:GetObjectType() == "Texture" and r ~= nt and r ~= hl and r ~= ck then
            r:SetTexture(nil)
        end
    end
    if nt then
        nt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        nt:ClearAllPoints(); nt:SetPoint("TOPLEFT", 1, -1); nt:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    if hl then hl:SetTexture(1, 1, 1, 0.15); hl:SetAllPoints(nt or t) end
    if ck then ck:SetTexture(1, 1, 1, 0.12); ck:SetAllPoints(nt or t) end
    A:SetTemplate(t)
end

local function Tabs(prefix, n)
    for i = 1, n do SkinTab(_G[prefix .. i]) end
end

local function Buttons(...)
    for i = 1, select("#", ...) do SkinButton(_G[select(i, ...)]) end
end

-- a whole window: strip its art (and that of the listed sub-frames), dark
-- panel with the given insets, flat close button
local function Window(name, l, t, r, b, subs, keep)
    local f = _G[name]
    if not f then return end
    if f.GetBackdrop and f:GetBackdrop() then f:SetBackdrop(nil) end
    A:StripTextures(f, keep)
    for _, s in ipairs(subs or {}) do A:StripTextures(_G[s], keep) end
    local p = Panel(f, l, t, r, b)
    local close = _G[name .. "CloseButton"]
    if close then SkinClose(close, p) end
    -- portraits sat in a round hole of the old art: hide them
    local portrait = _G[name .. "Portrait"]
    if portrait and portrait.SetAlpha then portrait:SetAlpha(0) end
    return f, p
end

------------------------------------------------------------------------
-- Readable texts: quest and gossip texts are black for parchment
------------------------------------------------------------------------
local function QuestTexts()
    local white = { "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoRewardText",
        "QuestInfoItemChooseText", "QuestInfoItemReceiveText", "QuestInfoSpellLearnText",
        "QuestInfoXPFrameReceiveText", "QuestInfoGroupSize", "QuestInfoRequiredMoneyText",
        "QuestProgressText", "QuestProgressRequiredMoneyText", "QuestProgressRequiredItemsText",
        "GreetingText", "AvailableQuestsText", "CurrentQuestsText", "QuestDetailText",
        "QuestRewardText", "QuestObjectiveText" }
    local gold = { "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader",
        "QuestInfoRewardsHeader", "QuestProgressTitleText", "QuestTitleText", "QuestDetailObjectiveTitleText",
        "QuestRewardTitleText", "QuestRewardRewardTitleText" }
    for _, n in ipairs(white) do local t = _G[n]; if t and t.SetTextColor then t:SetTextColor(0.9, 0.9, 0.9) end end
    for _, n in ipairs(gold) do local t = _G[n]; if t and t.SetTextColor then t:SetTextColor(1, 0.82, 0) end end
    for i = 1, 12 do
        local o = _G["QuestInfoObjective" .. i]
        if o and o.GetText and o:GetText() then
            local r, g, b = o:GetTextColor()
            if r < 0.3 and g < 0.3 and b < 0.3 then
                -- black = not done yet, dark grey = done
                if r > 0.1 then o:SetTextColor(0.55, 0.55, 0.55) else o:SetTextColor(0.9, 0.9, 0.9) end
            end
        end
    end
end

local function GossipTexts()
    if GossipGreetingText then GossipGreetingText:SetTextColor(0.9, 0.9, 0.9) end
    for i = 1, (NUMGOSSIPBUTTONS or 32) do
        local b = _G["GossipTitleButton" .. i]
        if b and b:IsShown() then
            local fs = b:GetFontString()
            local txt = b:GetText()
            if txt and txt:find("|cff000000") then b:SetText((txt:gsub("|cff000000", "|cffffd100"))) end
            if fs then fs:SetTextColor(0.9, 0.9, 0.9) end
        end
    end
end

------------------------------------------------------------------------
-- Windows that are always loaded
------------------------------------------------------------------------
local function SkinCore()
    -- Character (and its tabs: reputation, skills, currency, pet)
    Window("CharacterFrame", 11, -12, -32, 76,
        { "PaperDollFrame", "ReputationFrame", "SkillFrame", "TokenFrame", "PetPaperDollFrame",
          "PetPaperDollFrameCompanionFrame", "PetPaperDollFramePetFrame", "ReputationListScrollFrame",
          "SkillListScrollFrame", "TokenFrameContainer", "ReputationDetailFrame", "SkillDetailScrollFrame" })
    Tabs("CharacterFrameTab", 5)
    Tabs("PetPaperDollFrameTab", 3)
    for _, s in ipairs({ "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands",
        "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand",
        "Ranged", "Ammo" }) do
        SkinIcon(_G["Character" .. s .. "Slot"])
    end
    if ReputationDetailFrame then Panel(ReputationDetailFrame, 6, -6, -6, 6) end
    if ReputationDetailCloseButton then SkinClose(ReputationDetailCloseButton) end

    -- Spellbook
    Window("SpellBookFrame", 10, -12, -31, 75)
    for i = 1, 3 do SkinTab(_G["SpellBookFrameTabButton" .. i]) end
    for i = 1, (SPELLS_PER_PAGE or 12) do
        local b = _G["SpellButton" .. i]
        if b then
            SkinIcon(b, _G["SpellButton" .. i .. "IconTexture"])
            local bg = _G["SpellButton" .. i .. "Background"]; if bg then bg:SetAlpha(0) end
            local sf = _G["SpellButton" .. i .. "SlotFrame"]; if sf then sf:SetAlpha(0) end
        end
    end
    for i = 1, (MAX_SKILLLINE_TABS or 8) do SideTab(_G["SpellBookSkillLineTab" .. i]) end

    -- Quest log (3.3.5 wide log) and its detached detail window
    Window("QuestLogFrame", 10, -12, -1, 8, { "QuestLogCount", "EmptyQuestLogFrame" })
    Window("QuestLogDetailFrame", 10, -12, 0, 4)
    Buttons("QuestLogFrameAbandonButton", "QuestLogFramePushQuestButton", "QuestLogFrameTrackButton",
        "QuestLogFrameCancelButton", "QuestLogFrameShowMapButton")

    -- NPC windows
    Window("GossipFrame", 12, -17, -34, 65, { "GossipFrameGreetingPanel" })
    Buttons("GossipFrameGreetingGoodbyeButton")
    Window("QuestFrame", 12, -17, -34, 65,
        { "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel" })
    Buttons("QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteButton",
        "QuestFrameGoodbyeButton", "QuestFrameCompleteQuestButton", "QuestFrameCancelButton",
        "QuestFrameGreetingGoodbyeButton")
    Window("MerchantFrame", 10, -12, -34, 62)
    Tabs("MerchantFrameTab", 2)
    Window("TaxiFrame", 10, -12, -32, 76)
    Window("TabardFrame", 10, -12, -32, 76)
    Buttons("TabardFrameAcceptButton", "TabardFrameCancelButton")

    -- Social / group
    Window("FriendsFrame", 10, -12, -33, 76, { "FriendsListFrame", "IgnoreListFrame", "WhoFrame", "GuildFrame", "RaidFrame" })
    Tabs("FriendsFrameTab", 5)
    Buttons("FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton", "WhoFrameWhoButton",
        "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton", "GuildFrameAddMemberButton",
        "GuildFrameControlButton", "GuildFrameGuildInformationButton", "RaidFrameConvertToRaidButton",
        "RaidFrameRaidInfoButton", "FriendsFrameIgnorePlayerButton", "FriendsFrameUnsquelchButton")
    Window("PVPParentFrame", 10, -12, -32, 76, { "PVPFrame", "BattlefieldFrame" })
    Tabs("PVPParentFrameTab", 2)
    Window("LFDParentFrame", 10, -12, -1, 8, { "LFDQueueFrame", "LFDQueueFrameBackground" })
    Buttons("LFDQueueFrameFindGroupButton", "LFDQueueFrameCancelButton")

    -- Mail, trade, bank, loot, dress up
    Window("MailFrame", 10, -12, -32, 76, { "InboxFrame", "SendMailFrame" })
    Tabs("MailFrameTab", 2)
    Window("OpenMailFrame", 10, -12, -32, 76)
    Buttons("SendMailMailButton", "SendMailCancelButton", "OpenMailReplyButton", "OpenMailDeleteButton", "OpenMailCancelButton")
    Window("TradeFrame", 10, -12, -30, 52)
    Buttons("TradeFrameTradeButton", "TradeFrameCancelButton")
    Window("BankFrame", 10, -11, -25, 93)
    Buttons("BankFramePurchaseButton")
    Window("LootFrame", 13, -15, -66, 3)
    Window("DressUpFrame", 10, -12, -33, 73)
    Buttons("DressUpFrameCancelButton", "DressUpFrameResetButton")
    Window("ItemTextFrame", 10, -12, -32, 76)

    -- Game menu, options, popups
    Window("GameMenuFrame", 0, 0, 0, 0)
    if GameMenuFrameHeader then GameMenuFrameHeader:SetAlpha(0) end
    for _, n in ipairs({ "GameMenuButtonOptions", "GameMenuButtonSoundOptions", "GameMenuButtonUIOptions",
        "GameMenuButtonKeybindings", "GameMenuButtonMacros", "GameMenuButtonLogout", "GameMenuButtonQuit",
        "GameMenuButtonContinue", "GameMenuButtonHelp", "GameMenuButtonMacOptions", "GameMenuButtonRatings" }) do
        SkinButton(_G[n])
    end
    for _, n in ipairs({ "InterfaceOptionsFrame", "VideoOptionsFrame", "AudioOptionsFrame" }) do
        local f = _G[n]
        if f then
            Window(n, 0, 0, 0, 0)
            local h = _G[n .. "Header"]; if h then h:SetAlpha(0) end
            Buttons(n .. "Okay", n .. "Cancel", n .. "Defaults", n .. "Apply")
        end
    end
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local p = _G["StaticPopup" .. i]
        if p then
            p:SetBackdrop(nil)
            Panel(p, 0, 0, 0, 0)
            for j = 1, 3 do SkinButton(_G["StaticPopup" .. i .. "Button" .. j]) end
        end
    end

    -- texts that were black on parchment
    if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", QuestTexts) end
    for _, n in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel",
        "QuestFrameGreetingPanel", "QuestLogFrame", "QuestLogDetailFrame" }) do
        local f = _G[n]
        if f then f:HookScript("OnShow", QuestTexts) end
    end
    if GossipFrameUpdate then hooksecurefunc("GossipFrameUpdate", GossipTexts) end
    if ItemTextPageText then ItemTextPageText:SetTextColor(0.9, 0.9, 0.9) end
end

------------------------------------------------------------------------
-- Windows from load-on-demand Blizzard addons
------------------------------------------------------------------------
local LOD = {
    Blizzard_TalentUI = function()
        Window("PlayerTalentFrame", 13, -12, -31, 76, nil, "Background")
        Tabs("PlayerTalentFrameTab", 3)
        Buttons("PlayerTalentFrameActivateButton", "PlayerTalentFrameLearnButton", "PlayerTalentFrameResetButton")
        -- dual spec tabs (primary / secondary / pet) stay usable
        for i = 1, 4 do SideTab(_G["PlayerSpecTab" .. i]) end
    end,
    Blizzard_InspectUI = function()
        Window("InspectFrame", 10, -12, -31, 75, { "InspectPaperDollFrame", "InspectPVPFrame", "InspectTalentFrame" }, "Background")
        Tabs("InspectFrameTab", 3)
        for _, s in ipairs({ "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands",
            "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }) do
            SkinIcon(_G["Inspect" .. s .. "Slot"])
        end
    end,
    Blizzard_MacroUI = function()
        Window("MacroFrame", 10, -11, -32, 71)
        Tabs("MacroFrameTab", 2)
        Buttons("MacroDeleteButton", "MacroNewButton", "MacroExitButton", "MacroEditButton", "MacroSaveButton", "MacroCancelButton")
        Window("MacroPopupFrame", 0, 0, 0, 0)
        Buttons("MacroPopupOkayButton", "MacroPopupCancelButton")
    end,
    Blizzard_TradeSkillUI = function()
        Window("TradeSkillFrame", 10, -12, -32, 76)
        Buttons("TradeSkillCreateButton", "TradeSkillCreateAllButton", "TradeSkillCancelButton")
    end,
    Blizzard_TrainerUI = function()
        Window("ClassTrainerFrame", 10, -12, -32, 76)
        Buttons("ClassTrainerTrainButton", "ClassTrainerCancelButton")
    end,
    Blizzard_AuctionUI = function()
        Window("AuctionFrame", 10, -12, 0, 10, { "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions" })
        Tabs("AuctionFrameTab", 3)
        Buttons("BrowseSearchButton", "BrowseBidButton", "BrowseBuyoutButton", "BrowseCloseButton",
            "BidBidButton", "BidBuyoutButton", "BidCloseButton", "AuctionsCreateAuctionButton",
            "AuctionsCancelAuctionButton", "AuctionsCloseButton", "BrowseResetButton")
    end,
    Blizzard_GuildBankUI = function()
        Window("GuildBankFrame", 8, -11, 0, 8)
        Tabs("GuildBankFrameTab", 4)
        Buttons("GuildBankFrameDepositButton", "GuildBankFrameWithdrawButton", "GuildBankFramePurchaseButton")
    end,
    Blizzard_GlyphUI = function()
        if GlyphFrame then A:StripTextures(GlyphFrame, "Background") end
    end,
}

function A:BuildSkins()
    -- Blizzard windows use the ElvUI-WotLK skins (Elv/), this file's own
    -- window list is kept only as helpers
    local S = A.ElvSkins
    if S and not S.huiStarted then
        S.huiStarted = true
        S:Initialize()
    end
end
