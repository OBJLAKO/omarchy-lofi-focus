import QtQuick
import qs.Commons

// A shared, keyboard-accessible control with bounded live audio feedback.
Column {
  id: root
  property string label: ""
  property real value: 0
  property real minimum: 0
  readonly property real displayValue: slider.displayValue
  property string suffix: Math.round(displayValue) + "%"
  property string lowLabel: ""
  property string highLabel: ""
  property string middleLabel: ""
  property QtObject bar: null
  property bool animate: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal edited(int value)
  signal focusRequested(var item)
  width: parent.width; spacing: Style.space(2)
  SkylofiStyle { id: visual; foreground: root.foreground }
  Row {
    width: parent.width
    Text {
      width: parent.width - output.width - Style.space(8)
      text: root.label; color: root.foreground; elide: Text.ElideRight
      font.family: root.fontFamily; font.pixelSize: visual.label
    }
    Text {
      id: output
      width: Math.min(Style.space(100), parent.width * 0.45)
      text: root.suffix; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
      color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
    }
  }
  SkylofiSlider {
    id: slider
    objectName: "soundControlSlider"
    width: parent.width; height: Style.space(28)
    bar: root.bar; minimum: root.minimum; maximum: 100; step: 5; integer: true
    value: root.value; animate: root.animate
    trackColor: visual.sliderTrack; fillColor: Color.accent; knobColor: Color.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider; Accessible.name: root.label
    Accessible.description: root.suffix
    onEdited: function(value) { root.edited(value) }
    onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
  }
  Item {
    width: parent.width; height: low.visible ? low.implicitHeight : 0
    Text {
      id: low; anchors.left: parent.left
      visible: root.lowLabel.length > 0; text: root.lowLabel
      color: visual.quiet; font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.middleLabel.length > 0; text: root.middleLabel
      color: visual.quiet; font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    Text {
      anchors.right: parent.right
      visible: root.highLabel.length > 0; text: root.highLabel
      color: visual.quiet; font.family: root.fontFamily; font.pixelSize: visual.caption
    }
  }
}
