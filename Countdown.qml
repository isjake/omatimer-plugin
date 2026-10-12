import QtQuick
import "Model.js" as Model

// One timer: its duration, where it is, and when it ends. The service keeps a
// list of these; a window or the bar popup draws one.
QtObject {
  id: root

  property int savedSeconds: 60      // the duration reset goes back to
  property int activeSeconds: 60     // what the display shows
  property int runSeconds: 60        // length of the current run, for progress
  property bool running: false
  property bool finished: false      // done, until the next start/reset/edit
  property real deadline: 0          // ms since epoch, while running
  property string schedule: idleSchedule
  property var window: null          // its TimerWindow, when one is open
  property int number: 1             // stable while it lives: "Omatimer 2"

  readonly property string idleSchedule: "--:--:--  ·  --:--:--"
  readonly property bool paused: !running && !finished && activeSeconds !== savedSeconds
  readonly property real progress: running || paused
    ? (runSeconds > 0 ? 1 - activeSeconds / runSeconds : 0)
    : (finished ? 1 : 0)
  readonly property string state: running ? "running" : (finished ? "done" : (paused ? "paused" : "idle"))

  signal changed()          // something worth saving
  signal done(bool announce) // ran out; announce is false when restored late

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
    changed()
  }

  function stop() {
    if (!running) return
    tick()
    if (!running) return // it was already up
    ticker.stop()
    running = false
    changed()
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
    changed()
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
    changed()
    return true
  }

  // Clears "done" once it has been seen.
  function acknowledge() {
    if (!finished) return
    finished = false
    activeSeconds = savedSeconds
    runSeconds = savedSeconds
    schedule = idleSchedule
    changed()
  }

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
    changed()
    done(announce)
  }

  function serialize() {
    return {
      savedSeconds: savedSeconds, activeSeconds: activeSeconds, runSeconds: runSeconds,
      running: running, finished: finished, deadline: deadline, schedule: schedule
    }
  }

  // Restores a saved timer. A running one carries on; one that ran out while
  // the shell was gone shows as done, quietly.
  function restore(s) {
    function num(v, fallback) { return typeof v === "number" && isFinite(v) ? v : fallback }
    s = s || {}
    savedSeconds = Math.max(1, num(s.savedSeconds, 60))
    activeSeconds = Math.max(0, num(s.activeSeconds, savedSeconds))
    runSeconds = Math.max(1, num(s.runSeconds, savedSeconds))
    finished = s.finished === true
    schedule = typeof s.schedule === "string" ? s.schedule : idleSchedule
    if (s.running === true && num(s.deadline, 0) > 0) {
      deadline = s.deadline
      running = true
      if (deadline <= Date.now()) finish(false)
      else tick()
    }
  }

  property Timer ticker: Timer {
    repeat: false
    onTriggered: root.tick()
  }
}
