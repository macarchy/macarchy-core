pragma ComponentBehavior: Bound

// Control Center module — Système.
//
// The three switches whose state needs a sentence to be understood, plus the
// one number the home has no room for: what is left of the battery's design
// capacity after 337 cycles. Same contract as any third-party module.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: mod

  // ------------------------------------------------------------- contract
  property var bar: null
  property var manifest: null
  property bool panelOpen: false
  property bool pageShowing: false

  property string title: "Système"
  property string glyph: "󰒓"
  property bool hasToggle: false
  property bool active: false
  property bool alert: false

  readonly property string summary:
    (mod.batteryLimited ? "Plafond 80 %" : "Charge pleine")
    + " · aquarium " + (mod.aquariumOn ? "actif" : "éteint")

  // ------------------------------------------------------------- state
  readonly property var idleService:
    bar && bar.shell ? bar.shell.serviceFor("omarchy.idle") : null
  readonly property bool stayAwake: idleService ? idleService.stayAwake : false

  property bool batteryLimited: true
  property bool aquariumOn: false
  property int cycles: 0
  property int chargeFull: 0
  property int chargeDesign: 0

  readonly property int health:
    chargeDesign > 0 ? Math.round(chargeFull / chargeDesign * 100) : 0

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

  function toggleStayAwake() {
    // setIdleEnabled(true) re-enables idle, i.e. turns stay-awake OFF.
    if (idleService) idleService.setIdleEnabled(stayAwake)
  }

  // ------------------------------------------------------------- probes
  function refresh() { probe.running = true }

  onPageShowingChanged: if (pageShowing) refresh()
  onPanelOpenChanged: if (panelOpen) refresh()

  Timer {
    id: recheck
    interval: 900
    onTriggered: mod.refresh()
  }

  Process {
    id: probe
    command: ["bash", "-c",
      'b=/sys/class/power_supply/macsmc-battery\n' +
      'printf "%s\\n%s\\n%s\\n%s\\n" \\\n' +
      '  "$(cat $b/charge_control_end_threshold 2>/dev/null)" \\\n' +
      '  "$(cat $b/cycle_count 2>/dev/null)" \\\n' +
      '  "$(cat $b/charge_full 2>/dev/null)" \\\n' +
      '  "$(cat $b/charge_full_design 2>/dev/null)"\n' +
      'omarchy-aquarium-toggle status >/dev/null 2>&1 && echo on || echo off']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var l = String(text).split("\n")
        function num(i) { var v = parseInt((l[i] || "").trim(), 10); return isFinite(v) ? v : 0 }
        var end = num(0)
        if (end > 0) mod.batteryLimited = end <= 80
        mod.cycles = num(1)
        mod.chargeFull = num(2)
        mod.chargeDesign = num(3)
        mod.aquariumOn = (l[4] || "").trim() === "on"
      }
    }
  }

  // ------------------------------------------------------------- page
  property Component page: Component {
    ColumnLayout {
      spacing: Style.space(14)

      PanelSectionHeader {
        text: "Batterie"
        foreground: Color.popups.text
      }

      Toggle {
        Layout.fillWidth: true
        label: "Limiter la charge à 80 %"
        description: mod.batteryLimited
          ? "La charge s'arrête à 80 % — c'est ce qui use le moins la cellule."
          : "Charge jusqu'à 100 %."
        checked: mod.batteryLimited
        foreground: Color.popups.text
        onClicked: mod.toggleBatteryLimit()
      }

      Text {
        Layout.fillWidth: true
        visible: mod.health > 0
        text: "Santé " + mod.health + " % de la capacité d'origine · " + mod.cycles + " cycles"
        color: Util.alpha(Color.popups.text, 0.68)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSectionHeader {
        text: "Veille"
        foreground: Color.popups.text
      }

      Toggle {
        Layout.fillWidth: true
        label: "Rester éveillé"
        description: mod.stayAwake
          ? "L'écran ne s'éteindra pas et la session ne se verrouillera pas."
          : "Veille et verrouillage normaux."
        checked: mod.stayAwake
        foreground: Color.popups.text
        onClicked: mod.toggleStayAwake()
      }

      PanelSectionHeader {
        text: "Aquarium"
        foreground: Color.popups.text
      }

      Toggle {
        Layout.fillWidth: true
        label: "Fond d'écran animé"
        description: mod.aquariumOn
          ? "Le shader tourne sur la couche du fond d'écran."
          : "Fond d'écran fixe."
        checked: mod.aquariumOn
        foreground: Color.popups.text
        onClicked: mod.toggleAquarium()
      }
    }
  }
}
