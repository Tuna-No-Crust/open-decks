import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import "." as OD

// One row of the track table (or its header when `header` is true): colour
// dot, title, artist, BPM, key, time, and two small load buttons. Press and
// move to drag the track towards a deck edge.
Rectangle {
    id: root

    property bool header: false
    property int row: -1
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackBpm: ""
    property string trackKey: ""
    property string trackDuration: ""
    property color trackColor: "transparent"
    property int hotCues: 0
    property int memoryCues: 0
    property bool dimmed: false
    // The controller's selection (Options + D-pad), highlighted.
    property bool selected: false
    // Header only: which column is sorted.
    property string sortRole: ""
    property bool sortDescending: false

    signal loadRequested(int deck)
    signal tapped()
    signal sortRequested(string role)
    signal dragStarted(real x, real y)
    signal dragMoved(real x, real y)
    signal dragEnded()

    color: header ? "transparent" : (press.pressed ? OD.Tokens.raised : (selected ? OD.Tokens.selected : "transparent"))
    // The header's labels are the sort buttons: thumb-sized (user, 2026-10-26).
    implicitHeight: header ? OD.Tokens.minTouch + 4 : 48
    opacity: dimmed ? 0.4 : 1

    Rectangle {
        anchors.bottom: parent.bottom
        color: root.header ? "#22262E" : OD.Tokens.line
        height: 1
        width: parent.width
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        spacing: 12

        Item {
            implicitHeight: 10
            implicitWidth: 10

            Rectangle {
                anchors.centerIn: parent
                color: root.trackColor
                height: 10
                radius: 5
                visible: !root.header && root.trackColor.a > 0
                width: 10
            }
        }
        OD.TrackCell { Layout.fillWidth: true; Layout.minimumWidth: 80; header: root.header; role: "title"; label: "TITLE"; text: root.trackTitle; weight: Font.Medium; onSortRequested: r => root.sortRequested(r); sortRole: root.sortRole; sortDescending: root.sortDescending }
        OD.TrackCell { Layout.preferredWidth: 180; header: root.header; role: "artist"; label: "ARTIST"; text: root.trackArtist; muted: true; onSortRequested: r => root.sortRequested(r); sortRole: root.sortRole; sortDescending: root.sortDescending }
        OD.TrackCell { Layout.preferredWidth: 72; header: root.header; role: "bpm"; label: "BPM"; text: root.trackBpm; mono: true; align: Text.AlignRight; onSortRequested: r => root.sortRequested(r); sortRole: root.sortRole; sortDescending: root.sortDescending }
        OD.TrackCell { Layout.preferredWidth: 56; header: root.header; role: "key"; label: "KEY"; text: root.trackKey; mono: true; soft: true; onSortRequested: r => root.sortRequested(r); sortRole: root.sortRole; sortDescending: root.sortDescending }
        OD.TrackCell { Layout.preferredWidth: 56; header: root.header; role: "duration"; label: "TIME"; text: root.trackDuration; mono: true; muted: true; align: Text.AlignRight; onSortRequested: r => root.sortRequested(r); sortRole: root.sortRole; sortDescending: root.sortDescending }

        // Cue indicator: hot cue count in the deck-pad style, memory cues as
        // a small count beside it; dim dash when the track has neither.
        Item {
            Layout.preferredHeight: 24
            Layout.preferredWidth: 58

            Text {
                anchors.fill: parent
                color: OD.Tokens.textMuted
                font.bold: true
                font.letterSpacing: 1
                font.pixelSize: 11
                text: "CUES"
                verticalAlignment: Text.AlignVCenter
                visible: root.header
            }
            RowLayout {
                anchors.fill: parent
                spacing: 4
                visible: !root.header

                Rectangle {
                    Layout.preferredHeight: 22
                    Layout.preferredWidth: 26
                    color: root.hotCues > 0 ? OD.Tokens.hotcuePalette[0] : "transparent"
                    border.color: root.hotCues > 0 ? "transparent" : OD.Tokens.selected
                    border.width: 1
                    radius: 6

                    Text {
                        anchors.centerIn: parent
                        color: root.hotCues > 0 ? OD.Tokens.ground : OD.Tokens.textSubtle
                        font.bold: true
                        font.family: OD.Tokens.mono
                        font.pixelSize: 11
                        text: root.hotCues > 0 ? root.hotCues : "–"
                    }
                }
                Text {
                    color: OD.Tokens.textSubtle
                    font.family: OD.Tokens.mono
                    font.pixelSize: 11
                    text: root.memoryCues > 0 ? "+" + root.memoryCues : ""
                }
            }
        }

        // Load buttons: a tap alternative to dragging.
        Repeater {
            model: 2

            Button {
                id: load

                required property int index
                readonly property int deck: index + 1

                Layout.preferredHeight: 36
                Layout.preferredWidth: 36
                Accessible.name: "Load to deck " + deck
                visible: !root.header

                onClicked: root.loadRequested(deck)

                background: Rectangle {
                    border.color: OD.Tokens.deckColor(load.deck)
                    border.width: 1
                    color: load.down ? OD.Tokens.deckColor(load.deck) : OD.Tokens.raised
                    radius: 8
                }
                contentItem: Text {
                    color: load.down ? OD.Tokens.ground : OD.Tokens.deckColor(load.deck)
                    font.bold: true
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    text: load.deck
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        Item {
            Layout.preferredWidth: 84
            visible: root.header
        }
    }

    // Press anywhere else on the row and move: drag. The load buttons sit on
    // top of this area, so they still take their taps.
    MouseArea {
        id: press

        property bool dragging: false
        // Once the finger has moved mostly up/down, this press is a scroll:
        // leave it to the list and never start a drag from it.
        property bool scrolling: false
        property real startX: 0
        property real startY: 0

        anchors.fill: parent
        anchors.rightMargin: 96
        enabled: !root.header
        preventStealing: dragging
        z: -1

        onPressed: mouse => {
            startX = mouse.x;
            startY = mouse.y;
            dragging = false;
            scrolling = false;
        }
        onPositionChanged: mouse => {
            if (!pressed || scrolling) {
                return;
            }
            if (!dragging) {
                const dx = Math.abs(mouse.x - startX);
                const dy = Math.abs(mouse.y - startY);
                if (dy > 10 && dy > dx) {
                    scrolling = true; // the list takes over (it steals the grab)
                    return;
                }
                if (dx > 16 && dx > dy * 1.5) {
                    dragging = true;
                    root.dragStarted(mouse.x, mouse.y);
                }
            }
            if (dragging) {
                root.dragMoved(mouse.x, mouse.y);
            }
        }
        onReleased: {
            if (dragging) {
                dragging = false;
                root.dragEnded();
            } else if (!scrolling) {
                root.tapped();
            }
        }
        onCanceled: {
            if (dragging) {
                dragging = false;
                root.dragEnded();
            }
        }
    }
}
