// Gamepad DJ: two decks on any game controller, read through SDL.
//
// The controller sends a 50-byte report whenever the pad changes (see
// SdlGamepadController): version, 6 int16 axes, a uint32 button mask, the
// microseconds since the previous report, then the touchpads: a count and
// 2 x 2 finger slots (uint8 down, uint16 x, uint16 y, uint16 pressure), all
// little-endian. Version-1 pads send only the first 21 bytes.
//
// Each analog stick is the jog wheel of one deck. Spinning the stick around
// its rim turns the platter:
//   - playing      -> nudge (pitch bend while turning), like a CDJ's outer ring
//   - paused       -> scrub, for finding cue points
//   - vinyl mode   -> scratch (stick click toggles vinyl mode per deck)
// Holding a stick still out at the rim is a hand resting on the platter; letting
// it spring back to the centre is taking the hand off. Dipping inward while
// circling does not let go -- only settling at the centre does. The spring-back
// itself (mostly inward motion) is not counted as turning, and a paused deck
// stops dead on release, so it stays where it was scrubbed to.
//
// Layout (left hand = deck 1, right hand = deck 2):
//   Play                        click the left stick (L3)   click the right stick (R3)
//   FX on / off                 D-pad left                  Square (X)
//   Select EQ low / mid / high  Cross (A) / Circle (B) / Triangle (Y), for both decks
//                               (which band L2 + either stick moves; D-pad
//                               up / down / right are free)
//   Channel fader               push the stick straight up / down, no modifier
//                               (user, 2026-10-27: "can jogs and channel
//                               volume live in the same state?" -- trying it)
//   Vinyl mode / sync / loops   on the touch UI (deck panel badges and loop chips)
//   Hot cues                    on screen (touch pads), not on the controller
//   Cue                         L1 = deck 1, R1 = deck 2 (Mixxx's normal cue button);
//                               tap while that side's stick holds the platter = set the
//                               cue right there
//   Switch screens              tap the top bar on screen, then L1 / R1 = previous / next tab
//   Jog and fader in one state (user, 2026-10-27): a push is sorted when it
//   reaches kFaderDecideRadius: within kFaderSectorDeg of straight up/down
//   it is a channel fader push (the jog can't grab until the stick is back
//   at rest); anywhere else it is the jog, which grabs at grabRadius as
//   before. Start a turn from 3 or 9 o'clock, a fade from 12 or 6.
//   Stick layer -- hold L2 and the sticks stop being jog wheels (user,
//   2026-10-27: one trigger, R2 is free). Each stick works its own deck
//   (left = 1, right = 2), with two controls, one per axis; each push locks
//   to the axis it starts along:
//                 up/down                      left/right
//     L2          picked EQ band               filter (quick effect)
//   Tap A / B / Y to pick the band (also while L2 is held). The effect amount
//   is on the FX pads (touchpads / screen) now, not on a stick. (No tempo
//   control on the pad: sync, or the touch fader.)
//   The sticks spring back, so they move a fader/knob at a speed set by how
//   far they're pushed (on a curve, for fine slow fades), and letting go
//   leaves it where it is. Slamming a stick from rest to the edge jumps
//   straight to the end: faders to 100/0, EQs to kill (down) or neutral (up),
//   effect amount to full/off, and the filter back to neutral either way.
//   FX XY pads                  the controller's touchpads play the FX screen's
//   pads: a finger on the Steam Deck's left / right trackpad (or the left /
//   right half of a DualSense touchpad) is a finger on deck 1's / deck 2's pad.
//   Touch = effect on, slide = X (the effect's parameter) and Y (wet), lift =
//   off unless Hold is on; the pad on screen follows the finger.
//
// The focused deck will be the one tapped on the touchscreen; until the touch
// UI exists it is the last deck used from the controller.
//   Vinyl mode                  L3                          R3
//   Library: hold Options (Start) + D-pad up/down to scroll,
//            + D-pad left/right to load the selection on deck 1/2.
//            (Options is on the right so the left thumb stays on the D-pad.)
//   Create (Back/Select) loads the selection on an empty deck, else one that
//   isn't playing (never onto a playing deck).

var GamepadDJ = {};

GamepadDJ.Button = {
    south: 0, east: 1, west: 2, north: 3,
    back: 4, guide: 5, start: 6,
    leftStick: 7, rightStick: 8,
    leftShoulder: 9, rightShoulder: 10,
    dpadUp: 11, dpadDown: 12, dpadLeft: 13, dpadRight: 14,
};

GamepadDJ.kReportVersion = 2;
GamepadDJ.kReportSizeV1 = 21;
GamepadDJ.kReportSize = 50;
GamepadDJ.kMaxTouchpads = 2;
GamepadDJ.kMaxFingers = 2;
GamepadDJ.kIntervalsPerTurn = 1024; // scratch resolution
GamepadDJ.kTriggerOn = 0.03;
// L2 enters the mixer layer past kLayerOn and leaves it below kLayerOff.
GamepadDJ.kLayerOn = 0.5;
GamepadDJ.kLayerOff = 0.3;
GamepadDJ.kStickDeadzone = 0.15;
GamepadDJ.kLayerTickMs = 15;
// Base state, no modifier: a push is sorted into "fader" or "jog" once it
// reaches kFaderDecideRadius (must be below grabRadius, where the jog takes
// hold): a fader push when its direction is within kFaderSectorDeg of
// straight up or down, the jog otherwise. Decided once per push, until the
// stick is back in the dead zone.
GamepadDJ.kFaderDecideRadius = 0.4;
GamepadDJ.kFaderSectorDeg = 20;
// Inward motion this many times larger than the motion around the rim means
// the stick is springing back to the centre, not turning.
GamepadDJ.kSpringBackRatio = 2;
GamepadDJ.kSpringBackMinStep = 0.01;
GamepadDJ.kScrollRepeatDelayMs = 300;
GamepadDJ.kScrollRepeatMs = 90;
GamepadDJ.kFocusTracks = 3; // [Library] focused_widget: FocusWidget::TracksTable

GamepadDJ.kSettingFallbacks = {
    faderTravelSeconds: 0.35,
    faderCurve: 1.8,
    slamMs: 80,
    touchpadShowsFx: false,
};
// A slam must reach this far out within slamMs of leaving the dead zone.
GamepadDJ.kSlamReach = 0.9;

GamepadDJ.setting = function(name) {
    const value = engine.getSetting(name);
    return value === undefined ? GamepadDJ.kSettingFallbacks[name] : value;
};

// --- Jog ---------------------------------------------------------------

/**
 * One stick acting as one deck's jog wheel.
 *
 * States: released (hand off) and grabbed (hand on the platter). The mode --
 * scratch or nudge -- is decided at the moment of the grab and kept until
 * release, like putting a hand on the record versus pushing its edge.
 */
GamepadDJ.Jog = class {
    constructor(deck) {
        this.deck = deck;
        this.group = `[Channel${deck}]`;
        this.vinyl = false;
        this.grabbed = false;
        this.scratching = false;
        this.anchored = false; // lastAngle is valid for computing a delta
        this.lastAngle = 0;
        this.lastRadius = 0;
        this.tickRemainder = 0;
        this.releaseTimer = 0;
        this.turnsThisGrab = 0;
        this.waitForCentre = false;
    }

    // The stick was used for something else (the mixer layer): drop the
    // platter, and don't grab again until the stick has been back at rest.
    suspend() {
        this.release();
        this.waitForCentre = true;
    }

    toggleVinyl() {
        this.setVinyl(!this.vinyl);
    }

    setVinyl(on) {
        if (this.vinyl === on) {
            return;
        }
        this.vinyl = on;
        console.log(`Gamepad DJ: deck ${this.deck} vinyl mode ${on ? "on" : "off"}`);
    }

    // x, y in -1..1 with y down-positive, as SDL reports them
    update(x, y) {
        const r = Math.sqrt(x * x + y * y);
        // 0 = pushed up, clockwise positive
        const angle = Math.atan2(x, -y);
        const inward = this.lastRadius - r;
        this.lastRadius = r;

        if (this.waitForCentre) {
            if (r < GamepadDJ.setting("releaseRadius")) {
                this.waitForCentre = false;
            }
            return;
        }

        if (!this.grabbed) {
            if (r >= GamepadDJ.setting("grabRadius")) {
                this.grab(angle);
            }
            return;
        }

        if (r < GamepadDJ.setting("releaseRadius")) {
            // Possibly letting go -- but only if the stick stays at the centre.
            this.anchored = false;
            this.armRelease();
            return;
        }
        this.cancelRelease();

        if (r < GamepadDJ.setting("holdRadius")) {
            // Too close to the centre for the angle to mean anything. Keep
            // holding the platter; pick the rotation up again from wherever
            // the stick comes back out, without a jump.
            this.anchored = false;
            return;
        }
        if (!this.anchored) {
            this.lastAngle = angle;
            this.anchored = true;
            return;
        }

        let delta = angle - this.lastAngle;
        if (delta > Math.PI) {
            delta -= 2 * Math.PI;
        } else if (delta < -Math.PI) {
            delta += 2 * Math.PI;
        }
        this.lastAngle = angle;

        if (inward > GamepadDJ.kSpringBackMinStep &&
                inward > GamepadDJ.kSpringBackRatio * Math.abs(delta) * r) {
            // Springing back towards the centre: its sideways wobble is not
            // the player turning the platter.
            return;
        }

        const maxStep = GamepadDJ.setting("maxStepTurns");
        const turns = Math.max(-maxStep, Math.min(maxStep, delta / (2 * Math.PI)));
        this.turn(turns);
    }

    grab(angle) {
        GamepadDJ.focus(this.deck - 1);
        this.grabbed = true;
        this.anchored = true;
        this.lastAngle = angle;
        this.tickRemainder = 0;
        this.turnsThisGrab = 0;
        // Vinyl mode, or a stopped deck, means a hand on the record: scratch.
        // Otherwise push the edge of the platter: nudge.
        this.scratching = this.vinyl || !engine.getValue(this.group, "play");
        if (this.scratching) {
            const rpm = 60 / GamepadDJ.setting("secondsPerTurn");
            engine.scratchEnable(this.deck, GamepadDJ.kIntervalsPerTurn, rpm, 1 / 8, 1 / 8 / 32);
        }
        if (GamepadDJ.setting("logJog")) {
            console.log(`Gamepad DJ: deck ${this.deck} grab (${this.scratching ? "scratch" : "nudge"})`);
        }
    }

    turn(turns) {
        this.turnsThisGrab += turns;
        if (this.scratching) {
            this.tickRemainder += turns * GamepadDJ.kIntervalsPerTurn;
            const ticks = Math.trunc(this.tickRemainder);
            if (ticks !== 0) {
                this.tickRemainder -= ticks;
                engine.scratchTick(this.deck, ticks);
            }
        } else {
            engine.setValue(this.group, "jog", turns * GamepadDJ.setting("nudgeSensitivity"));
        }
    }

    armRelease() {
        if (this.releaseTimer) {
            return;
        }
        const ms = GamepadDJ.setting("releaseMs");
        if (ms <= 0) {
            this.release();
            return;
        }
        // Reports only arrive when the pad changes, so a stick resting at the
        // centre sends nothing: a timer has to notice that it stayed there.
        this.releaseTimer = engine.beginTimer(ms, () => {
            this.releaseTimer = 0;
            this.release();
        }, true);
    }

    cancelRelease() {
        if (this.releaseTimer) {
            engine.stopTimer(this.releaseTimer);
            this.releaseTimer = 0;
        }
    }

    release() {
        this.cancelRelease();
        if (!this.grabbed) {
            return;
        }
        this.grabbed = false;
        this.anchored = false;
        if (this.scratching) {
            // A playing deck ramps back up to speed like a released record; a
            // paused one stops dead, so a scrubbed-to position stays put.
            engine.scratchDisable(this.deck, engine.getValue(this.group, "play") > 0);
            this.scratching = false;
        }
        if (GamepadDJ.setting("logJog")) {
            console.log(`Gamepad DJ: deck ${this.deck} release after ${this.turnsThisGrab.toFixed(2)} turns`);
        }
    }
};

// --- Focus and nudge ---------------------------------------------------

// The deck the bumpers nudge. Set by touching a deck on screen once the touch
// UI exists; for now by using a deck from the controller.
GamepadDJ.focus = function(index) {
    if (GamepadDJ.focusedDeck !== index) {
        GamepadDJ.focusedDeck = index;
        if (GamepadDJ.setting("logJog")) {
            console.log(`Gamepad DJ: focus on deck ${index + 1}`);
        }
    }
    // Keep the touch UI's focus highlight in step with controller use
    // ([OpenDecks] focus: 1/2 = deck, 3 = the top bar; only exists with the QML UI).
    engine.setValue("[OpenDecks]", "focus", index + 1);
};

// What the touch UI says is focused: 1/2 = a deck, 3 = the top bar's tabs,
// 0 = nothing (fall back to the last deck used from the controller).
GamepadDJ.uiFocus = function() {
    return engine.getValue("[OpenDecks]", "focus");
};
GamepadDJ.focusedDeckIndex = function() {
    const f = GamepadDJ.uiFocus();
    return f === 1 || f === 2 ? f - 1 : GamepadDJ.focusedDeck;
};

// --- Buttons -----------------------------------------------------------

GamepadDJ.setMomentary = function(group, key, pressed) {
    engine.setValue(group, key, pressed ? 1 : 0);
};

GamepadDJ.bandName = function() {
    return ["low", "mid", "high"][GamepadDJ.band - 1];
};

GamepadDJ.togglePlay = function(group) {
    engine.setValue(group, "play", engine.getValue(group, "play") ? 0 : 1);
};

GamepadDJ.toggleLoop = function(group) {
    if (engine.getValue(group, "loop_enabled")) {
        engine.setValue(group, "reloop_toggle", 1);
    } else {
        engine.setValue(group, "beatloop_activate", 1);
    }
};

// One deck's buttons: play (stick click), FX on/off and the EQ band pick.
// Cue lives on the bumpers. (Hot cues, vinyl, sync and loops live on the
// touchscreen. L2 + a button used to toggle vinyl / sync / loop; dropped
// 2026-10-26 after a stray L2 + A put deck 2 in vinyl mode.)
GamepadDJ.Deck = class {
    constructor(deck, buttons) {
        this.deck = deck;
        this.group = `[Channel${deck}]`;
        this.eqGroup = `[EqualizerRack1_[Channel${deck}]_Effect1]`;
        this.unitGroup = `[EffectRack1_EffectUnit${deck}]`;
        this.slotGroup = `[EffectRack1_EffectUnit${deck}_Effect1]`;
        // {play, fxOn} -> button bit. (The EQ band pick is global, see
        // GamepadDJ.band.)
        this.buttons = buttons;
    }

    // Called for each button of this deck whose state changed.
    button(bit, pressed) {
        if (pressed) {
            GamepadDJ.focus(this.deck - 1);
        }
        const b = this.buttons;
        if (bit === b.play) {
            if (pressed) {
                GamepadDJ.togglePlay(this.group);
            }
        } else if (bit === b.fxOn) {
            // FX on/off for this deck: its own effect unit routed onto it,
            // like the FX pad's Hold. Switching on also enables slot 1.
            if (pressed) {
                this.toggleFx();
            }
        }
    }

    toggleFx() {
        const key = `group_${this.group}_enable`;
        const on = engine.getValue(this.unitGroup, key) ? 0 : 1;
        if (on) {
            engine.setValue(this.slotGroup, "enabled", 1);
        }
        engine.setValue(this.unitGroup, key, on);
        console.log(`Gamepad DJ: deck ${this.deck} FX ${on ? "on" : "off"}`);
    }
};

// --- Stick layers ------------------------------------------------------

/**
 * While its trigger is held, a layer takes the sticks away from the jogs.
 * Each stick drives two values of its own deck: targets.y for up/down and
 * targets.x for left/right. A push locks to the axis it starts along (the
 * larger component as it leaves the dead zone) until the stick is back at
 * rest, so a slightly diagonal fade doesn't also move the other control.
 *
 * A stick springs back to the centre, so it sets the *speed*: full deflection
 * sweeps the whole range in faderTravelSeconds, bent by faderCurve so small
 * pushes are very slow. Reports only come when the pad changes, so a timer
 * keeps the value moving while a stick is held still off-centre. Slamming
 * from the dead zone to kSlamReach within slamMs jumps the value to its end
 * instead: target.slamUp (default 1) or target.slamDown (default 0).
 *
 * A target is {group, key, slamUp?, slamDown?, before?, after?} or null for
 * "nothing". Values move with get/setParameter (normalised 0..1), which
 * follows each control's own curve -- linear faders, centred-unity EQs.
 */
GamepadDJ.StickLayer = class {
    constructor(name, targets) {
        this.name = name;
        this.targets = targets; // {x: (deckIndex) => target, y: ...}
        this.active = false;
        this.timer = 0;
        this.lastTick = 0;
        // Per stick: the locked axis ("x" | "y" | null at rest), the signed
        // deflection along it (+ = raise: up or right), when it left the
        // dead zone, and whether this push already slammed.
        this.axis = [null, null];
        this.value = [0, 0];
        this.leftRestAt = [0, 0];
        this.slammed = [false, false];
    }

    // trigger: 0..1; sticks: [[x, y], [x, y]] with y down-positive.
    // Returns true while the layer owns the sticks.
    update(trigger, sticks) {
        if (!this.active && trigger >= GamepadDJ.kLayerOn) {
            this.active = true;
            for (const jog of GamepadDJ.jogs) {
                jog.suspend();
            }
        } else if (this.active && trigger < GamepadDJ.kLayerOff) {
            this.active = false;
            this.stop();
            this.axis = [null, null];
            for (const jog of GamepadDJ.jogs) {
                jog.suspend(); // back to jog only once each stick is centred
            }
        }
        if (!this.active) {
            return false;
        }
        const now = Date.now();
        for (const [i, [x, y]] of sticks.entries()) {
            if (Math.max(Math.abs(x), Math.abs(y)) <= GamepadDJ.kStickDeadzone) {
                this.axis[i] = null;
                this.value[i] = 0;
                this.slammed[i] = false;
                continue;
            }
            if (!this.axis[i]) {
                this.axis[i] = Math.abs(x) > Math.abs(y) ? "x" : "y";
                this.leftRestAt[i] = now;
            }
            this.value[i] = this.axis[i] === "x" ? x : -y;
            if (!this.slammed[i] && Math.abs(this.value[i]) >= GamepadDJ.kSlamReach &&
                    now - this.leftRestAt[i] <= GamepadDJ.setting("slamMs")) {
                this.slammed[i] = true;
                this.slam(i);
            }
        }
        const moving = this.value.some((v, i) =>
            Math.abs(v) > GamepadDJ.kStickDeadzone && !this.slammed[i]);
        if (moving && !this.timer) {
            this.lastTick = now;
            this.timer = engine.beginTimer(GamepadDJ.kLayerTickMs, () => this.tick());
        } else if (!moving) {
            this.stop();
        }
        return true;
    }

    targetFor(i) {
        return this.axis[i] ? this.targets[this.axis[i]](i) : null;
    }

    tick() {
        const now = Date.now();
        const seconds = (now - this.lastTick) / 1000;
        this.lastTick = now;
        const travel = GamepadDJ.setting("faderTravelSeconds");
        const curve = GamepadDJ.setting("faderCurve");
        for (const [i, v] of this.value.entries()) {
            const target = this.targetFor(i);
            if (!target || this.slammed[i] || Math.abs(v) <= GamepadDJ.kStickDeadzone) {
                continue;
            }
            // Rescale past the dead zone so movement starts from zero, then
            // bend it so small pushes are very slow.
            const push = Math.pow(
                (Math.abs(v) - GamepadDJ.kStickDeadzone) / (1 - GamepadDJ.kStickDeadzone), curve);
            GamepadDJ.focus(i);
            if (target.before) {
                target.before(i);
            }
            const value = engine.getParameter(target.group, target.key) +
                    Math.sign(v) * push * seconds / travel;
            engine.setParameter(target.group, target.key, Math.max(0, Math.min(1, value)));
            if (target.after) {
                target.after(i);
            }
        }
    }

    slam(i) {
        const target = this.targetFor(i);
        if (!target) {
            return;
        }
        GamepadDJ.focus(i);
        if (target.before) {
            target.before(i);
        }
        const up = this.value[i] > 0;
        const end = up ?
            (target.slamUp === undefined ? 1 : target.slamUp) :
            (target.slamDown === undefined ? 0 : target.slamDown);
        engine.setParameter(target.group, target.key, end);
        if (target.after) {
            target.after(i);
        }
    }

    stop() {
        if (this.timer) {
            engine.stopTimer(this.timer);
            this.timer = 0;
        }
    }
};

/**
 * Sorts one stick's pushes in the base state (no modifier) between the
 * channel fader and the jog. Rest = undecided; the first report past
 * kFaderDecideRadius decides for the rest of the push: "fader" if the push
 * is within kFaderSectorDeg of straight up/down (the jog is told to wait for
 * the centre), "jog" otherwise (the jog grabs at grabRadius as always).
 * While L2 owns the sticks, block() parks the push until the next rest.
 */
GamepadDJ.BasePush = class {
    constructor(index) {
        this.index = index;
        this.mode = null; // null = at rest / undecided, "fader", "jog", "blocked"
    }

    // x, y as SDL reports them (y down-positive). True while the fader owns
    // this stick.
    update(x, y) {
        const r = Math.sqrt(x * x + y * y);
        if (r <= GamepadDJ.kStickDeadzone) {
            this.mode = null;
            return false;
        }
        // Never later than the jog's own grab (grabRadius can be set low).
        const decideAt = Math.min(GamepadDJ.kFaderDecideRadius, GamepadDJ.setting("grabRadius"));
        if (this.mode === null && r >= decideAt) {
            const sector = Math.tan(GamepadDJ.kFaderSectorDeg * Math.PI / 180);
            this.mode = Math.abs(x) <= Math.abs(y) * sector ? "fader" : "jog";
            if (this.mode === "fader") {
                GamepadDJ.jogs[this.index].suspend();
                if (GamepadDJ.setting("logJog")) {
                    console.log(`Gamepad DJ: deck ${this.index + 1} fader push`);
                }
            }
        }
        return this.mode === "fader";
    }

    block() {
        this.mode = "blocked";
    }
};

GamepadDJ.targets = {
    fader: (i) => ({group: `[Channel${i + 1}]`, key: "volume"}),
    // EQs: a slam down kills the band, a slam up snaps it back to neutral
    // (0.5 normalised = unity gain) -- kill and return, not full boost.
    low: (i) => ({group: `[EqualizerRack1_[Channel${i + 1}]_Effect1]`, key: "parameter1", slamUp: 0.5}),
    mid: (i) => ({group: `[EqualizerRack1_[Channel${i + 1}]_Effect1]`, key: "parameter2", slamUp: 0.5}),
    high: (i) => ({group: `[EqualizerRack1_[Channel${i + 1}]_Effect1]`, key: "parameter3", slamUp: 0.5}),
    // The deck's quick effect (a filter by default): left = low-pass, right =
    // high-pass, centre = off. A slam either way snaps it back to neutral.
    filter: (i) => ({
        group: `[QuickEffectRack1_[Channel${i + 1}]]`, key: "super1", slamUp: 0.5, slamDown: 0.5,
    }),
    // The deck's effect unit: its wet/dry mix, switched on for the deck
    // whenever the mix is above zero. Units start switched off with the mix
    // at 100%, so a unit that's off for this deck counts as mix 0.
    fx: (i) => ({
        group: `[EffectRack1_EffectUnit${i + 1}]`,
        key: "mix",
        before: (deck) => {
            const unit = `[EffectRack1_EffectUnit${deck + 1}]`;
            if (!engine.getValue(unit, `group_[Channel${deck + 1}]_enable`)) {
                engine.setParameter(unit, "mix", 0);
            }
        },
        after: (deck) => {
            const unit = `[EffectRack1_EffectUnit${deck + 1}]`;
            engine.setValue(unit, `group_[Channel${deck + 1}]_enable`,
                engine.getValue(unit, "mix") > 0 ? 1 : 0);
        },
    }),
};

// --- Touchpads -> FX XY pads -------------------------------------------

/**
 * The controller's touchpads as the FX screen's XY pads. The pad on screen
 * owns the effect logic (which parameter is X for the chosen effect, Hold,
 * switching the unit on and off); this only tells it where the finger is
 * through the [OpenDecks] fxN_touch / fxN_x / fxN_y controls, as if the finger
 * were on the screen.
 *
 * A pad with two touchpads (Steam Deck) uses the left one for deck 1 and
 * the right one for deck 2. A single touchpad (DualSense) is split down the
 * middle: a finger landing on the left half plays deck 1, on the right half
 * deck 2, and stays with that deck until it lifts, so it may slide across
 * the middle. A second finger takes whichever deck is free.
 */
GamepadDJ.TouchPads = class {
    constructor() {
        // Per finger slot (touchpad-major): the deck index it's playing, or -1.
        this.deckOfSlot = new Array(GamepadDJ.kMaxTouchpads * GamepadDJ.kMaxFingers).fill(-1);
        this.touching = [false, false];
    }

    // fingers: [{down, x, y}] per slot, x/y 0..1 with y down-positive.
    update(touchpads, fingers) {
        const taken = [false, false];
        const next = new Array(fingers.length).fill(-1);
        // Fingers already playing a deck keep it.
        for (const [slot, finger] of fingers.entries()) {
            const deck = this.deckOfSlot[slot];
            if (finger.down && deck >= 0 && !taken[deck]) {
                next[slot] = deck;
                taken[deck] = true;
            }
        }
        // New fingers: the touchpad they're on, or the half they landed in.
        for (const [slot, finger] of fingers.entries()) {
            if (!finger.down || next[slot] >= 0) {
                continue;
            }
            const pad = Math.floor(slot / GamepadDJ.kMaxFingers);
            let deck = touchpads >= 2 ? pad : (finger.x < 0.5 ? 0 : 1);
            if (taken[deck]) {
                deck = 1 - deck;
                if (taken[deck] || touchpads >= 2) {
                    continue; // both decks busy, or the other trackpad's deck
                }
            }
            next[slot] = deck;
            taken[deck] = true;
        }
        this.deckOfSlot = next;

        for (const deck of [0, 1]) {
            const slot = next.indexOf(deck);
            if (slot < 0) {
                if (this.touching[deck]) {
                    this.touching[deck] = false;
                    engine.setValue("[OpenDecks]", `fx${deck + 1}_touch`, 0);
                    if (GamepadDJ.setting("logJog")) {
                        console.log(`Gamepad DJ: touchpad lifted from deck ${deck + 1}'s FX pad`);
                    }
                }
                continue;
            }
            const finger = fingers[slot];
            // One touchpad shared by both decks: each half is a whole pad.
            const x = touchpads >= 2 ? finger.x :
                Math.max(0, Math.min(1, (finger.x - (deck === 0 ? 0 : 0.5)) * 2));
            const y = 1 - finger.y;
            engine.setValue("[OpenDecks]", `fx${deck + 1}_x`, x);
            engine.setValue("[OpenDecks]", `fx${deck + 1}_y`, y);
            if (!this.touching[deck]) {
                this.touching[deck] = true;
                GamepadDJ.focus(deck);
                if (GamepadDJ.setting("touchpadShowsFx")) {
                    engine.setValue("[OpenDecks]", "tab", 2);
                }
                engine.setValue("[OpenDecks]", `fx${deck + 1}_touch`, 1);
                if (GamepadDJ.setting("logJog")) {
                    console.log(`Gamepad DJ: touchpad on deck ${deck + 1}'s FX pad ` +
                        `at ${x.toFixed(2)}, ${y.toFixed(2)}`);
                }
            }
        }
    }

    releaseAll() {
        this.update(0, []);
    }
};

// --- Library -----------------------------------------------------------

GamepadDJ.scroll = function(direction) {
    if (GamepadDJ.setting("logJog")) {
        console.log(`Gamepad DJ: library ${direction < 0 ? "up" : "down"} ` +
            `(focus ${engine.getValue("[Library]", "focused_widget")})`);
    }
    engine.setValue("[Library]", direction < 0 ? "MoveUp" : "MoveDown", 1);
};

GamepadDJ.startScroll = function(direction) {
    GamepadDJ.stopScroll();
    GamepadDJ.scroll(direction);
    GamepadDJ.scrollTimer = engine.beginTimer(GamepadDJ.kScrollRepeatDelayMs, () => {
        GamepadDJ.scrollTimer = engine.beginTimer(GamepadDJ.kScrollRepeatMs, () => {
            GamepadDJ.scroll(direction);
        });
    }, true);
};

GamepadDJ.stopScroll = function() {
    if (GamepadDJ.scrollTimer) {
        engine.stopTimer(GamepadDJ.scrollTimer);
        GamepadDJ.scrollTimer = 0;
    }
};

GamepadDJ.loadSelected = function(deck) {
    engine.setValue(`[Channel${deck}]`, "LoadSelectedTrack", 1);
};

// Returns true if the button belonged to the library layer.
GamepadDJ.libraryButton = function(bit, pressed, buttons) {
    const B = GamepadDJ.Button;
    if (bit === B.back) {
        if (pressed) {
            // An empty deck first, then one that isn't playing.
            const decks = [1, 2];
            const deck =
                decks.find((d) => !engine.getValue(`[Channel${d}]`, "track_loaded")) ||
                decks.find((d) => !engine.getValue(`[Channel${d}]`, "play"));
            if (deck) {
                GamepadDJ.loadSelected(deck);
            }
        }
        return true;
    }
    const browsing = (buttons & (1 << B.start)) !== 0;
    if (bit === B.start) {
        if (pressed) {
            // [Library] MoveUp/MoveDown act on whichever library pane has
            // keyboard focus; after a click on a knob or deck that's none of
            // them, and scrolling silently does nothing.
            if (engine.getValue("[Library]", "focused_widget") !== GamepadDJ.kFocusTracks) {
                engine.setValue("[Library]", "focused_widget", GamepadDJ.kFocusTracks);
            }
        } else {
            GamepadDJ.stopScroll();
        }
        return true;
    }
    if (!browsing && !(bit === B.dpadUp || bit === B.dpadDown) ) {
        return false;
    }
    if (!browsing) {
        // D-pad up/down outside the browse layer belong to deck 1; make sure
        // a scroll started in the layer stops when its button comes up.
        if (!pressed && GamepadDJ.scrollTimer) {
            GamepadDJ.stopScroll();
            return true;
        }
        return false;
    }
    switch (bit) {
    case B.dpadUp:
    case B.dpadDown:
        if (pressed) {
            GamepadDJ.startScroll(bit === B.dpadUp ? -1 : 1);
        } else {
            GamepadDJ.stopScroll();
        }
        return true;
    case B.dpadLeft:
    case B.dpadRight:
        if (pressed) {
            GamepadDJ.loadSelected(bit === B.dpadLeft ? 1 : 2);
        }
        return true;
    default:
        return false;
    }
};

// --- Lifecycle and input -----------------------------------------------

GamepadDJ.init = function(id) {
    const B = GamepadDJ.Button;
    GamepadDJ.jogs = [new GamepadDJ.Jog(1), new GamepadDJ.Jog(2)];
    const T = GamepadDJ.targets;
    // L2 + stick (user, 2026-10-27, one layer): up/down = the EQ band picked
    // with that deck's buttons, left/right = filter. R2 is free. (Tempo stays
    // off the controller: sync, or the touch fader.)
    GamepadDJ.layer = new GamepadDJ.StickLayer("L2",
        {y: (i) => T[GamepadDJ.bandName()](i), x: T.filter});
    // One EQ pick for both decks (user, 2026-10-27: "A/B/Y select both
    // channels' EQ at the same time, that feels intuitive and opens up the
    // D-pad"): 1 low, 2 mid, 3 high. Sticky; the thumb can't hold a button
    // and push the stick. Works with L2 held too.
    GamepadDJ.band = 1;
    GamepadDJ.bandButton = {[B.south]: 1, [B.east]: 2, [B.north]: 3};
    // No modifier: a straight up/down push is the channel fader (speed,
    // curve and slam as in the layers); everything else is the jog. The
    // layer is switched on once and fed only the sticks BasePush gives it.
    GamepadDJ.faderLayer = new GamepadDJ.StickLayer("fader", {y: T.fader, x: () => null});
    GamepadDJ.basePushes = [new GamepadDJ.BasePush(0), new GamepadDJ.BasePush(1)];
    GamepadDJ.decks = [
        // Deck 1 = D-pad, deck 2 = face buttons (user, 2026-10-26):
        //   left / X   = FX on/off      down / A = select low EQ
        //   right / B  = select mid     up / Y   = select high
        // Cue is on the bumpers; play on the stick clicks. Vinyl mode, sync
        // and loops are on the touch UI (seldom used -> not under a thumb).
        new GamepadDJ.Deck(1, {play: B.leftStick, fxOn: B.dpadLeft}),
        new GamepadDJ.Deck(2, {play: B.rightStick, fxOn: B.west}),
        // D-pad up / down / right are free (outside the Options browse layer).
    ];
    GamepadDJ.deckOfButton = {};
    for (const [index, deck] of GamepadDJ.decks.entries()) {
        for (const bit of Object.values(deck.buttons)) {
            GamepadDJ.deckOfButton[bit] = index;
        }
    }
    GamepadDJ.touchPads = new GamepadDJ.TouchPads();
    // Vinyl mode is a badge on the touch UI ([OpenDecks] vinylN, QML builds
    // from 2026-10-26 on); older builds lack the control and keep it off.
    for (const jog of GamepadDJ.jogs) {
        const conn = engine.makeConnection("[OpenDecks]", `vinyl${jog.deck}`, (v) => jog.setVinyl(v > 0));
        if (conn) {
            conn.trigger();
        }
    }
    GamepadDJ.lastButtons = 0;
    GamepadDJ.scrollTimer = 0;
    GamepadDJ.focusedDeck = 0;
    GamepadDJ.bumperAction = {}; // per bumper bit: "cue" | "set" | "tab" while held
    console.log(`Gamepad DJ: ready on ${id}`);
    if (GamepadDJ.setting("logJog")) {
        const names = ["secondsPerTurn", "nudgeSensitivity", "grabRadius", "holdRadius",
            "releaseRadius", "releaseMs", "maxStepTurns"];
        console.log(`Gamepad DJ: settings ${names.map((n) => `${n}=${GamepadDJ.setting(n)}`).join(" ")}`);
    }
    GamepadDJ.reportCount = 0;
};

GamepadDJ.shutdown = function() {
    GamepadDJ.stopScroll();
    GamepadDJ.layer.stop();
    GamepadDJ.faderLayer.stop();
    for (const bit of Object.keys(GamepadDJ.bumperAction)) {
        if (GamepadDJ.bumperAction[bit] === "cue") {
            engine.setValue(`[Channel${Number(bit) === GamepadDJ.Button.leftShoulder ? 1 : 2}]`, "cue_default", 0);
        }
    }
    GamepadDJ.bumperAction = {};
    for (const jog of GamepadDJ.jogs) {
        jog.release();
    }
    GamepadDJ.touchPads.releaseAll();
};

GamepadDJ.incomingData = function(data, length) {
    if (length < GamepadDJ.kReportSizeV1) {
        return;
    }
    // The engine hands the report over as an indexable byte array, not an
    // ArrayBuffer; copy it into one so DataView can decode the int16/uint32s.
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : Uint8Array.from(data);
    const view = new DataView(bytes.buffer);
    const version = view.getUint8(0);
    if (version < 1 || version > GamepadDJ.kReportVersion) {
        return;
    }
    const axis = (i) => {
        const v = view.getInt16(1 + 2 * i, true);
        return v < 0 ? v / 32768 : v / 32767;
    };
    const buttons = view.getUint32(13, true);

    if (GamepadDJ.setting("logJog") && GamepadDJ.reportCount++ % 100 === 0) {
        const r = (x, y) => Math.sqrt(x * x + y * y).toFixed(2);
        console.log(`Gamepad DJ: report ${GamepadDJ.reportCount} left r=${r(axis(0), axis(1))} ` +
            `right r=${r(axis(2), axis(3))} buttons=${buttons.toString(16)}`);
    }

    // L2 (axis 4) owns the sticks while held; R2 (axis 5) does nothing.
    const sticks = [[axis(0), axis(1)], [axis(2), axis(3)]];
    if (GamepadDJ.layer.update(axis(4), sticks)) {
        for (const push of GamepadDJ.basePushes) {
            push.block();
        }
    } else {
        // Base state: each stick's push is either the fader's or the jog's.
        const faderSticks = sticks.map(([x, y], i) =>
            GamepadDJ.basePushes[i].update(x, y) ? [x, y] : [0, 0]);
        GamepadDJ.faderLayer.update(1, faderSticks);
        for (const [i, [x, y]] of sticks.entries()) {
            if (GamepadDJ.basePushes[i].mode !== "fader") {
                GamepadDJ.jogs[i].update(x, y);
            }
        }
    }

    if (version >= 2 && length >= GamepadDJ.kReportSize) {
        const touchpads = view.getUint8(21);
        const fingers = [];
        for (let slot = 0; slot < GamepadDJ.kMaxTouchpads * GamepadDJ.kMaxFingers; slot++) {
            const at = 22 + slot * 7;
            fingers.push({
                down: view.getUint8(at) !== 0,
                x: view.getUint16(at + 1, true) / 65535,
                y: view.getUint16(at + 3, true) / 65535,
            });
        }
        GamepadDJ.touchPads.update(touchpads, fingers);
    }

    const changed = buttons ^ GamepadDJ.lastButtons;
    GamepadDJ.lastButtons = buttons;
    if (!changed) {
        return;
    }
    const B = GamepadDJ.Button;
    for (let bit = 0; bit < 32; bit++) {
        if (!(changed & (1 << bit))) {
            continue;
        }
        const pressed = (buttons & (1 << bit)) !== 0;
        if (GamepadDJ.libraryButton(bit, pressed, buttons)) {
            continue;
        }
        if (bit === B.leftShoulder || bit === B.rightShoulder) {
            // Bumpers (user, 2026-10-26): L1 = deck 1's cue, R1 = deck 2's,
            // with Mixxx's normal cue behaviour. While that side's stick holds
            // the platter a tap sets the cue right there instead. With the top
            // bar focused on screen they switch tabs. (They may go back to
            // being nudge buttons if stray cue presses turn out to be a problem.)
            const index = bit === B.leftShoulder ? 0 : 1;
            const jog = GamepadDJ.jogs[index];
            const group = `[Channel${index + 1}]`;
            if (pressed) {
                if (GamepadDJ.uiFocus() === 3) {
                    const key = bit === B.leftShoulder ? "tab_prev" : "tab_next";
                    console.log(`Gamepad DJ: ${key} (top bar focused, tab ${engine.getValue("[OpenDecks]", "tab")})`);
                    engine.setValue("[OpenDecks]", key, 1);
                    engine.setValue("[OpenDecks]", key, 0);
                    GamepadDJ.bumperAction[bit] = "tab";
                } else if (jog.grabbed) {
                    engine.setValue(group, "cue_set", 1);
                    console.log(`Gamepad DJ: deck ${index + 1} cue set`);
                    GamepadDJ.bumperAction[bit] = "set";
                } else {
                    GamepadDJ.focus(index);
                    engine.setValue(group, "cue_default", 1);
                    GamepadDJ.bumperAction[bit] = "cue";
                }
            } else {
                // Release only what the press started: a cue press must get
                // its release (preview stops), a tab or set tap must not
                // release a cue it never pressed.
                if (GamepadDJ.bumperAction[bit] === "cue") {
                    engine.setValue(group, "cue_default", 0);
                }
                delete GamepadDJ.bumperAction[bit];
            }
            continue;
        }
        if (GamepadDJ.bandButton[bit] !== undefined) {
            if (pressed) {
                GamepadDJ.band = GamepadDJ.bandButton[bit];
                console.log(`Gamepad DJ: L2 up/down now controls the ${GamepadDJ.bandName()} EQ on both decks`);
            }
            continue;
        }
        const deckIndex = GamepadDJ.deckOfButton[bit];
        if (deckIndex !== undefined) {
            GamepadDJ.decks[deckIndex].button(bit, pressed);
        }
    }
};
