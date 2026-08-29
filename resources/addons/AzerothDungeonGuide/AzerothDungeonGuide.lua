local ADDON_NAME = ...
local PREFIX = "DC"

AzerothDungeonGuideDB = AzerothDungeonGuideDB or {}

local activeInstanceKey
local scheduledInstanceKey
local shownInstanceKey
local waitForCombatKey
local timers = {}

local driver = CreateFrame("Frame")

local function After(delay, callback)
    table.insert(timers, { remaining = delay, callback = callback })
end

driver:SetScript("OnUpdate", function(_, elapsed)
    for index = #timers, 1, -1 do
        local timer = timers[index]
        timer.remaining = timer.remaining - elapsed
        if timer.remaining <= 0 then
            table.remove(timers, index)
            timer.callback()
        end
    end
end)

local function DungeonIdentity()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then return nil end

    local name = GetInstanceInfo and GetInstanceInfo() or nil
    name = name or GetRealZoneText() or "Dungeon"
    return "party:" .. name, name
end

local function SendDungeonClearCommand(command, parameter)
    local payload = "CMD\t" .. command
    if parameter and parameter ~= "" then
        payload = payload .. "\t" .. tostring(parameter)
    end

    local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
    local inParty = GetNumPartyMembers and GetNumPartyMembers() > 0
    if inRaid or inParty then
        SendAddonMessage(PREFIX, payload, inRaid and "RAID" or "PARTY")
        return true
    end

    local playerName = UnitName("player")
    if playerName and playerName ~= "" then
        SendAddonMessage(PREFIX, payload, "WHISPER", playerName)
        return true
    end
    return false
end

local popup = CreateFrame("Frame", "AzerothDungeonGuideFrame", UIParent)
popup:SetAllPoints(UIParent)
popup:SetFrameStrata("FULLSCREEN_DIALOG")
popup:SetFrameLevel(50)
popup:EnableMouse(true)
popup:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
popup:SetBackdropColor(0, 0, 0, 0.72)
popup:Hide()

UISpecialFrames = UISpecialFrames or {}
table.insert(UISpecialFrames, "AzerothDungeonGuideFrame")

local card = CreateFrame("Frame", nil, popup)
card:SetSize(570, 450)
card:SetScale(1.15)
card:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
card:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 18,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
})
card:SetBackdropColor(0.035, 0.055, 0.075, 0.98)
card:SetBackdropBorderColor(0.72, 0.52, 0.20, 1)

local closeButton = CreateFrame("Button", nil, card, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
closeButton:SetScript("OnClick", function() popup:Hide() end)

local eyebrow = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
eyebrow:SetPoint("TOPLEFT", card, "TOPLEFT", 28, -24)
eyebrow:SetText("DUNGEON CLEAR")
eyebrow:SetTextColor(0.95, 0.68, 0.25)

local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -9)
title:SetText("How should we run this dungeon?")
title:SetTextColor(1, 0.94, 0.82)

local dungeonLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
dungeonLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
dungeonLabel:SetWidth(505)
dungeonLabel:SetJustifyH("LEFT")
dungeonLabel:SetTextColor(0.62, 0.70, 0.78)

local function SetButtonLook(button, highlighted)
    local color = button.accent
    if highlighted then
        button:SetBackdropColor(color[1] * 0.28, color[2] * 0.28, color[3] * 0.28, 1)
        button:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    else
        button:SetBackdropColor(0.07, 0.10, 0.13, 1)
        button:SetBackdropBorderColor(0.22, 0.28, 0.33, 1)
    end
end

local function MakeChoice(index, heading, description, accent, callback)
    local button = CreateFrame("Button", "AzerothDungeonGuideChoice" .. index, card)
    button:SetSize(514, 61)
    button:SetPoint("TOPLEFT", card, "TOPLEFT", 28, -105 - ((index - 1) * 69))
    button:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 12,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    button.accent = accent
    SetButtonLook(button, false)

    local number = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    number:SetPoint("LEFT", button, "LEFT", 16, 0)
    number:SetText(index)
    number:SetTextColor(accent[1], accent[2], accent[3])

    local buttonTitle = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonTitle:SetPoint("TOPLEFT", button, "TOPLEFT", 48, -12)
    buttonTitle:SetText(heading)
    buttonTitle:SetTextColor(0.96, 0.96, 0.96)

    local buttonDescription = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buttonDescription:SetPoint("TOPLEFT", buttonTitle, "BOTTOMLEFT", 0, -5)
    buttonDescription:SetWidth(440)
    buttonDescription:SetJustifyH("LEFT")
    buttonDescription:SetText(description)
    buttonDescription:SetTextColor(0.58, 0.65, 0.71)

    button:SetScript("OnEnter", function(self) SetButtonLook(self, true) end)
    button:SetScript("OnLeave", function(self) SetButtonLook(self, false) end)
    button:SetScript("OnClick", callback)
    return button
end

local function Notify(message, red)
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(message, red and 1 or 0.35, red and 0.30 or 0.95, red and 0.25 or 0.55, 1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffb347[Azeroth Dungeon Guide]|r " .. message)
    end
end

local function StartTankRun(pullMode, label)
    if not SendDungeonClearCommand("pull", pullMode) then
        Notify("Dungeon Clear commands are unavailable.", true)
        return
    end

    popup:Hide()
    Notify(label .. " selected. The bot tank is taking the lead.", false)
    After(0.20, function()
        SendDungeonClearCommand("on")
    end)
end

MakeChoice(1, "Dynamic — Recommended", "The tank chooses fast or careful pulls for each pack.", {0.22, 0.72, 1.00}, function()
    StartTankRun("dynamic", "Dynamic run")
end)

MakeChoice(2, "Fast — Charge Ahead", "The tank fights packs where they stand. Best when the group is strong.", {1.00, 0.62, 0.16}, function()
    StartTankRun("off", "Fast run")
end)

MakeChoice(3, "Careful — Pull to Camp", "The party waits while the tank brings each pack back safely.", {0.38, 0.85, 0.47}, function()
    StartTankRun("on", "Careful run")
end)

MakeChoice(4, "Manual — I Will Lead", "Dungeon Clear stays off and the bots continue following you.", {0.72, 0.72, 0.76}, function()
    SendDungeonClearCommand("off")
    popup:Hide()
    Notify("Manual run selected. Your bots will follow you.", false)
end)

local hint = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("BOTTOM", card, "BOTTOM", 0, 18)
hint:SetText("D-Pad / Stick: move cursor     A: select     B: close")
hint:SetTextColor(0.50, 0.57, 0.63)

local function ShowPrompt(instanceKey, instanceName)
    if InCombatLockdown and InCombatLockdown() then
        waitForCombatKey = instanceKey
        return
    end
    local currentKey, currentName = DungeonIdentity()
    if currentKey ~= instanceKey then return end

    shownInstanceKey = instanceKey
    waitForCombatKey = nil
    dungeonLabel:SetText((currentName or instanceName or "Dungeon") .. "  •  Requires a tank bot in your party")
    popup:Show()

    if ConsolePort and ConsolePort.UpdateFrameTracker then
        ConsolePort:UpdateFrameTracker()
    end
end

local function InspectLocation()
    local instanceKey, instanceName = DungeonIdentity()
    if not instanceKey then
        activeInstanceKey = nil
        scheduledInstanceKey = nil
        shownInstanceKey = nil
        waitForCombatKey = nil
        popup:Hide()
        return
    end

    if instanceKey == activeInstanceKey then return end
    activeInstanceKey = instanceKey
    shownInstanceKey = nil
    scheduledInstanceKey = instanceKey
    After(2.25, function()
        if scheduledInstanceKey == instanceKey and shownInstanceKey ~= instanceKey then
            scheduledInstanceKey = nil
            ShowPrompt(instanceKey, instanceName)
        end
    end)
end

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
        if ConsolePort and ConsolePort.AddFrameTracker then
            ConsolePort:AddFrameTracker(popup)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and waitForCombatKey then
        local key, name = DungeonIdentity()
        if key == waitForCombatKey then ShowPrompt(key, name) end
        return
    end

    InspectLocation()
end)

SLASH_AZEROTHDUNGEONGUIDE1 = "/adg"
SLASH_AZEROTHDUNGEONGUIDE2 = "/dungeonrun"
SlashCmdList.AZEROTHDUNGEONGUIDE = function(message)
    message = string.lower(message or "")
    if message == "off" then
        SendDungeonClearCommand("off")
        popup:Hide()
        Notify("Dungeon Clear stopped.", false)
        return
    end

    local key, name = DungeonIdentity()
    if not key then
        Notify("Enter a dungeon before opening the run selector.", true)
        return
    end
    ShowPrompt(key, name)
end
