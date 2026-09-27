import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root
  property var entries: []
  property string selectedId: ""
  property bool playing: false
  property bool available: true
  property bool saving: false
  property bool addingLink: false
  property string message: ""
  property bool failed: false
  property color foreground: Color.foreground
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property string pendingRemoval: ""
  property alias urlField: urlInput
  property alias titleField: titleInput
  signal saveRequested()
  signal playRequested(string id)
  signal removeRequested(string id)
  spacing: Style.space(12)

  Column {
    width: parent.width
    spacing: Style.space(5)
    Row {
      width: parent.width
      spacing: Style.space(8)
      Text {
        width: parent.width - addButton.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: "Your listening shelf"
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
      Button {
        id: addButton
        objectName: "addYoutube"
        text: root.addingLink ? "Close" : "Add link"
        iconText: root.addingLink ? "\uf00d" : "\uf067"
        foreground: root.foreground
        focusable: true
        onClicked: { root.addingLink = !root.addingLink; if (root.addingLink) urlInput.forceActiveFocus() }
      }
    }
    Text {
      width: parent.width
      text: "A video, a long conversation, a favourite mix. Save it here and add a little rain."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  BorderSurface {
    visible: root.addingLink || root.entries.length === 0
    width: parent.width
    implicitHeight: form.implicitHeight + Style.space(20)
    height: implicitHeight
    radius: Style.cornerRadius
    color: Qt.alpha(root.foreground, 0.025)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    Column {
      id: form
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(10)
      spacing: Style.space(8)
      TextField {
        id: urlInput
        objectName: "youtubeUrl"
        width: parent.width
        placeholderText: "Paste a YouTube link"
        maximumLength: 2048
        foreground: root.foreground
        onAccepted: root.saveRequested()
        Keys.onEscapePressed: focus = false
      }
      TextField {
        id: titleInput
        objectName: "youtubeTitle"
        width: parent.width
        placeholderText: "Give it a name (optional)"
        maximumLength: 160
        foreground: root.foreground
        onAccepted: root.saveRequested()
        Keys.onEscapePressed: focus = false
      }
      Button {
        objectName: "saveYoutube"
        width: parent.width
        text: root.saving ? "Saving…" : "Save to library"
        iconText: "\uf067"
        bordered: true
        selected: urlInput.text.trim().length > 0
        enabled: !root.saving && urlInput.text.trim().length > 0
        foreground: root.foreground
        focusable: true
        onClicked: root.saveRequested()
      }
    }
  }

  Text {
    width: parent.width
    visible: !root.available || root.message !== ""
    text: !root.available ? "Playback needs yt-dlp. You can still save links now." : root.message
    textFormat: Text.PlainText
    color: root.failed ? Color.urgent : root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }
  Text {
    visible: root.entries.length === 0
    width: parent.width
    text: "Your shelf is empty. Add your first link above."
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  Repeater {
    model: root.entries
    Column {
      required property var modelData
      width: root.width
      spacing: Style.space(4)
      Row {
        width: parent.width
        spacing: Style.space(6)
        StationRow {
          width: parent.width - removeButton.width - parent.spacing
          name: modelData.name
          description: modelData.position > 5 ? "Continue from " + Math.floor(modelData.position / 60) + " min" : "YouTube · audio only"
          glyph: "\uf144"
          current: root.selectedId === modelData.id
          playing: current && root.playing
          animate: false
          foreground: root.foreground
          fontFamily: root.fontFamily
          activeFocusOnTab: true
          Keys.onReturnPressed: root.playRequested(modelData.id)
          Keys.onSpacePressed: root.playRequested(modelData.id)
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.playRequested(modelData.id)
          }
        }
        Button {
          id: removeButton
          objectName: "removeYoutube-" + modelData.id
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf00d"
          tooltipText: "Remove from library"
          foreground: root.muted
          focusable: true
          onClicked: root.pendingRemoval = root.pendingRemoval === modelData.id ? "" : modelData.id
        }
      }
      Row {
        visible: root.pendingRemoval === modelData.id
        spacing: Style.space(8)
        Button {
          text: "Remove saved link"
          objectName: "confirmRemoveYoutube-" + modelData.id
          foreground: root.foreground
          focusable: true
          onClicked: { root.removeRequested(modelData.id); root.pendingRemoval = "" }
        }
        Button {
          text: "Keep it"
          foreground: root.muted
          focusable: true
          onClicked: root.pendingRemoval = ""
        }
      }
    }
  }
}
