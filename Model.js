.pragma library

// Pure helpers, kept out of the QML so they can be tested with plain node
// (tests/model.test.js).

// "90" -> 90, "1h 30m 10s" -> 5410, "1.5m" -> 90, "" or junk -> 0
function parseDuration(input) {
  var s = String(input === undefined || input === null ? "" : input).trim()
  if (s === "") return 0
  if (/^\d+$/.test(s)) return parseInt(s, 10)

  var unit = /(\d+(?:\.\d+)?)\s*([hms])/gi
  var total = 0
  var m
  while ((m = unit.exec(s)) !== null) {
    var value = parseFloat(m[1])
    var u = m[2].toLowerCase()
    if (u === "h") total += value * 3600
    else if (u === "m") total += value * 60
    else total += value
  }
  return Math.floor(total)
}

// 90 -> "1m30s", 3661 -> "1h1m1s", 45 -> "45s". Round-trips back through
// parseDuration, so the box stays editable in its own notation.
function formatDuration(seconds) {
  seconds = Math.max(0, Math.floor(seconds))
  if (seconds < 60) return seconds + "s"
  var h = Math.floor(seconds / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  var s = seconds % 60
  var out = ""
  if (h) out += h + "h"
  if (m) out += m + "m"
  if (s) out += s + "s"
  return out
}

// Ceiling: a timer reads 1s until the moment it is actually up.
function remainingSeconds(deadlineMs, nowMs) {
  var ms = deadlineMs - nowMs
  return ms > 0 ? Math.ceil(ms / 1000) : 0
}

// Wake exactly when the displayed figure is due to change, a hair past the
// boundary and never before it. A fixed 1000ms interval drifts off the second
// boundary, and the display then shows a figure twice or skips one.
function nextTickDelay(deadlineMs, nowMs) {
  var ms = deadlineMs - nowMs
  if (ms <= 0) return 0
  var delay = ms % 1000
  if (delay === 0) delay = 1000
  return delay + 4
}

function clockString(ms) {
  var d = new Date(ms)
  function two(n) { return n < 10 ? "0" + n : String(n) }
  return d.getHours() + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds())
}

// The freedesktop sounds most suited to a timer, listed first.
var timerFriendly = [
  "complete", "bell", "message", "message-new-instant", "alarm-clock-elapsed",
  "window-attention", "dialog-information", "service-login"
]

var builtinSounds = [
  { value: "builtin-chime", label: "chime", file: "chime.wav" },
  { value: "builtin-bell", label: "bell", file: "bell.wav" },
  { value: "builtin-click", label: "click", file: "click.wav" }
]

// Options for a sound picker: None, the built-ins, then whatever freedesktop
// sounds are installed (timer-friendly first). Speaker-test tones are left out.
function soundOptions(systemNames) {
  var names = (systemNames || []).filter(function(n) {
    return n !== "" && n.indexOf("audio-channel-") !== 0 && n !== "audio-test-signal"
  })
  var options = [{ value: "none", label: "None" }]
  builtinSounds.forEach(function(b) { options.push({ value: b.value, label: b.label + " (built in)" }) })
  timerFriendly.forEach(function(n) {
    if (names.indexOf(n) !== -1) options.push({ value: n, label: n.replace(/-/g, " ") })
  })
  names.slice().sort().forEach(function(n) {
    if (timerFriendly.indexOf(n) === -1) options.push({ value: n, label: n.replace(/-/g, " ") })
  })
  return options
}
