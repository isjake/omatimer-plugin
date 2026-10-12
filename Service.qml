import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The timer itself. One instance for the whole shell, so every bar (one per
// monitor) shows the same countdown, and the IPC target has a single owner.
//
// State is saved to ~/.local/state/omatimer/plugin.json, including a running
// timer's deadline: plugin updates and shell restarts reload this file, and a
// timer should survive that rather than silently vanish.
Scope {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.isjake.omatimer"

  // ---- timer state -------------------------------------------------------

  property int savedSeconds: 60      // the duration reset goes back to
  property int activeSeconds: 60     // what the display shows
  property int runSeconds: 60        // length of the current run, for progress
  property bool running: false
  property bool finished: false      // done, until the next start/reset/edit
  property real deadline: 0          // ms since epoch, while running
  property string schedule: idleSchedule

  readonly property string idleSchedule: "--:--:--  ·  --:--:--"
  readonly property bool paused: !running && !finished && activeSeconds !== savedSeconds
  readonly property real progress: running || paused
    ? (runSeconds > 0 ? 1 - activeSeconds / runSeconds : 0)
    : (finished ? 1 : 0)

  // ---- sound settings ----------------------------------------------------

  property int volume: 20            // percent of the system volume
  property bool muted: false
  property string buttonSound: "builtin-click"
  property string doneSound: "builtin-chime"
  property var systemSounds: []      // installed freedesktop sound names
  readonly property var soundOptions: Model.soundOptions(systemSounds)
  readonly property string systemSoundDir: "/usr/share/sounds/freedesktop/stereo/"

  // ---- actions -----------------------------------------------------------

  // A fresh (or finished) timer picks up `text` when given; a paused one
  // carries on unless the text was edited to something else.
  function start(text) {
    var typed = Model.parseDuration(text)
    var fresh = finished || activeSeconds <= 0 || activeSeconds === savedSeconds
    var edited = typed > 0 && (fresh || typed !== activeSeconds)
    if (edited) {
      savedSeconds = typed
      activeSeconds = typed
    } else if (fresh) {
      activeSeconds = savedSeconds
    }
    if (activeSeconds <= 0) return

    var now = Date.now()
    if (fresh || edited) runSeconds = activeSeconds
    finished = false
    running = true
    deadline = now + activeSeconds * 1000
    schedule = Model.clockString(now) + "  ·  " + Model.clockString(deadline)
    scheduleTick()
    save()
  }

  function stop() {
    if (!running) return
    tick()
    if (!running) return // it was already up
    ticker.stop()
    running = false
    save()
  }

  function toggle(text) {
    if (running) stop()
    else start(text)
  }

  function reset() {
    ticker.stop()
    running = false
    finished = false
    activeSeconds = savedSeconds
    runSeconds = savedSeconds
    schedule = idleSchedule
    save()
  }

  // Sets the duration without starting, like typing it in and pressing R.
  function setDuration(text) {
    var seconds = Model.parseDuration(text)
    if (seconds <= 0) return false
    ticker.stop()
    running = false
    finished = false
    savedSeconds = seconds
    activeSeconds = seconds
    runSeconds = seconds
    schedule = idleSchedule
    save()
    return true
  }

  // Clears the bar's "done" once it has been seen in the popup.
  function acknowledge() {
    if (!finished) return
    finished = false
    activeSeconds = savedSeconds
    runSeconds = savedSeconds
    schedule = idleSchedule
    save()
  }

  function toggleMute() {
    muted = !muted
    save()
  }

  function setVolume(v) {
    volume = Math.max(0, Math.min(100, Math.round(v)))
    save()
  }

  function setSound(key, name) {
    if (key === "buttonSound") buttonSound = name
    else if (key === "doneSound") doneSound = name
    else return
    save()
    play(name, true)
  }

  // ---- ticking -----------------------------------------------------------

  function scheduleTick() {
    var delay = Model.nextTickDelay(deadline, Date.now())
    if (delay <= 0) { tick(); return }
    ticker.interval = delay
    ticker.restart()
  }

  // Counted against a wall-clock deadline, so a slow tick (or a suspended
  // laptop) can't drift.
  function tick() {
    if (!running) return
    activeSeconds = Model.remainingSeconds(deadline, Date.now())
    if (activeSeconds > 0) { scheduleTick(); return }
    finish(true)
  }

  function finish(announce) {
    ticker.stop()
    running = false
    finished = true
    activeSeconds = 0
    schedule = "done  ·  " + Model.formatDuration(savedSeconds)
    save()
    if (!announce) return
    play(doneSound, false)
    // omarchy-glyph: Omarchy's notifications draw this in place of an icon.
    Quickshell.execDetached(["notify-send", "-a", "Omatimer", "-h", "string:omarchy-glyph:\u{F051B}",
      "Timer done", Model.formatDuration(savedSeconds) + " is up"])
  }

  Timer {
    id: ticker
    repeat: false
    onTriggered: root.tick()
  }

  // ---- sound -------------------------------------------------------------

  function soundPath(name) {
    if (!name || name === "none") return ""
    for (var i = 0; i < Model.builtinSounds.length; i++) {
      var b = Model.builtinSounds[i]
      if (b.value === name) return decodeURIComponent(Qt.resolvedUrl("sounds/" + b.file).toString().replace(/^file:\/\//, ""))
    }
    return systemSounds.indexOf(name) !== -1 ? systemSoundDir + name + ".oga" : ""
  }

  // Handed to PipeWire and forgotten; the volume is the stream's own, so it
  // scales whatever the system is set to. A preview cuts off the previous one
  // so scrolling through the list doesn't stack sounds up.
  function play(name, preview) {
    var path = soundPath(name)
    if (muted || volume <= 0 || path === "") return
    var cmd = ["sh", "-c",
      "if command -v pw-play >/dev/null; then exec pw-play --volume \"$1\" \"$3\"; " +
      "else exec paplay --volume=\"$2\" \"$3\"; fi",
      "omatimer-sound", String(volume / 100), String(Math.round(volume * 65536 / 100)), path]
    if (preview) {
      previewPlayer.running = false
      previewPlayer.command = cmd
      previewPlayer.running = true
    } else {
      Quickshell.execDetached(cmd)
    }
  }

  function clickSound() { play(buttonSound, false) }

  Process { id: previewPlayer }

  Process {
    id: soundScan
    command: ["sh", "-c", "ls \"$1\" 2>/dev/null", "sh", root.systemSoundDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.systemSounds = text.split("\n")
          .filter(function(f) { return /\.oga$/.test(f) })
          .map(function(f) { return f.replace(/\.oga$/, "") })
      }
    }
  }

  // ---- persistence -------------------------------------------------------

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omatimer"
  property bool restored: false

  function save() {
    if (!restored) return
    store.setText(JSON.stringify({
      savedSeconds: savedSeconds,
      activeSeconds: activeSeconds,
      runSeconds: runSeconds,
      running: running,
      finished: finished,
      deadline: deadline,
      schedule: schedule,
      volume: volume,
      muted: muted,
      buttonSound: buttonSound,
      doneSound: doneSound
    }, null, 2) + "\n")
  }

  function restore(raw) {
    var s = {}
    try { s = raw ? JSON.parse(raw) : {} } catch (e) { s = {} }
    function num(v, fallback) { return typeof v === "number" && isFinite(v) ? v : fallback }

    savedSeconds = Math.max(1, num(s.savedSeconds, 60))
    activeSeconds = Math.max(0, num(s.activeSeconds, savedSeconds))
    runSeconds = Math.max(1, num(s.runSeconds, savedSeconds))
    volume = Math.max(0, Math.min(100, num(s.volume, 20)))
    muted = s.muted === true
    if (typeof s.buttonSound === "string") buttonSound = s.buttonSound
    if (typeof s.doneSound === "string") doneSound = s.doneSound
    finished = s.finished === true
    schedule = typeof s.schedule === "string" ? s.schedule : idleSchedule
    restored = true

    if (s.running === true && num(s.deadline, 0) > 0) {
      deadline = s.deadline
      running = true
      // Ran out while the shell was gone: show it as done, quietly.
      if (deadline <= Date.now()) finish(false)
      else tick()
    }
  }

  FileView {
    id: store
    path: root.stateDir + "/plugin.json"
    printErrors: false
    atomicWrites: true
    onLoaded: if (!root.restored) root.restore(text())
    onLoadFailed: if (!root.restored) root.restore("")
  }

  Process {
    id: mkdir
    command: ["mkdir", "-p", root.stateDir]
  }

  Component.onCompleted: {
    mkdir.running = true
    soundScan.running = true
  }

  // ---- IPC ---------------------------------------------------------------
  //
  //   omarchy-shell omatimer start 25m     (start, optionally with a duration)
  //   omarchy-shell omatimer toggle | stop | reset | mute
  //   omarchy-shell omatimer set 1h30m     (set without starting)
  //   omarchy-shell omatimer open | close | status
  IpcHandler {
    target: "omatimer"

    function start(duration: string): void {
      if (duration !== "" && !root.setDuration(duration)) return
      root.start("")
    }
    function toggle(): void { root.toggle("") }
    function stop(): void { root.stop() }
    function reset(): void { root.reset() }
    function set(duration: string): void { root.setDuration(duration) }
    function mute(): void { root.toggleMute() }
    function open(): void { if (root.shell) root.shell.summon(root.pluginId, "{}") }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function status(): string {
      var state = root.running ? "running" : (root.finished ? "done" : (root.paused ? "paused" : "idle"))
      return state + " " + Model.formatDuration(root.activeSeconds)
    }
  }
}
