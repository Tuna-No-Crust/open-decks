import QtQuick 2.12
import "." as OD

// A short notice centred over the mixer's upper half ("Deck 1 is playing -
// stop it first"), gone after a few seconds. The design gives it no accent
// colour, so show() accepts one for its callers and ignores it.
Rectangle {
    id: root

    function show(message, accentColor) {
        label.text = message;
        opacity = 1;
        hide.restart();
    }

    anchors.horizontalCenter: parent.horizontalCenter
    border.color: OD.Tokens.edge
    border.width: OD.Tokens.b1
    color: OD.Tokens.raised
    height: OD.Tokens.targetMin
    opacity: 0
    radius: OD.Tokens.r.r2
    visible: opacity > 0
    width: OD.Tokens.layout.wMixer - OD.Tokens.s.s6 * 2
    y: parent.height / 2 - OD.Tokens.targetMin - OD.Tokens.s.s1
    z: 100

    Behavior on opacity {
        NumberAnimation {
            duration: OD.Tokens.durNormal
            easing.bezierCurve: OD.Tokens.easing
            easing.type: Easing.BezierSpline
        }
    }
    // How long a notice stays: a behaviour constant, not a visual token.
    Timer {
        id: hide

        interval: 2600
        onTriggered: root.opacity = 0
    }
    Text {
        id: label

        anchors.fill: parent
        anchors.leftMargin: OD.Tokens.s.s4
        anchors.rightMargin: OD.Tokens.s.s4
        color: OD.Tokens.text
        elide: Text.ElideRight
        font.family: OD.Tokens.sans
        font.pixelSize: OD.Tokens.fs.body
        font.weight: OD.Tokens.fw.medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    TapHandler {
        onTapped: root.opacity = 0
    }
}
