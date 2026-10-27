import QtQuick 2.12
import QtQuick.Controls
import "." as OD

// A small square touch button with a glyph (fullscreen, quit...).
Button {
    id: root

    property string glyph: ""
    // on = armed/danger (red); lit = selected (light).
    property bool on: false
    property bool lit: false

    implicitHeight: 36
    implicitWidth: Math.max(36, label.implicitWidth + 16)

    background: Rectangle {
        color: root.on ? OD.Tokens.danger : (root.lit || root.down ? OD.Tokens.selected : OD.Tokens.panel)
        radius: 8
    }
    contentItem: Text {
        id: label

        color: root.on ? OD.Tokens.ground : (root.lit ? OD.Tokens.text : OD.Tokens.textMuted)
        font.bold: root.on || root.lit
        font.pixelSize: 15
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        verticalAlignment: Text.AlignVCenter
    }
}
