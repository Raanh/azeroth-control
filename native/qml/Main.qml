import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: root
    visible: true
    width: 1920
    height: 1080
    color: "#091017"
    title: "Azeroth Control"

    property real s: Math.max(0.8, Math.min(width / 1920, height / 1080))
    property color gold: "#e6a126"
    property color panel: "#101a23"
    property color raised: "#15222d"
    property color edge: "#2c3b47"
    property color ink: "#f4f0e7"
    property color muted: "#93a1ae"
    property string page: "dashboard"
    property string installClientPath: "/home/deck/Games/AzerothCore-WotLK-HD"
    property string firstAccount: ""
    property string firstPassword: ""
    property var installProfiles: [
        {"id":"progression", "name":"Progressive Level 1–80"},
        {"id":"endgame", "name":"Instant Level 80"},
        {"id":"custom", "name":"Custom Realm"}
    ]
    property bool queueLfg: true
    property bool queueBg: true
    property bool autoQueueBg: false
    property bool dynamicBrackets: true
    property bool syncFactions: true
    property string partyLeader: ""
    property var openGamepadCombo: null
    property int openGamepadComboInitialIndex: -1
    property var openGamepadSelect: null
    property var deleteInstallationTarget: null
    property var partyRoles: ["Tank", "Healer", "DPS"]
    property var partyClasses: [
        {"id":1,"name":"Warrior","specs":[{"id":0,"name":"Arms","role":"DPS"},{"id":1,"name":"Fury","role":"DPS"},{"id":2,"name":"Protection","role":"Tank"}]},
        {"id":2,"name":"Paladin","specs":[{"id":0,"name":"Holy","role":"Healer"},{"id":1,"name":"Protection","role":"Tank"},{"id":2,"name":"Retribution","role":"DPS"}]},
        {"id":3,"name":"Hunter","specs":[{"id":0,"name":"Beast Mastery","role":"DPS"},{"id":1,"name":"Marksmanship","role":"DPS"},{"id":2,"name":"Survival","role":"DPS"}]},
        {"id":4,"name":"Rogue","specs":[{"id":0,"name":"Assassination","role":"DPS"},{"id":1,"name":"Combat","role":"DPS"},{"id":2,"name":"Subtlety","role":"DPS"}]},
        {"id":5,"name":"Priest","specs":[{"id":0,"name":"Discipline","role":"Healer"},{"id":1,"name":"Holy","role":"Healer"},{"id":2,"name":"Shadow","role":"DPS"}]},
        {"id":6,"name":"Death Knight","specs":[{"id":0,"name":"Blood","role":"Tank"},{"id":1,"name":"Frost","role":"DPS"},{"id":2,"name":"Unholy","role":"DPS"}]},
        {"id":7,"name":"Shaman","specs":[{"id":0,"name":"Elemental","role":"DPS"},{"id":1,"name":"Enhancement","role":"DPS"},{"id":2,"name":"Restoration","role":"Healer"}]},
        {"id":8,"name":"Mage","specs":[{"id":0,"name":"Arcane","role":"DPS"},{"id":1,"name":"Fire","role":"DPS"},{"id":2,"name":"Frost","role":"DPS"}]},
        {"id":9,"name":"Warlock","specs":[{"id":0,"name":"Affliction","role":"DPS"},{"id":1,"name":"Demonology","role":"DPS"},{"id":2,"name":"Destruction","role":"DPS"}]},
        {"id":11,"name":"Druid","specs":[{"id":0,"name":"Balance","role":"DPS"},{"id":1,"name":"Feral Tank","role":"Tank"},{"id":2,"name":"Restoration","role":"Healer"},{"id":3,"name":"Feral DPS","role":"DPS"}]}
    ]
    property var partySlots: [
        {"role":"Tank","classId":1,"specId":2},
        {"role":"Healer","classId":5,"specId":1},
        {"role":"DPS","classId":8,"specId":2},
        {"role":"DPS","classId":4,"specId":1}
    ]

    onPageChanged: {
        if (control.installations.length === 0 && page !== "install")
            page = "install"
    }

    function showFirstTimeSetup() {
        if (control.installations.length !== 0)
            return
        root.page = "install"
        Qt.callLater(function() { installProfile.forceActiveFocus() })
    }

    function classesForRole(role) {
        var result = []
        for (var i = 0; i < partyClasses.length; ++i) {
            var specs = partyClasses[i].specs
            for (var j = 0; j < specs.length; ++j) {
                if (specs[j].role === role) { result.push(partyClasses[i]); break }
            }
        }
        return result
    }

    function specsFor(classId, role) {
        for (var i = 0; i < partyClasses.length; ++i) {
            if (partyClasses[i].id !== classId) continue
            var result = []
            for (var j = 0; j < partyClasses[i].specs.length; ++j)
                if (partyClasses[i].specs[j].role === role) result.push(partyClasses[i].specs[j])
            return result
        }
        return []
    }

    function modelIndexById(model, id) {
        for (var i = 0; i < model.length; ++i) if (model[i].id === id) return i
        return 0
    }

    function setPartyRole(index, role) {
        var classes = classesForRole(role)
        if (!classes.length) return
        var specs = specsFor(classes[0].id, role)
        var next = partySlots.slice()
        next[index] = {"role":role,"classId":classes[0].id,"specId":specs[0].id}
        partySlots = next
    }

    function setPartyClass(index, classId) {
        var slot = partySlots[index]
        var specs = specsFor(classId, slot.role)
        var next = partySlots.slice()
        next[index] = {"role":slot.role,"classId":classId,"specId":specs[0].id}
        partySlots = next
    }

    function setPartySpec(index, specId) {
        var slot = partySlots[index]
        var next = partySlots.slice()
        next[index] = {"role":slot.role,"classId":slot.classId,"specId":specId}
        partySlots = next
    }

    function commitGamepadCombo(combo) {
        if (!combo || combo.currentIndex < 0)
            return
        if (combo.selectionKind === "leader") {
            if (combo.currentIndex < combo.selectionChoices.length)
                root.partyLeader = combo.selectionChoices[combo.currentIndex].name
        } else if (combo.selectionKind === "role") {
            root.setPartyRole(combo.selectionSlot, combo.currentText)
        } else if (combo.selectionKind === "class") {
            if (combo.selectionChoices[combo.currentIndex])
                root.setPartyClass(combo.selectionSlot, combo.selectionChoices[combo.currentIndex].id)
        } else if (combo.selectionKind === "spec") {
            if (combo.selectionChoices[combo.currentIndex])
                root.setPartySpec(combo.selectionSlot, combo.selectionChoices[combo.currentIndex].id)
        } else if (typeof combo.activated === "function") {
            combo.activated(combo.currentIndex)
        }
    }

    function beginComboSelection(combo) {
        root.openGamepadCombo = combo
        root.openGamepadComboInitialIndex = combo.currentIndex
    }

    function finishComboSelection(combo) {
        if (root.openGamepadCombo !== combo)
            return
        root.openGamepadCombo = null
        root.openGamepadComboInitialIndex = -1
        root.commitGamepadCombo(combo)
    }

    function collectGamepadControls(node, result) {
        if (!node || node.visible === false)
            return
        var children = node.children || []
        for (var i = 0; i < children.length; ++i) {
            var child = children[i]
            if (!child || child.visible === false || child.enabled === false)
                continue
            if (child.focusPolicy !== undefined && child.focusPolicy !== Qt.NoFocus
                    && child.width > 0 && child.height > 0 && typeof child.forceActiveFocus === "function")
                result.push(child)
            collectGamepadControls(child, result)
        }
    }

    function gamepadControls() {
        var result = []
        collectGamepadControls(root.contentItem, result)
        return result
    }

    function moveGamepadFocus(direction) {
        var current = root.activeFocusItem
        if (current && (direction === "left" || direction === "right")
                && current.value !== undefined && current.from !== undefined && current.to !== undefined) {
            var step = current.stepSize > 0 ? current.stepSize : (current.to - current.from) / 20
            current.value = Math.max(current.from, Math.min(current.to, current.value + (direction === "left" ? -step : step)))
            return
        }
        var controls = gamepadControls()
        if (controls.length === 0)
            return
        if (!current || controls.indexOf(current) < 0) {
            controls[0].forceActiveFocus()
            return
        }
        var origin = current.mapToItem(root.contentItem, current.width / 2, current.height / 2)
        var best = null
        var bestScore = Number.MAX_VALUE
        for (var i = 0; i < controls.length; ++i) {
            var candidate = controls[i]
            if (candidate === current)
                continue
            var point = candidate.mapToItem(root.contentItem, candidate.width / 2, candidate.height / 2)
            var dx = point.x - origin.x
            var dy = point.y - origin.y
            var primary = direction === "left" ? -dx : direction === "right" ? dx : direction === "up" ? -dy : dy
            if (primary <= 2)
                continue
            var perpendicular = direction === "left" || direction === "right" ? Math.abs(dy) : Math.abs(dx)
            var score = primary + perpendicular * 2.5
            if (score < bestScore) {
                bestScore = score
                best = candidate
            }
        }
        if (best)
            best.forceActiveFocus()
    }

    function handleGamepad(command) {
        if (command === "page-up") command = "up"
        if (command === "page-down") command = "down"

        if (root.openGamepadSelect) {
            if (!root.openGamepadSelect.menuOpen) {
                root.openGamepadSelect = null
            } else if (command === "back") {
                root.openGamepadSelect.cancelSelection()
                root.openGamepadSelect = null
                return
            } else if (command === "activate") {
                root.openGamepadSelect.acceptSelection()
                root.openGamepadSelect = null
                return
            } else if (command === "up" || command === "down") {
                root.openGamepadSelect.moveSelection(command === "up" ? -1 : 1)
                return
            } else {
                return
            }
        }

        if (root.openGamepadCombo && (!root.openGamepadCombo.popup || !root.openGamepadCombo.popup.visible)) {
            var externallyClosedCombo = root.openGamepadCombo
            root.openGamepadCombo = null
            root.openGamepadComboInitialIndex = -1
            root.commitGamepadCombo(externallyClosedCombo)
            if (command === "activate" || command === "back")
                return
        }

        if (root.openGamepadCombo) {
            if (command === "back" || command === "activate") {
                var completedCombo = root.openGamepadCombo
                if (command === "back" && root.openGamepadComboInitialIndex >= 0) {
                    for (var restoreStep = 0; restoreStep < completedCombo.count && completedCombo.currentIndex !== root.openGamepadComboInitialIndex; ++restoreStep)
                        completedCombo.incrementCurrentIndex()
                }
                root.openGamepadCombo.popup.close()
                completedCombo.forceActiveFocus()
                root.openGamepadCombo = null
                root.openGamepadComboInitialIndex = -1
                if (command === "activate" && completedCombo.currentIndex >= 0)
                    root.commitGamepadCombo(completedCombo)
            } else if ((command === "up" || command === "down") && root.openGamepadCombo.count > 0) {
                var delta = command === "up" ? -1 : 1
                if (delta < 0)
                    root.openGamepadCombo.decrementCurrentIndex()
                else
                    root.openGamepadCombo.incrementCurrentIndex()
            }
            return
        }

        if (command === "back") {
            if (control.installations.length === 0) {
                root.showFirstTimeSetup()
                return
            }
            if (root.page !== "dashboard") {
                root.page = "dashboard"
                dashboardButton.forceActiveFocus()
            }
            return
        }
        if (command === "activate") {
            var item = root.activeFocusItem
            if (item && item.isGamepadSelect === true) {
                root.openGamepadSelect = item
                item.openMenu()
            } else if (item && item.popup !== undefined && item.currentIndex !== undefined) {
                root.openGamepadCombo = item
                root.openGamepadComboInitialIndex = item.currentIndex
                item.popup.open()
            } else if (item && typeof item.click === "function")
                item.click()
            else if (item && typeof item.toggle === "function")
                item.toggle()
            return
        }
        if (command === "up" || command === "down" || command === "left" || command === "right")
            moveGamepadFocus(command)
    }

    palette {
        window: "#101a23"
        windowText: "#f4f0e7"
        text: "#f4f0e7"
        button: "#15222d"
        buttonText: "#f4f0e7"
        base: "#0d171f"
        alternateBase: "#15222d"
        highlight: "#e6a126"
        highlightedText: "#111820"
        placeholderText: "#7f8d99"
    }

    Rectangle {
        anchors.fill: parent
        z: -100
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0d1822" }
            GradientStop { position: 0.58; color: "#09131b" }
            GradientStop { position: 1.0; color: "#060c11" }
        }
    }

    Rectangle {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: control.installations.length > 0 ? 315 * root.s : 0
        visible: control.installations.length > 0
        color: "#070d12"
        border.color: "#17232c"

        Rectangle {
            x: 28 * root.s
            y: 28 * root.s
            width: 56 * root.s
            height: 56 * root.s
            radius: 14 * root.s
            color: "#241c0b"
            border.color: root.gold
            Text { anchors.centerIn: parent; text: "A"; color: root.gold; font.pixelSize: 29 * root.s; font.bold: true }
        }
        Text { x: 98 * root.s; y: 31 * root.s; text: "Azeroth"; color: root.ink; font.pixelSize: 24 * root.s; font.bold: true }
        Text { x: 98 * root.s; y: 63 * root.s; text: "Control · Native"; color: root.muted; font.pixelSize: 14 * root.s }

        AzButton {
            id: dashboardButton
            x: 26 * root.s; y: 145 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "⌂   Dashboard"; font.pixelSize: 19 * root.s
            highlighted: root.page === "dashboard"
            onClicked: { root.page = "dashboard"; forceActiveFocus() }
            KeyNavigation.down: realmsButton
        }
        AzButton {
            id: realmsButton
            x: 26 * root.s; y: 217 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "◇   Realms"; font.pixelSize: 19 * root.s
            highlighted: root.page === "realms" || root.page === "install"
            onClicked: { root.page = "realms"; control.reloadInstallations() }
            KeyNavigation.up: dashboardButton; KeyNavigation.down: botsButton
        }
        AzButton {
            id: botsButton
            x: 26 * root.s; y: 289 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "♟   Bots"; font.pixelSize: 19 * root.s
            highlighted: root.page === "bots"
            onClicked: root.page = "bots"
            KeyNavigation.up: realmsButton; KeyNavigation.down: queuesButton
        }
        AzButton {
            id: worldButton
            x: 26 * root.s; y: 505 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "◎   World Settings"; font.pixelSize: 19 * root.s
            highlighted: root.page === "world"
            onClicked: { root.page = "world"; control.loadSettings(control.activeRealm) }
            KeyNavigation.up: partyButton; KeyNavigation.down: addonsButton
        }
        AzButton {
            id: queuesButton
            x: 26 * root.s; y: 361 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "⇄   Queues"; font.pixelSize: 19 * root.s
            highlighted: root.page === "queues"
            onClicked: { root.page = "queues"; control.loadSettings(control.activeRealm) }
            KeyNavigation.up: botsButton; KeyNavigation.down: partyButton
        }
        AzButton {
            id: partyButton
            x: 26 * root.s; y: 433 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "♜   Party Builder"; font.pixelSize: 19 * root.s
            highlighted: root.page === "party"
            onClicked: { root.page = "party"; control.apiGet("party", "/api/party") }
            KeyNavigation.up: queuesButton; KeyNavigation.down: worldButton
        }
        AzButton {
            id: addonsButton
            x: 26 * root.s; y: 577 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "✚   Addons"; font.pixelSize: 19 * root.s
            highlighted: root.page === "addons"
            onClicked: {
                root.page = "addons"
                if (control.installations.length > 0)
                    control.apiGet("addons", "/api/addons")
            }
            KeyNavigation.up: worldButton; KeyNavigation.down: logsButton
        }
        AzButton {
            id: logsButton
            x: 26 * root.s; y: 649 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "≡   Logs"; font.pixelSize: 19 * root.s
            highlighted: root.page === "logs"
            onClicked: { root.page = "logs"; control.apiGet("logs", "/api/logs?lines=220") }
            KeyNavigation.up: addonsButton; KeyNavigation.down: maintenanceButton
        }
        AzButton {
            id: maintenanceButton
            x: 26 * root.s; y: 721 * root.s; width: 260 * root.s; height: 62 * root.s
            text: "▣   Updates & Backups"; font.pixelSize: 19 * root.s
            highlighted: root.page === "maintenance"
            onClicked: { root.page = "maintenance"; control.apiGet("backups", "/api/backups") }
            KeyNavigation.up: logsButton
        }
        Text {
            anchors.left: parent.left; anchors.leftMargin: 28 * root.s
            anchors.bottom: parent.bottom; anchors.bottomMargin: 24 * root.s
            text: control.version; color: "#60717f"; font.pixelSize: 14 * root.s
        }
    }

    Item {
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Text { x: 48 * root.s; y: 38 * root.s; text: "STEAMOS · LOCAL SERVER"; color: root.muted; font.pixelSize: 16 * root.s; font.letterSpacing: 2 }
        Text { x: 48 * root.s; y: 68 * root.s; text: control.installations.length === 0 ? "Welcome" : root.page === "dashboard" ? "Dashboard" : root.page.charAt(0).toUpperCase() + root.page.slice(1); color: root.ink; font.pixelSize: 42 * root.s; font.bold: true }

        Rectangle {
            id: card
            visible: root.page === "dashboard"
            x: 48 * root.s; y: 145 * root.s
            width: parent.width - 96 * root.s; height: parent.height - 190 * root.s
            radius: 18 * root.s; color: root.panel; border.color: root.edge

            Text { x: 36 * root.s; y: 30 * root.s; text: control.realmName; color: root.ink; font.pixelSize: 31 * root.s; font.bold: true }
            Text {
                x: 36 * root.s; y: 72 * root.s
                text: control.serverState === "online" ? "ONLINE · " + control.uptime : "OFFLINE"
                color: control.serverState === "online" ? "#58d38c" : "#ef6f6f"
                font.pixelSize: 17 * root.s; font.bold: true
            }
            BusyIndicator { anchors.right: parent.right; anchors.rightMargin: 36 * root.s; y: 35 * root.s; running: control.busy; visible: running }

            property real statGap: 16 * root.s
            property real statWidth: (width - 72 * root.s - statGap * 3) / 4

            Repeater {
                model: [
                    {"label":"BOTS ONLINE", "value":String(control.bots)},
                    {"label":"CPU", "value":String(control.cpu)},
                    {"label":"MEMORY", "value":String(control.memory)},
                    {"label":"ACTIVE REALM", "value":String(control.activeRealm)}
                ]
                delegate: Rectangle {
                    x: 36 * root.s + index * (card.statWidth + card.statGap)
                    y: 125 * root.s; width: card.statWidth; height: 130 * root.s
                    radius: 12 * root.s; color: root.raised; border.color: root.edge
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 28 * root.s; text: modelData.label; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 60 * root.s; text: modelData.value; color: root.ink; font.pixelSize: 25 * root.s; font.bold: true; elide: Text.ElideRight; width: parent.width - 30 * root.s; horizontalAlignment: Text.AlignHCenter }
                }
            }

            Rectangle {
                x: 36 * root.s; y: 280 * root.s
                width: (parent.width - 88 * root.s) / 2; height: 236 * root.s
                radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                Text { x: 24 * root.s; y: 20 * root.s; text: "SERVER CONTROLS"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.5 }
                Text { x: 24 * root.s; y: 52 * root.s; text: control.serverState === "online" ? "Realm is ready to play" : "Start your local realm"; color: root.ink; font.pixelSize: 23 * root.s; font.bold: true }
                AzButton { id: startButton; x: 24 * root.s; y: 103 * root.s; width: (parent.width - 62 * root.s) / 2; height: 54 * root.s; text: "Start"; primary: control.serverState !== "online"; font.pixelSize: 17 * root.s; enabled: !control.busy; onClicked: control.serverAction("start", control.activeRealm); KeyNavigation.up: dashboardButton; KeyNavigation.right: restartButton }
                AzButton { id: restartButton; anchors.right: parent.right; anchors.rightMargin: 24 * root.s; y: 103 * root.s; width: (parent.width - 62 * root.s) / 2; height: 54 * root.s; text: "Restart"; font.pixelSize: 17 * root.s; enabled: !control.busy; onClicked: control.serverAction("restart", control.activeRealm); KeyNavigation.left: startButton; KeyNavigation.right: stopButton }
                AzButton { id: stopButton; x: 24 * root.s; y: 169 * root.s; width: (parent.width - 62 * root.s) / 2; height: 44 * root.s; text: "Stop server"; danger: true; font.pixelSize: 16 * root.s; enabled: !control.busy; onClicked: control.serverAction("stop", control.activeRealm); KeyNavigation.left: restartButton; KeyNavigation.right: refreshButton }
                AzButton { id: refreshButton; anchors.right: parent.right; anchors.rightMargin: 24 * root.s; y: 169 * root.s; width: (parent.width - 62 * root.s) / 2; height: 44 * root.s; text: "Refresh status"; font.pixelSize: 16 * root.s; onClicked: control.refresh(); KeyNavigation.left: stopButton; KeyNavigation.right: dashboardPartyButton }
            }

            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 36 * root.s; y: 280 * root.s
                width: (parent.width - 88 * root.s) / 2; height: 236 * root.s
                radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                Text { x: 24 * root.s; y: 20 * root.s; text: "QUICK CONTROLS"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.5 }
                Text { x: 24 * root.s; y: 52 * root.s; text: "Prepare your next session"; color: root.ink; font.pixelSize: 23 * root.s; font.bold: true }
                AzButton { id: dashboardPartyButton; x: 24 * root.s; y: 103 * root.s; width: parent.width - 48 * root.s; height: 54 * root.s; text: "♜  Build & Summon Party"; primary: true; font.pixelSize: 17 * root.s; onClicked: { root.page = "party"; control.apiGet("party", "/api/party") } KeyNavigation.left: refreshButton; KeyNavigation.down: dashboardQueueButton }
                AzButton { id: dashboardQueueButton; x: 24 * root.s; y: 169 * root.s; width: (parent.width - 62 * root.s) / 2; height: 44 * root.s; text: "⇄  Queues"; font.pixelSize: 16 * root.s; onClicked: { root.page = "queues"; control.loadSettings(control.activeRealm) } KeyNavigation.up: dashboardPartyButton; KeyNavigation.right: dashboardWorldButton }
                AzButton { id: dashboardWorldButton; anchors.right: parent.right; anchors.rightMargin: 24 * root.s; y: 169 * root.s; width: (parent.width - 62 * root.s) / 2; height: 44 * root.s; text: "◎  World settings"; font.pixelSize: 16 * root.s; onClicked: { root.page = "world"; control.loadSettings(control.activeRealm) } KeyNavigation.left: dashboardQueueButton; KeyNavigation.up: dashboardPartyButton }
            }

            Rectangle {
                x: 36 * root.s; y: 536 * root.s; width: parent.width - 72 * root.s; height: 92 * root.s
                radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                Text { x: 24 * root.s; y: 17 * root.s; text: "OFFLINE SINGLE-PLAYER"; color: root.gold; font.pixelSize: 14 * root.s; font.bold: true; font.letterSpacing: 1.2 }
                Text { x: 24 * root.s; y: 46 * root.s; text: "Start the realm here, then launch your own WoW Steam shortcut. Azeroth Control never launches or takes focus from the game."; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap; width: parent.width - 48 * root.s }
            }

            Rectangle {
                x: 36 * root.s; y: 648 * root.s
                width: parent.width - 72 * root.s
                height: control.notice.length > 0 ? 82 * root.s : 0
                visible: control.notice.length > 0
                clip: true; radius: 10 * root.s; color: "#261f13"; border.color: "#6f5424"
                Text { anchors.fill: parent; anchors.margins: 18 * root.s; text: control.notice; color: "#e8c57f"; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
            }
        }

        Rectangle {
            id: pagePanel
            visible: root.page !== "dashboard"
            x: 48 * root.s; y: 145 * root.s
            width: parent.width - 96 * root.s; height: parent.height - 190 * root.s
            radius: 18 * root.s; color: root.panel; border.color: root.edge

            Text { x: 36 * root.s; y: 30 * root.s; text: root.page === "install" ? (control.installations.length === 0 ? "First-Time Setup" : "New Server Setup") : root.page === "realms" ? "Realm Controls" : root.page === "bots" ? "Bot Population" : root.page === "queues" ? "Queues" : root.page === "party" ? "Party Builder" : root.page === "world" ? "World Settings" : root.page === "addons" ? "Addons" : root.page === "logs" ? "Logs" : "Updates & Backups"; color: root.ink; font.pixelSize: 31 * root.s; font.bold: true }

            Item {
                x: 36 * root.s; y: 92 * root.s; width: parent.width - 72 * root.s; height: parent.height - 122 * root.s
                visible: root.page === "realms"
                property real leftWidth: width * 0.64

                Rectangle {
                    x: 0; y: 0; width: parent.leftWidth; height: parent.height
                    radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                    Text { x: 24 * root.s; y: 22 * root.s; text: "ACTIVE REALM"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.4 }
                    Text { x: 24 * root.s; y: 55 * root.s; text: control.realmName; color: root.ink; font.pixelSize: 27 * root.s; font.bold: true }
                    Text { x: 24 * root.s; y: 96 * root.s; text: control.serverState === "online" ? "●  ONLINE · " + control.uptime : "●  OFFLINE"; color: control.serverState === "online" ? "#58d38c" : "#ef6f6f"; font.pixelSize: 16 * root.s; font.bold: true }

                    Rectangle {
                        x: 24 * root.s; y: 140 * root.s; width: parent.width - 48 * root.s; height: 122 * root.s
                        radius: 10 * root.s; color: root.raised; border.color: root.edge
                        Text { x: 18 * root.s; y: 18 * root.s; text: "PROFILE"; color: root.muted; font.pixelSize: 13 * root.s }
                        Text { x: 18 * root.s; y: 48 * root.s; text: control.activeRealm; color: root.ink; font.pixelSize: 23 * root.s; font.bold: true }
                        Text { anchors.right: parent.right; anchors.rightMargin: 18 * root.s; y: 48 * root.s; text: control.bots + " bots online"; color: root.gold; font.pixelSize: 18 * root.s }
                    }

                    Text { x: 24 * root.s; y: 292 * root.s; text: "AVAILABLE PROFILES"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.3 }
                    Flow {
                        x: 24 * root.s; y: 326 * root.s; width: parent.width - 48 * root.s; spacing: 12 * root.s
                        Repeater {
                            model: control.availableRealms
                            delegate: AzButton { text: modelData; width: 190 * root.s; height: 54 * root.s; font.pixelSize: 17 * root.s; highlighted: modelData === control.activeRealm; onClicked: control.serverAction("start", modelData) }
                        }
                    }

                    Row {
                        x: 24 * root.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 24 * root.s; spacing: 12 * root.s
                        AzButton { id: realmStart; text: "Start realm"; primary: control.serverState !== "online"; width: 180 * root.s; height: 58 * root.s; font.pixelSize: 17 * root.s; enabled: !control.busy; onClicked: control.serverAction("start", control.activeRealm); KeyNavigation.right: realmRestart }
                        AzButton { id: realmRestart; text: "Restart realm"; width: 190 * root.s; height: 58 * root.s; font.pixelSize: 17 * root.s; enabled: !control.busy; onClicked: control.serverAction("restart", control.activeRealm); KeyNavigation.left: realmStart; KeyNavigation.right: realmStop }
                        AzButton { id: realmStop; text: "Stop server"; danger: true; width: 180 * root.s; height: 58 * root.s; font.pixelSize: 17 * root.s; enabled: !control.busy; onClicked: control.serverAction("stop", control.activeRealm); KeyNavigation.left: realmRestart }
                    }
                }

                Rectangle {
                    anchors.right: parent.right; y: 0; width: parent.width - parent.leftWidth - 16 * root.s; height: parent.height
                    radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                    Text { x: 24 * root.s; y: 22 * root.s; text: "LOCAL SERVER"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.4 }
                    Text { x: 24 * root.s; y: 55 * root.s; text: "Realm management"; color: root.ink; font.pixelSize: 25 * root.s; font.bold: true }
                    Text { x: 24 * root.s; y: 100 * root.s; width: parent.width - 48 * root.s; text: "Each realm has its own world, characters, bot population and progression. Only one local realm runs at a time."; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap }

                    Rectangle {
                        x: 24 * root.s; y: 198 * root.s; width: parent.width - 48 * root.s; height: 160 * root.s
                        radius: 10 * root.s; color: root.raised; border.color: root.edge
                        Text { x: 18 * root.s; y: 17 * root.s; text: "CREATE ANOTHER REALM"; color: root.gold; font.pixelSize: 14 * root.s; font.bold: true }
                        Text { x: 18 * root.s; y: 49 * root.s; width: parent.width - 36 * root.s; text: "Install a progression, endgame or custom profile with guided disk and bot recommendations."; color: root.muted; font.pixelSize: 16 * root.s; wrapMode: Text.Wrap }
                        AzButton { anchors.left: parent.left; anchors.leftMargin: 18 * root.s; anchors.right: parent.right; anchors.rightMargin: 18 * root.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 16 * root.s; height: 52 * root.s; text: "＋  Create a new server"; primary: true; font.pixelSize: 17 * root.s; onClicked: root.page = "install"; KeyNavigation.left: realmStart }
                    }

                    Text { x: 24 * root.s; y: 390 * root.s; text: "INSTALLED SERVERS"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.4 }
                    ListView {
                        x: 24 * root.s; y: 420 * root.s; width: parent.width - 48 * root.s; height: parent.height - 440 * root.s
                        spacing: 8 * root.s; clip: true; model: control.installations
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width; height: 64 * root.s; radius: 8 * root.s; color: root.raised; border.color: root.edge
                            Text { x: 14 * root.s; y: 9 * root.s; width: parent.width - 150 * root.s; text: modelData.name || "Azeroth Server"; color: root.ink; font.pixelSize: 16 * root.s; font.bold: true; elide: Text.ElideRight }
                            Text { x: 14 * root.s; y: 36 * root.s; width: parent.width - 150 * root.s; text: modelData.imported ? "Imported · files protected" : "Managed server"; color: root.muted; font.pixelSize: 13 * root.s }
                            AzButton { anchors.right: parent.right; anchors.rightMargin: 8 * root.s; anchors.verticalCenter: parent.verticalCenter; width: 112 * root.s; height: 46 * root.s; text: modelData.imported ? "Forget" : "Remove"; danger: true; font.pixelSize: 14 * root.s; onClicked: root.deleteInstallationTarget = modelData }
                        }
                    }
                }
            }

            Column {
                x: 36 * root.s; y: 100 * root.s; width: parent.width - 72 * root.s; spacing: 22 * root.s
                visible: root.page === "bots"
                Text { text: "Configured random bots: " + Math.round(botSlider.value); color: root.ink; font.pixelSize: 24 * root.s }
                Slider { id: botSlider; width: 720 * root.s; from: 0; to: 2000; stepSize: 50; value: control.configuredBots; live: true; KeyNavigation.down: botSave }
                Text { text: "Recommended for this Steam Machine: 500–1000 bots. Changes apply after realm restart."; color: root.muted; font.pixelSize: 18 * root.s; wrapMode: Text.Wrap }
                AzButton { id: botSave; text: "Save bot count"; primary: true; width: 220 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; enabled: !control.busy; onClicked: control.saveSettings({"botCount": Math.round(botSlider.value)}, control.activeRealm); KeyNavigation.up: botSlider }
            }

            Column {
                x: 36 * root.s; y: 100 * root.s; width: parent.width - 72 * root.s; spacing: 18 * root.s
                visible: root.page === "install"
                Text { text: control.installations.length === 0 ? "Welcome — create your first local realm" : "Create a new local server"; color: root.ink; font.pixelSize: 24 * root.s }
                Text { visible: control.installations.length === 0; width: 980 * root.s; text: "Choose a realm profile and point Azeroth Control to your own WoW 3.3.5a client. Server and addon controls unlock when setup finishes."; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap }
                Text { text: "Profile"; color: root.muted; font.pixelSize: 17 * root.s }
                AzSelect {
                    id: installProfile
                    width: 430 * root.s; height: 58 * root.s
                    choices: root.installProfiles; selectedIndex: 0; font.pixelSize: 18 * root.s
                    onSelectionAccepted: function(index) { selectedIndex = index }
                }
                Text { text: "WoW 3.3.5a client folder"; color: root.muted; font.pixelSize: 17 * root.s }
                TextField { id: installClient; width: 800 * root.s; height: 58 * root.s; text: root.installClientPath; font.pixelSize: 17 * root.s; selectByMouse: true }
                Row { spacing: 14 * root.s
                    TextField { id: accountField; width: 260 * root.s; height: 54 * root.s; placeholderText: "First account (optional)"; text: root.firstAccount; font.pixelSize: 16 * root.s; onTextChanged: root.firstAccount = text }
                    TextField { id: passwordField; width: 260 * root.s; height: 54 * root.s; placeholderText: "Password"; echoMode: TextInput.Password; text: root.firstPassword; font.pixelSize: 16 * root.s; onTextChanged: root.firstPassword = text }
                }
                Text { text: "Bot count: " + Math.round(installBots.value); color: root.ink; font.pixelSize: 22 * root.s }
                Slider { id: installBots; width: 720 * root.s; from: 0; to: 2000; stepSize: 50; value: 500; live: true; KeyNavigation.down: installButton }
                Text { text: "The installer estimates disk usage and creates the managed containers. WoW files are never downloaded or added to Steam."; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap }
                Row { spacing: 12 * root.s
                    AzButton { id: installButton; text: control.installRunning ? "Installing…" : "Start / Resume installation"; primary: true; width: 290 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; enabled: !control.installRunning && !control.busy; onClicked: { var chosenProfile = root.installProfiles[installProfile.selectedIndex]; control.installServer({"profile": chosenProfile.id, "clientPath": installClient.text, "bots": Math.round(installBots.value), "installRoot": "/home/deck/.local/share/azeroth-control", "serverName": "Azeroth " + chosenProfile.name, "accountName": root.firstAccount, "accountPassword": root.firstPassword}) } KeyNavigation.up: installBots; KeyNavigation.right: pauseInstallButton }
                    AzButton { id: pauseInstallButton; text: control.installPaused ? "Resume" : "Pause"; width: 150 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; visible: control.installRunning; onClicked: control.pauseInstallation(); KeyNavigation.left: installButton; KeyNavigation.right: cancelInstallButton }
                    AzButton { id: cancelInstallButton; text: "Cancel"; danger: true; width: 150 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; visible: control.installRunning; onClicked: control.cancelInstallation(); KeyNavigation.left: pauseInstallButton }
                }
                ProgressBar { width: 800 * root.s; from: 0; to: 100; value: control.installProgress; visible: control.installRunning || control.installProgress > 0 }
                Text { text: control.installMessage; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap; visible: control.installMessage.length > 0 }
            }

            Column {
                x: 36 * root.s; y: 100 * root.s; width: parent.width - 72 * root.s; spacing: 18 * root.s
                visible: root.page === "world"
                Text { text: "XP rate: " + xpSlider.value.toFixed(1) + "x"; color: root.ink; font.pixelSize: 22 * root.s }
                Slider { id: xpSlider; width: 720 * root.s; from: 0; to: 20; stepSize: 0.5; value: control.xpRate; live: true }
                Text { text: "Drop rate: " + dropSlider.value.toFixed(1) + "x"; color: root.ink; font.pixelSize: 22 * root.s }
                Slider { id: dropSlider; width: 720 * root.s; from: 0; to: 20; stepSize: 0.5; value: control.dropRate; live: true }
                Text { text: "Spawn rate: " + spawnSlider.value.toFixed(1) + "x"; color: root.ink; font.pixelSize: 22 * root.s }
                Slider { id: spawnSlider; width: 720 * root.s; from: 0.25; to: 20; stepSize: 0.25; value: control.spawnRate; live: true }
                AzButton { text: "Save world settings"; primary: true; width: 250 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; enabled: !control.busy; onClicked: control.saveSettings({"xpRate": Number(xpSlider.value), "dropRate": Number(dropSlider.value), "spawnRate": Number(spawnSlider.value)}, control.activeRealm) }
            }

            Column {
                x: 36 * root.s; y: 100 * root.s; spacing: 18 * root.s
                visible: root.page === "queues"
                Text { text: "Dungeon & Battleground queues"; color: root.ink; font.pixelSize: 24 * root.s }
                CheckBox { id: lfgCheck; text: "Join dungeon finder as a solo player"; checked: root.queueLfg; font.pixelSize: 18 * root.s; onToggled: root.queueLfg = checked }
                CheckBox { id: bgCheck; text: "Join battleground queue"; checked: root.queueBg; font.pixelSize: 18 * root.s; onToggled: root.queueBg = checked }
                CheckBox { id: autoBgCheck; text: "Auto-queue battlegrounds when available"; checked: root.autoQueueBg; font.pixelSize: 18 * root.s; onToggled: root.autoQueueBg = checked }
                CheckBox { id: dynamicCheck; text: "Use dynamic level brackets"; checked: root.dynamicBrackets; font.pixelSize: 18 * root.s; onToggled: root.dynamicBrackets = checked }
                CheckBox { id: factionCheck; text: "Synchronize bot factions"; checked: root.syncFactions; font.pixelSize: 18 * root.s; onToggled: root.syncFactions = checked }
                AzButton { text: "Save queue settings"; primary: true; width: 260 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; enabled: !control.busy; onClicked: control.saveSettings({"joinLfg": root.queueLfg, "joinBg": root.queueBg, "autoJoinBg": root.autoQueueBg, "dynamicBrackets": root.dynamicBrackets, "syncFactions": root.syncFactions}, control.activeRealm) }
                Text { text: "Bots are added to the queue by the PlayerBots module; party roles are selected in Party Builder."; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap; width: 820 * root.s }
            }

            Item {
                id: partyWorkspace
                x: 36 * root.s; y: 92 * root.s
                width: parent.width - 72 * root.s; height: parent.height - 122 * root.s
                visible: root.page === "party"
                property var partyInfo: control.data["/api/party"] || ({})
                property var onlinePlayers: partyInfo.players || []
                property real leftWidth: width * 0.64

                function selectFirstLeader() {
                    if (!root.partyLeader && onlinePlayers.length > 0)
                        root.partyLeader = onlinePlayers[0].name
                }

                onOnlinePlayersChanged: selectFirstLeader()
                Component.onCompleted: selectFirstLeader()

                Rectangle {
                    x: 0; y: 0; width: parent.width; height: 96 * root.s
                    radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                    Rectangle {
                        x: 20 * root.s; y: 18 * root.s; width: 60 * root.s; height: 60 * root.s
                        radius: 10 * root.s; color: root.partyLeader ? "#173b2d" : "#3b2b17"; border.color: root.partyLeader ? "#2d8d60" : "#8a6424"
                        Text { anchors.centerIn: parent; text: "YOU"; color: root.partyLeader ? "#7ce0aa" : root.gold; font.pixelSize: 15 * root.s; font.bold: true }
                    }
                    Text { x: 98 * root.s; y: 18 * root.s; text: "Party leader"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.2 }
                    Text { x: 98 * root.s; y: 47 * root.s; text: root.partyLeader || "No online character detected"; color: root.ink; font.pixelSize: 23 * root.s; font.bold: true }
                    ComboBox {
                        id: leaderCombo
                        property string selectionKind: "leader"
                        property var selectionChoices: partyWorkspace.onlinePlayers
                        anchors.right: parent.right; anchors.rightMargin: 22 * root.s; y: 21 * root.s
                        width: 360 * root.s; height: 56 * root.s
                        visible: partyWorkspace.onlinePlayers.length > 0
                        model: partyWorkspace.onlinePlayers; textRole: "name"; font.pixelSize: 17 * root.s
                        currentIndex: {
                            for (var i = 0; i < partyWorkspace.onlinePlayers.length; ++i)
                                if (partyWorkspace.onlinePlayers[i].name === root.partyLeader) return i
                            return 0
                        }
                        onActivated: root.commitGamepadCombo(leaderCombo)
                    }
                    Connections {
                        target: leaderCombo.popup
                        function onOpened() { root.beginComboSelection(leaderCombo) }
                        function onClosed() { root.finishComboSelection(leaderCombo) }
                    }
                    TextField {
                        anchors.right: parent.right; anchors.rightMargin: 22 * root.s; y: 21 * root.s
                        width: 360 * root.s; height: 56 * root.s
                        visible: partyWorkspace.onlinePlayers.length === 0
                        placeholderText: "Character name"; text: root.partyLeader; font.pixelSize: 17 * root.s
                        onTextChanged: root.partyLeader = text
                    }
                }

                Rectangle {
                    x: 0; y: 112 * root.s; width: partyWorkspace.leftWidth; height: parent.height - 112 * root.s
                    radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                    Text { x: 22 * root.s; y: 18 * root.s; text: "PARTY COMPOSITION"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.4 }
                    Text { x: 22 * root.s; y: 47 * root.s; text: "Choose a role, class and specialization"; color: root.ink; font.pixelSize: 21 * root.s; font.bold: true }

                    Column {
                        x: 22 * root.s; y: 86 * root.s; width: parent.width - 44 * root.s; spacing: 10 * root.s
                        Repeater {
                            model: 4
                            delegate: Rectangle {
                                required property int index
                                property int slotIndex: index
                                property var slot: root.partySlots[slotIndex]
                                width: parent.width; height: 84 * root.s; radius: 10 * root.s
                                color: slotIndex === 0 ? "#12263b" : slotIndex === 1 ? "#123127" : "#281b22"
                                border.color: slotIndex === 0 ? "#264e75" : slotIndex === 1 ? "#276345" : "#633441"
                                Rectangle {
                                    x: 12 * root.s; y: 18 * root.s; width: 48 * root.s; height: 48 * root.s; radius: 9 * root.s
                                    color: slotIndex === 0 ? "#19395b" : slotIndex === 1 ? "#174c35" : "#51252e"
                                    Text { anchors.centerIn: parent; text: String(slotIndex + 2); color: root.ink; font.pixelSize: 18 * root.s; font.bold: true }
                                }
                                AzSelect {
                                    id: roleBox
                                    x: 72 * root.s; y: 18 * root.s; width: 180 * root.s; height: 48 * root.s
                                    choices: root.partyRoles; textRole: ""; font.pixelSize: 16 * root.s
                                    selectedIndex: root.partyRoles.indexOf(parent.slot.role)
                                    onSelectionAccepted: function(selected) { root.setPartyRole(parent.slotIndex, root.partyRoles[selected]) }
                                    onMenuOpenChanged: {
                                        if (menuOpen) root.openGamepadSelect = roleBox
                                        else if (root.openGamepadSelect === roleBox) root.openGamepadSelect = null
                                    }
                                }
                                AzSelect {
                                    id: classBox
                                    choices: root.classesForRole(parent.slot.role)
                                    x: 264 * root.s; y: 18 * root.s; width: 230 * root.s; height: 48 * root.s
                                    textRole: "name"; font.pixelSize: 16 * root.s
                                    selectedIndex: root.modelIndexById(choices, parent.slot.classId)
                                    onSelectionAccepted: function(selected) { if (choices[selected]) root.setPartyClass(parent.slotIndex, choices[selected].id) }
                                    onMenuOpenChanged: {
                                        if (menuOpen) root.openGamepadSelect = classBox
                                        else if (root.openGamepadSelect === classBox) root.openGamepadSelect = null
                                    }
                                }
                                AzSelect {
                                    id: specBox
                                    choices: root.specsFor(parent.slot.classId, parent.slot.role)
                                    x: 506 * root.s; y: 18 * root.s; width: parent.width - x - 14 * root.s; height: 48 * root.s
                                    textRole: "name"; font.pixelSize: 16 * root.s
                                    selectedIndex: root.modelIndexById(choices, parent.slot.specId)
                                    onSelectionAccepted: function(selected) { if (choices[selected]) root.setPartySpec(parent.slotIndex, choices[selected].id) }
                                    onMenuOpenChanged: {
                                        if (menuOpen) root.openGamepadSelect = specBox
                                        else if (root.openGamepadSelect === specBox) root.openGamepadSelect = null
                                    }
                                }
                            }
                        }
                    }

                    AzButton {
                        id: buildButton
                        x: 22 * root.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 20 * root.s
                        width: parent.width - 44 * root.s; height: 62 * root.s
                        text: "♜  Build & Summon Party"; primary: true; font.pixelSize: 19 * root.s; font.bold: true
                        enabled: !control.busy && root.partyLeader.length > 0
                        onClicked: control.apiPost("party-build", "/api/party/build", {"leader": root.partyLeader, "slots": root.partySlots})
                        KeyNavigation.right: summonPartyButton
                    }
                }

                Rectangle {
                    anchors.right: parent.right; y: 112 * root.s
                    width: parent.width - partyWorkspace.leftWidth - 16 * root.s; height: parent.height - 112 * root.s
                    radius: 12 * root.s; color: "#0d171f"; border.color: root.edge
                    Text { x: 22 * root.s; y: 18 * root.s; text: "PARTY CONTROL"; color: root.muted; font.pixelSize: 14 * root.s; font.letterSpacing: 1.4 }
                    Text { x: 22 * root.s; y: 47 * root.s; text: "Quick recovery"; color: root.ink; font.pixelSize: 21 * root.s; font.bold: true }

                    Column {
                        x: 22 * root.s; y: 86 * root.s; width: parent.width - 44 * root.s; spacing: 10 * root.s
                        AzButton { id: summonPartyButton; width: parent.width; height: 54 * root.s; text: "Summon party"; primary: true; font.pixelSize: 17 * root.s; enabled: !control.busy && root.partyLeader.length > 0; onClicked: control.apiPost("party-action", "/api/party/action", {"leader": root.partyLeader, "action":"summon"}); KeyNavigation.left: buildButton; KeyNavigation.down: preparePartyButton }
                        AzButton { id: preparePartyButton; width: parent.width; height: 54 * root.s; text: "Level + Gear + Spells"; font.pixelSize: 17 * root.s; enabled: !control.busy && root.partyLeader.length > 0; onClicked: control.apiPost("party-action", "/api/party/action", {"leader": root.partyLeader, "action":"prepare"}); KeyNavigation.left: buildButton; KeyNavigation.up: summonPartyButton; KeyNavigation.down: recoverPartyButton }
                        AzButton { id: recoverPartyButton; width: parent.width; height: 54 * root.s; text: "Recover all"; font.pixelSize: 17 * root.s; enabled: !control.busy && root.partyLeader.length > 0; onClicked: control.apiPost("party-action", "/api/party/action", {"leader": root.partyLeader, "action":"recover"}); KeyNavigation.left: buildButton; KeyNavigation.up: preparePartyButton; KeyNavigation.down: disbandPartyButton }
                        AzButton { id: disbandPartyButton; width: parent.width; height: 54 * root.s; text: "Disband bots"; danger: true; font.pixelSize: 17 * root.s; enabled: !control.busy && root.partyLeader.length > 0; onClicked: control.apiPost("party-action", "/api/party/action", {"leader": root.partyLeader, "action":"disband"}); KeyNavigation.left: buildButton; KeyNavigation.up: recoverPartyButton }
                    }

                    Rectangle {
                        x: 22 * root.s; y: 334 * root.s; width: parent.width - 44 * root.s; height: 102 * root.s
                        radius: 9 * root.s; color: partyWorkspace.partyInfo.bridgeReady ? "#122b21" : "#2b2112"; border.color: partyWorkspace.partyInfo.bridgeReady ? "#286345" : "#705224"
                        Text { x: 16 * root.s; y: 15 * root.s; text: partyWorkspace.partyInfo.bridgeReady ? "●  BRIDGE READY" : "●  BRIDGE WAITING"; color: partyWorkspace.partyInfo.bridgeReady ? "#63d89a" : root.gold; font.pixelSize: 15 * root.s; font.bold: true }
                        Text { x: 16 * root.s; y: 48 * root.s; width: parent.width - 32 * root.s; text: partyWorkspace.partyInfo.bridgeReady ? "Server-side summon and preparation are available." : "Start the realm and log in with your character."; color: root.muted; font.pixelSize: 15 * root.s; wrapMode: Text.Wrap }
                    }

                    Text {
                        x: 22 * root.s; y: 454 * root.s; width: parent.width - 44 * root.s
                        text: {
                            var build = control.data["/api/party/build"]
                            var action = control.data["/api/party/action"]
                            return action && action.message ? action.message : build && build.message ? build.message : "Build creates four bots, summons them, matches your level, equips gear and learns spells."
                        }
                        color: root.gold; font.pixelSize: 15 * root.s; wrapMode: Text.Wrap
                    }
                }
            }

            Item {
                x: 36 * root.s; y: 100 * root.s; width: parent.width - 72 * root.s; height: parent.height - 130 * root.s
                visible: root.page === "addons"
                property var addonInfo: { var changed = control.data["/api/addons/action"]; return changed && changed.addons ? changed : (control.data["/api/addons"] || {}) }
                Text { x: 0; y: 0; text: "WoW addon library"; color: root.ink; font.pixelSize: 24 * root.s; font.bold: true }
                Text { x: 0; y: 38 * root.s; width: parent.width - 260 * root.s; text: control.installations.length === 0 ? "A configured realm supplies the WoW client folder used by the addon library." : addonInfo.clientPath ? "Client: " + addonInfo.clientPath : "Loading configured client…"; color: root.muted; font.pixelSize: 15 * root.s; elide: Text.ElideMiddle }
                AzButton { anchors.right: parent.right; y: 0; text: "Open addon folder"; width: 220 * root.s; height: 54 * root.s; font.pixelSize: 16 * root.s; enabled: control.installations.length > 0 && addonInfo.configured !== false; onClicked: control.apiPost("addons-folder", "/api/addons/action", {"action":"open-folder"}) }
                Rectangle {
                    visible: control.installations.length === 0
                    x: 0; y: 92 * root.s; width: parent.width; height: 230 * root.s; radius: 12 * root.s; color: root.raised; border.color: root.edge
                    Text { x: 24 * root.s; y: 24 * root.s; text: "NO REALM CONFIGURED"; color: root.gold; font.pixelSize: 14 * root.s; font.bold: true; font.letterSpacing: 1.3 }
                    Text { x: 24 * root.s; y: 62 * root.s; text: "Complete first-time setup"; color: root.ink; font.pixelSize: 26 * root.s; font.bold: true }
                    Text { x: 24 * root.s; y: 105 * root.s; width: parent.width - 48 * root.s; text: "After a realm is installed, Azeroth Control can find its WoW client and manage ConsolePortLK, Questie-X, RefinedBlizzPlates and the bundled addons."; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap }
                    AzButton { x: 24 * root.s; anchors.bottom: parent.bottom; anchors.bottomMargin: 20 * root.s; width: 250 * root.s; height: 56 * root.s; text: "Start first-time setup"; primary: true; font.pixelSize: 17 * root.s; onClicked: root.showFirstTimeSetup() }
                }
                ListView {
                    x: 0; y: 78 * root.s; width: parent.width; height: parent.height - 78 * root.s; spacing: 12 * root.s; clip: true
                    visible: control.installations.length > 0
                    model: parent.addonInfo.addons || []
                    delegate: Rectangle {
                        id: addonCard
                        required property int index
                        required property var modelData
                        width: ListView.view.width; height: 132 * root.s; radius: 10 * root.s; color: root.raised; border.color: modelData.installed ? "#2d8d60" : root.edge
                        Text { x: 18 * root.s; y: 14 * root.s; text: modelData.name; color: root.ink; font.pixelSize: 20 * root.s; font.bold: true }
                        Text { x: 18 * root.s; y: 46 * root.s; width: parent.width - 390 * root.s; text: modelData.description; color: root.ink; font.pixelSize: 15 * root.s; wrapMode: Text.Wrap }
                        Text { x: 18 * root.s; y: 82 * root.s; width: parent.width - 390 * root.s; text: modelData.note; color: root.muted; font.pixelSize: 13 * root.s; elide: Text.ElideRight }
                        Text { x: 18 * root.s; y: 106 * root.s; visible: modelData.id === "ffxiv-controller"; text: "Steam Input templates: " + (modelData.steamTemplatesInstalled || 0) + " / " + (modelData.steamTemplatesExpected || 7); color: (modelData.steamTemplatesInstalled || 0) === (modelData.steamTemplatesExpected || 7) ? "#58d38c" : root.gold; font.pixelSize: 13 * root.s }
                        Text { anchors.right: parent.right; anchors.rightMargin: 22 * root.s; y: 14 * root.s; text: modelData.installed ? "INSTALLED " + (modelData.installedVersion || "") : "v" + modelData.version; color: modelData.installed ? "#58d38c" : root.gold; font.pixelSize: 13 * root.s; font.bold: true }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 16 * root.s; y: 52 * root.s; spacing: 10 * root.s
                            AzButton {
                                visible: modelData.installed; width: 145 * root.s; height: 54 * root.s; text: "Repair"; font.pixelSize: 16 * root.s; enabled: !control.busy
                                onActiveFocusChanged: if (activeFocus) addonCard.ListView.view.positionViewAtIndex(index, ListView.Contain)
                                onClicked: control.apiPost("addons", "/api/addons/action", {"action":"repair", "id": modelData.id})
                            }
                            AzButton {
                                width: 155 * root.s; height: 54 * root.s; text: modelData.installed ? "Remove" : "Install"; danger: modelData.installed; primary: !modelData.installed; font.pixelSize: 16 * root.s; enabled: !control.busy
                                onActiveFocusChanged: if (activeFocus) addonCard.ListView.view.positionViewAtIndex(index, ListView.Contain)
                                onClicked: control.apiPost("addons", "/api/addons/action", {"action": modelData.installed ? "remove" : "install", "id": modelData.id})
                            }
                        }
                    }
                }
            }

            Column {
                x: 36 * root.s; y: 100 * root.s; width: parent.width - 72 * root.s; spacing: 12 * root.s
                visible: root.page === "logs"
                Text { text: "Server log"; color: root.ink; font.pixelSize: 24 * root.s }
                TextArea { id: logArea; width: parent.width; height: 560 * root.s; readOnly: true; wrapMode: TextArea.NoWrap; color: root.ink; font.pixelSize: 15 * root.s; text: { var l = control.data["/api/logs?lines=220"]; return l && l.logs ? l.logs : "Loading server log…" } }
                AzButton { text: "Refresh log"; width: 200 * root.s; height: 58 * root.s; font.pixelSize: 18 * root.s; onClicked: control.apiGet("logs", "/api/logs?lines=220") }
            }

            Column {
                x: 36 * root.s; y: 100 * root.s; spacing: 20 * root.s
                visible: root.page === "maintenance"
                Text { text: "Managed server maintenance"; color: root.ink; font.pixelSize: 24 * root.s }
                Row {
                    spacing: 14 * root.s
                    AzButton { id: updateButton; text: "Update server"; width: 220 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; enabled: !control.busy; onClicked: control.maintenanceAction("update"); KeyNavigation.right: repairButton }
                    AzButton { id: repairButton; text: "Repair installation"; width: 250 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; enabled: !control.busy; onClicked: control.maintenanceAction("repair"); KeyNavigation.left: updateButton }
                    AzButton { text: "Create backup"; width: 210 * root.s; height: 62 * root.s; font.pixelSize: 18 * root.s; enabled: !control.busy; onClicked: control.apiPost("backup", "/api/backup", {}) }
                }
                Text { text: "Updates create a recovery backup before changing the managed server."; color: root.muted; font.pixelSize: 18 * root.s; wrapMode: Text.Wrap }
                Text { text: { var b = control.data["/api/backups"]; return b && b.backups ? "Backups available: " + b.backups.length : "Backups: loading…" } color: root.gold; font.pixelSize: 17 * root.s }
            }
        }
    }

    Dialog {
        id: removeServerDialog
        visible: root.deleteInstallationTarget !== null
        modal: true; anchors.centerIn: parent; width: 720 * root.s; height: 350 * root.s
        closePolicy: Popup.NoAutoClose
        background: Rectangle { radius: 16 * root.s; color: root.panel; border.width: 2 * root.s; border.color: root.gold }
        contentItem: Item {
            Text { x: 28 * root.s; y: 22 * root.s; text: "REMOVE SERVER"; color: root.gold; font.pixelSize: 15 * root.s; font.bold: true; font.letterSpacing: 1.3 }
            Text { x: 28 * root.s; y: 58 * root.s; width: parent.width - 56 * root.s; text: root.deleteInstallationTarget ? root.deleteInstallationTarget.name : ""; color: root.ink; font.pixelSize: 27 * root.s; font.bold: true }
            Text { x: 28 * root.s; y: 108 * root.s; width: parent.width - 56 * root.s; text: root.deleteInstallationTarget && root.deleteInstallationTarget.imported ? "Forget removes this entry from Azeroth Control. Imported files are never deleted." : "Remove Only keeps all files. Delete Server Data stops the server and moves its managed folder to Trash. WoW files are never touched."; color: root.muted; font.pixelSize: 17 * root.s; wrapMode: Text.Wrap }
            Row { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 24 * root.s; spacing: 12 * root.s
                AzButton { text: "Cancel"; width: 150 * root.s; height: 58 * root.s; font.pixelSize: 17 * root.s; onClicked: root.deleteInstallationTarget = null }
                AzButton { text: root.deleteInstallationTarget && root.deleteInstallationTarget.imported ? "Forget" : "Remove Only"; width: 180 * root.s; height: 58 * root.s; font.pixelSize: 17 * root.s; onClicked: { control.removeInstallation(root.deleteInstallationTarget.id, false); root.deleteInstallationTarget = null } }
                AzButton { visible: root.deleteInstallationTarget && !root.deleteInstallationTarget.imported; text: "Delete Server Data"; danger: true; width: 210 * root.s; height: 58 * root.s; font.pixelSize: 17 * root.s; onClicked: { control.removeInstallation(root.deleteInstallationTarget.id, true); root.deleteInstallationTarget = null } }
            }
        }
    }

    Rectangle {
        id: gamepadFocusRing
        z: 10000
        enabled: false
        property Item target: root.activeFocusItem
        property point targetPosition: target ? target.mapToItem(root.contentItem, 0, 0) : Qt.point(0, 0)
        visible: target && target !== root.contentItem && target.width > 0 && target.height > 0
        x: targetPosition.x - 7 * root.s
        y: targetPosition.y - 7 * root.s
        width: target ? target.width + 14 * root.s : 0
        height: target ? target.height + 14 * root.s : 0
        radius: 12 * root.s
        color: "transparent"
        border.color: root.gold
        border.width: 4 * root.s

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3 * root.s
            radius: parent.radius + 3 * root.s
            color: "transparent"
            border.color: "#6b4300"
            border.width: 2 * root.s
            opacity: 0.9
        }
        SequentialAnimation on opacity {
            running: gamepadFocusRing.visible
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.68; duration: 650 }
            NumberAnimation { from: 0.68; to: 1.0; duration: 650 }
        }
        Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    }

    Shortcut { sequence: "Esc"; onActivated: { if (control.installations.length === 0) root.showFirstTimeSetup(); else if (root.page !== "dashboard") root.page = "dashboard"; else root.showMinimized() } }
    Connections {
        target: control
        function onYieldToGame() {
            // Keep the Control surface alive inside Gamescope. Minimizing it can
            // make Steam discard the XWayland window and leave a stale frame on
            // top of WoW. Lowering preserves instant Steam task switching.
            root.lower()
        }
        function onGamepadAction(command) { root.handleGamepad(command) }
        function onDataChanged() {
            var s = control.data["/api/settings?realm=" + control.activeRealm]
            if (s && s.settings) s = s.settings
            if (s) {
                if (s.joinLfg !== undefined) root.queueLfg = !!s.joinLfg
                if (s.joinBg !== undefined) root.queueBg = !!s.joinBg
                if (s.autoJoinBg !== undefined) root.autoQueueBg = !!s.autoJoinBg
                if (s.dynamicBrackets !== undefined) root.dynamicBrackets = !!s.dynamicBrackets
                if (s.syncFactions !== undefined) root.syncFactions = !!s.syncFactions
            }
        }
    }
    Connections {
        target: control
        function onInstallationsChanged() {
            if (control.installations.length === 0)
                root.showFirstTimeSetup()
        }
        function onInstallChanged() {
            if (!control.installRunning && control.installations.length > 0 && root.page === "install") {
                root.page = "dashboard"
                dashboardButton.forceActiveFocus()
            }
        }
    }

    Component.onCompleted: {
        if (control.installations.length === 0)
            root.showFirstTimeSetup()
        else
            dashboardButton.forceActiveFocus()
    }
}
