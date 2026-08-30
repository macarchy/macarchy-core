// macOS-style Cmd+Tab app switcher.
//
// Hyprland binds summon this overlay with {"action": "next" | "prev"} on
// each SUPER+TAB press; while open it holds the keyboard and commits when
// Super is released, exactly like releasing Cmd. Windows are grouped by
// appId — one icon per application — and ordered by recency, which this
// overlay tracks itself (keepLoaded keeps it alive).
//
// Two macOS behaviors worth their code: the bar only materialises after a
// short hold, so a quick Cmd+Tab tap flips to the previous app without ever
// flashing UI; and the selection is one pill that slides between icons
// rather than cells lighting up. The card's glass is real — the theme blurs
// the "macarchy-switcher" layer namespace like its menus.

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool shown: false     // content fades in after the hold delay
  property int selectedIndex: 0
  property var apps: []          // [{ appId, name, iconSource, win }]
  property var mru: []           // appIds, most recent first
  property var lastWin: ({})     // appId -> most recent toplevel

  // Recency bookkeeping runs for the whole shell session.
  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      var t = ToplevelManager.activeToplevel
      if (!t || !t.appId) return
      var id = String(t.appId)
      var m = root.mru.filter(function(x) { return x !== id })
      m.unshift(id)
      root.mru = m
      var w = root.lastWin
      w[id] = t
      root.lastWin = w
    }
  }

  Timer {
    id: holdTimer
    interval: 140
    onTriggered: root.shown = true
  }

  function entryFor(appId) {
    var vals = DesktopEntries.applications.values || []
    var idl = String(appId).toLowerCase()
    var loose = null
    for (var i = 0; i < vals.length; i++) {
      var eid = String(vals[i].id || "").toLowerCase()
      if (eid === idl) return vals[i]
      if (eid.length > 0 && (idl.indexOf(eid) !== -1 || eid.indexOf(idl) !== -1)) loose = loose || vals[i]
    }
    return loose
  }

  function rebuild() {
    var seen = {}
    var list = []
    var tls = ToplevelManager.toplevels.values || []
    for (var i = 0; i < tls.length; i++) {
      var t = tls[i]
      var id = String(t.appId || "?")
      if (seen[id]) continue
      seen[id] = true
      var entry = entryFor(id)
      var icon = entry && entry.icon ? entry.icon : ""
      list.push({
        appId: id,
        name: entry && entry.name ? entry.name : (t.title || id),
        iconSource: Quickshell.iconPath(icon, true) || Quickshell.iconPath("application-x-executable", true),
        win: root.lastWin[id] || t
      })
    }
    var order = root.mru
    list.sort(function(a, b) {
      var ia = order.indexOf(a.appId); if (ia < 0) ia = 999
      var ib = order.indexOf(b.appId); if (ib < 0) ib = 999
      return ia - ib
    })
    root.apps = list
  }

  function advance(step) {
    if (root.apps.length === 0) return
    root.selectedIndex = (root.selectedIndex + step + root.apps.length) % root.apps.length
  }

  function settle() {
    root.opened = false
    root.shown = false
    holdTimer.stop()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide()
  }

  function commit() {
    if (!root.opened) { settle(); return }
    var app = root.apps[root.selectedIndex]
    settle()
    if (app && app.win) {
      try { app.win.activate() } catch (e) {}
    }
  }

  function open(payloadJson) {
    var action = "next"
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (p && p.action) action = p.action
    } catch (e) {}
    if (action === "commit") { commit(); return }
    if (action === "cancel") { settle(); return }
    if (!root.opened) {
      rebuild()
      root.opened = true
      holdTimer.restart()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      root.selectedIndex = 0
      if (root.apps.length > 1) root.selectedIndex = 1
      if (action === "prev") root.selectedIndex = Math.max(0, root.apps.length - 1)
    } else {
      advance(action === "prev" ? -1 : 1)
    }
  }

  function close() { settle() }
  function dismiss() { settle() }

  PanelWindow {
    id: panel
    // The surface exists from the first Tab so the keyboard grab (and the
    // release-to-commit) works during a quick tap; the content itself waits
    // out the hold delay.
    visible: root.opened && root.apps.length > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "macarchy-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
            || event.key === Qt.Key_Meta) {
          root.commit()
          event.accepted = true
        }
      }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
        else if (event.key === Qt.Key_Left) { root.advance(-1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { root.advance(1); event.accepted = true }
      }
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(strip.width + card.pad * 2, panel.width - Style.space(64))
      height: card.cell + card.pad * 2 + nameLabel.height + Style.spacing.sm
      radius: Style.space(26)
      // The theme blurs this namespace like its menus; the fill only needs
      // enough body to frost the blur, not to paint over it.
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g,
                     Color.menu.background.b, 0.55)
      border.color: Color.menu.border
      border.width: 1

      readonly property int cell: Style.space(96)
      readonly property int iconSize: Style.space(72)
      readonly property int pad: Style.space(18)

      opacity: root.shown ? 1 : 0
      scale: root.shown ? 1 : 0.97
      transformOrigin: Item.Center
      Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

      Item {
        id: strip
        width: root.apps.length * card.cell
        height: card.cell
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: card.pad

        // The selection is one pill that travels, macOS-style.
        Rectangle {
          id: pill
          width: card.cell
          height: card.cell
          radius: Style.space(18)
          // Neutral pill drawn from the text color, macOS-style: reads as
          // material in both the dark and light theme.
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g,
                         Color.menu.text.b, 0.16)
          x: root.selectedIndex * card.cell
          Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutQuint } }
        }

        Row {
          anchors.fill: parent
          spacing: 0

          Repeater {
            model: root.apps
            delegate: Item {
              width: card.cell
              height: card.cell

              Image {
                anchors.centerIn: parent
                width: card.iconSize
                height: card.iconSize
                sourceSize.width: card.iconSize
                sourceSize.height: card.iconSize
                source: modelData.iconSource
                asynchronous: true
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.selectedIndex = index
                  root.commit()
                }
              }
            }
          }
        }
      }

      Text {
        id: nameLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: strip.bottom
        anchors.topMargin: Style.spacing.sm / 2
        text: root.apps.length > 0 && root.apps[root.selectedIndex] ? root.apps[root.selectedIndex].name : ""
        color: Color.menu.text
        opacity: 0.85
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
        font.letterSpacing: 0.2
      }
    }
  }
}
