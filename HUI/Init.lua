-- HUI - Init + slash commands

local A = HUI

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "HUI" then
        A:LoadDB()
        A:ApplyGCPause()
        local _, class = UnitClass("player")
        local d = {
            PRIEST  = { Magic = true, Disease = true },
            PALADIN = { Magic = true, Poison = true, Disease = true },
            SHAMAN  = { Poison = true, Disease = true, Curse = true },
            DRUID   = { Curse = true, Poison = true },
            MAGE    = { Curse = true },
        }
        A.canDispel = d[class] or {}

        A:LockUIScale()
        A:HookColorPicker()
        A:RunOOC(function()
            local m = A.db.modules
            A.fontKey = "units"; A:Safe("unit frames", function() A:BuildUnitFrames() end)
            A:Safe("castbars", function() A:BuildCastbars() end)
            A:Safe("cooldown manager", function() A:BuildCDM() end)
            A.fontKey = "raid"; if m.raid then A:Safe("raid frames", function() A:BuildRaid() end) end
            A.fontKey = "units"; if m.party then A:Safe("party frames", function() A:BuildParty() end) end
            A:Safe("hide blizzard frames", function() A:HideBlizzard() end)
            if m.buffs then A:Safe("buffs", function() A:BuildBuffs() end) end
            if m.actionbars then A:Safe("action bars", function() A:BuildActionBars() end) end
            A.fontKey = "minimap"; if m.minimap then A:Safe("minimap", function() A:BuildMinimap() end) end
            A.fontKey = "general"; if m.chat then A:Safe("chat", function() A:BuildChat() end) end
            if m.skins then A:Safe("window skins", function() A:BuildSkins() end) end
            A.fontKey = "bags"; if m.bags then A:Safe("bags", function() A:BuildBags() end) end
            A.fontKey = "general"; if m.tooltips then A:Safe("tooltips", function() A:BuildTooltips() end) end
            if m.nameplates then A:Safe("nameplates", function() A:BuildNameplates() end) end
            A.fontKey = "general"
            A:Safe("cursor & alerts", function() A:BuildCombatExtras() end)
            A:Safe("chat bubbles", function() A:BuildChatBubbles() end)
            A:Safe("quality of life", function() A:BuildQoL() end)
            A:Safe("events", function() A:RegisterUnitEvents() end)
            A.built = true
            A.builtScale = UIParent:GetEffectiveScale()
        end)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        A:Print("loaded. Type |cffffff00/hui|r for settings.")
        if A.versionReset then
            A:Print("new version (" .. tostring(A.db.addonVersion) .. "): all settings were reset to the defaults.")
        end

        if A.built then
            A:RunOOC(function()
                A:UpdateBarDefaults()
                for key, m in pairs(A.movers) do
                    if not A.db.positions[key] then A:ApplyPosition(key, m.frame) end
                end
            end)
            A:Safe("vehicle", function() A:UpdateVehicle() end)
            if A.PlaceBuffs then A:PlaceBuffs() end
        end
        -- building every frame leaves a lot of temporary data: free it while
        -- the loading screen is still up instead of carrying it into play
        collectgarbage("collect")
    end
end)

-- All bars on, once per character (the game keeps these settings per
-- character): bottom left / right, right bar 1 and 2, lock action bars, always
-- show action bars and secure ability toggle. The game loads its own saved bar
-- settings late (VARIABLES_LOADED comes after PLAYER_LOGIN in 3.3.5) and would
-- undo it, so do it after that, or on entering the world if it already happened.
local bars = CreateFrame("Frame")
bars:RegisterEvent("VARIABLES_LOADED")
bars:RegisterEvent("PLAYER_ENTERING_WORLD")
bars:SetScript("OnEvent", function(self)
    if not A.db or InCombatLockdown() or not SetActionBarToggles then return end
    local who = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    A.db.barsToggledChars = A.db.barsToggledChars or {}
    if A.db.barsToggledChars[who] then return end
    A.db.barsToggledChars[who] = true
    SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2 = "1", "1"
    SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4 = "1", "1"
    -- "always show" keeps empty slots visible, so mouseover bars show their grid
    ALWAYS_SHOW_MULTI_ACTIONBAR = "1"
    SetActionBarToggles(1, 1, 1, 1, 1)
    LOCK_ACTIONBAR = "1"
    pcall(SetCVar, "lockActionBars", "1")
    pcall(SetCVar, "alwaysShowActionBars", "1")
    pcall(SetCVar, "secureAbilityToggle", "1")
    if MultiActionBar_Update then MultiActionBar_Update() end
    if A.RelayoutBars then A:RelayoutBars() end
end)

-- Multisampling: 1px borders only line up cleanly with MSAA on (4x or 8x).
-- If it's lower, raise it to 4x once and restart the graphics device. Tried only
-- once per value, so a card that can't do 4x doesn't restart the screen every login.
local msaa = CreateFrame("Frame")
msaa:RegisterEvent("PLAYER_ENTERING_WORLD")
msaa:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not A.db or not A.db.forceMSAA then return end
    local ok, cur = pcall(GetCVar, "gxMultisample")
    cur = ok and tonumber(cur) or nil
    if not cur or cur >= 4 then return end
    if A.db.msaaTried == cur then return end
    A.db.msaaTried = cur
    pcall(SetCVar, "gxMultisample", "4")
    A:Print("multisampling set to 4x for clean 1px borders.")
    if RestartGx then RestartGx() end
end)


-- The game applies your UI scale after HUI has built its frames, so sizes that
-- are measured in screen pixels (raid buttons, chat width, 1px borders) came
-- out too small. When the scale settles (or changes later), measure again.
function A:Repixel()
    if InCombatLockdown() then self.repixelDirty = true return end
    self.screenH = nil
    self:Safe("repixel borders", function()
        for f in pairs(self.bgFrames or {}) do
            if f.GetBackdrop and f:GetBackdrop() then
                local r, g, b, a = f:GetBackdropColor()
                local br, bg, bb, ba = f:GetBackdropBorderColor()
                local bd = f:GetBackdrop()
                bd.edgeSize = self:PX(f)
                f:SetBackdrop(bd)
                f:SetBackdropColor(r, g, b, a)
                f:SetBackdropBorderColor(br, bg, bb, ba)
            end
        end
        for f in pairs(self.allFrames or {}) do
            if f.atrBorder then f.atrBorder:SetThickness(f.borderSize or 1) end
        end
    end)
    if self.Elv and self.Elv[1].UpdateFrameTemplates then self:Safe("repixel skins", function() self.Elv[1]:UpdateFrameTemplates() end) end
    if self.LayoutMinimapButtons then self:Safe("repixel minimap buttons", function() self.LayoutMinimapButtons() end) end
    if self.ResizeChat then self:Safe("repixel chat", function() self:ResizeChat() end) end
    if self.LayoutRaid then self:Safe("repixel raid", function() self:LayoutRaid() end) end
    if self.LayoutParty then self:Safe("repixel party", function() self:LayoutParty() end) end
    if self.RelayoutBars then self:Safe("repixel bars", function() self:RelayoutBars() end) end
    if self.RefreshUnits then self:Safe("repixel units", function() self:RefreshUnits() end) end
    if self.RefreshCDM then self:Safe("repixel cooldown manager", function() self:RefreshCDM() end) end
end

do
    local w, acc = CreateFrame("Frame"), 0
    w:RegisterEvent("PLAYER_REGEN_ENABLED")
    w:SetScript("OnEvent", function()
        if A.repixelDirty then A.repixelDirty = nil; A:Repixel() end
    end)
    w:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.5 then return end
        acc = 0
        if not A.built then return end
        A:LockUIScale()
        local s = UIParent:GetEffectiveScale()
        if A.builtScale and math.abs(s - A.builtScale) > 0.0001 then
            A.builtScale = s
            A:Repixel()
        end
    end)
end

-- /hui (the window itself is in HUI_Options, loaded on first use)
SLASH_HUISETTINGS1 = "/hui"
SlashCmdList["HUISETTINGS"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "unlock" or msg == "move" then A:Unlock()
    elseif msg == "lock" then A:Lock()
    elseif msg == "rolltest" then A:TestLootRolls()
    elseif msg == "findline" then A:FindLines()
    elseif msg == "perf" then A:PerfToggle()
    elseif msg == "mem" or msg == "memory" then A:PrintMemory()
    elseif msg == "cdm" then if A.CDMEdit then A:CDMEdit() end
    elseif msg == "cdm status" then if A.CDMStatus then A:CDMStatus() end
    elseif msg == "scale" then
        local p = A:ScaleProbe() or {}
        A:Print(string.format("scale %.4f  eff %.4f  UI %.1f x %.1f  useUiScale %s  uiScale %s  res %s  win %s  px %.4f",
            p.scale or 0, p.eff or 0, p.uiw or 0, p.uih or 0, tostring(p.useUiScale), tostring(p.uiScale),
            tostring(p.gxResolution), tostring(p.gxWindow), p.px or 0))
    else A:ToggleConfig() end
end
