-- HUI - Blizzard window skins, ported from ElvUI-WotLK (Modules/Skins).
-- This file recreates the small part of the ElvUI engine those skins use
-- (E, S, the frame toolkit, hooks) on top of HUI's own media, colours and
-- pixel math, so the skin files can stay as close to ElvUI's as possible.

local A = HUI
local _G = _G
local unpack, type, select, pairs, ipairs = unpack, type, select, pairs, ipairs
local floor = math.floor
local CreateFrame = CreateFrame

local E = { initialized = true }
local L = setmetatable({}, { __index = function(_, k) return k end })
local S = { hooks = {} }
A.Elv = { E, L, {}, {}, {} }
A.ElvSkins = S

local M = [[Interface\AddOns\HUI\media\elv\]]

E.noop = function() end
E.myname = UnitName("player")
E.myclass = select(2, UnitClass("player"))
E.TexCoords = { 0.08, 0.92, 0.08, 0.92 }   -- ElvUI's default icon crop
E.PixelMode = true
E.frames = {}
E.texts = {}
E.unitFrameElements = {}
E.ModuleCallbacks, E.InitialModuleCallbacks = {}, {}

-- 1 screen pixel in UIParent units, read live so it is right whatever the UI scale
local mt = {}
mt.__index = function(t, k)
    if k == "mult" or k == "Border" then return A:PX(UIParent) end
    if k == "Spacing" then return 0 end
end
setmetatable(E, mt)

E.HiddenFrame = CreateFrame("Frame")
E.HiddenFrame:Hide()
E.UIParent = UIParent

E.Media = {
    Textures = {
        ArrowUp = M .. "ArrowUp",
        BagQuestIcon = M .. "BagQuestIcon",
        Close = [[Interface\AddOns\HUI\media\close]],
        Highlight = M .. "Highlight",
        Melli = M .. "Melli",
        Minus = M .. "Minus",
        MinusButton = M .. "MinusButton",
        Plus = M .. "Plus",
        PlusButton = M .. "PlusButton",
        NormTex2 = M .. "NormTex2",
        White8x8 = [[Interface\BUTTONS\WHITE8X8]],
    },
}

-- colours follow HUI's background setting ("Default" = solid, "Transparent" = its alpha)
E.media = {
    blankTex = [[Interface\BUTTONS\WHITE8X8]],
    normTex = M .. "NormTex2",
    glossTex = M .. "NormTex2",
    normFont = A.media.font,
    bordercolor = { 0, 0, 0 },
    unitframeBorderColor = { 0, 0, 0 },
    rgbvaluecolor = { 0.99, 0.48, 0.17 },     -- ElvUI's default value colour (hover border)
    backdropcolor = { 0.1, 0.1, 0.1 },
    backdropfadecolor = { 0.06, 0.06, 0.06, 0.8 },
}
local function SyncColors()
    local c = A.colors and A.colors.backdrop
    if not c then return end
    E.media.backdropcolor[1], E.media.backdropcolor[2], E.media.backdropcolor[3] = c[1], c[2], c[3]
    local f = E.media.backdropfadecolor
    f[1], f[2], f[3], f[4] = c[1], c[2], c[3], c[4] or 0.8
end

local font = A.media.font
E.LSM = { Fetch = function() return font end }
E.Libs = { LSM = E.LSM }
E.db = {
    general = { font = "HUI", fontSize = 12, fontStyle = "OUTLINE", valuecolor = { r = 0.99, g = 0.48, b = 0.17 } },
    chat = { tabFont = "HUI", tabFontSize = 12, tabFontOutline = "OUTLINE", numScrollMessages = 3 },
    bags = { colors = {
        profession = {
            quiver = { r = 1, g = 0.69, b = 0.41 }, ammoPouch = { r = 1, g = 0.69, b = 0.41 },
            soulBag = { r = 1, g = 0.69, b = 0.41 }, leatherworking = { r = 0.88, g = 0.73, b = 0.29 },
            inscription = { r = 0.29, g = 0.30, b = 0.88 }, herbs = { r = 0.07, g = 0.71, b = 0.13 },
            enchanting = { r = 0.76, g = 0.02, b = 0.8 }, engineering = { r = 0.91, g = 0.46, b = 0.18 },
            gems = { r = 0.03, g = 0.71, b = 0.81 }, mining = { r = 0.54, g = 0.40, b = 0.04 },
        },
        items = { questStarter = { r = 1, g = 1, b = 0 }, questItem = { r = 1, g = 0.30, b = 0.30 } },
    } },
}
E.global = { general = {} }
setmetatable(E.global.general, { __index = function(_, k) if k == "UIScale" then return UIParent:GetScale() end end })

-- every Blizzard skin on, except the ones HUI does itself
local blizzard = setmetatable({ tooltip = false }, { __index = function() return true end })
E.private = {
    skins = { blizzard = blizzard, checkBoxSkin = true, ace3 = { enable = false } },
    general = { loot = false, lootRoll = true },   -- HUI draws its own loot rolls (LootRoll.lua)
    bags = { enable = false },
    worldmap = { enable = false },
}

function E:Print(...) A:Print(...) end
function E:Scale(x) local m = E.mult; return m * floor(x / m + 0.5) end
function E:GetModule(name) if name == "Skins" then return S end return {} end
function E:RegisterModule() end
function E:RegisterCooldown() end
function E:RegisterStatusBar(bar) if bar and bar.SetStatusBarTexture then bar:SetStatusBarTexture(E.media.normTex) end end
function E:SetSmoothing() end
function E:CreateMover() end

function E:ColorGradient(perc, ...)
    if perc >= 1 then return select(select("#", ...) - 2, ...)
    elseif perc <= 0 then return ... end
    local num = select("#", ...) / 3
    local segment, relperc = math.modf(perc * (num - 1))
    local r1, g1, b1, r2, g2, b2 = select((segment * 3) + 1, ...)
    return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end

do -- E:Delay
    local waiting = {}
    local f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnUpdate", function(self, el)
        local n = 0
        for i = #waiting, 1, -1 do
            local w = waiting[i]
            w[1] = w[1] - el
            if w[1] <= 0 then
                table.remove(waiting, i)
                pcall(w[2], unpack(w, 3, w.n))
            else
                n = n + 1
            end
        end
        if n == 0 and #waiting == 0 then self:Hide() end
    end)
    function E:Delay(delay, func, ...)
        local t = { delay, func, ... }
        t.n = select("#", ...) + 2
        waiting[#waiting + 1] = t
        f:Show()
    end
end

E.ScanTooltip = CreateFrame("GameTooltip", "HUIScanTooltip", UIParent, "GameTooltipTemplate")

------------------------------------------------------------------------
-- Frame toolkit (ElvUI Core/Toolkit.lua)
------------------------------------------------------------------------
local backdropr, backdropg, backdropb, backdropa, borderr, borderg, borderb = 0, 0, 0, 1, 0, 0, 0
local function GetTemplate(template)
    SyncColors()
    backdropa = 1
    if template == "ClassColor" then
        local color = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[E.myclass] or RAID_CLASS_COLORS[E.myclass]
        borderr, borderg, borderb = color.r, color.g, color.b
        backdropr, backdropg, backdropb = unpack(E.media.backdropcolor)
    elseif template == "Transparent" then
        borderr, borderg, borderb = unpack(E.media.bordercolor)
        backdropr, backdropg, backdropb, backdropa = unpack(E.media.backdropfadecolor)
    else
        borderr, borderg, borderb = unpack(E.media.bordercolor)
        backdropr, backdropg, backdropb = unpack(E.media.backdropcolor)
    end
end

local function Size(frame, width, height)
    frame:SetWidth(E:Scale(width))
    frame:SetHeight(E:Scale(height or width))
end
local function Width(frame, width) frame:SetWidth(E:Scale(width)) end
local function Height(frame, height) frame:SetHeight(E:Scale(height)) end

local function Point(obj, arg1, arg2, arg3, arg4, arg5)
    if type(arg5) == "number" then
        arg5 = E:Scale(arg5); arg4 = E:Scale(arg4)
    elseif type(arg4) == "number" then
        arg4 = E:Scale(arg4); arg3 = E:Scale(arg3)
    elseif type(arg3) == "number" then
        arg3 = E:Scale(arg3); arg2 = E:Scale(arg2)
    end
    obj:SetPoint(arg1, arg2 or obj:GetParent(), arg3, arg4, arg5)
end

local function SetOutside(obj, anchor, xOffset, yOffset, anchor2)
    xOffset = xOffset or E.Border
    yOffset = yOffset or E.Border
    anchor = anchor or obj:GetParent()
    if obj:GetPoint() then obj:ClearAllPoints() end
    obj:Point("TOPLEFT", anchor, "TOPLEFT", -xOffset, yOffset)
    obj:Point("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", xOffset, -yOffset)
end

local function SetInside(obj, anchor, xOffset, yOffset, anchor2)
    xOffset = xOffset or E.Border
    yOffset = yOffset or E.Border
    anchor = anchor or obj:GetParent()
    if obj:GetPoint() then obj:ClearAllPoints() end
    obj:Point("TOPLEFT", anchor, "TOPLEFT", xOffset, -yOffset)
    obj:Point("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", -xOffset, yOffset)
end

local function SetTemplate(frame, template, glossTex, ignoreUpdates, forcePixelMode)
    GetTemplate(template)
    frame.template = template or "Default"
    if glossTex then frame.glossTex = glossTex end
    if ignoreUpdates then frame.ignoreUpdates = ignoreUpdates end
    if forcePixelMode then frame.forcePixelMode = forcePixelMode end

    if template ~= "NoBackdrop" then
        frame:SetBackdrop({
            bgFile = glossTex and E.media.glossTex or E.media.blankTex,
            edgeFile = E.media.blankTex,
            tile = false, tileSize = 0, edgeSize = A:PX(frame),
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        frame:SetBackdropColor(backdropr, backdropg, backdropb, backdropa)
    else
        frame:SetBackdrop(nil)
    end
    if frame.SetBackdropBorderColor and frame:GetBackdrop() then
        frame:SetBackdropBorderColor(borderr, borderg, borderb)
    end
    if not frame.ignoreUpdates then E.frames[frame] = true end
end

local function CreateBackdrop(frame, template, glossTex, ignoreUpdates, forcePixelMode)
    if not template then template = "Default" end
    local parent = (frame.IsObjectType and frame:IsObjectType("Texture") and frame:GetParent()) or frame
    local backdrop = frame.backdrop or CreateFrame("Frame", nil, parent)
    if not frame.backdrop then frame.backdrop = backdrop end
    if frame.forcePixelMode or forcePixelMode then
        backdrop:SetOutside(frame, E.mult, E.mult)
    else
        backdrop:SetOutside(frame)
    end
    backdrop:SetTemplate(template, glossTex, ignoreUpdates, forcePixelMode)
    local frameLevel = parent.GetFrameLevel and parent:GetFrameLevel()
    local below = frameLevel and (frameLevel - 1)
    if below and below >= 0 then backdrop:SetFrameLevel(below) else backdrop:SetFrameLevel(0) end
end

local function CreateShadow(frame, size)
    if frame.shadow then return end
    local shadow = CreateFrame("Frame", nil, frame)
    shadow:SetFrameLevel(1)
    shadow:SetFrameStrata(frame:GetFrameStrata())
    shadow:SetOutside(frame, size or 3, size or 3)
    frame.shadow = shadow
end

local function Kill(object)
    if object.UnregisterAllEvents then
        object:UnregisterAllEvents()
        object:SetParent(E.HiddenFrame)
    else
        object.Show = object.Hide
    end
    object:Hide()
end

local function StripTextures(object, kill, alpha)
    if object:IsObjectType("Texture") then
        if kill then object:Kill() elseif alpha then object:SetAlpha(0) else object:SetTexture(nil) end
    elseif object.GetNumRegions then
        for i = 1, object:GetNumRegions() do
            local region = select(i, object:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                if kill then region:Kill() elseif alpha then region:SetAlpha(0) else region:SetTexture(nil) end
            end
        end
    end
end

local function FontTemplate(fs, fnt, fontSize, fontStyle)
    fs.font, fs.fontSize, fs.fontStyle = fnt, fontSize, fontStyle
    fnt = fnt or font
    fontSize = fontSize or E.db.general.fontSize
    fontStyle = fontStyle or E.db.general.fontStyle
    fs:SetFont(fnt, fontSize, fontStyle ~= "NONE" and fontStyle or "")
    if fontStyle == "NONE" then
        local s = E.mult or 1
        fs:SetShadowOffset(s, -s / 2)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    end
    E.texts[fs] = true
end

local function StyleButton(button, noHover, noPushed, noChecked)
    if button.SetHighlightTexture and not button.hover and not noHover then
        local hover = button:CreateTexture()
        hover:SetInside()
        hover:SetTexture(1, 1, 1, 0.3)
        button:SetHighlightTexture(hover)
        button.hover = hover
    end
    if button.SetPushedTexture and not button.pushed and not noPushed then
        local pushed = button:CreateTexture()
        pushed:SetInside()
        pushed:SetTexture(0.9, 0.8, 0.1, 0.3)
        button:SetPushedTexture(pushed)
        button.pushed = pushed
    end
    if button.SetCheckedTexture and not button.checked and not noChecked then
        local checked = button:CreateTexture()
        checked:SetInside()
        checked:SetTexture(1, 1, 1, 0.3)
        button:SetCheckedTexture(checked)
        button.checked = checked
    end
    local name = button.GetName and button:GetName()
    local cooldown = name and _G[name .. "Cooldown"]
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetInside()
    end
end

local function CreateCloseButton(frame, size, offset, texture, backdrop)
    if frame.CloseButton then return end
    local b = CreateFrame("Button", nil, frame)
    b:Size(size or 16)
    b:Point("TOPRIGHT", offset or -6, offset or -6)
    if backdrop then b:CreateBackdrop(nil, true) end
    b.Texture = b:CreateTexture(nil, "OVERLAY")
    b.Texture:SetAllPoints()
    b.Texture:SetTexture(texture or E.Media.Textures.Close)
    b:SetScript("OnClick", function(btn) btn:GetParent():Hide() end)
    b:SetScript("OnEnter", function(btn) btn.Texture:SetVertexColor(unpack(E.media.rgbvaluecolor)) end)
    b:SetScript("OnLeave", function(btn) btn.Texture:SetVertexColor(1, 1, 1) end)
    frame.CloseButton = b
end

local function GetNamedChild(frame, childName, index)
    local name = frame and frame.GetName and frame:GetName()
    if not name or not childName then return nil end
    return _G[name .. childName .. (index or "")]
end

local function addapi(object)
    local m = getmetatable(object).__index
    if not object.Size then m.Size = Size end
    if not object.Point then m.Point = Point end
    if not object.SetOutside then m.SetOutside = SetOutside end
    if not object.SetInside then m.SetInside = SetInside end
    if not object.SetTemplate then m.SetTemplate = SetTemplate end
    if not object.CreateBackdrop then m.CreateBackdrop = CreateBackdrop end
    if not object.CreateShadow then m.CreateShadow = CreateShadow end
    if not object.Kill then m.Kill = Kill end
    if not object.Width then m.Width = Width end
    if not object.Height then m.Height = Height end
    if not object.FontTemplate then m.FontTemplate = FontTemplate end
    if not object.StripTextures then m.StripTextures = StripTextures end
    if not object.StyleButton then m.StyleButton = StyleButton end
    if not object.CreateCloseButton then m.CreateCloseButton = CreateCloseButton end
    if not object.GetNamedChild then m.GetNamedChild = GetNamedChild end
end

do
    local handled = { Frame = true }
    local object = CreateFrame("Frame")
    addapi(object)
    addapi(object:CreateTexture())
    addapi(object:CreateFontString())
    object = EnumerateFrames()
    while object do
        if not handled[object:GetObjectType()] then
            addapi(object)
            handled[object:GetObjectType()] = true
        end
        object = EnumerateFrames(object)
    end
    addapi(GameFontNormal)
end

-- keep skinned frames on HUI's background colour / pixel size
function E:UpdateFrameTemplates()
    for frame in pairs(E.frames) do
        if frame and frame.template and not frame.ignoreUpdates then
            frame:SetTemplate(frame.template, frame.glossTex, nil, frame.forcePixelMode)
        end
    end
end

------------------------------------------------------------------------
-- Skin registry + minimal AceHook (SecureHook / RawHook / HookScript / Unhook)
------------------------------------------------------------------------
local callbacks, addonCallbacks = {}, {}

function S:AddCallback(name, fn)
    callbacks[#callbacks + 1] = { name, fn }
end

function S:AddCallbackForAddon(addon, name, fn)
    addonCallbacks[addon] = addonCallbacks[addon] or {}
    local t = addonCallbacks[addon]
    t[#t + 1] = { name, fn }
end

local function Run(entry)
    local ok, err = pcall(entry[2])
    if not ok then A:Print("|cffff5555skin " .. entry[1] .. ":|r " .. tostring(err)) end
end

local active = {}
function S:SecureHook(obj, method, fn)
    if type(obj) == "string" then obj, method, fn = _G, obj, method end
    local key = tostring(obj) .. method
    active[key] = true
    hooksecurefunc(obj, method, function(...) if active[key] then fn(...) end end)
end

function S:RawHook(obj, method, fn)
    if type(obj) == "string" then obj, method, fn = _G, obj, method end
    local orig = obj[method]
    if obj == _G then S.hooks[method] = orig else S.hooks[obj] = S.hooks[obj] or {}; S.hooks[obj][method] = orig end
    obj[method] = fn
    active[tostring(obj) .. method] = orig
end

function S:HookScript(frame, script, fn)
    local key = tostring(frame) .. script
    active[key] = true
    frame:HookScript(script, function(...) if active[key] then fn(...) end end)
end

function S:Unhook(obj, method)
    if type(obj) == "string" then obj, method = _G, obj end
    local key = tostring(obj) .. method
    local v = active[key]
    if type(v) == "function" then obj[method] = v end
    active[key] = nil
end

function S:Initialize()
    S.uiPanelQueue, S.hitRectQueue = {}, {}
    for _, entry in ipairs(callbacks) do Run(entry) end
    callbacks = {}
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event, addon)
        if event == "PLAYER_REGEN_ENABLED" then
            if S.PLAYER_REGEN_ENABLED then S:PLAYER_REGEN_ENABLED() end
            return
        end
        local list = addonCallbacks[addon]
        if list then
            addonCallbacks[addon] = nil
            for _, entry in ipairs(list) do Run(entry) end
        end
    end)
    for addon, list in pairs(addonCallbacks) do
        if IsAddOnLoaded(addon) then
            addonCallbacks[addon] = nil
            for _, entry in ipairs(list) do Run(entry) end
        end
    end
end

function S:RegisterEvent() end
function S:UnregisterEvent() end
