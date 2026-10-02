import QtQuick
import qs.Commons

// Local composition tokens, backed by the user's Omarchy palette and scale.
// Instantiate once in a view: this is deliberately not a second global theme.
QtObject {
  id: style

  property color foreground: Color.foreground
  property color background: Color.popups.background
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  // KeyboardPanel's contentWidth/contentHeight name its whole card, including
  // its own padding and border. The usable body is smaller than these values.
  readonly property int panelWidth: Style.space(460)
  readonly property int panelHeight: Style.space(600)
  readonly property int padding: Style.space(20)
  readonly property int groupGap: Style.space(16)
  readonly property int controlGap: Style.space(8)
  readonly property int smallGap: Style.space(4)
  readonly property int rowHeight: Style.space(56)
  readonly property int controlHeight: Style.space(36)
  readonly property int touchTarget: Style.space(32)
  readonly property int iconSize: Style.space(16)
  readonly property int iconSlot: Style.space(24)
  readonly property int dockHeight: Style.space(104)
  readonly property int radius: Math.max(0, Style.cornerRadius)

  // The shell's default caption is 10px. Small but essential player labels
  // need a little more room while still following the user's text scale.
  readonly property int caption: Math.max(1, Math.round(11 * Style.fontScale))
  readonly property int label: Math.max(1, Math.round(12 * Style.fontScale))
  readonly property int body: Math.max(1, Math.round(13 * Style.fontScale))
  readonly property int title: Math.max(1, Math.round(18 * Style.fontScale))

  readonly property color muted: Qt.alpha(foreground, 0.76)
  readonly property color quiet: Qt.alpha(foreground, 0.60)
  readonly property color line: Qt.alpha(foreground, 0.12)
  readonly property color surface: Qt.alpha(foreground, 0.035)
  readonly property color hover: Qt.alpha(foreground, 0.075)
  readonly property color selected: Qt.alpha(accent, 0.11)
  readonly property color pressed: Qt.alpha(accent, 0.17)
  readonly property color focus: Qt.alpha(accent, 0.85)
  readonly property color sliderTrack: Qt.alpha(foreground, 0.14)

  // Motion explains state changes. It never delays playback commands.
  readonly property int feedbackDuration: 100
  readonly property int transitionDuration: 160
  readonly property int disclosureDuration: 180
  readonly property int maximumShift: Style.space(4)
}
