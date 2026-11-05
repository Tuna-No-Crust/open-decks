pragma Singleton
import QtQuick 2.12

// The effects offered on the FX screen (Mixxx built-ins), and how the XY pad
// and the beat chips map onto each one's parameters. Parameter numbers are
// 1-based `parameterN` controls of the slot, in manifest order (buttons such
// as Quantize/Triplets are numbered separately and don't count).
//
// The pad plays two parameters (user, 2026-11-05: "x and y should cover 2
// parts of the fx"); the wet amount is mostly not on the pad but set per effect
// (`mixMode` + `wet`, the unit's mix) and trimmed with the WET fader.
// An axis is one of
//   { param, steps: [...] }  value snapped to one of `steps` (beats, ...)
//   { param, from, to }      value, linear
//   { param, nfrom, nto }    the 0..1 `parameter` (follows the effect's own
//                            curve, e.g. log for filter cutoffs)
//   { roll: [...] }          the deck's loop roll size in beats (Roll)
//   { mix: true, from, to }  the unit's mix (wet) instead of a parameter
// `preset` sets slot-1 values when the effect is picked; `chain` loads a
// second effect into slot 2 (Dub's filter on the repeats). `trail`: on lift
// the effect's send (`sendParam`) closes and the unit stays on that long,
// so echoes and reverb ring out instead of being cut off.
// Mix modes: 0 = Dry/Wet (crossfade; for effects whose output already holds
// the dry signal, and filters), 1 = Dry+Wet (dry stays at full, the effect is
// added on top; Echo and Reverb output only the wet signal).
QtObject {
    readonly property var effects: [
        { id: "org.mixxx.effects.echo", name: "Echo",
            x: { param: 1, steps: [0.125, 0.25, 0.5, 1, 2] }, xLabel: "time ⅛ → 2",
            y: { param: 2, from: 0.3, to: 0.85 }, yLabel: "feedback",
            mixMode: 1, wet: 0.6, preset: { 3: 0, 4: 1 }, sendParam: 4, trail: 4000,
            beatsParam: 1, minBeats: 0.125, maxBeats: 2 },
        // Mixxx has no dub echo: a long-feedback ping-pong Echo with a band
        // pass on the repeats (Filter in slot 2; in Dry+Wet the dry signal
        // doesn't pass through the chain, so only the repeats are filtered).
        { id: "org.mixxx.effects.echo", name: "Dub",
            x: { param: 1, steps: [0.25, 0.5, 0.75, 1] }, xLabel: "time ¼ → 1",
            y: { param: 2, from: 0.55, to: 0.95 }, yLabel: "feedback",
            mixMode: 1, wet: 0.7, preset: { 3: 0.4, 4: 1 }, sendParam: 4, trail: 6000,
            chain: { id: "org.mixxx.effects.filter", preset: { 1: 3000, 2: 1.2, 3: 300 } },
            beatsParam: 1, minBeats: 0.25, maxBeats: 1 },
        { id: "org.mixxx.effects.reverb", name: "Reverb",
            x: { param: 1, from: 0.25, to: 0.92 }, xLabel: "decay",
            y: { param: 3, from: 0.8, to: 0 }, yLabel: "bright",
            mixMode: 1, wet: 0.45, preset: { 2: 1, 4: 1 }, sendParam: 4, trail: 3500,
            beatsParam: 0 },
        // Stages must be even: every all-pass stage inverts the bass, so
        // Mixxx's default of 7 cancels the low end against the dry signal
        // (sounded like a high pass).
        // 4 stages, rate fixed at 2 beats (beat chips change it), wet on Y
        // (user, 2026-11-05).
        { id: "org.mixxx.effects.phaser", name: "Phaser",
            x: { param: 2, from: 0, to: 0.95 }, xLabel: "feedback",
            y: { mix: true, from: 0, to: 1 }, yLabel: "wet",
            mixMode: 0, wet: 1, preset: { 1: 2, 3: 1, 4: 4, 5: 1 },
            beatsParam: 1, minBeats: 0.5, maxBeats: 4 },
        // Rate fixed at 16 beats (beat chips change it), wet on Y (user,
        // 2026-11-05).
        { id: "org.mixxx.effects.flanger", name: "Flanger",
            x: { param: 4, from: 0, to: 0.95 }, xLabel: "jet",
            y: { mix: true, from: 0, to: 1 }, yLabel: "wet",
            mixMode: 0, wet: 1, preset: { 1: 16, 5: 1 },
            beatsParam: 1, minBeats: 0.5, maxBeats: 16 },
        // Both filters are Mixxx's Filter effect (lpf, q, hpf): X sweeps one
        // corner, the preset parks the other one open. Always fully wet: a
        // filter crossfaded with the dry signal hardly filters.
        { id: "org.mixxx.effects.filter", name: "High Pass",
            x: { param: 3, nfrom: 0, nto: 0.85 }, xLabel: "cutoff ↑",
            y: { param: 2, from: 0.707, to: 3 }, yLabel: "resonance",
            mixMode: 0, wet: 1, preset: { 1: 22050 },
            beatsParam: 0 },
        { id: "org.mixxx.effects.filter", name: "Low Pass",
            x: { param: 1, nfrom: 0.15, nto: 1 }, xLabel: "cutoff (open →)",
            y: { param: 2, from: 0.707, to: 3 }, yLabel: "resonance",
            mixMode: 0, wet: 1, preset: { 3: 13 },
            beatsParam: 0 },
        // Roll = the deck's own slip loop roll (beatlooproll_N_activate: the
        // track carries on underneath, like a CDJ's), with the unit's Filter
        // darkening the repeats when the finger goes down.
        { id: "org.mixxx.effects.filter", name: "Roll",
            x: { roll: [1, 0.5, 0.25, 0.125, 0.0625] }, xLabel: "length 1 → 1⁄16",
            y: { param: 1, nfrom: 0.3, nto: 1 }, yLabel: "open",
            mixMode: 0, wet: 1, preset: { 2: 0.707, 3: 13 },
            beatsParam: 0 },
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

    // Axis position 0..1 -> what to write. Returns { value } or { parameter }.
    function axisTarget(axis, pos) {
        const p = Math.min(1, Math.max(0, pos));
        if (axis.steps) {
            return { value: axis.steps[Math.min(axis.steps.length - 1, Math.floor(p * axis.steps.length))] };
        }
        if (axis.nfrom !== undefined) {
            return { parameter: axis.nfrom + p * (axis.nto - axis.nfrom) };
        }
        return { value: axis.from + p * (axis.to - axis.from) };
    }

    // The inverse, so the pad's ring shows where a parameter is even when the
    // beat chips (or anything else) moved it.
    function axisPosition(axis, value, parameter) {
        let p;
        if (axis.steps) {
            let best = 0;
            for (let i = 1; i < axis.steps.length; ++i) {
                if (Math.abs(axis.steps[i] - value) < Math.abs(axis.steps[best] - value)) {
                    best = i;
                }
            }
            p = (best + 0.5) / axis.steps.length;
        } else if (axis.nfrom !== undefined) {
            p = (parameter - axis.nfrom) / (axis.nto - axis.nfrom);
        } else {
            p = (value - axis.from) / (axis.to - axis.from);
        }
        return Math.min(1, Math.max(0, p));
    }

    // Loop roll size for a pad position.
    function rollSize(axis, pos) {
        const p = Math.min(1, Math.max(0, pos));
        return axis.roll[Math.min(axis.roll.length - 1, Math.floor(p * axis.roll.length))];
    }
}
