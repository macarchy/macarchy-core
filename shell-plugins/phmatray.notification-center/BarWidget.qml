// Notification center: a bell in the bar opening a macOS-style full-height
// sidebar of archived notifications, grouped per app with per-group and
// global clears, plus a Do Not Disturb switch wired to the built-in
// notification service.
//
// The sidebar is a layer-shell surface anchored to the right edge with an
// exclusive zone (ExclusionMode.Auto + three anchored edges), so Hyprland
// retiles windows out of its way instead of covering them, and it slots in
// under the bar's own reserved edge automatically.
//
// Data comes from this plugin's archiver service (Service.qml); every removal
// routes back through it so the archive, its tombstones, and the panel agree.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

import "CenterLogic.js" as CenterLogic
import "components"

Panel {
  id: root
  moduleName: "phmatray.notification-center"
  ipcTarget: "phmatray.notification-center"

  readonly property var center: bar && bar.shell ? bar.shell.serviceFor("phmatray.notification-center") : null
  readonly property var notificationService: bar && bar.shell ? bar.shell.serviceFor("omarchy.notifications") : null
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  readonly property var entries: center ? center.entries : []
  readonly property var groups: CenterLogic.groupEntries(entries)
  readonly property int collapsedCount: 3

  // Per-group "Show more" state, reset every open like macOS stacks.
  property var expandedGroups: ({})
  property double now: Date.now()

  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    expandedGroups = ({})
    now = Date.now()
    if (center) center.scan()
    panelFlick.contentY = 0
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  // Keep relative timestamps honest while the panel sits open.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  function toggleDnd() {
    if (notificationService)
      notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
  }

  function expandGroup(label) {
    var next = {}
    for (var key in expandedGroups) next[key] = expandedGroups[key]
    next[label] = true
    expandedGroups = next
  }

  function removeEntry(entry) {
    if (center && entry) center.removeEntries([entry.stem])
  }

  function clearGroup(group) {
    if (!center || !group) return
    var stems = []
    for (var i = 0; i < group.items.length; i++) stems.push(group.items[i].stem)
    center.removeEntries(stems)
  }

  // Same icon resolution as the cards, for the group headers.
  function resolveIcon(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  // Click-through like the built-in toasts: run the persisted action when one
  // survives, otherwise jump to the sender's window. Either way the entry
  // leaves the center, macOS-style.
  function activateEntry(entry) {
    if (!entry) return
    var argv = CenterLogic.parseExecArgv(entry.execArgv)
    if (argv) Util.execArgv(argv)
    else if (entry.app) Quickshell.execDetached(["omarchy-hyprland-focus-app", String(entry.app)])
    removeEntry(entry)
    close()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "󰂛" : "󰂚"
    tooltipText: root.dnd ? "Notifications (silenced)" : "Notifications"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleDnd()
      else root.toggle()
    }
  }

  PanelWindow {
    id: sidePanel
    visible: root.opened
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    color: "transparent"
    // Cards inside match the toast width exactly (NotificationCard's
    // Style.space(380)), so a notification keeps its size when it lands here.
    implicitWidth: Math.round(Style.space(380) + Style.spacing.popupPadding * 2 + 1)

    // Namespace is what the theme's glass blur layer rule matches on.
    WlrLayershell.namespace: "phmatray-notification-center"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Three anchored edges + the default ExclusionMode.Auto reserve the full
    // panel width on the right, which is what pushes tiled windows aside. The
    // compositor also keeps it clear of the bar's own reserved edge.
    anchors {
      top: true
      bottom: true
      right: true
    }

    // Clicking anywhere outside dismisses, macOS-style. The bar window rides
    // along in the grab so the bell's own click reaches toggle() instead of
    // the grab closing the panel first and the bell instantly reopening it.
    HyprlandFocusGrab {
      active: root.opened
      windows: root.QsWindow.window ? [sidePanel, root.QsWindow.window] : [sidePanel]
      onCleared: root.close()
    }

    Rectangle {
      id: glassSurface
      anchors.fill: parent
      color: Color.popups.background
      clip: true

      // ---- liquid glass treatment -------------------------------------
      // Hyprland's blur refracts what's behind the surface; these layers add
      // the material's own optics. White/black constants on purpose: glass
      // catches light the same way in both themes.

      // Specular sheen falling from the top edge.
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(150)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.13) }
          GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
      }

      // Bright rim where the pane catches the light under the bar.
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(1, 1, 1, 0.22)
      }

      // Depth shading toward the bottom.
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(180)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.14) }
        }
      }

      // A slow band of light drifting down the pane — the "liquid" in the
      // glass. Faint enough to never compete with text.
      Rectangle {
        id: lightBand
        width: parent.width * 1.6
        height: Style.space(220)
        anchors.horizontalCenter: parent.horizontalCenter
        rotation: -14
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.07) }
          GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }

        SequentialAnimation on y {
          running: root.opened
          loops: Animation.Infinite
          NumberAnimation {
            from: -lightBand.height
            to: glassSurface.height
            duration: 22000
            easing.type: Easing.InOutSine
          }
          PauseAnimation { duration: 6000 }
        }
      }

      // Lit glass edge where the pane meets the pushed-aside windows:
      // bright at the top where the sheen lives, fading as it descends.
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.30) }
          GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.06) }
        }
      }

      FocusScope {
        id: focusScope
        anchors.fill: parent
        anchors.margins: Style.spacing.popupPadding
        anchors.leftMargin: Style.spacing.popupPadding + 1
        focus: true

        Keys.onEscapePressed: root.close()

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(10)

          ColumnLayout {
            id: headerBlock
            Layout.fillWidth: true
            spacing: Style.space(8)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(6)

              Text {
                text: "Notifications"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Item { Layout.fillWidth: true }

              // Same glyphs and tooltip copy as the bar's DND indicator, so
              // the control reads as the same switch wherever it appears.
              PanelActionButton {
                iconText: root.dnd ? "󰂛" : "󰂚"
                tooltipText: root.dnd ? "Allow Notifications" : "Silence Notifications"
                foreground: root.dnd ? Color.accent : Color.popups.text
                onClicked: root.toggleDnd()
              }

              Button {
                visible: root.entries.length > 0
                text: "Clear All"
                fontSize: Style.font.caption
                foreground: Color.popups.text
                onClicked: if (root.center) root.center.clearAll()
              }
            }

            PanelSeparator {
              Layout.fillWidth: true
              foreground: Color.popups.text
            }
          }

          // Empty state, macOS wording, centered in the free height.
          Item {
            visible: root.groups.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(8)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰂚"
                color: Util.alpha(Color.popups.text, 0.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "No Recent Notifications"
                color: root.dimColor
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Flickable {
            id: panelFlick
            visible: root.groups.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: listColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Hyprland scales touchpad scrolling by 0.4 (input:touchpad:
            // scroll_factor) and Flickable applies pixelDelta 1:1, so a long
            // swipe moved the list a little. Drive contentY here instead, at
            // about finger speed on the touchpad and a sane step on a wheel
            // (same handler as the control center's Jarvis page).
            WheelHandler {
              target: null
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var dy = event.pixelDelta.y !== 0
                  ? event.pixelDelta.y * 2.5
                  : event.angleDelta.y / 120 * Style.space(80)
                var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
                panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - dy))
              }
            }

            Column {
              id: listColumn
              width: panelFlick.width
              // Wider than the intra-group card gap, so stacks read as stacks.
              spacing: Style.space(18)

              Repeater {
                model: root.groups

                delegate: Column {
                  id: groupColumn
                  required property var modelData
                  readonly property bool expanded: !!root.expandedGroups[modelData.label]
                  readonly property var visibleItems: expanded
                    ? modelData.items
                    : modelData.items.slice(0, root.collapsedCount)
                  readonly property int hiddenCount: modelData.items.length - root.collapsedCount

                  width: listColumn.width
                  spacing: Style.space(6)

                  RowLayout {
                    id: groupHeader
                    width: parent.width
                    spacing: Style.space(6)

                    readonly property string iconSource: root.resolveIcon(groupColumn.modelData.appIcon)
                    readonly property bool hovered: groupHeaderHover.hovered

                    HoverHandler { id: groupHeaderHover }

                    // The sending app's own mark, macOS-stack style: its icon
                    // when one resolves, its glyph otherwise, nothing if bare.
                    Image {
                      id: groupIcon
                      Layout.preferredWidth: Style.space(14)
                      Layout.preferredHeight: Style.space(14)
                      Layout.alignment: Qt.AlignVCenter
                      visible: groupHeader.iconSource.length > 0 && status !== Image.Error
                      source: groupHeader.iconSource
                      sourceSize.width: width * Screen.devicePixelRatio
                      sourceSize.height: height * Screen.devicePixelRatio
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      visible: !groupIcon.visible && groupColumn.modelData.glyph.length > 0
                      text: groupColumn.modelData.glyph
                      color: Qt.darker(Color.popups.text, 1.4)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    PanelSectionHeader {
                      Layout.fillWidth: true
                      text: groupColumn.modelData.label
                      foreground: Color.popups.text
                      elide: Text.ElideRight
                    }

                    // Destructive, so it only surfaces on hover and takes the
                    // urgent hover tint like other forget/unpair actions. It
                    // stays in the layout at opacity 0 — removing it on
                    // un-hover would change the header height and make the
                    // whole stack jump.
                    PanelActionButton {
                      iconText: "󰅖"
                      fontSize: Style.font.caption
                      size: Style.space(18)
                      tooltipText: "Clear " + groupColumn.modelData.label
                      foreground: Qt.darker(Color.popups.text, 1.4)
                      hoverColor: Color.urgent
                      enabled: groupHeader.hovered
                      opacity: groupHeader.hovered ? 1 : 0
                      Behavior on opacity { NumberAnimation { duration: 100 } }
                      onClicked: root.clearGroup(groupColumn.modelData)
                    }
                  }

                  Repeater {
                    model: groupColumn.visibleItems

                    delegate: CenterCard {
                      required property var modelData
                      width: groupColumn.width
                      app: modelData.app
                      appIcon: modelData.appIcon
                      summary: modelData.summary
                      body: modelData.body
                      image: modelData.image
                      glyph: modelData.glyph
                      urgency: modelData.urgency
                      timeText: CenterLogic.timeAgo(modelData.timestamp, root.now)
                      onActivated: root.activateEntry(modelData)
                      onCloseRequested: root.removeEntry(modelData)
                    }
                  }

                  // "Show more" as a small chip, like the collapsed-stack
                  // affordance under a macOS notification stack.
                  Rectangle {
                    visible: !groupColumn.expanded && groupColumn.hiddenCount > 0
                    radius: height / 2
                    color: showMoreArea.containsMouse ? Style.hoverFill : Style.normalFill
                    implicitWidth: showMoreText.implicitWidth + Style.space(20)
                    implicitHeight: showMoreText.implicitHeight + Style.space(8)

                    Text {
                      id: showMoreText
                      anchors.centerIn: parent
                      text: "Show " + groupColumn.hiddenCount + " more"
                      color: showMoreArea.containsMouse ? Color.popups.text : root.dimColor
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: showMoreArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.expandGroup(groupColumn.modelData.label)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
