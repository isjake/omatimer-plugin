import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The timer's face: the number (typed into directly), a progress hairline,
// start · end times, and the buttons. Used by the bar popup and by each timer
// window.
//
// Everything scales off one unit taken from both dimensions, as the app did,
// so the layout keeps its proportions short-and-wide or tall-and-narrow.
Item {
  id: root

  property var service: null
  property var countdown: null
  property color ink: Color.foreground
  property string family: Style.font.family

  signal helpRequested()
  signal escapePressed()
  signal newRequested()

  readonly property real unit: Math.max(1, Math.min(width / 34, height / 22))
  readonly property real smallSize: clamp(Style.font.caption, unit * 1.25, 45)
  readonly property real bigCap: clamp(26, unit * 5.6, 290)
  readonly property real hit: Math.round(clamp(32, unit * 3.6, 150))
  readonly property real mark: Math.round(clamp(18, unit * 1.6, 60))

  readonly property bool running: countdown ? countdown.running : false
  readonly property bool finished: countdown ? countdown.finished : false
  readonly property bool muted: service ? service.muted : false
  readonly property string displayValue: !countdown ? "60s"
    : Model.formatDuration(finished ? countdown.savedSeconds : countdown.activeSeconds)

  readonly property string iconPaused: "\u{F03E4}"  // nf-md-pause
  readonly property string iconPlay: "\u{F040A}"    // nf-md-play
  readonly property string iconReset: "\u{F0450}"   // nf-md-refresh
  readonly property string iconSound: "\u{F057E}"   // nf-md-volume_high
  readonly property string iconMuted: "\u{F075F}"   // nf-md-volume_off
  readonly property string iconHelp: "\u{F0625}"    // nf-md-help_circle_outline

  function clamp(lo, v, hi) { return Math.max(lo, Math.min(v, hi)) }

  // ---- the box and the timer -------------------------------------------

  property bool dirty: false // the box holds something typed, not the timer's value

  function syncInput(force) {
    if (dirty && !force) return
    dirty = false
    if (input.text !== displayValue) input.text = displayValue
  }

  function focusInput() {
    syncInput(true)
    input.forceActiveFocus()
    input.cursorPosition = input.text.length
  }

  function startOrStop() {
    if (!countdown) return
    if (service) service.clickSound()
    countdown.toggle(input.text)
    syncInput(true)
  }

  function resetTimer() {
    if (!countdown) return
    if (service) service.clickSound()
    countdown.reset()
    syncInput(true)
  }

  onDisplayValueChanged: syncInput(false)
  onCountdownChanged: syncInput(true)

  // ---- layout ------------------------------------------------------------

  Column {
    anchors.centerIn: parent
    width: parent.width
    spacing: Math.round(root.unit * 0.7)

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
        selectedTextColor: Color.background
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
            root.escapePressed()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.startOrStop()
          } else if (event.key === Qt.Key_R && !ctrl) {
            root.resetTimer()
          } else if (event.key === Qt.Key_M && ctrl) {
            if (root.service) root.service.toggleMute()
          } else if (event.key === Qt.Key_N && ctrl) {
            root.newRequested()
          } else if (event.key === Qt.Key_Question || event.key === Qt.Key_F1) {
            root.helpRequested()
          } else {
            return
          }
          event.accepted = true
        }
      }
    }

    // progress hairline, three quarters of the width
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width * 0.75
      height: Math.round(root.clamp(3, root.unit * 0.22, 10))

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
        width: track.width * (root.countdown ? Math.max(0, Math.min(1, root.countdown.progress)) : 0)

        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.countdown ? root.countdown.schedule : "--:--:--  ·  --:--:--"
      color: root.ink
      opacity: 0.55
      font.family: root.family
      font.pixelSize: root.smallSize
    }

    // play/pause, reset, mute centred; the help mark off to the right
    Item {
      width: parent.width
      height: root.hit

      Row {
        anchors.centerIn: parent
        spacing: Math.round(root.hit * 0.18)

        FaceButton {
          iconText: root.running ? root.iconPaused : root.iconPlay
          tooltipText: root.running ? "Stop (Enter)" : "Start (Enter)"
          onClicked: root.startOrStop()
        }
        FaceButton {
          iconText: root.iconReset
          tooltipText: "Reset (R)"
          onClicked: root.resetTimer()
        }
        FaceButton {
          iconText: root.muted ? root.iconMuted : root.iconSound
          tooltipText: root.muted ? "Unmute (Ctrl+M)" : "Mute (Ctrl+M)"
          onClicked: if (root.service) root.service.toggleMute()
        }
      }

      // A quiet mark off to the side, as in the app: no frame, half ink, a
      // little lift under the pointer.
      FaceButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(root.mark * 1.5)
        height: Math.round(root.mark * 1.5)
        radius: height / 2
        iconSize: Math.round(root.mark * 0.85)
        bordered: false
        foreground: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, hot ? 0.8 : 0.45)
        iconText: root.iconHelp
        tooltipText: "Shortcuts and settings (?)"
        onClicked: root.helpRequested()
      }
    }
  }

  readonly property real bigSize: {
    var avail = Math.max(1, width - Style.space(16))
    var w = metrics.advanceWidth
    return w > avail ? Math.max(Style.font.title, bigCap * avail / w) : bigCap
  }

  component FaceButton: Button {
    width: root.hit
    height: root.hit
    bordered: true
    foreground: root.ink
    fontFamily: root.family
    iconSize: Math.round(root.hit * 0.42)
  }
}
