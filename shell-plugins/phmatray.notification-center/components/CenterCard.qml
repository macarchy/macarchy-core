// One archived notification row in the center panel. Built from the same
// glass-card material as the built-in toast (NotificationCard): the
// notifications background/border/text tokens and the Hyprland-mirrored
// corner radius, so the archive reads as the notifications themselves,
// landed — just set denser for a list, with a relative timestamp.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string glyph: ""
  property string timeText: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2.
  property int urgency: 1

  signal activated()
  signal closeRequested()

  readonly property bool hovered: hoverTracker.hovered
  readonly property string smallIconSource: resolveIcon(image.length > 0 ? image : appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property string cleanBody: String(body || "")
    .replace(/<img[^>]*>/gi, "")
    .replace(/\r\n|\r|\n/g, "<br/>")
    .trim()

  // Same derivations as NotificationCard, off the notifications text token.
  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.4)
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)

  function resolveIcon(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  radius: Style.cornerRadius
  // The toast's background token at full alpha: the theme's glass alpha is
  // tuned for a card floating alone over the desktop, but here cards sit on
  // the already-translucent panel — stacked glass just goes muddy.
  color: Qt.rgba(Color.notifications.background.r, Color.notifications.background.g, Color.notifications.background.b, 1.0)
  borderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))
  clip: true
  topPadding: Style.space(8)
  bottomPadding: Style.space(8)
  leftPadding: Style.space(10)
  rightPadding: Style.space(10)

  implicitHeight: contentRow.implicitHeight + contentTopInset + contentBottomInset

  // Critical notifications keep a visible mark even in the archive.
  Rectangle {
    visible: root.urgency === 2
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.borderLeft
    anchors.topMargin: root.borderTop
    anchors.bottomMargin: root.borderBottom
    width: Style.space(3)
    color: Color.urgent
  }

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.closeRequested()
      else root.activated()
    }
  }

  RowLayout {
    id: contentRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.contentTopInset
    anchors.leftMargin: root.contentLeftInset
    anchors.rightMargin: root.contentRightInset
    spacing: Style.space(10)

    Item {
      id: iconSlot
      Layout.preferredWidth: visible ? Style.space(28) : 0
      Layout.preferredHeight: visible ? Style.space(28) : 0
      Layout.alignment: Qt.AlignVCenter
      visible: (root.smallIconSource.length > 0 && iconImage.status !== Image.Error) || root.hasGlyph

      Image {
        id: iconImage
        anchors.fill: parent
        source: root.smallIconSource
        sourceSize.width: iconSlot.width * Screen.devicePixelRatio
        sourceSize.height: iconSlot.height * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: !root.hasGlyph || iconImage.status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: root.hasGlyph && iconImage.status !== Image.Ready
        text: root.glyph
        color: Color.notifications.text
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.space(2)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          text: root.summary
          color: Color.notifications.text
          font.family: "Liberation Sans"
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          maximumLineCount: 1
        }

        // The timestamp and the close button share one slot and cross-fade,
        // so hovering never moves a single pixel of layout.
        Item {
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredWidth: Math.max(timeLabel.implicitWidth, closeBadge.width)
          Layout.preferredHeight: Math.max(timeLabel.implicitHeight, closeBadge.height)

          Text {
            id: timeLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.timeText
            color: root.dimColor
            font.family: "Liberation Sans"
            font.pixelSize: Style.font.caption
            opacity: root.hovered ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 100 } }
          }

          Rectangle {
            id: closeBadge
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: Style.space(16)
            radius: width / 2
            color: closeArea.containsMouse
              ? Qt.rgba(Color.notifications.text.r, Color.notifications.text.g, Color.notifications.text.b, 0.28)
              : Qt.rgba(Color.notifications.text.r, Color.notifications.text.g, Color.notifications.text.b, 0.14)
            opacity: root.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }

            Text {
              anchors.centerIn: parent
              text: "󰅖"
              color: Color.notifications.text
              font.family: Style.font.family
              font.pixelSize: Style.space(9)
            }

            MouseArea {
              id: closeArea
              anchors.fill: parent
              enabled: root.hovered
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.closeRequested()
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.cleanBody.length > 0
        text: root.cleanBody
        textFormat: Text.StyledText
        color: root.bodyColor
        font.family: "Liberation Sans"
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 2
      }
    }
  }

}
