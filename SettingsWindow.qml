import QtQuick
import Quickshell
import qs.Commons

// The shortcuts and settings, as a small window of their own beside the
// timers (the app's help window). The ? in any timer window toggles it.
FloatingWindow {
  id: root

  property var service: null
  property bool closingFromService: false

  signal userClosed()

  function closeFromService() {
    closingFromService = true
    visible = false
    destroy()
  }

  onVisibleChanged: if (!visible && !closingFromService) userClosed()

  title: "Omatimer settings"
  implicitWidth: 480
  implicitHeight: Math.max(420, content.implicitHeight + 48)
  minimumSize: Qt.size(380, 360)
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)

  Flickable {
    anchors.fill: parent
    anchors.margins: 24
    contentHeight: content.implicitHeight
    clip: true

    SettingsContent {
      id: content
      width: parent.width
      service: root.service
      ink: Color.foreground
      family: Style.font.family
    }
  }
}
