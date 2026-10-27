import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import "." as OD

// A labelled row of touch chips, one of which is selected. `options` is a
// list of {label, value}; tapping a chip emits picked(value). Chips wrap
// onto further lines when the labels (device names) are long.
ColumnLayout {
    id: root

    property string label: ""
    property var options: []
    property var selectedValue: undefined
    property color accent: OD.Tokens.text
    property string emptyText: "None found"

    signal picked(var value)

    spacing: 6

    Text {
        color: OD.Tokens.textMuted
        font.bold: true
        font.letterSpacing: 1
        font.pixelSize: 11
        text: root.label
        visible: root.label !== ""
    }
    Text {
        color: OD.Tokens.textSubtle
        font.pixelSize: 14
        text: root.emptyText
        visible: root.options.length === 0
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: root.options

            Button {
                id: chip

                required property var modelData
                readonly property bool selected: root.selectedValue !== undefined
                    && modelData.value === root.selectedValue

                Accessible.name: modelData.label
                enabled: root.enabled
                height: OD.Tokens.minTouch
                width: Math.max(72, text.implicitWidth + 28)

                onClicked: root.picked(modelData.value)

                background: Rectangle {
                    color: chip.selected ? root.accent : (chip.down ? OD.Tokens.selected : OD.Tokens.raised)
                    radius: 8
                }
                contentItem: Text {
                    id: text

                    color: chip.selected ? OD.Tokens.ground : OD.Tokens.textSoft
                    elide: Text.ElideMiddle
                    font.bold: chip.selected
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    text: chip.modelData.label
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
