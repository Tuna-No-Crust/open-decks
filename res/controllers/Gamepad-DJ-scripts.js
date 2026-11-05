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
// Screens (user, 2026-11-05: "switching menus should change the controls,
// I shouldn't be able to mess with songs and faders in the library page"):
// the controller follows the touch UI's tab ([OpenDecks] tab).
//   Perform, FX       the performance layout below
//   Library, Settings the browse layout: jog, faders, EQ, cue, play and the
//                     touchpads are off, the sticks and bumpers browse instead
// Leaving Perform/FX lets go of everything in progress (a held cue, a held
// platter, a fader or L2 push, a touchpad finger), and a stick that was
// pushed has to come back to rest before it does anything on the new screen.
//   Switch screens              Options = next tab, Create = previous tab, on every screen
//
// Performance layout (left hand = deck 1, right hand = deck 2):
//   Play                        click the left stick (L3)   click the right stick (R3)
//   Jog                         turn the stick (always, unless a pick is armed)
//   Pick for the sticks         tap X (Square) = channel fader, A (Cross) = low EQ,
//                               B (Circle) = mid, Y (Triangle) = high
//   Cue                         L1 = deck 1, R1 = deck 2 (Mixxx's normal cue button);
//                               on a playing deck only after a cueHoldMs hold, so a
//                               brush can't stop the track; tap while that side's
//                               stick holds the platter = set the cue right there
//   Vinyl mode / sync / loops   on the touch UI (deck panel badges and loop chips)
//   Hot cues                    on screen (touch pads), not on the controller
//   FX on / off                 the touchpads and the screen only
//   Picks (user, 2026-11-05: "remove the L2 layer entirely, tapping ABXY
//   selects a fader or EQ band to use", after the bare-stick fader kept
//   firing while jogging or nudging): a tap arms both sticks for the picked
//   control -- up/down on each stick moves its own deck's fader or band --
//   and they go back to being jogs once both have been at rest for pickHoldMs.
//   A stick that is holding the platter when the tap comes keeps jogging
//   until it is back at rest. Combos: press one while holding another and
//   both are armed (A+B = low and mid together). The armed controls light
//   up on screen ([OpenDecks] pick, bits: 1 low, 2 mid, 4 high, 8 fader). L2
//   and R2 do nothing; the filter is on the touch screen.
//   The sticks spring back, so they move a fader/knob at a speed set by how
//   far they're pushed (on a curve, for fine slow fades), and letting go
//   leaves it where it is. Slamming a stick from rest to the edge jumps
//   straight to the end: faders to 100/0, EQs to kill (down) or neutral (up).
//   FX XY pads                  the controller's touchpads play the FX screen's
//   pads: a finger on the Steam Deck's left / right trackpad (or the left /
//   right half of a DualSense touchpad) is a finger on deck 1's / deck 2's pad.
//   Touch = effect on, slide = X (the effect's parameter) and Y (wet), lift =
//   off unless Hold is on; the pad on screen follows the finger.
//
// Browse layout (Library, Settings):
//   Tracks                      left stick or D-pad up / down (the further the
//                               stick is pushed, the faster the list moves)
//   Playlists                   right stick up / down
//   Load the highlighted track  L1 = deck 1, R1 = deck 2 (the sides of their cue);
//                               A = an empty deck, else one that isn't playing
//                               (never onto a playing deck: the UI refuses it)
//
// The focused deck is the one tapped on the touchscreen, else the last deck
// used from the controller.

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
GamepadDJ.kStickDeadzone = 0.15;
GamepadDJ.kLayerTickMs = 15;
// Inward motion this many times larger than the motion around the rim means
// the stick is springing back to the centre, not turning.
GamepadDJ.kSpringBackRatio = 2;
GamepadDJ.kSpringBackMinStep = 0.01;
GamepadDJ.kScrollRepeatDelayMs = 300;
GamepadDJ.kScrollRepeatMs = 90;
// Browse layout: a stick scrolls a list once it is pushed past kListStickOn
// up or down (and stops below kListStickOff), one step at once, then one
// every slowMs at that threshold down to fastMs at full push.
GamepadDJ.kListStickOn = 0.35;
GamepadDJ.kListStickOff = 0.25;
GamepadDJ.kTrackListMs = {slowMs: 260, fastMs: 35};
GamepadDJ.kPlaylistMs = {slowMs: 450, fastMs: 160};
// What A / B / Y / X arm the sticks for; [OpenDecks] pick has bit N set
// while kPicks[N] is armed.
GamepadDJ.kPicks = ["low", "mid", "high", "fader"];
// [OpenDecks] tab: 0 Perform, 1 Library, 2 FX, 3 Settings.
GamepadDJ.kBrowseTabs = [1, 3];
GamepadDJ.kFocusTracks = 3; // [Library] focused_widget: FocusWidget::TracksTable

GamepadDJ.kSettingFallbacks = {
    faderTravelSeconds: 0.35,
    faderCurve: 1.8,
    slamMs: 80,
    pickHoldMs: 1500,
    cueHoldMs: 250,
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

// One deck's buttons: play (stick click). Cue lives on the bumpers, the
// picks on the face buttons. (Hot cues, vinyl, sync, loops and FX on/off
// live on the touchscreen and touchpads. L2 + a button used to toggle vinyl
// / sync / loop; dropped 2026-10-26 after a stray L2 + A put deck 2 in vinyl
// mode.)
GamepadDJ.Deck = class {
    constructor(deck, buttons) {
        this.deck = deck;
        this.group = `[Channel${deck}]`;
        // {play} -> button bit.
        this.buttons = buttons;
    }

    // Called for each button of this deck whose state changed.
    button(bit, pressed) {
        if (pressed) {
            GamepadDJ.focus(this.deck - 1);
        }
        if (bit === this.buttons.play && pressed) {
            GamepadDJ.togglePlay(this.group);
        }
    }
};

// --- Stick layers ------------------------------------------------------

/**
 * Moves faders and knobs with the sticks it is fed (the armed ones; a stick
 * it doesn't own is fed as [0, 0], i.e. at rest). Each stick drives values
 * of its own deck: targets.y for up/down and targets.x for left/right. A
 * push locks to the axis it starts along (the larger component as it leaves
 * the dead zone) until the stick is back at rest, so a slightly diagonal
 * fade doesn't also move the other control.
 *
 * A stick springs back to the centre, so it sets the *speed*: full deflection
 * sweeps the whole range in faderTravelSeconds, bent by faderCurve so small
 * pushes are very slow. Reports only come when the pad changes, so a timer
 * keeps the value moving while a stick is held still off-centre. Slamming
 * from the dead zone to kSlamReach within slamMs jumps the value to its end
 * instead: target.slamUp (default 1) or target.slamDown (default 0).
 *
 * targets.x / .y map a deck index to a list of {group, key, slamUp?,
 * slamDown?} (empty = "nothing"). Values move with get/setParameter (normalised 0..1), which
 * follows each control's own curve -- linear faders, centred-unity EQs.
 */
GamepadDJ.StickLayer = class {
    constructor(name, targets) {
        this.name = name;
        this.targets = targets; // {x: (deckIndex) => [target], y: ...}
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

    // sticks: [[x, y], [x, y]] with y down-positive.
    update(sticks) {
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
    }

    // The targets stick i moves along its locked axis (a list: a combo pick
    // moves several at once).
    targetsFor(i) {
        return this.axis[i] ? this.targets[this.axis[i]](i) : [];
    }

    tick() {
        const now = Date.now();
        const seconds = (now - this.lastTick) / 1000;
        this.lastTick = now;
        const travel = GamepadDJ.setting("faderTravelSeconds");
        const curve = GamepadDJ.setting("faderCurve");
        for (const [i, v] of this.value.entries()) {
            const targets = this.targetsFor(i);
            if (!targets.length || this.slammed[i] || Math.abs(v) <= GamepadDJ.kStickDeadzone) {
                continue;
            }
            // Rescale past the dead zone so movement starts from zero, then
            // bend it so small pushes are very slow.
            const push = Math.pow(
                (Math.abs(v) - GamepadDJ.kStickDeadzone) / (1 - GamepadDJ.kStickDeadzone), curve);
            GamepadDJ.focus(i);
            for (const target of targets) {
                const value = engine.getParameter(target.group, target.key) +
                        Math.sign(v) * push * seconds / travel;
                engine.setParameter(target.group, target.key, Math.max(0, Math.min(1, value)));
            }
        }
    }

    slam(i) {
        const targets = this.targetsFor(i);
        if (!targets.length) {
            return;
        }
        GamepadDJ.focus(i);
        const up = this.value[i] > 0;
        for (const target of targets) {
            const end = up ?
                (target.slamUp === undefined ? 1 : target.slamUp) :
                (target.slamDown === undefined ? 0 : target.slamDown);
            engine.setParameter(target.group, target.key, end);
        }
    }

    stop() {
        if (this.timer) {
            engine.stopTimer(this.timer);
            this.timer = 0;
        }
    }

    // The screen changed or the pick ended: drop any push in progress.
    reset() {
        this.stop();
        this.axis = [null, null];
        this.value = [0, 0];
        this.slammed = [false, false];
    }
};

/**
 * The face-button picks. A tap on A / B / Y / X arms both sticks for the low
 * / mid / high EQ or the channel fader. Pressing one while another is still
 * held adds it (user, 2026-11-05: "A and B select 2 EQ bands"), so A+B moves
 * low and mid together; a press with none held starts a new pick. Each
 * stick then belongs either to
 * its jog or to the pick, decided when it leaves rest (so a stick holding
 * the platter at the tap keeps jogging until it lets go). Once both sticks
 * have been at rest for pickHoldMs the pick ends and they are jogs again.
 */
GamepadDJ.Picks = class {
    constructor() {
        this.pick = []; // the armed GamepadDJ.kPicks names; empty = jog
        this.owner = [null, null]; // per stick while pushed: "jog" | "pick"
        this.timer = 0;
        this.layer = new GamepadDJ.StickLayer("pick",
            {y: (i) => this.pick.map((name) => GamepadDJ.targets[name](i)), x: () => []});
    }

    // add: keep what is armed (a combo), else replace it.
    arm(name, add) {
        if (!add) {
            this.pick = [];
        }
        if (!this.pick.includes(name)) {
            this.pick.push(name);
        }
        this.show();
        console.log(`Gamepad DJ: sticks armed for ${this.pick.join(" + ")}`);
        this.restartTimer();
    }

    disarm() {
        this.stopTimer();
        this.layer.reset();
        if (this.pick.length) {
            this.pick = [];
            this.show();
            console.log("Gamepad DJ: sticks back to jog");
        }
    }

    // The screen changed: drop the pick, and sticks that are pushed now
    // count as the jog's until they are back at rest.
    reset() {
        this.disarm();
        this.owner = this.owner.map((o) => (o ? "jog" : null));
    }

    show() {
        if (GamepadDJ.hasPickControl) {
            // A bit per armed control: 1 low, 2 mid, 4 high, 8 fader.
            engine.setValue("[OpenDecks]", "pick", this.pick.reduce(
                (bits, name) => bits | (1 << GamepadDJ.kPicks.indexOf(name)), 0));
        }
    }

    // sticks: [[x, y], [x, y]], y down-positive. Feeds the jogs and the layer.
    update(sticks) {
        for (const [i, [x, y]] of sticks.entries()) {
            const resting = Math.sqrt(x * x + y * y) <= GamepadDJ.kStickDeadzone;
            if (resting) {
                this.owner[i] = null;
            } else if (!this.owner[i]) {
                this.owner[i] = this.pick.length ? "pick" : "jog";
                if (this.owner[i] === "pick") {
                    GamepadDJ.jogs[i].release();
                }
            }
            if (this.owner[i] !== "pick") {
                GamepadDJ.jogs[i].update(x, y);
            }
        }
        if (!this.pick.length) {
            return;
        }
        this.layer.update(sticks.map((s, i) => (this.owner[i] === "pick" ? s : [0, 0])));
        if (this.owner.includes("pick")) {
            this.stopTimer();
        } else if (!this.timer) {
            this.restartTimer();
        }
    }

    restartTimer() {
        this.stopTimer();
        this.timer = engine.beginTimer(GamepadDJ.setting("pickHoldMs"), () => {
            this.timer = 0;
            if (!this.owner.includes("pick")) {
                this.disarm();
            }
        }, true);
    }

    stopTimer() {
        if (this.timer) {
            engine.stopTimer(this.timer);
            this.timer = 0;
        }
    }
};

GamepadDJ.targets = {
    fader: (i) => ({group: `[Channel${i + 1}]`, key: "volume"}),
    // EQs: a slam down kills the band, a slam up snaps it back to neutral
    // (0.5 normalised = unity gain) -- kill and return, not full boost.
    low: (i) => ({group: `[EqualizerRack1_[Channel${i + 1}]_Effect1]`, key: "parameter1", slamUp: 0.5}),
    mid: (i) => ({group: `[EqualizerRack1_[Channel${i + 1}]_Effect1]`, key: "parameter2", slamUp: 0.5}),
    high: (i) => ({group: `[EqualizerRack1_[Channel${i + 1}]_Effect1]`, key: "parameter3", slamUp: 0.5}),
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

// An empty deck first, then one that isn't playing.
GamepadDJ.loadSelectedAnywhere = function() {
    const decks = [1, 2];
    const deck =
        decks.find((d) => !engine.getValue(`[Channel${d}]`, "track_loaded")) ||
        decks.find((d) => !engine.getValue(`[Channel${d}]`, "play"));
    if (deck) {
        GamepadDJ.loadSelected(deck);
    }
};

GamepadDJ.movePlaylist = function(direction) {
    if (GamepadDJ.setting("logJog")) {
        console.log(`Gamepad DJ: playlist ${direction < 0 ? "up" : "down"}`);
    }
    // Upstream's sidebar controls; the touch Library listens to them (the
    // classic sidebar widget doesn't exist in the touch UI, so Mixxx itself
    // ignores them there).
    engine.setValue("[Playlist]", direction < 0 ? "SelectPrevPlaylist" : "SelectNextPlaylist", 1);
};

/**
 * One stick scrolling a list in the browse layout. Up or down past
 * kListStickOn takes one step at once, then repeats while the stick is held,
 * every rates.slowMs at the threshold down to rates.fastMs at full push (the
 * interval is re-read each step, so pushing further speeds it up). Below
 * kListStickOff it stops. step(direction) is called with -1 = up, +1 = down.
 */
GamepadDJ.ListStick = class {
    constructor(rates, step) {
        this.rates = rates;
        this.step = step;
        this.direction = 0;
        this.push = 0;
        this.timer = 0;
        this.waitForRest = false;
    }

    // y as SDL reports it (down-positive).
    update(y) {
        const push = Math.abs(y);
        if (this.waitForRest) {
            if (push > GamepadDJ.kStickDeadzone) {
                return;
            }
            this.waitForRest = false;
        }
        this.push = push;
        if (this.direction && push < GamepadDJ.kListStickOff) {
            this.stop();
        } else if (!this.direction && push >= GamepadDJ.kListStickOn) {
            this.direction = Math.sign(y);
            this.step(this.direction);
            this.schedule();
        } else if (this.direction && Math.sign(y) !== this.direction) {
            this.stop(); // flicked straight through to the other side
        }
    }

    schedule() {
        const span = Math.max(0, Math.min(1,
            (this.push - GamepadDJ.kListStickOn) / (1 - GamepadDJ.kListStickOn)));
        const ms = this.rates.slowMs + (this.rates.fastMs - this.rates.slowMs) * span;
        this.timer = engine.beginTimer(Math.round(ms), () => {
            this.timer = 0;
            if (this.direction) {
                this.step(this.direction);
                this.schedule();
            }
        }, true);
    }

    stop() {
        this.direction = 0;
        if (this.timer) {
            engine.stopTimer(this.timer);
            this.timer = 0;
        }
    }

    // The screen changed: stop, and ignore the stick until it is back at rest.
    reset() {
        this.stop();
        this.waitForRest = true;
    }
};

// The browse layout's buttons (Library, Settings). Everything not listed
// here does nothing on those screens.
GamepadDJ.browseButton = function(bit, pressed) {
    const B = GamepadDJ.Button;
    switch (bit) {
    case B.dpadUp:
    case B.dpadDown:
        if (pressed) {
            GamepadDJ.startScroll(bit === B.dpadUp ? -1 : 1);
        } else {
            GamepadDJ.stopScroll();
        }
        break;
    case B.leftShoulder:
    case B.rightShoulder:
        if (pressed) {
            GamepadDJ.loadSelected(bit === B.leftShoulder ? 1 : 2);
        }
        break;
    case B.south:
        if (pressed) {
            GamepadDJ.loadSelectedAnywhere();
        }
        break;
    }
};

// Options / Create = next / previous screen, on every screen. True if the
// button was one of them.
GamepadDJ.tabButton = function(bit, pressed) {
    const B = GamepadDJ.Button;
    if (bit !== B.start && bit !== B.back) {
        return false;
    }
    if (pressed) {
        const key = bit === B.start ? "tab_next" : "tab_prev";
        engine.setValue("[OpenDecks]", key, 1);
        engine.setValue("[OpenDecks]", key, 0);
    }
    return true;
};

// A bumper's cue press on deck index (Mixxx's cue_default; released when
// the bumper comes up).
GamepadDJ.cue = function(bit, index) {
    GamepadDJ.focus(index);
    engine.setValue(`[Channel${index + 1}]`, "cue_default", 1);
    GamepadDJ.bumperAction[bit] = "cue";
};

GamepadDJ.cancelCueHold = function(bit) {
    if (GamepadDJ.cueTimer[bit]) {
        engine.stopTimer(GamepadDJ.cueTimer[bit]);
        GamepadDJ.cueTimer[bit] = 0;
    }
};

// Called whenever [OpenDecks] tab changes (from the controller or a tap on
// screen). Switching between the performance and the browse layout lets go
// of everything the other one was doing.
GamepadDJ.setScreen = function(tab) {
    const browsing = GamepadDJ.kBrowseTabs.includes(Math.round(tab));
    if (browsing === GamepadDJ.browsing) {
        return;
    }
    GamepadDJ.browsing = browsing;
    console.log(`Gamepad DJ: ${browsing ? "browse" : "performance"} controls (tab ${tab})`);
    GamepadDJ.releaseAll();
};

// Let go of everything in progress, in both layouts. Sticks that are pushed
// right now must come back to rest before they do anything again.
GamepadDJ.releaseAll = function() {
    GamepadDJ.stopScroll();
    for (const list of GamepadDJ.listSticks) {
        list.reset();
    }
    GamepadDJ.picks.reset();
    for (const jog of GamepadDJ.jogs) {
        jog.suspend();
    }
    for (const bit of Object.keys(GamepadDJ.bumperAction)) {
        if (GamepadDJ.bumperAction[bit] === "cue") {
            engine.setValue(`[Channel${Number(bit) === GamepadDJ.Button.leftShoulder ? 1 : 2}]`, "cue_default", 0);
        }
        GamepadDJ.cancelCueHold(bit);
        // Still held: its release belongs to nobody now.
        GamepadDJ.bumperAction[bit] = "done";
    }
    GamepadDJ.touchPads.releaseAll();
};

// --- Lifecycle and input -----------------------------------------------

GamepadDJ.init = function(id) {
    const B = GamepadDJ.Button;
    GamepadDJ.jogs = [new GamepadDJ.Jog(1), new GamepadDJ.Jog(2)];
    // A / B / Y / X arm the sticks (user, 2026-11-05); see GamepadDJ.Picks.
    GamepadDJ.pickButton = {[B.south]: "low", [B.east]: "mid", [B.north]: "high", [B.west]: "fader"};
    GamepadDJ.pickMask = Object.keys(GamepadDJ.pickButton).reduce((m, b) => m | (1 << Number(b)), 0);
    GamepadDJ.picks = new GamepadDJ.Picks();
    // The highlight on screen needs a build with [OpenDecks] pick (2026-11-05);
    // older ones just don't show it.
    GamepadDJ.hasPickControl = Boolean(engine.makeConnection("[OpenDecks]", "pick", () => {}));
    GamepadDJ.picks.show();
    GamepadDJ.decks = [
        // Cue is on the bumpers, the picks on the face buttons. Vinyl mode,
        // sync, loops and FX on/off are on the touch UI and touchpads (seldom
        // used -> not under a thumb). The D-pad is free.
        new GamepadDJ.Deck(1, {play: B.leftStick}),
        new GamepadDJ.Deck(2, {play: B.rightStick}),
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
    GamepadDJ.bumperAction = {}; // per bumper bit: "pending" | "cue" | "set" | "done" while held
    GamepadDJ.cueTimer = {}; // per bumper bit: the hold timer on a playing deck
    // Browse layout: left stick = tracks, right stick = playlists.
    GamepadDJ.listSticks = [
        new GamepadDJ.ListStick(GamepadDJ.kTrackListMs, GamepadDJ.scroll),
        new GamepadDJ.ListStick(GamepadDJ.kPlaylistMs, GamepadDJ.movePlaylist),
    ];
    // Follow the touch UI's screen. The classic UI has no [OpenDecks] tab, so
    // it keeps the performance layout.
    GamepadDJ.browsing = false;
    const tabConn = engine.makeConnection("[OpenDecks]", "tab", (v) => GamepadDJ.setScreen(v));
    if (tabConn) {
        tabConn.trigger();
    }
    console.log(`Gamepad DJ: ready on ${id}`);
    if (GamepadDJ.setting("logJog")) {
        const names = ["secondsPerTurn", "nudgeSensitivity", "grabRadius", "holdRadius",
            "releaseRadius", "releaseMs", "maxStepTurns"];
        console.log(`Gamepad DJ: settings ${names.map((n) => `${n}=${GamepadDJ.setting(n)}`).join(" ")}`);
    }
    GamepadDJ.reportCount = 0;
};

GamepadDJ.shutdown = function() {
    GamepadDJ.releaseAll();
    GamepadDJ.bumperAction = {};
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

    // L2 and R2 (axes 4 and 5) do nothing.
    const sticks = [[axis(0), axis(1)], [axis(2), axis(3)]];
    if (GamepadDJ.browsing) {
        // Browse layout: the sticks scroll lists (only up/down counts).
        for (const [i, [, y]] of sticks.entries()) {
            GamepadDJ.listSticks[i].update(y);
        }
    } else {
        GamepadDJ.picks.update(sticks);
    }

    if (version >= 2 && length >= GamepadDJ.kReportSize && !GamepadDJ.browsing) {
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
    // A pick press starts a new pick unless a pick button was already held
    // (a combo); buttons pressed together in one report all join it.
    let newPick = !((buttons ^ changed) & GamepadDJ.pickMask);
    for (let bit = 0; bit < 32; bit++) {
        if (!(changed & (1 << bit))) {
            continue;
        }
        const pressed = (buttons & (1 << bit)) !== 0;
        if (GamepadDJ.tabButton(bit, pressed)) {
            continue;
        }
        if (GamepadDJ.browsing) {
            if (!pressed) {
                delete GamepadDJ.bumperAction[bit]; // a cue press from before the switch
            }
            GamepadDJ.browseButton(bit, pressed);
            continue;
        }
        if (bit === B.leftShoulder || bit === B.rightShoulder) {
            // Bumpers (user, 2026-10-26): L1 = deck 1's cue, R1 = deck 2's,
            // with Mixxx's normal cue behaviour. While that side's stick holds
            // the platter a tap sets the cue right there instead. On a playing
            // deck the cue only fires once the bumper has been held for
            // cueHoldMs (user, 2026-11-05: "tapping cue shouldn't stop a
            // playing track, the bumpers are too easy to touch"), so a brush
            // does nothing; a stopped deck cues on the press as before.
            const index = bit === B.leftShoulder ? 0 : 1;
            const jog = GamepadDJ.jogs[index];
            const group = `[Channel${index + 1}]`;
            if (pressed) {
                if (jog.grabbed) {
                    engine.setValue(group, "cue_set", 1);
                    console.log(`Gamepad DJ: deck ${index + 1} cue set`);
                    GamepadDJ.bumperAction[bit] = "set";
                } else if (engine.getValue(group, "play") && GamepadDJ.setting("cueHoldMs") > 0) {
                    GamepadDJ.bumperAction[bit] = "pending";
                    GamepadDJ.cueTimer[bit] = engine.beginTimer(GamepadDJ.setting("cueHoldMs"), () => {
                        GamepadDJ.cueTimer[bit] = 0;
                        if (GamepadDJ.bumperAction[bit] === "pending") {
                            console.log(`Gamepad DJ: deck ${index + 1} cue held, back to the cue point`);
                            GamepadDJ.cue(bit, index);
                        }
                    }, true);
                } else {
                    GamepadDJ.cue(bit, index);
                }
            } else {
                // Release only what the press started: a cue press must get
                // its release (preview stops), a set tap must not
                // release a cue it never pressed.
                if (GamepadDJ.bumperAction[bit] === "cue") {
                    engine.setValue(group, "cue_default", 0);
                }
                GamepadDJ.cancelCueHold(bit);
                delete GamepadDJ.bumperAction[bit];
            }
            continue;
        }
        if (GamepadDJ.pickButton[bit] !== undefined) {
            if (pressed) {
                GamepadDJ.picks.arm(GamepadDJ.pickButton[bit], !newPick);
                newPick = false;
            }
            continue;
        }
        const deckIndex = GamepadDJ.deckOfButton[bit];
        if (deckIndex !== undefined) {
            GamepadDJ.decks[deckIndex].button(bit, pressed);
        }
    }
};
