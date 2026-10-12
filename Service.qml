import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The plugin's always-on half: every timer, the settings they share, the
// windows, sound, and the "omatimer" IPC target. One instance for the whole
// shell, so a bar on every monitor shows the same timers.
//
// How timers open is the `mode` setting:
//   windows  multiple timers, a window each, like the app (the default)
//   bar      one timer, in a popup from the bar widget
//
// State is saved to ~/.local/state/omatimer/plugin.json, running deadlines
// included: plugin updates and shell restarts reload this file, and timers
// (and their windows) should come back rather than silently vanish.
Scope {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.isjake.omatimer"

  // ---- settings ----------------------------------------------------------

  property string mode: "windows"
  property int lastSeconds: 60       // a new timer opens with the last duration used
  property int volume: 20            // percent of the system volume
  property bool muted: false
  property string buttonSound: "builtin-click"
  property string doneSound: "builtin-chime"
  property var systemSounds: []      // installed freedesktop sound names
  readonly property var soundOptions: Model.soundOptions(systemSounds)
  readonly property string systemSoundDir: "/usr/share/sounds/freedesktop/stereo/"

  // ---- timers ------------------------------------------------------------

  property var timers: []
  readonly property var primary: timers.length > 0 ? timers[0] : null

  // The one the bar shows: the running timer that ends soonest, else a
  // finished one, else a paused one.
  readonly property var featured: {
    var best = null
    for (var i = 0; i < timers.length; i++) {
      var t = timers[i]
      if (t.running && (!best || t.deadline < best.deadline)) best = t
    }
    if (best) return best
    for (i = 0; i < timers.length; i++) if (timers[i].finished) return timers[i]
    for (i = 0; i < timers.length; i++) if (timers[i].paused) return timers[i]
    return null
  }
  // The one the bar is pointed at: picked by cycling through them from the
  // bar, else the featured one.
  property var selected: null
  readonly property var shownTimer: selected && timers.indexOf(selected) !== -1
    ? selected : (featured || primary)

  function cycle(delta) {
    if (timers.length === 0) return
    var i = timers.indexOf(shownTimer)
    selected = timers[((i < 0 ? 0 : i) + delta + timers.length) % timers.length]
  }

  readonly property int runningCount: {
    var n = 0
    for (var i = 0; i < timers.length; i++) if (timers[i].running) n++
    return n
  }

  Component { id: countdownComponent; Countdown {} }
  Component { id: windowComponent; TimerWindow {} }
  Component { id: settingsComponent; SettingsWindow {} }

  function createCountdown(saved) {
    var c = countdownComponent.createObject(root)
    // The lowest number not in use, so titles stay short: Omatimer, Omatimer 2.
    var n = 1
    while (timers.some(function(t) { return t.number === n })) n++
    c.number = n
    if (saved) c.restore(saved)
    else c.setDuration(String(lastSeconds))
    c.changed.connect(function() {
      if (c.running) root.lastSeconds = c.savedSeconds
      root.save()
    })
    c.done.connect(function(announce) { if (announce) root.announce(c) })
    timers = timers.concat([c])
    return c
  }

  function ensurePrimary() {
    return primary || createCountdown(null)
  }

  function removeTimer(c) {
    var i = timers.indexOf(c)
    if (i === -1) return
    var next = timers.slice()
    next.splice(i, 1)
    timers = next
    if (selected === c) selected = null
    if (c.window) c.window.closeFromService()
    c.window = null
    c.ticker.stop()
    c.destroy()
    save()
  }

  // A new timer the way the app's launcher made one: in windows mode a new
  // window, in bar mode the one timer, shown.
  function newTimer(text, start) {
    var c
    if (mode === "windows") {
      c = createCountdown(null)
    } else {
      c = ensurePrimary()
      if (c.running && text === "") { show(c); return c }
    }
    if (text !== "") c.setDuration(text)
    if (start) c.start("")
    show(c)
    save()
    return c
  }

  function show(c) {
    if (mode === "bar") {
      if (shell) shell.summon(pluginId, "{}")
      return
    }
    if (!c.window) {
      var w = windowComponent.createObject(root, { service: root, countdown: c })
      c.window = w
      w.userClosed.connect(function() { root.windowClosed(c, w) })
      w.visible = true
      save()
    } else {
      c.window.visible = true
    }
  }

  // Super+W on a timer window. The window is the timer, so the timer goes
  // with it, as closing the app did.
  function windowClosed(c, w) {
    if (c.window !== w) return
    c.window = null
    Qt.callLater(function() { w.destroy() })
    removeTimer(c)
  }

  function setMode(m) {
    if (["windows", "bar"].indexOf(m) === -1 || m === mode) return
    mode = m
    if (m === "bar") {
      // One timer from here on: the featured one, else the first.
      var keep = featured || primary
      timers.slice().forEach(function(t) { if (t !== keep) root.removeTimer(t) })
      timers.forEach(function(t) {
        if (t.window) { t.window.closeFromService(); t.window = null }
      })
      ensurePrimary()
      if (settingsWindow) settingsWindow.closeFromService()
      settingsWindow = null
    } else {
      show(ensurePrimary())
    }
    save()
  }

  // For the bar widget and IPC: the timer an unqualified start/stop means.
  function target() {
    return shownTimer || ensurePrimary()
  }

  // Brings a timer's window forward, from any workspace. Found by its title,
  // which carries the timer's number.
  function focusTimer(c) {
    if (!c) return
    if (mode === "bar") { show(c); return }
    if (!c.window) { show(c); return }
    Quickshell.execDetached(["sh", "-c",
      'a=$(hyprctl clients -j | jq -r --arg t "$1" \'.[]|select(.title==$t)|.address\' | head -n1); ' +
      '[ -n "$a" ] && hyprctl dispatch "hl.dsp.focus({ window = \\"address:$a\\" })" >/dev/null',
      "sh", c.window.title])
  }

  // ---- shared actions ----------------------------------------------------

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

  property var settingsWindow: null

  function toggleSettingsWindow() {
    if (mode === "bar") {
      if (shell) shell.summon(pluginId, "{}")
      return
    }
    // Built fresh each time: a window the compositor has closed doesn't map
    // again when it's made visible.
    if (settingsWindow) {
      settingsWindow.closeFromService()
      settingsWindow = null
      return
    }
    var w = settingsComponent.createObject(root, { service: root })
    w.userClosed.connect(function() {
      if (root.settingsWindow === w) root.settingsWindow = null
      Qt.callLater(function() { w.destroy() })
    })
    settingsWindow = w
    w.visible = true
  }

  function announce(c) {
    play(doneSound, false)
    // omarchy-glyph: Omarchy's notifications draw this in place of an icon.
    Quickshell.execDetached(["notify-send", "-a", "Omatimer", "-h", "string:omarchy-glyph:\u{F051B}",
      "Timer done", Model.formatDuration(c.savedSeconds) + " is up"])
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

  // Batched: a tick, a click and a sound change in one frame write once.
  function save() {
    if (restored) Qt.callLater(writeState)
  }

  function writeState() {
    store.setText(JSON.stringify({
      version: 2,
      mode: mode,
      lastSeconds: lastSeconds,
      volume: volume,
      muted: muted,
      buttonSound: buttonSound,
      doneSound: doneSound,
      timers: timers.map(function(t) {
        var s = t.serialize()
        s.open = !!t.window
        return s
      })
    }, null, 2) + "\n")
  }

  function restore(raw) {
    var s = {}
    try { s = raw ? JSON.parse(raw) : {} } catch (e) { s = {} }
    function num(v, fallback) { return typeof v === "number" && isFinite(v) ? v : fallback }

    // 1.1 betas had a one-window mode; it opens as windows now.
    if (s.mode === "bar") mode = "bar"
    volume = Math.max(0, Math.min(100, num(s.volume, 20)))
    muted = s.muted === true
    if (typeof s.buttonSound === "string") buttonSound = s.buttonSound
    if (typeof s.doneSound === "string") doneSound = s.doneSound

    // 1.0 kept a single timer at the top level.
    var saved = Array.isArray(s.timers) ? s.timers
      : (typeof s.savedSeconds === "number" ? [s] : [])
    lastSeconds = Math.max(1, num(s.lastSeconds, saved.length ? num(saved[0].savedSeconds, 60) : 60))
    if (mode === "bar") saved = saved.slice(0, 1)

    restored = true
    saved.forEach(function(t) {
      // In windows mode a timer without a window has nothing to show it, so
      // only the ones that had a window come back. 1.0 timers had none.
      if (root.mode === "windows" && t.open !== true) return
      var c = root.createCountdown(t)
      if (root.mode === "windows") root.show(c)
    })
    if (mode === "bar") ensurePrimary()
    save()
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
    installLauncher()
  }

  // ---- launcher entry ----------------------------------------------------
  //
  // So SUPER+SPACE finds "Omatimer". Omarchy has no manifest field for this,
  // so the plugin writes the entry itself on enable and removes it on disable
  // (the approach OmaSettings takes). Only a file carrying the marker is ever
  // written or deleted, and a symlink at the path is left alone.

  readonly property string desktopDest: Quickshell.env("HOME") + "/.local/share/applications/" + pluginId + ".desktop"
  readonly property string desktopMarker: "^X-Omatimer-Plugin-Managed=true$"

  // $1 template, $2 destination, $3 marker, $4 icon
  readonly property string installScript:
      '[ -f "$1" ] || exit 0\n'
    + '[ -L "$2" ] && exit 0\n'
    + 'if [ -e "$2" ] && ! grep -q "$3" "$2"; then exit 0; fi\n'
    + 'mkdir -p "${2%/*}" || exit 0\n'
    + 'tmp=$(mktemp "$2.XXXXXX") || exit 0\n'
    + 'sed "s|@ICON@|$4|" "$1" >"$tmp" || { rm -f "$tmp"; exit 0; }\n'
    + 'chmod 644 "$tmp"\n'
    + 'if cmp -s "$tmp" "$2"; then rm -f "$tmp"; else mv -f "$tmp" "$2"; fi\n'

  readonly property string removeScript:
      '[ -L "$1" ] && exit 0\n'
    + 'grep -q "$2" "$1" 2>/dev/null && rm -f "$1"\n'

  property bool launcherInstalled: false

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))

  function installLauncher() {
    if (launcherInstalled) return
    var dir = pluginDir
    launcherInstalled = true
    Quickshell.execDetached(["sh", "-c", installScript, "sh",
                             dir + "/omatimer.desktop", desktopDest, desktopMarker, dir + "/icon.svg"])
  }

  // Reached on disable and on remove alike (remove disables first). A reload
  // also lands here, and the new instance writes the entry straight back.
  Component.onDestruction: {
    if (launcherInstalled)
      Quickshell.execDetached(["sh", "-c", removeScript, "sh", desktopDest, desktopMarker])
  }

  // ---- IPC ---------------------------------------------------------------
  //
  //   omarchy-shell omatimer open           a new timer (window, or the popup)
  //   omarchy-shell omatimer start 25m      a new timer, started ("" = the current one)
  //   omarchy-shell omatimer set 1h30m      a new timer, not started
  //   omarchy-shell omatimer toggle | stop | reset   the timer the bar shows
  //   omarchy-shell omatimer next | previous | focus   cycle the bar, or go to its timer
  //   omarchy-shell omatimer mute | settings | status
  //   omarchy-shell omatimer mode windows|bar
  IpcHandler {
    target: "omatimer"

    function open(): void { root.newTimer("", false) }
    function start(duration: string): void {
      if (duration === "") { root.target().start(""); return }
      if (Model.parseDuration(duration) > 0) root.newTimer(duration, true)
    }
    function set(duration: string): void {
      if (Model.parseDuration(duration) > 0) root.newTimer(duration, false)
    }
    function toggle(): void { root.target().toggle("") }
    function stop(): void { root.target().stop() }
    function reset(): void { root.target().reset() }
    function next(): void { root.cycle(1) }
    function previous(): void { root.cycle(-1) }
    function focus(): void { root.focusTimer(root.shownTimer) }
    function mute(): void { root.toggleMute() }
    function settings(): void { root.toggleSettingsWindow() }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function mode(name: string): void { root.setMode(name) }
    function status(): string {
      if (root.timers.length === 0) return "none"
      return root.timers.map(function(t) {
        return t.state + " " + Model.formatDuration(t.finished ? t.savedSeconds : t.activeSeconds)
      }).join("\n")
    }
  }
}
