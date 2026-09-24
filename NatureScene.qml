import QtQuick

// A small, quiet window onto the enabled sounds. Paint only while audible
// and visible; no particle emitters or offscreen animation in the shell.
Canvas {
  id: scene
  property color foreground: "white"
  property color accent: foreground
  property string sounds: ""
  property bool playing: false
  property real phase: 0
  readonly property bool animate: visible && playing && sounds.length > 0
  readonly property bool rain: sounds.indexOf("rain") >= 0 || sounds.indexOf("tent") >= 0 || sounds.indexOf("storm") >= 0
  readonly property bool wind: sounds.indexOf("wind") >= 0
  readonly property bool storm: sounds.indexOf("storm") >= 0 || sounds.indexOf("thunder") >= 0
  readonly property bool fire: sounds.indexOf("fire") >= 0
  readonly property bool water: sounds.indexOf("wave") >= 0 || sounds.indexOf("stream") >= 0
  readonly property bool forest: sounds.indexOf("forest") >= 0 || sounds.indexOf("bird") >= 0 || sounds.indexOf("night") >= 0
  readonly property bool birds: sounds.indexOf("bird") >= 0
  readonly property bool night: sounds.indexOf("night") >= 0
  readonly property bool tent: sounds.indexOf("tent") >= 0

  onSoundsChanged: requestPaint()
  onPlayingChanged: requestPaint()
  onForegroundChanged: requestPaint()
  onAccentChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onVisibleChanged: if (visible) requestPaint()

  Timer {
    interval: 40
    running: scene.animate
    repeat: true
    onTriggered: {
      scene.phase = (scene.phase + 0.04) % 120
      scene.requestPaint()
    }
  }

  onPaint: {
    var c = getContext("2d")
    c.reset()
    if (width <= 0 || height <= 0) return
    c.scale(width / 400, height / 48)
    c.lineCap = "round"
    c.lineJoin = "round"
    c.strokeStyle = foreground
    c.fillStyle = foreground
    c.lineWidth = 1
    var t = phase
    var level = playing && sounds.length > 0 ? 1 : 0.4

    // A faint horizon grounds the scene, even while the mix is paused.
    c.globalAlpha = 0.12 * level
    c.beginPath(); c.moveTo(0, 42)
    c.bezierCurveTo(70, 38, 90, 45, 155, 42)
    c.bezierCurveTo(230, 36, 300, 46, 400, 41); c.stroke()

    if (rain) {
      for (var i = 0; i < 22; i++) {
        var drop = (t * 0.43 + i * 0.618) % 1
        var x = (i * 61 + 13) % 400 - drop * (wind ? 12 : 3)
        var y = drop * 48
        c.globalAlpha = (0.1 + Math.sin(drop * Math.PI) * 0.24) * level
        c.beginPath(); c.moveTo(x, y)
        c.lineTo(x - (wind ? 2.5 : 0.5), y + 3); c.stroke()
      }
    }

    if (wind) {
      for (var w = 0; w < 4; w++) {
        var drift = (t * 0.09 + w * 0.25) % 1
        var wx = drift * 470 - 70
        var wy = 10 + w * 8
        c.globalAlpha = Math.sin(drift * Math.PI) * 0.24 * level
        c.beginPath(); c.moveTo(wx, wy)
        c.bezierCurveTo(wx + 15, wy - 3, wx + 30, wy + 3, wx + 47, wy); c.stroke()
      }
    }

    if (water) {
      c.globalAlpha = 0.28 * level
      for (var wave = 0; wave < 3; wave++) {
        c.beginPath()
        for (var px = 0; px <= 400; px += 4) {
          var py = 33 + wave * 4 + Math.sin(px / 25 + t * 0.55 + wave) * 1.8
          if (px === 0) c.moveTo(px, py); else c.lineTo(px, py)
        }
        c.stroke()
      }
    }

    if (forest) {
      c.globalAlpha = 0.26 * level
      for (var tree = 0; tree < 3; tree++) {
        var tx = 34 + tree * 18
        var ty = tree === 1 ? 11 : 18
        c.beginPath(); c.moveTo(tx, 42); c.lineTo(tx, ty)
        c.moveTo(tx - 7, ty + 10); c.lineTo(tx, ty + 3); c.lineTo(tx + 7, ty + 10)
        c.moveTo(tx - 9, ty + 18); c.lineTo(tx, ty + 9); c.lineTo(tx + 9, ty + 18); c.stroke()
      }
      for (var mote = 0; mote < 5; mote++) {
        var mx = 100 + mote * 54 + Math.sin(t * 0.3 + mote) * 5
        var my = 12 + (mote % 3) * 9 + Math.cos(t * 0.4 + mote) * 3
        c.globalAlpha = (0.16 + 0.1 * Math.sin(t * 0.7 + mote * 2)) * level
        c.beginPath(); c.arc(mx, my, 1, 0, Math.PI * 2); c.fill()
      }
    }

    if (birds) {
      c.globalAlpha = 0.35 * level
      for (var bird = 0; bird < 2; bird++) {
        var bx = (t * 4 + bird * 35) % 350 + 25
        var by = 12 + bird * 6 + Math.sin(t * 0.5 + bird) * 2
        c.beginPath(); c.moveTo(bx - 4, by - 1)
        c.quadraticCurveTo(bx - 2, by - 3, bx, by)
        c.quadraticCurveTo(bx + 2, by - 3, bx + 4, by - 1); c.stroke()
      }
    }

    if (night) {
      c.globalAlpha = 0.4 * level
      c.beginPath(); c.moveTo(360, 6)
      c.bezierCurveTo(352, 5, 349, 17, 357, 20)
      c.bezierCurveTo(362, 22, 366, 18, 367, 15)
      c.bezierCurveTo(359, 17, 356, 11, 360, 6); c.stroke()
    }

    if (tent) {
      c.globalAlpha = 0.52 * level
      c.beginPath(); c.moveTo(154, 41); c.lineTo(174, 16); c.lineTo(198, 41)
      c.lineTo(154, 41); c.moveTo(174, 16); c.lineTo(211, 23); c.lineTo(230, 41)
      c.lineTo(198, 41); c.moveTo(169, 41); c.lineTo(175, 28); c.lineTo(184, 41); c.stroke()
    }

    if (storm) {
      // Slow cloud movement and a steady bolt, never a flashing background.
      var cx = 295 + Math.sin(t * 0.25) * 4
      c.globalAlpha = 0.35 * level
      c.beginPath(); c.moveTo(cx - 20, 20)
      c.bezierCurveTo(cx - 31, 20, cx - 30, 9, cx - 20, 10)
      c.bezierCurveTo(cx - 17, 0, cx - 3, 1, cx, 10)
      c.bezierCurveTo(cx + 13, 4, cx + 24, 13, cx + 18, 20)
      c.closePath(); c.stroke()
      c.strokeStyle = accent
      c.globalAlpha = (0.35 + 0.12 * Math.sin(t * 0.7)) * level
      c.beginPath(); c.moveTo(cx, 22); c.lineTo(cx - 5, 29)
      c.lineTo(cx + 1, 29); c.lineTo(cx - 4, 37); c.stroke()
      c.strokeStyle = foreground
    }

    if (fire) {
      var fx = tent ? 246 : 197
      var sway = Math.sin(t * 1.1) * 2
      c.strokeStyle = accent
      c.globalAlpha = 0.45 * level
      c.beginPath(); c.moveTo(fx - 6, 39)
      c.bezierCurveTo(fx - 13, 30, fx - 2 + sway, 27, fx + sway, 20)
      c.bezierCurveTo(fx + 2, 29, fx + 11, 31, fx + 5, 39); c.stroke()
      c.globalAlpha = 0.24 * level
      c.beginPath(); c.moveTo(fx, 38)
      c.quadraticCurveTo(fx - 4, 34, fx + sway, 30); c.stroke()
      c.strokeStyle = foreground
      c.globalAlpha = 0.36 * level
      c.beginPath(); c.moveTo(fx - 8, 40); c.lineTo(fx + 8, 44)
      c.moveTo(fx + 8, 40); c.lineTo(fx - 8, 44); c.stroke()
    }
    c.globalAlpha = 1
  }
}
