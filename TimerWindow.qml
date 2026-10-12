import QtQuick
import Quickshell
import qs.Commons

// A timer as an ordinary window: Hyprland tiles it, floats it, moves it
// between workspaces and closes it (Super+W) like any other app. Window rules
// can match it by title: ^Omatimer.
FloatingWindow {
  id: root

  property var service: null
  property var countdown: null
  // Set when the service closes the window itself, so that isn't mistaken for
  // the user closing it.
  property bool closingFromService: false

  signal userClosed()

  title: "Omatimer" + (countdown && countdown.number > 1 ? " " + countdown.number : "")
    + (service && service.muted ? " (muted)" : "")
  implicitWidth: 640
  implicitHeight: 480
  minimumSize: Qt.size(280, 220)
  // Opaque, so transparency stays the compositor's job like every other
  // window's.
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)

  function closeFromService() {
    closingFromService = true
    visible = false
    destroy()
  }

  onVisibleChanged: {
    if (visible) Qt.callLater(face.focusInput)
    else if (!closingFromService) userClosed()
  }

  TimerFace {
    id: face
    anchors.fill: parent
    service: root.service
    countdown: root.countdown
    ink: Color.foreground
    family: Style.font.family
    onHelpRequested: if (root.service) root.service.toggleSettingsWindow()
    onNewRequested: if (root.service) root.service.newTimer("", false)
  }
}
