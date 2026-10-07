import QtQuick
import QtQuick.Dialogs
import qs.Commons
import qs.Ui

// Native browsing is convenient; the editable path remains available when
// the desktop cannot provide a file dialog. Only the backend copies audio.
Column {
  id: root
  property bool expanded: false
  property bool animate: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal importRequested(string path, string title)
  signal focusRequested(var item)
  spacing: Style.space(6)
  function filePath(url) {
    var value = String(url)
    return value.indexOf("file://") === 0 ? decodeURIComponent(value.slice(7)) : ""
  }
  function submit() {
    var path = pathField.text.trim()
    if (path.charAt(0) !== "/") { pathField.forceActiveFocus(); return }
    root.importRequested(path,titleField.text.trim())
    root.expanded = false; pathField.text = ""; titleField.text = ""
  }
  SkylofiStyle { id: visual; foreground: root.foreground }
  SkylofiButton {
    objectName: "soundImportButton"
    text: "Import sound…"; iconText: "\uf07b"
    fontSize: visual.label; fontFamily: root.fontFamily
    foreground: root.foreground; animate: root.animate
    focusable: true; bordered: true
    onClicked: { root.expanded = !root.expanded; if (root.expanded) dialog.open() }
  }
  Column {
    width: parent.width; spacing: Style.space(6); visible: root.expanded
    Text {
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
        horizontalPadding: 0; verticalPadding: 0; focusable: true; bordered: true
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
        placeholderText: "Name (optional)"
        foreground: root.foreground; font.family: root.fontFamily; font.pixelSize: visual.label
        Accessible.name: "Imported sound name, optional"
        onAccepted: root.submit()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
      SkylofiButton {
        id: importButton
        objectName: "soundImportConfirm"
        text: "Import"; height: titleField.height
        enabled: pathField.text.trim().charAt(0) === "/"
        foreground: root.foreground; fontFamily: root.fontFamily; animate: root.animate
        focusable: true; bordered: true
        onClicked: root.submit()
      }
    }
  }
  FileDialog {
    id: dialog
    title: "Import an ambience sound"
    nameFilters: ["Audio files (*.ogg *.wav *.flac *.mp3)","All files (*)"]
    fileMode: FileDialog.OpenFile
    onAccepted: {
      pathField.text = root.filePath(selectedFile)
      root.expanded = true
      Qt.callLater(function() { titleField.forceActiveFocus(); root.focusRequested(titleField) })
    }
  }
}
