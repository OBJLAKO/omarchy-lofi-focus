import QtQuick
import qs.Commons
import qs.Ui

// A left/right stage with depth. It deliberately makes no front/back claim.
// The backend owns DSP and gentle variation; this view has no polling timer.
Column {
  id: root
  property alias stageItem: stage
  property var layers: []
  property var options: []
  property string selectedId: ""
  property var room: ({preset:"cozy",size:35,softness:55,reflections:25})
  property bool animate: true
  property bool detailsOpen: false
  property Item popupBoundary: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property var currentLayer: layers.find(function(layer) { return layer.id === root.selectedId }) || layers[0] || ({})
  property var sourceIds: []
  property var sourceOptions: []
  signal selected(string id)
  signal layerEdited(string id, string key, string value)
  signal positionEdited(string id, int pan, int distance)
  signal roomEdited(string key, int value)
  signal focusRequested(var item)
  spacing: Style.space(10)
  onSelectedIdChanged: syncSelection()
  onLayersChanged: { syncSources(); syncSelection() }
  onOptionsChanged: syncSources()
  function syncSources() {
    var ids = layers.map(function(layer) { return layer.id })
    // Status updates include changing effective levels. Keep the visual
    // objects and mouse grab when the set of active sources stays the same.
    if (JSON.stringify(ids) !== JSON.stringify(sourceIds)) sourceIds = ids
    var choices = layers.map(function(layer) {
      var option = root.options.find(function(option) { return option.value === layer.id })
      return {value:layer.id,label:option ? option.label : layer.name || layer.id,description:root.positionText(layer)}
    })
    if (JSON.stringify(choices) !== JSON.stringify(sourceOptions)) sourceOptions = choices
  }
  function syncSelection() {
    var layer = layers.find(function(layer) { return layer.id === root.selectedId }) || layers[0]
    if (sourcePicker) sourcePicker.value = layer ? layer.id : ""
  }
  onVisibleChanged: if (!visible) sourcePicker.close()
  function close() { sourcePicker.close() }
  function number(layer, key, fallback) {
    var value = Number(layer[key])
    return layer[key] === undefined || !isFinite(value) ? fallback : value
  }
  function depthText(value) { return value < 33 ? "Near" : value < 67 ? "Mid" : "Far" }
  function panText(value) { return Math.abs(value) < 15 ? "Center" : value < 0 ? "Left" : "Right" }
  function positionText(layer) { return (layer.outside ? "Outside · " : "") + depthText(number(layer,"distance",35)) + " · " + panText(number(layer,"pan",0)) }
  function sourceName(id) {
    var option = options.find(function(option) { return option.value === id })
    return option ? option.label : id
  }
  function edit(key, value) {
    if (currentLayer.id) root.layerEdited(currentLayer.id, key, String(value))
  }
  SkylofiStyle { id: visual; foreground: root.foreground }
  Rectangle {
    id: stage
    objectName: "soundStage"
    width: parent.width; height: Style.space(170)
    radius: Math.min(Style.cornerRadius, Style.space(8))
    color: visual.surface; border.width: 1; border.color: visual.line; clip: true
    Rectangle {
      x: parent.width * 0.10; y: parent.height * 0.12
      width: parent.width * 0.80; height: parent.height * 0.73
      color: "transparent"; radius: root.room.preset === "outside" ? height / 2 : Style.space(7)
      border.width: 1; border.color: Qt.alpha(root.foreground, 0.15)
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter; y: Style.space(4)
      text: "Farther"; color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    Text {
      x: Style.space(8); y: parent.height - height - Style.space(5)
      text: "Left"; color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    Text {
      x: parent.width - width - Style.space(8); y: parent.height - height - Style.space(5)
      text: "Right"; color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    Column {
      x: parent.width / 2 - width / 2; y: parent.height * 0.79
      spacing: Style.space(2)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "\uf025"; color: Color.accent
        font.family: root.fontFamily; font.pixelSize: visual.iconSize
      }
      Text {
        text: "You"; color: visual.muted
        font.family: root.fontFamily; font.pixelSize: visual.caption
      }
    }
    Repeater {
      model: root.sourceIds
      Rectangle {
        id: marker
        required property var modelData
        readonly property var soundState: root.layers.find(function(layer) { return layer.id === marker.modelData }) || ({})
        property bool dragging: false
        property bool moved: false
        property point startPoint: Qt.point(0,0)
        property real draftPan: root.number(marker.soundState,"pan",0)
        property real draftDistance: root.number(marker.soundState,"distance",35)
        readonly property real pan: dragging ? draftPan : root.number(marker.soundState,"pan",0)
        readonly property real distance: dragging ? draftDistance : root.number(marker.soundState,"distance",35)
        readonly property bool diffuse: marker.soundState.diffuse === true || root.number(marker.soundState,"width",20) >= 60
        objectName: "source-" + modelData
        width: Math.min(Style.space(diffuse ? 120 : 104), stage.width * 0.38)
        height: Style.space(32)
        x: Math.max(Style.space(4), Math.min(stage.width - width - Style.space(4), stage.width * (0.5 + pan * 0.0038) - width / 2))
        y: Math.max(Style.space(22), Math.min(stage.height - height - Style.space(26), stage.height * (0.79 - distance * 0.0061) - height / 2))
        radius: diffuse ? height / 2 : Math.min(Style.cornerRadius, Style.space(6))
        color: root.selectedId === modelData ? visual.selected : Color.popups.background
        border.width: 1; border.color: root.selectedId === modelData || activeFocus ? Color.accent : visual.line
        z: dragging || root.selectedId === modelData ? 2 : 1
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.sourceName(modelData) + ", " + root.positionText(marker.soundState)
        Accessible.onPressAction: root.selected(modelData)
        Keys.onReturnPressed: root.selected(modelData)
        Keys.onSpacePressed: root.selected(modelData)
        Keys.onLeftPressed: root.positionEdited(modelData, Math.max(-100, pan - 5), distance)
        Keys.onRightPressed: root.positionEdited(modelData, Math.min(100, pan + 5), distance)
        Keys.onUpPressed: root.positionEdited(modelData, pan, Math.min(100, distance + 5))
        Keys.onDownPressed: root.positionEdited(modelData, pan, Math.max(0, distance - 5))
        Text {
          anchors.fill: parent; anchors.margins: Style.space(6)
          verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
          text: root.sourceName(marker.modelData); textFormat: Text.PlainText
          elide: Text.ElideRight; color: root.foreground
          font.family: root.fontFamily; font.pixelSize: visual.caption
        }
        MouseArea {
          anchors.fill: parent; preventStealing: true
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          onPressed: function(event) {
            marker.forceActiveFocus(); root.selected(marker.modelData)
            marker.draftPan = marker.pan; marker.draftDistance = marker.distance
            marker.startPoint = marker.mapToItem(stage,event.x,event.y)
            marker.moved = false; marker.dragging = true
          }
          onPositionChanged: function(event) {
            if (!pressed) return
            var point = marker.mapToItem(stage,event.x,event.y)
            if (!marker.moved && Math.abs(point.x - marker.startPoint.x) < 3 && Math.abs(point.y - marker.startPoint.y) < 3) return
            marker.moved = true
            marker.draftPan = Math.max(-100,Math.min(100,(point.x / stage.width - 0.5) / 0.0038))
            marker.draftDistance = Math.max(0,Math.min(100,(0.79 - point.y / stage.height) / 0.0061))
          }
          onReleased: {
            var id = marker.modelData, pan = Math.round(marker.draftPan), distance = Math.round(marker.draftDistance)
            var moved = marker.moved
            marker.dragging = false
            if (moved) root.positionEdited(id,pan,distance)
          }
          onCanceled: marker.dragging = false
        }
        onActiveFocusChanged: if (activeFocus) { root.selected(modelData); root.focusRequested(this) }
      }
    }
  }
  Text {
    width: parent.width
    text: "Drag a sound, or use the position controls."
    wrapMode: Text.Wrap; color: visual.muted
    font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  FocusDropdown {
    id: sourcePicker
    objectName: "spaceSourcePicker"
    width: parent.width; showLabel: false; label: "Sound to place"
    options: root.sourceOptions; value: root.currentLayer.id || ""
    popupBoundary: root.popupBoundary; animate: root.animate
    foreground: root.foreground; fontFamily: root.fontFamily
    placeholderText: "Find an active sound"
    onChanged: function(value) { root.selected(value) }
    onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
  }
  Text {
    width: parent.width
    text: root.currentLayer.diffuse === true || root.number(root.currentLayer,"width",20) >= 60 ? "Atmosphere · broad sound" : "Object · local sound"
    color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  SpatialSlider {
    objectName: "spaceDistance"
    label: "Distance"; value: root.number(root.currentLayer,"distance",35)
    suffix: root.depthText(value)
    onEdited: function(value) { root.edit("distance",value) }
  }
  SpatialSlider {
    objectName: "spacePan"
    label: "Position"; minimum: -100; value: root.number(root.currentLayer,"pan",0)
    suffix: root.panText(value)
    onEdited: function(value) { root.edit("pan",value) }
  }
  SkylofiButton {
    objectName: "spaceDetailsButton"
    width: parent.width
    text: root.detailsOpen ? "Hide detailed acoustics" : "Detailed acoustics"
    leftAlign: true; iconText: root.detailsOpen ? "\uf107" : "\uf105"
    foreground: visual.muted; fontFamily: root.fontFamily; fontSize: visual.label
    horizontalPadding: Style.space(2); verticalPadding: 0
    animate: root.animate; focusable: true
    onClicked: root.detailsOpen = !root.detailsOpen
  }
  Column {
    width: parent.width; spacing: Style.space(10); visible: root.detailsOpen
    Row {
      width: parent.width; spacing: Style.space(8)
      Text {
        width: parent.width - outsideToggle.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: "Outside the room"; wrapMode: Text.Wrap
        color: root.foreground; font.family: root.fontFamily; font.pixelSize: visual.label
      }
      SkylofiSwitch {
        id: outsideToggle
        objectName: "spaceOutside"
        checked: root.currentLayer.outside === true; animate: root.animate
        foreground: root.foreground; Accessible.name: "Outside the room"
        onToggled: root.edit("outside",checked ? "off" : "on")
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
    Row {
      width: parent.width; spacing: Style.space(8)
      Text {
        width: parent.width - layerLivingToggle.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: "Vary this sound"; wrapMode: Text.Wrap
        color: root.foreground; font.family: root.fontFamily; font.pixelSize: visual.label
      }
      SkylofiSwitch {
        id: layerLivingToggle
        objectName: "spaceLiving"
        checked: root.currentLayer.living !== false; animate: root.animate
        foreground: root.foreground; Accessible.name: "Vary this sound with Living mix"
        onToggled: root.edit("living",checked ? "off" : "on")
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
    Repeater {
      model: [{key:"width",label:"Sound width",fallback:20},{key:"softness",label:"Muffling",fallback:35},{key:"reflections",label:"Reflections",fallback:25},{key:"echo",label:"Echo",fallback:0}]
      SpatialSlider {
        required property var modelData
        objectName: "space-" + modelData.key
        label: modelData.label; value: root.number(root.currentLayer,modelData.key,modelData.fallback)
        suffix: Math.round(value) + "%"
        onEdited: function(value) { root.edit(modelData.key,value) }
      }
    }
    Text {
      width: parent.width; text: "Shared room"
      color: root.foreground; font.family: root.fontFamily; font.pixelSize: visual.label; font.weight: Font.DemiBold
    }
    Repeater {
      model: [{key:"size",label:"Room size",fallback:35},{key:"softness",label:"Soft furnishings",fallback:55},{key:"reflections",label:"Room reflections",fallback:25}]
      SpatialSlider {
        required property var modelData
        objectName: "room-" + modelData.key
        label: modelData.label; value: root.number(root.room,modelData.key,modelData.fallback)
        suffix: Math.round(value) + "%"
        onEdited: function(value) { root.roomEdited(modelData.key,value) }
      }
    }
  }
  component SpatialSlider: Column {
    id: row
    property string label: ""
    property real value: 0
    property real minimum: 0
    property string suffix: ""
    signal edited(int value)
    width: parent.width; spacing: Style.space(2)
    Row {
      width: parent.width
      Text {
        width: parent.width - output.width
        text: row.label; color: root.foreground
        font.family: root.fontFamily; font.pixelSize: visual.label
        elide: Text.ElideRight
      }
      Text {
        id: output
        width: Style.space(60); text: row.suffix
        horizontalAlignment: Text.AlignRight; color: visual.muted
        font.family: root.fontFamily; font.pixelSize: visual.caption
      }
    }
    SkylofiSlider {
      objectName: "spatialSlider"
      width: parent.width; height: Style.space(30)
      bar: root.bar; minimum: row.minimum; maximum: 100; step: 5; integer: true
      value: row.value; animate: root.animate
      trackColor: visual.sliderTrack; fillColor: Color.accent; knobColor: Color.accent
      activeFocusOnTab: true; Accessible.role: Accessible.Slider; Accessible.name: row.label
      Keys.onLeftPressed: row.edited(Math.max(row.minimum,row.value - 5))
      Keys.onRightPressed: row.edited(Math.min(100,row.value + 5))
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Home) { row.edited(row.minimum); event.accepted = true }
        else if (event.key === Qt.Key_End) { row.edited(100); event.accepted = true }
      }
      onReleased: function(value) { row.edited(value) }
      onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    }
  }
}
