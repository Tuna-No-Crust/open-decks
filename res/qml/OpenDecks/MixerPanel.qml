import QtQuick 2.12
import "." as OD

// Bottom of the centre column on Perform (480 x 400): both channels, the
// locking crossfader and the cue level. No fill, no frame: the readouts and
// faders sit directly on the ground.
Item {
    id: root

    implicitHeight: OD.Tokens.layout.hFrame / 2
    implicitWidth: OD.Tokens.layout.wMixer

    OD.ChannelStrip {
        deckNumber: 1
        x: OD.Tokens.s.s4
        y: OD.Tokens.s.s2
    }
    OD.ChannelStrip {
        anchors.right: parent.right
        anchors.rightMargin: OD.Tokens.s.s4
        deckNumber: 2
        y: OD.Tokens.s.s2
    }
    OD.Crossfader {
        width: root.width - OD.Tokens.s.s4 * 2
        x: OD.Tokens.s.s4
        y: OD.Tokens.s.s2 + OD.Tokens.layout.hFader + OD.Tokens.s.s4
    }
    OD.CueLevel {
        width: root.width - OD.Tokens.s.s4 * 2
        x: OD.Tokens.s.s4
        y: OD.Tokens.s.s2 + OD.Tokens.layout.hFader + OD.Tokens.s.s4 + OD.Tokens.layout.hXfader + OD.Tokens.s.s4
    }
}
