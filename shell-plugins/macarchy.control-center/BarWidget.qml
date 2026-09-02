pragma ComponentBehavior: Bound

// Control Center — a full-height liquid-glass sidebar on the LEFT edge, the
// mirror of the notification center on the right.
//
// This file is a SHELL, not a settings screen. It owns the home (the battery
// crown, eight quick tiles, the two sliders you actually drag, now playing,
// the radios) and it hosts MODULES: anything that needs a page of its own
// ships as one, including the two that live in this plugin's own modules/
// folder. A module is a plain Item that describes its row and hands over a
// page Component — see docs/superpowers/specs/2026-09-02-control-center-ux-design.md.
//
// What the shell takes care of, so modules stay dumb:
//   - instantiation is deferred to the first open, never shell startup;
//   - `panelOpen` / `pageShowing` / `pageSettled` are the only polling gates
//     a module needs;
//   - the Flickable and its WheelHandler live here. Hyprland scales touchpad
//     scrolling by input:touchpad:scroll_factor = 0.4 and Qt applies the
//     pixelDelta 1:1, which makes a bare Flickable useless on this trackpad.
//     The trap is solved once, here; a module page is content, not a scroller.
//   - a module that fails to load costs one urgent row, never the panel.
//
// Gesture grammar (see ~/.config/hypr/input.lua): a three-finger swipe toward
// a panel's edge dismisses it, away from its edge summons the opposite one.
// Both swipes land on swipeLeft/swipeRight, which resolve them against both
// panels' open state in-process.
//
// Every control routes through its owner: in-process shell services
// reactively, the macarchy daemons via their own CLIs, brightness via
// brightnessctl (the same path the keys take, which is what omarchy-als
// watches to learn its offset), radios via nmcli / bluetoothctl with the full
// device UIs deep-linked to the panels that already exist.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

import "components"

Panel {
  id: root
  moduleName: "macarchy.control-center"
  ipcTarget: "macarchy.control-center"
  // The standard Panel IPC is replaced below so the same target can also
  // carry the contextual swipe handlers and module navigation.
  manageIpc: false

  // The module interface this build speaks. A module declaring a higher
  // major is refused with a visible row rather than a silent blank.
  readonly property int moduleApiVersion: 1

  // ----------------------------------------------------- shell services
  readonly property var notificationService: bar && bar.shell ? bar.shell.serviceFor("omarchy.notifications") : null
  readonly property var nightlightService: bar && bar.shell ? bar.shell.serviceFor("omarchy.nightlight") : null
  readonly property var idleService: bar && bar.shell ? bar.shell.serviceFor("omarchy.idle") : null
  readonly property var mediaService: bar && bar.shell ? bar.shell.serviceFor("omarchy.media") : null

  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false
  readonly property bool nightlight: nightlightService ? nightlightService.enabled : false
  readonly property bool stayAwake: idleService ? idleService.stayAwake : false

  // ----------------------------------------------------- daemon states
  //
  // Polled on open, flipped optimistically on toggle, re-checked shortly
  // after so the tiles converge on the truth.
  property bool batteryLimited: true
  property bool aquariumOn: false
  // "on" | "paused" | "off" — the daemon's status line reports paused since
  // the omarchy-als paused-marker patch.
  property string alsState: "off"
  property string themeName: ""
  readonly property bool lightMode: themeName === "apple-glass-light"

  property bool wifiOn: false
  property string wifiSsid: ""
  property bool btOn: false
  property int btConnected: 0

  // "main", or the id of the module whose page is showing.
  property string route: "main"

  // A relayout while the finger is still moving yanks the content out from
  // under it; modules gate their fast polls on this.
  property bool scrolling: false
  Timer { id: scrollIdle; interval: 500; onTriggered: root.scrolling = false }
  readonly property var currentModule: route !== "main" ? (moduleInstances[route] || null) : null

  property int panelBrightness: 0
  property int panelMax: 1

  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    route = "main"
    // `bar.shell` is wired after this widget is constructed, so the scan at
    // Component.onCompleted can come up short on the very first open.
    if (!modulesReady) scanModules()
    modulesReady = true
    refresh()
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  onRouteChanged: scroller.contentY = 0

  function refresh() {
    batteryProc.running = true
    aquariumProc.running = true
    alsProc.running = true
    themeProc.running = true
    radioProc.running = true
    backlightProc.running = true
    volumeSinkProc.running = true

    for (var id in moduleInstances) {
      var inst = moduleInstances[id]
      if (inst && typeof inst.refresh === "function") inst.refresh()
    }
  }

  Timer { id: recheck; interval: 900; onTriggered: root.refresh() }
  // Theme switching takes a few seconds (terminals restart, hooks run).
  Timer { id: slowRecheck; interval: 4000; onTriggered: root.refresh() }

  // Backlights move under ALS and the keys while the panel sits open. Only on
  // the home: a module page polls its own copy, and the two never overlap.
  Timer {
    interval: 2000
    repeat: true
    running: root.opened && root.route === "main"
    onTriggered: backlightProc.running = true
  }

  // ----------------------------------------------------- modules
  //
  // Entries carry everything needed to draw a row BEFORE the module is
  // loaded — which is why `order` lives in the manifest and not in the QML:
  // sorting cannot wait for instantiation without reshuffling rows under the
  // pointer.
  property bool modulesReady: false
  property var moduleEntries: []
  property var moduleInstances: ({})

  function registerModule(id, item) {
    var next = ({})
    for (var k in root.moduleInstances) next[k] = root.moduleInstances[k]
    next[id] = item
    root.moduleInstances = next
  }

  function scanModules() {
    var found = [
      { id: "macarchy.cc.display", url: String(Qt.resolvedUrl("modules/Display.qml")),
        order: 10, name: "Affichage", manifest: null, error: "" },
      { id: "macarchy.cc.system", url: String(Qt.resolvedUrl("modules/System.qml")),
        order: 20, name: "Système", manifest: null, error: "" }
    ]

    var reg = bar && bar.shell ? bar.shell.pluginRegistry : null
    var plugins = reg && reg.installedPlugins ? reg.installedPlugins : null
    for (var id in plugins) {
      var m = plugins[id]
      if (!m || !Array.isArray(m.kinds)) continue
      if (m.kinds.indexOf("control-center-module") === -1) continue
      if (typeof reg.isEnabled === "function" && !reg.isEnabled(id)) continue

      var decl = m.controlCenterModule || {}
      var entry = {
        id: id, url: "", order: Number(decl.order) || 50,
        name: String(m.name || id), manifest: m, error: ""
      }
      if ((Number(decl.apiVersion) || 1) > root.moduleApiVersion) {
        entry.error = "Interface trop récente pour ce Control Center"
      } else {
        entry.url = String(reg.entryPointUrl(m, "controlCenterModule") || "")
        if (!entry.url) entry.error = "Point d'entrée introuvable"
      }
      found.push(entry)
    }

    found.sort(function(a, b) { return a.order - b.order || (a.name < b.name ? -1 : 1) })
    root.moduleEntries = found
  }

  Component.onCompleted: scanModules()

  Connections {
    target: root.bar && root.bar.shell ? root.bar.shell.pluginRegistry : null
    ignoreUnknownSignals: true
    function onPluginsChanged() { root.scanModules() }
  }

  // Instances live here, out of the layout, so a row can be drawn before its
  // module has loaded and can survive one that never does.
  Item {
    id: moduleHost
    visible: false
    width: 0
    height: 0

    Repeater {
      model: root.modulesReady ? root.moduleEntries : []

      delegate: Loader {
        id: slot
        required property var modelData

        active: String(slot.modelData.url).length > 0
        source: slot.modelData.url

        onLoaded: {
          if (!item) return
          if ("bar" in item) item.bar = root.bar
          if ("manifest" in item) item.manifest = slot.modelData.manifest
          item.panelOpen = Qt.binding(function() { return root.opened })
          item.pageShowing = Qt.binding(function() { return root.route === slot.modelData.id })
          if ("pageSettled" in item)
            item.pageSettled = Qt.binding(function() { return !root.scrolling })
          // A module that opens an editor wants the sidebar out of the way
          // first; it has no other business closing the panel.
          if (item.closeRequested) item.closeRequested.connect(root.close)
          root.registerModule(slot.modelData.id, item)
        }

        onStatusChanged: if (status === Loader.Error)
          console.warn("control-center: module failed to load:", slot.modelData.id)
      }
    }
  }

  // ----------------------------------------------------- toggle actions

  function toggleDnd() {
    if (notificationService) notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
  }

  function toggleNightlight() {
    if (nightlightService) nightlightService.setNightlight(!nightlight)
  }

  function toggleStayAwake() {
    // setIdleEnabled(true) re-enables idle, i.e. turns stay-awake OFF —
    // same call the bar indicator makes.
    if (idleService) idleService.setIdleEnabled(stayAwake)
  }

  function toggleBatteryLimit() {
    batteryLimited = !batteryLimited
    Quickshell.execDetached(["omarchy-battery-limit", "toggle"])
    recheck.restart()
  }

  function toggleAquarium() {
    aquariumOn = !aquariumOn
    Quickshell.execDetached(["omarchy-aquarium-toggle"])
    recheck.restart()
  }

  function toggleAls() {
    if (alsState === "off") {
      alsState = "on"
      Quickshell.execDetached(["omarchy-als", "daemon"])
    } else {
      alsState = alsState === "paused" ? "on" : "paused"
      Quickshell.execDetached(["omarchy-als", "toggle"])
    }
    recheck.restart()
  }

  // An explicit tap is a choice: it leaves the automatic appearance (the
  // timer) the way picking Light or Dark does on macOS. Entering Auto is the
  // Affichage page's job.
  function toggleAppearance() {
    var next = lightMode ? "apple-glass" : "apple-glass-light"
    themeName = next
    Quickshell.execDetached(["bash", "-c",
      "systemctl --user disable --now omarchy-auto-appearance.timer; exec omarchy-theme-set " + next])
    slowRecheck.restart()
  }

  function toggleWifi() {
    wifiOn = !wifiOn
    Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "on" : "off"])
    recheck.restart()
  }

  function toggleBluetooth() {
    btOn = !btOn
    Quickshell.execDetached(["bluetoothctl", "power", btOn ? "on" : "off"])
    recheck.restart()
  }

  // Deep-link a row to its full panel: close this sidebar, then open the bar
  // widget's own popup once the focus grab has let go.
  function openPanelWidget(id) {
    root.close()
    var list = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(id) : []
    if (list.length > 0 && typeof list[0].open === "function")
      Qt.callLater(function() { list[0].open() })
  }

  // ----------------------------------------------------- daemon probes

  Process {
    id: batteryProc
    command: ["bash", "-c",
      'b=/sys/class/power_supply/macsmc-battery\n' +
      'printf "%s\\n%s\\n%s\\n%s\\n" \\\n' +
      '  "$(cat $b/charge_control_end_threshold 2>/dev/null)" \\\n' +
      '  "$(cat $b/status 2>/dev/null)" \\\n' +
      '  "$(cat $b/time_to_empty_now 2>/dev/null)" \\\n' +
      '  "$(cat $b/time_to_full_now 2>/dev/null)"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var l = String(text).split("\n")
        var end = parseInt((l[0] || "").trim(), 10)
        if (isFinite(end) && end > 0) root.batteryLimited = end <= 80
        root.batteryStatus = (l[1] || "").trim()
        var empty = parseInt((l[2] || "").trim(), 10)
        var full = parseInt((l[3] || "").trim(), 10)
        root.batterySeconds = root.batteryStatus === "Charging"
          ? (isFinite(full) ? full : 0)
          : (isFinite(empty) ? empty : 0)
      }
    }
  }

  Process {
    id: aquariumProc
    command: ["bash", "-c", "omarchy-aquarium-toggle status >/dev/null 2>&1 && echo on || echo off"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.aquariumOn = String(text).trim() === "on"
    }
  }

  Process {
    id: alsProc
    command: ["bash", "-c", "omarchy-als status 2>/dev/null | tail -1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text)
        if (line.indexOf("running") === -1) root.alsState = "off"
        else root.alsState = line.indexOf("paused") !== -1 ? "paused" : "on"
      }
    }
  }

  Process {
    id: themeProc
    command: ["cat", Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.themeName = String(text).trim()
    }
  }

  Process {
    id: radioProc
    // The SSID comes from the active connection, not `dev wifi`: the scan
    // list can block for seconds (the tiles sat on "Off" meanwhile) and its
    // active column reads "no" even for the joined network on this driver.
    // printf guarantees exactly four lines, connected or not.
    command: ["bash", "-c",
      'w=$(LANG=C nmcli radio wifi 2>/dev/null)\n' +
      's=$(LANG=C nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -m1 802-11-wireless | cut -d: -f1)\n' +
      'b=$(bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && echo on || echo off)\n' +
      'c=$(bluetoothctl devices Connected 2>/dev/null | grep -c "^Device")\n' +
      'printf "%s\\n%s\\n%s\\n%s\\n" "${w:-disabled}" "$s" "$b" "${c:-0}"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).split("\n")
        if (lines.length < 4) return
        root.wifiOn = (lines[0] || "").trim() === "enabled"
        root.wifiSsid = (lines[1] || "").trim()
        root.btOn = (lines[2] || "").trim() === "on"
        var count = parseInt((lines[3] || "").trim(), 10)
        root.btConnected = isFinite(count) ? count : 0
      }
    }
  }

  // ----------------------------------------------------- backlight

  Process {
    id: backlightProc
    command: ["bash", "-c",
      'p=/sys/class/backlight/apple-panel-bl\n' +
      'echo "$(cat $p/brightness) $(cat $p/max_brightness)"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        if (parts.length < 2) return
        var b = parseInt(parts[0], 10)
        var m = parseInt(parts[1], 10)
        if (isFinite(m) && m > 0) root.panelMax = m
        // Don't yank a slider the user is holding.
        if (isFinite(b) && !panelSlider.dragging) root.panelBrightness = b
      }
    }
  }

  // Trailing-edge throttle: dragging emits a stream of moved() values, the
  // last one within each window is what brightnessctl gets. The settled value
  // is what omarchy-als confirms over two polls and learns from.
  property int pendingPanel: -1

  Timer {
    id: panelWrite
    interval: 120
    onTriggered: if (root.pendingPanel >= 0) {
      Quickshell.execDetached(["brightnessctl", "-q", "-d", "apple-panel-bl", "set", String(root.pendingPanel)])
      root.pendingPanel = -1
    }
  }

  function setPanelBrightness(frac) {
    // Floor of 1: writing 0 blanks the panel entirely.
    var value = Math.max(1, Math.round(frac * panelMax))
    panelBrightness = value
    pendingPanel = value
    panelWrite.restart()
  }

  // ----------------------------------------------------- volume (Pipewire)
  //
  // Same resolution the audio panel and the volume keys use: loudness lives on
  // the physical sink behind any DSP/tuning chain (Asahi speaker tuning),
  // which omarchy-audio-output-sink resolves from the current default.

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  property string volumeSinkName: ""

  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name)) return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio) return n
    }
    return sink
  }

  readonly property real outputVolume: volumeSink && volumeSink.audio ? volumeSink.audio.volume : 0
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  readonly property bool micMuted: source && source.audio ? source.audio.muted : false
  readonly property bool hasMic: !!(source && source.audio)
  readonly property string outputLabel: {
    var device = volumeSink && volumeSink.description ? String(volumeSink.description) : ""
    if (!device && sink && sink.description) device = String(sink.description)
    return device
  }

  PwObjectTracker { objects: root.volumeSink ? [root.volumeSink] : [] }
  PwObjectTracker { objects: root.source ? [root.source] : [] }

  Process {
    id: volumeSinkProc
    command: ["omarchy-audio-output-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.volumeSinkName = String(text).trim()
    }
  }

  function setVolume(v) {
    if (volumeSink && volumeSink.audio)
      volumeSink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleMute() {
    if (volumeSink && volumeSink.audio)
      volumeSink.audio.muted = !volumeSink.audio.muted
  }

  function toggleMic() {
    if (source && source.audio)
      source.audio.muted = !source.audio.muted
  }

  // ----------------------------------------------------- media

  readonly property var player: mediaService ? mediaService.activePlayer : null
  readonly property bool hasMedia: mediaService ? mediaService.hasMedia : false
  readonly property bool playing: player ? player.playbackState === MprisPlaybackState.Playing : false

  // ----------------------------------------------------- battery
  //
  // The percentage comes from UPower, which is reliable. The sentence does
  // not: UPower publishes no "time to" line on this machine (the macsmc
  // battery refreshes lazily, and under the 80 % cap the state sits on
  // pending-charge forever), so the driver's own sysfs counters are read
  // directly and the estimate is simply omitted when they read zero.

  property string batteryStatus: ""
  property int batterySeconds: 0

  readonly property var batteryDevice: UPower.displayDevice
  readonly property int batteryPercent: batteryDevice ? Math.round(Number(batteryDevice.percentage || 0) * 100) : 0
  readonly property bool batteryCharging: batteryStatus === "Charging"
  readonly property bool batteryDischarging: batteryStatus === "Discharging"
  readonly property bool batteryLow: batteryDischarging && batteryPercent <= 15

  function batteryTimeText() {
    if (batterySeconds <= 0) return ""
    var mins = Math.round(batterySeconds / 60)
    if (mins < 60) return mins + " min"
    return Math.floor(mins / 60) + " h " + String(mins % 60).padStart(2, "0")
  }

  function batteryCaption() {
    var parts = []
    if (batteryCharging) parts.push("En charge")
    else if (batteryDischarging) parts.push("Sur batterie")
    else parts.push("Branchée")

    var t = batteryTimeText()
    if (t.length > 0) parts.push(batteryCharging ? "pleine dans " + t : t + " restantes")
    else if (batteryLimited) parts.push("plafonnée à 80 %")
    return parts.join(" · ")
  }

  // ----------------------------------------------------- gestures / IPC

  function notificationCenter() {
    var list = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets("phmatray.notification-center") : []
    return list.length > 0 ? list[0] : null
  }

  // Swipe toward a panel's edge dismisses it; away from its edge summons the
  // opposite one.
  function swipeRight() {
    var nc = notificationCenter()
    if (nc && nc.opened) nc.close()
    else root.open()
  }

  function swipeLeft() {
    if (root.opened) root.close()
    else {
      var nc = notificationCenter()
      if (nc) nc.open()
    }
  }

  // Opening resets the route to the home, so the override has to land after
  // it. This is also the only way to verify a module page by screenshot:
  // this machine has neither synthetic pointer nor synthetic scroll.
  function showPage(id) {
    root.open()
    root.route = String(id)
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function swipeLeft(): void { root.swipeLeft() }
    function swipeRight(): void { root.swipeRight() }
    function page(id: string): void { root.showPage(id) }
    // Kept from when Jarvis was the only page there could be.
    function jarvis(): void { root.showPage("macarchy.jarvis") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘮"
    tooltipText: "Control Center"
    onPressed: function(buttonCode) { root.toggle() }
  }

  // ----------------------------------------------------- the sidebar

  PanelWindow {
    id: sidePanel
    visible: root.opened
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    color: "transparent"
    implicitWidth: Math.round(Style.space(380) + Style.spacing.popupPadding * 2 + 1)

    WlrLayershell.namespace: "macarchy-control-center"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
    }

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

      // Liquid glass, mirrored from the notification center: sheen and rim up
      // top, depth below, lit edge on the RIGHT where the pane meets the
      // pushed-aside windows.
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

      Rectangle {
        id: lightBand
        width: parent.width * 1.6
        height: Style.space(220)
        anchors.horizontalCenter: parent.horizontalCenter
        rotation: 14
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

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(1, 1, 1, 0.22)
      }

      Rectangle {
        anchors.right: parent.right
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
        anchors.rightMargin: Style.spacing.popupPadding + 1
        focus: true

        // Escape walks back one page before it closes the panel.
        Keys.onEscapePressed: {
          if (root.route !== "main") root.route = "main"
          else root.close()
        }

        Flickable {
          id: scroller
          anchors.fill: parent
          contentWidth: width
          contentHeight: content.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          clip: true
          interactive: contentHeight > height

          // Hyprland scales touchpad scrolling by 0.4 (input:touchpad:
          // scroll_factor) and Flickable applies pixelDelta 1:1, so a long
          // swipe moved the page a little. Drive contentY here instead, at
          // about finger speed on the touchpad and a sane step on a wheel.
          WheelHandler {
            target: null
            onWheel: function(event) {
              var max = Math.max(0, scroller.contentHeight - scroller.height)
              if (max <= 0) return
              var dy = event.pixelDelta.y !== 0
                ? event.pixelDelta.y * 2.5
                : (event.angleDelta.y / 120) * Style.space(80)
              scroller.contentY = Math.max(0, Math.min(max, scroller.contentY - dy))
              root.scrolling = true
              scrollIdle.restart()
            }
          }

          ColumnLayout {
            id: content
            width: scroller.width
            spacing: Style.space(16)

            // ------------------------------------------------ the home

            ColumnLayout {
              visible: root.route === "main"
              Layout.fillWidth: true
              spacing: Style.space(16)

              BatteryGlance {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(4)
                percent: root.batteryPercent
                caption: root.batteryCaption()
                charging: root.batteryCharging
                low: root.batteryLow
              }

              GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: Style.space(2)
                rowSpacing: Style.space(6)

                QuickTile {
                  Layout.fillWidth: true
                  glyph: "󰂛"
                  label: "Ne pas déranger"
                  active: root.dnd
                  onClicked: root.toggleDnd()
                }

                QuickTile {
                  Layout.fillWidth: true
                  glyph: "󰔎"
                  label: "Veilleuse"
                  active: root.nightlight
                  onClicked: root.toggleNightlight()
                }

                QuickTile {
                  Layout.fillWidth: true
                  glyph: "󰝕"
                  label: "Apparence"
                  active: root.lightMode
                  onClicked: root.toggleAppearance()
                }

                QuickTile {
                  Layout.fillWidth: true
                  visible: root.hasMic
                  glyph: root.micMuted ? "󰍭" : "󰍬"
                  label: "Micro"
                  active: !root.micMuted
                  onClicked: root.toggleMic()
                }

                QuickTile {
                  Layout.fillWidth: true
                  glyph: "󰈺"
                  label: "Aquarium"
                  active: root.aquariumOn
                  onClicked: root.toggleAquarium()
                }

                QuickTile {
                  Layout.fillWidth: true
                  glyph: "󰅶"
                  label: "Rester éveillé"
                  active: root.stayAwake
                  onClicked: root.toggleStayAwake()
                }

                QuickTile {
                  Layout.fillWidth: true
                  glyph: "󰃠"
                  label: "Luminosité auto"
                  // Three states: filled = correcting, ring = daemon alive
                  // but paused, neutral = not running.
                  mode: root.alsState
                  onClicked: root.toggleAls()
                }

                QuickTile {
                  Layout.fillWidth: true
                  glyph: "󱃍"
                  label: "Charge 80 %"
                  active: root.batteryLimited
                  onClicked: root.toggleBatteryLimit()
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)

                Text {
                  text: "󰖙"
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                }

                PanelSlider {
                  id: panelSlider
                  Layout.fillWidth: true
                  bar: root.bar
                  value: root.panelMax > 0 ? root.panelBrightness / root.panelMax : 0
                  onMoved: function(v) { root.setPanelBrightness(v) }
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(10)

                  Text {
                    text: root.outputMuted ? "󰖁" : "󰕾"
                    color: root.outputMuted ? root.dimColor : Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleMute()
                    }
                  }

                  PanelSlider {
                    Layout.fillWidth: true
                    bar: root.bar
                    value: Math.max(0, Math.min(1, root.outputVolume))
                    onMoved: function(v) { root.setVolume(v) }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  Layout.leftMargin: Style.space(28)
                  visible: root.outputLabel.length > 0
                  text: root.outputLabel
                  color: root.dimColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPanelWidget("omarchy.audio")
                  }
                }
              }

              // Now playing, when something is.
              RowLayout {
                visible: root.hasMedia
                Layout.fillWidth: true
                spacing: Style.space(10)

                Item {
                  Layout.preferredWidth: Style.space(36)
                  Layout.preferredHeight: Style.space(36)

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(6)
                    color: Util.alpha(Color.popups.text, 0.12)
                    visible: art.status !== Image.Ready

                    Text {
                      anchors.centerIn: parent
                      text: "󰝚"
                      color: root.dimColor
                      font.family: Style.font.family
                      font.pixelSize: Style.font.icon
                    }
                  }

                  Image {
                    id: art
                    anchors.fill: parent
                    source: root.mediaService ? root.mediaService.artUrl : ""
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    Layout.fillWidth: true
                    text: root.mediaService ? root.mediaService.title : ""
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.mediaService ? root.mediaService.artist : ""
                    color: root.dimColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                PanelActionButton {
                  iconText: "󰒮"
                  foreground: Color.popups.text
                  enabled: root.player && root.player.canGoPrevious
                  onClicked: if (root.player) root.player.previous()
                }

                PanelActionButton {
                  iconText: root.playing ? "󰏤" : "󰐊"
                  foreground: Color.popups.text
                  enabled: root.player && root.player.canTogglePlaying
                  onClicked: if (root.player) root.player.togglePlaying()
                }

                PanelActionButton {
                  iconText: "󰒭"
                  foreground: Color.popups.text
                  enabled: root.player && root.player.canGoNext
                  onClicked: if (root.player) root.player.next()
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)

                ConnectRow {
                  Layout.fillWidth: true
                  glyph: root.wifiOn ? "󰖩" : "󰖪"
                  label: "Wi-Fi"
                  stateText: root.wifiOn ? (root.wifiSsid.length > 0 ? root.wifiSsid : "Activé") : "Désactivé"
                  active: root.wifiOn
                  onToggled: root.toggleWifi()
                  onOpened: root.openPanelWidget("omarchy.network")
                }

                ConnectRow {
                  Layout.fillWidth: true
                  glyph: root.btOn ? "󰂯" : "󰂲"
                  label: "Bluetooth"
                  stateText: root.btOn
                    ? (root.btConnected > 0
                        ? root.btConnected + (root.btConnected === 1 ? " appareil" : " appareils")
                        : "Activé")
                    : "Désactivé"
                  active: root.btOn
                  onToggled: root.toggleBluetooth()
                  onOpened: root.openPanelWidget("omarchy.bluetooth")
                }

                // One row per module, drawn from the entry as soon as the
                // registry knows about it — a module that is still loading,
                // or that never will, still has a row.
                Repeater {
                  model: root.moduleEntries

                  delegate: ConnectRow {
                    id: moduleRow
                    required property var modelData
                    readonly property var inst: root.moduleInstances[moduleRow.modelData.id] || null

                    Layout.fillWidth: true
                    glyph: moduleRow.inst ? moduleRow.inst.glyph : "󰏗"
                    label: moduleRow.inst ? moduleRow.inst.title : moduleRow.modelData.name
                    stateText: moduleRow.modelData.error.length > 0
                      ? moduleRow.modelData.error
                      : (moduleRow.inst ? moduleRow.inst.summary : "…")
                    active: moduleRow.inst ? moduleRow.inst.active : false
                    alert: moduleRow.modelData.error.length > 0
                      || (moduleRow.inst ? moduleRow.inst.alert : false)
                    hasToggle: moduleRow.inst ? moduleRow.inst.hasToggle : false
                    hasPage: moduleRow.modelData.error.length === 0
                      && !!moduleRow.inst && !!moduleRow.inst.page
                    onToggled: if (moduleRow.inst) moduleRow.inst.toggled()
                    onOpened: root.route = moduleRow.modelData.id
                  }
                }
              }
            }

            // ------------------------------------------------ a module page

            ColumnLayout {
              visible: root.route !== "main"
              Layout.fillWidth: true
              spacing: Style.space(14)

              RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(2)
                spacing: Style.space(8)

                Button {
                  text: "‹"
                  fontSize: Style.font.title
                  foreground: Color.popups.text
                  onClicked: root.route = "main"
                }

                Text {
                  text: root.currentModule ? root.currentModule.title : ""
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Item { Layout.fillWidth: true }

                ToggleSwitch {
                  visible: !!root.currentModule && root.currentModule.hasToggle
                  checked: !!root.currentModule && root.currentModule.active
                  trackHeight: Style.space(16)
                  onToggled: if (root.currentModule) root.currentModule.toggled()
                }
              }

              Loader {
                Layout.fillWidth: true
                sourceComponent: root.currentModule ? root.currentModule.page : null
              }
            }
          }
        }
      }
    }
  }
}
