// One quick toggle on the Control Center's home grid: a circular badge over
// a short label, four to a row. The badge carries the state, so the tile
// needs no state line — which is what lets four fit where two used to.
//
// Three states, because auto-brightness has three: filled = on, RING =
// paused (the daemon is alive but not correcting), neutral = off.

import QtQuick
import qs.Commons

Item {
  id: root

  property string glyph: ""
  property string label: ""
  // mode: "on" | "paused" | "off". `active` is the two-state shorthand.
  property bool active: false
  property string mode: active ? "on" : "off"

  signal clicked()

  readonly property bool hovered: hoverTracker.hovered
  readonly property color textColor: Color.popups.text
  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)
  readonly property bool lit: mode === "on"
  readonly property bool paused: mode === "paused"

  implicitHeight: stack.implicitHeight + Style.space(12)

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Rectangle {
    anchors.fill: parent
    radius: Math.min(Style.cornerRadius, Style.space(10))
    color: root.hovered ? Style.hoverFill : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Column {
    id: stack
    width: root.width
    // Top-anchored, not centred: a two-line label ("Ne pas déranger") would
    // otherwise lift its badge out of line with its row's neighbours.
    anchors.top: parent.top
    anchors.topMargin: Style.space(6)
    spacing: Style.space(6)

    Rectangle {
      width: Style.space(38)
      height: Style.space(38)
      anchors.horizontalCenter: parent.horizontalCenter
      radius: width / 2
      color: root.lit ? Color.accent : Util.alpha(root.textColor, 0.12)
      border.width: root.paused ? 2 : 0
      border.color: Color.accent

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.lit ? Color.popups.background
          : (root.paused ? Color.accent : root.textColor)
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      width: root.width - Style.space(2)
      horizontalAlignment: Text.AlignHCenter
      text: root.label
      color: root.lit || root.paused ? root.textColor : root.dimColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      // Two lines, because « Ne pas déranger » does not fit on one at a
      // quarter of a 380px panel and abbreviating it would read as jargon.
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
  }
}
