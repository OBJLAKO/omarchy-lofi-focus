import QtQuick
import qs.Commons

// The value stays owned by the backend. Animation is presentation only and
// finishes immediately when motion is disabled or the panel closes.
Item {
  id: root
  property bool checked: false
  property bool interactive: true
  property bool animate: true
  property bool hasCursor: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  readonly property bool hot: mouse.containsMouse || hasCursor || activeFocus
  readonly property int trackWidth: Style.space(38)
  readonly property int trackHeight: Style.space(22)
  readonly property int knobSize: Style.space(16)
  readonly property int knobInset: Style.space(3)
  signal toggled()
  signal hovered(bool isHovered)
  implicitWidth: Style.space(46)
  implicitHeight: Style.space(32)
  activeFocusOnTab: interactive
  Accessible.role: Accessible.CheckBox
  Accessible.checked: checked
  Accessible.onPressAction: if (interactive) root.toggled()
  Keys.onSpacePressed: if (interactive) root.toggled()
  Keys.onReturnPressed: if (interactive) root.toggled()
  Keys.onEnterPressed: if (interactive) root.toggled()
  onAnimateChanged: if (!animate) { knobFeedback.complete(); trackFeedback.complete() }
  onVisibleChanged: if (!visible) { knobFeedback.complete(); trackFeedback.complete() }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: Style.cornerRadius
    border.width: root.activeFocus ? 1 : 0
    border.color: root.accent
  }
  Rectangle {
    id: track
    objectName: "switchTrack"
    width: root.trackWidth; height: root.trackHeight
    anchors.centerIn: parent
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: root.checked ? Qt.alpha(root.accent, 0.22) : Qt.alpha(root.foreground, root.hot ? 0.16 : 0.09)
    border.width: 1
    border.color: root.checked ? Qt.alpha(root.accent, 0.55) : Qt.alpha(root.foreground, 0.22)
    opacity: root.interactive ? 1 : 0.55
    Behavior on color {
      enabled: root.animate && root.visible
      ColorAnimation { id: trackFeedback; duration: 100 }
    }
    Rectangle {
      id: knob
      objectName: "switchKnob"
      width: root.knobSize; height: width
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.cornerRadius > 0 ? width / 2 : 0
      color: root.checked ? root.accent : Qt.alpha(root.foreground, 0.76)
      Behavior on x {
        enabled: root.animate && root.visible
        NumberAnimation { id: knobFeedback; duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.toggled() }
  }
}
