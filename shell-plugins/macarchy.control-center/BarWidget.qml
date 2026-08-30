// Control Center: a full-height liquid-glass sidebar on the LEFT edge —
// the mirror of the notification center on the right. Quick toggles,
// display and sound sliders, connectivity, now playing, and battery.
//
// Gesture grammar (see ~/.config/hypr/input.lua): a three-finger swipe
// toward a panel's edge dismisses it, away from its edge summons the
// opposite one. Both swipes land on this widget's swipeLeft/swipeRight
// IPC, which resolves them against both panels' open state in-process.
//
// Every control routes through its owner:
//   - in-process shell services (notifications, nightlight, idle, media)
//     reactively;
//   - the macarchy daemons via their own CLIs (omarchy-als,
//     omarchy-battery-limit, omarchy-aquarium-toggle, omarchy theme set);
//   - brightness via brightnessctl — the same path the brightness keys
//     take, which is exactly what omarchy-als watches to learn its curve
//     offset (writes are confirmed over two 1s polls, so the settled
//     slider value becomes the learned preference);
//   - radios via nmcli / bluetoothctl, with the full device UIs
//     deep-linked to the existing network/bluetooth panels.

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
  // carry the contextual swipe handlers.
  manageIpc: false

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
  // "on" | "paused" | "off" — the daemon's status line reports paused
  // since the omarchy-als paused-marker patch.
  property string alsState: "off"
  // Current theme slug; the Appearance tile is "light mode" on/off.
  property string themeName: ""
  readonly property bool lightMode: themeName === "apple-glass-light"

  // Wi-Fi / Bluetooth radios.
  property bool wifiOn: false
  property string wifiSsid: ""
  property bool btOn: false
  property int btConnected: 0

  // Jarvis: mascot visibility (live, via its IPC) and the soul's settings
  // (read from SOUL.md; writes go through sed + `omarchy-jarvis reset` so
  // the new soul takes effect on the next conversation).
  readonly property string soulPath: Quickshell.env("HOME") + "/Work/jarvis/SOUL.md"
  readonly property string jarvisMemoryDir: Quickshell.env("HOME") + "/Work/jarvis/memory/"
  property bool jarvisShown: true
  property string jarvisTone: "majordome"
  property bool jarvisHumor: true
  property bool jarvisVous: false
  property string jarvisLang: "fr"
  property bool jarvisWake: false
  readonly property var jarvisLangs: [["fr", "Français"], ["en", "English"], ["auto", "Auto"]]
  property int jarvisFailures: 0
  property int jarvisLessons: 0
  readonly property var jarvisTones: ["majordome", "complice", "laconique"]

  // "main" | "jarvis" — which page the sidebar shows.
  property string page: "main"

  // Backlights (raw sysfs units).
  property int panelBrightness: 0
  property int panelMax: 1
  property int kbdBrightness: 0
  property int kbdMax: 1

  readonly property color dimColor: Util.alpha(Color.popups.text, 0.55)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    page = "main"
    refresh()
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function refresh() {
    batteryLimitProc.running = true
    aquariumProc.running = true
    alsProc.running = true
    themeProc.running = true
    radioProc.running = true
    backlightProc.running = true
    volumeSinkProc.running = true
    jarvisProc.running = true
  }

  Timer {
    id: recheck
    interval: 900
    repeat: false
    onTriggered: root.refresh()
  }

  // Theme switching takes a few seconds (terminals restart, hooks run).
  Timer {
    id: slowRecheck
    interval: 4000
    repeat: false
    onTriggered: root.refresh()
  }

  // Backlights move under ALS/keys while the panel sits open.
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: backlightProc.running = true
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

  function toggleAppearance() {
    var next = lightMode ? "apple-glass" : "apple-glass-light"
    themeName = next
    Quickshell.execDetached(["omarchy-theme-set", next])
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

  function toggleJarvis() {
    jarvisShown = !jarvisShown
    Quickshell.execDetached(["omarchy-shell", "macarchy.jarvis", jarvisShown ? "show" : "hide"])
  }

  function setJarvisTone(tone) {
    jarvisTone = tone
    Quickshell.execDetached(["bash", "-c",
      'sed -i "s/^- ton: .*/- ton: $1/" "$2" && omarchy-jarvis reset', "--",
      tone, soulPath])
  }

  function toggleJarvisHumor() {
    jarvisHumor = !jarvisHumor
    Quickshell.execDetached(["bash", "-c",
      'sed -i "s/^- humour: .*/- humour: $1/" "$2" && omarchy-jarvis reset', "--",
      jarvisHumor ? "oui" : "non", soulPath])
  }

  function toggleJarvisWake() {
    jarvisWake = !jarvisWake
    if (jarvisWake) Quickshell.execDetached(["omarchy-jarvis-wake"])
    else Quickshell.execDetached(["pkill", "-f", "jarvis-wake[.]py"])
    recheck.restart()
  }

  function setJarvisLang(lang) {
    jarvisLang = lang
    Quickshell.execDetached(["bash", "-c",
      'sed -i "s/^- langue: .*/- langue: $1/" "$2"', "--",
      lang, soulPath])
  }

  function toggleJarvisVous() {
    jarvisVous = !jarvisVous
    Quickshell.execDetached(["bash", "-c",
      'sed -i "s/^- adresse: .*/- adresse: $1/" "$2" && omarchy-jarvis reset', "--",
      jarvisVous ? "monsieur" : "tutoiement", soulPath])
  }

  function editSoul() {
    root.close()
    Quickshell.execDetached(["zed", soulPath])
  }

  function editMemory(file) {
    root.close()
    Quickshell.execDetached(["zed", jarvisMemoryDir + file])
  }

  function jarvisDream() {
    Quickshell.execDetached(["omarchy-jarvis", "dream"])
    root.close()
  }

  function jarvisReset() {
    Quickshell.execDetached(["omarchy-jarvis", "reset"])
  }

  // Deep-link a row to its full panel: close this sidebar, then open the
  // bar widget's own popup once the focus grab has let go.
  function openPanelWidget(id) {
    root.close()
    var list = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(id) : []
    if (list.length > 0 && typeof list[0].open === "function")
      Qt.callLater(function() { list[0].open() })
  }

  // ----------------------------------------------------- daemon probes

  Process {
    id: batteryLimitProc
    running: false
    command: ["cat", "/sys/class/power_supply/macsmc-battery/charge_control_end_threshold"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var end = parseInt(String(text).trim(), 10)
        if (isFinite(end)) root.batteryLimited = end <= 80
      }
    }
  }

  Process {
    id: aquariumProc
    running: false
    command: ["bash", "-c", "omarchy-aquarium-toggle status >/dev/null 2>&1 && echo on || echo off"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.aquariumOn = String(text).trim() === "on"
    }
  }

  Process {
    id: alsProc
    running: false
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
    running: false
    command: ["cat", Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.themeName = String(text).trim()
    }
  }

  Process {
    id: radioProc
    running: false
    command: ["bash", "-c",
      'LANG=C nmcli -t -f WIFI radio 2>/dev/null\n' +
      'LANG=C nmcli -t -f active,ssid dev wifi 2>/dev/null | grep "^yes" | head -1 | cut -d: -f2\n' +
      'echo "--"\n' +
      'bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && echo on || echo off\n' +
      'bluetoothctl devices Connected 2>/dev/null | grep -c "^Device" || true']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).split("\n")
        var sep = lines.indexOf("--")
        if (sep === -1) return
        root.wifiOn = (lines[0] || "").trim() === "enabled"
        root.wifiSsid = sep > 1 ? (lines[1] || "").trim() : ""
        root.btOn = (lines[sep + 1] || "").trim() === "on"
        var count = parseInt((lines[sep + 2] || "").trim(), 10)
        root.btConnected = isFinite(count) ? count : 0
      }
    }
  }

  Process {
    id: jarvisProc
    running: false
    command: ["bash", "-c",
      'omarchy-shell macarchy.jarvis isShown 2>/dev/null || echo off\n' +
      'grep -m1 "^- ton:" "$1" 2>/dev/null | sed "s/^- ton: *//"\n' +
      'grep -m1 "^- humour:" "$1" 2>/dev/null | sed "s/^- humour: *//"\n' +
      'grep -m1 "^- adresse:" "$1" 2>/dev/null | sed "s/^- adresse: *//"\n' +
      'grep -m1 "^- langue:" "$1" 2>/dev/null | sed "s/^- langue: *//"\n' +
      // The bracket keeps this probing shell's own cmdline out of the
      // match — a plain pattern makes pgrep find itself and the toggle
      // reads "on" forever.
      'pgrep -f "jarvis-wake[.]py" >/dev/null && echo on || echo off\n' +
      // wc -l always prints exactly one line, unlike `grep -c || echo 0`
      // which double-prints on a zero-match file and shifts every line
      // after it.
      'grep "^- \\[" "$2/FAILURES.md" 2>/dev/null | wc -l\n' +
      'grep "^- " "$2/LEARNED.md" 2>/dev/null | wc -l', "--",
      root.soulPath, root.jarvisMemoryDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).split("\n")
        root.jarvisShown = (lines[0] || "").trim() === "on"
        var tone = (lines[1] || "").trim()
        if (root.jarvisTones.indexOf(tone) !== -1) root.jarvisTone = tone
        root.jarvisHumor = (lines[2] || "").trim() !== "non"
        root.jarvisVous = (lines[3] || "").trim() === "monsieur"
        var lang = (lines[4] || "").trim()
        root.jarvisLang = (lang === "fr" || lang === "en" || lang === "auto") ? lang : "fr"
        root.jarvisWake = (lines[5] || "").trim() === "on"
        var fails = parseInt((lines[6] || "").trim(), 10)
        var lessons = parseInt((lines[7] || "").trim(), 10)
        root.jarvisFailures = isFinite(fails) ? fails : 0
        root.jarvisLessons = isFinite(lessons) ? lessons : 0
      }
    }
  }

  // ----------------------------------------------------- backlights

  Process {
    id: backlightProc
    running: false
    command: ["bash", "-c",
      'p=/sys/class/backlight/apple-panel-bl; k=/sys/class/leds/kbd_backlight\n' +
      'echo "$(cat $p/brightness) $(cat $p/max_brightness) $(cat $k/brightness) $(cat $k/max_brightness)"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        if (parts.length < 4) return
        var pb = parseInt(parts[0], 10), pm = parseInt(parts[1], 10)
        var kb = parseInt(parts[2], 10), km = parseInt(parts[3], 10)
        if (isFinite(pm) && pm > 0) root.panelMax = pm
        if (isFinite(km) && km > 0) root.kbdMax = km
        // Don't yank a slider the user is holding.
        if (isFinite(pb) && !panelSlider.dragging) root.panelBrightness = pb
        if (isFinite(kb) && !kbdSlider.dragging) root.kbdBrightness = kb
      }
    }
  }

  // Trailing-edge throttle: dragging emits a stream of moved() values, the
  // last one within each window is what brightnessctl gets. The settled
  // value is what omarchy-als confirms over two polls and learns from.
  property int pendingPanel: -1
  property int pendingKbd: -1

  Timer {
    id: panelWrite
    interval: 120
    repeat: false
    onTriggered: if (root.pendingPanel >= 0) {
      Quickshell.execDetached(["brightnessctl", "-q", "-d", "apple-panel-bl", "set", String(root.pendingPanel)])
      root.pendingPanel = -1
    }
  }

  Timer {
    id: kbdWrite
    interval: 120
    repeat: false
    onTriggered: if (root.pendingKbd >= 0) {
      Quickshell.execDetached(["brightnessctl", "-q", "-d", "kbd_backlight", "set", String(root.pendingKbd)])
      root.pendingKbd = -1
    }
  }

  function setPanelBrightness(frac) {
    // Floor of 1: writing 0 blanks the panel entirely.
    var value = Math.max(1, Math.round(frac * panelMax))
    panelBrightness = value
    pendingPanel = value
    panelWrite.restart()
  }

  function setKbdBrightness(frac) {
    var value = Math.max(0, Math.round(frac * kbdMax))
    kbdBrightness = value
    pendingKbd = value
    kbdWrite.restart()
  }

  // ----------------------------------------------------- volume (Pipewire)
  //
  // Same resolution the audio panel and the volume keys use: loudness lives
  // on the physical sink behind any DSP/tuning chain (Asahi speaker tuning),
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
    running: false
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

  // ----------------------------------------------------- battery glance

  readonly property var batteryDevice: UPower.displayDevice
  readonly property int batteryPercent: batteryDevice ? Math.round(Number(batteryDevice.percentage || 0) * 100) : 0
  readonly property bool batteryCharging: batteryDevice ? batteryDevice.state === UPowerDeviceState.Charging : false

  // ----------------------------------------------------- gestures / IPC

  function notificationCenter() {
    var list = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets("phmatray.notification-center") : []
    return list.length > 0 ? list[0] : null
  }

  // Swipe toward a panel's edge dismisses it; away from its edge summons
  // the opposite one.
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

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function swipeLeft(): void { root.swipeLeft() }
    function swipeRight(): void { root.swipeRight() }
    // Deep link straight to the Jarvis page. Open first: opening resets
    // the page to "main", so the override has to land after it.
    function jarvis(): void { root.open(); root.page = "jarvis" }
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
    implicitWidth: Math.round(Style.space(340) + Style.spacing.popupPadding * 2 + 1)

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

      // Liquid glass, mirrored from the notification center: sheen and rim
      // up top, depth below, lit edge on the RIGHT where the pane meets the
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

        Keys.onEscapePressed: {
          if (root.page !== "main") root.page = "main"
          else root.close()
        }

        ColumnLayout {
          visible: root.page === "main"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(10)

          Text {
            text: "Control Center"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: Color.popups.text
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            ControlTile {
              Layout.fillWidth: true
              glyph: "󰂛"
              label: "Do Not Disturb"
              active: root.dnd
              onClicked: root.toggleDnd()
            }

            ControlTile {
              Layout.fillWidth: true
              glyph: "󰔎"
              label: "Night Light"
              active: root.nightlight
              onClicked: root.toggleNightlight()
            }

            ControlTile {
              Layout.fillWidth: true
              glyph: "󰃠"
              label: "Auto Brightness"
              stateText: root.alsState === "on" ? "On"
                : (root.alsState === "paused" ? "Paused" : "Off")
              active: root.alsState === "on"
              onClicked: root.toggleAls()
            }

            ControlTile {
              Layout.fillWidth: true
              glyph: "󱃍"
              label: "Battery Limit"
              stateText: root.batteryLimited ? "Capped at 80%" : "Charging to 100%"
              active: root.batteryLimited
              onClicked: root.toggleBatteryLimit()
            }

            ControlTile {
              Layout.fillWidth: true
              glyph: "󰈺"
              label: "Aquarium"
              active: root.aquariumOn
              onClicked: root.toggleAquarium()
            }

            ControlTile {
              Layout.fillWidth: true
              glyph: "󰅶"
              label: "Stay Awake"
              active: root.stayAwake
              onClicked: root.toggleStayAwake()
            }

            ControlTile {
              Layout.fillWidth: true
              glyph: "󰝕"
              label: "Appearance"
              stateText: root.lightMode ? "Light" : "Dark"
              active: root.lightMode
              onClicked: root.toggleAppearance()
            }

            ControlTile {
              Layout.fillWidth: true
              visible: root.hasMic
              glyph: root.micMuted ? "󰍭" : "󰍬"
              label: "Microphone"
              stateText: root.micMuted ? "Muted" : "Live"
              active: !root.micMuted
              onClicked: root.toggleMic()
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: Color.popups.text
          }

          PanelSectionHeader {
            text: "Display"
            foreground: Color.popups.text
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

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              text: "󰌌"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
            }

            PanelSlider {
              id: kbdSlider
              Layout.fillWidth: true
              bar: root.bar
              value: root.kbdMax > 0 ? root.kbdBrightness / root.kbdMax : 0
              onMoved: function(v) { root.setKbdBrightness(v) }
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: Color.popups.text
          }

          PanelSectionHeader {
            text: "Sound"
            foreground: Color.popups.text
          }

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
            visible: root.outputLabel.length > 0
            text: root.outputLabel
            color: root.dimColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: Color.popups.text
          }

          ConnectRow {
            Layout.fillWidth: true
            glyph: root.wifiOn ? "󰖩" : "󰖪"
            label: "Wi-Fi"
            stateText: root.wifiOn ? (root.wifiSsid.length > 0 ? root.wifiSsid : "On") : "Off"
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
                  ? root.btConnected + (root.btConnected === 1 ? " device" : " devices")
                  : "On")
              : "Off"
            active: root.btOn
            onToggled: root.toggleBluetooth()
            onOpened: root.openPanelWidget("omarchy.bluetooth")
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: Color.popups.text
          }

          PanelSectionHeader {
            text: "Jarvis"
            foreground: Color.popups.text
          }

          // The master switch shows/dives the Babel fish; clicking the row
          // opens the dedicated Jarvis page.
          ConnectRow {
            Layout.fillWidth: true
            glyph: "󰚩"
            label: "Jarvis"
            stateText: root.jarvisTone.charAt(0).toUpperCase() + root.jarvisTone.slice(1)
              + (root.jarvisLessons > 0 ? " · " + root.jarvisLessons + " leçon" + (root.jarvisLessons > 1 ? "s" : "") : "")
            active: root.jarvisShown
            onToggled: root.toggleJarvis()
            onOpened: root.page = "jarvis"
          }

          PanelSeparator {
            visible: root.hasMedia
            Layout.fillWidth: true
            foreground: Color.popups.text
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

          PanelSeparator {
            Layout.fillWidth: true
            foreground: Color.popups.text
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: root.batteryCharging ? "󰉁" : "󰂂"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
            }

            Text {
              text: root.batteryPercent + "%"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              text: root.batteryCharging
                ? (root.batteryLimited ? "charging · capped at 80%" : "charging")
                : (root.batteryLimited ? "capped at 80%" : "")
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Item { Layout.fillWidth: true }
          }
        }

        // ------------------------------------------------ the Jarvis page

        ColumnLayout {
          visible: root.page === "jarvis"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Button {
              text: "‹"
              fontSize: Style.font.title
              foreground: Color.popups.text
              onClicked: root.page = "main"
            }

            Text {
              text: "Jarvis"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Item { Layout.fillWidth: true }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: Color.popups.text
          }

          ConnectRow {
            Layout.fillWidth: true
            glyph: "󰈺"
            label: "Mascotte"
            stateText: root.jarvisShown ? "Visible" : "Cachée"
            active: root.jarvisShown
            onToggled: root.toggleJarvis()
            onOpened: root.toggleJarvis()
          }

          PanelSectionHeader {
            text: "Âme"
            foreground: Color.popups.text
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Repeater {
              model: root.jarvisTones

              delegate: Button {
                required property string modelData
                Layout.fillWidth: true
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                fontSize: Style.font.caption
                foreground: Color.popups.text
                selected: root.jarvisTone === modelData
                onClicked: root.setJarvisTone(modelData)
              }
            }
          }

          Toggle {
            Layout.fillWidth: true
            label: "Humour"
            checked: root.jarvisHumor
            foreground: Color.popups.text
            onClicked: root.toggleJarvisHumor()
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "Langue"
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.jarvisLangs

              delegate: Button {
                required property var modelData
                Layout.fillWidth: true
                text: modelData[1]
                fontSize: Style.font.caption
                foreground: Color.popups.text
                selected: root.jarvisLang === modelData[0]
                onClicked: root.setJarvisLang(modelData[0])
              }
            }
          }

          Toggle {
            Layout.fillWidth: true
            label: "« Hey Jarvis » (wake word)"
            checked: root.jarvisWake
            foreground: Color.popups.text
            onClicked: root.toggleJarvisWake()
          }

          Toggle {
            Layout.fillWidth: true
            label: "Vouvoiement (« Monsieur »)"
            checked: root.jarvisVous
            foreground: Color.popups.text
            onClicked: root.toggleJarvisVous()
          }

          Button {
            Layout.fillWidth: true
            text: "Éditer l'âme (SOUL.md)"
            fontSize: Style.font.caption
            foreground: Color.popups.text
            onClicked: root.editSoul()
          }

          PanelSectionHeader {
            text: "Mémoire"
            foreground: Color.popups.text
          }

          Text {
            Layout.fillWidth: true
            text: root.jarvisFailures + " échec" + (root.jarvisFailures > 1 ? "s" : "")
              + " en attente · " + root.jarvisLessons + " leçon" + (root.jarvisLessons > 1 ? "s" : "") + " apprise" + (root.jarvisLessons > 1 ? "s" : "")
            color: root.dimColor
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Button {
              Layout.fillWidth: true
              text: "Rêver"
              fontSize: Style.font.caption
              foreground: Color.popups.text
              enabled: root.jarvisFailures > 0
              tooltipText: "Consolider les échecs en leçons"
              onClicked: root.jarvisDream()
            }

            Button {
              Layout.fillWidth: true
              text: "Nouvelle conversation"
              fontSize: Style.font.caption
              foreground: Color.popups.text
              onClicked: root.jarvisReset()
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Button {
              Layout.fillWidth: true
              text: "Journal des échecs"
              fontSize: Style.font.caption
              foreground: Color.popups.text
              onClicked: root.editMemory("FAILURES.md")
            }

            Button {
              Layout.fillWidth: true
              text: "Leçons"
              fontSize: Style.font.caption
              foreground: Color.popups.text
              onClicked: root.editMemory("LEARNED.md")
            }
          }
        }
      }
    }
  }
}
