import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import "." as OD

// The centre-column controls of one effect unit: beat chips for its tempo
// parameter (Echo's delay, Flanger's speed...), Hold, and the WET fader (the
// unit's mix; each effect starts at its own amount and mix mode, FxCatalog).
ColumnLayout {
    id: root

    required property OD.FxUnitPanel unit
    readonly property int deckNumber: unit.deckNumber
    readonly property color accent: OD.Tokens.deckColor(deckNumber)
    readonly property var effect: unit.effect
    readonly property bool hasBeats: (effect?.beatsParam ?? 0) > 0

    spacing: 8

    Mixxx.ControlProxy {
        id: beatsParam

        group: root.unit.slotGroup
        key: "parameter" + (root.effect?.beatsParam || 1)
    }
    Mixxx.ControlProxy {
        id: mix

        group: root.unit.unitGroup
        key: "mix"
    }

    Text {
        color: root.accent
        font.bold: true
        font.letterSpacing: 1
        font.pixelSize: 11
        text: "UNIT " + root.deckNumber + " · BEATS"
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: OD.FxCatalog.beatChips

            Button {
                id: chip

                required property var modelData
                readonly property bool inRange: root.hasBeats
                    && modelData.beats >= root.effect.minBeats - 0.001
                    && modelData.beats <= root.effect.maxBeats + 0.001
                readonly property bool selected: inRange && Math.abs(beatsParam.value - modelData.beats) < 0.01

                Layout.fillWidth: true
                Layout.preferredHeight: OD.Tokens.minTouch
                Layout.preferredWidth: 1
                Accessible.name: modelData.label + " beats"
                enabled: inRange
                opacity: inRange ? 1 : 0.35

                onClicked: beatsParam.value = modelData.beats

                background: Rectangle {
                    color: chip.selected ? root.accent : (chip.down ? OD.Tokens.selected : OD.Tokens.raised)
                    radius: 8
                }
                contentItem: Text {
                    color: chip.selected ? OD.Tokens.ground : OD.Tokens.textSoft
                    font.bold: true
                    font.family: OD.Tokens.mono
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    text: chip.modelData.label
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Button {
            id: holdButton

            Layout.preferredHeight: OD.Tokens.minTouch
            Layout.preferredWidth: 88
            Accessible.name: "Hold effect " + root.deckNumber
            checkable: true
            checked: root.unit.hold

            onToggled: root.unit.setHold(checked)

            background: Rectangle {
                border.color: OD.Tokens.selected
                color: holdButton.checked ? root.accent : OD.Tokens.raised
                radius: 8
            }
            contentItem: Text {
                color: holdButton.checked ? OD.Tokens.ground : OD.Tokens.textSoft
                font.pixelSize: 13
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                text: "Hold"
                verticalAlignment: Text.AlignVCenter
            }
        }
        Text {
            color: OD.Tokens.textMuted
            font.bold: true
            font.letterSpacing: 1
            font.pixelSize: 11
            text: "WET"
        }
        Slider {
            id: wetSlider

            Layout.fillWidth: true
            Layout.preferredHeight: OD.Tokens.minTouch
            Accessible.name: "Effect " + root.deckNumber + " wet"
            from: 0
            to: 1
            live: true
            value: mix.value

            onMoved: mix.value = value

            background: Item {
                Rectangle {
                    color: OD.Tokens.raised
                    height: 4
                    radius: 2
                    width: parent.width - OD.Tokens.minTouch
                    x: OD.Tokens.minTouch / 2
                    y: parent.height / 2 - 2

                    Rectangle {
                        color: root.accent
                        height: parent.height
                        radius: 2
                        width: wetSlider.visualPosition * parent.width
                    }
                }
            }
            handle: Rectangle {
                border.color: wetSlider.pressed ? root.accent : OD.Tokens.selected
                border.width: 1
                color: wetSlider.pressed ? root.accent : OD.Tokens.raised
                height: OD.Tokens.minTouch
                radius: height / 2
                width: OD.Tokens.minTouch
                x: wetSlider.visualPosition * (wetSlider.width - width)
                y: (wetSlider.height - height) / 2
            }
        }
        Text {
            Layout.preferredWidth: 36
            color: OD.Tokens.textSoft
            font.family: OD.Tokens.mono
            font.pixelSize: 12
            horizontalAlignment: Text.AlignRight
            text: Math.round(mix.value * 100)
        }
    }
}
