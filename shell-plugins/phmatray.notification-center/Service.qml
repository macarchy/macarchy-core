// Archiver service for the notification center.
//
// The built-in notification service keeps only the newest 10 entries in
// ~/.local/state/omarchy/notifications/history/ and trims the rest away.
// This service mirrors every history file into a larger archive under
// ~/.local/state/omarchy/notification-center/ — including copies of the
// images the entries reference, since those die with the built-in trim —
// before that trim can delete it. The panel (BarWidget.qml) binds to the
// parsed `entries` and routes every removal through here, so one serialized
// job queue owns all file traffic.
//
// Removals are remembered in a tombstone file: a deleted entry usually still
// exists in the built-in history dir (it holds the newest 10), and without
// the tombstone the next mirror pass would resurrect it.

import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

import "CenterLogic.js" as CenterLogic

Item {
  id: service

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string historyDir: home + "/.local/state/omarchy/notifications/history/"
  readonly property string liveImagesDir: home + "/.local/state/omarchy/notifications/images/"
  readonly property string rootDir: home + "/.local/state/omarchy/notification-center/"
  readonly property string archiveDir: rootDir + "archive/"
  readonly property string archiveImagesDir: rootDir + "images/"
  readonly property string tombstoneFile: rootDir + "deleted.list"
  readonly property int archiveLimit: 200

  // Parsed archive, newest-first. The panel binds to this.
  property var entries: []

  // ------------------------------------------------------------- job queue
  //
  // All file work (mirror passes, removals, clears) runs through one
  // serialized Process so a removal issued after a mirror pass can't race
  // it. A read of the archive only starts once the queue is empty, so it
  // always sees the state the queued work produced.

  property var jobQueue: []
  property bool readPending: false
  property bool mirrorQueued: false

  function enqueueJob(job) {
    jobQueue = jobQueue.concat([job])
    runNextJob()
  }

  function runNextJob() {
    if (jobProc.running) return
    if (jobQueue.length === 0) {
      if (readPending && !readProc.running) {
        readPending = false
        readProc.running = true
      }
      return
    }
    var job = jobQueue[0]
    jobQueue = jobQueue.slice(1)
    if (job.isMirror) mirrorQueued = false
    jobProc.command = job.command
    jobProc.running = true
  }

  Process {
    id: jobProc
    running: false
    onExited: service.runNextJob()
  }

  // ---------------------------------------------------------- mirror pass
  //
  // Idempotent: copies any history file (and its stem-named images) that the
  // archive doesn't already hold and the tombstones don't forbid, rewrites
  // the image paths inside the JSON to the archived copies, then trims the
  // archive to archiveLimit newest (file names sort numerically by their
  // leading millisecond timestamp) and keeps the tombstone list bounded.
  readonly property string mirrorScript:
    'hist="$1" imgs="$2" arch="$3" archimgs="$4" limit="$5" dead="$6"\n' +
    'mkdir -p "$arch" "$archimgs" || exit 0\n' +
    'touch "$dead"\n' +
    'shopt -s nullglob\n' +
    'for f in "$hist"/*.json; do\n' +
    '  name="${f##*/}"\n' +
    '  [[ -e "$arch/$name" ]] && continue\n' +
    '  grep -qxF "$name" "$dead" && continue\n' +
    '  stem="${name%.json}"\n' +
    '  for img in "$imgs/$stem"-*; do\n' +
    '    cp -n -- "$img" "$archimgs/${img##*/}" 2>/dev/null || true\n' +
    '  done\n' +
    '  sed "s|$imgs|$archimgs|g" -- "$f" > "$arch/$name" || rm -f -- "$arch/$name"\n' +
    'done\n' +
    'ls -1 "$arch" 2>/dev/null | sort -n | head -n -"$limit" | while IFS= read -r stale; do\n' +
    '  rm -f -- "$arch/$stale" "$archimgs/${stale%.json}"-*\n' +
    'done\n' +
    'tail -n 300 "$dead" > "$dead.tmp" 2>/dev/null && mv -f -- "$dead.tmp" "$dead"\n' +
    'exit 0'

  function scan() {
    readPending = true
    if (mirrorQueued) return
    mirrorQueued = true
    enqueueJob({
      isMirror: true,
      command: ["bash", "-c", mirrorScript, "--",
        historyDir, liveImagesDir, archiveDir, archiveImagesDir,
        String(archiveLimit), tombstoneFile]
    })
  }

  // ------------------------------------------------------------- removals
  //
  // Entries update optimistically so the panel reacts instantly; the queued
  // job makes it true on disk and the tombstone keeps it true across future
  // mirror passes.

  function removeEntries(stems) {
    if (!Array.isArray(stems) || stems.length === 0) return
    var drop = {}
    for (var i = 0; i < stems.length; i++) drop[String(stems[i])] = true
    var keep = []
    for (var j = 0; j < entries.length; j++) {
      if (!drop[entries[j].stem]) keep.push(entries[j])
    }
    entries = keep
    var command = ["bash", "-c",
      'arch="$1" imgs="$2" dead="$3"\n' +
      'shift 3\n' +
      'mkdir -p "$arch" "$imgs" "$(dirname "$dead")"\n' +
      'for stem in "$@"; do\n' +
      '  printf "%s\\n" "$stem.json" >> "$dead"\n' +
      '  rm -f -- "$arch/$stem.json" "$imgs/$stem"-*\n' +
      'done\n' +
      'exit 0', "--",
      archiveDir, archiveImagesDir, tombstoneFile]
    for (var k = 0; k < stems.length; k++) command.push(String(stems[k]))
    enqueueJob({ command: command })
  }

  // Clears the archive AND tombstones everything currently in the built-in
  // history dir, so the mirror doesn't immediately re-import the newest 10.
  function clearAll() {
    entries = []
    enqueueJob({ command: ["bash", "-c",
      'hist="$1" arch="$2" imgs="$3" dead="$4"\n' +
      'mkdir -p "$arch" "$imgs" "$(dirname "$dead")"\n' +
      'shopt -s nullglob\n' +
      'for f in "$arch"/*.json "$hist"/*.json; do\n' +
      '  printf "%s\\n" "${f##*/}" >> "$dead"\n' +
      'done\n' +
      'sort -u "$dead" 2>/dev/null | tail -n 300 > "$dead.tmp" && mv -f -- "$dead.tmp" "$dead"\n' +
      'rm -f -- "$arch"/*.json "$imgs"/*\n' +
      'exit 0', "--",
      historyDir, archiveDir, archiveImagesDir, tombstoneFile] })
  }

  // ------------------------------------------------------------- archive read

  Process {
    id: readProc
    running: false
    // awk 1 (not cat) so a torn file missing its trailing newline can't glue
    // itself onto the next file and take a valid entry down with it.
    command: ["bash", "-c", 'awk 1 "$1"/*.json 2>/dev/null || true', "--", service.archiveDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.entries = CenterLogic.parseEntries(text)
    }
    onExited: service.runNextJob()
  }

  // ------------------------------------------------------------- triggers
  //
  // The folder watch reacts to the built-in service archiving a toast or
  // recording a DND-silenced notification; the timer is a backstop for the
  // add+trim case where the file count doesn't change.

  FolderListModel {
    id: historyWatch
    folder: "file://" + service.historyDir
    nameFilters: ["*.json"]
    showDirs: false
    onCountChanged: scanDebounce.restart()
  }

  Timer {
    id: scanDebounce
    interval: 300
    repeat: false
    onTriggered: service.scan()
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: service.scan()
  }

  Component.onCompleted: scan()
}
