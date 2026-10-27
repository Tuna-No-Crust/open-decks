pragma Singleton
import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import "." as OD

// UI state shared between screens; focus is mirrored into a Mixxx control.
QtObject {
    // The crossfader lock is the same lock on the Perform and FX screens.
    property bool crossfaderLocked: true

    // What the thumbs last touched: 0 none, 1 deck 1, 2 deck 2, 3 the top bar.
    // Lives in the [OpenDecks] focus control so the gamepad mapping can read it
    // (nudge target, tab switching) and set it (deck used from the controller).
    property alias focus: focusCtl.value
    readonly property Mixxx.ControlProxy focusControl: Mixxx.ControlProxy {
        id: focusCtl

        group: "[OpenDecks]"
        key: "focus"
    }

    function focusDeck(deckNumber) {
        focusControl.value = deckNumber;
    }

    // Headphone cue level starts low on every launch (user, 2026-10-26: "cue
    // should default to 30, never start at the loudest"). 0.3 of the slider
    // is about -6 dB; Mixxx would otherwise restore whatever was last set.
    // (A QML hot reload re-creates this singleton and resets it too.)
    readonly property Mixxx.ControlProxy headGain: Mixxx.ControlProxy {
        group: "[Master]"
        key: "headGain"
    }
    Component.onCompleted: headGain.parameter = 0.3

    // A short on-screen notice, shown by the app shell's toast.
    signal notice(string message, color accent)

    function notify(message, accent) {
        notice(message, accent || OD.Tokens.text);
    }
}
