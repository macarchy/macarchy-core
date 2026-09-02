// A row on the Control Center's home: badge + name + state line, an optional
// switch, and an optional chevron. Clicking the row opens whatever is behind
// it (a module page, or one of the shell's own panels); the switch owns its
// own click and sits above the row's MouseArea.
//
// A row with no page and a switch toggles on a plain click — nothing on this
// panel should look pressable and do nothing.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property string glyph: ""
  property string label: ""
  property string stateText: ""
  property bool active: false
  // Something needs attention behind this row: the badge turns urgent.
  property bool alert: false
  property bool hasToggle: true
  property bool hasPage: true

  signal toggled()
  signal opened()

  readonly property bool hovered: hoverTracker.hovered
  readonly property color textColor: Color.popups.text
  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)

  radius: Math.min(Style.cornerRadius, Style.space(10))
  color: hovered ? Style.hoverFill : Style.normalFill
  implicitHeight: Style.space(46)

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.hasPage ? root.opened() : (root.hasToggle ? root.toggled() : null)
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(10)

    Rectangle {
      Layout.preferredWidth: Style.space(26)
      Layout.preferredHeight: Style.space(26)
      Layout.alignment: Qt.AlignVCenter
      radius: width / 2
      color: root.alert ? Color.urgent : (root.active ? Color.accent : Util.alpha(root.textColor, 0.12))

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        text: root.glyph
        color: (root.active || root.alert) ? Color.popups.background : root.textColor
        font.family: Style.font.family
        font.pixelSize: Style.font.iconSmall
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
        visible: text.length > 0
        text: root.stateText
        color: root.dimColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    ToggleSwitch {
      visible: root.hasToggle
      Layout.alignment: Qt.AlignVCenter
      checked: root.active
      trackHeight: Style.space(16)
      onToggled: root.toggled()
    }

    Text {
      visible: root.hasPage
      Layout.alignment: Qt.AlignVCenter
      text: "󰅂"
      color: root.dimColor
      font.family: Style.font.family
      font.pixelSize: Style.font.iconSmall
    }
  }
}
