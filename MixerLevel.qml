import QtQuick
import qs.Commons
import qs.Ui

// A readable label and numeric level above a full-width track. The persistent
// dock uses the same control in one compact row.
FocusScope {
  id: row
  property QtObject bar: null
  property string label: ""
  property real value: 0
  property real labelWidth: Style.space(80)
  property bool compact: false
  property bool removable: false
  readonly property bool inlineLevel: compact && width >= labelWidth + Style.space(removable ? 146 : 110)
  property bool animate: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal edited(int value)
  signal removeRequested()
  signal focusRequested(var item)
  readonly property real copyHeight: Math.max(labelText.implicitHeight, percentage.implicitHeight, removable ? removeButton.height : 0)
  readonly property real sliderTop: inlineLevel ? 0 : copyHeight + Style.space(4)
  implicitHeight: inlineLevel ? Style.space(36) : sliderTop + slider.height
  SkylofiStyle { id: visual; foreground: row.foreground; background: Color.popups.background; accent: Color.accent }
  Text {
    id: labelText
    objectName: "levelLabel"
    width: row.inlineLevel ? row.labelWidth : parent.width - percentage.width - (row.removable ? removeButton.width + Style.space(8) : 0) - Style.space(10)
    y: row.inlineLevel ? (parent.height - height) / 2 : (row.copyHeight - height) / 2
    text: row.label; textFormat: Text.PlainText
    color: row.foreground
    font.family: row.fontFamily; font.pixelSize: visual.label
    elide: Text.ElideRight
  }
  SkylofiSlider {
    id: slider
    objectName: "levelSlider"
    animate: row.animate
    x: row.inlineLevel ? row.labelWidth + Style.space(10) : 0
    y: row.sliderTop
    width: Math.max(Style.space(40), row.width - x - (row.inlineLevel ? percentage.width + Style.space(10) + (row.removable ? removeButton.width + Style.space(8) : 0) : 0))
    height: Style.space(32)
    bar: row.bar
    trackColor: visual.sliderTrack
    fillColor: Color.accent
    knobColor: Color.accent
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
    onActiveFocusChanged: if (activeFocus) row.focusRequested(this)
  }
  Text {
    id: percentage
    objectName: "levelReadout"
    x: parent.width - width - (row.removable ? removeButton.width + Style.space(8) : 0)
    y: row.inlineLevel ? (parent.height - height) / 2 : (row.copyHeight - height) / 2
    width: Style.space(40)
    text: Math.round(slider.dragging ? slider.liveValue : row.value) + "%"
    color: visual.muted
    font.family: row.fontFamily; font.pixelSize: visual.label
    horizontalAlignment: Text.AlignRight
  }
  SkylofiButton {
    fontFamily: row.fontFamily
    animate: row.animate && row.visible
    id: removeButton
    objectName: "removeSound"
    visible: row.removable
    x: parent.width - width
    y: row.inlineLevel ? (parent.height - height) / 2 : 0
    width: Style.space(28); height: Style.space(28)
    iconText: "\uf00d"; iconSize: visual.caption
    foreground: visual.muted
    horizontalPadding: 0; verticalPadding: 0
    focusable: true
    tooltipText: "Remove " + row.label
    Accessible.name: tooltipText
    onClicked: row.removeRequested()
    onActiveFocusChanged: if (activeFocus) row.focusRequested(this)
  }
}
