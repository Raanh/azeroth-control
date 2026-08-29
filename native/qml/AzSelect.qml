import QtQuick
import QtQuick.Controls

Control {
    id: select
    property var choices: []
    property string textRole: "name"
    property int selectedIndex: 0
    property int pendingIndex: selectedIndex
    readonly property bool isGamepadSelect: true
    readonly property bool menuOpen: menu.visible
    signal selectionAccepted(int index)

    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    leftPadding: 16
    rightPadding: 42

    function optionText(index) {
        if (index < 0 || index >= choices.length)
            return "Select…"
        var option = choices[index]
        if (typeof option === "string")
            return option
        return option && option[textRole] !== undefined ? String(option[textRole]) : String(option)
    }

    function openMenu() {
        pendingIndex = Math.max(0, Math.min(selectedIndex, choices.length - 1))
        optionList.currentIndex = pendingIndex
        menu.open()
    }

    function moveSelection(delta) {
        if (!choices.length)
            return
        pendingIndex = (pendingIndex + delta + choices.length) % choices.length
        optionList.currentIndex = pendingIndex
        optionList.positionViewAtIndex(pendingIndex, ListView.Contain)
    }

    function acceptSelection() {
        if (!menu.visible || !choices.length)
            return
        var acceptedIndex = pendingIndex
        menu.close()
        forceActiveFocus()
        selectionAccepted(acceptedIndex)
    }

    function cancelSelection() {
        pendingIndex = selectedIndex
        menu.close()
        forceActiveFocus()
    }

    contentItem: Text {
        text: select.optionText(select.selectedIndex)
        color: "#f4f0e7"
        font: select.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 8
        color: select.activeFocus || select.menuOpen ? "#1b2b36" : "#14212b"
        border.width: select.activeFocus || select.menuOpen ? 2 : 1
        border.color: select.activeFocus || select.menuOpen ? "#e6a126" : "#3a4c59"
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 15
        anchors.verticalCenter: parent.verticalCenter
        text: select.menuOpen ? "▲" : "▼"
        color: select.activeFocus ? "#e6a126" : "#93a1ae"
        font.pixelSize: 12
    }

    MouseArea {
        anchors.fill: parent
        onClicked: select.menuOpen ? select.acceptSelection() : select.openMenu()
    }

    Keys.onReturnPressed: function(event) { event.accepted = true }
    Keys.onEnterPressed: function(event) { event.accepted = true }
    Keys.onEscapePressed: function(event) { event.accepted = true }

    Popup {
        id: menu
        x: 0
        y: select.height + 6
        width: select.width
        height: Math.min(choices.length * 48 + 8, 300)
        padding: 4
        modal: false
        focus: false
        closePolicy: Popup.NoAutoClose
        z: 1000

        background: Rectangle {
            radius: 8
            color: "#0b141b"
            border.width: 2
            border.color: "#e6a126"
        }

        contentItem: ListView {
            id: optionList
            clip: true
            model: select.choices
            currentIndex: select.pendingIndex
            delegate: Rectangle {
                required property int index
                width: optionList.width
                height: 48
                radius: 5
                color: index === select.pendingIndex ? "#e6a126" : "transparent"
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 13
                    text: select.optionText(index)
                    color: index === select.pendingIndex ? "#121820" : "#f4f0e7"
                    font.pixelSize: select.font.pixelSize
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        select.pendingIndex = index
                        select.acceptSelection()
                    }
                }
            }
            ScrollBar.vertical: ScrollBar { }
        }
    }
}
