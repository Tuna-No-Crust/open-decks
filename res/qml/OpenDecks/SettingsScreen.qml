import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import QtQuick.Layouts
import "." as OD

// Settings: audio routing first (which device and channel pair is the
// master, which the headphone cue, host API, sample rate, buffer), so a new
// interface needs no hand-edited soundconfig.xml. Everything is a chip row
// sized for thumbs; nothing applies until Apply is tapped.
//
// Mixxx.SoundManager is reached lazily (AppShell loads this screen on first
// use): the singleton is registered after main.qml has loaded.
Item {
    id: root

    readonly property var manager: Mixxx.SoundManager

    // Edited state (what the chips show).
    property string api: ""
    property int sampleRate: 0
    property int bufferIndex: 5
    property int keylock: 0
    property var outputs: []        // Mixxx.OutputDevice objects for `api`
    property int masterDevice: -1   // index into outputs
    property int masterChannel: 0   // first channel of the pair (0, 2, 4...)
    property int headDevice: -1     // -1 = no headphone output
    property int headChannel: 0

    // What the engine runs now, for change detection.
    property string loadedSnapshot: ""
    property bool applying: false
    property string statusText: ""
    property bool statusError: false
    readonly property bool hasChanges: snapshot() !== loadedSnapshot

    readonly property var apiOptions: manager.getHostAPIList().map(a => ({ label: a, value: a }))
    readonly property var sampleRateOptions: manager.getSampleRates(api).map(r => ({ label: (r / 1000) + " kHz", value: r }))
    readonly property var bufferOptions: bufferOptionsFor(api, sampleRate)
    readonly property var keylockOptions: manager.getKeylockEngines().map(e => ({
        label: ["SoundTouch", "Rubber Band", "Rubber Band R3"][e] || ("Engine " + e), value: e }))
    readonly property var deviceOptions: outputs.map((d, i) => ({ label: d.displayName, value: i }))
    readonly property var headDeviceOptions: [{ label: "Off", value: -1 }].concat(deviceOptions)

    function snapshot() {
        return JSON.stringify([api, sampleRate, bufferIndex, keylock,
            deviceName(masterDevice), masterChannel, deviceName(headDevice), headChannel]);
    }
    function deviceName(index) {
        return index >= 0 && index < outputs.length ? outputs[index].displayName : "";
    }
    function pairOptions(deviceIndex) {
        const device = deviceIndex >= 0 ? outputs[deviceIndex] : null;
        const pairs = device ? Math.floor(device.channelCount / 2) : 0;
        const list = [];
        for (let p = 0; p < pairs; ++p) {
            list.push({ label: (2 * p + 1) + "–" + (2 * p + 2), value: 2 * p });
        }
        return list;
    }
    // Mixxx stores the buffer as an index 1..7; what it means depends on the
    // API (SoundManagerConfig::getFramesPerBuffer).
    function bufferOptionsFor(hostApi, rate) {
        if (hostApi === "JACK Audio Connection Kit") {
            return [{ label: "Auto", value: 5 }, { label: "2048 frames", value: 6 }, { label: "4096 frames", value: 7 }];
        }
        const list = [];
        if (!rate) {
            return list;
        }
        let frames = 1;
        if (hostApi === "PipeWire") {
            frames = 64;
        } else {
            while (frames / rate * 1000 < 1.0) {
                frames *= 2;
            }
        }
        for (let i = 1; i <= 7; ++i) {
            list.push({ label: (frames / rate * 1000).toFixed(1) + " ms", value: i });
            frames *= 2;
        }
        return list;
    }

    function loadDevices(hostApi) {
        outputs = manager.availableOutputDevices(hostApi).filter(d => d.channelCount >= 2);
    }
    // Read the running configuration into the chips.
    function load() {
        api = manager.getAPI();
        sampleRate = manager.getSampleRate();
        bufferIndex = manager.getAudioBufferSizeIndex();
        keylock = manager.getKeylockEngine();
        loadDevices(api);
        masterDevice = -1;
        headDevice = -1;
        masterChannel = 0;
        headChannel = 0;
        for (let i = 0; i < outputs.length; ++i) {
            const connections = outputs[i].connections(manager);
            for (const c of connections) {
                if (c.type === 0) {        // AudioPathType::Main
                    masterDevice = i;
                    masterChannel = c.channelGroup;
                } else if (c.type === 1) { // AudioPathType::Headphones
                    headDevice = i;
                    headChannel = c.channelGroup;
                }
            }
        }
        loadedSnapshot = snapshot();
    }
    function pickApi(newApi) {
        if (newApi === api) {
            return;
        }
        api = newApi;
        loadDevices(api);
        // Keep the devices if the new API lists them under the same names.
        const master = deviceName(masterDevice), head = deviceName(headDevice);
        masterDevice = outputs.findIndex(d => d.displayName === master);
        headDevice = outputs.findIndex(d => d.displayName === head);
        const rates = manager.getSampleRates(api);
        if (rates.indexOf(sampleRate) < 0) {
            sampleRate = rates.length ? rates[0] : 0;
        }
        if (api === "JACK Audio Connection Kit" && bufferIndex < 5) {
            bufferIndex = 5;
        }
    }
    function clampChannel(deviceIndex, channel) {
        const pairs = pairOptions(deviceIndex);
        return pairs.some(p => p.value === channel) ? channel : 0;
    }
    function apply() {
        if (masterDevice < 0) {
            setStatus("Pick a master output first", true);
            return;
        }
        manager.setAPI(api);
        manager.setSampleRate(sampleRate);
        manager.setAudioBufferSizeIndex(bufferIndex);
        manager.setKeylockEngine(keylock);
        manager.clearOutputs();
        manager.addOutput(outputs[masterDevice], 0, masterChannel, 0);
        if (headDevice >= 0) {
            manager.addOutput(outputs[headDevice], 1, headChannel, 0);
        }
        // The handheld has no inputs (no mics, no timecode); drop any that an
        // old config carried for another API so they can't block the restart.
        manager.clearInputs();
        applying = true;
        setStatus("Applying…", false);
        manager.commit();
    }
    function rescan() {
        setStatus("Looking for devices…", false);
        manager.rescanDevices();
        const master = deviceName(masterDevice), head = deviceName(headDevice);
        loadDevices(api);
        masterDevice = outputs.findIndex(d => d.displayName === master);
        headDevice = outputs.findIndex(d => d.displayName === head);
        // Rescanning closed the devices; put the current config back.
        apply();
    }
    function setStatus(text, isError) {
        statusText = text;
        statusError = isError;
    }

    Component.onCompleted: load()

    Connections {
        target: root.manager

        function onCommitted(error) {
            root.applying = false;
            if (error) {
                // The engine keeps the failed config until a good one is
                // applied, so leave the chips as they are and keep Apply
                // live (an empty snapshot never matches) — pick again, Apply.
                root.setStatus(error.split("\n").filter(l => l.trim() !== "").join(" — ")
                    + " — not applied", true);
                OD.UiState.notify("Audio: " + error.split("\n")[0], OD.Tokens.danger);
                root.loadedSnapshot = "";
            } else {
                root.setStatus("Applied", false);
                OD.UiState.notify("Audio settings applied");
                root.load();
            }
        }
    }
    Mixxx.ControlProxy {
        id: outputLatency

        group: "[App]"
        key: "output_latency_ms"
    }
    Mixxx.ControlProxy {
        id: latencyUsage

        group: "[App]"
        key: "audio_latency_usage"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Flickable {
            id: flick

            Layout.fillHeight: true
            Layout.fillWidth: true
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            contentHeight: content.implicitHeight
            contentWidth: width
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: ScrollBar { }

            ColumnLayout {
                id: content

                enabled: !root.applying
                spacing: 12
                width: flick.width

                // ---- Outputs: the reason this screen exists ----
                Rectangle {
                    Layout.fillWidth: true
                    color: OD.Tokens.panel
                    implicitHeight: outputsColumn.implicitHeight + 32
                    radius: 12

                    ColumnLayout {
                        id: outputsColumn

                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                color: OD.Tokens.text
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                                text: "Outputs"
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                color: OD.Tokens.textMuted
                                font.family: OD.Tokens.mono
                                font.pixelSize: 12
                                text: "LATENCY " + outputLatency.value.toFixed(1) + " ms · LOAD "
                                    + Math.round(latencyUsage.value * 100) + " %"
                            }
                        }

                        OD.ChipRow {
                            Layout.fillWidth: true
                            accent: OD.Tokens.deck1
                            emptyText: "No output device for " + (root.api || "this API")
                            label: "MASTER · DEVICE"
                            options: root.deviceOptions
                            selectedValue: root.masterDevice

                            onPicked: (v) => {
                                root.masterDevice = v;
                                root.masterChannel = root.clampChannel(v, root.masterChannel);
                            }
                        }
                        OD.ChipRow {
                            Layout.fillWidth: true
                            accent: OD.Tokens.deck1
                            label: "MASTER · CHANNELS"
                            options: root.pairOptions(root.masterDevice)
                            selectedValue: root.masterChannel
                            visible: root.masterDevice >= 0

                            onPicked: (v) => root.masterChannel = v
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            color: OD.Tokens.line
                            height: 1
                        }

                        OD.ChipRow {
                            Layout.fillWidth: true
                            accent: OD.Tokens.deck2
                            label: "HEADPHONE CUE · DEVICE"
                            options: root.headDeviceOptions
                            selectedValue: root.headDevice

                            onPicked: (v) => {
                                root.headDevice = v;
                                root.headChannel = root.clampChannel(v, root.headChannel);
                            }
                        }
                        OD.ChipRow {
                            Layout.fillWidth: true
                            accent: OD.Tokens.deck2
                            label: "HEADPHONE CUE · CHANNELS"
                            options: root.pairOptions(root.headDevice)
                            selectedValue: root.headChannel
                            visible: root.headDevice >= 0

                            onPicked: (v) => root.headChannel = v
                        }
                        Text {
                            Layout.fillWidth: true
                            color: OD.Tokens.textSubtle
                            font.pixelSize: 12
                            text: root.masterDevice >= 0 && root.headDevice === root.masterDevice
                                && root.headChannel === root.masterChannel
                                ? "Master and cue share a channel pair — pick different channels."
                                : "Master and cue may be two devices (one clock on the Deck's PipeWire) or two pairs of one interface."
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ---- Engine ----
                Rectangle {
                    Layout.fillWidth: true
                    color: OD.Tokens.panel
                    implicitHeight: engineColumn.implicitHeight + 32
                    radius: 12

                    ColumnLayout {
                        id: engineColumn

                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14

                        Text {
                            color: OD.Tokens.text
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            text: "Engine"
                        }
                        OD.ChipRow {
                            Layout.fillWidth: true
                            label: "SOUND API"
                            options: root.apiOptions
                            selectedValue: root.api

                            onPicked: (v) => root.pickApi(v)
                        }
                        OD.ChipRow {
                            Layout.fillWidth: true
                            label: "SAMPLE RATE"
                            options: root.sampleRateOptions
                            selectedValue: root.sampleRate

                            onPicked: (v) => root.sampleRate = v
                        }
                        OD.ChipRow {
                            Layout.fillWidth: true
                            label: "AUDIO BUFFER"
                            options: root.bufferOptions
                            selectedValue: root.bufferIndex

                            onPicked: (v) => root.bufferIndex = v
                        }
                        Text {
                            Layout.fillWidth: true
                            color: OD.Tokens.textSubtle
                            font.pixelSize: 12
                            text: "Smaller buffers make the jog feel tighter; too small and the sound crackles (watch LOAD above)."
                            wrapMode: Text.WordWrap
                        }
                        OD.ChipRow {
                            Layout.fillWidth: true
                            label: "KEY LOCK ENGINE"
                            options: root.keylockOptions
                            selectedValue: root.keylock

                            onPicked: (v) => root.keylock = v
                        }
                    }
                }
            }
        }

        // ---- Action bar: deliberate taps at the edges, statusText in the middle ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                id: rescanButton

                Accessible.name: "Look for devices again"
                Layout.preferredHeight: 52
                Layout.preferredWidth: 200
                enabled: !root.applying

                onClicked: root.rescan()

                background: Rectangle {
                    border.color: OD.Tokens.selected
                    color: rescanButton.down ? OD.Tokens.selected : OD.Tokens.raised
                    radius: 10
                }
                contentItem: Text {
                    color: OD.Tokens.text
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    text: "↻  Look for devices"
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                Layout.fillWidth: true
                color: root.statusError ? OD.Tokens.danger : OD.Tokens.textMuted
                elide: Text.ElideRight
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                text: root.statusText
            }
            Button {
                id: revertButton

                Accessible.name: "Revert"
                Layout.preferredHeight: 52
                Layout.preferredWidth: 140
                enabled: root.hasChanges && !root.applying
                opacity: enabled ? 1 : 0.4

                onClicked: {
                    root.load();
                    root.setStatus("", false);
                }

                background: Rectangle {
                    border.color: OD.Tokens.selected
                    color: revertButton.down ? OD.Tokens.selected : OD.Tokens.raised
                    radius: 10
                }
                contentItem: Text {
                    color: OD.Tokens.text
                    font.pixelSize: 15
                    horizontalAlignment: Text.AlignHCenter
                    text: "Revert"
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Button {
                id: applyButton

                Accessible.name: "Apply audio settings"
                Layout.preferredHeight: 52
                Layout.preferredWidth: 200
                enabled: root.hasChanges && !root.applying
                opacity: enabled ? 1 : 0.4

                onClicked: root.apply()

                background: Rectangle {
                    color: applyButton.down ? OD.Tokens.cap : OD.Tokens.text
                    radius: 10
                }
                contentItem: Text {
                    color: OD.Tokens.ground
                    font.bold: true
                    font.pixelSize: 15
                    horizontalAlignment: Text.AlignHCenter
                    text: root.applying ? "Applying…" : "Apply"
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
