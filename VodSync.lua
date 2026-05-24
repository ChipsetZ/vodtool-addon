--[[
  VodSync — precision timestamp overlay for VOD synchronisation
  ─────────────────────────────────────────────────────────────
  Shows three lines in the top-left corner at the start of each boss pull:

    1775499538.402       ← Unix time (seconds.ms) — primary OCR target
    868004.732           ← GetTime() client uptime — high-precision anchor
    18:19:43  06/04      ← Human-readable UTC time / date — visual fallback

  Fires on ENCOUNTER_START, auto-hides after SHOW_DURATION seconds.
  Use /vodsync test to preview without a boss pull.

  INSTALL: drop the VodSync/ folder into <WoW>/Interface/AddOns/
--]]

-- ── Configuration ─────────────────────────────────────────────────────────────
local ALPHA         = 0.15   -- opacity: 0.08 (barely visible) to 0.25 (readable)
local FONT_SIZE     = 14     -- larger = better OCR; 14 readable without being intrusive
local FONT_PATH     = "Fonts\\FRIZQT__.TTF"
local FONT_FLAGS    = "MONOCHROME,OUTLINE"
local UPDATE_HZ     = 30     -- updates per second
local SHOW_DURATION = 5      -- seconds to show overlay after pull starts
-- ──────────────────────────────────────────────────────────────────────────────

-- On by default every session. /vodsync off to hide for this session only.
-- Relogging resets it back to on.
local enabled   = true
local showTimer = 0   -- counts down from SHOW_DURATION; overlay visible while > 0

local frame = CreateFrame("Frame", "VodSyncFrame", UIParent)
-- TOOLTIP is the highest normal-use strata; FULLSCREEN_DIALOG would also work
-- but blocks parts of the UI Blizzard considers dialog-level. We want the
-- overlay visually on top of raid frames, unit frames, action bars, etc.,
-- which all sit at MEDIUM or HIGH at most. Frame level 1000 within TOOLTIP
-- pushes us above other TOOLTIP-strata frames if any addon shares this strata.
frame:SetFrameStrata("TOOLTIP")
frame:SetFrameLevel(1000)
frame:SetAllPoints(UIParent)
frame:SetIgnoreParentScale(true) -- avoid being shrunk by UIParent scale changes
frame:SetIgnoreParentAlpha(true) -- avoid being faded by parent alpha (e.g. cinematics)
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetDrawLayer("OVERLAY", 7) -- topmost sublevel within OVERLAY draw layer
text:SetFont(FONT_PATH, FONT_SIZE, FONT_FLAGS)
text:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 6, -6)
text:SetTextColor(1, 1, 1, ALPHA)
text:SetJustifyH("LEFT")
text:Hide()

-- Re-assert top strata if another addon yanks us down (rare but cheap insurance)
local function ensureTop()
    if frame:GetFrameStrata() ~= "TOOLTIP" then
        frame:SetFrameStrata("TOOLTIP")
    end
    if frame:GetFrameLevel() < 1000 then
        frame:SetFrameLevel(1000)
    end
end

-- Sync GetServerTime (integer Unix seconds) with GetTime (float uptime) once
-- at load so we can interpolate sub-second precision on the Unix timestamp.
local serverBase = GetServerTime()   -- Unix seconds, integer
local clientBase = GetTime()         -- WoW uptime seconds, float

local ticker = 0

frame:SetScript("OnEvent", function(_, event)
    if event == "ENCOUNTER_START" then
        showTimer = SHOW_DURATION
        ensureTop()
    elseif event == "ENCOUNTER_END" then
        showTimer = 0
        text:Hide()
    end
end)

frame:SetScript("OnUpdate", function(_, dt)
    -- Drain the show timer regardless of throttle
    if showTimer > 0 then
        showTimer = showTimer - dt
    end

    ticker = ticker + dt
    if ticker < (1 / UPDATE_HZ) then return end
    ticker = 0

    local _, instanceType = IsInInstance()
    if not enabled or instanceType ~= "raid" or showTimer <= 0 then
        text:Hide()
        return
    end

    local clientNow = GetTime()

    -- ── Line 1: Unix timestamp seconds.milliseconds ──────────────────────────
    local unixFloat = serverBase + (clientNow - clientBase)
    local line1 = string.format("%.3f", unixFloat)

    -- ── Line 2: GetTime() client uptime ──────────────────────────────────────
    local line2 = string.format("%.3f", clientNow)

    -- ── Line 3: HH:MM:SS  DD/MM  (derived from unixFloat) ───────────────────
    local secs = math.floor(unixFloat)
    local hh   = math.floor(secs / 3600) % 24
    local mm   = math.floor(secs / 60)   % 60
    local ss   = secs % 60
    local ddmm = date("%d/%m")
    local line3 = string.format("%02d:%02d:%02d  %s", hh, mm, ss, ddmm)

    text:SetText(line1 .. "\n" .. line2 .. "\n" .. line3)
    text:Show()
end)

-- ── Slash command ─────────────────────────────────────────────────────────────
--   /vodsync          → toggle on/off
--   /vodsync on|off   → explicit
--   /vodsync 0.15     → set opacity (0.01–1.0)
--   /vodsync test     → show overlay for SHOW_DURATION (preview without a pull)
SLASH_VODSYNC1 = "/vodsync"
SlashCmdList["VODSYNC"] = function(msg)
    msg = strtrim(msg):lower()

    if msg == "off" then
        enabled   = false
        showTimer = 0
        text:Hide()
        print("|cff00ff00VodSync|r off for this session (resets on relog)")

    elseif msg == "on" then
        enabled = true
        print("|cff00ff00VodSync|r on")

    elseif msg == "test" then
        -- Preview without needing an actual boss pull (works anywhere in a raid)
        showTimer = SHOW_DURATION
        ensureTop()
        print(string.format("|cff00ff00VodSync|r showing for %d seconds (test)", SHOW_DURATION))

    elseif msg == "" then
        enabled = not enabled
        if not enabled then showTimer = 0; text:Hide() end
        print("|cff00ff00VodSync|r " .. (enabled and "on" or "off for this session (resets on relog)"))

    else
        local val = tonumber(msg)
        if val and val >= 0.01 and val <= 1.0 then
            ALPHA = val
            text:SetTextColor(1, 1, 1, ALPHA)
            print(string.format("|cff00ff00VodSync|r opacity set to %.2f", ALPHA))
        else
            print("|cff00ff00VodSync|r  /vodsync          — toggle on/off")
            print("|cff00ff00VodSync|r  /vodsync on|off   — explicit")
            print("|cff00ff00VodSync|r  /vodsync 0.15     — set opacity")
            print(string.format("|cff00ff00VodSync|r  /vodsync test     — preview for %ds", SHOW_DURATION))
        end
    end
end
