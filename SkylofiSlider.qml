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
  property bool integer: false
  property color trackColor: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "#333"
  property color fillColor: bar ? bar.foreground : Color.foreground
  property color knobColor: bar ? bar.foreground : Color.foreground
  property bool dragging: false
  property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
  property real liveValue: value

  // macOS-style notches. When > 1, that many evenly-spaced tick marks are cut
  // into the track (drawn in the panel background color, so only the part
  // crossing the track shows). Purely visual — snapping is the caller's job via
  // `integer`/`step` or an index-based value. Default 0 leaves the track plain.
  property int tickCount: 0
  property color tickColor: bar ? bar.background : Color.background

  onValueChanged: if (!dragging) liveValue = value

  signal moved(real value)
  signal released(real value)

  // Right-click is a secondary action on the whole track — audio uses it to
  // mute the channel the slider belongs to. Dragging stays left-button only.
  signal rightClicked()

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.md)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property bool _hot: mouseArea.containsMouse || root.dragging || root.activeFocus

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
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
      x: Math.max(0, Math.min(track.width - width,
                              track.width * (index / (root.tickCount - 1)) - width / 2))
    }
  }

  BorderSurface {
    id: knob
    width: root.knobSize
    height: root.knobSize
    radius: root.knobSize / 2
    color: root.knobColor
    borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
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
    anchors.fill: parent; anchors.margins: -2
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

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x))
      var raw = root.minimum + (clamped / track.width) * root.range
      if (root.integer) raw = Math.round(raw)
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.forceActiveFocus(Qt.MouseFocusReason)
      root.dragging = true
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.rightClicked()
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onCanceled: { root.dragging = false; root.liveValue = root.value }
    onWheel: function(wheel) {
      if (!root.activeFocus) { wheel.accepted = false; return }
      var delta = wheel.angleDelta.y > 0 ? root.step : -root.step
      var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + delta))
      if (root.integer) next = Math.round(next)
      root.liveValue = next
      root.moved(next)
      root.released(next)
    }
  }
}
