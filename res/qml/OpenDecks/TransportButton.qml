import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import "." as OD

// PLAY / CUE / PFL of one deck, the touch twins of the controller's transport.
//   play: lit in the deck hue while playing (active-engaged); a tap always
//         toggles, nothing is refused.
//   cue:  press = cue_default 1, release = 0 (hold-to-preview needs the
//         release); 2 px edge + dot while the deck sits at the cue point.
// PLAY acts on press: the lift is latency when dropping on the beat.
// PLAY and CUE are dimmed and inert while the deck has no track.
//   pfl:  headphone cue toggle; 2 px edge + dot while routed.
Item {
    id: root

    required property int deckNumber
    property string variant: "play"

    readonly property string group: "[Channel" + deckNumber + "]"
    readonly property color accent: OD.Tokens.deckColor(deckNumber)
    readonly property bool isPlay: variant === "play"
    readonly property bool isCue: variant === "cue"
    readonly property bool isPfl: variant === "pfl"
    readonly property bool engaged: isPlay && play.value > 0
    readonly property var player: Mixxx.PlayerManager.getPlayer(group)
    readonly property bool loaded: player ? player.isLoaded : false
    // cue_indicator blinks while paused *away* from the cue, so it can't say
    // "at the cue". Compare positions instead (cue_point is in stereo samples).
    readonly property real cueSeconds: sampleRate.value > 0 ? cuePoint.value / (2 * sampleRate.value) : -1
    readonly property bool atCue: loaded && cuePoint.value >= 0 && cueSeconds >= 0 &&
        Math.abs(playPosition.value * duration.value - cueSeconds) <= 0.02
    readonly property bool modeOn: (isCue && atCue) || (isPfl && pfl.value > 0)
    readonly property bool pressed: tap.pressed
    readonly property color ink: engaged ? OD.Tokens.ground :
        modeOn ? accent : isPfl ? OD.Tokens.textSecondary : OD.Tokens.text

    Accessible.name: isPlay ? (engaged ? "Pause" : "Play") : isCue ? "Cue" : "Headphone cue"
    Accessible.role: Accessible.Button
    enabled: isPfl || loaded
    implicitHeight: OD.Tokens.layout.hTransport
    opacity: enabled ? 1 : OD.Tokens.opacityDisabled
    implicitWidth: isPlay ? OD.Tokens.layout.wPlay : isCue ? OD.Tokens.layout.wCue : OD.Tokens.layout.wPfl

    // The glyph and label order is the same on both decks; only the row of
    // buttons is mirrored (by DeckPanel).
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    Mixxx.ControlProxy { id: play; group: root.group; key: "play" }
    Mixxx.ControlProxy { id: cue; group: root.group; key: "cue_default" }
    Mixxx.ControlProxy { id: cuePoint; group: root.group; key: "cue_point" }
    Mixxx.ControlProxy { id: playPosition; group: root.group; key: "playposition" }
    Mixxx.ControlProxy { id: duration; group: root.group; key: "duration" }
    Mixxx.ControlProxy { id: sampleRate; group: root.group; key: "track_samplerate" }
    Mixxx.ControlProxy { id: pfl; group: root.group; key: "pfl" }

    Rectangle {
        anchors.fill: parent
        border.color: root.engaged || root.modeOn ? root.accent :
            root.pressed ? OD.Tokens.textSecondary : OD.Tokens.edge
        border.width: root.modeOn ? OD.Tokens.b2 : OD.Tokens.b1
        color: root.engaged ? root.accent : root.pressed ? OD.Tokens.raised : OD.Tokens.panel
        radius: OD.Tokens.r.r2

        Behavior on color { ColorAnimation { duration: OD.Tokens.durFast } }
        Behavior on border.color { ColorAnimation { duration: OD.Tokens.durFast } }
    }

    // Mode dot, same place as on the badges.
    Rectangle {
        color: root.accent
        height: OD.Tokens.layout.dot
        radius: OD.Tokens.r.pill
        visible: root.modeOn
        width: OD.Tokens.layout.dot
        x: OD.Tokens.s.s2
        y: OD.Tokens.s.s2
    }

    // PLAY / PAUSE and CUE: glyph (play only) + uppercase label.
    Row {
        anchors.centerIn: parent
        spacing: OD.Tokens.s.s3
        visible: !root.isPfl

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            ink: root.ink
            kind: root.engaged ? "pause" : "play"
            visible: root.isPlay
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.ink
            font.capitalization: Font.AllUppercase
            font.family: OD.Tokens.sans
            font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.body, OD.Tokens.ls.label)
            font.pixelSize: OD.Tokens.fs.body
            font.weight: OD.Tokens.fw.bold
            lineHeight: OD.Tokens.lh.body
            lineHeightMode: Text.FixedHeight
            text: root.isCue ? "Cue" : root.engaged ? "Pause" : "Play"
        }
    }

    // PFL: headphones over a small caption.
    Column {
        anchors.centerIn: parent
        visible: root.isPfl

        Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            ink: root.ink
            kind: "phones"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.ink
            font.family: OD.Tokens.sans
            font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.caption, OD.Tokens.ls.label)
            font.pixelSize: OD.Tokens.fs.caption
            font.weight: OD.Tokens.fw.semibold
            lineHeight: OD.Tokens.lh.caption
            lineHeightMode: Text.FixedHeight
            text: "PFL"
        }
    }

    // Drawn in the current ink so no icon font or image is needed (shapes
    // follow the frame's SVGs: 16 box for play/pause, 24 box for headphones).
    component Glyph: Canvas {
        id: glyph

        property color ink: OD.Tokens.text
        property string kind: "play"

        height: kind === "phones" ? OD.Tokens.layout.glyphM : OD.Tokens.layout.glyphS
        width: height

        onInkChanged: requestPaint()
        onKindChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = ink;
            ctx.strokeStyle = ink;
            if (kind === "phones") {
                const u = width / 24;
                ctx.lineWidth = 2 * u;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(3 * u, 16 * u);
                ctx.lineTo(3 * u, 11 * u);
                ctx.arc(12 * u, 11 * u, 9 * u, Math.PI, 2 * Math.PI);
                ctx.lineTo(21 * u, 16 * u);
                ctx.stroke();
                ctx.beginPath();
                ctx.roundedRect(1.5 * u, 13 * u, 6 * u, 8 * u, 2 * u, 2 * u);
                ctx.fill();
                ctx.beginPath();
                ctx.roundedRect(16.5 * u, 13 * u, 6 * u, 8 * u, 2 * u, 2 * u);
                ctx.fill();
            } else if (kind === "pause") {
                const u = width / 16;
                ctx.fillRect(2.5 * u, 1.5 * u, 4 * u, 13 * u);
                ctx.fillRect(9.5 * u, 1.5 * u, 4 * u, 13 * u);
            } else {
                const u = width / 16;
                ctx.beginPath();
                ctx.moveTo(3 * u, 1.5 * u);
                ctx.lineTo(3 * u, 14.5 * u);
                ctx.lineTo(14 * u, 8 * u);
                ctx.closePath();
                ctx.fill();
            }
        }
        Component.onCompleted: requestPaint()
    }

    TapHandler {
        id: tap

        // Exclusive grab until release, so a wobbling thumb still counts. The
        // long-press limit is lifted (TapHandler would drop the tap after
        // ~0.8 s; an hour is "never").
        gesturePolicy: TapHandler.ReleaseWithinBounds
        longPressThreshold: 3600

        onPressedChanged: {
            if (root.isCue)
                cue.value = pressed ? 1 : 0;
            else if (root.isPlay && pressed)
                play.value = play.value > 0 ? 0 : 1;
        }
        onTapped: if (root.isPfl) pfl.value = pfl.value > 0 ? 0 : 1
    }
}
