pragma ComponentBehavior: Bound

// Control Center module — Affichage.
//
// Written against exactly the contract a third-party plugin gets: a plain
// Item that describes its home row and hands over a page Component. It
// reaches nothing inside the Control Center; `qs.Ui` and `qs.Commons` are
// all a module needs to compose a page.
//
// What lives here rather than on the home: the keyboard backlight (the ALS
// drives it most of the time), and the two settings whose state needs a
// sentence rather than a lit badge.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../components"

Item {
  id: mod

  // ------------------------------------------------------------- contract
  property var bar: null
  property var manifest: null
  property bool panelOpen: false
  property bool pageShowing: false
  // Set false by the shell while the finger is still moving.
  property bool pageSettled: true

  property string title: "Affichage"
  property string glyph: "󰃟"
  property bool hasToggle: false
  property bool active: false
  property bool alert: false

  readonly property string summary:
    mod.autoOn
      ? "Auto · " + (mod.lightMode ? "Clair" : "Sombre")
      : (mod.lightMode ? "Clair" : "Sombre") + " · luminosité " + mod.alsWord

  // ------------------------------------------------------------- state
  readonly property var nightlightService:
    bar && bar.shell ? bar.shell.serviceFor("omarchy.nightlight") : null
  readonly property bool nightlight: nightlightService ? nightlightService.enabled : false

  // "on" | "paused" | "off"
  property string alsState: "off"
  property string themeName: ""
  readonly property bool lightMode: themeName === "apple-glass-light"

  // ---- automatic appearance: "Auto" means the systemd timer is enabled,
  // read back from `omarchy-auto-appearance status`. Nothing else stores it.
  property bool autoOn: false
  property string autoMode: "solar"      // "solar" | "schedule"
  property string sunrise: ""
  property string sunset: ""
  property string autoFrom: ""
  property string autoUntil: ""
  property bool sunError: false
  property string latitude: ""
  property string longitude: ""
  property bool locating: false
  property bool locateFailed: false

  readonly property bool appleGlass:
    themeName === "apple-glass" || themeName === "apple-glass-light"
  readonly property string appearanceValue:
    autoOn ? "auto" : (lightMode ? "light" : "dark")

  function appearanceSentence() {
    if (!autoOn) return "L'apparence automatique est désactivée."
    if (!appleGlass) return "En attente : le thème actif n'est pas Apple Glass."
    if (autoMode === "schedule")
      return "Claire de " + autoFrom + " à " + autoUntil + ", sombre le reste du temps."
    if (sunError) return "Position inconnue — appuie sur Détecter."
    if (sunrise === "") return "Suit le soleil."
    return "Suit le soleil — lever " + sunrise + ", coucher " + sunset + "."
  }

  function positionSentence() {
    if (locateFailed) return "Détection impossible — hors ligne ?"
    if (latitude === "") return "Position inconnue"
    return "Position " + Number(latitude).toFixed(2) + ", " + Number(longitude).toFixed(2)
  }

  property int kbdBrightness: 0
  property int kbdMax: 1

  readonly property string alsWord:
    alsState === "on" ? "active" : (alsState === "paused" ? "en pause" : "éteinte")

  function alsSentence() {
    if (alsState === "on") return "Active — elle suit la lumière ambiante et apprend de tes corrections."
    if (alsState === "paused") return "En pause — le démon tourne mais ne corrige plus rien."
    return "Éteinte — le démon n'a pas démarré."
  }

  // The daemon has no `stop`: `toggle` pauses and resumes a running one,
  // `daemon` starts it. So the page offers exactly the transitions that
  // exist, and says so, rather than a switch that would lie in one position.
  function alsActionLabel() {
    if (alsState === "on") return "Mettre en pause"
    if (alsState === "paused") return "Reprendre"
    return "Démarrer"
  }

  function alsAct() {
    if (alsState === "off") {
      alsState = "on"
      Quickshell.execDetached(["omarchy-als", "daemon"])
    } else {
      alsState = alsState === "paused" ? "on" : "paused"
      Quickshell.execDetached(["omarchy-als", "toggle"])
    }
    recheck.restart()
  }

  // "auto" | "light" | "dark". Auto is the timer being enabled; an explicit
  // choice disables it first, like picking Light or Dark on macOS.
  function setAppearance(value) {
    if (value === "auto") {
      autoOn = true
      Quickshell.execDetached(["bash", "-c",
        "systemctl --user enable --now omarchy-auto-appearance.timer; exec omarchy-auto-appearance"])
    } else {
      autoOn = false
      themeName = value === "light" ? "apple-glass-light" : "apple-glass"
      Quickshell.execDetached(["bash", "-c",
        "systemctl --user disable --now omarchy-auto-appearance.timer; exec omarchy-theme-set " + themeName])
    }
    slowRecheck.restart()
  }

  function locate() {
    if (locating) return
    locating = true
    locateFailed = false
    locateProc.running = true
  }

  function toggleNightlight() {
    if (nightlightService) nightlightService.setNightlight(!nightlight)
  }

  function setKbdBrightness(frac) {
    var value = Math.max(0, Math.round(frac * kbdMax))
    kbdBrightness = value
    pendingKbd = value
    kbdWrite.restart()
  }

  // ------------------------------------------------------------- probes
  //
  // Only while this page is on screen. The Control Center polls its own copy
  // of what the home shows, and gates that on being on the home — so the two
  // never run at the same time.

  function refresh() {
    alsProc.running = true
    themeProc.running = true
    kbdProc.running = true
    autoProc.running = true
    locationProc.running = true
  }

  onPageShowingChanged: if (pageShowing) refresh()
  // The home row's summary needs the theme and the ALS state too, once.
  onPanelOpenChanged: if (panelOpen) { alsProc.running = true; themeProc.running = true; autoProc.running = true }

  Timer {
    id: recheck
    interval: 900
    onTriggered: mod.refresh()
  }

  Timer {
    id: slowRecheck
    interval: 4000
    onTriggered: mod.refresh()
  }

  Timer {
    interval: 2000
    repeat: true
    running: mod.pageShowing && mod.pageSettled
    onTriggered: kbdProc.running = true
  }

  Process {
    id: alsProc
    command: ["bash", "-c", "omarchy-als status 2>/dev/null | tail -1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text)
        if (line.indexOf("running") === -1) mod.alsState = "off"
        else mod.alsState = line.indexOf("paused") !== -1 ? "paused" : "on"
      }
    }
  }

  Process {
    id: themeProc
    command: ["cat", Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: mod.themeName = String(text).trim()
    }
  }

  Process {
    id: autoProc
    command: ["omarchy-auto-appearance", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fields = {}
        String(text).trim().split(/\s+/).forEach(function(pair) {
          var eq = pair.indexOf("=")
          if (eq > 0) fields[pair.slice(0, eq)] = pair.slice(eq + 1)
        })
        mod.autoOn = fields.enabled === "yes"
        mod.autoMode = fields.mode || "solar"
        mod.sunError = fields.error === "sun"
        mod.sunrise = fields.sunrise || ""
        mod.sunset = fields.sunset || ""
        mod.autoFrom = fields.from || ""
        mod.autoUntil = fields.until || ""
      }
    }
  }

  Process {
    id: locationProc
    command: ["jq", "-r", '"\\(.latitude) \\(.longitude)"',
      Quickshell.env("HOME") + "/.config/omarchy/dynamic-wallpaper.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        if (parts.length === 2 && isFinite(Number(parts[0])) && isFinite(Number(parts[1]))) {
          mod.latitude = parts[0]
          mod.longitude = parts[1]
        } else {
          mod.latitude = ""
          mod.longitude = ""
        }
      }
    }
  }

  Process {
    id: locateProc
    command: ["omarchy-locate"]
    onExited: function(exitCode) {
      mod.locating = false
      mod.locateFailed = exitCode !== 0
      // omarchy-locate re-applies the theme; give omarchy-theme-set time.
      mod.refresh()
      slowRecheck.restart()
    }
  }

  Process {
    id: kbdProc
    command: ["bash", "-c",
      'k=/sys/class/leds/kbd_backlight; echo "$(cat $k/brightness) $(cat $k/max_brightness)"']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        if (parts.length < 2) return
        var b = parseInt(parts[0], 10)
        var m = parseInt(parts[1], 10)
        if (isFinite(m) && m > 0) mod.kbdMax = m
        if (isFinite(b) && !mod.kbdDragging) mod.kbdBrightness = b
      }
    }
  }

  // Trailing-edge throttle, same shape as the panel backlight on the home:
  // the settled value is what omarchy-als confirms over two polls and learns.
  property bool kbdDragging: false
  property int pendingKbd: -1

  Timer {
    id: kbdWrite
    interval: 120
    onTriggered: if (mod.pendingKbd >= 0) {
      Quickshell.execDetached(["brightnessctl", "-q", "-d", "kbd_backlight", "set", String(mod.pendingKbd)])
      mod.pendingKbd = -1
    }
  }

  // ------------------------------------------------------------- page
  property Component page: Component {
    ColumnLayout {
      spacing: Style.space(14)

      PanelSectionHeader {
        text: "Rétroéclairage du clavier"
        foreground: Color.popups.text
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
          Layout.fillWidth: true
          bar: mod.bar
          value: mod.kbdMax > 0 ? mod.kbdBrightness / mod.kbdMax : 0
          onDraggingChanged: mod.kbdDragging = dragging
          onMoved: function(v) { mod.setKbdBrightness(v) }
        }

        Text {
          Layout.preferredWidth: Style.space(34)
          horizontalAlignment: Text.AlignRight
          text: Math.round(mod.kbdMax > 0 ? mod.kbdBrightness / mod.kbdMax * 100 : 0) + " %"
          color: Util.alpha(Color.popups.text, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      PanelSectionHeader {
        text: "Luminosité automatique"
        foreground: Color.popups.text
      }

      Text {
        Layout.fillWidth: true
        text: mod.alsSentence()
        color: Util.alpha(Color.popups.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Button {
        Layout.fillWidth: true
        text: mod.alsActionLabel()
        bordered: true
        fontSize: Style.font.caption
        foreground: Color.popups.text
        onClicked: mod.alsAct()
      }

      PanelSectionHeader {
        text: "Veilleuse"
        foreground: Color.popups.text
      }

      Toggle {
        Layout.fillWidth: true
        label: "Lumière chaude"
        description: mod.nightlight ? "Active" : "Éteinte"
        checked: mod.nightlight
        foreground: Color.popups.text
        onClicked: mod.toggleNightlight()
      }

      PanelSectionHeader {
        text: "Apparence"
        foreground: Color.popups.text
      }

      PillRow {
        Layout.fillWidth: true
        options: [
          { value: "dark", label: "Sombre" },
          { value: "light", label: "Claire" },
          { value: "auto", label: "Auto" }
        ]
        value: mod.appearanceValue
        foreground: Color.popups.text
        fontSize: Style.font.caption
        onChanged: function(v) { mod.setAppearance(v) }
      }

      Text {
        Layout.fillWidth: true
        text: mod.appearanceSentence()
        color: Util.alpha(Color.popups.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Text {
          Layout.fillWidth: true
          text: mod.positionSentence()
          color: Util.alpha(Color.popups.text, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Button {
          text: mod.locating ? "…" : "Détecter"
          enabled: !mod.locating
          bordered: true
          fontSize: Style.font.caption
          foreground: Color.popups.text
          onClicked: mod.locate()
        }
      }
    }
  }
}
