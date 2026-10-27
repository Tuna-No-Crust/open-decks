import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Layouts
import "." as OD
import "camelot.js" as Camelot

// One deck's touch panel (400 x 492): tempo fader at the outer edge, then a
// 316 px column: framed track module, badges, transport, eight hot cue pads,
// loop chips. Deck 2 is mirrored so its tempo fader, PLAY and the module's
// outer side sit at the right edge, under the right thumb; pads, loops and
// badges opt out so they still read A→H, ¼→16 and SYNC→KEY LOCK.
// Every size is fixed: 8+176+8+44+8+56+8+124+8+44+8 = 492, so nothing can
// squeeze the loop chips off the bottom of the screen. (Owner, 2026-10-27:
// the pads grew 48 -> 60; the module's time row 64 -> 48 and the transport
// row 64 -> 56 paid for it.)
Item {
    id: root

    required property int deckNumber
    readonly property string group: "[Channel" + deckNumber + "]"
    readonly property color accent: OD.Tokens.deckColor(deckNumber)
    readonly property bool mirrored: deckNumber % 2 === 0

    readonly property var player: Mixxx.PlayerManager.getPlayer(group)
    readonly property var track: player ? player.currentTrack : null
    readonly property bool loaded: player ? player.isLoaded : false
    readonly property bool focused: OD.UiState.focus === root.deckNumber
    readonly property bool fxOn: fx1.value > 0 || fx2.value > 0 || fx3.value > 0 || fx4.value > 0

    LayoutMirroring.enabled: mirrored
    LayoutMirroring.childrenInherit: true

    function formatTime(seconds) {
        const s = Math.max(0, Math.round(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    Mixxx.ControlProxy { id: bpm; group: root.group; key: "bpm" }
    Mixxx.ControlProxy { id: playPosition; group: root.group; key: "playposition" }
    Mixxx.ControlProxy { id: duration; group: root.group; key: "duration" }
    Mixxx.ControlProxy { id: play; group: root.group; key: "play" }
    Mixxx.ControlProxy { id: sync; group: root.group; key: "sync_enabled" }
    Mixxx.ControlProxy { id: leader; group: root.group; key: "sync_leader" }
    Mixxx.ControlProxy { id: keylock; group: root.group; key: "keylock" }
    // [OpenDecks] vinylN only exists in builds that register it; elsewhere it logs
    // "does not exist" and reads 0.
    Mixxx.ControlProxy { id: vinyl; group: "[OpenDecks]"; key: "vinyl" + root.deckNumber }
    // FX is lit when any of the four units is routed to this deck.
    Mixxx.ControlProxy { id: fx1; group: "[EffectRack1_EffectUnit1]"; key: "group_" + root.group + "_enable" }
    Mixxx.ControlProxy { id: fx2; group: "[EffectRack1_EffectUnit2]"; key: "group_" + root.group + "_enable" }
    Mixxx.ControlProxy { id: fx3; group: "[EffectRack1_EffectUnit3]"; key: "group_" + root.group + "_enable" }
    Mixxx.ControlProxy { id: fx4; group: "[EffectRack1_EffectUnit4]"; key: "group_" + root.group + "_enable" }

    OD.TempoFader {
        anchors.left: parent.left
        anchors.leftMargin: OD.Tokens.s.s2
        deckNumber: root.deckNumber
        height: parent.height - 2 * OD.Tokens.s.s2
        y: OD.Tokens.s.s2
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.leftMargin: OD.Tokens.s.s2 + OD.Tokens.layout.wTempo + OD.Tokens.s.s2
        spacing: OD.Tokens.s.s2
        width: OD.Tokens.layout.wContent
        y: OD.Tokens.s.s2

        // --- Track module: the one framed box on Perform.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: OD.Tokens.layout.hModule
            border.color: OD.Tokens.line
            border.width: OD.Tokens.b1
            color: OD.Tokens.lane
            radius: OD.Tokens.r.r2

            Item {
                anchors.fill: parent
                // The 1 px frame sits inside the 176 (border-box): 176 - 2*8 = 160 = the rows.
                anchors.margins: OD.Tokens.s.s2

                // Title over artist.
                Column {
                    height: OD.Tokens.layout.hTextblock
                    width: parent.width

                    Text {
                        color: OD.Tokens.text
                        elide: Text.ElideRight
                        font.family: OD.Tokens.sans
                        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.title, OD.Tokens.ls.title)
                        font.pixelSize: OD.Tokens.fs.title
                        font.weight: OD.Tokens.fw.semibold
                        horizontalAlignment: Text.AlignLeft
                        lineHeight: OD.Tokens.lh.title
                        lineHeightMode: Text.FixedHeight
                        text: root.loaded ? (root.track?.title || "Untitled") : "No track loaded"
                        width: parent.width
                    }
                    Text {
                        color: OD.Tokens.textMuted
                        elide: Text.ElideRight
                        font.family: OD.Tokens.sans
                        font.pixelSize: OD.Tokens.fs.body
                        font.weight: OD.Tokens.fw.regular
                        horizontalAlignment: Text.AlignLeft
                        lineHeight: OD.Tokens.lh.body
                        lineHeightMode: Text.FixedHeight
                        text: root.loaded ? (root.track?.artist ?? "") : "Drag a track here"
                        width: parent.width
                    }
                }

                // Remaining time at the outer side, status dots at the inner.
                Item {
                    height: OD.Tokens.layout.hTimerow
                    width: parent.width
                    y: OD.Tokens.layout.hTextblock + OD.Tokens.s.s2

                    Text {
                        anchors.left: parent.left
                        color: OD.Tokens.text
                        font.family: OD.Tokens.mono
                        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.display, OD.Tokens.ls.tight)
                        font.pixelSize: OD.Tokens.fs.display
                        font.weight: OD.Tokens.fw.semibold
                        fontSizeMode: Text.HorizontalFit // -12:34 would not fit 196 px
                        height: OD.Tokens.layout.hTimerow
                        horizontalAlignment: Text.AlignLeft
                        // The 64 px digits sit on a 48 px line (ink is ~45 px).
                        lineHeight: OD.Tokens.layout.hTimerow
                        lineHeightMode: Text.FixedHeight
                        minimumPixelSize: OD.Tokens.fs.title
                        text: root.loaded ? "-" + root.formatTime(duration.value * (1 - playPosition.value)) : "--:--"
                        verticalAlignment: Text.AlignVCenter
                        width: OD.Tokens.layout.wTime
                    }
                    Column {
                        anchors.right: parent.right
                        width: OD.Tokens.layout.wStatus

                        StatusLine { accent: root.accent; label: play.value > 0 ? "Playing" : "Paused"; lit: play.value > 0 }
                        StatusLine { accent: root.accent; label: "Leader"; lit: leader.value > 0 }
                        StatusLine { accent: root.accent; label: "FX"; lit: root.fxOn }
                    }
                }

                // BPM and key on one baseline; "BPM" and "KEY" sit s2 above it.
                Row {
                    id: bpmRow

                    // Same order on both decks, flush with the outer edge.
                    LayoutMirroring.enabled: false
                    LayoutMirroring.childrenInherit: true
                    anchors.left: root.mirrored ? undefined : parent.left
                    anchors.right: root.mirrored ? parent.right : undefined
                    height: OD.Tokens.layout.hBpmrow
                    y: OD.Tokens.layout.hTextblock + OD.Tokens.s.s2 + OD.Tokens.layout.hTimerow + OD.Tokens.s.s1

                    readonly property real base: bpmValue.baselineOffset

                    Text {
                        color: OD.Tokens.textMuted
                        font.capitalization: Font.AllUppercase
                        font.family: OD.Tokens.sans
                        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.caption, OD.Tokens.ls.label)
                        font.pixelSize: OD.Tokens.fs.caption
                        font.weight: OD.Tokens.fw.semibold
                        rightPadding: OD.Tokens.s.s2
                        text: "BPM"
                        y: bpmRow.base - OD.Tokens.s.s2 - baselineOffset
                    }
                    Text {
                        id: bpmValue

                        color: OD.Tokens.text
                        font.family: OD.Tokens.mono
                        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.readout, OD.Tokens.ls.tight)
                        font.pixelSize: OD.Tokens.fs.readout
                        font.weight: OD.Tokens.fw.semibold
                        lineHeight: OD.Tokens.lh.readout
                        lineHeightMode: Text.FixedHeight
                        text: root.loaded ? bpm.value.toFixed(2) : "---.--"
                    }
                    Text {
                        color: OD.Tokens.textMuted
                        font.capitalization: Font.AllUppercase
                        font.family: OD.Tokens.sans
                        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.caption, OD.Tokens.ls.label)
                        font.pixelSize: OD.Tokens.fs.caption
                        font.weight: OD.Tokens.fw.semibold
                        leftPadding: OD.Tokens.s.s3
                        rightPadding: OD.Tokens.s.s2
                        text: "Key"
                        visible: keyValue.text !== ""
                        y: bpmRow.base - OD.Tokens.s.s2 - baselineOffset
                    }
                    Text {
                        id: keyValue

                        color: OD.Tokens.text
                        font.family: OD.Tokens.mono
                        font.pixelSize: OD.Tokens.fs.body
                        font.weight: OD.Tokens.fw.semibold
                        // Mixxx formats keyText in the user's notation; show Camelot.
                        text: root.loaded ? Camelot.camelot(root.track?.keyText) : ""
                        y: bpmRow.base - baselineOffset
                    }
                }
            }
        }

        // --- Badges: tappable modes, left-aligned on both decks.
        Row {
            Layout.fillWidth: true
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true
            spacing: OD.Tokens.s.s2

            OD.Badge {
                text: "SYNC"
                on: sync.value > 0
                onColor: root.accent
                tappable: true
                onTapped: sync.value = sync.value > 0 ? 0 : 1
            }
            OD.Badge {
                text: "VINYL"
                on: vinyl.value > 0
                onColor: root.accent
                tappable: true
                onTapped: vinyl.value = vinyl.value > 0 ? 0 : 1
            }
            OD.Badge {
                text: "KEY LOCK"
                on: keylock.value > 0
                onColor: root.accent
                tappable: true
                onTapped: keylock.value = keylock.value > 0 ? 0 : 1
            }
        }

        // --- Transport: PLAY at the outer edge (mirroring reverses deck 2).
        Row {
            Layout.fillWidth: true
            spacing: OD.Tokens.s.s2

            OD.TransportButton { deckNumber: root.deckNumber; variant: "play" }
            OD.TransportButton { deckNumber: root.deckNumber; variant: "cue" }
            OD.TransportButton { deckNumber: root.deckNumber; variant: "pfl" }
        }

        // --- Hot cue pads, A→H on both decks.
        Grid {
            Layout.fillWidth: true
            columns: 4
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true
            spacing: OD.Tokens.s.s1

            Repeater {
                model: 8

                OD.HotcuePad {
                    id: pad

                    required property int index

                    group: root.group
                    number: pad.index + 1
                }
            }
        }

        // --- Loop chips, ¼→16 on both decks, one segmented strip.
        Row {
            Layout.fillWidth: true
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            Repeater {
                model: [
                    { beats: 0.25, label: "¼" }, { beats: 0.5, label: "½" },
                    { beats: 1, label: "1" }, { beats: 2, label: "2" },
                    { beats: 4, label: "4" }, { beats: 8, label: "8" },
                    { beats: 16, label: "16" },
                ]

                OD.LoopChip {
                    id: chip

                    required property int index
                    required property var modelData

                    accent: root.accent
                    beats: chip.modelData.beats
                    first: chip.index === 0
                    group: root.group
                    label: chip.modelData.label
                    last: chip.index === 6
                }
            }
        }
    }

    // Focus: 2 px hue border inside the panel bounds, below the touch layer.
    Rectangle {
        anchors.fill: parent
        border.color: root.accent
        border.width: OD.Tokens.b2
        color: "transparent"
        visible: root.focused
        z: 4
    }

    // Focus on touch-down anywhere in the panel (pads included): a passive
    // handler above the content, so presses still reach the pads and chips.
    Item {
        anchors.fill: parent
        z: 5

        TapHandler {
            gesturePolicy: TapHandler.DragThreshold
            onPressedChanged: if (pressed) OD.UiState.focusDeck(root.deckNumber)
        }
    }

    // One PLAYING / LEADER / FX line of the module: a 6 px dot on the outer
    // side of the word. Unlit = ring in the edge colour, muted word; lit =
    // dot filled in the deck hue, bright word.
    component StatusLine: Item {
        // Inline components can't see the file's ids, hence the property.
        property color accent
        property string label
        property bool lit: false

        height: OD.Tokens.lh.caption
        width: OD.Tokens.layout.wStatus

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            border.color: parent.lit ? parent.accent : OD.Tokens.edge
            border.width: OD.Tokens.b1
            color: parent.lit ? parent.accent : "transparent"
            height: OD.Tokens.layout.dot
            radius: OD.Tokens.r.pill
            width: OD.Tokens.layout.dot
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: OD.Tokens.s.s3
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: parent.lit ? OD.Tokens.text : OD.Tokens.textMuted
            font.capitalization: Font.AllUppercase
            font.family: OD.Tokens.sans
            font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.caption, OD.Tokens.ls.label)
            font.pixelSize: OD.Tokens.fs.caption
            font.weight: OD.Tokens.fw.semibold
            horizontalAlignment: Text.AlignLeft
            lineHeight: OD.Tokens.lh.caption
            lineHeightMode: Text.FixedHeight
            text: parent.label
        }
    }
}
