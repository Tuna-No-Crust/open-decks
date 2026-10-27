import QtQuick 2.12
import QtQuick.Layouts
import "." as OD

// Root of the handheld touch UI: the view switcher over the three screens.
Rectangle {
    id: root

    // main.qml reads this for the window's menu bar; the handheld UI has none.
    property var menuBar: null
    property var applicationWindow

    color: OD.Tokens.ground

    // IBM Plex is on neither the Deck nor Android (OFL, bundled in res/fonts);
    // Mixxx also adds res/fonts to QFontDatabase at startup, this is belt and braces.
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexSans-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexSans-Medium.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexSans-SemiBold.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexSans-Bold.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexMono-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexMono-Medium.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexMono-SemiBold.ttf") }
    FontLoader { source: Qt.resolvedUrl("../../fonts/IBMPlexMono-Bold.ttf") }

    // Notices for the whole UI (screens call OD.UiState.notify(...)).
    OD.Toast {
        id: toast
    }
    Connections {
        target: OD.UiState

        function onNotice(message, accent) {
            toast.show(message, accent);
        }
    }

    // Anchored, not a ColumnLayout: the bar and the screens must touch.
    OD.TopBar {
        id: topBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: implicitHeight
        window: root.applicationWindow
    }
    Item {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom

        StackLayout {
            anchors.fill: parent
            currentIndex: topBar.currentIndex

            OD.PerformScreen {}

            OD.LibraryScreen {}
            OD.FxScreen {}
            // Settings is built on first use: it talks to Mixxx.SoundManager,
            // which only exists once the core has initialised (after main.qml
            // loaded), and nobody needs it during a set.
            Loader {
                id: settingsLoader

                // Once built it stays (keeps its edits while you flip tabs).
                property bool opened: false

                active: opened || topBar.currentIndex === 3
                sourceComponent: OD.SettingsScreen {}

                onLoaded: opened = true
            }
        }
    }
}
