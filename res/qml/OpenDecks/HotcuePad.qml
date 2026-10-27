import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import "." as OD

// One on-screen hot cue pad. Empty: dashed edge + "tap to set" (tap sets it at
// the play position). Set: solid edge, letter and bar in the cue's own colour
// from rekordbox/Mixxx. Held while set: filled in that colour (the cue is
// firing). Hold to play from it; released = back, CDJ-style when paused.
Button {
    id: root

    required property string group
    required property int number // 1-based

    readonly property bool isSet: statusControl.value !== 0
    readonly property color cueColor: colorControl.value >= 0 ?
        "#" + Math.round(colorControl.value).toString(16).padStart(6, "0") :
        OD.Tokens.hotcuePalette[(number - 1) % OD.Tokens.hotcuePalette.length]
    readonly property bool firing: down && isSet
    // No track: dimmed and inert (the fifth state).
    readonly property var player: Mixxx.PlayerManager.getPlayer(group)
    readonly property bool loaded: player ? player.isLoaded : false

    enabled: loaded
    opacity: enabled ? 1 : OD.Tokens.opacityDisabled
    implicitHeight: OD.Tokens.layout.hPad
    implicitWidth: OD.Tokens.layout.wPad
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    Accessible.name: isSet ? "Hot cue " + letter.text : "Set hot cue " + letter.text

    onPressed: activateControl.value = 1
    onReleased: activateControl.value = 0
    onCanceled: activateControl.value = 0

    Mixxx.ControlProxy {
        id: activateControl

        group: root.group
        key: "hotcue_" + root.number + "_activate"
    }
    Mixxx.ControlProxy {
        id: statusControl

        group: root.group
        key: "hotcue_" + root.number + "_status"
    }
    Mixxx.ControlProxy {
        id: colorControl

        group: root.group
        key: "hotcue_" + root.number + "_color"
    }

    background: Item {
        // Solid body for set pads and for the pressed empty pad.
        Rectangle {
            anchors.fill: parent
            border.color: root.firing ? root.cueColor : OD.Tokens.edge
            border.width: OD.Tokens.b1
            color: root.firing ? root.cueColor : root.down ? OD.Tokens.raised : OD.Tokens.panel
            radius: OD.Tokens.r.r2
            visible: root.isSet || root.down

            Behavior on color { ColorAnimation { duration: OD.Tokens.durFast } }
        }
        // Dashed edge of an empty pad (Rectangle can't dash).
        Canvas {
            id: dashes

            anchors.fill: parent
            visible: !root.isSet && !root.down

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                // Pad fill inside the dashes.
                ctx.fillStyle = OD.Tokens.panel;
                ctx.beginPath();
                ctx.roundedRect(0, 0, width, height, OD.Tokens.r.r2, OD.Tokens.r.r2);
                ctx.fill();
                ctx.strokeStyle = OD.Tokens.edge;
                ctx.lineWidth = OD.Tokens.b1;
                ctx.setLineDash([OD.Tokens.s.s1, OD.Tokens.s.s1 - OD.Tokens.b1]);
                ctx.beginPath();
                ctx.roundedRect(0.5, 0.5, width - 1, height - 1, OD.Tokens.r.r2, OD.Tokens.r.r2);
                ctx.stroke();
            }
            onHeightChanged: requestPaint()
            onWidthChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }
    }
    contentItem: Item {
        Text {
            id: letter

            color: root.firing ? OD.Tokens.ground : root.isSet ? root.cueColor : OD.Tokens.textMuted
            font.family: OD.Tokens.sans
            font.pixelSize: OD.Tokens.fs.title
            font.weight: OD.Tokens.fw.bold
            lineHeight: OD.Tokens.lh.title
            lineHeightMode: Text.FixedHeight
            text: "ABCDEFGH".charAt(root.number - 1)
            verticalAlignment: Text.AlignVCenter

            // Set: letter at the left padding, centred vertically; empty:
            // letter and hint as one centred block.
            x: root.isSet ? OD.Tokens.s.s3 - OD.Tokens.b1 : (parent.width - width) / 2
            y: root.isSet ? (parent.height - height) / 2 : hint.y - OD.Tokens.lh.title + OD.Tokens.s.s1
        }
        Text {
            id: hint

            color: OD.Tokens.textMuted
            font.family: OD.Tokens.sans
            font.pixelSize: OD.Tokens.fs.caption
            font.weight: OD.Tokens.fw.medium
            lineHeight: OD.Tokens.lh.caption
            lineHeightMode: Text.FixedHeight
            text: "tap to set"
            visible: !root.isSet
            x: (parent.width - width) / 2
            // Block = title line + caption line overlapping by s1, centred.
            y: (parent.height - (OD.Tokens.lh.title + OD.Tokens.lh.caption - OD.Tokens.s.s1)) / 2
                + OD.Tokens.lh.title - OD.Tokens.s.s1
        }
        // Cue-colour bar under the letter.
        Rectangle {
            color: root.firing ? OD.Tokens.ground : root.cueColor
            height: OD.Tokens.b2
            visible: root.isSet
            width: OD.Tokens.s.s5
            x: OD.Tokens.s.s3 - OD.Tokens.b1
            y: parent.height - OD.Tokens.s.s1 - height
        }
    }
}
