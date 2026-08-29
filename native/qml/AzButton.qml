import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool danger: false

    implicitHeight: 58
    hoverEnabled: true
    leftPadding: 18
    rightPadding: 18

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.primary ? "#171006"
              : control.danger ? "#ff9ca3"
              : control.highlighted || control.activeFocus ? "#f2b64b"
              : "#e8edf2"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 10
        color: control.down ? (control.primary ? "#bd7612" : "#263846")
             : control.primary ? (control.hovered ? "#f3b43a" : "#e5a126")
             : control.danger ? (control.hovered ? "#3b2025" : "#29191d")
             : control.highlighted ? "#272217"
             : control.hovered ? "#1d2c37"
             : "#14212b"
        border.width: control.primary || control.highlighted || control.activeFocus ? 2 : 1
        border.color: control.primary ? "#ffc75c"
                    : control.danger ? "#743941"
                    : control.highlighted || control.activeFocus ? "#b98020"
                    : "#344653"

        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on border.color { ColorAnimation { duration: 100 } }
    }
}
