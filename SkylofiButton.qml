import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

// A small theme-native action with an explicit motion policy. The host Button
// has unconditional color animation, so reduced motion needs a local control.
BorderSurface {
  id: root
  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false
  property bool animate: true
  property color foreground: Color.foreground
  property color background: "transparent"
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property bool leftAlign: false
  readonly property bool hot: mouse.containsMouse || hasCursor
  readonly property bool focused: focusable && activeFocus
  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  SkylofiStyle { id: visual; foreground: root.foreground; accent: root.accent }
  implicitWidth: (buttonIcon.visible ? buttonIcon.implicitWidth : 0)
    + (buttonLabel.visible ? buttonLabel.implicitWidth : 0)
    + (buttonIcon.visible && buttonLabel.visible ? copy.spacing : 0)
    + horizontalPadding * 2 + Style.space(2)
  implicitHeight: Math.max(visual.touchTarget, copy.implicitHeight + verticalPadding * 2 + Style.space(2))
  radius: visual.radius
  color: !enabled ? background : mouse.pressed ? visual.pressed
    : selected || active ? Qt.alpha(root.accent, hot ? 0.17 : 0.11)
    : focused || hot ? visual.hover : background
  borderSpec: focused ? Border.flat(visual.focus, 1)
    : bordered ? Border.flat(hot ? visual.quiet : visual.line, 1) : Border.none()
  activeFocusOnTab: focusable
  Accessible.role: Accessible.Button
  Accessible.name: text || tooltipText
  Accessible.description: tooltipText
  Accessible.onPressAction: if (enabled) root.clicked()
  Keys.onReturnPressed: if (enabled && focusable) root.clicked()
  Keys.onEnterPressed: if (enabled && focusable) root.clicked()
  Keys.onSpacePressed: if (enabled && focusable) root.clicked()
  onAnimateChanged: if (!animate) fillFeedback.complete()
  onVisibleChanged: if (!visible) fillFeedback.complete()

  Behavior on color {
    enabled: root.animate && root.visible
    ColorAnimation { id: fillFeedback; duration: visual.feedbackDuration }
  }
  Row {
    id: copy
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.horizontalPadding + Style.space(1)
    spacing: Style.space(6)
    // Some legacy callers already fade disabled controls. Avoid fading twice.
    opacity: root.enabled || root.opacity < 1 ? 1 : 0.45
    SkylofiIcon {
      id: buttonIcon
      visible: root.iconText.length > 0
      glyph: root.iconText
      anchors.verticalCenter: parent.verticalCenter
      color: root.selected ? root.accent : root.foreground
      size: root.iconSize
    }
    Text {
      id: buttonLabel
      visible: root.text.length > 0
      width: Math.min(implicitWidth,Math.max(0,root.width - root.horizontalPadding * 2 - Style.space(2)
        - (buttonIcon.visible ? buttonIcon.width + copy.spacing : 0)))
      elide: Text.ElideRight
      text: root.text; textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      color: root.foreground
      font.family: root.fontFamily; font.pixelSize: root.fontSize
      font.weight: root.selected ? Font.DemiBold : Font.Normal
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: function(event) {
      if (root.focusable) root.forceActiveFocus(Qt.MouseFocusReason)
      if (event.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }
  QQC.ToolTip {
    visible: root.tooltipText.length > 0 && mouse.containsMouse
    text: root.tooltipText
    delay: 450
    enter: Transition { }
    exit: Transition { }
    background: BorderSurface {
      color: Color.tooltip.background
      borderSpec: Border.flat(Color.tooltip.border, 1)
      radius: visual.radius
    }
    contentItem: Text {
      text: root.tooltipText; textFormat: Text.PlainText
      color: Color.tooltip.text
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
  }
}
