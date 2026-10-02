import QtQuick
import qs.Commons
import qs.Ui

// Selection stays visible; hover and keyboard focus are temporary affordances.
CursorSurface {
  id: root
  property string glyph: "\uf001"
  property string name: ""
  property string description: ""
  property bool playing: false
  property bool muted: false
  property bool animate: true
  property string fontFamily: Style.font.family
  signal activated()
  implicitHeight: Math.max(Style.space(54), copy.implicitHeight + Style.space(18))
  activeFocusOnTab: true
  hasCursor: mouse.containsMouse || activeFocus
  Accessible.role: Accessible.Button
  Accessible.name: name
  Accessible.description: description + (current ? ", selected" : "")
  Accessible.onPressAction: root.activated()
  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

  Rectangle {
    x: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(32); height: width
    radius: Style.cornerRadius
    color: Qt.alpha(root.current ? root.accent : root.foreground, 0.08)
    Text {
      anchors.centerIn: parent
      visible: !root.playing
      text: root.current ? (root.muted ? "\uf04c" : "\uf00c") : root.glyph
      color: root.current ? root.accent : Qt.alpha(root.foreground, 0.75)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    PlaybackWave {
      anchors.centerIn: parent
      width: Style.space(14); height: Style.space(14)
      visible: root.playing
      active: root.playing
      animate: root.animate
      ink: root.accent
    }
  }
  Column {
    id: copy
    x: Style.space(54)
    width: parent.width - x - Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)
    Text {
      width: parent.width
      text: root.name; textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily; font.pixelSize: Style.font.body
      font.bold: root.current
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text.length > 0
      text: root.description; textFormat: Text.PlainText
      color: Qt.alpha(root.foreground, 0.7)
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent; hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: { root.forceActiveFocus(); root.activated() }
  }
}
