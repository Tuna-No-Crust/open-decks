pragma Singleton
import QtQuick 2.12

// The effects offered on the FX screen (Mixxx built-ins), and how the XY pad
// and the beat chips map onto each one's parameters. Parameter numbers are
// 1-based `parameterN` controls of effect slot 1, in manifest order.
QtObject {
    readonly property var effects: [
        { id: "org.mixxx.effects.echo", name: "Echo", xParam: 1, xLabel: "delay time",
            beatsParam: 1, minBeats: 0.125, maxBeats: 2 },
        { id: "org.mixxx.effects.reverb", name: "Reverb", xParam: 1, xLabel: "decay",
            beatsParam: 0 },
        { id: "org.mixxx.effects.flanger", name: "Flanger", xParam: 1, xLabel: "speed",
            beatsParam: 1, minBeats: 0.25, maxBeats: 32 },
        { id: "org.mixxx.effects.phaser", name: "Phaser", xParam: 1, xLabel: "period",
            beatsParam: 1, minBeats: 0.125, maxBeats: 4 },
        { id: "org.mixxx.effects.bitcrusher", name: "Bitcrusher", xParam: 1, xLabel: "bit depth",
            beatsParam: 0 },
        { id: "org.mixxx.effects.tremolo", name: "Tremolo", xParam: 1, xLabel: "depth",
            beatsParam: 2, minBeats: 0.25, maxBeats: 8 },
        // Both filters are Mixxx's Filter effect (lpf, q, hpf): X sweeps one
        // corner, `preset` parks the other one open (normalised 0..1).
        { id: "org.mixxx.effects.filter", name: "Low Pass", xParam: 1, xLabel: "cutoff ↓",
            beatsParam: 0, preset: { 3: 0 } },
        { id: "org.mixxx.effects.filter", name: "High Pass", xParam: 3, xLabel: "cutoff ↑",
            beatsParam: 0, preset: { 1: 1 } },
    ]

    readonly property var beatChips: [
        { beats: 0.125, label: "⅛" }, { beats: 0.25, label: "¼" }, { beats: 0.5, label: "½" },
        { beats: 1, label: "1" }, { beats: 2, label: "2" }, { beats: 4, label: "4" },
    ]

    // First catalog index with this effect id (the filters share one), or -1.
    function indexOfId(id) {
        for (let i = 0; i < effects.length; ++i) {
            if (effects[i].id === id) {
                return i;
            }
        }
        return -1;
    }
}
