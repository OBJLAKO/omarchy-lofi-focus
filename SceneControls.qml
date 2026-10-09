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
  property bool savePending: false
  property string saveError: ""
  property bool confirmingRemoval: false
  readonly property var currentScene: scenes.find(function(scene) { return scene.id === root.sceneId }) || null
  readonly property var options: [{value:"",label:"Current mix",description:"Your current sounds and room"}].concat(scenes.map(function(scene) {
    return {value:String(scene.id),label:String(scene.name) + (root.dirty && scene.id === root.sceneId ? " (edited)" : ""),description:"Saved mix"}
  }))
  signal applyRequested(string id)
  signal saveRequested(string name)
  signal removeRequested(string id)
  signal focusRequested(var item)
  spacing: Style.space(6)
  onSceneIdChanged: confirmingRemoval = false
  onVisibleChanged: if (!visible) { picker.close(); saving = false; confirmingRemoval = false }
  function close() { picker.close(); saving = false; confirmingRemoval = false }
  function save() {
    if (root.savePending) return
    var name = nameField.text.trim()
    if (!name) { nameField.forceActiveFocus(); return }
    root.savePending = true
    root.saveError = ""
    root.saveRequested(name)
  }
  function finishSave(code, message) {
    if (!root.savePending) return
    root.savePending = false
    if (code === 0) {
      root.saving = false
      root.saveError = ""
      nameField.text = ""
    } else {
      root.saving = true
      root.saveError = message || "Could not save this scene. Try again."
      Qt.callLater(function() {
        if (root.visible && root.saving) { nameField.forceActiveFocus(); root.focusRequested(nameField) }
      })
    }
  }
  SkylofiStyle { id: visual; foreground: root.foreground }
  Row {
    width: parent.width
    spacing: Style.space(6)
    FocusDropdown {
      id: picker
      objectName: "scenePicker"
      width: parent.width - saveButton.width - (removeButton.visible ? removeButton.width + parent.spacing : 0) - parent.spacing
      showLabel: false; label: "Saved scene"; placeholderText: "Find a scene"
      // The backend confirms selection. A rejected scene must not change the
      // displayed name or leave the remove action pointing at another scene.
      options: root.options; value: root.sceneId; controlledValue: true
      popupBoundary: root.popupBoundary
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      onChanged: function(value) { if (value) root.applyRequested(value) }
      onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    }
    SkylofiButton {
      id: saveButton
      objectName: "sceneSaveButton"
      text: "Save"; height: picker.height
      iconText: "\uf0c7"; tooltipText: "Save current mix as a scene"
      horizontalPadding: Style.space(8); verticalPadding: 0; focusable: true; bordered: true
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      selected: root.saving
      enabled: !root.savePending
      onClicked: {
        root.saving = !root.saving; root.confirmingRemoval = false
        if (root.saving) {
          if (!root.saveError) nameField.text = root.currentScene ? root.currentScene.name : ""
          Qt.callLater(function() { nameField.forceActiveFocus(); root.focusRequested(nameField) })
        }
      }
    }
    SkylofiButton {
      id: removeButton
      objectName: "sceneRemoveButton"
      width: Style.space(32); height: picker.height
      iconText: "\uf1f8"; tooltipText: "Remove selected saved scene"
      visible: root.currentScene !== null
      horizontalPadding: 0; verticalPadding: 0; focusable: true; bordered: true
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      selected: root.confirmingRemoval
      onClicked: { root.confirmingRemoval = !root.confirmingRemoval; root.saving = false }
    }
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
      enabled: !root.savePending
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
      text: root.savePending ? "Saving…" : "Save"; height: nameField.height
      enabled: !root.savePending && nameField.text.trim().length > 0
      foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
      focusable: true; bordered: true
      onClicked: root.save()
    }
  }
  Text {
    objectName: "sceneSaveError"
    width: parent.width
    visible: root.saving && root.saveError.length > 0
    text: root.saveError; textFormat: Text.PlainText
    wrapMode: Text.Wrap; color: visual.muted
    font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Row {
    width: parent.width; spacing: Style.space(6)
    visible: root.confirmingRemoval && root.currentScene !== null
    Text {
      width: parent.width - confirmRemove.width - cancelRemove.width - parent.spacing * 2
      anchors.verticalCenter: parent.verticalCenter
      objectName: "sceneRemovePrompt"
      text: root.currentScene ? "Remove “" + root.currentScene.name + "”?" : "Remove saved scene?"
      textFormat: Text.PlainText
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
