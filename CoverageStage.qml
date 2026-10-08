import QtQuick
import qs.Commons

// Coverage is a diffuse stereo field, not a front/back coordinate. No timers,
// Canvas repaint loop or animation on the audio status updates.
Rectangle {
  id: root
  property var layers: []
  property var options: []
  property string selectedId: ""
  property bool interactive: true
  property bool mini: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var sourceIds: []
  property var markerLayout: ({})
  readonly property real markerSize: Style.space(root.mini ? 28 : 36)
  readonly property int layoutColumns: Math.max(1,Math.floor((width - markerSize - Style.space(8)) / (markerSize + Style.space(5))) + 1)
  signal selected(string id)
  signal positionEdited(string id, int pan, int distance)
  signal focusRequested(var item)
  onLayersChanged: {
    var ids = layers.map(function(layer) { return layer.id })
    // Keep the same marker and mouse grab while effective levels change.
    if (JSON.stringify(ids) !== JSON.stringify(sourceIds)) sourceIds = ids
    updateLayout()
  }
  onWidthChanged: updateLayout()
  onHeightChanged: updateLayout()
  function number(layer,key,fallback) {
    var value = Number(layer[key])
    return layer[key] === undefined || !isFinite(value) ? fallback : value
  }
  function sourceName(id) {
    var option = options.find(function(option) { return option.value === id })
    return option ? option.label : id
  }
  function sourceIcon(id) {
    if (/fire|bonfire/.test(id)) return "\uf06d"
    if (/rain|storm/.test(id)) return "\uf0c2"
    if (/wind/.test(id)) return "\u224b"
    if (/river|water|ocean|stream/.test(id)) return "\uf043"
    if (/forest|leaves/.test(id)) return "\uf1bb"
    return "\uf001"
  }
  function coverageText(value) { return value < 25 ? "Point" : value < 75 ? "Wide" : "Surrounding" }
  function centerX(pan) { return width / 2 + pan * (width / 2 - Style.space(24)) / 100 }
  function centerY(distance) { return height * (root.mini ? 0.49 - distance * 0.0032 : 0.63 - distance * 0.0045) }
  function mapHeight() {
    if (mini) return Style.space(112)
    var size = markerSize, inset = size / 2 + Style.space(4), top = Style.space(28) + size / 2
    var step = size + Style.space(5), columns = layoutColumns
    var result = Style.space(width < Style.space(280) ? 230 : 260)
    var clearance = size / 2 + Style.space(24)
    // Account for the headphone hit area too. Large fonts on a narrow panel
    // need more rows; ordinary scenes retain the compact map height.
    function capacity(mapHeight) {
      var bottom = Math.max(top,mapHeight - size / 2 - Style.space(28))
      var rows = Math.max(1,Math.floor((bottom - top) / step) + 1), count = 0
      for (var row = 0; row < rows; row++) for (var col = 0; col < columns; col++) {
        var x = columns === 1 ? width / 2 : inset + col * (width - inset * 2) / (columns - 1)
        var y = rows === 1 ? (top + bottom) / 2 : top + row * (bottom - top) / (rows - 1)
        if (Math.abs(x - width / 2) >= clearance || Math.abs(y - mapHeight * 0.80) >= clearance) count++
      }
      return count
    }
    while (capacity(result) < sourceIds.length && result < Style.space(1400)) result += step
    return result
  }
  function updateLayout() {
    if (width <= 0 || height <= 0) return
    var inset = markerSize / 2 + Style.space(4)
    var top = root.mini ? inset : Style.space(28) + markerSize / 2
    var bottom = Math.max(top,height - markerSize / 2 - Style.space(28))
    var step = markerSize + Style.space(5), slots = [], anchors = []
    var columns = Math.max(1,Math.floor((width - inset * 2) / step) + 1)
    var rows = Math.max(1,Math.floor((bottom - top) / step) + 1)
    function awayFromListener(point) {
      var clearance = markerSize / 2 + Style.space(root.mini ? 15 : 21) + Style.space(3)
      return Math.abs(point.x - width / 2) >= clearance || Math.abs(point.y - height * 0.80) >= clearance
    }
    for (var row = 0; row < rows; row++) for (var col = 0; col < columns; col++) {
      var slot = {x:columns === 1 ? width / 2 : inset + col * (width - inset * 2) / (columns - 1),
        y:rows === 1 ? (top + bottom) / 2 : top + row * (bottom - top) / (rows - 1)}
      if (awayFromListener(slot)) slots.push(slot)
    }
    for (var sound of layers) anchors.push({id:sound.id,
      x:Math.max(inset,Math.min(width - inset,centerX(number(sound,"pan",0)))),
      y:Math.max(top,Math.min(bottom,centerY(number(sound,"distance",0))))})
    function available(point,used) {
      return awayFromListener(point) && !used.some(function(other) { return Math.abs(point.x - other.x) < step && Math.abs(point.y - other.y) < step })
    }
    function nearest(anchor,choices) {
      return choices.slice().sort(function(a,b) {
        return (a.x-anchor.x)*(a.x-anchor.x)+(a.y-anchor.y)*(a.y-anchor.y)
          - (b.x-anchor.x)*(b.x-anchor.x)-(b.y-anchor.y)*(b.y-anchor.y)
      })
    }
    var result = {}, used = [], crowded = false
    for (var anchor of anchors) {
      var choices = [anchor].concat(nearest(anchor,slots))
      var choice = choices.find(function(point) { return available(point,used) })
      if (!choice) { crowded = true; break }
      used.push(choice); result[anchor.id] = {x:choice.x,y:choice.y,dx:choice.x-anchor.x,dy:choice.y-anchor.y}
    }
    // Dense legacy scenes may have every source at the same coordinate. A
    // fixed grid guarantees distinct hit targets without rewriting positions.
    if (crowded) {
      result = {}; var free = slots.slice()
      for (var anchor of anchors) {
        var choice = nearest(anchor,free)[0] || anchor
        free = free.filter(function(slot) { return slot !== choice })
        result[anchor.id] = {x:choice.x,y:choice.y,dx:choice.x-anchor.x,dy:choice.y-anchor.y}
      }
    }
    markerLayout = result
  }
  SkylofiStyle { id: visual; foreground: root.foreground }
  height: root.mapHeight()
  radius: Math.min(Style.cornerRadius, Style.space(10))
  color: visual.surface; border.width: 1; border.color: visual.line; clip: true
  Repeater {
    model: 2
    Rectangle {
      required property int index
      width: root.width * (index === 0 ? 0.52 : 0.88)
      height: root.height * (index === 0 ? 0.42 : 0.75)
      x: (root.width - width) / 2; y: root.height * 0.50 - height / 2
      radius: width / 2; color: "transparent"
      border.width: 1; border.color: Qt.alpha(root.foreground,0.09)
    }
  }
  Repeater {
    model: root.sourceIds
    Rectangle {
      required property var modelData
      readonly property var soundState: root.layers.find(function(layer) { return layer.id === modelData }) || ({})
      readonly property real amount: Math.max(0,Math.min(100,root.number(soundState,"coverage",50))) / 100
      readonly property real pan: root.number(soundState,"pan",0)
      readonly property real distance: root.number(soundState,"distance",0)
      objectName: "coverage-" + modelData
      width: Style.space(16) + amount * (root.width * 0.90 - Style.space(16))
      height: Style.space(16) + amount * (root.height * 0.78 - Style.space(16))
      x: root.centerX(pan) * (1 - amount) + root.width / 2 * amount - width / 2
      y: root.centerY(distance) * (1 - amount) + root.height * 0.50 * amount - height / 2
      radius: width / 2
      color: Qt.alpha(Color.accent,root.selectedId === modelData ? 0.11 : 0.035)
      border.width: Math.max(1,Style.space(2) + amount * Style.space(8))
      border.color: Qt.alpha(Color.accent,root.selectedId === modelData ? 0.28 : 0.10)
      opacity: amount > 0.01 ? 1 : 0
    }
  }
  Text {
    x: Style.space(10); y: Style.space(8)
    width: root.width - Style.space(20)
    text: root.mini ? "" : root.sourceName(root.selectedId)
    visible: text.length > 0; elide: Text.ElideRight
    color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Repeater {
    model: root.sourceIds
    Rectangle {
      required property var modelData
      readonly property var point: root.markerLayout[modelData] || ({x:0,y:0,dx:0,dy:0})
      x: point.x - point.dx; y: point.y - point.dy
      width: Math.sqrt(point.dx * point.dx + point.dy * point.dy); height: 1
      rotation: Math.atan2(point.dy,point.dx) * 180 / Math.PI
      transformOrigin: Item.Left
      color: Qt.alpha(root.foreground,root.selectedId === modelData ? 0.30 : 0.14)
      visible: width > Style.space(3); z: 2
    }
  }
  Text {
    anchors.horizontalCenter: parent.horizontalCenter; y: Style.space(8)
    text: "Farther"; visible: !root.mini && root.selectedId.length === 0
    color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Rectangle {
    width: Style.space(root.mini ? 30 : 42); height: width; radius: width / 2
    x: (root.width - width) / 2; y: root.height * 0.80 - height / 2
    color: Color.popups.background; border.width: 1; border.color: visual.line; z: 2
    Text {
      anchors.centerIn: parent; text: "\uf025"; color: Color.accent
      font.family: root.fontFamily; font.pixelSize: visual.iconSize
    }
  }
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height - height - Style.space(4)
    text: "You"; visible: !root.mini
    color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Text {
    x: Style.space(10); y: parent.height - height - Style.space(5)
    text: "Left"; color: visual.quiet
    font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Text {
    x: parent.width - width - Style.space(10); y: parent.height - height - Style.space(5)
    text: "Right"; color: visual.quiet
    font.family: root.fontFamily; font.pixelSize: visual.caption
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
      property point dragOffset: Qt.point(0,0)
      property real startPan: 0
      property real startDistance: 0
      property real draftPan: root.number(soundState,"pan",0)
      property real draftDistance: root.number(soundState,"distance",0)
      readonly property real pan: dragging ? draftPan : root.number(soundState,"pan",0)
      readonly property real distance: dragging ? draftDistance : root.number(soundState,"distance",0)
      readonly property var visualPoint: root.markerLayout[modelData] || ({x:root.centerX(pan),y:root.centerY(distance),dx:0,dy:0})
      objectName: "source-" + modelData
      width: root.markerSize; height: width; radius: width / 2
      x: Math.max(Style.space(4),Math.min(root.width - width - Style.space(4),(dragging ? root.centerX(pan) + dragOffset.x : visualPoint.x) - width / 2))
      y: Math.max(Style.space(root.mini ? 4 : 28),Math.min(root.height - height - Style.space(24),(dragging ? root.centerY(distance) + dragOffset.y : visualPoint.y) - height / 2))
      color: root.selectedId === modelData ? visual.selected : Color.popups.background
      border.width: 1; border.color: root.selectedId === modelData || activeFocus ? Color.accent : visual.line
      z: dragging || root.selectedId === modelData ? 4 : 3
      activeFocusOnTab: root.interactive
      Accessible.role: Accessible.Button
      Accessible.ignored: !root.interactive
      Accessible.name: root.sourceName(modelData)
      Accessible.description: "Use arrows to change left/right position and distance"
      Accessible.onPressAction: root.selected(modelData)
      Keys.onReturnPressed: root.selected(modelData)
      Keys.onSpacePressed: root.selected(modelData)
      Keys.onLeftPressed: if (root.interactive) root.positionEdited(modelData,Math.max(-100,pan - 5),distance)
      Keys.onRightPressed: if (root.interactive) root.positionEdited(modelData,Math.min(100,pan + 5),distance)
      Keys.onUpPressed: if (root.interactive) root.positionEdited(modelData,pan,Math.min(100,distance + 5))
      Keys.onDownPressed: if (root.interactive) root.positionEdited(modelData,pan,Math.max(0,distance - 5))
      Text {
        anchors.centerIn: parent; text: root.sourceIcon(marker.modelData)
        color: root.selectedId === marker.modelData ? Color.accent : root.foreground
        font.family: root.fontFamily; font.pixelSize: visual.iconSize
      }
      MouseArea {
        anchors.fill: parent; enabled: root.interactive; preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: function(event) {
          marker.forceActiveFocus(); root.selected(marker.modelData)
          marker.draftPan = marker.pan; marker.draftDistance = marker.distance
          marker.startPan = marker.pan; marker.startDistance = marker.distance
          marker.dragOffset = Qt.point(marker.visualPoint.dx,marker.visualPoint.dy)
          marker.startPoint = marker.mapToItem(root,event.x,event.y)
          marker.moved = false; marker.dragging = true
        }
        onPositionChanged: function(event) {
          if (!pressed) return
          var point = marker.mapToItem(root,event.x,event.y)
          if (!marker.moved && Math.abs(point.x - marker.startPoint.x) < 3 && Math.abs(point.y - marker.startPoint.y) < 3) return
          marker.moved = true
          marker.draftPan = Math.max(-100,Math.min(100,marker.startPan + (point.x - marker.startPoint.x) / Math.max(1,root.width / 2 - Style.space(24)) * 100))
          marker.draftDistance = Math.max(0,Math.min(100,marker.startDistance - (point.y - marker.startPoint.y) / root.height / 0.0045))
        }
        onReleased: {
          var moved = marker.moved, id = marker.modelData
          var pan = Math.round(marker.draftPan), distance = Math.round(marker.draftDistance)
          marker.dragging = false
          if (moved) root.positionEdited(id,pan,distance)
        }
        onCanceled: marker.dragging = false
      }
      onActiveFocusChanged: if (activeFocus) { root.selected(modelData); root.focusRequested(this) }
    }
  }
}
