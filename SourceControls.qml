import QtQuick
import QtQuick.Controls as QQC
import qs.Commons

Column {
  id: root
  property var sound: ({})
  property QtObject bar: null
  property bool animate: true
  property bool detailsOpen: false
  property bool helpOpen: false
  property bool canAudition: false
  property bool auditioning: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal volumeEdited(int value)
  signal layerEdited(string key, string value)
  signal presetRequested(string preset)
  signal auditionRequested()
  signal focusRequested(var item)
  width: parent.width; spacing: Style.space(10)
  function number(key,fallback) {
    var value = Number(sound[key])
    return sound[key] === undefined || !isFinite(value) ? fallback : value
  }
  function depthText(value) { return value < 33 ? "Nearby" : value < 67 ? "Midway" : "Distant" }
  function coverageText(value) { return value < 25 ? "Point" : value < 75 ? "Wide" : "Surrounding" }
  SkylofiStyle { id: visual; foreground: root.foreground }
  Row {
    id: auditionRow
    width: parent.width; spacing: Style.space(6)
    Item {
      width: Math.min(auditionButton.implicitWidth,Math.max(0,root.width - helpButton.implicitWidth - auditionRow.spacing))
      height: auditionButton.implicitHeight
    SkylofiButton {
      id: auditionButton
      width: parent.width
      objectName: "sourceAudition"
      text: root.auditioning ? "Back to mix" : "Solo"
      tooltipText: root.canAudition ? "Hear and adjust only this sound until you return to the mix" : "Start playback to hear a sound alone"
      iconText: root.auditioning ? "\uf0e2" : "\uf025"
      bordered: true; focusable: true; enabled: root.canAudition
      opacity: enabled ? 1 : 0.45
      fontSize: visual.caption; foreground: root.foreground; fontFamily: root.fontFamily
      animate: root.animate; onClicked: root.auditionRequested()
      onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    }
      MouseArea {
        id: unavailableHover
        anchors.fill: parent; enabled: !root.canAudition
        hoverEnabled: true; acceptedButtons: Qt.NoButton
      }
      QQC.ToolTip {
        objectName: "auditionUnavailableHint"
        visible: !root.canAudition && unavailableHover.containsMouse
        text: "Start playback to hear a sound alone"; delay: 350
        enter: Transition {}
        exit: Transition {}
        background: Rectangle {
          color: Color.tooltip.background; radius: visual.radius
          border.width: 1; border.color: Color.tooltip.border
        }
        contentItem: Text {
          text: "Start playback to hear a sound alone"; color: Color.tooltip.text
          font.family: root.fontFamily; font.pixelSize: visual.caption
        }
      }
    }
    SkylofiButton {
      id: helpButton
      objectName: "coverageHelp"
      text: ""; iconText: "\uf05a"; tooltipText: "About coverage"
      focusable: true; selected: root.helpOpen; animate: root.animate
      foreground: visual.muted; fontFamily: root.fontFamily
      onClicked: root.helpOpen = !root.helpOpen
      onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    }
  }
  Text {
    width: parent.width; visible: root.auditioning
    text: "Only this sound is playing. Changes apply to your mix."
    wrapMode: Text.Wrap; color: visual.muted
    font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Row {
    width: parent.width; spacing: Style.space(6)
    Repeater {
      model: [{id:"near",label:"Nearby"},{id:"far",label:"Distant"},{id:"around",label:"Around"}]
      SkylofiButton {
        required property var modelData
        objectName: "sourcePreset-" + modelData.id
        width: (root.width - Style.space(12)) / 3
        text: modelData.label; bordered: true; focusable: true
        tooltipText: modelData.label
        horizontalPadding: Style.space(2); verticalPadding: Style.space(2)
        foreground: root.foreground; fontFamily: root.fontFamily; fontSize: visual.caption
        animate: root.animate
        onClicked: root.presetRequested(modelData.id)
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
  }
  SoundControl {
    objectName: "spaceVolume"
    label: "Volume"; value: root.number("volume",25)
    lowLabel: "Quiet"; highLabel: "Loud"
    bar: root.bar; foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
    onEdited: function(value) { root.volumeEdited(value) }
    onFocusRequested: function(item) { root.focusRequested(item) }
  }
  SoundControl {
    objectName: "spaceDistance"
    label: "Distance"; value: root.number("distance",0); suffix: root.depthText(displayValue)
    lowLabel: "Nearby"; highLabel: "Far away"
    bar: root.bar; foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
    onEdited: function(value) { root.layerEdited("distance",String(value)) }
    onFocusRequested: function(item) { root.focusRequested(item) }
  }
  SoundControl {
    objectName: "spaceCoverage"
    label: "Coverage"; value: root.number("coverage",50); suffix: root.coverageText(displayValue)
    lowLabel: "Point"; middleLabel: "Wide"; highLabel: "Surrounding"
    bar: root.bar; foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
    onEdited: function(value) { root.layerEdited("coverage",String(value)) }
    onFocusRequested: function(item) { root.focusRequested(item) }
  }
  Text {
    width: parent.width; visible: root.helpOpen
    text: "Coverage spreads a point into a diffuse stereo field. Headphones give the clearest effect."
    wrapMode: Text.Wrap; color: visual.muted
    font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  SkylofiButton {
    objectName: "spaceDetailsButton"
    width: parent.width
    text: root.detailsOpen ? "Hide extra acoustics" : "Extra acoustics"
    leftAlign: true; iconText: root.detailsOpen ? "\uf107" : "\uf105"
    foreground: visual.muted; fontFamily: root.fontFamily; fontSize: visual.caption
    horizontalPadding: 0; verticalPadding: 0
    animate: root.animate; focusable: true
    onClicked: root.detailsOpen = !root.detailsOpen
    onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
  }
  Column {
    width: parent.width; visible: root.detailsOpen; spacing: Style.space(10)
    SoundControl {
      objectName: "spacePan"
      label: "Left / right"; minimum: -100; value: root.number("pan",0)
      suffix: Math.abs(displayValue) < 15 ? "Center" : displayValue < 0 ? "Left" : "Right"
      lowLabel: "Left"; highLabel: "Right"
      bar: root.bar; foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      onEdited: function(value) { root.layerEdited("pan",String(value)) }
      onFocusRequested: function(item) { root.focusRequested(item) }
    }
    Row {
      width: parent.width; spacing: Style.space(8)
      Text {
        width: parent.width - outsideToggle.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: "Outside the room"; wrapMode: Text.Wrap; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: visual.label
      }
      SkylofiSwitch {
        id: outsideToggle; objectName: "spaceOutside"
        checked: root.sound.outside === true; animate: root.animate
        foreground: root.foreground; Accessible.name: "Outside the room"
        onToggled: root.layerEdited("outside",checked ? "off" : "on")
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
    Row {
      width: parent.width; spacing: Style.space(8)
      Text {
        width: parent.width - livingToggle.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: "Vary this sound"; wrapMode: Text.Wrap; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: visual.label
      }
      SkylofiSwitch {
        id: livingToggle; objectName: "spaceLiving"
        checked: root.sound.living !== false; animate: root.animate
        foreground: root.foreground; Accessible.name: "Vary this sound with Living mix"
        onToggled: root.layerEdited("living",checked ? "off" : "on")
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
    Repeater {
      model: [{key:"softness",label:"Muffling",fallback:0},{key:"reflections",label:"Reflections",fallback:25},{key:"echo",label:"Echo",fallback:0},{key:"width",label:"Original stereo width",fallback:100}]
      SoundControl {
        required property var modelData
        objectName: "space-" + modelData.key
        label: modelData.label; value: root.number(modelData.key,modelData.fallback)
        bar: root.bar; foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
        onEdited: function(value) { root.layerEdited(modelData.key,String(value)) }
        onFocusRequested: function(item) { root.focusRequested(item) }
      }
    }
  }
}
