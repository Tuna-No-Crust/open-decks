import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import "." as OD

// Library screen: slim waveforms, the rekordbox stick's playlists and a
// search on the left, the track table on the right. Drag a track to the
// left or right edge to load it to deck 1 / 2 (the drop zones appear while
// dragging); tapping a row's deck buttons does the same without a drag.
Item {
    id: root

    readonly property var rb: Mixxx.Rekordbox
    readonly property bool dragging: dragProxy.Drag.active
    property int dragRow: -1
    property string dragTitle: ""
    property string dragBpm: ""

    // Loading onto a playing deck is refused (like a CDJ): a notice instead.
    Mixxx.ControlProxy { id: play1; group: "[Channel1]"; key: "play" }
    Mixxx.ControlProxy { id: play2; group: "[Channel2]"; key: "play" }

    function deckPlaying(deck) {
        return (deck === 1 ? play1.value : play2.value) > 0;
    }
    function loadTo(row, deck) {
        if (deckPlaying(deck)) {
            OD.UiState.notify("Deck " + deck + " is playing — stop it before loading", OD.Tokens.deckColor(deck));
            return;
        }
        rb.loadTrack(row, deck);
    }

    // Controller browsing (Options + D-pad in the gamepad mapping): the same
    // [Library] / [ChannelN] controls the classic library listens to.
    property int selectedRow: -1

    // Push buttons the controller taps: act on the signalled value (the
    // control may be 0 again by the time this runs) and re-arm them.
    Mixxx.ControlProxy {
        id: moveUp

        group: "[Library]"
        key: "MoveUp"

        onValueChanged: (v) => { if (v > 0) { root.moveSelection(-1); moveUp.value = 0; } }
    }
    Mixxx.ControlProxy {
        id: moveDown

        group: "[Library]"
        key: "MoveDown"

        onValueChanged: (v) => { if (v > 0) { root.moveSelection(1); moveDown.value = 0; } }
    }
    Mixxx.ControlProxy {
        id: load1

        group: "[Channel1]"
        key: "LoadSelectedTrack"

        onValueChanged: (v) => { if (v > 0) { root.loadSelected(1); load1.value = 0; } }
    }
    Mixxx.ControlProxy {
        id: load2

        group: "[Channel2]"
        key: "LoadSelectedTrack"

        onValueChanged: (v) => { if (v > 0) { root.loadSelected(2); load2.value = 0; } }
    }
    Mixxx.ControlProxy { id: tabControl; group: "[OpenDecks]"; key: "tab" }

    function moveSelection(step) {
        const count = rb.tracks.count;
        if (count === 0) {
            return;
        }
        selectedRow = Math.max(0, Math.min(count - 1, selectedRow + step));
        table.positionViewAtIndex(selectedRow, ListView.Contain);
        tabControl.value = 1; // browsing shows the library
    }
    function loadSelected(deck) {
        if (selectedRow >= 0 && selectedRow < rb.tracks.count) {
            loadTo(selectedRow, deck);
        }
    }

    function pickFirstDevice() {
        if (rb.currentDevice === "" && rb.devices.length > 0) {
            rb.selectDevice(rb.devices[0].path);
        }
    }

    Connections {
        target: root.rb

        function onDevicesChanged() {
            root.pickFirstDevice();
        }
    }
    Component.onCompleted: pickFirstDevice()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.bottomMargin: 4
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            spacing: 8

            OD.WaveLane {
                Layout.fillWidth: true
                compact: true
                deckNumber: 1
            }
            OD.WaveLane {
                Layout.fillWidth: true
                compact: true
                deckNumber: 2
            }
        }

        RowLayout {
            Layout.bottomMargin: 12
            Layout.fillHeight: true
            Layout.fillWidth: true
            // Room at the edges for the drop zones (and the thumbs).
            Layout.leftMargin: 108
            Layout.rightMargin: 108
            Layout.topMargin: 4
            spacing: 12

            // ---- Sidebar: search, devices, playlists ----------------------
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 272
                color: OD.Tokens.panel
                radius: 12

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Text {
                        color: OD.Tokens.textMuted
                        font.bold: true
                        font.letterSpacing: 1
                        font.pixelSize: 11
                        text: "SEARCH"
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        border.color: search.activeFocus ? OD.Tokens.textSubtle : OD.Tokens.selected
                        color: OD.Tokens.lane
                        implicitHeight: OD.Tokens.minTouch
                        radius: 8

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                color: OD.Tokens.textMuted
                                font.pixelSize: 15
                                text: "⌕"
                            }
                            TextField {
                                id: search

                                Layout.fillWidth: true
                                background: null
                                color: OD.Tokens.text
                                font.pixelSize: 14
                                placeholderText: "Title, artist, album"
                                placeholderTextColor: OD.Tokens.textSubtle

                                onTextChanged: root.rb.tracks.search(text)
                            }
                            OD.IconButton {
                                glyph: "×"
                                implicitHeight: 28
                                implicitWidth: 28
                                visible: search.text !== ""

                                onClicked: search.text = ""
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        color: OD.Tokens.textMuted
                        elide: Text.ElideRight
                        font.bold: true
                        font.letterSpacing: 1
                        font.pixelSize: 11
                        text: "REKORDBOX"
                    }
                    // A full-width, thumb-sized button (the old 28 px icon was
                    // too small to hit on the Deck), doubling as the busy state.
                    Button {
                        id: refreshButton

                        Layout.fillWidth: true
                        Layout.preferredHeight: OD.Tokens.minTouch
                        Accessible.name: "Look for sticks again"
                        enabled: !root.rb.loading

                        onClicked: root.rb.refresh()

                        background: Rectangle {
                            border.color: OD.Tokens.selected
                            color: refreshButton.down ? OD.Tokens.selected : OD.Tokens.raised
                            radius: 8
                        }
                        contentItem: Text {
                            color: root.rb.loading ? OD.Tokens.textMuted : OD.Tokens.text
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            text: root.rb.loading ? "Looking for sticks…" : "↻  Look for sticks"
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    ListView {
                        id: sidebar

                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        model: ListModel {
                            id: sidebarModel
                        }
                        spacing: 2

                        // Devices first, then the current device's playlists.
                        function rebuild() {
                            sidebarModel.clear();
                            const devices = root.rb.devices;
                            for (const d of devices) {
                                sidebarModel.append({ kind: "device", name: d.name, path: d.path, depth: 0, folder: false });
                                if (d.path === root.rb.currentDevice) {
                                    sidebarModel.append({ kind: "all", name: "All tracks", path: d.path, depth: 1, folder: false });
                                    for (const p of root.rb.playlists) {
                                        sidebarModel.append({ kind: "playlist", name: p.name, path: p.path, depth: p.depth + 1, folder: p.folder });
                                    }
                                }
                            }
                        }

                        Component.onCompleted: rebuild()

                        Connections {
                            target: root.rb

                            function onDevicesChanged() { sidebar.rebuild(); }
                            function onPlaylistsChanged() { sidebar.rebuild(); }
                            function onCurrentChanged() { sidebar.rebuild(); }
                        }

                        delegate: Button {
                            id: row

                            required property string kind
                            required property string name
                            required property string path
                            required property int depth
                            required property bool folder

                            readonly property bool selected: kind !== "device" && path === root.rb.currentPlaylist
                            readonly property bool isDevice: kind === "device"

                            height: OD.Tokens.minTouch
                            width: sidebar.width
                            Accessible.name: name

                            onClicked: {
                                if (isDevice) {
                                    root.rb.selectDevice(path);
                                } else {
                                    root.rb.selectPlaylist(path);
                                }
                            }

                            background: Rectangle {
                                color: row.selected ? OD.Tokens.selected : (row.down ? OD.Tokens.raised : "transparent")
                                radius: 8
                            }
                            contentItem: RowLayout {
                                spacing: 8

                                Item { implicitWidth: 4 + 14 * Math.max(0, row.depth - 1) }
                                Text {
                                    color: OD.Tokens.textMuted
                                    font.pixelSize: 13
                                    text: row.isDevice ? "▣" : (row.folder ? "▸" : "")
                                    visible: text !== ""
                                }
                                Text {
                                    Layout.fillWidth: true
                                    color: row.isDevice ? OD.Tokens.textMuted : (row.selected ? OD.Tokens.text : OD.Tokens.textSoft)
                                    elide: Text.ElideRight
                                    font.bold: row.isDevice
                                    font.letterSpacing: row.isDevice ? 1 : 0
                                    font.pixelSize: row.isDevice ? 11 : 14
                                    text: row.isDevice ? row.name.toUpperCase() : row.name
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            color: OD.Tokens.textSubtle
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            text: root.rb.loading ? "Reading the stick…" : "No rekordbox stick found.\nPlug one in and tap ↻."
                            visible: sidebarModel.count === 0
                            width: parent.width - 16
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ---- Track table --------------------------------------------
            Rectangle {
                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                color: OD.Tokens.panel
                radius: 12

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    OD.TrackRow {
                        Layout.fillWidth: true
                        header: true
                        sortRole: table.sortRole
                        sortDescending: table.sortDescending

                        onSortRequested: role => {
                            if (table.sortRole === role) {
                                table.sortDescending = !table.sortDescending;
                            } else {
                                table.sortRole = role;
                                table.sortDescending = false;
                            }
                            root.rb.tracks.sortBy(table.sortRole, table.sortDescending);
                        }
                    }
                    ListView {
                        id: table

                        property string sortRole: ""
                        property bool sortDescending: false

                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        model: root.rb.tracks

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: OD.TrackRow {
                            required property int index
                            required property var model

                            dimmed: root.dragging && root.dragRow === index
                            row: index
                            selected: root.selectedRow === index
                            trackArtist: model.artist ?? ""
                            trackBpm: model.bpm ?? ""
                            trackColor: model.color ?? "transparent"
                            trackDuration: model.duration ?? ""
                            trackKey: model.key ?? ""
                            trackTitle: model.title ?? ""
                            hotCues: model.hotcues ?? 0
                            memoryCues: model.memcues ?? 0
                            width: table.width

                            onLoadRequested: deck => root.loadTo(index, deck)
                            onTapped: root.selectedRow = index
                            onDragStarted: (x, y) => {
                                root.dragRow = index;
                                root.dragTitle = model.title ?? "";
                                root.dragBpm = model.bpm ?? "";
                                dragProxy.begin(mapToItem(root, x, y));
                            }
                            onDragMoved: (x, y) => dragProxy.move(mapToItem(root, x, y))
                            onDragEnded: dragProxy.end()
                        }

                        Text {
                            anchors.centerIn: parent
                            color: OD.Tokens.textSubtle
                            font.pixelSize: 14
                            text: root.rb.loading ? "Reading the rekordbox export…" : (root.rb.currentDevice === "" ? "Pick a stick on the left" : "No tracks")
                            visible: table.count === 0
                        }
                    }
                }
            }
        }
    }

    // ---- Drop zones + drag ghost ---------------------------------------
    Repeater {
        model: 2

        Rectangle {
            id: zone

            required property int index
            readonly property int deck: index + 1
            readonly property color accent: OD.Tokens.deckColor(deck)
            readonly property bool hot: root.dragging && dragProxy.x >= x && dragProxy.x <= x + width
            readonly property bool playing: root.deckPlaying(deck)

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            anchors.left: deck === 1 ? parent.left : undefined
            anchors.leftMargin: 12
            anchors.right: deck === 2 ? parent.right : undefined
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 80
            border.color: playing ? OD.Tokens.danger : accent
            border.width: 2
            color: playing ? Qt.rgba(1, 0.36, 0.36, 0.12) : (hot ? Qt.rgba(accent.r, accent.g, accent.b, 0.3) : Qt.rgba(accent.r, accent.g, accent.b, 0.14))
            opacity: root.dragging ? 1 : 0
            radius: 12
            width: 84

            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    color: zone.accent
                    implicitHeight: 40
                    implicitWidth: 40
                    radius: 10

                    Text {
                        anchors.centerIn: parent
                        color: OD.Tokens.ground
                        font.bold: true
                        font.pixelSize: 20
                        text: zone.deck
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    color: zone.playing ? OD.Tokens.danger : OD.Tokens.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    text: zone.playing ? "Playing\nstop first" : "Drop to\nload"
                }
            }
        }
    }

    // The dragged track, following the finger. Not a real QtQuick Drag: the
    // drop targets are the two edge zones, decided by x on release.
    Rectangle {
        id: dragProxy

        property bool active: false
        readonly property int targetDeck: x + width / 2 < 108 ? 1 : (x + width / 2 > root.width - 108 ? 2 : 0)
        readonly property color accent: targetDeck === 2 ? OD.Tokens.deck2 : OD.Tokens.deck1

        function begin(p) {
            x = p.x - 60;
            y = p.y - 26;
            active = true;
        }
        function move(p) {
            x = p.x - 60;
            y = p.y - 26;
        }
        function end() {
            if (targetDeck > 0 && root.dragRow >= 0) {
                root.loadTo(root.dragRow, targetDeck);
            }
            active = false;
            root.dragRow = -1;
        }

        Drag.active: active
        border.color: accent
        border.width: 2
        color: OD.Tokens.selected
        height: 52
        opacity: active ? 1 : 0
        radius: 10
        rotation: -2
        visible: opacity > 0
        width: 360
        z: 10

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Text {
                Layout.fillWidth: true
                color: OD.Tokens.text
                elide: Text.ElideRight
                font.pixelSize: 14
                font.weight: Font.DemiBold
                text: root.dragTitle
            }
            Text {
                color: OD.Tokens.text
                font.family: OD.Tokens.mono
                font.pixelSize: 13
                text: root.dragBpm
            }
            Text {
                color: OD.Tokens.textSoft
                font.pixelSize: 12
                text: dragProxy.targetDeck > 0 ? "→ Deck " + dragProxy.targetDeck : "← drag to an edge →"
            }
        }
    }
}
