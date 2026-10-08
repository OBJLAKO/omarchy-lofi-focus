import QtQuick
import qs.Commons

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
  implicitHeight: body.implicitHeight + Style.space(20)
  height: implicitHeight; radius: Math.min(Style.cornerRadius,Style.space(8))
  color: root.selected ? visual.selected : visual.surface
  border.width: 1; border.color: root.selected ? Qt.alpha(Color.accent,0.65) : visual.line
  SkylofiStyle { id: visual; foreground: root.foreground }
  function sourceIcon(id) {
    if (/fire|bonfire/.test(id)) return "\uf06d"
    if (/rain|storm/.test(id)) return "\uf0c2"
    if (/wind/.test(id)) return "\u224b"
    if (/river|water|ocean|stream/.test(id)) return "\uf043"
    if (/forest|leaves/.test(id)) return "\uf1bb"
    return "\uf001"
  }
  Column {
    id: body
    x: Style.space(10); y: Style.space(10)
    width: parent.width - Style.space(20); spacing: Style.space(10)
    Row {
      width: parent.width; spacing: Style.space(6)
      Item {
        id: selectButton
        objectName: "sourceSelect-" + (root.sound.id || "")
        width: parent.width - removeButton.width - parent.spacing
        height: Math.max(Style.space(38),sourceName.implicitHeight + description.implicitHeight + Style.space(5))
        activeFocusOnTab: true
        Accessible.role: Accessible.Button; Accessible.name: root.label
        Accessible.description: root.expanded ? "Hide sound controls" : "Show sound controls"
        Accessible.onPressAction: root.selectedRequested()
        Keys.onReturnPressed: root.selectedRequested()
        Keys.onSpacePressed: root.selectedRequested()
        Rectangle {
          anchors.fill: parent; color: "transparent"; radius: Style.space(4)
          border.width: parent.activeFocus ? 1 : 0; border.color: Color.accent
        }
        Text {
          id: sourceName
          x: Style.space(24); y: 0
          width: parent.width - x - level.width - Style.space(8)
          text: root.label; elide: Text.ElideRight; color: root.foreground
          font.family: root.fontFamily; font.pixelSize: visual.body
        }
        Text {
          id: level; anchors.right: parent.right; y: 0
          text: Math.round(Number(root.sound.volume) || 0) + "%"
          color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
        }
        Text {
          id: description
          x: Style.space(24); y: sourceName.implicitHeight + Style.space(4); width: parent.width - x
          text: (Number(root.sound.distance || 0) < 33 ? "Nearby" : Number(root.sound.distance || 0) < 67 ? "Midway" : "Distant") + " · "
            + (Number(root.sound.coverage === undefined ? 50 : root.sound.coverage) < 25 ? "Point" : Number(root.sound.coverage === undefined ? 50 : root.sound.coverage) < 75 ? "Wide" : "Surrounding")
            + (typeof root.sound.effective_volume === "number" && Math.round(root.sound.effective_volume) !== Math.round(root.sound.volume) ? " · " + Math.round(root.sound.effective_volume) + "% now" : "")
          elide: Text.ElideRight; color: visual.muted
          font.family: root.fontFamily; font.pixelSize: visual.caption
        }
        Text {
          x: 0; y: (sourceName.implicitHeight - height) / 2
          text: root.sourceIcon(root.sound.id || "")
          color: root.selected ? Color.accent : root.foreground
          font.family: root.fontFamily; font.pixelSize: visual.iconSize
        }
        MouseArea {
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          onClicked: { selectButton.forceActiveFocus(Qt.MouseFocusReason); root.selectedRequested() }
        }
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
      SkylofiButton {
        id: removeButton
        objectName: "sourceRemove-" + (root.sound.id || "")
        text: ""; iconText: "\uf00d"; tooltipText: "Remove sound from mix"
        width: Style.space(28); height: Style.space(32); horizontalPadding: 0
        focusable: true; foreground: visual.muted; fontFamily: root.fontFamily; animate: root.animate
        onClicked: root.removeRequested()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
    Loader {
      objectName: "sourceDetailsLoader"
      width: parent.width; active: root.expanded; visible: active
      height: item ? item.implicitHeight : 0
      sourceComponent: Component {
      Column {
      width: parent.width; spacing: Style.space(10)
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
}
