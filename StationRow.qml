import QtQuick
import qs.Commons
import qs.Ui

// Plain source rows let the names lead. One persistent selected mark and a
// separate keyboard outline distinguish selection from hover.
BorderSurface {
  id: root
  property bool current: false
  property bool hasCursor: mouse.containsMouse || activeFocus
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string glyph: "\uf001"
  property string name: ""
  property string description: ""
  property bool playing: false
  property bool muted: false
  property bool animate: true
  property string fontFamily: Style.font.family
  signal activated()
  SkylofiStyle { id: visual; foreground: root.foreground; background: Color.popups.background; accent: root.accent }
  implicitHeight: visual.rowHeight
  color: mouse.pressed ? visual.pressed : root.current ? Qt.alpha(root.accent, root.hasCursor ? 0.15 : 0.09)
    : root.hasCursor ? visual.hover : "transparent"
  radius: visual.radius
  Behavior on color {
    enabled: root.animate && root.visible
    ColorAnimation { id: selectionFeedback; duration: visual.feedbackDuration }
  }
  onAnimateChanged: if (!animate) selectionFeedback.complete()
  onVisibleChanged: if (!visible) selectionFeedback.complete()
  borderSpec: activeFocus ? Border.flat(root.accent, 1) : Border.none()
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: name
  Accessible.description: description + (current ? ", selected" : "")
  Accessible.onPressAction: root.activated()
  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

  SkylofiIcon {
    x: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.glyph
    color: root.current ? root.accent : visual.quiet
    size: visual.iconSize
  }
  Column {
    id: copy
    x: Style.space(46)
    width: parent.width - x - Style.space(34)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)
    Text {
      width: parent.width
      text: root.name; textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily; font.pixelSize: visual.body
      font.weight: root.current ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text.length > 0
      text: root.description; textFormat: Text.PlainText
      color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.caption
      elide: Text.ElideRight
    }
  }
  SkylofiIcon {
    anchors.right: parent.right; anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    visible: root.current
    name: root.muted ? "pause" : "check"
    color: root.accent
    size: visual.iconSize
  }
  MouseArea {
    id: mouse
    anchors.fill: parent; hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: { root.forceActiveFocus(); root.activated() }
  }
}
