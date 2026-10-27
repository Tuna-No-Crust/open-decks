import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import "." as OD

// One deck's effect unit: effect unit N on channel N, with the built-in
// effect in slot 1. The XY pad plays it: X = the effect's main parameter,
// Y = wet amount; touching switches the unit onto the deck, lifting switches
// it off again unless Hold is on. Effect chips swap what's in slot 1.
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
    readonly property bool hold: enableOnDeck.value > 0 && !pad.touched
    // Decided when a finger lands: was the unit already on (toggled/held)?
    // Then lifting leaves it on, and X/Y stay where the finger left them.
    property bool keepOnAfterLift: false

    function setHold(on) {
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
    // The slot's first three parameters, for the catalog presets.
    Mixxx.ControlProxy { id: param1; group: root.slotGroup; key: "parameter1" }
    Mixxx.ControlProxy { id: param2; group: root.slotGroup; key: "parameter2" }
    Mixxx.ControlProxy { id: param3; group: root.slotGroup; key: "parameter3" }

    Mixxx.ControlProxy {
        id: xParam

        group: root.slotGroup
        key: "parameter" + (root.effect?.xParam ?? 1)
    }

    // A fresh profile starts with empty units; give each deck something to
    // play straight away (unit 1 Echo, unit 2 Reverb, like the mockup).
    // Mixxx also routes unit N onto deck N from the start; here the pad (or
    // Hold) is what switches a unit on, so begin with it off.
    Component.onCompleted: {
        if (root.slot && root.slot.effectId === "") {
            selectEffect(root.deckNumber === 1 ? 0 : 1);
        }
        allUnitsOff();
    }

    // The pad's press / move / release, shared by the on-screen finger and
    // the controller's touchpad.
    function padPress() {
        OD.UiState.focusDeck(root.deckNumber);
        keepOnAfterLift = enableOnDeck.value > 0;
        slotEnabled.value = 1;
        enableOnDeck.value = 1;
    }
    function padMove(x, y) {
        xParam.parameter = x;
        mix.parameter = y;
    }
    function padRelease() {
        if (!keepOnAfterLift) {
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
        root.catalogIndex = index;
        if (root.slot.effectId !== entry.id) {
            root.slot.effectId = entry.id;
        }
        if (entry.preset) {
            const params = [null, param1, param2, param3];
            for (const n in entry.preset) {
                params[n].parameter = entry.preset[n];
            }
        }
        // Slots 2 and 3 may hold whatever the saved chain preset put there;
        // this panel offers one effect per unit, so keep them empty.
        for (let n = 2; n <= 3; ++n) {
            const other = Mixxx.EffectsManager.getEffectSlot(root.deckNumber, n);
            if (other && other.effectId !== "") {
                other.effectId = "";
            }
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
            xLabel: root.effect?.xLabel ?? "parameter 1"
            xValue: xParam.parameter
            yLabel: "wet"
            yValue: mix.parameter

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
