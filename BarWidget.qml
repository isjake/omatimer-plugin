import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar button. Optional in windows mode, where it shows one timer (the
// one ending soonest, unless you've cycled to another) and a counter, 2/3,
// that cycles through them. In bar mode it also hosts the popup.
//
// Left click opens (that timer's window, or the popup), right click starts or
// stops it, middle click resets it, scrolling cycles.
Panel {
  id: root
  manageIpc: false // the service owns the "omatimer" IPC target

  // ---- the service -------------------------------------------------------
  //
  // Looked up rather than injected, and looked up again on a timer: the
  // service can load after this widget, and a plugin update replaces it.
  property var service: null

  function resolveService() {
    var shell = bar ? bar.shell : null
    var found = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(moduleName) : null
    if (found !== service) service = found
  }

  onBarChanged: resolveService()
  onModuleNameChanged: resolveService()
  Component.onCompleted: resolveService()

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.resolveService()
  }

  readonly property bool barMode: service ? service.mode === "bar" : false
  readonly property var shown: !service ? null : (barMode ? service.primary : service.shownTimer)
  readonly property int timerCount: service ? service.timers.length : 0
  readonly property int shownIndex: service && shown ? service.timers.indexOf(shown) : -1
  readonly property bool showCounter: !barMode && !vertical && timerCount > 1
  readonly property bool running: shown ? shown.running : false
  readonly property bool paused: shown ? shown.paused : false
  readonly property bool finished: shown ? shown.finished : false

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color ink: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  readonly property string iconTimer: "\u{F051B}"   // nf-md-timer
  readonly property string iconPaused: "\u{F03E4}"  // nf-md-pause

  property bool showSettings: false

  onOpenedChanged: {
    if (opened) {
      if (!barMode && service) {
        // Summoned while timers live in windows: show those instead.
        close()
        service.newTimer("", false)
        return
      }
      face.focusInput()
    } else if (shown && barMode) {
      // Seen it: the bar can stop saying "done".
      shown.acknowledge()
    }
  }

  // ---- bar button --------------------------------------------------------

  readonly property string barLabel: {
    var icon = paused ? iconPaused : iconTimer
    if (vertical || !shown) return icon
    if (finished) return icon + " done"
    if (running || paused) return icon + " " + Model.formatDuration(shown.activeSeconds)
    // With several, an idle one says which it is.
    if (showCounter) return icon + " " + Model.formatDuration(shown.savedSeconds)
    return icon
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth

  implicitWidth: buttons.implicitWidth
  implicitHeight: button.implicitHeight

  function cycle(delta) {
    if (root.service && !root.barMode) root.service.cycle(delta)
  }

  Row {
    id: buttons
    anchors.fill: parent

    WidgetButton {
      id: button
      height: parent.height
      bar: root.bar
      text: root.barLabel
      active: root.finished
      dimmed: root.paused
      horizontalMargin: root.showCounter ? 5 : 8.75
      verticalPadding: 8.75
      tooltipText: root.opened ? ""
        : (root.running ? "Right click to stop, left click to open"
          : (root.paused ? "Right click to resume, left click to open"
            : "Right click to start, left click to open"))

      onPressed: function(b) {
        var s = root.service
        if (!s) return
        if (b === Qt.RightButton) {
          s.clickSound()
          if (root.shown) root.shown.toggle("")
          else s.newTimer("", true)
        } else if (b === Qt.MiddleButton) {
          if (!root.shown) return
          s.clickSound()
          root.shown.reset()
        } else if (root.barMode) {
          root.toggle()
        } else if (root.shown) {
          s.focusTimer(root.shown)
        } else {
          s.newTimer("", false)
        }
      }
      onWheelMoved: function(delta) { root.cycle(delta > 0 ? -1 : 1) }
    }

    // 2/3: which timer the bar is showing. Click for the next one.
    WidgetButton {
      id: counter
      visible: root.showCounter
      height: parent.height
      bar: root.bar
      text: (root.shownIndex + 1) + "/" + root.timerCount
      fontSize: Style.font.bodySmall
      dimmed: true
      horizontalMargin: 5
      verticalPadding: 8.75
      tooltipText: "Next timer (right click: previous, or scroll)"
      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycle(-1)
        else if (b === Qt.LeftButton) root.cycle(1)
      }
      onWheelMoved: function(delta) { root.cycle(delta > 0 ? -1 : 1) }
    }
  }

  // ---- popup (bar mode) --------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.barMode
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      TimerFace {
        id: face
        width: parent.width
        height: Math.round(width * 0.66)
        service: root.service
        countdown: root.barMode ? root.shown : null
        ink: root.ink
        family: root.family
        onHelpRequested: root.showSettings = !root.showSettings
        onEscapePressed: root.close()
      }

      PanelSeparator {
        visible: root.showSettings
        foreground: root.ink
        width: parent.width
      }

      SettingsContent {
        visible: root.showSettings
        width: parent.width
        service: root.service
        ink: root.ink
        family: root.family
      }
    }
  }
}
