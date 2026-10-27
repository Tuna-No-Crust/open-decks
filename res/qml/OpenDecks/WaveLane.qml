import ".." as Skin
import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import "." as OD
import "camelot.js" as Camelot

// One deck's full-width scrolling waveform plus its overview strip (Mixxx's
// own renderer for now; rekordbox's stored colour waveforms come later). The
// lane is a flat band: no radius, a hairline under it. The tag at the deck's
// own edge (deck 1 left, deck 2 right) carries number, BPM and key.
Item {
    id: root

    required property int deckNumber
    // Slim strip without the overview, for screens where the waveform is a
    // glance (Library, FX); its tag also names the track.
    property bool compact: false
    readonly property string group: "[Channel" + deckNumber + "]"
    readonly property color accent: OD.Tokens.deckColor(deckNumber)
    readonly property var player: Mixxx.PlayerManager.getPlayer(group)
    readonly property bool loaded: player?.isLoaded ?? false
    readonly property bool focused: OD.UiState.focus === root.deckNumber

    implicitHeight: compact ? OD.Tokens.layout.hLaneCompact : OD.Tokens.layout.hLane
    implicitWidth: OD.Tokens.layout.wFrame

    Mixxx.ControlProxy { id: bpm; group: root.group; key: "bpm" }

    Rectangle {
        anchors.fill: parent
        clip: true
        color: OD.Tokens.lane

        Skin.WaveformDisplay {
            group: root.group
            height: root.compact ? OD.Tokens.layout.hWaveCompact : OD.Tokens.layout.hWave
            width: parent.width
            y: OD.Tokens.s.s2
        }
        Skin.WaveformOverview {
            group: root.group
            height: OD.Tokens.layout.hOverview
            visible: !root.compact
            width: parent.width
            y: OD.Tokens.s.s2 + OD.Tokens.layout.hWave + OD.Tokens.s.s1
        }

        // Hairline under the lane.
        Rectangle {
            anchors.bottom: parent.bottom
            color: OD.Tokens.line
            height: OD.Tokens.b1
            width: parent.width
        }

        // Tag: opaque, so it never fights the waveform for contrast.
        Rectangle {
            anchors.left: root.deckNumber === 1 ? parent.left : undefined
            anchors.right: root.deckNumber === 1 ? undefined : parent.right
            color: OD.Tokens.lane
            height: OD.Tokens.layout.hTag
            width: tagRow.implicitWidth + 2 * OD.Tokens.s.s2
            y: OD.Tokens.s.s2

            Row {
                id: tagRow

                anchors.centerIn: parent
                spacing: OD.Tokens.s.s2

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: OD.Tokens.text
                    font.family: OD.Tokens.mono
                    font.pixelSize: OD.Tokens.fs.label
                    font.weight: OD.Tokens.fw.semibold
                    text: root.deckNumber
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: OD.Tokens.textSecondary
                    elide: Text.ElideRight
                    font.family: OD.Tokens.mono
                    font.pixelSize: OD.Tokens.fs.label
                    font.weight: OD.Tokens.fw.semibold
                    text: [root.player?.currentTrack?.title, root.player?.currentTrack?.artist]
                        .filter(s => s).join(" · ")
                    visible: root.compact && root.loaded
                    width: Math.min(implicitWidth, root.width / 3)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.loaded ? OD.Tokens.textSecondary : OD.Tokens.textMuted
                    font.family: OD.Tokens.mono
                    font.pixelSize: OD.Tokens.fs.label
                    font.weight: OD.Tokens.fw.semibold
                    text: root.loaded ? bpm.value.toFixed(2) : "No track"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: OD.Tokens.textMuted
                    font.family: OD.Tokens.mono
                    font.pixelSize: OD.Tokens.fs.label
                    font.weight: OD.Tokens.fw.semibold
                    text: Camelot.camelot(root.player?.currentTrack?.keyText)
                    visible: root.loaded && text !== ""
                }
            }
        }

        // Focus: inside the lane, no fade over the waveform.
        Rectangle {
            anchors.fill: parent
            border.color: root.accent
            border.width: OD.Tokens.b2
            color: "transparent"
            visible: root.focused
            z: 4
        }

        // Focus on touch-down. Sits above the waveform but only grabs
        // passively, so the press still reaches the waveform's own handling.
        Item {
            anchors.fill: parent
            z: 5

            TapHandler {
                gesturePolicy: TapHandler.DragThreshold
                onPressedChanged: if (pressed) OD.UiState.focusDeck(root.deckNumber)
            }
        }
    }
}
