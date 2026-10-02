import QtQuick
import qs.Commons
import qs.Ui

// Native slider with a large pointer target and explicit keyboard controls.
Row {
  id: row
  property QtObject bar: null
  property string label: ""
  property real value: 0
  property real labelWidth: Style.space(76)
  property bool removable: false
  property bool animate: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal edited(int value)
  signal removeRequested()
  spacing: Style.space(10)
  Text {
    width: row.labelWidth
    text: row.label; textFormat: Text.PlainText
    color: row.foreground
    font.family: row.fontFamily; font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    anchors.verticalCenter: parent.verticalCenter
  }
  PanelSlider {
    id: slider
    objectName: "levelSlider"
    width: Math.max(Style.space(40), row.width - row.labelWidth - percentage.width - row.spacing * (row.removable ? 3 : 2) - (row.removable ? removeButton.width : 0))
    implicitHeight: Style.space(34)
    bar: row.bar
    trackColor: Qt.alpha(row.foreground, 0.16)
    fillColor: row.foreground
    knobColor: row.foreground
    minimum: 0; maximum: 100; step: 5; integer: true
    value: row.value
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: row.label + " volume"
    Accessible.description: Math.round(row.value) + " percent"
    Keys.onLeftPressed: row.edited(Math.max(0, row.value - 5))
    Keys.onRightPressed: row.edited(Math.min(100, row.value + 5))
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Home) { row.edited(0); event.accepted = true }
      else if (event.key === Qt.Key_End) { row.edited(100); event.accepted = true }
    }
    onReleased: function(value) { row.edited(value) }
    anchors.verticalCenter: parent.verticalCenter
    Rectangle {
      anchors.fill: parent; anchors.margins: -2
      visible: slider.activeFocus
      color: "transparent"; radius: Style.cornerRadius
      border.color: Color.accent; border.width: 1
    }
  }
  Text {
    id: percentage
    width: Style.space(36)
    text: Math.round(slider.dragging ? slider.liveValue : row.value) + "%"
    color: Qt.alpha(row.foreground, 0.7)
    font.family: row.fontFamily; font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignRight
    anchors.verticalCenter: parent.verticalCenter
  }
  Button {
    id: removeButton
    visible: row.removable
    width: Style.space(30); height: Style.space(30)
    iconText: "\uf00d"; iconSize: Style.font.caption
    foreground: Qt.alpha(row.foreground, 0.7)
    horizontalPadding: 0; verticalPadding: 0
    focusable: true
    tooltipText: "Remove " + row.label
    Accessible.name: tooltipText
    onClicked: row.removeRequested()
    anchors.verticalCenter: parent.verticalCenter
  }
}
