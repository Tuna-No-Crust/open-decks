import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import "." as OD

// A vertical fader: slot, five ticks and a 64 x 44 handle that carries its
// own 0-100 value. Drag the handle (or anywhere on the slot) with a finger;
// the stick layers move the same control, so both stay in step.
Slider {
    id: root

    required property string group
    property string key: "volume"
    required property color accent

    // Pressed and still = selected; once it moves it is engaged (deck hue).
    property bool moving: false

    from: 0
    to: 1
    orientation: Qt.Vertical
    implicitWidth: OD.Tokens.layout.wFader
    implicitHeight: OD.Tokens.layout.hFader
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    live: true
    value: control.parameter

    onMoved: {
        moving = true;
        control.parameter = value;
    }
    onPressedChanged: {
        if (!pressed) {
            moving = false;
        }
    }

    Mixxx.ControlProxy {
        id: control

        group: root.group
        key: root.key
    }

    background: Item {
        Rectangle {
            color: OD.Tokens.edge
            height: parent.height
            width: OD.Tokens.b2
            x: parent.width / 2 - OD.Tokens.b1
        }
        // Ticks sit at the handle-centre positions for 0/25/50/75/100 %.
        Repeater {
            model: 5

            Rectangle {
                required property int index

                color: OD.Tokens.line
                height: OD.Tokens.b1
                width: OD.Tokens.s.s4
                x: parent.width / 2 - OD.Tokens.s.s2
                y: OD.Tokens.layout.hHandle / 2 + index * (parent.height - OD.Tokens.layout.hHandle) / 4
            }
        }
    }
    handle: Rectangle {
        border.color: root.moving ? root.accent : (root.pressed ? OD.Tokens.textSecondary : OD.Tokens.edge)
        border.width: OD.Tokens.b1
        color: root.moving ? root.accent : (root.pressed ? OD.Tokens.selected : OD.Tokens.raised)
        height: OD.Tokens.layout.hHandle
        radius: OD.Tokens.r.r2
        width: OD.Tokens.layout.wFader
        x: 0
        y: root.visualPosition * (root.height - height)

        Behavior on color {
            ColorAnimation { duration: OD.Tokens.durFast }
        }

        Text {
            anchors.centerIn: parent
            color: root.moving ? OD.Tokens.ground : OD.Tokens.text
            font.family: OD.Tokens.mono
            font.pixelSize: OD.Tokens.fs.body
            font.weight: OD.Tokens.fw.bold
            text: Math.round(root.value * 100)
        }
    }
    TapHandler {
        onDoubleTapped: control.reset()
    }
}
