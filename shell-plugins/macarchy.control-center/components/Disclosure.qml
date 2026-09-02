// A settings group that stays folded until it is wanted, with its current
// value on the header line — so a page can show what it is set to without
// showing what it is made of.
//
// Folding is instant on purpose: these live inside a Flickable, and a height
// animation there fights the scroll position for the length of the animation.

import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: root

  property string title: ""
  property string summary: ""
  property bool expanded: false

  default property alias content: body.data

  readonly property color textColor: Color.popups.text
  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)

  spacing: Style.space(8)

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: Style.space(38)
    radius: Math.min(Style.cornerRadius, Style.space(10))
    color: header.hovered ? Style.hoverFill : Style.normalFill

    HoverHandler { id: header }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.expanded = !root.expanded
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰅂"
        color: root.dimColor
        font.family: Style.font.family
        font.pixelSize: Style.font.iconSmall
        rotation: root.expanded ? 90 : 0

        Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }

      Text {
        text: root.title
        color: root.textColor
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Item { Layout.fillWidth: true }

      Text {
        Layout.maximumWidth: parent.width * 0.5
        visible: text.length > 0 && !root.expanded
        text: root.summary
        color: root.dimColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  ColumnLayout {
    id: body
    Layout.fillWidth: true
    Layout.leftMargin: Style.space(4)
    Layout.bottomMargin: root.expanded ? Style.space(4) : 0
    visible: root.expanded
    spacing: Style.space(8)
  }
}
