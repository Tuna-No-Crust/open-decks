import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window 2.12
import "." as OD

// Everything sits in the centre block (reach rule 2: nothing at the screen
// edges). Utility row: wordmark, LEADER readout, ⋯ menu. Tab row: Perform,
// Library, FX, Settings. The ⋯ menu holds the seldom-used fullscreen and
// quit; quit takes two taps so a stray thumb can't end a set.
Rectangle {
    id: root

    // The shown tab, kept in [OpenDecks] tab so the controller can switch it.
    // 0 Perform, 1 Library, 2 FX, 3 Settings (touch only, the bumpers skip it).
    readonly property int currentIndex: Math.max(0, Math.min(3, Math.round(tab.value)))
    // Tap the bar to focus it; the bumpers then change tabs.
    readonly property bool focused: OD.UiState.focus === 3
    // The ApplicationWindow, for the fullscreen toggle.
    property var window: null
    readonly property bool fullscreen: window ? window.visibility === Window.FullScreen : false

    // The centre block, centred so a resized Mac window keeps the layout.
    readonly property real blockX: (width - OD.Tokens.layout.wMixer) / 2

    color: OD.Tokens.ground
    implicitHeight: OD.Tokens.layout.hTopbar

    Mixxx.ControlProxy { id: tab; group: "[OpenDecks]"; key: "tab" }
    // The controller taps these (1 then 0) faster than the UI runs, so use
    // the value the signal carries, and re-arm them so every tap is a change.
    Mixxx.ControlProxy {
        id: tabNext

        group: "[OpenDecks]"
        key: "tab_next"

        onValueChanged: (newValue) => {
            if (newValue > 0) {
                tab.value = root.currentIndex >= 2 ? 0 : root.currentIndex + 1;
                tabNext.value = 0;
            }
        }
    }
    Mixxx.ControlProxy {
        id: tabPrev

        group: "[OpenDecks]"
        key: "tab_prev"

        onValueChanged: (newValue) => {
            if (newValue > 0) {
                tab.value = root.currentIndex === 0 ? 2 : Math.min(2, root.currentIndex - 1);
                tabPrev.value = 0;
            }
        }
    }
    Mixxx.ControlProxy {
        id: leaderBpm

        group: "[InternalClock]"
        key: "bpm"
    }

    TapHandler {
        onTapped: OD.UiState.focus = 3
    }

    Rectangle {
        anchors.bottom: parent.bottom
        color: OD.Tokens.line
        height: OD.Tokens.b1
        width: parent.width
    }

    // --- utility row
    Text {
        color: OD.Tokens.text
        font.family: OD.Tokens.sans
        font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.body, OD.Tokens.ls.title)
        font.pixelSize: OD.Tokens.fs.body
        font.weight: OD.Tokens.fw.semibold
        height: OD.Tokens.layout.hUtility
        text: "Open Decks"
        verticalAlignment: Text.AlignVCenter
        x: root.blockX + OD.Tokens.s.s4
    }

    // A readout, not a button.
    Row {
        height: OD.Tokens.layout.hUtility
        spacing: OD.Tokens.s.s2
        x: root.blockX + (OD.Tokens.layout.wMixer - width) / 2

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: OD.Tokens.textMuted
            font.capitalization: Font.AllUppercase
            font.family: OD.Tokens.sans
            font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.label, OD.Tokens.ls.label)
            font.pixelSize: OD.Tokens.fs.label
            font.weight: OD.Tokens.fw.semibold
            text: "Leader"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: OD.Tokens.text
            font.family: OD.Tokens.mono
            font.pixelSize: OD.Tokens.fs.body
            font.weight: OD.Tokens.fw.semibold
            text: leaderBpm.value.toFixed(2)
        }
    }

    Button {
        id: menuButton

        Accessible.name: "More: fullscreen, quit"
        height: OD.Tokens.targetMin
        width: OD.Tokens.targetMin
        x: root.blockX + OD.Tokens.layout.wMixer - OD.Tokens.s.s4 - width

        onClicked: {
            if (menu.opened) {
                menu.close();
            } else {
                menu.open();
            }
            OD.UiState.focus = 3;
        }

        background: Rectangle {
            border.color: menuButton.down ? OD.Tokens.textSecondary : OD.Tokens.edge
            border.width: OD.Tokens.b1
            color: menu.opened ? OD.Tokens.selected : (menuButton.down ? OD.Tokens.raised : OD.Tokens.panel)
            radius: OD.Tokens.r.r2
        }
        // Three bars: the middle one on the centre, the others b2 + s1 away.
        contentItem: Item {
            Repeater {
                model: 3

                Rectangle {
                    required property int index

                    anchors.horizontalCenter: parent.horizontalCenter
                    color: OD.Tokens.textSecondary
                    height: OD.Tokens.b2
                    width: OD.Tokens.layout.glyphS
                    y: (parent.height - height) / 2 + (index - 1) * (OD.Tokens.b2 + OD.Tokens.s.s1)
                }
            }
        }

        // The menu, hanging under the button with its right edge aligned.
        Popup {
            id: menu

            closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
            modal: false
            padding: OD.Tokens.s.s1
            width: OD.Tokens.layout.wApply
            x: menuButton.width - width
            y: menuButton.height + OD.Tokens.s.s1

            onClosed: {
                quitArm.stop();
                quitRow.armed = false;
            }

            background: Rectangle {
                border.color: OD.Tokens.edge
                border.width: OD.Tokens.b1
                color: OD.Tokens.panel
                radius: OD.Tokens.r.r2
            }
            contentItem: ColumnLayout {
                spacing: OD.Tokens.s.s1

                MenuRow {
                    glyph: root.fullscreen ? "⤡" : "⤢"
                    label: root.fullscreen ? "Leave fullscreen" : "Fullscreen"
                    visible: root.window !== null

                    onClicked: {
                        root.window.visibility = root.fullscreen ? Window.Windowed : Window.FullScreen;
                        menu.close();
                    }
                }
                MenuRow {
                    id: quitRow

                    property bool armed: false

                    danger: armed
                    glyph: "⏻"
                    label: armed ? "Tap again to quit" : "Quit"

                    onClicked: {
                        if (armed) {
                            Qt.quit();
                        } else {
                            armed = true;
                            quitArm.restart();
                        }
                    }

                    Timer {
                        id: quitArm

                        // Behaviour timeout (3 s to confirm), not a motion token.
                        interval: 3000
                        onTriggered: quitRow.armed = false
                    }
                }
            }
        }
    }

    // --- tab row
    Item {
        id: tabGroup

        height: OD.Tokens.layout.hTab
        width: OD.Tokens.layout.wTab * 4
        x: root.blockX + OD.Tokens.s.s4
        y: OD.Tokens.layout.hUtility

        Row {
            Repeater {
                model: ["Perform", "Library", "FX", "Settings"]

                Button {
                    id: tabButton

                    required property int index
                    required property string modelData
                    readonly property bool active: index === root.currentIndex

                    Accessible.name: modelData
                    checkable: false
                    height: OD.Tokens.layout.hTab
                    width: OD.Tokens.layout.wTab

                    onClicked: {
                        tab.value = index;
                        OD.UiState.focus = 3;
                    }

                    background: Rectangle {
                        color: tabButton.down ? OD.Tokens.raised : "transparent"
                        radius: OD.Tokens.r.r1

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: OD.Tokens.s.s2
                            anchors.left: parent.left
                            anchors.leftMargin: OD.Tokens.s.s4
                            anchors.right: parent.right
                            anchors.rightMargin: OD.Tokens.s.s4
                            color: OD.Tokens.accent
                            height: OD.Tokens.b2
                            visible: tabButton.active
                        }
                    }
                    contentItem: Text {
                        color: tabButton.active ? OD.Tokens.text : OD.Tokens.textMuted
                        font.family: OD.Tokens.sans
                        font.pixelSize: OD.Tokens.fs.body
                        font.weight: OD.Tokens.fw.semibold
                        horizontalAlignment: Text.AlignHCenter
                        text: tabButton.modelData
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        // Controller focus on the bar: outlined inside the tab group's bounds.
        Rectangle {
            anchors.fill: parent
            border.color: OD.Tokens.focus
            border.width: OD.Tokens.b2
            color: "transparent"
            opacity: root.focused ? 1 : 0
            radius: OD.Tokens.r.r1

            Behavior on opacity {
                NumberAnimation { duration: OD.Tokens.durFast }
            }
        }
    }

    component MenuRow: Button {
        id: row

        property string glyph: ""
        property string label: ""
        property bool danger: false

        Layout.fillWidth: true
        Layout.preferredHeight: OD.Tokens.targetPrimary
        Accessible.name: label

        background: Rectangle {
            color: row.danger ? OD.Tokens.danger : (row.down ? OD.Tokens.raised : "transparent")
            radius: OD.Tokens.r.r1
        }
        contentItem: RowLayout {
            spacing: OD.Tokens.s.s3

            Text {
                Layout.leftMargin: OD.Tokens.s.s3
                Layout.preferredWidth: OD.Tokens.layout.glyphS
                color: row.danger ? OD.Tokens.ground : OD.Tokens.textSecondary
                font.family: OD.Tokens.sans
                font.pixelSize: OD.Tokens.fs.body
                horizontalAlignment: Text.AlignHCenter
                text: row.glyph
            }
            Text {
                Layout.fillWidth: true
                color: row.danger ? OD.Tokens.ground : OD.Tokens.text
                font.family: OD.Tokens.sans
                font.pixelSize: OD.Tokens.fs.body
                font.weight: row.danger ? OD.Tokens.fw.bold : OD.Tokens.fw.medium
                text: row.label
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
