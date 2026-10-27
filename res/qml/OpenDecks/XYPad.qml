import QtQuick 2.12
import "." as OD

// A touch XY pad. While a finger is down `x`/`y` follow it (0..1, y up) and
// `touched` is true; the ring always shows the current values, so the pad
// also reads back what the controller's stick layer did. Lift = release.
// `remoteTouched` lights it up the same way for a finger that isn't on the
// screen (the controller's touchpad, driven through FxUnitPanel).
Rectangle {
    id: root

    required property color accent
    property real xValue: 0.5
    property real yValue: 0
    property bool active: false // lit up (the effect is audible)
    property string xLabel: ""
    property string yLabel: ""
    property bool remoteTouched: false
    readonly property bool touched: finger.pressed || remoteTouched

    signal moved(real x, real y)
    signal pressed()
    signal released()

    border.color: root.touched ? root.accent : OD.Tokens.selected
    border.width: 1
    clip: true
    color: OD.Tokens.lane
    radius: 10

    // 4x4 grid
    Repeater {
        model: 3

        Rectangle {
            required property int index

            color: OD.Tokens.raised
            height: parent.height
            width: 1
            x: Math.round(parent.width * (index + 1) / 4)
        }
    }
    Repeater {
        model: 3

        Rectangle {
            required property int index

            color: OD.Tokens.raised
            height: 1
            width: parent.width
            y: Math.round(parent.height * (index + 1) / 4)
        }
    }

    // Glow under the finger while the effect is audible.
    Rectangle {
        color: root.accent
        height: 160
        opacity: root.active ? 0.22 : 0
        radius: 80
        width: 160
        x: root.xValue * root.width - 80
        y: (1 - root.yValue) * root.height - 80

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }
    // Crosshair
    Rectangle {
        color: root.accent
        height: parent.height
        opacity: root.touched ? 0.5 : 0.25
        width: 1
        x: root.xValue * root.width
    }
    Rectangle {
        color: root.accent
        height: 1
        opacity: root.touched ? 0.5 : 0.25
        width: parent.width
        y: (1 - root.yValue) * root.height
    }
    // Ring
    Rectangle {
        border.color: root.accent
        border.width: 3
        color: "#660B0C0F"
        height: 44
        opacity: root.touched || root.active ? 1 : 0.5
        radius: 22
        width: 44
        x: root.xValue * root.width - 22
        y: (1 - root.yValue) * root.height - 22
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.leftMargin: 10
        color: OD.Tokens.textMuted
        font.pixelSize: 11
        text: "← " + root.xLabel + " →"
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.top: parent.top
        anchors.topMargin: 8
        color: OD.Tokens.textMuted
        font.pixelSize: 11
        text: "↑ " + root.yLabel
    }

    // One finger per pad, independent of what the other hand is doing: a
    // MultiPointTouchArea gets its own touch point even while another finger
    // holds a fader or the other deck's pad (a MouseArea only ever saw the
    // first finger). The mouse works too, for the Mac. Pressing anywhere jumps
    // straight there: a pad, not a slider.
    MultiPointTouchArea {
        id: area

        function report(point) {
            const nx = Math.min(1, Math.max(0, point.x / width));
            const ny = Math.min(1, Math.max(0, 1 - point.y / height));
            root.moved(nx, ny);
        }

        anchors.fill: parent
        maximumTouchPoints: 1
        minimumTouchPoints: 1
        mouseEnabled: true
        touchPoints: [
            TouchPoint { id: finger }
        ]

        onPressed: (points) => {
            root.pressed();
            report(points[0]);
        }
        onUpdated: (points) => report(points[0])
        onReleased: root.released()
        onCanceled: root.released()
    }
}
