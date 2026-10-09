import QtQuick
import QtQuick.Dialogs
import qs.Commons
import qs.Ui

// Native browsing is convenient; the editable path remains available when
// the desktop cannot provide a file dialog. Only the backend copies audio.
Column {
  id: root
  property bool expanded: false
  property bool pending: false
  property string errorMessage: ""
  property bool animate: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal importRequested(string path, string title)
  signal focusRequested(var item)
  spacing: Style.space(6)
  // Wrapped error text can move the focused field after the reply callback.
  onHeightChanged: Qt.callLater(function() {
    if (!root.visible) return
    if (pathField.activeFocus) root.focusRequested(pathField)
    else if (titleField.activeFocus) root.focusRequested(titleField)
  })
  function filePath(url) {
    var value = String(url)
    return value.indexOf("file://") === 0 ? decodeURIComponent(value.slice(7)) : ""
  }
  function focusPath() {
    Qt.callLater(function() {
      if (!root.visible || dialog.visible) return
      pathField.forceActiveFocus(); root.focusRequested(pathField)
    })
  }
  function openImporter() {
    var alreadyExpanded = expanded
    expanded = true
    if (!pending && !alreadyExpanded) dialog.open()
    focusPath()
  }
  function submit() {
    if (pending) return
    var path = pathField.text.trim()
    if (path.charAt(0) !== "/") { pathField.forceActiveFocus(); return }
    pending = true; errorMessage = ""
    root.importRequested(path,titleField.text.trim())
  }
  function completeImport(exitCode, message) {
    if (!pending) return
    pending = false
    if (exitCode === 0) {
      errorMessage = ""; expanded = false
      pathField.text = ""; titleField.text = ""
      Qt.callLater(function() { if (root.visible) { importToggle.forceActiveFocus(); root.focusRequested(importToggle) } })
    } else {
      errorMessage = message || "Could not import this sound. Check the file and try again."
      expanded = true
      Qt.callLater(function() {
        if (!root.visible) return
        pathField.forceActiveFocus()
        root.focusRequested(errorHint)
        root.focusRequested(pathField)
      })
    }
  }
  SkylofiStyle { id: visual; foreground: root.foreground }
  SkylofiButton {
    id: importToggle
    objectName: "soundImportButton"
    text: root.expanded ? "Cancel import" : "Import sound…"
    iconText: root.expanded ? "close" : "\uf07b"
    fontSize: visual.label; fontFamily: root.fontFamily
    foreground: root.foreground; animate: root.animate
    focusable: true; bordered: true; enabled: !root.pending
    onClicked: { if (root.expanded) root.expanded = false; else root.openImporter() }
  }
  Column {
    width: parent.width; spacing: Style.space(6); visible: root.expanded
    Text {
      id: errorHint
      objectName: "soundImportError"
      width: parent.width; visible: root.errorMessage.length > 0
      text: root.errorMessage; textFormat: Text.PlainText
      wrapMode: Text.Wrap; color: Color.urgent
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    Text {
      objectName: "soundImportGuidance"
      visible: root.errorMessage.length === 0
      width: parent.width; text: "Add your own OGG, WAV, FLAC or MP3. A copy stays in your sound library."
      wrapMode: Text.Wrap; color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
    Row {
      width: parent.width; spacing: Style.space(6)
      TextField {
        id: pathField
        objectName: "soundImportPath"
        width: parent.width - browseButton.width - parent.spacing
        height: Style.space(34); maximumLength: 4096
        readOnly: root.pending
        placeholderText: "Absolute path to an audio file"
        foreground: root.foreground; font.family: root.fontFamily; font.pixelSize: visual.label
        Accessible.name: "Audio file path"
        onAccepted: root.submit()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
      SkylofiButton {
        id: browseButton
        objectName: "soundImportBrowse"
        width: Style.space(34); height: pathField.height
        iconText: "\uf07c"; tooltipText: "Browse audio files"
        foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
        horizontalPadding: 0; verticalPadding: 0; focusable: true; bordered: true; enabled: !root.pending
        onClicked: dialog.open()
      }
    }
    Row {
      width: parent.width; spacing: Style.space(6)
      TextField {
        id: titleField
        objectName: "soundImportTitle"
        width: parent.width - importButton.width - parent.spacing
        height: Style.space(34); maximumLength: 60
        readOnly: root.pending
        placeholderText: "Name (optional)"
        foreground: root.foreground; font.family: root.fontFamily; font.pixelSize: visual.label
        Accessible.name: "Imported sound name, optional"
        onAccepted: root.submit()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
      SkylofiButton {
        id: importButton
        objectName: "soundImportConfirm"
        text: root.pending ? "Importing…" : "Import"; height: titleField.height
        enabled: !root.pending && pathField.text.trim().charAt(0) === "/"
        foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
        focusable: true; bordered: true
        onClicked: root.submit()
      }
    }
  }
  FileDialog {
    id: dialog
    objectName: "soundImportDialog"
    title: "Import an ambience sound"
    nameFilters: ["Audio files (*.ogg *.wav *.flac *.mp3)","All files (*)"]
    fileMode: FileDialog.OpenFile
    onAccepted: {
      pathField.text = root.filePath(selectedFile)
      root.expanded = true
      Qt.callLater(function() { titleField.forceActiveFocus(); root.focusRequested(titleField) })
    }
    onRejected: root.focusPath()
  }
}
