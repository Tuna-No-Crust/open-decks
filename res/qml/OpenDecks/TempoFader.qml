import Mixxx 1.0 as Mixxx
import QtQuick
import "." as OD

// Per-deck tempo fader at the panel's outer edge: touch only, the gamepad has
// no tempo mapping by decision (sync is the controller's way to match BPM).
// `[ChannelN] rate` is -1..+1 across rateRange. Mixxx's default direction
// (rate_dir -1) puts the faster end at the bottom, which is Qt's natural
// vertical slider (+1 at the top = slower), so only the +/- end marks flip
// with rate_dir. Tap the head to reset.
Item {
    id: root

    required property int deckNumber

    readonly property string group: "[Channel" + deckNumber + "]"
    readonly property color accent: OD.Tokens.deckColor(deckNumber)
    // Unreadable (0) counts as Mixxx's default, inverted.
    readonly property bool plusAtBottom: rateDir.value <= 0
    readonly property real percent: (rateRatio.value - 1) * 100
    // The cap stays inside the track (its edge, not its centre, stops at the
    // ends), so it is never clipped at full deflection.
    readonly property real trackTop: OD.Tokens.targetMin + OD.Tokens.s.s2
    readonly property var player: Mixxx.PlayerManager.getPlayer(group)
    readonly property bool loaded: player ? player.isLoaded : false

    implicitHeight: OD.Tokens.layout.hTempoTrack + OD.Tokens.targetMin + OD.Tokens.s.s2
    implicitWidth: OD.Tokens.layout.wTempo

    Mixxx.ControlProxy { id: rate; group: root.group; key: "rate" }
    Mixxx.ControlProxy { id: rateRatio; group: root.group; key: "rate_ratio" }
    Mixxx.ControlProxy { id: rateRange; group: root.group; key: "rateRange" }
    Mixxx.ControlProxy { id: rateDir; group: root.group; key: "rate_dir" }

    // Track.
    Rectangle {
        color: OD.Tokens.edge
        height: OD.Tokens.layout.hTempoTrack
        width: OD.Tokens.b2
        x: (root.width - width) / 2
        y: root.trackTop
    }
    // Centre detent.
    Rectangle {
        color: OD.Tokens.textSecondary
        height: OD.Tokens.b2
        width: OD.Tokens.s.s4
        x: (root.width - width) / 2
        y: root.trackTop + (OD.Tokens.layout.hTempoTrack - height) / 2
    }
    // End marks: the faster end is "+". A ground patch interrupts the track
    // behind each, so a "−" doesn't read as a "+" crossed by the line.
    Repeater {
        model: 2

        Rectangle {
            id: mark

            required property int index
            readonly property bool isTop: index === 0

            color: OD.Tokens.ground
            height: OD.Tokens.lh.label
            width: OD.Tokens.s.s5
            x: (root.width - width) / 2
            y: isTop ? root.trackTop + OD.Tokens.s.s1 :
                root.trackTop + OD.Tokens.layout.hTempoTrack - height - OD.Tokens.s.s1

            Text {
                anchors.fill: parent
                color: OD.Tokens.textMuted
                font.family: OD.Tokens.mono
                font.pixelSize: OD.Tokens.fs.label
                font.weight: OD.Tokens.fw.semibold
                horizontalAlignment: Text.AlignHCenter
                lineHeight: OD.Tokens.lh.label
                lineHeightMode: Text.FixedHeight
                text: mark.isTop === root.plusAtBottom ? "\u2212" : "+"
            }
        }
    }

    // The cap is the only thing that takes touch: a press on the track does
    // nothing, because the thumbs grip the Deck right here and a stray touch
    // must not throw the tempo. Drags are relative to where the cap was.
    Rectangle {
        id: cap

        readonly property real travel: OD.Tokens.layout.hTempoTrack - OD.Tokens.targetMin
        readonly property bool moving: dragH.active
        readonly property real clamped: Math.max(-1, Math.min(1, rate.value))
        property real startRate: 0

        Accessible.name: "Tempo deck " + root.deckNumber
        border.color: moving ? root.accent : capTap.pressed ? OD.Tokens.textSecondary : OD.Tokens.edge
        border.width: OD.Tokens.b1
        color: moving ? root.accent : capTap.pressed ? OD.Tokens.selected : OD.Tokens.raised
        enabled: root.loaded
        height: OD.Tokens.targetMin
        opacity: enabled ? 1 : OD.Tokens.opacityDisabled
        radius: OD.Tokens.r.r2
        width: OD.Tokens.targetMin
        x: (root.width - width) / 2
        // +1 (rate) at the top; the cap's edge, not its centre, meets the ends.
        y: root.trackTop + (1 - clamped) / 2 * travel
        z: 1 // covers the +/- end marks at the extremes

        Behavior on color { ColorAnimation { duration: OD.Tokens.durFast } }

        Repeater {
            model: 2

            Rectangle {
                id: bar

                required property int index

                color: cap.moving ? OD.Tokens.ground : OD.Tokens.textSecondary
                height: OD.Tokens.b2
                x: OD.Tokens.s.s3
                width: cap.width - 2 * OD.Tokens.s.s3
                y: bar.index === 0 ? cap.height / 2 - OD.Tokens.s.s1 : cap.height / 2 + OD.Tokens.b2
            }
        }
        // Passive: only feeds the pressed look before the drag starts.
        TapHandler { id: capTap }
        DragHandler {
            id: dragH

            target: null
            xAxis.enabled: false
            onActiveChanged: if (active) cap.startRate = cap.clamped
            onActiveTranslationChanged: {
                if (!active)
                    return;
                const r = Math.max(-1, Math.min(1, cap.startRate - 2 * activeTranslation.y / cap.travel));
                // Snap to 0 within +-0.5 % so "dead centre" is easy to land.
                rate.value = Math.abs(r * rateRange.value) < 0.005 ? 0 : r;
            }
        }
    }

    // Head: caption over the signed readout; a tap puts the tempo back to 0.
    Rectangle {
        id: head

        border.color: headTap.pressed ? OD.Tokens.textSecondary : OD.Tokens.edge
        border.width: OD.Tokens.b1
        color: headTap.pressed ? OD.Tokens.raised : OD.Tokens.panel
        enabled: root.loaded
        height: OD.Tokens.targetMin
        opacity: enabled ? 1 : OD.Tokens.opacityDisabled
        radius: OD.Tokens.r.r2
        width: OD.Tokens.layout.wTempo
        z: 1

        Accessible.name: "Tempo " + readout.text + ", tap to reset"
        Accessible.role: Accessible.Button

        Behavior on color { ColorAnimation { duration: OD.Tokens.durFast } }

        Column {
            anchors.centerIn: parent

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: OD.Tokens.textMuted
                font.capitalization: Font.AllUppercase
                font.family: OD.Tokens.sans
                font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.caption, OD.Tokens.ls.label)
                font.pixelSize: OD.Tokens.fs.caption
                font.weight: OD.Tokens.fw.semibold
                lineHeight: OD.Tokens.lh.caption
                lineHeightMode: Text.FixedHeight
                text: "Tempo"
            }
            Text {
                id: readout

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, head.width - 2 * OD.Tokens.b2)
                color: OD.Tokens.text
                font.family: OD.Tokens.mono
                font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.label, OD.Tokens.ls.tight)
                font.pixelSize: OD.Tokens.fs.label
                font.weight: OD.Tokens.fw.semibold
                fontSizeMode: Text.HorizontalFit
                lineHeight: OD.Tokens.lh.label
                lineHeightMode: Text.FixedHeight
                minimumPixelSize: OD.Tokens.fs.caption
                text: (root.percent < 0 ? "−" : "+") + Math.abs(root.percent).toFixed(2) + "%"
            }
        }
        TapHandler {
            id: headTap

            onTapped: rate.value = 0
        }
    }
}
