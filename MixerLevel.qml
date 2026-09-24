import QtQuick
import qs.Commons
import qs.Ui

// One consistently sized volume row, reused for the whole mix and each sound.
Row {
  id: row
  property QtObject bar: null
  property string label: ""
  property real value: 0
  property real labelWidth: Style.space(52)
  property bool removable: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal edited(int value)
  signal removeRequested()
  spacing: Style.space(6)

  Text {
    width: row.labelWidth
    text: row.label
    textFormat: Text.PlainText
    color: row.foreground
    font.family: row.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    anchors.verticalCenter: parent.verticalCenter
  }
  PanelSlider {
    id: slider
    width: row.width - row.labelWidth - percentage.width - row.spacing * (row.removable ? 3 : 2) - (row.removable ? removeButton.width : 0)
    bar: row.bar
    minimum: 0
    maximum: 100
    step: 5
    integer: true
    value: row.value
    onReleased: function(value) { row.edited(value) }
    anchors.verticalCenter: parent.verticalCenter
  }
  Text {
    id: percentage
    width: Style.space(34)
    text: Math.round(slider.dragging ? slider.liveValue : row.value) + "%"
    color: Qt.alpha(row.foreground, 0.65)
    font.family: row.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignRight
    anchors.verticalCenter: parent.verticalCenter
  }
  Button {
    id: removeButton
    visible: row.removable
    width: Style.space(24)
    height: Style.space(24)
    iconText: "\uf00d"
    iconSize: Style.font.caption
    foreground: Qt.alpha(row.foreground, 0.65)
    horizontalPadding: 0
    verticalPadding: 0
    focusable: true
    tooltipText: "Remove " + row.label
    onClicked: row.removeRequested()
    anchors.verticalCenter: parent.verticalCenter
  }
}
