// Pure helpers for the notification center: parsing the archive, grouping
// entries per app, and humanizing timestamps. No QML dependencies, so the
// logic stays testable with node.

// The archive files use the built-in notification service's single-line JSON
// format; stem (timestamp-originalId) is the file identity every removal and
// dedupe keys off.
function parseEntries(raw) {
  var lines = String(raw || "").split("\n")
  var entries = []
  var seen = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var value
    try {
      value = JSON.parse(line)
    } catch (e) {
      // Torn write from a crash mid-copy — skip the line, keep the rest.
      continue
    }
    if (!value || typeof value !== "object") continue
    var app = String(value.app || "")
    // The built-in service's own user-action confirmations ("Theme changed",
    // "Screenshot saved") are feedback for something the user just did;
    // replaying them in the center is noise, macOS-style ephemerality.
    if (app === "omarchy-action") continue
    var timestamp = Number(value.timestamp || 0)
    var entry = {
      stem: String(timestamp) + "-" + String(value.originalId || value.id || 0),
      app: app,
      appIcon: String(value.appIcon || ""),
      summary: String(value.summary || ""),
      body: String(value.body || ""),
      image: String(value.image || ""),
      glyph: String(value.glyph || ""),
      execArgv: String(value.execArgv || ""),
      urgency: typeof value.urgency === "number" ? value.urgency : 1,
      timestamp: timestamp
    }
    if (seen[entry.stem]) continue
    seen[entry.stem] = true
    entries.push(entry)
  }
  entries.sort(function(a, b) { return b.timestamp - a.timestamp })
  return entries
}

// Group label shown as the section header. Bare-CLI senders never declare an
// identity, so they all fold into one "System" bucket.
function appLabel(app) {
  var name = String(app || "")
  if (!name || name === "notify-send") return "System"
  // Bare binary names arrive lowercase ("kitty"); present them like app names.
  if (name === name.toLowerCase() && name.indexOf(" ") < 0)
    return name.charAt(0).toUpperCase() + name.slice(1)
  return name
}

// Entries arrive newest-first, so groups come out ordered by each app's
// newest notification — the same order macOS stacks its groups in.
function groupEntries(entries) {
  var rows = Array.isArray(entries) ? entries : []
  var order = []
  var byLabel = {}
  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i]
    if (!entry) continue
    var label = appLabel(entry.app)
    var group = byLabel[label]
    if (!group) {
      group = { label: label, appIcon: "", glyph: "", items: [] }
      byLabel[label] = group
      order.push(group)
    }
    // The group header borrows the newest entry's identity marks.
    if (!group.appIcon && entry.appIcon) group.appIcon = entry.appIcon
    if (!group.glyph && entry.glyph) group.glyph = entry.glyph
    group.items.push(entry)
  }
  return order
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function timeAgo(timestamp, now) {
  var ts = Number(timestamp || 0)
  var ref = Number(now || 0)
  if (ts <= 0) return ""
  var minutes = Math.floor(Math.max(0, ref - ts) / 60000)
  if (minutes < 1) return "now"
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var then = new Date(ts)
  var refDate = new Date(ref)
  var startOfToday = new Date(refDate.getFullYear(), refDate.getMonth(), refDate.getDate()).getTime()
  if (ts >= startOfToday - 86400000) return "yesterday"
  return then.getDate() + " " + MONTHS[then.getMonth()]
}

// Structural validation of a persisted omarchy-exec-argv hint, mirroring the
// built-in service: fail closed on anything that isn't a plain argv vector.
function parseExecArgv(value) {
  var text = String(value || "")
  if (!text) return null
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed) || parsed.length === 0) return null
  for (var i = 0; i < parsed.length; i++) {
    if (typeof parsed[i] !== "string") return null
  }
  if (!parsed[0] || parsed[0].charAt(0) === "-") return null
  return parsed
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEntries: parseEntries,
    appLabel: appLabel,
    groupEntries: groupEntries,
    timeAgo: timeAgo,
    parseExecArgv: parseExecArgv
  }
}
