local ADDON_NAME = ...

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local bindings = {
    -- Face buttons. Base actions match the requested FFXIV-style controls;
    -- L2, R2 and L2+R2 expose three eight-slot skill banks.
    CP_R_LEFT = {
        [""] = "TOGGLEWORLDMAP",
        ["SHIFT-"] = "ACTIONBUTTON1",
        ["CTRL-"] = "ACTIONBUTTON9",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON1",
    },
    CP_R_DOWN = {
        [""] = "INTERACTTARGET",
        ["SHIFT-"] = "ACTIONBUTTON2",
        ["CTRL-"] = "ACTIONBUTTON10",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON2",
    },
    CP_R_UP = {
        [""] = "JUMP",
        ["SHIFT-"] = "ACTIONBUTTON3",
        ["CTRL-"] = "ACTIONBUTTON11",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON3",
    },
    CP_R_RIGHT = {
        [""] = "TOGGLEGAMEMENU",
        ["SHIFT-"] = "ACTIONBUTTON4",
        ["CTRL-"] = "ACTIONBUTTON12",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON4",
    },

    -- The unmodified D-pad is reserved for target navigation. It becomes a
    -- skill diamond while either trigger is held.
    CP_L_LEFT = {
        [""] = "TARGETPREVIOUSENEMY",
        ["SHIFT-"] = "ACTIONBUTTON5",
        ["CTRL-"] = "MULTIACTIONBAR1BUTTON1",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON5",
    },
    CP_L_DOWN = {
        [""] = "TARGETSELF",
        ["SHIFT-"] = "ACTIONBUTTON6",
        ["CTRL-"] = "MULTIACTIONBAR1BUTTON2",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON6",
    },
    CP_L_UP = {
        [""] = "TARGETNEARESTFRIEND",
        ["SHIFT-"] = "ACTIONBUTTON7",
        ["CTRL-"] = "MULTIACTIONBAR1BUTTON3",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON7",
    },
    CP_L_RIGHT = {
        [""] = "TARGETNEARESTENEMY",
        ["SHIFT-"] = "ACTIONBUTTON8",
        ["CTRL-"] = "MULTIACTIONBAR1BUTTON4",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR2BUTTON8",
    },

    -- L1 always cycles enemies. R1 opens ConsolePort's utility ring.
    CP_T1 = { [""] = "TARGETNEARESTENEMY" },
    CP_T2 = { [""] = "CLICK ConsolePortUtilityToggle:LeftButton" },

    CP_X_LEFT = {
        [""] = "OPENALLBAGS",
        ["SHIFT-"] = "TOGGLECHARACTER0",
        ["CTRL-"] = "TOGGLESPELLBOOK",
        ["CTRL-SHIFT-"] = "TOGGLETALENTS",
    },
    CP_X_RIGHT = { [""] = "TOGGLEGAMEMENU" },

    -- Steam Deck / Steam Controller rear buttons remain useful extra slots.
    CP_T3 = {
        [""] = "MULTIACTIONBAR3BUTTON1",
        ["SHIFT-"] = "MULTIACTIONBAR3BUTTON2",
        ["CTRL-"] = "MULTIACTIONBAR3BUTTON3",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR3BUTTON4",
    },
    CP_T4 = {
        [""] = "MULTIACTIONBAR3BUTTON5",
        ["SHIFT-"] = "MULTIACTIONBAR3BUTTON6",
        ["CTRL-"] = "MULTIACTIONBAR3BUTTON7",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR3BUTTON8",
    },
    CP_T5 = {
        [""] = "MULTIACTIONBAR3BUTTON9",
        ["SHIFT-"] = "MULTIACTIONBAR3BUTTON10",
        ["CTRL-"] = "MULTIACTIONBAR3BUTTON11",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR3BUTTON12",
    },
    CP_T6 = {
        [""] = "MULTIACTIONBAR4BUTTON1",
        ["SHIFT-"] = "MULTIACTIONBAR4BUTTON2",
        ["CTRL-"] = "MULTIACTIONBAR4BUTTON3",
        ["CTRL-SHIFT-"] = "MULTIACTIONBAR4BUTTON4",
    },
}

local crossbar = {
    scale = 1.10,
    width = 1100,
    watchbars = true,
    showline = false,
    lock = true,
    useSquareButtons = true,
    isTriple = true,
    dividers = {
        DIVIDER_LEFT = {
            point = {"BOTTOM", -170, 95}, breadth = 130, depth = 300,
            rotation = 90, thickness = 2, intensity = 12,
            opacity = {focus = "M1", hidden = "M2"},
        },
        DIVIDER_RIGHT = {
            point = {"BOTTOM", 172, 95}, breadth = 130, depth = 300,
            rotation = 270, thickness = 2, intensity = 12,
            opacity = {focus = "M2", hidden = "M1"},
        },
        DIVIDER_CENTER_L = {
            point = {"BOTTOM", -168, 95}, breadth = 130, depth = 300,
            rotation = 270, thickness = 2, intensity = 12,
            opacity = {focus = "M0", hidden = "M1,M2"},
        },
        DIVIDER_CENTER_R = {
            point = {"BOTTOM", 170, 95}, breadth = 130, depth = 300,
            rotation = 90, thickness = 2, intensity = 12,
            opacity = {focus = "M0", hidden = "M1,M2"},
        },
    },
    layout = {
        CP_L_UP_SHIFT = {point = {"BOTTOM", -400, 100}, size = 45},
        CP_L_DOWN_SHIFT = {point = {"BOTTOM", -400, 50}, size = 45},
        CP_L_LEFT_SHIFT = {point = {"BOTTOM", -450, 75}, size = 45},
        CP_L_RIGHT_SHIFT = {point = {"BOTTOM", -350, 75}, size = 45},
        CP_R_UP_SHIFT = {point = {"BOTTOM", -250, 100}, size = 45},
        CP_R_DOWN_SHIFT = {point = {"BOTTOM", -250, 50}, size = 45},
        CP_R_LEFT_SHIFT = {point = {"BOTTOM", -300, 75}, size = 45},
        CP_R_RIGHT_SHIFT = {point = {"BOTTOM", -200, 75}, size = 45},

        CP_T3 = {point = {"BOTTOM", -75, 215}, size = 45, scale = 0.8, static = true},
        CP_T4 = {point = {"BOTTOM", -25, 215}, size = 45, scale = 0.8, static = true},
        CP_T1 = {point = {"BOTTOM", 25, 215}, size = 45, scale = 0.8, static = true},
        CP_T2 = {point = {"BOTTOM", 75, 215}, size = 45, scale = 0.8, static = true},

        CP_L_UP = {point = {"BOTTOM", -75, 100}, size = 45},
        CP_L_DOWN = {point = {"BOTTOM", -75, 50}, size = 45},
        CP_L_LEFT = {point = {"BOTTOM", -125, 75}, size = 45},
        CP_L_RIGHT = {point = {"BOTTOM", -25, 75}, size = 45},
        CP_R_UP = {point = {"BOTTOM", 75, 100}, size = 45},
        CP_R_DOWN = {point = {"BOTTOM", 75, 50}, size = 45},
        CP_R_LEFT = {point = {"BOTTOM", 25, 75}, size = 45},
        CP_R_RIGHT = {point = {"BOTTOM", 125, 75}, size = 45},

        CP_L_UP_CTRL = {point = {"BOTTOM", 250, 100}, size = 45},
        CP_L_DOWN_CTRL = {point = {"BOTTOM", 250, 50}, size = 45},
        CP_L_LEFT_CTRL = {point = {"BOTTOM", 200, 75}, size = 45},
        CP_L_RIGHT_CTRL = {point = {"BOTTOM", 300, 75}, size = 45},
        CP_R_UP_CTRL = {point = {"BOTTOM", 400, 100}, size = 45},
        CP_R_DOWN_CTRL = {point = {"BOTTOM", 400, 50}, size = 45},
        CP_R_LEFT_CTRL = {point = {"BOTTOM", 350, 75}, size = 45},
        CP_R_RIGHT_CTRL = {point = {"BOTTOM", 450, 75}, size = 45},
    },
}

local changedSettings = {
    forceController = "STEAMDECK",
    type = "STEAMDECK",
    CP_M1 = "CP_TL2",
    CP_M2 = "CP_TR2",
    CP_T1 = "CP_TL1",
    CP_T2 = "CP_TR1",
    interactWith = "CP_R_DOWN",
    interactNPC = true,
    interactCache = true,
    skipGuideBtn = true,
    calibration = {
        CP_L_UP = "F1",
        CP_L_RIGHT = "F2",
        CP_L_DOWN = "F3",
        CP_L_LEFT = "F4",
        CP_X_LEFT = "F5",
        CP_T1 = "F7",
        CP_T2 = "F8",
        CP_R_UP = "F9",
        CP_R_RIGHT = "F10",
        CP_R_DOWN = "F11",
        CP_R_LEFT = "F12",
        CP_T3 = "]",
        CP_T4 = "'",
        CP_T5 = "[",
        CP_T6 = ";",
    },
}

local function currentSpec(data)
    if data and data.CPAPI and data.CPAPI.GetSpecialization then
        return data.CPAPI.GetSpecialization()
    end
    return GetActiveTalentGroup and GetActiveTalentGroup() or 1
end

local function rememberBackup(data, specID)
    if AzerothFFXIVControllerDB.backup then return end
    local oldBindings = ConsolePortBindingSet and ConsolePortBindingSet[specID]
    local oldSettings = {}
    ConsolePortSettings = ConsolePortSettings or {}
    for key in pairs(changedSettings) do oldSettings[key] = copy(ConsolePortSettings[key]) end
    AzerothFFXIVControllerDB.backup = {
        bindings = copy(oldBindings or (data and data.Bindings) or {}),
        bar = copy(ConsolePortBarSetup),
        settings = oldSettings,
    }
end

local function loadBindings(data, specID, newBindings)
    ConsolePortBindingSet = ConsolePortBindingSet or {}
    ConsolePortBindingSet[specID] = copy(newBindings)
    data.Bindings = ConsolePortBindingSet[specID]
    ConsolePort:LoadBindingSet(data.Bindings, true)
end

local function applyPreset(force)
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffb347[Azeroth FFXIV]|r Leave combat, then use /affxiv apply.")
        return false
    end
    if not ConsolePort or not ConsolePort.GetData or not ConsolePortBar or not ConsolePortBar.OnLoad then
        print("|cffff5a5a[Azeroth FFXIV]|r ConsolePortLK and ConsolePortBar are required.")
        return false
    end

    AzerothFFXIVControllerDB = AzerothFFXIVControllerDB or {}
    local generation = AZEROTH_FFXIV_PRESET_GENERATION or "packaged"
    if not force and AzerothFFXIVControllerDB.generation == generation then return true end

    local data = ConsolePort:GetData()
    local specID = currentSpec(data)
    rememberBackup(data, specID)

    ConsolePortSettings = ConsolePortSettings or {}
    for key, value in pairs(changedSettings) do ConsolePortSettings[key] = copy(value) end
    loadBindings(data, specID, bindings)
    ConsolePortBar:OnLoad(copy(crossbar), true)
    if ConsolePort.UpdateMouseDriver then ConsolePort:UpdateMouseDriver() end

    AzerothFFXIVControllerDB.generation = generation
    AzerothFFXIVControllerDB.appliedAt = date and date("%Y-%m-%d %H:%M:%S") or "applied"
    AzerothFFXIVControllerDB.restored = nil
    print("|cff6ee7a8[Azeroth FFXIV]|r Crossbar preset applied. L2/R2 open skill banks; /affxiv shows help.")
    return true
end

local function restorePreset()
    AzerothFFXIVControllerDB = AzerothFFXIVControllerDB or {}
    local backup = AzerothFFXIVControllerDB.backup
    if not backup then
        print("|cffffb347[Azeroth FFXIV]|r No earlier controller settings were recorded for this character.")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffb347[Azeroth FFXIV]|r Leave combat, then use /affxiv restore.")
        return
    end

    local data = ConsolePort:GetData()
    local specID = currentSpec(data)
    ConsolePortSettings = ConsolePortSettings or {}
    for key in pairs(changedSettings) do ConsolePortSettings[key] = backup.settings[key] end
    loadBindings(data, specID, backup.bindings or {})
    if backup.bar then ConsolePortBar:OnLoad(copy(backup.bar), true) end
    if ConsolePort.UpdateMouseDriver then ConsolePort:UpdateMouseDriver() end

    AzerothFFXIVControllerDB.generation = AZEROTH_FFXIV_PRESET_GENERATION or "packaged"
    AzerothFFXIVControllerDB.restored = true
    print("|cff6ee7a8[Azeroth FFXIV]|r Previous ConsolePort settings restored for this character.")
end

SLASH_AZEROTHFFXIV1 = "/affxiv"
SlashCmdList.AZEROTHFFXIV = function(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    if command == "apply" then
        applyPreset(true)
    elseif command == "restore" then
        restorePreset()
    else
        local state = AzerothFFXIVControllerDB and AzerothFFXIVControllerDB.restored and "restored" or "active"
        print("|cffe6ac52[Azeroth FFXIV]|r " .. state .. " — L2/R2: skills, L1: target, L1+D-pad: zoom, X: map, A: interact, Y: jump, B: back.")
        print("|cffe6ac52[Azeroth FFXIV]|r Commands: /affxiv apply · /affxiv restore")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self.started = GetTime()
    self:SetScript("OnUpdate", function(frame)
        if GetTime() - frame.started < 1 then return end
        frame:SetScript("OnUpdate", nil)
        applyPreset(false)
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
