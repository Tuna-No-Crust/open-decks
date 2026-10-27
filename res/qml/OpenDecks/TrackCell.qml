import QtQuick 2.12
import "." as OD

// One cell of the track table. As a header it shows the column label and
// sorts the table when tapped.
Item {
    id: root

    property bool header: false
    // Header only: whether tapping sorts by this column.
    property bool sortable: true
    property string role: ""
    property string label: ""
    property string text: ""
    property bool mono: false
    property bool muted: false
    property bool soft: false
    property int weight: Font.Normal
    property int align: Text.AlignLeft
    property string sortRole: ""
    property bool sortDescending: false

    signal sortRequested(string role)

    implicitHeight: cell.implicitHeight

    Text {
        id: cell

        readonly property bool sorted: root.header && root.sortRole === root.role

        anchors.fill: parent
        color: root.header
            ? (sorted ? OD.Tokens.text : OD.Tokens.textMuted)
            : (root.muted ? OD.Tokens.textMuted : (root.soft ? OD.Tokens.textSoft : OD.Tokens.text))
        elide: Text.ElideRight
        font.bold: root.header
        font.family: root.mono && !root.header ? OD.Tokens.mono : "sans-serif"
        font.letterSpacing: root.header ? 1 : 0
        font.pixelSize: root.header ? 12 : (root.mono ? 13 : 14)
        font.weight: root.header ? Font.Bold : root.weight
        horizontalAlignment: root.align
        text: root.header ? root.label + (sorted ? (root.sortDescending ? " ↓" : " ↑") : "") : root.text
        verticalAlignment: Text.AlignVCenter
    }
    TapHandler {
        enabled: root.header && root.sortable

        onTapped: root.sortRequested(root.role)
    }
}
