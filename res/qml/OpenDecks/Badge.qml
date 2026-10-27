import QtQuick 2.12
import "." as OD

// SYNC / VINYL / KEY LOCK style toggle (also a plain readout on the FX
// screen). Rest: panel + 1 px edge. Pressed: raised. On = active-mode: 2 px
// edge, a dot and the text all in `onColor`, so the state never rides on
// colour alone.
Item {
    id: root

    required property string text
    property bool on: false
    property color onColor: OD.Tokens.text
    property bool tappable: false
    // Kept for callers; every badge has the full target height now.
    property bool tall: tappable

    signal tapped()

    implicitHeight: OD.Tokens.targetMin
    implicitWidth: Math.max(OD.Tokens.layout.wBadge, label.implicitWidth + 2 * OD.Tokens.s.s3)

    Accessible.name: text
    Accessible.role: tappable ? Accessible.Button : Accessible.StaticText

    Rectangle {
        anchors.fill: parent
        border.color: root.on ? root.onColor : tap.pressed ? OD.Tokens.textSecondary : OD.Tokens.edge
        border.width: root.on ? OD.Tokens.b2 : OD.Tokens.b1
        color: tap.pressed ? OD.Tokens.raised : OD.Tokens.panel
        radius: OD.Tokens.r.r2

        Behavior on color { ColorAnimation { duration: OD.Tokens.durFast } }
        Behavior on border.color { ColorAnimation { duration: OD.Tokens.durFast } }
    }
    Rectangle {
        color: root.onColor
        height: OD.Tokens.layout.dot
        radius: OD.Tokens.r.pill
        visible: root.on
        width: OD.Tokens.layout.dot
        x: OD.Tokens.s.s2
        y: OD.Tokens.s.s2
    }
    Text {
        id: label

        anchors.centerIn: parent
        color: root.on ? root.onColor : OD.Tokens.textSecondary
        font.capitalization: Font.AllUppercase
        font.family: OD.Tokens.sans
        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.label, OD.Tokens.ls.label)
        font.pixelSize: OD.Tokens.fs.label
        font.weight: OD.Tokens.fw.semibold
        text: root.text
    }

    TapHandler {
        id: tap

        enabled: root.tappable
        // A slow or slightly moving thumb still counts as a tap.
        gesturePolicy: TapHandler.ReleaseWithinBounds
        longPressThreshold: 3600
        onTapped: root.tapped()
    }
}
