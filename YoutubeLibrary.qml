import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root
  property var entries: []
  property var entryIds: []
  onEntriesChanged: {
    var ids = entries.map(function(entry) { return entry.id })
    if (JSON.stringify(ids) !== JSON.stringify(entryIds)) entryIds = ids
  }
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
  signal focusRequested(var item)
  function focusSearch() { searching = true; Qt.callLater(function() { search.forceActiveFocus() }) }
  function entryDescription(entry) {
    // Saved links can also be live streams. A stored clock alone does not mean
    // the source can resume; let the backend identify recordings explicitly.
    if (entry.is_live === false && entry.position > 5) return "Continue from " + Math.floor(entry.position / 60) + " min"
    return entry.is_live === true ? "Live YouTube stream" : "Saved YouTube audio"
  }
  SkylofiStyle { id: visual; foreground: root.foreground; background: Color.popups.background; accent: Color.accent }
  spacing: Style.space(12)

  Row {
    width: parent.width
    spacing: visual.controlGap
    Text {
      width: parent.width - addButton.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      text: root.entries.length === 0 ? "Your collection" : root.entries.length + (root.entries.length === 1 ? " saved link" : " saved links")
      textFormat: Text.PlainText; color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.label
      elide: Text.ElideRight
    }
    SkylofiButton {
      fontFamily: root.fontFamily
      animate: root.animate && root.visible
      id: addButton
      objectName: "addYoutube"
      text: root.addingLink ? "Cancel" : "Add link"
      iconText: root.addingLink ? "\uf00d" : "\uf067"
      height: visual.controlHeight
      fontSize: visual.label; iconSize: visual.label
      foreground: root.foreground; focusable: true
      bordered: !root.addingLink
      onClicked: {
        root.addingLink = !root.addingLink
        if (root.addingLink) Qt.callLater(function() { urlInput.forceActiveFocus() })
      }
      onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    }
  }
  TextField {
    id: search
    objectName: "librarySearch"
    width: parent.width; height: visual.controlHeight
    visible: root.searching || root.entries.length > 4
    placeholderText: "Search saved links"
    maximumLength: 160
    foreground: root.foreground
    font.family: root.fontFamily; font.pixelSize: visual.body
    onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
    Keys.onEscapePressed: { text = ""; root.searching = false; focus = false }
  }
  BorderSurface {
    objectName: "addLinkForm"
    width: parent.width
    visible: root.addingLink
    height: form.implicitHeight + Style.space(28)
    radius: Math.min(Style.cornerRadius, Style.space(10))
    color: visual.surface
    borderSpec: Border.flat(visual.line, 1)
    Column {
      id: form
      anchors.left: parent.left; anchors.right: parent.right
      anchors.top: parent.top; anchors.margins: Style.space(14)
      spacing: Style.space(10)
      Text {
        width: parent.width
        text: "Save a YouTube mix, live stream or conversation."
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.caption
      }
      Column {
        width: parent.width
        spacing: Style.space(4)
        Text {
          text: "YouTube link"
          textFormat: Text.PlainText; color: visual.muted
          font.family: root.fontFamily; font.pixelSize: visual.caption
        }
        TextField {
          id: urlInput
          objectName: "youtubeUrl"
          width: parent.width; height: visual.controlHeight
          placeholderText: "Paste a YouTube link"
          maximumLength: 2048
          foreground: root.foreground
          font.family: root.fontFamily; font.pixelSize: visual.body
          Accessible.name: "YouTube link"
          onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
          onAccepted: if (!root.saving && text.trim().length > 0) root.saveRequested()
          Keys.onEscapePressed: { focus = false; root.addingLink = false }
        }
      }
      Column {
        width: parent.width
        spacing: Style.space(4)
        Text {
          text: "Name (optional)"
          textFormat: Text.PlainText; color: visual.muted
          font.family: root.fontFamily; font.pixelSize: visual.caption
        }
        TextField {
          id: titleInput
          objectName: "youtubeTitle"
          width: parent.width; height: visual.controlHeight
          placeholderText: "e.g. Morning jazz"
          maximumLength: 160
          foreground: root.foreground
          font.family: root.fontFamily; font.pixelSize: visual.body
          Accessible.name: "Link name, optional"
          onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
          onAccepted: if (!root.saving && urlInput.text.trim().length > 0) root.saveRequested()
          Keys.onEscapePressed: { focus = false; root.addingLink = false }
        }
      }
      SkylofiButton {
        fontFamily: root.fontFamily
        animate: root.animate && root.visible
        objectName: "saveYoutube"
        width: parent.width; height: visual.controlHeight
        text: root.saving ? "Saving…" : "Save link"
        selected: true
        enabled: !root.saving && urlInput.text.trim().length > 0
        opacity: enabled ? 1 : 0.45
        fontSize: visual.body
        foreground: root.foreground; focusable: true
        onClicked: root.saveRequested()
        onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
      }
    }
  }
  Column {
    width: parent.width
    visible: root.entries.length === 0 && !root.addingLink
    spacing: Style.space(6)
    Text {
      width: parent.width
      text: "Keep your favourites here"
      textFormat: Text.PlainText; color: root.foreground
      font.family: root.fontFamily; font.pixelSize: visual.body
    }
    Text {
      width: parent.width
      text: "Add a YouTube link to choose it alongside your radio stations."
      textFormat: Text.PlainText; wrapMode: Text.Wrap
      color: visual.muted
      font.family: root.fontFamily; font.pixelSize: visual.caption
    }
  }
  Text {
    width: parent.width
    visible: !root.available || root.message.length > 0
    text: !root.available ? "Install yt-dlp to play YouTube audio. You can still save links." : root.message
    textFormat: Text.PlainText; wrapMode: Text.Wrap
    color: root.failed ? Color.urgent : visual.muted
    font.family: root.fontFamily; font.pixelSize: visual.caption
  }
  Column {
    width: parent.width
    spacing: Style.space(2)
    Repeater {
      model: root.entryIds
      Column {
        required property var modelData
        readonly property var entry: root.entries.find(function(value) { return value.id === modelData }) || ({})
        objectName: "libraryEntry-" + entry.id
        width: root.width
        visible: (entry.name || "").toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0
        spacing: Style.space(6)
        Row {
          width: parent.width
          spacing: Style.space(4)
          StationRow {
            width: parent.width - removeButton.width - parent.spacing
            name: entry.name
            description: root.entryDescription(entry)
            glyph: "\uf144"
            current: root.selectedId === entry.id
            playing: current && root.playing
            animate: root.animate && root.visible
            foreground: root.foreground; fontFamily: root.fontFamily
            onActivated: root.playRequested(entry.id)
            onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
          }
          SkylofiButton {
            fontFamily: root.fontFamily
            animate: root.animate && root.visible
            id: removeButton
            objectName: "removeYoutube-" + entry.id
            width: Style.space(28); height: Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\uf1f8"; iconSize: visual.caption
            tooltipText: "Remove saved link"
            foreground: visual.muted; focusable: true
            Accessible.name: "Remove " + entry.name
            onClicked: root.pendingRemoval = root.pendingRemoval === entry.id ? "" : entry.id
            onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
          }
        }
        BorderSurface {
          visible: root.pendingRemoval === entry.id
          width: parent.width
          height: confirmation.implicitHeight + Style.space(20)
          radius: Math.min(Style.cornerRadius, Style.space(8))
          color: visual.surface
          borderSpec: Border.flat(visual.line, 1)
          Row {
            id: confirmation
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.margins: Style.space(10)
            spacing: Style.space(8)
            Text {
              width: Math.max(0, parent.width - confirmButton.width - keepButton.width - parent.spacing * 2)
              anchors.verticalCenter: parent.verticalCenter
              text: "Remove this link?"
              textFormat: Text.PlainText; color: visual.muted
              font.family: root.fontFamily; font.pixelSize: visual.caption
              wrapMode: Text.Wrap
            }
            SkylofiButton {
              fontFamily: root.fontFamily
              animate: root.animate && root.visible
              id: confirmButton
              text: "Remove"
              objectName: "confirmRemoveYoutube-" + entry.id
              foreground: Color.urgent; bordered: true; focusable: true
              height: Style.space(32); fontSize: visual.label
              onClicked: { root.removeRequested(entry.id); root.pendingRemoval = "" }
              onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
            }
            SkylofiButton {
              fontFamily: root.fontFamily
              animate: root.animate && root.visible
              id: keepButton
              text: "Keep"; foreground: root.foreground; focusable: true
              height: Style.space(32); fontSize: visual.label
              onClicked: root.pendingRemoval = ""
              onActiveFocusChanged: if (activeFocus) root.focusRequested(this)
            }
          }
        }
      }
    }
  }
  Text {
    visible: search.text.length > 0 && root.entries.filter(function(entry) { return (entry.name || "").toLowerCase().indexOf(search.text.trim().toLowerCase()) >= 0 }).length === 0
    width: parent.width
    text: "No matching saved links."
    color: visual.muted; font.family: root.fontFamily; font.pixelSize: visual.body
  }
}
