import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import "." as OD

// Headphone cue level (`[Master] headGain`): label, a slider whose pill
// travels the whole track, and the gain in dB. Uses the control's 0..1
// `parameter` so the slider follows Mixxx's own gain curve (unity is the
// middle, where the notch is). Double-tap = unity.
Item {
    id: root

    // label | track | gap | value: the label and value columns are fixed,
    // the track takes the rest (232 at 448 px).
    readonly property real trackWidth: Math.max(0, width - 2 * OD.Tokens.layout.wCllabel - OD.Tokens.s.s5)

    implicitHeight: OD.Tokens.targetMin
    implicitWidth: OD.Tokens.layout.wMixer - OD.Tokens.s.s4 * 2

    Mixxx.ControlProxy {
        id: control

        group: "[Master]"
        key: "headGain"
    }

    // headGain is a gain (-14 dB .. +14 dB, unity at the middle).
    readonly property string dbText: {
        const g = control.value;
        if (!(g > 0)) {
            return "-∞";
        }
        const db = 20 * Math.log10(g);
        const text = db.toFixed(1);
        if (Number(text) === 0) {
            return (0).toFixed(1);
        }
        return (db > 0 ? "+" : "") + text;
    }

    Text {
        color: OD.Tokens.textMuted
        font.capitalization: Font.AllUppercase
        font.family: OD.Tokens.sans
        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.label, OD.Tokens.ls.label)
        font.pixelSize: OD.Tokens.fs.label
        font.weight: OD.Tokens.fw.semibold
        height: parent.height
        text: "CUE LEVEL"
        verticalAlignment: Text.AlignVCenter
    }
    Row {
        anchors.right: parent.right
        height: parent.height
        spacing: OD.Tokens.s.s1

        Text {
            color: OD.Tokens.text
            font.family: OD.Tokens.mono
            font.pixelSize: OD.Tokens.fs.body
            font.weight: OD.Tokens.fw.semibold
            height: parent.height
            text: root.dbText
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            color: OD.Tokens.textMuted
            font.family: OD.Tokens.sans
            font.pixelSize: OD.Tokens.fs.label
            font.weight: OD.Tokens.fw.semibold
            height: parent.height
            text: "dB"
            verticalAlignment: Text.AlignVCenter
        }
    }
    Slider {
        id: slider

        // Wider than the track by a handle, so the pill's centre runs the
        // track from end to end.
        property bool moving: false

        height: parent.height
        from: 0
        to: 1
        live: true
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        value: control.parameter
        width: root.trackWidth + OD.Tokens.targetMin
        x: OD.Tokens.layout.wCllabel - OD.Tokens.targetMin / 2

        onMoved: {
            moving = true;
            control.parameter = value;
        }
        onPressedChanged: {
            if (!pressed) {
                moving = false;
            }
        }

        background: Item {
            Rectangle {
                color: OD.Tokens.edge
                height: OD.Tokens.b2
                width: root.trackWidth
                x: OD.Tokens.targetMin / 2
                y: parent.height / 2 - OD.Tokens.b1

                Rectangle {
                    color: OD.Tokens.textMuted
                    height: OD.Tokens.layout.notch
                    width: OD.Tokens.b2
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                }
            }
        }
        handle: Rectangle {
            border.color: slider.moving ? OD.Tokens.accent : (slider.pressed ? OD.Tokens.textSecondary : OD.Tokens.edge)
            border.width: OD.Tokens.b1
            color: slider.moving ? OD.Tokens.accent : (slider.pressed ? OD.Tokens.selected : OD.Tokens.raised)
            height: OD.Tokens.targetMin
            radius: OD.Tokens.r.pill
            width: OD.Tokens.targetMin
            x: slider.visualPosition * (slider.width - width)
            y: 0

            Behavior on color {
                ColorAnimation { duration: OD.Tokens.durFast }
            }

            Rectangle {
                anchors.centerIn: parent
                color: slider.moving ? OD.Tokens.ground : OD.Tokens.text
                height: OD.Tokens.layout.dot
                radius: OD.Tokens.r.pill
                width: OD.Tokens.layout.dot
            }
        }
        TapHandler {
            onDoubleTapped: control.reset()
        }
    }
}
