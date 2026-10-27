import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Layouts
import "." as OD

// FX screen: slim waveforms, then an XY effect pad per deck at the outer
// edges (thumb reach) with the unit controls and touch faders in the middle,
// so a whole transition can happen without leaving the screen.
ColumnLayout {
    id: root

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
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.topMargin: 4
        spacing: 12

        OD.FxUnitPanel {
            id: unit1

            Layout.fillHeight: true
            Layout.preferredWidth: 420
            deckNumber: 1
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.minimumWidth: 300
            color: OD.Tokens.panelSunk
            radius: 12

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 16

                OD.FxUnitControls {
                    Layout.fillWidth: true
                    unit: unit1
                }
                OD.FxUnitControls {
                    Layout.fillWidth: true
                    unit: unit2
                }

                Rectangle {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    color: OD.Tokens.raised
                    radius: 10

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            color: OD.Tokens.textMuted
                            font.bold: true
                            font.letterSpacing: 1
                            font.pixelSize: 11
                            text: "FADERS"
                        }
                        RowLayout {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            spacing: 56

                            Item { Layout.fillWidth: true }
                            Repeater {
                                model: 2

                                ColumnLayout {
                                    id: channel

                                    required property int index
                                    readonly property int deckNumber: index + 1
                                    readonly property color accent: OD.Tokens.deckColor(deckNumber)

                                    Layout.fillHeight: true
                                    spacing: 6

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        color: channel.accent
                                        font.bold: true
                                        font.pixelSize: 11
                                        text: "CH " + channel.deckNumber
                                    }
                                    OD.ChannelFader {
                                        id: fader

                                        Layout.fillHeight: true
                                        accent: channel.accent
                                        group: "[Channel" + channel.deckNumber + "]"
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        color: OD.Tokens.textMuted
                                        font.family: OD.Tokens.mono
                                        font.pixelSize: 10
                                        text: Math.round(fader.value * 100)
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        OD.Crossfader {
                            Layout.fillWidth: true
                        }
                        OD.CueLevel {
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        OD.FxUnitPanel {
            id: unit2

            Layout.fillHeight: true
            Layout.preferredWidth: 420
            deckNumber: 2
        }
    }
}
