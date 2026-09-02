// The Control Center's crown: the battery, as the biggest object on the
// panel. It used to be the smallest line on it, in grey, at the bottom —
// which is backwards, because the charge is what this panel is opened to
// LOOK at as often as it is opened to click.
//
// The caption is composed by the caller: it is the one place that already
// holds the charge cap, the AC state and whatever UPower will admit about
// time remaining.

import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: root

  property int percent: 0
  property string caption: ""
  property bool charging: false
  property bool low: false

  readonly property color textColor: Color.popups.text
  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)
  readonly property color ringColor: low ? Color.urgent : Color.accent
  readonly property real fraction: Math.max(0, Math.min(1, percent / 100))

  spacing: Style.space(14)

  Item {
    Layout.preferredWidth: Style.space(62)
    Layout.preferredHeight: Style.space(62)

    Canvas {
      id: ring
      anchors.fill: parent

      readonly property real lineWidth: Style.space(6)

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2
        var cy = height / 2
        var r = (Math.min(width, height) - ring.lineWidth) / 2
        ctx.lineWidth = ring.lineWidth
        ctx.lineCap = "round"

        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
        ctx.strokeStyle = Util.alpha(root.textColor, 0.12)
        ctx.stroke()

        if (root.fraction <= 0) return
        ctx.beginPath()
        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * root.fraction)
        ctx.strokeStyle = root.ringColor
        ctx.stroke()
      }
    }

    // Canvas does not track the bindings its paint reads.
    Connections {
      target: root
      function onFractionChanged() { ring.requestPaint() }
      function onRingColorChanged() { ring.requestPaint() }
    }

    Text {
      anchors.centerIn: parent
      text: root.charging ? "󰉁" : "󰁹"
      color: root.charging ? root.ringColor : root.dimColor
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    spacing: Style.space(2)

    Text {
      text: root.percent + " %"
      color: root.textColor
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      Layout.fillWidth: true
      visible: text.length > 0
      text: root.caption
      color: root.dimColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
