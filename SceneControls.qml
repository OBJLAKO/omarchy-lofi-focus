import QtQuick
import qs.Commons
import qs.Ui

// Scene actions stay explicit: changing a picker applies a scene, while a
// typed name saves the current mix. Neither action starts playback.
Column {
  id: root
  property var scenes: []
  property string sceneId: ""
  property bool dirty: false
  property bool animate: true
  property Item popupBoundary: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool saving: false
  property bool confirmingRemoval: false
  readonly property var currentScene: scenes.find(function(scene) { return scene.id === root.sceneId }) || null
  readonly property var options: [{value:"",label:"Unsaved mix",description:"Current room and sounds"}].concat(scenes.map(function(scene) {
    return {value:String(scene.id),label:String(scene.name),description:"Saved room and sound layers"}
  }))
  signal applyRequested(string id)
  signal saveRequested(string name)
  signal removeRequested(string id)
  signal focusRequested(var item)
  spacing: Style.space(6)
  onSceneIdChanged: { picker.value = sceneId; confirmingRemoval = false }
  onVisibleChanged: if (!visible) { picker.close(); saving = false; confirmingRemoval = false }
  function close() { picker.close(); saving = false; confirmingRemoval = false }
  function save() {
    var name = nameField.text.trim()
    if (!name) { nameField.forceActiveFocus(); return }
    root.saveRequested(name)
    root.saving = false
  }
  SkylofiStyle { id: visual; foreground: root.foreground }
  Row {
    width: parent.width
    spacing: Style.space(6)
    FocusDropdown {
      id: picker
      objectName: "scenePicker"
      width: parent.width - saveButton.width - removeButton.width - parent.spacing * 2
      showLabel: false; label: "Saved scene"; placeholderText: "Find a scene"
      options: root.options; value: root.sceneId
      popupBoundary: root.popupBoundary
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      onChanged: function(value) { if (value) root.applyRequested(value); else picker.value = root.sceneId }
      onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    }
    SkylofiButton {
      id: saveButton
      objectName: "sceneSaveButton"
      width: Style.space(32); height: picker.height
      iconText: "\uf0c7"; tooltipText: "Save current mix as a scene"
      horizontalPadding: 0; verticalPadding: 0; focusable: true; bordered: true
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      selected: root.saving
      onClicked: {
        root.saving = !root.saving; root.confirmingRemoval = false
        if (root.saving) {
          nameField.text = root.currentScene ? root.currentScene.name : ""
          Qt.callLater(function() { nameField.forceActiveFocus(); root.focusRequested(nameField) })
        }
      }
    }
    SkylofiButton {
      id: removeButton
      objectName: "sceneRemoveButton"
      width: Style.space(32); height: picker.height
      iconText: "\uf1f8"; tooltipText: "Remove selected saved scene"
      enabled: root.currentScene !== null; opacity: enabled ? 1 : 0.45
      horizontalPadding: 0; verticalPadding: 0; focusable: true; bordered: true
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      selected: root.confirmingRemoval
      onClicked: { root.confirmingRemoval = !root.confirmingRemoval; root.saving = false }
    }
  }
  Text {
    width: parent.width
    // A changing dirty flag must not insert/remove a row above a grabbed
    // fader. Keep this caption on one line with stable geometry.
    text: root.dirty ? "Modified · save this mix" : root.currentScene ? "Saved scene" : "Save your room and sounds"
    textFormat: Text.PlainText; elide: Text.ElideRight
    color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Row {
    width: parent.width; spacing: Style.space(6)
    visible: root.saving
    TextField {
      id: nameField
      objectName: "sceneName"
      width: parent.width - confirmSave.width - parent.spacing
      height: Style.space(34)
      maximumLength: 40; placeholderText: "Scene name"
      foreground: root.foreground
      font.family: root.fontFamily; font.pixelSize: visual.label
      Accessible.name: "Scene name"
      onAccepted: root.save()
      Keys.onEscapePressed: root.saving = false
      onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    }
    SkylofiButton {
      id: confirmSave
      objectName: "sceneSaveConfirm"
      text: "Save"; height: nameField.height
      enabled: nameField.text.trim().length > 0
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      focusable: true; bordered: true
      onClicked: root.save()
    }
  }
  Row {
    width: parent.width; spacing: Style.space(6)
    visible: root.confirmingRemoval && root.currentScene !== null
    Text {
      width: parent.width - confirmRemove.width - cancelRemove.width - parent.spacing * 2
      anchors.verticalCenter: parent.verticalCenter
      text: "Remove saved scene?"; textFormat: Text.PlainText
      wrapMode: Text.Wrap; color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    SkylofiButton {
      id: confirmRemove
      objectName: "sceneRemoveConfirm"
      text: "Remove"; foreground: root.foreground; fontFamily: root.fontFamily
      animate: root.animate; focusable: true; bordered: true
      onClicked: { var id = root.sceneId; root.confirmingRemoval = false; root.removeRequested(id) }
    }
    SkylofiButton {
      id: cancelRemove
      text: "Keep"; foreground: visual.muted; fontFamily: root.fontFamily
      animate: root.animate; focusable: true
      onClicked: root.confirmingRemoval = false
    }
  }
}
