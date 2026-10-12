import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar button and its popup. The countdown itself lives in Service.qml, so
// a bar on every monitor shows the same timer; this file only draws it.
//
// Bar: left click opens the popup, right click starts or stops, middle click
// resets. In the popup the duration box keeps the focus, the same as the app:
// Enter/Space start or stop, R resets, Ctrl+M mutes, ?/F1 shows the settings.
Panel {
  id: root
  manageIpc: false // the service owns the "omatimer" IPC target

  // ---- the service -------------------------------------------------------
  //
  // Looked up rather than injected, and looked up again on a timer: the
  // service can load after this widget, and a plugin update replaces it.
  property var timer: null

  function resolveTimer() {
    var shell = bar ? bar.shell : null
    var found = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(moduleName) : null
    if (found !== timer) timer = found
  }

  onBarChanged: resolveTimer()
  onModuleNameChanged: resolveTimer()
  Component.onCompleted: resolveTimer()

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.resolveTimer()
  }

  readonly property bool running: timer ? timer.running : false
  readonly property bool paused: timer ? timer.paused : false
  readonly property bool finished: timer ? timer.finished : false
  readonly property bool muted: timer ? timer.muted : false
  readonly property string displayValue: !timer ? "60s"
    : Model.formatDuration(finished ? timer.savedSeconds : timer.activeSeconds)

  readonly property string iconTimer: "\u{F051B}"   // nf-md-timer
  readonly property string iconPaused: "\u{F03E4}"  // nf-md-pause
  readonly property string iconPlay: "\u{F040A}"    // nf-md-play
  readonly property string iconReset: "\u{F0450}"   // nf-md-refresh
  readonly property string iconSound: "\u{F057E}"   // nf-md-volume_high
  readonly property string iconMuted: "\u{F075F}"   // nf-md-volume_off
  readonly property string iconHelp: "\u{F02D7}"    // nf-md-help_circle

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color ink: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // ---- actions -----------------------------------------------------------

  property bool showSettings: false
  property bool dirty: false // the box holds something typed, not the timer's value

  function syncInput(force) {
    if (dirty && !force) return
    dirty = false
    if (input.text !== displayValue) input.text = displayValue
  }

  function startOrStop() {
    if (!timer) return
    timer.clickSound()
    timer.toggle(input.text)
    syncInput(true)
  }

  function resetTimer() {
    if (!timer) return
    timer.clickSound()
    timer.reset()
    syncInput(true)
  }

  function toggleMute() {
    if (timer) timer.toggleMute()
  }

  onDisplayValueChanged: syncInput(false)

  onOpenedChanged: {
    if (opened) {
      syncInput(true)
      input.cursorPosition = input.text.length
    } else if (timer) {
      // Seen it: the bar can stop saying "done".
      timer.acknowledge()
    }
  }

  // ---- bar button --------------------------------------------------------

  readonly property string barLabel: {
    if (vertical || !timer) return finished ? iconTimer : (paused ? iconPaused : iconTimer)
    if (finished) return iconTimer + " done"
    if (running) return iconTimer + " " + Model.formatDuration(timer.activeSeconds)
    if (paused) return iconPaused + " " + Model.formatDuration(timer.activeSeconds)
    return iconTimer
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    active: root.finished
    dimmed: root.paused
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.opened ? ""
      : (root.running ? "Timer running · right click to stop"
        : (root.paused ? "Timer paused · right click to resume" : "Timer · right click to start"))

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (!root.timer) return
        root.timer.clickSound()
        root.timer.toggle("")
      } else if (b === Qt.MiddleButton) {
        if (!root.timer) return
        root.timer.clickSound()
        root.timer.reset()
      } else {
        root.toggle()
      }
    }
  }

  // ---- popup -------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: input
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      // ---- the number: typed into directly, shrinks to fit ----
      Item {
        width: parent.width
        height: Math.round(root.bigSize * 1.25)

        TextMetrics {
          id: metrics
          font.family: root.family
          font.pixelSize: root.bigCap
          text: input.text === "" ? "60s" : input.text
        }

        TextInput {
          id: input
          anchors.fill: parent
          horizontalAlignment: TextInput.AlignHCenter
          verticalAlignment: TextInput.AlignVCenter
          color: root.ink
          selectionColor: Color.accent
          selectedTextColor: Color.popups.background
          font.family: root.family
          font.pixelSize: root.bigSize
          readOnly: root.running
          selectByMouse: true
          validator: RegularExpressionValidator { regularExpression: /[0-9hmsHMS. ]*/ }

          onTextEdited: root.dirty = true

          Text {
            anchors.centerIn: parent
            visible: input.text === ""
            text: "60s"
            color: root.ink
            opacity: 0.35
            font: input.font
          }

          // Shortcuts are pulled out of the box's key stream before they turn
          // into text. A plain "m" is part of "25m", hence Ctrl+M for mute.
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            var ctrl = event.modifiers & Qt.ControlModifier
            if (event.key === Qt.Key_Escape) {
              root.close()
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              root.startOrStop()
            } else if (event.key === Qt.Key_R && !ctrl) {
              root.resetTimer()
            } else if (event.key === Qt.Key_M && ctrl) {
              root.toggleMute()
            } else if (event.key === Qt.Key_Question || event.key === Qt.Key_F1) {
              root.showSettings = !root.showSettings
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.switchPanel(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            } else {
              return
            }
            event.accepted = true
          }
        }
      }

      // ---- progress hairline ----
      Item {
        width: parent.width
        height: Style.space(4)

        Rectangle {
          id: track
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
        }

        Rectangle {
          anchors.left: track.left
          anchors.top: track.top
          anchors.bottom: track.bottom
          radius: track.radius
          color: Color.accent
          visible: width > 0
          width: track.width * (root.timer ? Math.max(0, Math.min(1, root.timer.progress)) : 0)

          Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }
      }

      // ---- started · ends ----
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.timer ? root.timer.schedule : "--:--:--  ·  --:--:--"
        color: root.ink
        opacity: 0.55
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }

      // ---- buttons: play/pause, reset, mute, and settings off to the side ----
      Item {
        width: parent.width
        height: playButton.height

        Row {
          anchors.centerIn: parent
          spacing: Style.space(8)

          IconButton {
            id: playButton
            iconText: root.running ? root.iconPaused : root.iconPlay
            tooltipText: root.running ? "Stop (Enter)" : "Start (Enter)"
            onClicked: root.startOrStop()
          }
          IconButton {
            iconText: root.iconReset
            tooltipText: "Reset (R)"
            onClicked: root.resetTimer()
          }
          IconButton {
            iconText: root.muted ? root.iconMuted : root.iconSound
            tooltipText: root.muted ? "Unmute (Ctrl+M)" : "Mute (Ctrl+M)"
            onClicked: root.toggleMute()
          }
        }

        IconButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          bordered: false
          selected: root.showSettings
          iconText: root.iconHelp
          tooltipText: "Shortcuts and sounds (?)"
          onClicked: root.showSettings = !root.showSettings
        }
      }

      // ---- settings: shortcuts, volume, sounds ----
      Column {
        width: parent.width
        spacing: Style.space(10)
        visible: root.showSettings

        PanelSeparator { foreground: root.ink }

        Grid {
          columns: 2
          columnSpacing: Style.space(14)
          rowSpacing: Style.space(4)

          Repeater {
            model: [
              "Enter / Space", "start or stop",
              "R", "reset to the saved duration",
              "Ctrl+M", "mute or unmute",
              "? / F1", "show or hide this",
              "Right click", "start or stop, from the bar",
              "Middle click", "reset, from the bar"
            ]
            Text {
              required property var modelData
              required property int index
              textFormat: Text.PlainText
              text: modelData
              color: root.ink
              opacity: index % 2 === 0 ? 1 : 0.6
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Durations: 90, 25m, 1h30m, 1.5m"
          color: root.ink
          opacity: 0.6
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSectionHeader {
          text: "VOLUME  " + (root.timer ? root.timer.volume : 20) + "%"
          foreground: root.ink
          fontFamily: root.family
        }

        // Previews on release rather than while dragging, so a drag doesn't
        // fire a stack of chimes.
        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: 100
          step: 1
          integer: true
          value: root.timer ? root.timer.volume : 20
          onMoved: function(v) { if (root.timer) root.timer.setVolume(v) }
          onReleased: function(v) {
            if (!root.timer) return
            root.timer.setVolume(v)
            root.timer.play(root.timer.buttonSound !== "none" ? root.timer.buttonSound : root.timer.doneSound, true)
          }
        }

        SoundPicker { label: "Button sound"; key: "buttonSound" }
        SoundPicker { label: "Done sound"; key: "doneSound" }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Built-in sounds come with the timer. Others are the freedesktop sound theme, listed when it's installed (sound-theme-freedesktop). All play through PipeWire at the volume above."
          color: root.ink
          opacity: 0.45
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // Number size: as big as the popup allows, smaller when the text is long.
  readonly property real bigCap: Style.font.displayLarge * 2.4
  readonly property real bigSize: {
    var avail = Math.max(1, panel.contentWidth - panel.padding * 2 - Style.space(16))
    var w = metrics.advanceWidth
    return w > avail ? Math.max(Style.font.title, bigCap * avail / w) : bigCap
  }

  component IconButton: Button {
    width: Style.space(44)
    height: Style.space(40)
    bordered: true
    foreground: root.ink
    fontFamily: root.family
    iconSize: Style.font.iconLarge
  }

  component SoundPicker: Row {
    id: picker
    property string label: ""
    property string key: ""

    width: parent.width
    spacing: Style.space(10)

    Text {
      id: pickerLabel
      width: Style.space(96)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: picker.label
      color: root.ink
      font.family: root.family
      font.pixelSize: Style.font.bodySmall
    }

    Dropdown {
      width: picker.width - pickerLabel.width - picker.spacing
      showLabel: false
      foreground: root.ink
      fontFamily: root.family
      options: root.timer ? root.timer.soundOptions : []
      value: root.timer ? root.timer[picker.key] : ""
      onChanged: function(v) { if (root.timer) root.timer.setSound(picker.key, v) }
    }
  }
}
