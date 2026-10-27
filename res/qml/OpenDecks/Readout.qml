import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import "." as OD

// A 44 px readout row for a control the sticks drive (EQ band, filter, FX
// amount): label, value, and a bar with a marker. The whole row is the
// reset target (design-system §4: tap-to-reset, safe because it sits in the
// centre zone).
Item {
    id: root

    required property string group
    required property string key
    required property string label
    // "eq": dB of the band's gain, KILL at zero. "filter": bipolar -1..+1.
    // "fx": integer 0..100.
    property string kind: "eq"
    // Overridable, e.g. to show an effect unit as 0 while it is switched off.
    property real level: control.parameter
    readonly property bool bipolar: kind !== "fx"
    readonly property bool kill: kind === "eq" && level < 0.005

    implicitWidth: OD.Tokens.layout.wReadouts
    implicitHeight: OD.Tokens.targetMin

    function signed(v, digits) {
        const text = v.toFixed(digits);
        // Never show "-0.0" or "+0.00".
        if (Number(text) === 0) {
            return (0).toFixed(digits);
        }
        return (v > 0 ? "+" : "") + text;
    }

    readonly property string valueText: {
        if (kind === "fx") {
            return Math.round(level * 100).toString();
        }
        if (kind === "filter") {
            return signed((level - 0.5) * 2, 2);
        }
        if (kill) {
            return "KILL";
        }
        return signed(20 * Math.log10(control.value), 1);
    }

    Mixxx.ControlProxy {
        id: control

        group: root.group
        key: root.key
    }

    Rectangle {
        anchors.fill: parent
        color: tap.pressed ? OD.Tokens.raised : "transparent"

        Behavior on color {
            ColorAnimation { duration: OD.Tokens.durFast }
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom
        color: OD.Tokens.line
        height: OD.Tokens.b1
        width: parent.width
    }
    Text {
        color: OD.Tokens.textMuted
        font.capitalization: Font.AllUppercase
        font.family: OD.Tokens.sans
        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.label, OD.Tokens.ls.label)
        font.pixelSize: OD.Tokens.fs.label
        font.weight: OD.Tokens.fw.semibold
        height: OD.Tokens.lh.label
        text: root.label
        verticalAlignment: Text.AlignVCenter
        y: OD.Tokens.s.s2 + OD.Tokens.b2
    }
    Text {
        anchors.right: parent.right
        color: root.kill ? OD.Tokens.danger : OD.Tokens.text
        font.family: OD.Tokens.mono
        font.pixelSize: OD.Tokens.fs.label
        font.weight: OD.Tokens.fw.semibold
        height: OD.Tokens.lh.label
        text: root.valueText
        verticalAlignment: Text.AlignVCenter
        y: OD.Tokens.s.s2 + OD.Tokens.b2
    }
    Rectangle {
        id: bar

        color: OD.Tokens.edge
        height: OD.Tokens.b2
        width: parent.width
        y: parent.height - OD.Tokens.s.s2 + OD.Tokens.b1 - OD.Tokens.b2

        // Centre notch: neutral for the bipolar controls.
        Rectangle {
            color: OD.Tokens.textMuted
            height: OD.Tokens.layout.notch
            visible: root.bipolar
            width: OD.Tokens.b2
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
        }
        Rectangle {
            color: OD.Tokens.text
            height: OD.Tokens.layout.notch
            radius: OD.Tokens.r.r1
            width: OD.Tokens.layout.dot
            x: Math.max(0, Math.min(1, root.level)) * parent.width - width / 2
            y: (parent.height - height) / 2
        }
    }
    TapHandler {
        id: tap

        // The FX row's default would be mix 1.0 (fully wet): reset it to dry.
        onTapped: root.kind === "fx" ? control.parameter = 0 : control.reset()
    }
}
