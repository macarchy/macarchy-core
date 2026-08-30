// One quick-setting tile, macOS Control Center style: a circular icon badge
// that fills with the accent when active, a title, and a one-word state
// line. The whole tile is the click target.

import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: root

  property string glyph: ""
  property string label: ""
  property string stateText: active ? "On" : "Off"
  property bool active: false

  signal clicked()

  readonly property bool hovered: hoverTracker.hovered
  readonly property color textColor: Color.popups.text
  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)

  radius: Math.min(Style.cornerRadius, Style.space(10))
  color: hovered ? Style.hoverFill : Style.normalFill
  implicitHeight: Style.space(52)

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(10)

    Rectangle {
      Layout.preferredWidth: Style.space(28)
      Layout.preferredHeight: Style.space(28)
      Layout.alignment: Qt.AlignVCenter
      radius: width / 2
      color: root.active ? Color.accent : Util.alpha(root.textColor, 0.12)

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.active ? Color.popups.background : root.textColor
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        text: root.label
        color: root.textColor
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        text: root.stateText
        color: root.dimColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
