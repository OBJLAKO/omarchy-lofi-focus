import QtQuick
import qs.Commons

// A mixer strip: the sound, two contextual actions, and its fader. Spatial
// controls load only when requested; the ordinary mix stays easy to scan.
Rectangle {
  id: root
  property var sound: ({})
  property string label: ""
  property bool selected: false
  property bool expanded: false
  property bool animate: true
  property bool canAudition: false
  property bool auditioning: false
  property bool detailsOpen: false
  property bool helpOpen: false
  readonly property bool compactHeader: width < Style.space(250)
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal selectedRequested()
  signal removeRequested()
  signal volumeEdited(int value)
  signal layerEdited(string key, string value)
  signal presetRequested(string preset)
  signal auditionRequested()
  signal focusRequested(var item)
  implicitHeight: body.implicitHeight + Style.space(16)
  height: implicitHeight
  color: "transparent"
  border.width: 0
  SkylofiStyle { id: visual; foreground: root.foreground }
  function sourceIcon(id) {
    if (/fire|bonfire/.test(id)) return "fire"
    if (/rain|storm/.test(id)) return "rain"
    if (/wind/.test(id)) return "wind"
    if (/river|water|ocean|stream/.test(id)) return "water"
    if (/forest|leaves/.test(id)) return "tree"
    return "music"
  }
  Column {
    id: body
    y: Style.space(8)
    width: parent.width
    spacing: Style.space(4)
    Item {
      width: parent.width
      height: Style.space(32)
      SkylofiIcon {
        x: 0; anchors.verticalCenter: parent.verticalCenter
        name: root.sourceIcon(root.sound.id || "")
        size: visual.iconSize
        color: root.auditioning ? Color.accent : visual.muted
      }
      Text {
        id: sourceName
        x: Style.space(24)
        width: Math.max(0, selectButton.x - x - Style.space(8))
        anchors.verticalCenter: parent.verticalCenter
        text: root.label; textFormat: Text.PlainText
        elide: Text.ElideRight; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: visual.body
        font.weight: Font.Medium
      }
      SkylofiButton {
        id: selectButton
        objectName: "sourceSelect-" + (root.sound.id || "")
        x: soloButton.x - width - Style.space(4)
        text: "Space"
        width: Style.space(54); height: Style.space(32)
        horizontalPadding: Style.space(4); verticalPadding: 0
        fontSize: visual.caption; foreground: root.expanded ? Color.accent : visual.muted
        fontFamily: root.fontFamily; animate: root.animate
        tooltipText: root.expanded ? "Hide spatial settings for " + root.label : "Spatial settings for " + root.label
        Accessible.name: "Spatial settings for " + root.label
        selected: root.expanded; focusable: true
        onClicked: root.selectedRequested()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
      SkylofiButton {
        id: soloButton
        objectName: "sourceSolo-" + (root.sound.id || "")
        x: removeButton.x - width - Style.space(4)
        text: root.auditioning ? "Mix" : "Solo"
        tooltipText: root.auditioning ? "Back to mix" : "Listen to " + root.label + " alone"
        Accessible.name: root.auditioning ? "Back to mix" : "Solo " + root.label
        width: Style.space(44); height: Style.space(32)
        horizontalPadding: Style.space(2); verticalPadding: 0
        fontSize: visual.caption; foreground: root.auditioning ? Color.accent : visual.muted
        fontFamily: root.fontFamily; animate: root.animate
        selected: root.auditioning; focusable: true; enabled: root.canAudition
        onClicked: root.auditionRequested()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
      SkylofiButton {
        id: removeButton
        objectName: "sourceRemove-" + (root.sound.id || "")
        x: parent.width - width
        iconText: "close"; tooltipText: "Remove " + root.label + " from mix"
        Accessible.name: "Remove " + root.label + " from mix"
        width: Style.space(32); height: Style.space(32)
        horizontalPadding: 0; verticalPadding: 0; iconSize: visual.iconSize
        focusable: true; foreground: visual.quiet; fontFamily: root.fontFamily; animate: root.animate
        onClicked: root.removeRequested()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
    Item {
      id: volumeLevel
      objectName: "sourceVolume-" + (root.sound.id || "")
      width: parent.width; height: Style.space(32)
      signal edited(int value)
      onEdited: function(value) { root.volumeEdited(value) }
      SkylofiSlider {
        id: volumeSlider
        objectName: "levelSlider"
        width: Math.max(Style.space(40), parent.width - volumeReadout.width - Style.space(12))
        height: parent.height
        bar: root.bar; minimum: 0; maximum: 100; step: 5; integer: true
        value: Number(root.sound.volume) || 0; animate: root.animate
        trackColor: visual.sliderTrack; fillColor: Color.accent; knobColor: Color.accent
        activeFocusOnTab: true
        Accessible.role: Accessible.Slider
        Accessible.name: root.label + " volume"
        Accessible.description: Math.round(displayValue) + " percent"
        onEdited: function(value) { volumeLevel.edited(value) }
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
      Text {
        id: volumeReadout
        objectName: "levelReadout"
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        text: Math.round(volumeSlider.displayValue) + "%"
        color: visual.muted; horizontalAlignment: Text.AlignRight
        font.family: root.fontFamily; font.pixelSize: visual.label
      }
    }
    Loader {
      objectName: "sourceDetailsLoader"
      width: parent.width; active: root.expanded; visible: active
      height: item ? item.implicitHeight : 0
      sourceComponent: Component {
        Column {
          width: parent.width; spacing: Style.space(12)
          CoverageStage {
            objectName: "sourceMini-" + (root.sound.id || "")
            width: parent.width; mini: true; interactive: false
            layers: root.sound.id ? [root.sound] : []
            options: [{value:root.sound.id,label:root.label}]; selectedId: root.sound.id || ""
            foreground: root.foreground; fontFamily: root.fontFamily
          }
          SourceControls {
            objectName: "sourceControls-" + (root.sound.id || "")
            sound: root.sound; bar: root.bar; animate: root.animate
            showVolume: false; showAudition: false
            detailsOpen: root.detailsOpen; helpOpen: root.helpOpen
            onDetailsOpenChanged: root.detailsOpen = detailsOpen
            onHelpOpenChanged: root.helpOpen = helpOpen
            canAudition: root.canAudition; auditioning: root.auditioning
            foreground: root.foreground; fontFamily: root.fontFamily
            onVolumeEdited: function(value) { root.volumeEdited(value) }
            onLayerEdited: function(key,value) { root.layerEdited(key,value) }
            onPresetRequested: function(preset) { root.presetRequested(preset) }
            onAuditionRequested: root.auditionRequested()
            onFocusRequested: function(item) { root.focusRequested(item) }
          }
        }
      }
    }
  }
  Rectangle {
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    height: 1; color: Qt.alpha(root.foreground, 0.08)
  }
}
