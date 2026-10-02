import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root
  property var entries: []
  property string selectedId: ""
  property bool playing: false
  property bool animate: true
  property bool available: true
  property bool saving: false
  property bool addingLink: false
  property string message: ""
  property bool failed: false
  property color foreground: Color.foreground
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property string pendingRemoval: ""
  property bool searching: false
  property alias urlField: urlInput
  property alias titleField: titleInput
  signal saveRequested()
  signal playRequested(string id)
  signal removeRequested(string id)
  function focusSearch() { searching = true; Qt.callLater(function() { search.forceActiveFocus() }) }
  spacing: Style.space(12)

  Row {
    width: parent.width
    spacing: Style.space(8)
    Text {
      width: parent.width - addButton.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      text: "Your saved links"
      textFormat: Text.PlainText; color: root.foreground
      font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
      elide: Text.ElideRight
    }
    Button {
      id: addButton
      objectName: "addYoutube"
      text: root.addingLink ? "Cancel" : "Add link"
      iconText: root.addingLink ? "\uf00d" : "\uf067"
      foreground: root.foreground; focusable: true
      onClicked: {
        root.addingLink = !root.addingLink
        if (root.addingLink) Qt.callLater(function() { urlInput.forceActiveFocus() })
      }
    }
  }
  TextField {
    id: search
    objectName: "librarySearch"
    width: parent.width
    visible: root.searching || root.entries.length > 4
    placeholderText: "Search saved links"
    maximumLength: 160
    foreground: root.foreground
    Keys.onEscapePressed: { text = ""; root.searching = false; focus = false }
  }
  BorderSurface {
    width: parent.width
    visible: height > 0
    height: root.addingLink || root.entries.length === 0 ? form.implicitHeight + Style.space(24) : 0
    clip: true
    radius: Style.cornerRadius
    color: Qt.alpha(root.foreground, 0.035)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    opacity: root.addingLink || root.entries.length === 0 ? 1 : 0
    Behavior on opacity { enabled: root.animate && root.visible; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Column {
      id: form
      anchors.left: parent.left; anchors.right: parent.right
      anchors.top: parent.top; anchors.margins: Style.space(12)
      spacing: Style.space(10)
      Text {
        width: parent.width
        visible: root.entries.length === 0
        text: "Keep a favourite mix or conversation here."
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption
      }
      TextField {
        id: urlInput
        objectName: "youtubeUrl"
        width: parent.width
        placeholderText: "Paste a YouTube link"
        maximumLength: 2048
        foreground: root.foreground
        Accessible.name: "YouTube link"
        onAccepted: if (!root.saving && text.trim().length > 0) root.saveRequested()
        Keys.onEscapePressed: { focus = false; root.addingLink = false }
      }
      TextField {
        id: titleInput
        objectName: "youtubeTitle"
        width: parent.width
        placeholderText: "Name · optional"
        maximumLength: 160
        foreground: root.foreground
        Accessible.name: "Link name, optional"
        onAccepted: if (!root.saving && urlInput.text.trim().length > 0) root.saveRequested()
        Keys.onEscapePressed: { focus = false; root.addingLink = false }
      }
      Button {
        objectName: "saveYoutube"
        width: parent.width
        text: root.saving ? "Saving…" : "Save link"
        iconText: "\uf067"
        bordered: true; selected: urlInput.text.trim().length > 0
        enabled: !root.saving && urlInput.text.trim().length > 0
        opacity: enabled ? 1 : 0.5
        foreground: root.foreground; focusable: true
        onClicked: root.saveRequested()
      }
    }
  }
  Text {
    width: parent.width
    visible: !root.available || root.message.length > 0
    text: !root.available ? "YouTube playback needs yt-dlp. You can save links now." : root.message
    textFormat: Text.PlainText; wrapMode: Text.Wrap
    color: root.failed ? Color.urgent : root.muted
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
  }
  Repeater {
    model: root.entries
    Column {
      required property var modelData
      objectName: "libraryEntry-" + modelData.id
      width: root.width
      visible: (modelData.name || "").toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0
      spacing: Style.space(6)
      Row {
        width: parent.width
        spacing: Style.space(6)
        StationRow {
          width: parent.width - removeButton.width - parent.spacing
          name: modelData.name
          description: modelData.position > 5 ? "Continue from " + Math.floor(modelData.position / 60) + " min" : "YouTube audio"
          glyph: "\uf144"
          current: root.selectedId === modelData.id
          playing: current && root.playing
          animate: root.animate && root.visible
          foreground: root.foreground; fontFamily: root.fontFamily
          onActivated: root.playRequested(modelData.id)
        }
        Button {
          id: removeButton
          objectName: "removeYoutube-" + modelData.id
          width: Style.space(30); height: Style.space(32)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf00d"; iconSize: Style.font.caption
          tooltipText: "Remove saved link"
          foreground: root.muted; focusable: true
          Accessible.name: "Remove " + modelData.name
          onClicked: root.pendingRemoval = root.pendingRemoval === modelData.id ? "" : modelData.id
        }
      }
      Row {
        visible: root.pendingRemoval === modelData.id
        width: parent.width
        spacing: Style.space(8)
        Button {
          text: "Remove link"
          objectName: "confirmRemoveYoutube-" + modelData.id
          foreground: root.foreground; bordered: true; focusable: true
          onClicked: { root.removeRequested(modelData.id); root.pendingRemoval = "" }
        }
        Button {
          text: "Keep"; foreground: root.muted; focusable: true
          onClicked: root.pendingRemoval = ""
        }
      }
    }
  }
  Text {
    visible: search.text.length > 0 && root.entries.filter(function(entry) { return (entry.name || "").toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0 }).length === 0
    width: parent.width
    text: "No saved links found."
    color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
  }
}
