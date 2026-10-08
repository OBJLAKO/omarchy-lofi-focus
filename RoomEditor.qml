import QtQuick
import qs.Commons

// The overall scene complements the compact cards. Both use one selected ID.
Column {
  id: root
  property alias stageItem: stage
  property alias sourceIds: stage.sourceIds
  property var layers: []
  property var options: []
  property string selectedId: ""
  property var room: ({preset:"cozy",size:35,softness:55,reflections:25})
  property bool animate: true
  property bool canAudition: false
  property string auditionId: ""
  property Item popupBoundary: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property var currentLayer: layers.find(function(layer) { return layer.id === root.selectedId }) || layers[0] || ({})
  signal selected(string id)
  signal layerEdited(string id, string key, string value)
  signal volumeEdited(string id, int value)
  signal presetRequested(string id, string preset)
  signal auditionRequested(string id)
  signal positionEdited(string id, int pan, int distance)
  signal roomEdited(string key, int value)
  signal focusRequested(var item)
  spacing: Style.space(10)
  function close() {}
  function number(layer,key,fallback) { return stage.number(layer,key,fallback) }
  function depthText(value) { return value < 33 ? "Near" : value < 67 ? "Mid" : "Far" }
  function panText(value) { return Math.abs(value) < 15 ? "Center" : value < 0 ? "Left" : "Right" }
  function positionText(layer) { return (layer.outside ? "Outside · " : "") + depthText(number(layer,"distance",0)) + " · " + panText(number(layer,"pan",0)) }
  SkylofiStyle { id: visual; foreground: root.foreground }
  CoverageStage {
    id: stage
    objectName: "soundStage"
    width: parent.width; layers: root.layers; options: root.options; selectedId: root.selectedId
    foreground: root.foreground; fontFamily: root.fontFamily
    onSelected: function(id) { root.selected(id) }
    onPositionEdited: function(id,pan,distance) { root.positionEdited(id,pan,distance) }
    onFocusRequested: function(item) { root.focusRequested(item) }
  }
  Text {
    width: parent.width
    text: "Drag an icon to move a sound. Arrows adjust left/right and distance."
    wrapMode: Text.Wrap; color: visual.muted
    font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Flow {
    width: parent.width; spacing: Style.space(4)
    Repeater {
      model: stage.sourceIds
      SkylofiButton {
        required property var modelData
        objectName: "mapSelect-" + modelData
        text: stage.sourceName(modelData); selected: root.selectedId === modelData
        tooltipText: stage.sourceName(modelData)
        iconText: stage.sourceIcon(modelData); focusable: true; bordered: true
        fontSize: visual.caption; foreground: root.foreground; fontFamily: root.fontFamily
        horizontalPadding: Style.space(6); animate: root.animate
        width: Math.min(implicitWidth,root.width)
        clip: true
        Accessible.name: stage.sourceName(modelData)
        onClicked: root.selected(modelData)
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
  }
  Text {
    width: parent.width; text: stage.sourceName(root.currentLayer.id || "")
    color: root.foreground; elide: Text.ElideRight
    font.family: root.fontFamily; font.pixelSize: visual.body; font.weight: Font.DemiBold
  }
  SourceControls {
    objectName: "mapSourceControls"
    sound: root.currentLayer; bar: root.bar; animate: root.animate
    canAudition: root.canAudition; auditioning: root.auditionId === root.currentLayer.id
    foreground: root.foreground; fontFamily: root.fontFamily
    onVolumeEdited: function(value) { if (root.currentLayer.id) root.volumeEdited(root.currentLayer.id,value) }
    onLayerEdited: function(key,value) { if (root.currentLayer.id) root.layerEdited(root.currentLayer.id,key,value) }
    onPresetRequested: function(preset) { if (root.currentLayer.id) root.presetRequested(root.currentLayer.id,preset) }
    onAuditionRequested: if (root.currentLayer.id) root.auditionRequested(root.currentLayer.id)
    onFocusRequested: function(item) { root.focusRequested(item) }
  }
}
