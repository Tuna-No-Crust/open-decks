import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import "." as OD

// One chip of the auto-loop strip: tap to start (or stop) an auto loop of
// `beats` beats. The seven chips form one segmented strip with shared edges:
// every chip after the first omits its left edge, unless the chip before it
// is the lit one (that chip's right edge is the hue, so this one draws its
// own again). Only the strip's outer corners are rounded.
Button {
    id: root

    required property string group
    required property real beats
    required property string label
    property color accent: OD.Tokens.text
    property bool first: false
    property bool last: false

    readonly property bool active: loopEnabled.value > 0 && Math.abs(loopSize.value - beats) < 0.001
    // The sizes double from chip to chip (1/4, 1/2, 1 ... 16).
    readonly property bool afterActive: !first && loopEnabled.value > 0 &&
        Math.abs(loopSize.value - beats / 2) < 0.001
    readonly property bool leftEdge: first || active || afterActive
    // No track: dimmed and inert (the fifth state).
    readonly property var player: Mixxx.PlayerManager.getPlayer(group)
    readonly property bool loaded: player ? player.isLoaded : false

    enabled: loaded
    opacity: enabled ? 1 : OD.Tokens.opacityDisabled
    implicitHeight: OD.Tokens.targetMin
    implicitWidth: OD.Tokens.layout.wLoop
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    Accessible.name: "Loop " + label + " beats"

    onClicked: toggle.value = 1

    Mixxx.ControlProxy {
        id: toggle

        group: root.group
        key: "beatloop_" + root.beats + "_toggle"
    }
    Mixxx.ControlProxy {
        id: loopEnabled

        group: root.group
        key: "loop_enabled"
    }
    Mixxx.ControlProxy {
        id: loopSize

        group: root.group
        key: "beatloop_size"
    }

    // The edge is the outer rectangle's fill; the inner one is inset by the
    // edge width, which lets the left edge be left out per chip.
    background: Rectangle {
        bottomLeftRadius: root.first ? OD.Tokens.r.r2 : 0
        bottomRightRadius: root.last ? OD.Tokens.r.r2 : 0
        color: root.active ? root.accent : root.down ? OD.Tokens.textSecondary : OD.Tokens.edge
        topLeftRadius: root.first ? OD.Tokens.r.r2 : 0
        topRightRadius: root.last ? OD.Tokens.r.r2 : 0

        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: OD.Tokens.b1
            anchors.leftMargin: root.leftEdge ? OD.Tokens.b1 : 0
            anchors.rightMargin: OD.Tokens.b1
            anchors.topMargin: OD.Tokens.b1
            bottomLeftRadius: root.first ? OD.Tokens.r.r2 - OD.Tokens.b1 : 0
            bottomRightRadius: root.last ? OD.Tokens.r.r2 - OD.Tokens.b1 : 0
            color: root.active ? root.accent : root.down ? OD.Tokens.raised : OD.Tokens.panel
            topLeftRadius: root.first ? OD.Tokens.r.r2 - OD.Tokens.b1 : 0
            topRightRadius: root.last ? OD.Tokens.r.r2 - OD.Tokens.b1 : 0

            Behavior on color { ColorAnimation { duration: OD.Tokens.durFast } }
        }
    }
    contentItem: Text {
        color: root.active ? OD.Tokens.ground : OD.Tokens.textSecondary
        font.family: OD.Tokens.mono
        font.pixelSize: OD.Tokens.fs.body
        font.weight: root.active ? OD.Tokens.fw.bold : OD.Tokens.fw.semibold
        horizontalAlignment: Text.AlignHCenter
        text: root.label
        verticalAlignment: Text.AlignVCenter
    }
}
