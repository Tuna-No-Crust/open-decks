import "." as Skin
import "OpenDecks" as OD
import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Window 2.12
import "Theme"

ApplicationWindow {
    id: root

    readonly property bool isMobile: Qt.platform.os === "android" || Qt.platform.os === "ios"
    // The handheld touch UI is designed at the Steam Deck's 1280x800.
    readonly property int designWidth: 1280
    readonly property int designHeight: 800

    color: OD.Tokens.ground
    title: "Open Decks"
    height: isMobile ? Screen.height : designHeight
    menuBar: content.item ? content.item.menuBar : null
    minimumHeight: isMobile ? 0 : 300
    minimumWidth: isMobile ? 0 : 680
    visible: true
    width: isMobile ? Screen.width : designWidth

    function updateVisibility() {
        if (!Mixxx.Core.ready) {
            return;
        }
        root.visibility = Mixxx.Config.configStartInFullscreenKey || isMobile
                ? Window.FullScreen
                : Window.Windowed;
    }

    Connections {
        target: Mixxx.Core
        function onReadyChanged() {
            root.updateVisibility();
        }
    }

    Component.onCompleted: root.updateVisibility()

    Loader {
        id: content

        anchors.fill: parent

        active: Mixxx.Core.ready
        asynchronous: true
        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("Failed to load the Mixxx main window")
                Qt.quit()
            }
        }
        // Our handheld UI (res/qml/OpenDecks) in place of upstream's MainWindow,
        // which stays in the tree for reference.
        sourceComponent: Component {
            OD.AppShell {
                applicationWindow: root
            }
        }
    }
    // Startup splash: the Open Decks mark, name and a loading line in the
    // deck colours, until the touch UI is ready (then fades out).
    Rectangle {
        id: splash
        visible: opacity > 0
        color: OD.Tokens.ground
        anchors.fill: parent

        property bool ready: false

        Component.onCompleted: {
            ready = true
        }

        states: [
            State {
                when: splash.ready && content.status != Loader.Ready

                PropertyChanges {
                    brand.opacity: 1
                    brand.anchors.verticalCenterOffset: 0
                }
            },
            State {
                when: content.status == Loader.Ready && content.active

                PropertyChanges {
                    splash.opacity: 0
                }
            }
        ]

        Column {
            id: brand
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 24
            opacity: 0
            spacing: 20

            Behavior on opacity {
                NumberAnimation { duration: 600; easing.type: Easing.OutQuad }
            }
            Behavior on anchors.verticalCenterOffset {
                NumberAnimation { duration: 600; easing.type: Easing.OutQuad }
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 112
                source: "OpenDecks/images/logo.svg"
                sourceSize.height: 224
                sourceSize.width: 224
                width: 112
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: OD.Tokens.text
                font.family: OD.Tokens.sans
                font.letterSpacing: OD.Tokens.tracking(32, OD.Tokens.ls.title)
                font.pixelSize: 32
                font.weight: OD.Tokens.fw.semibold
                text: "Open Decks"
            }
            // Indeterminate loading line: a short segment sweeping a thin
            // track, blue on the way out, orange on the way back.
            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                clip: true
                color: OD.Tokens.raised
                height: 3
                radius: 1.5
                width: 160

                Rectangle {
                    id: sweep
                    color: OD.Tokens.deck1
                    height: parent.height
                    radius: parent.radius
                    width: 48
                    x: -width

                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: splash.visible
                        PropertyAction { target: sweep; property: "color"; value: OD.Tokens.deck1 }
                        NumberAnimation { from: -sweep.width; to: track.width; duration: 900; easing.type: Easing.InOutQuad }
                        PropertyAction { target: sweep; property: "color"; value: OD.Tokens.deck2 }
                        NumberAnimation { from: track.width; to: -sweep.width; duration: 900; easing.type: Easing.InOutQuad }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: OD.Tokens.textMuted
                font.capitalization: Font.AllUppercase
                font.family: OD.Tokens.mono
                font.letterSpacing: OD.Tokens.tracking(12, OD.Tokens.ls.label)
                font.pixelSize: 12
                text: "Loading"
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.InOutQuad }
        }
    }
}
