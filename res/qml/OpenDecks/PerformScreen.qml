import QtQuick 2.12
import "." as OD

// The default screen (1280 x 700 under the top bar): both waveform lanes
// stacked full width, then deck 1 | mixer | deck 2. No margins: the lanes run
// edge to edge and the deck panels are the 400 px thumb zones at the sides.
Item {
    id: root

    OD.WaveLane {
        id: lane1

        deckNumber: 1
        height: implicitHeight
        width: parent.width
    }
    OD.WaveLane {
        id: lane2

        anchors.top: lane1.bottom
        deckNumber: 2
        height: implicitHeight
        width: parent.width
    }

    Item {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: lane2.bottom

        // Deck 2's panel is mirrored, which would also mirror its own anchors,
        // so each panel fills a plain slot that is anchored here.
        Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.top: parent.top
            width: OD.Tokens.layout.wZone

            OD.DeckPanel {
                anchors.fill: parent
                deckNumber: 1
            }
        }

        // Centre: controller legend at the top, the mixer in the lower half
        // (x 400-880, y >= 400 of the frame), nothing in between for a thumb
        // to land on by accident.
        Item {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: OD.Tokens.layout.wMixer

            Text {
                color: OD.Tokens.textMuted
                font.family: OD.Tokens.sans
                font.pixelSize: OD.Tokens.fs.caption
                font.weight: OD.Tokens.fw.medium
                horizontalAlignment: Text.AlignHCenter
                lineHeight: OD.Tokens.lh.caption
                lineHeightMode: Text.FixedHeight
                text: "L2 ↕ fader ↔ FX · R2 ↕ EQ ↔ filter"
                width: parent.width
                y: OD.Tokens.s.s2
            }
            OD.MixerPanel {
                anchors.bottom: parent.bottom
                height: OD.Tokens.layout.hFrame / 2
                width: parent.width
            }
        }

        Item {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.top: parent.top
            width: OD.Tokens.layout.wZone

            OD.DeckPanel {
                anchors.fill: parent
                deckNumber: 2
            }
        }
    }
}
