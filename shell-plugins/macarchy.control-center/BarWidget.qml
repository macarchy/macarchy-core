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
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import qs.Ui as Ui

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
  // What he does when he is asked to listen with the microphone muted. The
  // default hands over the keyboard: he cannot hear you, so the honest move
  // is the other way in — never the sprite and the « J'écoute… » over a node
  // nothing can pass through, which is what he did all of 2026-09-01.
  property string jarvisMuteMode: "ecrire"
  readonly property var jarvisMuteModes: [["ecrire", "Clavier"], ["prevenir", "Prévenir"], ["reactiver", "Réactiver"]]
  property int jarvisFailures: 0
  property int jarvisLessons: 0
  property int jarvisSuggestions: 0
  readonly property var jarvisTones: ["majordome", "complice", "laconique"]

  // The fish's look: five soul settings, one per part (sprites/parts.py).
  // Writes go through sed then `omarchy-jarvis look`, chained in one
  // shell so the regeneration always reads the new value; the fish on
  // the desktop is the preview.
  property string jarvisCorps: "B1"
  property string jarvisOeil: "E1"
  property string jarvisCriniere: "M1"
  property string jarvisQueue: "T1"
  property string jarvisCouleur: "or"
  readonly property var jarvisLookAxes: [
    ["corps", "Corps", [["B1", "Babel"], ["B2", "Rond"], ["B3", "Élancé"], ["B4", "Anguille"]]],
    ["oeil", "Œil", [["E1", "Grand"], ["E2", "Amande"], ["E3", "Rond"], ["E4", "Anneau"]]],
    ["criniere", "Crinière", [["M1", "Éventail"], ["M2", "Voile"], ["M3", "Mohawk"], ["M4", "Antennes"]]],
    ["queue", "Queue", [["T1", "Fourche"], ["T2", "Éventail"], ["T3", "Croissant"], ["T4", "Ruban"]]]
  ]
  readonly property var jarvisCouleurs: [
    ["or", "#F2C94C"], ["corail", "#F08A5D"], ["lagon", "#4CC9C0"], ["lavande", "#A78BFA"],
    ["menthe", "#7ED957"], ["perle", "#ECE7DC"], ["braise", "#FF6B6B"], ["encre", "#5C8DFF"]
  ]
  function jarvisLookValue(key) {
    return key === "corps" ? jarvisCorps : key === "oeil" ? jarvisOeil
      : key === "criniere" ? jarvisCriniere : key === "queue" ? jarvisQueue : jarvisCouleur
  }

  // Live status, from `omarchy-jarvis status` (key=value lines): what he
  // is doing, what his brain last said about itself, the last exchange,
  // and the automations' clock. Polled every few seconds while the Jarvis
  // page is showing.
  property string jarvisState: "idle"
  property string jarvisBrain: "ok"          // ok | quota <epoch> | blocked | down
  property bool jarvisQuiet: false
  property bool jarvisRondes: true
  property bool jarvisReves: true
  property string jarvisSilence: "23-7"      // "HH-HH" | "non"
  property int jarvisLastHeartbeat: 0
  property int jarvisNextHeartbeat: 0
  property string jarvisLastAsk: ""
  property string jarvisLastReply: ""
  // [{ n, date, text }] — the dream's proposals awaiting a decision.
  property var jarvisSuggestionList: []

  readonly property bool jarvisBrainOk: jarvisBrain === "ok"

  function jarvisClock(epoch) {
    var d = new Date(epoch * 1000)
    return d.getHours() + "h" + String(d.getMinutes()).padStart(2, "0")
  }

  function jarvisStateText() {
    switch (jarvisState) {
    case "listening": return "À l'écoute"
    case "transcribing": return "Transcrit"
    case "thinking": return "Réfléchit"
    case "speaking": return "Parle"
    case "followup": return "Attend une suite"
    case "sleeping": return "Rêve"
    // Milliseconds long in practice — the panel polls every few seconds and
    // will almost never catch it — but the label exists so an abort that
    // does wedge reads as an abort and not as a fish at rest.
    case "cancelling": return "Annule"
    default: return "Au repos"
    }
  }

  function jarvisBrainText() {
    if (jarvisBrain.indexOf("quota ") === 0)
      return "Quota atteint · retour " + jarvisClock(parseInt(jarvisBrain.slice(6), 10))
    if (jarvisBrain === "blocked") return "Ronde bloquée (approbation)"
    if (jarvisBrain === "down") return "Cerveau injoignable"
    return "Cerveau OK"
  }

  function jarvisSilenceText() {
    var m = /^(\d+)-(\d+)$/.exec(jarvisSilence)
    return m ? m[1] + "h–" + m[2] + "h" : "23h–7h"
  }

  // The rounds line: why they are not happening, or when the next one is.
  function jarvisRoundsText() {
    if (!jarvisRondes) return "Désactivées"
    if (jarvisBrain.indexOf("quota ") === 0) return "Suspendues jusqu'à " + jarvisClock(parseInt(jarvisBrain.slice(6), 10)) + " (quota)"
    if (jarvisQuiet) return "En pause (silence " + jarvisSilenceText() + ")"
    var last = jarvisLastHeartbeat > 0 ? "Dernière " + jarvisClock(jarvisLastHeartbeat) : "Aucune encore"
    var mins = Math.max(0, Math.round((jarvisNextHeartbeat - Date.now() / 1000) / 60))
    return last + " · prochaine dans ~" + mins + " min"
  }

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

  // Switching the ears off inside a follow-up window used to park him there:
  // the daemon is what closes that window, so killing it left the fish perked
  // up until the next press — and with it the whole body clock. `settle` is a
  // no-op from every other state, so it costs nothing to always send it.
  function toggleJarvisWake() {
    jarvisWake = !jarvisWake
    if (jarvisWake) Quickshell.execDetached(["omarchy-jarvis-wake"])
    else Quickshell.execDetached(["bash", "-c",
      'pkill -f "jarvis-wake[.]py"; omarchy-jarvis settle'])
    recheck.restart()
  }

  // Ces trois pastilles fixent la langue de la conversation entière : ce que
  // ses oreilles attendent (whisper est épinglé sur ce réglage) et la voix
  // qui répond. Jarvis les relit à chaque phrase, donc pas de `reset` ici —
  // presser « English » au milieu d'un échange change la voix de la réponse
  // suivante. Sous « Auto » il devine, une fois par réponse ; c'est
  // précisément ce que ces deux autres pastilles servent à éviter.
  function setJarvisLang(lang) {
    jarvisLang = lang
    Quickshell.execDetached(["bash", "-c",
      'sed -i "s/^- langue: .*/- langue: $1/" "$2"', "--",
      lang, soulPath])
  }

  // Read live by the pipeline on the next press — no `reset` needed, so it
  // goes through the generic setter like the automations do.
  function setJarvisMuteMode(mode) {
    jarvisMuteMode = mode
    setJarvisSetting("micro-coupe", mode)
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

  // The automations live in SOUL.md's « Réglages » like the tone does, but
  // they are read live by the FSM on every tick — no reset needed. An older
  // soul without the line gets it appended after `langue`.
  function setJarvisSetting(key, value) {
    Quickshell.execDetached(["bash", "-c",
      'grep -q "^- $1:" "$3" && sed -i "s/^- $1: .*/- $1: $2/" "$3" || sed -i "/^- langue:/a - $1: $2" "$3"', "--",
      key, value, soulPath])
    recheck.restart()
  }

  function toggleJarvisRondes() {
    jarvisRondes = !jarvisRondes
    setJarvisSetting("rondes", jarvisRondes ? "oui" : "non")
  }

  function toggleJarvisReves() {
    jarvisReves = !jarvisReves
    setJarvisSetting("reves", jarvisReves ? "oui" : "non")
  }

  function toggleJarvisSilence() {
    var on = jarvisSilence !== "non"
    jarvisSilence = on ? "non" : "23-7"
    setJarvisSetting("silence", jarvisSilence)
  }

  // A suggestion leaves the inbox either way: `accept` hands it to a
  // background mission in the jarvis repo, `reject` just journals it.
  // The written exchange for shared offices: one line to
  // `omarchy-jarvis ask --quiet` — same brain, same banner and bubble,
  // no speakers. Optimistically paint the ask; the 3s poll brings the
  // state ("Réfléchit") and then the reply into the banner above.
  function sendJarvisText(text) {
    var t = text.trim()
    if (t.length === 0) return
    jarvisLastAsk = t
    jarvisLastReply = ""
    Quickshell.execDetached(["omarchy-jarvis", "ask", "--quiet", t])
    recheck.restart()
  }

  function setJarvisLook(key, value) {
    if (key === "corps") jarvisCorps = value
    else if (key === "oeil") jarvisOeil = value
    else if (key === "criniere") jarvisCriniere = value
    else if (key === "queue") jarvisQueue = value
    else jarvisCouleur = value
    Quickshell.execDetached(["bash", "-c",
      'grep -q "^- $1:" "$3" && sed -i "s/^- $1: .*/- $1: $2/" "$3" || sed -i "/^- langue:/a - $1: $2" "$3"; omarchy-jarvis look', "--",
      key, value, soulPath])
  }

  function randomJarvisLook() {
    Quickshell.execDetached(["omarchy-jarvis", "look", "random"])
    recheck.restart()
  }

  function decideSuggestion(n, verdict) {
    jarvisSuggestionList = jarvisSuggestionList.filter(function(s) { return s.n !== n })
    Quickshell.execDetached(["omarchy-jarvis", "suggestion", String(n), verdict])
    slowRecheck.restart()
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
    // The SSID comes from the active connection, not `dev wifi`: the scan
    // list can block for seconds (the tiles sat on "Off" meanwhile) and
    // its active column reads "no" even for the joined network on this
    // driver. printf guarantees exactly four lines, connected or not.
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
      // Then the FSM's own report (key=value lines, counts included) and,
      // past a marker, the suggestions as tab-separated `n date text`.
      'omarchy-jarvis status 2>/dev/null\n' +
      'echo ---\n' +
      'omarchy-jarvis suggestions 2>/dev/null', "--",
      root.soulPath]
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

        var kv = {}
        var suggestions = []
        var i = 6
        for (; i < lines.length && lines[i] !== "---"; i++) {
          var eq = lines[i].indexOf("=")
          if (eq > 0) kv[lines[i].slice(0, eq)] = lines[i].slice(eq + 1)
        }
        for (i++; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length >= 3) suggestions.push({ n: parseInt(parts[0], 10), date: parts[1], text: parts.slice(2).join("\t") })
        }
        function num(k) { var v = parseInt(kv[k] || "", 10); return isFinite(v) ? v : 0 }
        root.jarvisState = kv.state || "idle"
        root.jarvisBrain = kv.brain || "ok"
        root.jarvisQuiet = kv.quiet === "oui"
        root.jarvisRondes = kv.rondes !== "non"
        root.jarvisReves = kv.reves !== "non"
        root.jarvisSilence = kv.silence || "23-7"
        root.jarvisMuteMode = kv.micro_coupe || "ecrire"
        root.jarvisCorps = kv.corps || "B1"
        root.jarvisOeil = kv.oeil || "E1"
        root.jarvisCriniere = kv.criniere || "M1"
        root.jarvisQueue = kv.queue || "T1"
        root.jarvisCouleur = kv.couleur || "or"
        root.jarvisLastHeartbeat = num("last_heartbeat")
        root.jarvisNextHeartbeat = num("next_heartbeat")
        root.jarvisLastAsk = kv.last_ask || ""
        root.jarvisLastReply = kv.last_reply || ""
        root.jarvisFailures = num("failures")
        root.jarvisLessons = num("lessons")
        root.jarvisSuggestions = num("suggestions")
        // A `var` assignment always signals, and the Repeater would then
        // rebuild every card on each poll — only swap when the inbox
        // actually changed.
        if (JSON.stringify(suggestions) !== JSON.stringify(root.jarvisSuggestionList))
          root.jarvisSuggestionList = suggestions
      }
    }
  }

  // The Jarvis page is live: his state changes by the second when he is
  // spoken to, and a round or a quota notice can land while it is open.
  Timer {
    interval: 3000
    repeat: true
    // Not while the page is being scrolled: a refresh can relayout the
    // column (a new last reply, a card gone) and yank the content.
    running: root.opened && root.page === "jarvis" && !jarvisFlick.moving && !root.jarvisScrolling
    onTriggered: jarvisProc.running = true
  }

  // Wheel-driven scrolling sets contentY directly, so Flickable.moving
  // never sees it; this flag covers that path for the poll above.
  property bool jarvisScrolling: false

  Timer {
    id: jarvisScrollIdle
    interval: 500
    repeat: false
    onTriggered: root.jarvisScrolling = false
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
            // A brain in trouble (quota, stall) takes over the state line
            // and the badge — that is the one thing worth seeing from here.
            stateText: !root.jarvisBrainOk ? root.jarvisBrainText()
              : root.jarvisTone.charAt(0).toUpperCase() + root.jarvisTone.slice(1)
                + (root.jarvisLessons > 0 ? " · " + root.jarvisLessons + " leçon" + (root.jarvisLessons > 1 ? "s" : "") : "")
            alert: !root.jarvisBrainOk
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

        // Taller than the pane on a busy day (status, automations, memory,
        // the suggestion inbox): it scrolls.
        Flickable {
          id: jarvisFlick
          visible: root.page === "jarvis"
          anchors.fill: parent
          contentWidth: width
          contentHeight: jarvisPage.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // Hyprland scales touchpad scrolling by 0.4 (input:touchpad:
          // scroll_factor) and Flickable applies pixelDelta 1:1, so a long
          // swipe moved the page a little. Drive contentY here instead, at
          // about finger speed on the touchpad and a sane step on a wheel.
          WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
              var dy = event.pixelDelta.y !== 0
                ? event.pixelDelta.y * 2.5
                : event.angleDelta.y / 120 * Style.space(80)
              var maxY = Math.max(0, jarvisFlick.contentHeight - jarvisFlick.height)
              jarvisFlick.contentY = Math.max(0, Math.min(maxY, jarvisFlick.contentY - dy))
              root.jarvisScrolling = true
              jarvisScrollIdle.restart()
            }
          }

          ColumnLayout {
            id: jarvisPage
            width: parent.width
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

            // Live status: what he is doing, how his brain is, the last
            // exchange. A brain in trouble turns the dot and its line urgent.
            Rectangle {
              Layout.fillWidth: true
              radius: Math.min(Style.cornerRadius, Style.space(10))
              color: Style.normalFill
              implicitHeight: statusCol.implicitHeight + Style.space(20)

              ColumnLayout {
                id: statusCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(4)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Rectangle {
                    Layout.preferredWidth: Style.space(8)
                    Layout.preferredHeight: Style.space(8)
                    radius: width / 2
                    color: root.jarvisBrainOk ? Color.accent : Color.urgent

                    Behavior on color { ColorAnimation { duration: 120 } }
                  }

                  Text {
                    text: root.jarvisStateText()
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    text: root.jarvisBrainText()
                    color: root.jarvisBrainOk ? root.dimColor : Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  Layout.fillWidth: true
                  visible: root.jarvisLastAsk.length > 0
                  text: "« " + root.jarvisLastAsk + " »"
                  color: root.dimColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  visible: root.jarvisLastReply.length > 0
                  text: "→ " + root.jarvisLastReply
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                }

                // Write to him when speaking is not an option (shared
                // office): Enter sends the line silently (`ask --quiet`).
                // The panel is WlrKeyboardFocus.OnDemand while open, so a
                // click in the field routes the keyboard here.
                Ui.TextField {
                  id: jarvisWriteField
                  Layout.fillWidth: true
                  Layout.topMargin: Style.space(4)
                  placeholderText: "Écris à Jarvis…"
                  foreground: Color.popups.text
                  font.pixelSize: Style.font.bodySmall
                  onAccepted: {
                    root.sendJarvisText(text)
                    clear()
                  }
                }
              }
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
                  // `active` paints the selected fill but keeps the label in
                  // the foreground color — `selected` recolors the text to
                  // the accent, accent-on-accent, unreadable on this glass.
                  active: root.jarvisTone === modelData
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
                  // Same readable-label fix as the tone pills above.
                  active: root.jarvisLang === modelData[0]
                  onClicked: root.setJarvisLang(modelData[0])
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(6)

              Text {
                text: "Micro coupé"
                color: root.dimColor
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.jarvisMuteModes

                delegate: Button {
                  required property var modelData
                  Layout.fillWidth: true
                  text: modelData[1]
                  fontSize: Style.font.caption
                  foreground: Color.popups.text
                  active: root.jarvisMuteMode === modelData[0]
                  onClicked: root.setJarvisMuteMode(modelData[0])
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

            // ------------------------------------------------ appearance
            PanelSectionHeader {
              text: "Apparence"
              foreground: Color.popups.text
            }

            Repeater {
              model: root.jarvisLookAxes

              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(6)

                Text {
                  Layout.preferredWidth: Style.space(52)
                  text: modelData[1]
                  color: root.dimColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: modelData[2]

                  delegate: Button {
                    required property var modelData
                    readonly property string axisKey: parent.modelData ? parent.modelData[0] : ""
                    Layout.fillWidth: true
                    text: modelData[1]
                    fontSize: Style.font.caption
                    foreground: Color.popups.text
                    active: root.jarvisLookValue(axisKey) === modelData[0]
                    onClicked: root.setJarvisLook(axisKey, modelData[0])
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(6)

              Text {
                Layout.preferredWidth: Style.space(52)
                text: "Couleur"
                color: root.dimColor
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.jarvisCouleurs

                delegate: Rectangle {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(22)
                  radius: Style.space(4)
                  color: modelData[1]
                  border.width: root.jarvisCouleur === modelData[0] ? 2 : 0
                  border.color: Color.popups.text

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setJarvisLook("couleur", parent.modelData[0])
                  }
                }
              }
            }

            Button {
              Layout.fillWidth: true
              text: "Au hasard"
              fontSize: Style.font.caption
              foreground: Color.popups.text
              onClicked: root.randomJarvisLook()
            }

            PanelSectionHeader {
              text: "Automatismes"
              foreground: Color.popups.text
            }

            Toggle {
              Layout.fillWidth: true
              label: "Rondes"
              description: root.jarvisRoundsText()
              checked: root.jarvisRondes
              foreground: Color.popups.text
              onClicked: root.toggleJarvisRondes()
            }

            Toggle {
              Layout.fillWidth: true
              label: "Rêves automatiques"
              description: root.jarvisReves ? "Consolide sa mémoire quand il s'ennuie" : "Seulement sur « Rêver »"
              checked: root.jarvisReves
              foreground: Color.popups.text
              onClicked: root.toggleJarvisReves()
            }

            Toggle {
              Layout.fillWidth: true
              label: "Silence " + root.jarvisSilenceText()
              description: root.jarvisQuiet ? "En cours — il ne parle que si on lui parle" : "Ni rondes, ni rêves, ni parole spontanée la nuit"
              checked: root.jarvisSilence !== "non"
              foreground: Color.popups.text
              onClicked: root.toggleJarvisSilence()
            }

            PanelSectionHeader {
              text: "Mémoire"
              foreground: Color.popups.text
            }

            Text {
              Layout.fillWidth: true
              text: root.jarvisFailures + " échec" + (root.jarvisFailures > 1 ? "s" : "")
                + " en attente · " + root.jarvisLessons + " leçon" + (root.jarvisLessons > 1 ? "s" : "") + " apprise" + (root.jarvisLessons > 1 ? "s" : "")
                + (root.jarvisSuggestions > 0
                    ? " · " + root.jarvisSuggestions + " suggestion" + (root.jarvisSuggestions > 1 ? "s" : "")
                    : "")
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
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

              Button {
                Layout.fillWidth: true
                text: "Boîte noire"
                fontSize: Style.font.caption
                foreground: Color.popups.text
                tooltipText: "Chaque commande exécutée aujourd'hui"
                // Local date, not toISOString (UTC would open yesterday's
                // trace until 2 a.m. in Brussels).
                onClicked: {
                  var d = new Date()
                  var day = d.getFullYear() + "-"
                    + String(d.getMonth() + 1).padStart(2, "0") + "-"
                    + String(d.getDate()).padStart(2, "0")
                  root.editMemory("trace/" + day + ".log")
                }
              }
            }

            // The inbox: what his dreams proposed and nobody has decided on.
            // « Confier » hands it to a background mission; « Rejeter »
            // drops it — both leave a journal line, nothing vanishes.
            PanelSectionHeader {
              visible: root.jarvisSuggestionList.length > 0
              text: "Suggestions"
              foreground: Color.popups.text
            }

            Repeater {
              model: root.jarvisSuggestionList

              delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                radius: Math.min(Style.cornerRadius, Style.space(10))
                color: Style.normalFill
                implicitHeight: suggestionCol.implicitHeight + Style.space(20)

                ColumnLayout {
                  id: suggestionCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(10)
                  spacing: Style.space(6)

                  Text {
                    text: modelData.date
                    color: root.dimColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    Layout.fillWidth: true
                    text: modelData.text
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Button {
                      Layout.fillWidth: true
                      text: "Confier"
                      fontSize: Style.font.caption
                      foreground: Color.popups.text
                      tooltipText: "Lancer une mission de fond qui l'applique"
                      onClicked: root.decideSuggestion(modelData.n, "accept")
                    }

                    Button {
                      Layout.fillWidth: true
                      text: "Rejeter"
                      fontSize: Style.font.caption
                      foreground: Color.popups.text
                      onClicked: root.decideSuggestion(modelData.n, "reject")
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
