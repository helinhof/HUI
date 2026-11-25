-- HUI - Chat bubbles (ElvUI style)
-- Speech bubbles lose their parchment art and tail and become a dark box
-- (background colour) with a 1px black border, and the
-- chat font. Bubbles are children of WorldFrame with no name, so new ones
-- are looked for whenever WorldFrame gets more children.
-- The game makes the bubble frame much bigger than its text, so the box is
-- drawn by HUI, fitted to the text with a small margin (PAD_X / PAD_Y).

local A = HUI
local select = select

local BUBBLE_TEX = "Interface\\Tooltips\\ChatBubble-Background"
local PAD_X, PAD_Y = 6, 4   -- screen pixels between the text and the border
local bubbles = {}

local function IsBubble(f)
    if f:GetName() or not f.GetRegions then return false end
    for i = 1, f:GetNumRegions() do
        local r = select(i, f:GetRegions())
        if r and r.GetTexture and r:GetTexture() == BUBBLE_TEX then return true end
    end
    return false
end

-- size the box to the text (the game reuses bubbles for new messages)
local function Fit(f)
    local t, bg = f.huiText, f.huiBg
    if not (t and bg) then return end
    local px = A:PX(f)
    local sw, rw = t:GetStringWidth() or 0, t:GetWidth() or 0
    local w = (sw > 0 and rw > 0) and math.min(sw, rw) or math.max(sw, rw)
    local h = t:GetStringHeight() or 0
    if h <= 0 then h = t:GetHeight() or 0 end
    w = A:Snap(f, w + 2 * PAD_X * px)
    h = A:Snap(f, h + 2 * PAD_Y * px)
    if bg.huiW ~= w or bg.huiH ~= h then
        bg.huiW, bg.huiH = w, h
        bg:SetWidth(w)
        bg:SetHeight(h)
    end
end

local function UpdateBorder(f)
    if not f.huiText then return end
    local c = A.colors.backdrop
    f.huiBg:SetTexture(c[1], c[2], c[3], c[4])
    local size = A.db.bubbleFontSize or 10
    if f.huiSize ~= size then
        f.huiSize = size
        f.huiText:SetFont(A.media.chatFont, size, "")
    end
    Fit(f)
end

local function Skin(f)
    for i = 1, f:GetNumRegions() do
        local r = select(i, f:GetRegions())
        if r:IsObjectType("Texture") then
            r:SetTexture(nil)
        elseif r:IsObjectType("FontString") then
            f.huiText = r
        end
    end
    f:SetBackdrop(nil)
    if not f.huiText then f.huiBubble = true return end
    local px = A:PX(f)
    -- the box: background behind the text, 1px black lines around it
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("CENTER", f.huiText, "CENTER", 0, 0)
    f.huiBg = bg
    local function Edge()
        local e = f:CreateTexture(nil, "BORDER")
        e:SetTexture(0, 0, 0, 1)
        return e
    end
    local top, bottom, left, right = Edge(), Edge(), Edge(), Edge()
    top:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", -px, 0)
    top:SetPoint("BOTTOMRIGHT", bg, "TOPRIGHT", px, 0)
    top:SetHeight(px)
    bottom:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", -px, 0)
    bottom:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", px, 0)
    bottom:SetHeight(px)
    left:SetPoint("TOPRIGHT", bg, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", bg, "BOTTOMLEFT", 0, 0)
    left:SetWidth(px)
    right:SetPoint("TOPLEFT", bg, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMLEFT", bg, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(px)

    f.huiText:SetFont(A.media.chatFont, A.db.bubbleFontSize or 10, "")
    f.huiText:SetShadowOffset(px, -px)
    f.huiText:SetShadowColor(0, 0, 0, 1)
    f:HookScript("OnShow", UpdateBorder)
    f:SetFrameStrata("BACKGROUND")
    UpdateBorder(f)
    f.huiBubble = true
    bubbles[#bubbles + 1] = f
end

function A:BuildChatBubbles()
    if self.bubbleFrame or not self.db.bubbles then return end
    local last, acc = 0, -2   -- start looking after two seconds
    local scan = CreateFrame("Frame")
    self.bubbleFrame = scan
    scan:SetScript("OnUpdate", A:PerfWrap("Chat bubbles", function(_, el)
        acc = acc + el
        if acc < 0.1 then return end
        acc = 0
        -- re-fit the boxes of the bubbles on screen (their text changes)
        for i = 1, #bubbles do
            local f = bubbles[i]
            if f:IsShown() then Fit(f) end
        end
        local n = WorldFrame:GetNumChildren()
        if n == last then return end
        local function check(...)
            for i = last + 1, n do
                local f = select(i, ...)
                if f and not f.huiBubble and IsBubble(f) then Skin(f) end
            end
        end
        check(WorldFrame:GetChildren())
        last = n
    end))
end
