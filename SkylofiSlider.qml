// Adapted from Omarchy shell/Ui/PanelSlider.qml.
// https://github.com/basecamp/omarchy
// Copyright (c) David Heinemeier Hansson
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  // Wheel adjusts a level only after explicit focus. Otherwise a scroll
  // gesture passes through to the tab body instead of changing the mix.
  property bool animate: true
  onAnimateChanged: if (!animate) { fillFeedback.complete(); positionFeedback.complete(); hoverFeedback.complete() }
  onVisibleChanged: if (!visible) { fillFeedback.complete(); positionFeedback.complete(); hoverFeedback.complete() }

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  // Qt's accessible value interface uses these names for custom sliders.
  readonly property real minimumValue: minimum
  readonly property real maximumValue: maximum
  readonly property real stepSize: step
  Accessible.role: Accessible.Slider
  Accessible.focusable: enabled
  Accessible.onIncreaseAction: if (enabled) root.commit(root.liveValue + root.step)
  Accessible.onDecreaseAction: if (enabled) root.commit(root.liveValue - root.step)
  property bool integer: false
  property color trackColor: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "#333"
  property color fillColor: bar ? bar.foreground : Color.foreground
  property color knobColor: bar ? bar.foreground : Color.foreground
  property bool dragging: false
  property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
  property real liveValue: value
  // Latest-value throttle, not a restart-only debounce: audio follows a long
  // drag at a bounded rate. Release flushes the exact last value immediately.
  property int updateInterval: 60
  property bool localValueHeld: false
  property real pendingValue: value
  property real lastEditedValue: value
  property bool editPending: false

  // macOS-style notches. When > 1, that many evenly-spaced tick marks are cut
  // into the track (drawn in the panel background color, so only the part
  // crossing the track shows). Purely visual — snapping is the caller's job via
  // `integer`/`step` or an index-based value. Default 0 leaves the track plain.
  property int tickCount: 0
  property color tickColor: bar ? bar.background : Color.background

  onValueChanged: if (!dragging && !localValueHeld) { liveValue = value; lastEditedValue = value }
  readonly property real displayValue: liveValue
  function bounded(value) {
    var result = Math.max(minimum,Math.min(maximum,Number(value)))
    return integer ? Math.round(result) : result
  }
  function flushEdit() {
    liveUpdate.stop()
    if (!editPending) return
    editPending = false
    if (Math.abs(pendingValue - lastEditedValue) > 0.0001) {
      lastEditedValue = pendingValue
      root.edited(pendingValue)
    }
  }
  function queueEdit(value) {
    pendingValue = bounded(value); editPending = true
    if (!liveUpdate.running) liveUpdate.start()
  }
  function commit(value) {
    liveValue = bounded(value); localValueHeld = true; valueHold.restart()
    pendingValue = liveValue; editPending = true; flushEdit()
  }
  Timer { id: liveUpdate; interval: root.updateInterval; onTriggered: root.flushEdit() }
  Timer {
    id: valueHold; interval: 300
    onTriggered: { root.localValueHeld = false; if (!root.dragging) { root.liveValue = root.value; root.lastEditedValue = root.value } }
  }
  Keys.onLeftPressed: root.commit(root.liveValue - root.step)
  Keys.onRightPressed: root.commit(root.liveValue + root.step)
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Home) { root.commit(root.minimum); event.accepted = true }
    else if (event.key === Qt.Key_End) { root.commit(root.maximum); event.accepted = true }
  }

  signal moved(real value)
  signal edited(real value)
  signal released(real value)

  // Right-click is a secondary action on the whole track — audio uses it to
  // mute the channel the slider belongs to. Dragging stays left-button only.
  signal rightClicked()

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.md)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property bool _hot: mouseArea.containsMouse || root.dragging || root.activeFocus
  // Keep the thumb's hover enlargement and the focus stroke inside the hit
  // target. Painting outside the item makes a clipped page cut off the outline
  // and makes the slider look attached to the caption or row above it.
  readonly property real horizontalInset: Math.min(width / 2, Math.ceil(knobSize * 1.08 / 2) + Style.space(3))

  Rectangle {
    id: track
    objectName: "sliderTrack"
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.horizontalInset
    anchors.rightMargin: root.horizontalInset
    height: root.trackHeight
    radius: height / 2
    color: root.trackColor
  }

  Rectangle {
    id: fill
    anchors.verticalCenter: track.verticalCenter
    anchors.left: track.left
    height: track.height
    radius: track.radius
    color: root.fillColor
    width: track.width * root.progress

    Behavior on width {
      enabled: root.animate && root.visible && !root.dragging
      NumberAnimation { id: fillFeedback; duration: 120; easing.type: Easing.OutCubic }
    }
  }

  Repeater {
    model: root.tickCount > 1 ? root.tickCount : 0
    Rectangle {
      required property int index
      width: Math.max(1, Style.space(2))
      height: root.trackHeight + Style.space(4)
      radius: 1
      color: root.tickColor
      anchors.verticalCenter: track.verticalCenter
      x: track.x + Math.max(0, Math.min(track.width - width,
                              track.width * (index / (root.tickCount - 1)) - width / 2))
    }
  }

  BorderSurface {
    id: knob
    objectName: "sliderThumb"
    width: root.knobSize
    height: root.knobSize
    radius: root.knobSize / 2
    color: root.knobColor
    borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
    anchors.verticalCenter: track.verticalCenter
    x: track.x + track.width * root.progress - width / 2
    scale: root._hot ? 1.08 : 1.0

    Behavior on x {
      enabled: root.animate && root.visible && !root.dragging
      NumberAnimation { id: positionFeedback; duration: 120; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      enabled: root.animate && root.visible
      NumberAnimation { id: hoverFeedback; duration: 100; easing.type: Easing.OutCubic }
    }
  }

  Rectangle {
    objectName: "sliderFocusOutline"
    anchors.fill: parent; anchors.margins: Style.space(1)
    color: "transparent"
    radius: Style.cornerRadius
    border.color: Color.accent
    border.width: root.activeFocus ? 1 : 0
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    // A small vertical excursion must not let the surrounding Flickable
    // steal an active volume/seek drag. MouseArea keeps its grab until release,
    // including pointer positions outside the track and the slider bounds.
    preventStealing: true

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x - track.x))
      var raw = root.minimum + (clamped / Math.max(1, track.width)) * root.range
      if (root.integer) raw = Math.round(raw)
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.forceActiveFocus(Qt.MouseFocusReason)
      valueHold.stop(); root.localValueHeld = false
      root.lastEditedValue = root.value
      root.dragging = true
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
      root.queueEdit(next)
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.rightClicked()
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
      root.queueEdit(next)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.localValueHeld = true; valueHold.restart()
      root.pendingValue = root.liveValue; root.editPending = true; root.flushEdit()
      root.released(root.liveValue)
    }
    onCanceled: {
      root.dragging = false
      root.localValueHeld = true; valueHold.restart(); root.flushEdit()
    }
    onWheel: function(wheel) {
      if (!root.activeFocus) { wheel.accepted = false; return }
      var delta = wheel.angleDelta.y > 0 ? root.step : -root.step
      var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + delta))
      if (root.integer) next = Math.round(next)
      root.commit(next)
      root.moved(next)
      root.released(next)
    }
  }
}
