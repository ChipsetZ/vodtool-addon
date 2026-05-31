--[[
  VodSync — precision timestamp overlay for VOD synchronisation
  ─────────────────────────────────────────────────────────────
  Shows one short line in the top-left corner at the start of each boss pull:

    1779210806.402       ← Unix time (seconds.ms) — OCR sync anchor

  Renders as opaque white digits on a solid black plate so an OCR pipeline
  (downscaled to 720p, lanczos upscaled, tesseract) can read it reliably.
  The plate is small enough not to obscure raid frames, but bright enough
  to survive grayscale + contrast steps.

  Fires on ENCOUNTER_START, auto-hides after SHOW_DURATION seconds.
  Use /vodsync test to preview without a boss pull.

  INSTALL: drop the VodSync/ folder into <WoW>/Interface/AddOns/
--]]

-- ── Configuration ─────────────────────────────────────────────────────────────
local PLATE_ALPHA   = 1.0    -- background plate opacity (0..1). 1.0 = best OCR.
local TEXT_ALPHA    = 1.0    -- timestamp text opacity (0..1). 1.0 = best OCR.
local FONT_SIZE     = 22     -- larger digits = OCR robust against downscale
local FONT_PATH     = "Fonts\\ARIALN.TTF" -- narrow monospace-ish, clean digit forms
local FONT_FLAGS    = "OUTLINE"
local PAD_X         = 6      -- plate horizontal padding around text (px)
local PAD_Y         = 3      -- plate vertical padding around text (px)
local UPDATE_HZ     = 30     -- updates per second
local SHOW_DURATION = 5      -- seconds to show overlay after pull starts
-- ──────────────────────────────────────────────────────────────────────────────

-- On by default every session. /vodsync off to hide for this session only.
local enabled   = true
local showTimer = 0

local frame = CreateFrame("Frame", "VodSyncFrame", UIParent)
-- TOOLTIP strata + frameLevel 1000 keep us above raid frames, action bars, etc.
frame:SetFrameStrata("TOOLTIP")
frame:SetFrameLevel(1000)
frame:SetAllPoints(UIParent)
frame:SetIgnoreParentScale(true)
frame:SetIgnoreParentAlpha(true)
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")

-- Solid black plate sized to text. Drawn under the FontString so the digits
-- sit on a uniform high-contrast background — survives grayscale conversion.
local plate = frame:CreateTexture(nil, "BACKGROUND")
plate:SetColorTexture(0, 0, 0, PLATE_ALPHA)
plate:Hide()

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetDrawLayer("OVERLAY", 7)
text:SetFont(FONT_PATH, FONT_SIZE, FONT_FLAGS)
text:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 6 + PAD_X, -6 - PAD_Y)
text:SetTextColor(1, 1, 1, TEXT_ALPHA)
text:SetJustifyH("LEFT")
text:Hide()

-- Anchor the plate to fit the text snugly with PAD_*.
plate:SetPoint("TOPLEFT",     text, "TOPLEFT",     -PAD_X, PAD_Y)
plate:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT",  PAD_X, -PAD_Y)

local function ensureTop()
    if frame:GetFrameStrata() ~= "TOOLTIP" then
        frame:SetFrameStrata("TOOLTIP")
    end
    if frame:GetFrameLevel() < 1000 then
        frame:SetFrameLevel(1000)
    end
end

-- Sync GetServerTime (integer Unix seconds) with GetTime (float uptime) so we
-- can interpolate sub-second precision. Re-anchored on every ENCOUNTER_START
-- so loading screens / alt-tabs that pause GetTime can't cause the overlay to
-- drift behind real wall-clock — at most 5s (SHOW_DURATION) of drift is
-- possible within the visible window.
local serverBase = GetServerTime()
local clientBase = GetTime()

local ticker = 0

frame:SetScript("OnEvent", function(_, event)
    if event == "ENCOUNTER_START" then
        serverBase = GetServerTime()
        clientBase = GetTime()
        showTimer = SHOW_DURATION
        ensureTop()
    elseif event == "ENCOUNTER_END" then
        showTimer = 0
        text:Hide()
        plate:Hide()
    end
end)

frame:SetScript("OnUpdate", function(_, dt)
    if showTimer > 0 then
        showTimer = showTimer - dt
    end

    ticker = ticker + dt
    if ticker < (1 / UPDATE_HZ) then return end
    ticker = 0

    local _, instanceType = IsInInstance()
    if not enabled or instanceType ~= "raid" or showTimer <= 0 then
        text:Hide()
        plate:Hide()
        return
    end

    local unixFloat = serverBase + (GetTime() - clientBase)
    text:SetText(string.format("%.3f", unixFloat))
    text:Show()
    plate:Show()
end)

-- ── Slash command ─────────────────────────────────────────────────────────────
--   /vodsync          → toggle on/off
--   /vodsync on|off   → explicit
--   /vodsync 0.85     → set plate+text alpha (0.01–1.0). 1.0 is best for OCR.
--   /vodsync test     → preview overlay for SHOW_DURATION seconds
SLASH_VODSYNC1 = "/vodsync"
SlashCmdList["VODSYNC"] = function(msg)
    msg = strtrim(msg):lower()

    if msg == "off" then
        enabled   = false
        showTimer = 0
        text:Hide()
        plate:Hide()
        print("|cff00ff00VodSync|r off for this session (resets on relog)")

    elseif msg == "on" then
        enabled = true
        print("|cff00ff00VodSync|r on")

    elseif msg == "test" then
        showTimer = SHOW_DURATION
        ensureTop()
        print(string.format("|cff00ff00VodSync|r showing for %d seconds (test)", SHOW_DURATION))

    elseif msg == "" then
        enabled = not enabled
        if not enabled then showTimer = 0; text:Hide(); plate:Hide() end
        print("|cff00ff00VodSync|r " .. (enabled and "on" or "off for this session (resets on relog)"))

    else
        local val = tonumber(msg)
        if val and val >= 0.01 and val <= 1.0 then
            PLATE_ALPHA = val
            TEXT_ALPHA  = val
            plate:SetColorTexture(0, 0, 0, PLATE_ALPHA)
            text:SetTextColor(1, 1, 1, TEXT_ALPHA)
            print(string.format("|cff00ff00VodSync|r opacity set to %.2f", val))
        else
            print("|cff00ff00VodSync|r  /vodsync          — toggle on/off")
            print("|cff00ff00VodSync|r  /vodsync on|off   — explicit")
            print("|cff00ff00VodSync|r  /vodsync 0.85     — set opacity (1.0 is best for OCR)")
            print(string.format("|cff00ff00VodSync|r  /vodsync test     — preview for %ds", SHOW_DURATION))
        end
    end
end
