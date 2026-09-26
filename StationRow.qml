import QtQuick
import qs.Commons
import qs.Ui

// One selectable station row, in the style of Omarchy's device rows
// (shell/plugins/panels/audio/Panel.qml). Visual state comes entirely from
// `current` (the remembered selection) and `hasCursor` (keyboard/mouse
// cursor) so a single highlight is ever on screen. A small equalizer marks
// the station that is actually producing sound.
CursorSurface {
  id: root

  property string glyph: ""
  property string name: ""
  property string description: ""
  property bool playing: false
  property bool muted: false
  property bool animate: true
  property string fontFamily: Style.font.family

  implicitHeight: rowInner.implicitHeight + Style.spacing.xl

  Row {
    id: rowInner
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(8)

    // Leading glyph, or an animated equalizer when this station is playing.
    Item {
      width: Style.space(22)
      implicitHeight: Math.max(glyphText.implicitHeight, equalizer.implicitHeight)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: glyphText
        textFormat: Text.PlainText
        visible: !root.playing
        anchors.centerIn: parent
        text: root.glyph
        color: Qt.alpha(root.foreground, root.muted ? 0.5 : 1.0)
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        horizontalAlignment: Text.AlignHCenter
      }

      Row {
        id: equalizer
        visible: root.playing
        anchors.centerIn: parent
        spacing: Style.space(2)

        Repeater {
          model: 3

          Rectangle {
            required property int index
            width: Style.space(3)
            height: Style.space(6)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.muted ? Qt.alpha(root.foreground, 0.5) : root.accent
            transformOrigin: Item.Bottom
            // A fixed stepped height keeps the equalizer readable when motion
            // is disabled; the animation overrides scale only while running.
            readonly property real restingScale: index === 0 ? 1.0 : (index === 1 ? 1.6 : 0.7)
            scale: root.animate ? 1 : restingScale

            SequentialAnimation on scale {
              running: root.playing && root.visible && root.animate
              loops: Animation.Infinite
              PauseAnimation { duration: index * 140 }
              NumberAnimation { to: 1.9; duration: 260; easing.type: Easing.InOutSine }
              NumberAnimation { to: 0.55; duration: 300; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.3; duration: 240; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.0; duration: 220; easing.type: Easing.InOutSine }
            }
          }
        }
      }
    }

    Column {
      width: parent.width - Style.space(22) - parent.spacing
      spacing: Style.space(1)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        text: root.name
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.current
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: root.description
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }
}
