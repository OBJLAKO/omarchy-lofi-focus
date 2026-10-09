import QtQuick

// One optical grid and stroke weight for every control. Legacy glyph values
// remain accepted so existing callers do not depend on an icon font.
Item {
  id: root
  property string name: ""
  property string glyph: ""
  property color color: "white"
  property real size: 16
  readonly property string iconName: resolve(name || glyph)
  implicitWidth: size
  implicitHeight: size
  width: size
  height: size
  Image {
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    smooth: true
    sourceSize.width: Math.max(1, Math.round(width * 2))
    sourceSize.height: Math.max(1, Math.round(height * 2))
    source: "data:image/svg+xml;utf8," + encodeURIComponent(root.svg(root.iconName))
  }

  function resolve(value) {
    var legacy = {
      "\uf001":"music", "\uf130":"microphone", "\uf072":"plane", "\uf0f5":"cup",
      "\uf06d":"fire", "\uf0c2":"rain", "\u224b":"wind", "\uf043":"water", "\uf1bb":"tree",
      "\uf025":"headphones", "\uf00d":"close", "\uf00c":"check", "\uf067":"plus",
      "\uf04b":"play", "\uf04c":"pause", "\uf04d":"stop", "\uf144":"play-circle",
      "\uf105":"chevron-right", "\uf104":"chevron-left", "\uf107":"chevron-down", "\uf106":"chevron-up",
      "\uf0e2":"return", "\uf05a":"info", "\uf07b":"folder", "\uf07c":"folder-open",
      "\uf0c7":"save", "\uf1f8":"trash", "\uf013":"settings", "\uf1de":"sliders",
      "\uf028":"volume", "\uf026":"volume-low", "\uf027":"volume-low", "\uf6a9":"mute",
      "\uf002":"search", "\uf0c1":"link", "\uf304":"edit"
    }
    return legacy[value] || value || "music"
  }

  function svg(icon) {
    var drawings = {
      "music": '<path d="M9 17V5l11-2v12M9 9l11-2"/><ellipse cx="6" cy="17" rx="3" ry="2.5"/><ellipse cx="17" cy="15" rx="3" ry="2.5"/>',
      "microphone": '<rect x="9" y="3" width="6" height="12" rx="3"/><path d="M6 11v1a6 6 0 0 0 12 0v-1M12 18v3M9 21h6"/>',
      "plane": '<path d="m21 3-7 18-3-8-8-3 18-7ZM11 13l5-5"/>',
      "cup": '<path d="M4 8h12v7a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5V8ZM16 9h2a3 3 0 0 1 0 6h-2M7 3v2M11 3v2"/>',
      "fire": '<path d="M12 3c1 5-4 5-2 9 1-1 2-2 2-4 4 3 7 5 7 9a7 7 0 0 1-14 0c0-4 3-7 7-14Z"/>',
      "rain": '<path d="M7 15H6a4 4 0 0 1-.3-8A6 6 0 0 1 17 7a4 4 0 0 1 1 8h-1M8 18l-1 3M13 17l-1 3M18 18l-1 3"/>',
      "wind": '<path d="M3 8h11a3 3 0 1 0-3-3M3 12h15a3 3 0 1 1-3 3M3 16h5a3 3 0 1 1-3 3"/>',
      "water": '<path d="M12 3C9 7 5 11 5 15a7 7 0 0 0 14 0c0-4-4-8-7-12ZM8 15a4 4 0 0 0 4 4"/>',
      "tree": '<path d="m12 3-5 6h3l-5 6h5l-3 4h10l-3-4h5l-5-6h3l-5-6ZM12 19v3"/>',
      "headphones": '<path d="M4 14v-2a8 8 0 0 1 16 0v2"/><rect x="3" y="12" width="4" height="8" rx="2"/><rect x="17" y="12" width="4" height="8" rx="2"/>',
      "close": '<path d="m6 6 12 12M18 6 6 18"/>',
      "check": '<path d="m5 12 4 4L19 6"/>',
      "plus": '<path d="M12 5v14M5 12h14"/>',
      "play": '<path d="m8 4 12 8-12 8V4Z"/>',
      "pause": '<path d="M8 5v14M16 5v14" stroke-width="3"/>',
      "stop": '<rect x="5" y="5" width="14" height="14" rx="2"/>',
      "play-circle": '<circle cx="12" cy="12" r="9"/><path d="m10 8 6 4-6 4V8Z"/>',
      "chevron-right": '<path d="m9 5 7 7-7 7"/>',
      "chevron-left": '<path d="m15 5-7 7 7 7"/>',
      "chevron-down": '<path d="m5 9 7 7 7-7"/>',
      "chevron-up": '<path d="m5 15 7-7 7 7"/>',
      "return": '<path d="M4 4v6h6M4 10a8 8 0 1 1 0 5"/>',
      "info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7v.1"/>',
      "folder": '<path d="M3 7V5a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/>',
      "folder-open": '<path d="M3 17V5a2 2 0 0 1 2-2h5l2 3h7v4M3 21l3-11h16l-3 11H3Z"/>',
      "save": '<path d="M4 3h13l3 3v15H4V3ZM8 3v6h8V3M8 21v-8h8v8"/>',
      "trash": '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/>',
      "settings": '<path d="m10 3-.6 3-2 .9-2.8-1-2 3.4 2.3 2v2.4l-2.3 2 2 3.4 2.8-1 2 .9.6 3h4l.6-3 2-.9 2.8 1 2-3.4-2.3-2v-2.4l2.3-2-2-3.4-2.8 1-2-.9-.6-3h-4Z"/><circle cx="12" cy="12" r="3"/>',
      "sliders": '<path d="M4 6h4M12 6h8M4 12h10M18 12h2M4 18h4M12 18h8"/><circle cx="10" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="10" cy="18" r="2"/>',
      "volume": '<path d="m11 4-6 5H2v6h3l6 5V4ZM15 8a6 6 0 0 1 0 8M18 5a10 10 0 0 1 0 14"/>',
      "volume-low": '<path d="m12 4-6 5H3v6h3l6 5V4ZM17 8a6 6 0 0 1 0 8"/>',
      "mute": '<path d="m11 4-6 5H2v6h3l6 5V4ZM16 9l6 6M22 9l-6 6"/>',
      "search": '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
      "link": '<path d="m10 13 4-4M8 16l-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0M16 8l1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0"/>',
      "edit": '<path d="m15 4 5 5M4 15l12-12a2 2 0 0 1 3 0l2 2a2 2 0 0 1 0 3L9 20l-6 1 1-6Z"/>',
      "space": '<ellipse cx="12" cy="12" rx="10" ry="6"/><path d="M2 12h20M12 6v12"/><circle cx="12" cy="12" r="2"/>',
      "radio": '<rect x="3" y="7" width="18" height="14" rx="3"/><path d="m5 7 13-5M7 11h10M16 16h1"/><circle cx="8" cy="16" r="2"/>'
    }
    var rgb = "rgb(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255) + "," + Math.round(color.b * 255) + ")"
    return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="' + rgb + '" stroke-opacity="' + color.a + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + (drawings[icon] || drawings.music) + '</svg>'
  }
}
