import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import "." as OD

// One channel of the mixer: a touch fader at the outer edge, and beside it
// the readouts of what the controller's stick layers drive (EQ, filter, FX).
Item {
    id: root

    required property int deckNumber
    readonly property string group: "[Channel" + deckNumber + "]"
    readonly property color accent: OD.Tokens.deckColor(deckNumber)
    readonly property string eqGroup: "[EqualizerRack1_" + group + "_Effect1]"
    readonly property string fxGroup: "[EffectRack1_EffectUnit" + deckNumber + "]"
    // Channel 1's fader sits at the left edge of the mixer, channel 2's at the right.
    readonly property bool faderOuterLeft: deckNumber === 1

    implicitHeight: OD.Tokens.layout.hFader
    implicitWidth: OD.Tokens.layout.wCh

    // Effect units start switched off with the mix at 100%; show those as 0.
    Mixxx.ControlProxy {
        id: fxEnabled

        group: root.fxGroup
        key: "group_" + root.group + "_enable"
    }
    Mixxx.ControlProxy {
        id: fxMix

        group: root.fxGroup
        key: "mix"
    }

    OD.ChannelFader {
        accent: root.accent
        anchors.left: root.faderOuterLeft ? parent.left : undefined
        anchors.right: root.faderOuterLeft ? undefined : parent.right
        group: root.group
        height: parent.height
        width: OD.Tokens.layout.wFader
    }
    Column {
        anchors.left: root.faderOuterLeft ? undefined : parent.left
        anchors.right: root.faderOuterLeft ? parent.right : undefined
        width: OD.Tokens.layout.wReadouts

        Text {
            color: OD.Tokens.text
            font.family: OD.Tokens.sans
            font.pixelSize: OD.Tokens.fs.body
            font.weight: OD.Tokens.fw.semibold
            height: OD.Tokens.lh.body
            horizontalAlignment: root.faderOuterLeft ? Text.AlignLeft : Text.AlignRight
            text: "CH " + root.deckNumber
            verticalAlignment: Text.AlignVCenter
            width: parent.width
        }
        OD.Readout { group: root.eqGroup; key: "parameter3"; label: "HIGH" }
        OD.Readout { group: root.eqGroup; key: "parameter2"; label: "MID" }
        OD.Readout { group: root.eqGroup; key: "parameter1"; label: "LOW" }
        OD.Readout {
            group: "[QuickEffectRack1_" + root.group + "]"
            key: "super1"
            kind: "filter"
            label: "FILTER"
        }
        OD.Readout {
            group: root.fxGroup
            key: "mix"
            kind: "fx"
            label: "FX"
            level: fxEnabled.value > 0 ? fxMix.parameter : 0
        }
    }
}
