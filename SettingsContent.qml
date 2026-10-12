import QtQuick
import qs.Commons
import qs.Ui

// Shortcuts, how timers open, volume, and sounds. Shown inline in the bar
// popup, and as its own small window from a timer window.
Column {
  id: root

  property var service: null
  property color ink: Color.foreground
  property string family: Style.font.family
  property bool showModeNote: true

  spacing: Style.space(10)

  Grid {
    columns: 2
    columnSpacing: Style.space(14)
    rowSpacing: Style.space(4)

    Repeater {
      model: [
        "Enter / Space", "start or stop",
        "R", "reset to the saved duration",
        "Ctrl+M", "mute or unmute",
        "Ctrl+N", "a new timer",
        "? / F1", "show or hide this",
        "Bar, right click", "start or stop",
        "Bar, middle click", "reset"
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

  PanelSeparator { foreground: root.ink; width: parent.width }

  Picker {
    label: "Timers"
    options: [
      { value: "windows", label: "Multiple timers, in windows" },
      { value: "bar", label: "One timer, in the bar" }
    ]
    value: root.service ? root.service.mode : "windows"
    onPicked: function(v) { if (root.service) root.service.setMode(v) }
  }

  Text {
    visible: root.showModeNote
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "Windows tile and float like any app. The bar has one timer: switching to it keeps the timer that ends soonest and closes the rest."
    color: root.ink
    opacity: 0.45
    font.family: root.family
    font.pixelSize: Style.font.caption
  }

  PanelSectionHeader {
    text: "VOLUME  " + (root.service ? root.service.volume : 20) + "%"
    foreground: root.ink
    fontFamily: root.family
  }

  // Previews on release rather than while dragging, so a drag doesn't fire a
  // stack of chimes.
  PanelSlider {
    width: parent.width
    minimum: 0
    maximum: 100
    step: 1
    integer: true
    fillColor: root.ink
    knobColor: root.ink
    trackColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.15)
    value: root.service ? root.service.volume : 20
    onMoved: function(v) { if (root.service) root.service.setVolume(v) }
    onReleased: function(v) {
      if (!root.service) return
      root.service.setVolume(v)
      root.service.play(root.service.buttonSound !== "none" ? root.service.buttonSound : root.service.doneSound, true)
    }
  }

  Picker {
    label: "Button sound"
    options: root.service ? root.service.soundOptions : []
    value: root.service ? root.service.buttonSound : ""
    onPicked: function(v) { if (root.service) root.service.setSound("buttonSound", v) }
  }

  Picker {
    label: "Done sound"
    options: root.service ? root.service.soundOptions : []
    value: root.service ? root.service.doneSound : ""
    onPicked: function(v) { if (root.service) root.service.setSound("doneSound", v) }
  }

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

  component Picker: Row {
    id: picker
    property string label: ""
    property var options: []
    property string value: ""
    signal picked(string value)

    width: root.width
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
      options: picker.options
      value: picker.value
      onChanged: function(v) { picker.picked(v) }
    }
  }
}
