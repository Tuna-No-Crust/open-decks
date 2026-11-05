import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import "." as OD

// One deck's effect unit: effect unit N on channel N, with the built-in
// effect in slot 1 (and slot 2 for chains such as Dub). The XY pad plays two
// of the effect's parameters (FxCatalog says which); the wet amount comes
// from the catalog and the WET fader. Touching switches the unit onto the
// deck, lifting switches it off again unless Hold is on; echoes and reverb
// ring out first (`trail`). Roll drives the deck's slip loop roll instead.
// Effect chips swap what's loaded.
// The controller's touchpad plays the same pad through [OpenDecks] fxN_touch /
// fxN_x / fxN_y (set by the gamepad mapping), with the same press / move /
// release logic as a finger on the screen.
Rectangle {
    id: root

    required property int deckNumber
    readonly property string channel: "[Channel" + deckNumber + "]"
    readonly property string unitGroup: "[EffectRack1_EffectUnit" + deckNumber + "]"
    readonly property string slotGroup: "[EffectRack1_EffectUnit" + deckNumber + "_Effect1]"
    readonly property color accent: OD.Tokens.deckColor(deckNumber)
    readonly property var slot: Mixxx.EffectsManager.getEffectSlot(deckNumber, 1)
    // The chosen catalog entry. Two entries can share an effect id (the
    // filters), so the choice is remembered here and only re-derived from the
    // slot when something else loads a different effect into it.
    property int catalogIndex: -1
    readonly property string slotEffectId: slot?.effectId ?? ""
    readonly property var effect: catalogIndex >= 0 ? OD.FxCatalog.effects[catalogIndex] : null

    onSlotEffectIdChanged: {
        if (!effect || effect.id !== slotEffectId) {
            catalogIndex = OD.FxCatalog.indexOfId(slotEffectId);
        }
    }
    // Audible = any of the four units is switched onto this deck (Mixxx can
    // route several units to one channel; this panel only drives unit N).
    readonly property bool active: enableOnDeck.value > 0 || othersOn
    readonly property bool othersOn: on1.value + on2.value + on3.value > 0
    // "Hold" = the unit is on without a finger on the pad: switched on by the
    // Hold button or the controller's FX toggle (user, 2026-10-26: a lift
    // must not reset a unit that was toggled on; without the toggle, touch =
    // on, lift = off). One state, however it was switched on.
    readonly property bool hold: enableOnDeck.value > 0 && !pad.touched && !trailTimer.running
    // Decided when a finger lands: was the unit already on (toggled/held)?
    // Then lifting leaves it on, and X/Y stay where the finger left them.
    property bool keepOnAfterLift: false

    function setHold(on) {
        endTrail(false);
        if (on) {
            slotEnabled.value = 1;
            enableOnDeck.value = 1;
            keepOnAfterLift = true;
        } else {
            keepOnAfterLift = false;
            allUnitsOff();
        }
    }

    color: OD.Tokens.panel
    radius: 12

    Mixxx.ControlProxy {
        id: enableOnDeck

        group: root.unitGroup
        key: "group_" + root.channel + "_enable"
    }
    // The other three units' routing onto this deck.
    Mixxx.ControlProxy { id: on1; group: "[EffectRack1_EffectUnit" + root.otherUnit(1) + "]"; key: "group_" + root.channel + "_enable" }
    Mixxx.ControlProxy { id: on2; group: "[EffectRack1_EffectUnit" + root.otherUnit(2) + "]"; key: "group_" + root.channel + "_enable" }
    Mixxx.ControlProxy { id: on3; group: "[EffectRack1_EffectUnit" + root.otherUnit(3) + "]"; key: "group_" + root.channel + "_enable" }

    function otherUnit(n) {
        // The n-th unit number that isn't this deck's own (1..4 minus N).
        const others = [1, 2, 3, 4].filter(u => u !== root.deckNumber);
        return others[n - 1];
    }

    function allUnitsOff() {
        enableOnDeck.value = 0;
        on1.value = 0;
        on2.value = 0;
        on3.value = 0;
    }

    Mixxx.ControlProxy {
        id: mix

        group: root.unitGroup
        key: "mix"
    }
    Mixxx.ControlProxy {
        id: slotEnabled

        group: root.slotGroup
        key: "enabled"
    }
    Mixxx.ControlProxy {
        id: mixMode

        group: root.unitGroup
        key: "mix_mode"
    }
    // Slot 1's parameters (index = parameter number), for presets and axes.
    Mixxx.ControlProxy { id: param1; group: root.slotGroup; key: "parameter1" }
    Mixxx.ControlProxy { id: param2; group: root.slotGroup; key: "parameter2" }
    Mixxx.ControlProxy { id: param3; group: root.slotGroup; key: "parameter3" }
    Mixxx.ControlProxy { id: param4; group: root.slotGroup; key: "parameter4" }
    Mixxx.ControlProxy { id: param5; group: root.slotGroup; key: "parameter5" }
    readonly property var params: [null, param1, param2, param3, param4, param5]
    // Slot 2, for chains.
    readonly property string slot2Group: "[EffectRack1_EffectUnit" + deckNumber + "_Effect2]"
    Mixxx.ControlProxy { id: slot2Enabled; group: root.slot2Group; key: "enabled" }
    Mixxx.ControlProxy { id: s2param1; group: root.slot2Group; key: "parameter1" }
    Mixxx.ControlProxy { id: s2param2; group: root.slot2Group; key: "parameter2" }
    Mixxx.ControlProxy { id: s2param3; group: root.slot2Group; key: "parameter3" }
    readonly property var slot2Params: [null, s2param1, s2param2, s2param3]

    // The proxies the pad's axes act on (null for Roll's X).
    readonly property var xProxy: axisProxy(effect?.x)
    readonly property var yProxy: axisProxy(effect?.y)

    function axisProxy(axis) {
        if (!axis) {
            return null;
        }
        if (axis.mix) {
            return mix;
        }
        return axis.param ? params[axis.param] : null;
    }
    // Pad positions 0..1, read back from the parameters so the ring follows
    // the beat chips too. Roll's X has no parameter: the last finger position.
    property real rollX: 0.5
    readonly property real xPos: !effect ? 0.5
        : (xProxy ? OD.FxCatalog.axisPosition(effect.x, xProxy.value, xProxy.parameter) : rollX)
    readonly property real yPos: effect && yProxy
        ? OD.FxCatalog.axisPosition(effect.y, yProxy.value, yProxy.parameter) : 0.5

    function applyAxis(axis, proxy, pos) {
        if (!proxy) {
            return;
        }
        const t = OD.FxCatalog.axisTarget(axis, pos);
        if (t.parameter !== undefined) {
            proxy.parameter = t.parameter;
        } else {
            proxy.value = t.value;
        }
    }

    // Roll: the deck's beatlooproll_<size>_activate, one proxy per size (the
    // control names are fixed). rollSize = the roll held now, 0 = none.
    property real rollSize: 0
    Mixxx.ControlProxy { id: roll0; group: root.channel; key: "beatlooproll_0.0625_activate" }
    Mixxx.ControlProxy { id: roll1; group: root.channel; key: "beatlooproll_0.125_activate" }
    Mixxx.ControlProxy { id: roll2; group: root.channel; key: "beatlooproll_0.25_activate" }
    Mixxx.ControlProxy { id: roll3; group: root.channel; key: "beatlooproll_0.5_activate" }
    Mixxx.ControlProxy { id: roll4; group: root.channel; key: "beatlooproll_1_activate" }
    readonly property var rollProxies: ({ "0.0625": roll0, "0.125": roll1, "0.25": roll2, "0.5": roll3, "1": roll4 })

    function setRoll(size) {
        if (size === rollSize) {
            return;
        }
        // Start the new size before letting go of the old one: Mixxx keeps a
        // stack of held rolls, so the loop changes size without dropping out
        // of slip mode in between.
        const previous = rollSize;
        rollSize = size;
        if (size > 0) {
            rollProxies[String(size)].value = 1;
        }
        if (previous > 0) {
            rollProxies[String(previous)].value = 0;
        }
    }

    // Echo / Reverb tails: on lift the send closes, the unit stays on for the
    // effect's `trail`, then goes off. A touch or Hold in the meantime takes
    // over (send back open).
    Timer {
        id: trailTimer

        onTriggered: root.endTrail(true)
    }
    function endTrail(switchOff) {
        const wasTrailing = trailTimer.running || switchOff;
        trailTimer.stop();
        if (!wasTrailing) {
            return;
        }
        if (switchOff) {
            root.allUnitsOff();
        }
        if (root.effect?.sendParam) {
            root.params[root.effect.sendParam].value = root.effect.preset[root.effect.sendParam];
        }
    }

    // A fresh profile starts with empty units; give each deck something to
    // play straight away (unit 1 Echo, unit 2 Reverb, like the mockup).
    // Mixxx also routes unit N onto deck N from the start; here the pad (or
    // Hold) is what switches a unit on, so begin with it off.
    // On every start the chosen effect's preset is applied again (wet, mix
    // mode, chain): the saved profile may hold anything, including effects
    // that left the catalog.
    Component.onCompleted: {
        if (root.slot) {
            const saved = OD.FxCatalog.indexOfId(root.slot.effectId);
            selectEffect(saved >= 0 ? saved : (root.deckNumber === 1 ? 0 : 2));
        }
        allUnitsOff();
    }

    // The pad's press / move / release, shared by the on-screen finger and
    // the controller's touchpad.
    function padPress() {
        OD.UiState.focusDeck(root.deckNumber);
        const trailing = trailTimer.running;
        endTrail(false);
        keepOnAfterLift = enableOnDeck.value > 0 && !trailing;
        slotEnabled.value = 1;
        enableOnDeck.value = 1;
    }
    function padMove(x, y) {
        if (!root.effect) {
            return;
        }
        if (root.effect.x.roll) {
            root.rollX = x;
            setRoll(OD.FxCatalog.rollSize(root.effect.x, x));
        } else {
            applyAxis(root.effect.x, root.xProxy, x);
        }
        applyAxis(root.effect.y, root.yProxy, y);
    }
    function padRelease() {
        setRoll(0);
        if (keepOnAfterLift) {
            return;
        }
        if (root.effect?.trail) {
            root.params[root.effect.sendParam].value = 0;
            trailTimer.interval = root.effect.trail;
            trailTimer.start();
        } else {
            root.allUnitsOff();
        }
    }

    // A finger on the controller's touchpad. The mapping sets x and y before
    // raising touch, and keeps them current while it stays down.
    Mixxx.ControlProxy {
        id: padTouch

        group: "[OpenDecks]"
        key: "fx" + root.deckNumber + "_touch"

        onValueChanged: (v) => {
            if (v > 0) {
                root.padPress();
                root.padMove(padX.value, padY.value);
            } else {
                root.padRelease();
            }
        }
    }
    Mixxx.ControlProxy {
        id: padX

        group: "[OpenDecks]"
        key: "fx" + root.deckNumber + "_x"

        onValueChanged: (v) => {
            if (padTouch.value > 0) {
                root.padMove(v, padY.value);
            }
        }
    }
    Mixxx.ControlProxy {
        id: padY

        group: "[OpenDecks]"
        key: "fx" + root.deckNumber + "_y"

        onValueChanged: (v) => {
            if (padTouch.value > 0) {
                root.padMove(padX.value, v);
            }
        }
    }

    function selectEffect(index) {
        if (!root.slot) {
            return;
        }
        const entry = OD.FxCatalog.effects[index];
        endTrail(trailTimer.running);
        setRoll(0);
        root.catalogIndex = index;
        if (root.slot.effectId !== entry.id) {
            root.slot.effectId = entry.id;
        }
        for (const n in entry.preset) {
            root.params[n].value = entry.preset[n];
        }
        mixMode.value = entry.mixMode;
        mix.value = entry.wet;
        // Slot 2 holds the chain's second effect, if any; anything else the
        // saved chain preset put in slots 2-3 goes.
        for (let n = 2; n <= 3; ++n) {
            const other = Mixxx.EffectsManager.getEffectSlot(root.deckNumber, n);
            const wanted = n === 2 && entry.chain ? entry.chain.id : "";
            if (other && other.effectId !== wanted) {
                other.effectId = wanted;
            }
        }
        if (entry.chain) {
            for (const n in entry.chain.preset) {
                root.slot2Params[n].value = entry.chain.preset[n];
            }
            slot2Enabled.value = 1;
        } else {
            slot2Enabled.value = 0;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            LayoutMirroring.enabled: root.deckNumber % 2 === 0
            LayoutMirroring.childrenInherit: true
            spacing: 8

            Rectangle {
                color: root.accent
                implicitHeight: 22
                implicitWidth: 22
                radius: 6

                Text {
                    anchors.centerIn: parent
                    color: OD.Tokens.ground
                    font.bold: true
                    font.pixelSize: 12
                    text: root.deckNumber
                }
            }
            Text {
                Layout.fillWidth: true
                color: OD.Tokens.text
                elide: Text.ElideRight
                font.pixelSize: 15
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignLeft
                text: root.effect?.name ?? (root.slot?.effectName || "No effect")
            }
            OD.Badge {
                on: root.active
                onColor: root.accent
                text: root.active ? "ON · " + Math.round(mix.parameter * 100) + "% WET" : "OFF"
            }
        }

        OD.XYPad {
            id: pad

            Layout.fillHeight: true
            Layout.fillWidth: true
            accent: root.accent
            active: root.active
            remoteTouched: padTouch.value > 0
            xLabel: root.effect?.xLabel ?? ""
            xValue: root.xPos
            yLabel: root.effect?.yLabel ?? ""
            yValue: root.yPos

            onPressed: root.padPress()
            onMoved: (x, y) => root.padMove(x, y)
            onReleased: root.padRelease()
        }

        GridLayout {
            Layout.fillWidth: true
            columnSpacing: 6
            columns: 4
            rowSpacing: 6

            Repeater {
                model: OD.FxCatalog.effects

                Button {
                    id: chip

                    required property int index
                    required property var modelData
                    readonly property bool selected: root.catalogIndex === index

                    Layout.fillWidth: true
                    Layout.preferredHeight: OD.Tokens.minTouch
                    Layout.preferredWidth: 1
                    Accessible.name: "Effect " + modelData.name

                    onClicked: root.selectEffect(index)

                    background: Rectangle {
                        color: chip.selected ? root.accent : (chip.down ? OD.Tokens.selected : OD.Tokens.raised)
                        radius: 8
                    }
                    contentItem: Text {
                        color: chip.selected ? OD.Tokens.ground : OD.Tokens.textSoft
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        text: chip.modelData.name
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
