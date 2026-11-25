-- HUI - Glows: the four border glows of WeakAuras (LibCustomGlow-1.0, as
-- shipped with WeakAuras for 3.3.5): Action Button Glow, Pixel Glow,
-- Autocast Shine and Proc Glow. Same code and textures, made standalone (no
-- LibStub, no global pools), so HUI doesn't need WeakAuras installed.
--
-- A.Glow.Start(frame, kind, color)  kind: "button" | "pixel" | "autocast" | "proc"
-- A.Glow.Stop(frame)                color: { r, g, b, a } or nil (default look)
--
-- Contains work of Hendrick "nevcairiel" Leppkes (LibButtonGlow-1.0) and the
-- LibCustomGlow / WeakAuras authors.

local A = HUI
local G = {}
A.Glow = G

local pairs, ipairs, unpack, setmetatable = pairs, ipairs, unpack, setmetatable
local abs, ceil, floor, min = math.abs, math.ceil, math.floor, math.min
local mod = math.fmod
local tinsert, tremove = table.insert, table.remove

local TEX = "Interface\\AddOns\\HUI\\media\\glow\\"
local textureList = {
    buttonGlow = TEX .. "IconAlert",
    buttonGlowAnts = TEX .. "IconAlertAnts",
    buttonGlowAntsDesaturated = TEX .. "IconAlertAnts_desaturated",
    -- the proc flipbook as 32-bit TGA: the retail .blp it came from is stored
    -- uncompressed (a BLP format the 3.3.5 client can't draw: the glow ran,
    -- invisible). Half size, 2 MB each instead of 8.
    proc = TEX .. "proc.tga",
    procDesaturated = TEX .. "proc_desaturated.tga",
    white = "Interface\\BUTTONS\\WHITE8X8",
    shine = TEX .. "Artifacts",
    shineDesaturated = TEX .. "Artifacts_desaturated",
}
local shineCoords = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }

-- tiny object pool (the 3.3.5 client has none built in)
local function NewPool(create, reset)
    local pool = { free = {} }
    function pool:Acquire()
        local o = tremove(self.free)
        if o then
            o.atrPoolFree = nil
            return o, false
        end
        return create(), true
    end
    function pool:Release(o)
        if not o or o.atrPoolFree then return end
        reset(self, o)
        o.atrPoolFree = true
        tinsert(self.free, o)
    end
    return pool
end
local function NewFrame() return CreateFrame("Frame", nil, UIParent) end

local function AnimateTexCoords(texture, textureWidth, textureHeight, frameWidth, frameHeight, numFrames, elapsed, throttle)
    if not texture.frame then
        texture.frame = 1
        texture.throttle = throttle
        texture.numColumns = floor(textureWidth / frameWidth)
        texture.numRows = floor(textureHeight / frameHeight)
        texture.columnWidth = frameWidth / textureWidth
        texture.rowHeight = frameHeight / textureHeight
    end
    local frame = texture.frame
    if not texture.throttle or texture.throttle > throttle then
        local framesToAdvance = floor(texture.throttle / throttle)
        while frame + framesToAdvance > numFrames do
            frame = frame - numFrames
        end
        frame = frame + framesToAdvance
        texture.throttle = 0
        local left = mod(frame - 1, texture.numColumns) * texture.columnWidth
        local right = left + texture.columnWidth
        local bottom = ceil(frame / texture.numColumns) * texture.rowHeight
        local top = bottom - texture.rowHeight
        texture:SetTexCoord(left, right, top, bottom)
        texture.frame = frame
    else
        texture.throttle = texture.throttle + elapsed
    end
end

------------------------------------------------------------------------
-- Pixel glow / Autocast shine share a frame pool. Each frame keeps its own
-- textures (3.3.5 textures can't move between frames).
------------------------------------------------------------------------
local GlowFramePool = NewPool(NewFrame, function(pool, frame)
    frame:SetScript("OnSizeChanged", nil)
    frame:SetScript("OnUpdate", nil)
    local parent = frame:GetParent()
    if frame.name and parent and parent[frame.name] == frame then parent[frame.name] = nil end
    if frame.textures then
        for _, t in ipairs(frame.textures) do t:Hide(); t:ClearAllPoints() end
    end
    frame.used = 0
    frame.info = {}
    frame.name = nil
    frame.timer = nil
    frame:Hide()
    frame:ClearAllPoints()
end)

local function addFrameAndTex(r, color, name, key, N, xOffset, yOffset, texture, texCoord, frameLevel)
    key = key or ""
    frameLevel = frameLevel or 8
    if not r[name .. key] then
        r[name .. key] = GlowFramePool:Acquire()
        r[name .. key]:SetParent(r)
        r[name .. key].name = name .. key
    end
    local f = r[name .. key]
    f:SetFrameLevel(r:GetFrameLevel() + frameLevel)
    f:SetPoint("TOPLEFT", r, "TOPLEFT", -xOffset + 0.05, yOffset + 0.05)
    f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", xOffset, -yOffset + 0.05)
    f:Show()
    f.textures = f.textures or {}
    for i = 1, N do
        local t = f.textures[i]
        if not t then
            t = f:CreateTexture(nil, "OVERLAY")
            f.textures[i] = t
        end
        t:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
        t:SetBlendMode(name == "_AutoCastGlow" and "ADD" or "BLEND")
        t:SetTexture(texture)
        t:SetVertexColor(color[1], color[2], color[3], color[4])
        t:Show()
    end
    for i = N + 1, #f.textures do
        f.textures[i]:Hide()
        f.textures[i]:ClearAllPoints()
    end
    f.used = N
end

-- Pixel glow ----------------------------------------------------------
local pPoint = {
    ["BOTTOMLEFT"] = "BOTTOMRIGHT",
    ["BOTTOMRIGHT"] = "TOPRIGHT",
    ["TOPRIGHT"] = "TOPLEFT",
    ["TOPLEFT"] = "BOTTOMLEFT",
}

local function pWidth(position, width, length, thickness, line1, line2, point)
    line1:ClearAllPoints()
    line1:SetPoint(pPoint[point], point == "BOTTOMLEFT" and -position or position, 0)
    position = width - position
    if position > length then
        line1:SetWidth(length); line1:SetHeight(thickness)
        line2:Hide()
    else
        line2:ClearAllPoints()
        line2:SetPoint(point)
        line2:Show()
        line1:SetWidth(position); line1:SetHeight(thickness)
        line2:SetWidth(thickness); line2:SetHeight(length - position)
    end
end

local function pHeight(position, height, length, thickness, line1, line2, point)
    line1:ClearAllPoints()
    line1:SetPoint(pPoint[point], 0, point == "BOTTOMRIGHT" and -position or position)
    position = height - position
    if position > length then
        line1:SetWidth(thickness); line1:SetHeight(length)
        line2:Hide()
    else
        line2:ClearAllPoints()
        line2:SetPoint(point)
        line2:Show()
        line1:SetWidth(thickness); line1:SetHeight(position)
        line2:SetWidth(length - position); line2:SetHeight(thickness)
    end
end

local GlowpUpdate, GlowacUpdate, GlowbgUpdate, GlowFlipbook
local function pSizeChanged(self, width, height)
    if not (width or height) then
        width, height = self:GetWidth(), self:GetHeight()
    end
    if width ~= self.info.width or height ~= self.info.height then
        self.info.width = width
        self.info.height = height
        self.info.perimeter = 2 * (width + height)
        self.info.bottomlim = height * 2 + width
        self.info.rightlim = height + width
        self.info.space = self.info.perimeter / self.info.N
    end
end

local function pUpdate(self, elapsed)
    self.timer = self.timer + elapsed / self.info.period
    if self.timer > 1 or self.timer < -1 then
        self.timer = self.timer % 1
    end
    local info = self.info
    for i = 1, info.N do
        local position = (info.space * i + info.perimeter * self.timer) % info.perimeter
        if position > info.bottomlim then
            pWidth(position - info.bottomlim, info.width, info.length, info.th, self.textures[i], self.textures[info.N + i], "BOTTOMLEFT")
        elseif position > info.rightlim then
            pHeight(position - info.rightlim, info.height, info.length, info.th, self.textures[i], self.textures[info.N + i], "BOTTOMRIGHT")
        elseif position > info.height then
            pWidth(position - info.height, info.width, info.length, info.th, self.textures[i], self.textures[info.N + i], "TOPRIGHT")
        else
            pHeight(position, info.height, info.length, info.th, self.textures[i], self.textures[info.N + i], "TOPLEFT")
        end
    end
end

GlowpUpdate = HUI:PerfWrap("Glows", pUpdate)

function G.PixelGlow_Start(r, color, N, frequency, length, th, xOffset, yOffset, border, key, frameLevel)
    if not r then return end
    if not N or N <= 0 then N = 8 end
    local width, height = r:GetWidth(), r:GetHeight()
    length = length or floor((width + height) * (2 / N - 0.1))
    length = min(length, min(width, height))
    key = key or ""
    addFrameAndTex(r, color or { .95, .95, .32, 1 }, "_PixelGlow", key, N * 2, xOffset or 0, yOffset or 0,
        textureList.white, { 0, 1, 0, 1 }, frameLevel)
    local f = r["_PixelGlow" .. key]
    f.timer = f.timer or 0
    f.info = f.info or {}
    f.info.N = N
    f.info.period = (not frequency or abs(frequency) < 0.000001) and 4 or (1 / frequency)
    f.info.th = th or 1
    if f.info.length ~= length then
        f.info.width = nil
        f.info.length = length
    end
    pSizeChanged(f)
    f:SetScript("OnSizeChanged", pSizeChanged)
    pUpdate(f, 0)
    f:SetScript("OnUpdate", GlowpUpdate)
end

function G.PixelGlow_Stop(r, key)
    if not r then return end
    key = key or ""
    if r["_PixelGlow" .. key] then GlowFramePool:Release(r["_PixelGlow" .. key]) end
end

-- Autocast shine ------------------------------------------------------
local acSizes = { 7, 6, 5, 4 }

local function acUpdate(self, elapsed)
    local width, height = self:GetWidth(), self:GetHeight()
    if width <= 0 or height <= 0 then
        local _, _, rw, rh = self:GetRect()
        width, height = rw or width, rh or height
    end
    if not width or not height or width <= 0 or height <= 0 then return end
    local perimeter = 2 * (width + height)
    local bottomlim = height * 2 + width
    local rightlim = height + width
    local space = perimeter / self.info.N
    local texIndex = 0
    for k = 1, 4 do
        self.timer[k] = self.timer[k] + elapsed / (self.info.period * k)
        if self.timer[k] > 1 or self.timer[k] < -1 then
            self.timer[k] = self.timer[k] % 1
        end
        for i = 1, self.info.N do
            texIndex = texIndex + 1
            local t = self.textures[texIndex]
            local position = (space * i + perimeter * self.timer[k]) % perimeter
            t:ClearAllPoints()
            if position > bottomlim then
                t:SetPoint("CENTER", self, "BOTTOMRIGHT", -position + bottomlim, 0)
            elseif position > rightlim then
                t:SetPoint("CENTER", self, "TOPRIGHT", 0, -position + rightlim)
            elseif position > height then
                t:SetPoint("CENTER", self, "TOPLEFT", position - height, 0)
            else
                t:SetPoint("CENTER", self, "BOTTOMLEFT", 0, position)
            end
        end
    end
end

GlowacUpdate = HUI:PerfWrap("Glows", acUpdate)

function G.AutoCastGlow_Start(r, color, N, frequency, scale, xOffset, yOffset, key, frameLevel)
    if not r then return end
    if not (N and N > 0) then N = 4 end
    scale = scale or 1
    key = key or ""
    local texture = color and textureList.shineDesaturated or textureList.shine
    addFrameAndTex(r, color or { .95, .95, .32, 1 }, "_AutoCastGlow", key, N * 4, xOffset or 0, yOffset or 0,
        texture, shineCoords, frameLevel)
    local f = r["_AutoCastGlow" .. key]
    for k, size in pairs(acSizes) do
        for i = 1, N do
            local t = f.textures[i + N * (k - 1)]
            t:SetWidth(size * scale); t:SetHeight(size * scale)
        end
    end
    f.timer = f.timer or { 0, 0, 0, 0 }
    f.info = f.info or {}
    f.info.N = N
    f.info.period = (not frequency or abs(frequency) < 0.000001) and 8 or (1 / frequency)
    f:SetScript("OnUpdate", GlowacUpdate)
    acUpdate(f, 0)
end

function G.AutoCastGlow_Stop(r, key)
    if not r then return end
    key = key or ""
    if r["_AutoCastGlow" .. key] then GlowFramePool:Release(r["_AutoCastGlow" .. key]) end
end

------------------------------------------------------------------------
-- Action Button Glow (the default Blizzard proc glow, LibButtonGlow)
------------------------------------------------------------------------
local function InitAlphaAnimation(self)
    self.target = self.target or self:GetRegionParent()
    self.change = self.change or 0
    self.frameAlpha = self.target:GetAlpha()
    self.alphaFactor = self.change
end

local function TidyAlphaAnimation(self)
    self.alphaFactor = nil
    self.frameAlpha = nil
end

local function AlphaAnimation_OnUpdate(self)
    local progress = self:GetSmoothProgress()
    if progress ~= 0 then
        if not self.played then
            InitAlphaAnimation(self)
            self.played = 1
        end
        if self.frameAlpha then
            local a = self.frameAlpha + self.alphaFactor * progress
            if a < 0 then a = 0 elseif a > 1 then a = 1 end
            self.target:SetAlpha(a)
            if progress == 1 then TidyAlphaAnimation(self) end
        end
    end
end

local function AlphaAnimation_OnStop(self)
    if self.frameAlpha then TidyAlphaAnimation(self) end
    self.played = nil
end

-- appear: fades the texture in by `alpha`; otherwise out by it
local function CreateAlphaAnim(group, target, order, duration, alpha, delay, appear)
    local a = group:CreateAnimation()
    if target then a.target = a:GetRegionParent()[target] end
    if order then a:SetOrder(order) end
    a:SetDuration(duration)
    a.change = appear and alpha or -alpha
    if appear then tinsert(group.appear, a) else tinsert(group.fade, a) end
    if delay then a:SetStartDelay(delay) end
    a:SetScript("OnUpdate", AlphaAnimation_OnUpdate)
    a:SetScript("OnStop", AlphaAnimation_OnStop)
    a:SetScript("OnFinished", AlphaAnimation_OnStop)
end

local function InitScaleAnimation(self)
    self.target = self.target or self:GetRegionParent()
    self.scaleX = self.scaleX or 0
    self.scaleY = self.scaleY or 0
    local _, _, width, height = self.target:GetRect()
    if not width then return end
    self.frameWidth = width
    self.frameHeight = height
    self.widthFactor = width * self.scaleX - width
    self.heightFactor = height * self.scaleY - height
    local setCenter
    local parent = self.target:GetParent()
    local numPoints = self.target:GetNumPoints()
    if numPoints > 0 then
        local point, relativeTo, relativePoint, xOffset, yOffset = self.target:GetPoint(1)
        if numPoints == 1 and point == "CENTER" then
            setCenter = false
        else
            local i = 1
            while true do
                if relativeTo ~= parent and yOffset then
                    local j = #self + 1
                    self[j], self[j + 1], self[j + 2], self[j + 3], self[j + 4] = point, relativeTo, relativePoint, xOffset, yOffset
                end
                i = i + 1
                if numPoints >= i then
                    point, relativeTo, relativePoint, xOffset, yOffset = self.target:GetPoint(i)
                else
                    break
                end
            end
            setCenter = true
        end
    else
        setCenter = true
    end
    if setCenter then
        local x, y = self.target:GetCenter()
        local parentX, parentY = parent:GetCenter()
        self.target:ClearAllPoints()
        self.target:SetPoint("CENTER", x - parentX, y - parentY)
    end
    return 1
end

local function TidyScaleAnimation(self)
    local target = self.target
    if #self ~= 0 then
        target:ClearAllPoints()
        for i = 1, #self, 5 do
            target:SetPoint(self[i], self[i + 1], self[i + 2], self[i + 3], self[i + 4])
            self[i], self[i + 1], self[i + 2], self[i + 3], self[i + 4] = nil, nil, nil, nil, nil
        end
    end
    self.widthFactor = nil
    self.heightFactor = nil
    self.frameWidth = nil
    self.frameHeight = nil
end

local function ScaleAnimation_OnUpdate(self)
    local progress = self:GetSmoothProgress()
    if progress ~= 0 then
        if not self.played then
            if InitScaleAnimation(self) then self.played = 1 end
        end
        if self.frameWidth then
            self.target:SetWidth(self.frameWidth + self.widthFactor * progress)
            self.target:SetHeight(self.frameHeight + self.heightFactor * progress)
            if progress == 1 then TidyScaleAnimation(self) end
        end
    end
end

local function ScaleAnimation_OnStop(self)
    if self.frameWidth then TidyScaleAnimation(self) end
    self.played = nil
end

local function CreateScaleAnim(group, target, order, duration, x, y, delay, smoothing, onPlay)
    local scale = group:CreateAnimation()
    if target then scale.target = scale:GetRegionParent()[target] end
    scale:SetOrder(order)
    scale:SetDuration(duration)
    scale.scaleX, scale.scaleY = x, y
    if delay then scale:SetStartDelay(delay) end
    if smoothing then scale:SetSmoothing(smoothing) end
    if onPlay then scale:SetScript("OnPlay", onPlay) end
    scale:SetScript("OnUpdate", ScaleAnimation_OnUpdate)
    scale:SetScript("OnStop", ScaleAnimation_OnStop)
    scale:SetScript("OnFinished", ScaleAnimation_OnStop)
end

local ButtonGlowPool = NewPool(NewFrame, function(pool, frame)
    local parent = frame:GetParent()
    if parent and parent._ButtonGlow == frame then parent._ButtonGlow = nil end
    frame:Hide()
    frame:ClearAllPoints()
end)

local function SetSize2(t, w, h) t:SetWidth(w); t:SetHeight(h) end

local function AnimIn_OnPlay(anim)
    local frame = anim:GetRegionParent()
    local frameWidth, frameHeight = frame:GetWidth(), frame:GetHeight()
    SetSize2(frame.spark, frameWidth, frameHeight)
    frame.spark:SetAlpha(not (frame.color) and 1 or 0.3 * frame.color[4])
    SetSize2(frame.innerGlow, frameWidth / 2, frameHeight / 2)
    frame.innerGlow:SetAlpha(not (frame.color) and 1 or frame.color[4])
    frame.innerGlowOver:SetAlpha(not (frame.color) and 1 or frame.color[4])
    SetSize2(frame.outerGlow, frameWidth * 2, frameHeight * 2)
    frame.outerGlow:SetAlpha(not (frame.color) and 1 or frame.color[4])
    frame.outerGlowOver:SetAlpha(not (frame.color) and 1 or frame.color[4])
    SetSize2(frame.ants, frameWidth * 0.85, frameHeight * 0.85)
    frame.ants:SetAlpha(0)
    frame:Show()
end

local function AnimIn_OnFinished(group)
    local frame = group:GetParent()
    local frameWidth, frameHeight = frame:GetWidth(), frame:GetHeight()
    frame.spark:SetAlpha(0)
    frame.innerGlow:SetAlpha(0)
    SetSize2(frame.innerGlow, frameWidth, frameHeight)
    frame.innerGlowOver:SetAlpha(0)
    SetSize2(frame.outerGlow, frameWidth, frameHeight)
    frame.outerGlowOver:SetAlpha(0)
    SetSize2(frame.outerGlowOver, frameWidth, frameHeight)
    frame.ants:SetAlpha(not (frame.color) and 1 or frame.color[4])
end

local function AnimIn_OnStop(group)
    local frame = group:GetParent()
    frame.spark:SetAlpha(0)
    frame.innerGlow:SetAlpha(0)
    frame.innerGlowOver:SetAlpha(0)
    frame.outerGlowOver:SetAlpha(0)
end

local function bgHide(self)
    if self.animOut.isPlaying then
        self.animOut:Stop()
        ButtonGlowPool:Release(self)
    end
end

local function bgUpdate(self, elapsed)
    AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, self.throttle)
end

GlowbgUpdate = HUI:PerfWrap("Glows", bgUpdate)

local function configureButtonGlow(f, alpha)
    f.spark = f:CreateTexture(nil, "BACKGROUND")
    f.spark:SetPoint("CENTER")
    f.spark:SetAlpha(0)
    f.spark:SetTexture(textureList.buttonGlow)
    f.spark:SetTexCoord(0.00781250, 0.61718750, 0.00390625, 0.26953125)

    f.innerGlow = f:CreateTexture(nil, "ARTWORK")
    f.innerGlow:SetPoint("CENTER")
    f.innerGlow:SetAlpha(0)
    f.innerGlow:SetTexture(textureList.buttonGlow)
    f.innerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    f.innerGlowOver = f:CreateTexture(nil, "ARTWORK")
    f.innerGlowOver:SetPoint("TOPLEFT", f.innerGlow, "TOPLEFT")
    f.innerGlowOver:SetPoint("BOTTOMRIGHT", f.innerGlow, "BOTTOMRIGHT")
    f.innerGlowOver:SetAlpha(0)
    f.innerGlowOver:SetTexture(textureList.buttonGlow)
    f.innerGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

    f.outerGlow = f:CreateTexture(nil, "ARTWORK")
    f.outerGlow:SetPoint("CENTER")
    f.outerGlow:SetAlpha(0)
    f.outerGlow:SetTexture(textureList.buttonGlow)
    f.outerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    f.outerGlowOver = f:CreateTexture(nil, "ARTWORK")
    f.outerGlowOver:SetPoint("TOPLEFT", f.outerGlow, "TOPLEFT")
    f.outerGlowOver:SetPoint("BOTTOMRIGHT", f.outerGlow, "BOTTOMRIGHT")
    f.outerGlowOver:SetAlpha(0)
    f.outerGlowOver:SetTexture(textureList.buttonGlow)
    f.outerGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

    f.ants = f:CreateTexture(nil, "OVERLAY")
    f.ants:SetPoint("CENTER")
    f.ants:SetAlpha(0)
    f.ants:SetTexture(textureList.buttonGlowAnts)

    f.animIn = f:CreateAnimationGroup()
    f.animIn.appear = {}
    f.animIn.fade = {}
    CreateScaleAnim(f.animIn, "spark",          1, 0.2, 1.5, 1.5, nil, nil, AnimIn_OnPlay)
    CreateAlphaAnim(f.animIn, "spark",          1, 0.2, alpha, nil, true)
    CreateScaleAnim(f.animIn, "innerGlow",      1, 0.3, 2, 2)
    CreateScaleAnim(f.animIn, "innerGlowOver",  1, 0.3, 2, 2)
    CreateAlphaAnim(f.animIn, "innerGlowOver",  1, 0.3, alpha, nil, false)
    CreateScaleAnim(f.animIn, "outerGlow",      1, 0.3, 0.5, 0.5)
    CreateScaleAnim(f.animIn, "outerGlowOver",  1, 0.3, 0.5, 0.5)
    CreateAlphaAnim(f.animIn, "outerGlowOver",  1, 0.3, alpha, nil, false)
    CreateScaleAnim(f.animIn, "spark",          1, 0.2, 0.666666, 0.666666, 0.2)
    CreateAlphaAnim(f.animIn, "spark",          1, 0.2, alpha, 0.2, false)
    CreateAlphaAnim(f.animIn, "innerGlow",      1, 0.2, alpha, 0.3, false)
    CreateAlphaAnim(f.animIn, "ants",           1, 0.2, alpha, 0.3, true)
    f.animIn:SetScript("OnStop", AnimIn_OnStop)
    f.animIn:SetScript("OnFinished", AnimIn_OnFinished)

    f.animOut = f:CreateAnimationGroup()
    f.animOut.appear = {}
    f.animOut.fade = {}
    CreateAlphaAnim(f.animOut, "outerGlowOver", 1, 0.2, alpha, nil, true)
    CreateAlphaAnim(f.animOut, "ants",          1, 0.2, alpha, nil, false)
    CreateAlphaAnim(f.animOut, "outerGlowOver", 2, 0.2, alpha, nil, false)
    CreateAlphaAnim(f.animOut, "outerGlow",     2, 0.2, alpha, nil, false)
    f.animOut:SetScript("OnPlay", function(self) self.isPlaying = true end)
    f.animOut:SetScript("OnStop", function(self) self.isPlaying = false end)
    f.animOut:SetScript("OnFinished", function(self) self.isPlaying = false; ButtonGlowPool:Release(f) end)
    f.animOut.isPlaying = false

    f:SetScript("OnHide", bgHide)
end

local function updateAlphaAnim(f, alpha)
    for _, anim in pairs(f.animIn.appear) do anim.change = alpha end
    for _, anim in pairs(f.animIn.fade) do anim.change = -alpha end
    for _, anim in pairs(f.animOut.appear) do anim.change = alpha end
    for _, anim in pairs(f.animOut.fade) do anim.change = -alpha end
end

local ButtonGlowTextures = { spark = true, innerGlow = true, innerGlowOver = true, outerGlow = true, outerGlowOver = true, ants = true }

local function updateButtonGlowTextures(f, hasColor)
    if hasColor then
        f.innerGlow:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
        f.outerGlow:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
        f.ants:SetTexture(textureList.buttonGlowAntsDesaturated)
    else
        f.innerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
        f.outerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
        f.ants:SetTexture(textureList.buttonGlowAnts)
    end
end

local function noZero(num) return num == 0 and 0.001 or num end

local function PlaceButtonGlow(f, r, frameLevel)
    local width, height = r:GetWidth(), r:GetHeight()
    f:SetFrameLevel(r:GetFrameLevel() + frameLevel)
    f:SetWidth(width * 1.4); f:SetHeight(height * 1.4)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", r, "TOPLEFT", -width * 0.2, height * 0.2)
    f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", width * 0.2, -height * 0.2)
    return width, height
end

function G.ButtonGlow_Start(r, color, frequency, frameLevel)
    if not r then return end
    frameLevel = frameLevel or 8
    local throttle = frequency and frequency > 0 and 0.25 / frequency * 0.01 or 0.01
    if r._ButtonGlow then
        local f = r._ButtonGlow
        local width, height = PlaceButtonGlow(f, r, frameLevel)
        SetSize2(f.ants, width * 1.4 * 0.85, height * 1.4 * 0.85)
        AnimIn_OnFinished(f.animIn)
        if f.animOut.isPlaying then
            f.animOut:Stop()
            f.animIn:Play()
        end
        if not color then
            updateButtonGlowTextures(f, false)
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(nil)
                f[texture]:SetVertexColor(1, 1, 1)
                f[texture]:SetAlpha(min(f[texture]:GetAlpha() / noZero(f.color and f.color[4] or 1), 1))
            end
            updateAlphaAnim(f, 1)
            f.color = false
        else
            updateButtonGlowTextures(f, true)
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetVertexColor(color[1], color[2], color[3])
                f[texture]:SetAlpha(min(f[texture]:GetAlpha() / noZero(f.color and f.color[4] or 1) * color[4], 1))
            end
            updateAlphaAnim(f, color[4] or 1)
            f.color = color
        end
        f.throttle = throttle
    else
        local f, new = ButtonGlowPool:Acquire()
        if new then
            configureButtonGlow(f, color and color[4] or 1)
        else
            updateAlphaAnim(f, color and color[4] or 1)
        end
        r._ButtonGlow = f
        f:SetParent(r)
        PlaceButtonGlow(f, r, frameLevel)
        if not color then
            f.color = false
            updateButtonGlowTextures(f, false)
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(nil)
                f[texture]:SetVertexColor(1, 1, 1)
            end
        else
            f.color = color
            updateButtonGlowTextures(f, true)
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetVertexColor(color[1], color[2], color[3])
            end
        end
        f.throttle = throttle
        f:SetScript("OnUpdate", GlowbgUpdate)
        f.animIn:Play()
    end
end

function G.ButtonGlow_Stop(r)
    local f = r and r._ButtonGlow
    if not f then return end
    if f.animOut.isPlaying then
        -- the fade out releases it when done
    elseif f.animIn:IsPlaying() then
        f.animIn:Stop()
        ButtonGlowPool:Release(f)
    elseif r:IsVisible() then
        f.animOut:Play()
    else
        ButtonGlowPool:Release(f)
    end
end

------------------------------------------------------------------------
-- Proc glow (the retail "flipbook" proc border)
------------------------------------------------------------------------
local ProcGlowRows, ProcGlowColumns, ProcGlowFrames, ProcGlowStartDuration = 6, 5, 30, 0.7
local ProcGlowTexCoord = {
    Loop = {
        left = 0.412598, top = 0.000976562,
        frameWidth = (0.575195 - 0.412598) / ProcGlowColumns,
        frameHeight = (0.391602 - 0.000976562) / ProcGlowRows,
    },
    Start = {
        left = 0.000488281, top = 0.000976562,
        frameWidth = (0.411621 - 0.000488281) / ProcGlowColumns,
        frameHeight = (0.987305 - 0.000976562) / ProcGlowRows,
    },
}

local function SetTile(texture, frame, texCoord)
    frame = frame - 1
    local row = floor(frame / ProcGlowColumns)
    local column = mod(frame, ProcGlowColumns)
    local left = texCoord.left + texCoord.frameWidth * column
    local top = texCoord.top + texCoord.frameHeight * row
    texture:SetTexCoord(left, left + texCoord.frameWidth, top, top + texCoord.frameHeight)
end

local StartFlipbook

local function FlipbookAnimation_OnUpdate(self, elapsed)
    local data = self.flipbookData
    if not data then return end
    data.elapsedTime = data.elapsedTime + elapsed
    if data.loopDuration then
        data.startElapsed = data.startElapsed + elapsed
        if data.startElapsed >= ProcGlowStartDuration then
            local loopElapsed = data.startElapsed - ProcGlowStartDuration
            StartFlipbook(self, self.ProcLoop, ProcGlowFrames / data.loopDuration, "Loop")
            data = self.flipbookData
            data.elapsedTime = loopElapsed
        end
    end
    local framesToAdvance = floor(data.elapsedTime * data.frameRate)
    if framesToAdvance > 0 then
        data.elapsedTime = data.elapsedTime - framesToAdvance / data.frameRate
        data.currentFrame = mod(data.currentFrame - 1 + framesToAdvance, ProcGlowFrames) + 1
        SetTile(data.texture, data.currentFrame, data.texCoord)
    end
end

GlowFlipbook = HUI:PerfWrap("Glows", FlipbookAnimation_OnUpdate)

local function StopFlipbook(f)
    f:SetScript("OnUpdate", nil)
    if f.flipbookData and f.flipbookData.texture then f.flipbookData.texture:Hide() end
    f.flipbookData = nil
end

StartFlipbook = function(f, texture, frameRate, key, loopDuration)
    StopFlipbook(f)
    f.flipbookData = {
        texture = texture,
        texCoord = ProcGlowTexCoord[key],
        frameRate = frameRate,
        currentFrame = 1,
        elapsedTime = 0,
        startElapsed = loopDuration and 0,
        loopDuration = loopDuration,
    }
    SetTile(texture, 1, f.flipbookData.texCoord)
    texture:Show()
    f:SetScript("OnUpdate", GlowFlipbook)
end

local ProcGlowPool = NewPool(NewFrame, function(pool, frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetScript("OnShow", nil)
    frame:SetScript("OnHide", nil)
    frame:SetScript("OnUpdate", nil)
    local parent = frame:GetParent()
    if frame.key and parent and parent[frame.key] == frame then parent[frame.key] = nil end
end)

local function InitProcGlow(f)
    f.ProcStart = f:CreateTexture(nil, "ARTWORK")
    f.ProcStart:SetBlendMode("ADD")
    f.ProcStart:SetTexture(textureList.proc)
    f.ProcStart:SetTexCoord(0.0827148248, 0.1649413686, 0.000976562, 0.165364635)
    f.ProcStart:SetAlpha(1)
    SetSize2(f.ProcStart, 150, 150)
    f.ProcStart:SetPoint("CENTER")
    f.ProcStart:Hide()

    f.ProcLoop = f:CreateTexture(nil, "ARTWORK")
    f.ProcLoop:SetTexture(textureList.proc)
    f.ProcLoop:SetTexCoord(0.412598, 0.4451174, 0.000976562, 0.066080801666667)
    f.ProcLoop:SetAlpha(1)
    f.ProcLoop:SetAllPoints()
    f.ProcLoop:Hide()
end

local function SetupProcGlow(f, options)
    f.key = "_ProcGlow" .. options.key
    f:SetScript("OnHide", function(self) StopFlipbook(self) end)
    f:SetScript("OnShow", function(self)
        StopFlipbook(self)
        if self.startAnim then
            local width, height = self:GetWidth(), self:GetHeight()
            SetSize2(self.ProcStart, (width / 42 * 150) / 1.4, (height / 42 * 150) / 1.4)
            StartFlipbook(self, self.ProcStart, ProcGlowFrames / ProcGlowStartDuration, "Start", options.duration)
        else
            StartFlipbook(self, self.ProcLoop, ProcGlowFrames / options.duration, "Loop")
        end
    end)
    local texture = options.color and textureList.procDesaturated or textureList.proc
    f.ProcStart:SetTexture(texture)
    f.ProcLoop:SetTexture(texture)
    local color = options.color or { 1, 1, 1, 1 }
    f.ProcStart:SetVertexColor(unpack(color))
    f.ProcLoop:SetVertexColor(unpack(color))
    f.startAnim = options.startAnim
end

local ProcGlowDefaults = { frameLevel = 8, color = nil, startAnim = true, xOffset = 0, yOffset = 0, duration = 1, key = "" }

function G.ProcGlow_Start(r, options)
    if not r then return end
    options = options or {}
    setmetatable(options, { __index = ProcGlowDefaults })
    local key = "_ProcGlow" .. options.key
    local f, new
    if r[key] then
        f = r[key]
    else
        f, new = ProcGlowPool:Acquire()
        if new then InitProcGlow(f) end
        r[key] = f
    end
    f:SetParent(r)
    f:SetFrameLevel(r:GetFrameLevel() + options.frameLevel)
    local width, height = r:GetWidth(), r:GetHeight()
    local xOffset = options.xOffset + width * 0.2
    local yOffset = options.yOffset + height * 0.2
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", r, "TOPLEFT", -xOffset, yOffset)
    f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", xOffset, -yOffset)
    SetupProcGlow(f, options)
    f:Hide()   -- OnShow (re)starts the flipbook
    f:Show()
end

function G.ProcGlow_Stop(r, key)
    key = key or ""
    local f = r and r["_ProcGlow" .. key]
    if f then ProcGlowPool:Release(f) end
end

------------------------------------------------------------------------
-- One call for HUI: start / stop a glow of a kind (WeakAuras' defaults)
------------------------------------------------------------------------
G.kinds = {
    { "button", "Action Button Glow" },
    { "pixel", "Pixel Glow" },
    { "autocast", "Autocast Shine" },
    { "proc", "Proc Glow" },
}

function G.Stop(r)
    if not r or not r.atrGlowKind then return end
    local k = r.atrGlowKind
    r.atrGlowKind = nil
    if k == "button" then G.ButtonGlow_Stop(r)
    elseif k == "pixel" then G.PixelGlow_Stop(r)
    elseif k == "autocast" then G.AutoCastGlow_Stop(r)
    elseif k == "proc" then G.ProcGlow_Stop(r)
    end
end

-- frameLevel: levels above `r` (keep text you want readable higher than this)
function G.Start(r, kind, color, frameLevel)
    if not r then return end
    if (r:GetWidth() or 0) < 1 or (r:GetHeight() or 0) < 1 then return end
    kind = kind or "button"
    if r.atrGlowKind and r.atrGlowKind ~= kind then G.Stop(r) end
    frameLevel = frameLevel or 4
    if kind == "pixel" then
        G.PixelGlow_Start(r, color, 8, 0.25, 10, 1, 0, 0, false, nil, frameLevel)
    elseif kind == "autocast" then
        G.AutoCastGlow_Start(r, color, 8, 0.25, 1, 0, 0, nil, frameLevel)
    elseif kind == "proc" then
        G.ProcGlow_Start(r, { color = color, startAnim = false, duration = 1, xOffset = 0, yOffset = 0, frameLevel = frameLevel, key = "" })
    else
        kind = "button"
        G.ButtonGlow_Start(r, color, 0.25, frameLevel)
    end
    r.atrGlowKind = kind
end
