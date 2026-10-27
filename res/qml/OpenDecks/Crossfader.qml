import Mixxx 1.0 as Mixxx
import QtQuick 2.12
import QtQuick.Controls
import "." as OD

// The crossfader with its lock. Locked (the default) the handle shows a lock
// glyph and ignores touch, so a thumb reaching for the screen can't throw the
// mix. The lock state is shared with the other screens' crossfader.
Item {
    id: root

    readonly property bool locked: OD.UiState.crossfaderLocked

    // Everything but the track is fixed, so the track takes whatever width
    // the screen gives (248 at 448 px): 1 | track | 2 | gap | LOCK.
    readonly property real trackWidth: Math.max(0, width - 2 * OD.Tokens.layout.wXlabel -
        3 * OD.Tokens.s.s2 - OD.Tokens.layout.wLock)

    implicitHeight: OD.Tokens.layout.hXfader
    implicitWidth: OD.Tokens.layout.wMixer - OD.Tokens.s.s4 * 2

    Mixxx.ControlProxy {
        id: control

        group: "[Master]"
        key: "crossfader"
    }

    // 16 x 16 padlock: body plus shackle; an open shackle drops its right leg.
    component LockGlyph: Canvas {
        id: glyph

        property color ink
        property bool closed: true

        height: OD.Tokens.layout.glyphS
        width: OD.Tokens.layout.glyphS

        onClosedChanged: requestPaint()
        onInkChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.scale(width / 16, height / 16);
            ctx.fillStyle = ink;
            ctx.strokeStyle = ink;
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.roundedRect(2, 7, 12, 8, 2, 2);
            ctx.fill();
            ctx.beginPath();
            ctx.moveTo(4.5, 7);
            ctx.lineTo(4.5, 5);
            ctx.arc(8, 5, 3.5, Math.PI, 0);
            if (closed) {
                ctx.lineTo(11.5, 7);
            }
            ctx.stroke();
        }
        Component.onCompleted: requestPaint()
    }

    Text {
        color: OD.Tokens.textSecondary
        font.family: OD.Tokens.mono
        font.pixelSize: OD.Tokens.fs.body
        font.weight: OD.Tokens.fw.bold
        height: OD.Tokens.targetMin
        horizontalAlignment: Text.AlignHCenter
        text: "1"
        verticalAlignment: Text.AlignVCenter
        width: OD.Tokens.layout.wXlabel
        y: (parent.height - height) / 2
    }
    Text {
        color: OD.Tokens.textSecondary
        font.family: OD.Tokens.mono
        font.pixelSize: OD.Tokens.fs.body
        font.weight: OD.Tokens.fw.bold
        height: OD.Tokens.targetMin
        horizontalAlignment: Text.AlignHCenter
        text: "2"
        verticalAlignment: Text.AlignVCenter
        width: OD.Tokens.layout.wXlabel
        x: OD.Tokens.layout.wXlabel + OD.Tokens.s.s2 + root.trackWidth + OD.Tokens.s.s2
        y: (parent.height - height) / 2
    }
    Slider {
        id: slider

        // Pressed and still = selected; once it moves it is engaged.
        property bool moving: false

        enabled: !root.locked
        from: -1
        to: 1
        height: parent.height
        live: true
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        value: control.value
        width: root.trackWidth
        x: OD.Tokens.layout.wXlabel + OD.Tokens.s.s2

        onMoved: {
            moving = true;
            control.value = value;
        }
        onPressedChanged: {
            if (!pressed) {
                moving = false;
            }
        }

        background: Item {
            Rectangle {
                color: OD.Tokens.edge
                height: OD.Tokens.b2
                width: parent.width
                y: parent.height / 2 - OD.Tokens.b1

                Rectangle {
                    color: OD.Tokens.textMuted
                    height: OD.Tokens.layout.notch
                    width: OD.Tokens.b2
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                }
            }
        }
        handle: Rectangle {
            border.color: slider.moving ? OD.Tokens.accent : (slider.pressed ? OD.Tokens.textSecondary : OD.Tokens.edge)
            border.width: OD.Tokens.b1
            color: {
                if (root.locked) {
                    return OD.Tokens.panel;
                }
                return slider.moving ? OD.Tokens.accent : (slider.pressed ? OD.Tokens.selected : OD.Tokens.raised);
            }
            height: OD.Tokens.layout.hHandle
            radius: OD.Tokens.r.r2
            width: OD.Tokens.layout.wFader
            x: slider.visualPosition * (slider.width - width)
            y: (slider.height - height) / 2

            Behavior on color {
                ColorAnimation { duration: OD.Tokens.durFast }
            }

            LockGlyph {
                anchors.centerIn: parent
                ink: OD.Tokens.textMuted
                visible: root.locked
            }
            // A fader cap turned sideways: two vertical bars.
            Row {
                anchors.centerIn: parent
                spacing: OD.Tokens.s.s1
                visible: !root.locked

                Rectangle {
                    color: slider.moving ? OD.Tokens.ground : OD.Tokens.textSecondary
                    height: OD.Tokens.layout.glyphS
                    width: OD.Tokens.b2
                }
                Rectangle {
                    color: slider.moving ? OD.Tokens.ground : OD.Tokens.textSecondary
                    height: OD.Tokens.layout.glyphS
                    width: OD.Tokens.b2
                }
            }
        }
        TapHandler {
            onDoubleTapped: control.reset()
        }
    }
    Item {
        id: lock

        Accessible.name: root.locked ? "Unlock crossfader" : "Lock crossfader"
        Accessible.role: Accessible.Button
        anchors.right: parent.right
        height: OD.Tokens.targetMin
        width: OD.Tokens.layout.wLock
        y: (parent.height - height) / 2

        Rectangle {
            anchors.fill: parent
            border.color: root.locked ? OD.Tokens.textSecondary : OD.Tokens.edge
            border.width: root.locked ? OD.Tokens.b2 : OD.Tokens.b1
            color: lockTap.pressed ? OD.Tokens.raised : OD.Tokens.panel
            radius: OD.Tokens.r.r2

            Behavior on color {
                ColorAnimation { duration: OD.Tokens.durFast }
            }
        }
        Row {
            anchors.centerIn: parent
            spacing: OD.Tokens.s.s1

            LockGlyph {
                anchors.verticalCenter: parent.verticalCenter
                closed: root.locked
                ink: root.locked ? OD.Tokens.text : OD.Tokens.textSecondary
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: root.locked ? OD.Tokens.text : OD.Tokens.textSecondary
                font.family: OD.Tokens.sans
                font.letterSpacing: OD.Tokens.tracking(OD.Tokens.fs.label, OD.Tokens.ls.label)
                font.pixelSize: OD.Tokens.fs.label
                font.weight: OD.Tokens.fw.semibold
                text: root.locked ? "LOCKED" : "LOCK"
            }
        }
        TapHandler {
            id: lockTap

            onTapped: OD.UiState.crossfaderLocked = !root.locked
        }
    }
}
