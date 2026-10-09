import QtQuick
import QtQuick.Window
import QtTest
import qs.Commons
import "Plugin" as Lofi

Window {
  id: win
  width: 480; height: 620; visible: true
  QtObject {
    id: host
    property string statusJson: ""
    property var commands: []
    signal actionFinished(var arguments, int exitCode, string message)
    function runAction(args) { commands = commands.concat([args]) }
  }
  Lofi.Panel { id: panel; anchors.fill: parent; hostWidget: host }
  TestCase {
    name: "SkylofiUsability"
    when: win.visible
    property string phase: ""
    function item(name) {
      var result = findChild(panel, name)
      verify(result !== null, "Missing " + name)
      return result
    }
    function initTestCase() {
      Style.fontBaseSize = 12
      Style.spacingScale = 1
      wait(100)
    }
    function init() {
      phase = "init"
      panel.open(); panel.showView(0)
      panel.soundSpaceOpen = false; panel.voiceControlsOpen = false
      panel.libraryOpen = false; panel.soundLibraryOpen = false
      item("soundImport").pending = false; item("soundImport").expanded = false
      item("soundImport").errorMessage = ""
      item("soundImportPath").text = ""; item("soundImportTitle").text = ""
      item("stationSearch").text = ""
      host.statusJson = JSON.stringify({
        running: true, paused: false, main_running: true, main_state: "playing",
        station: "lofi-lilo", name: "Lilo-Fi Radio", category: "lofi",
        source_kind: "radio", main_volume: 65, master_volume: 80,
        spatial_available: true, voice_available: true,
        mix: false, bg_station: "", bg_running: false, bg_state: "stopped",
        nature_layers: [{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:35}],
        imported_sounds: [], animations: false, fade_enabled: true, ducking: true
      })
      panel.applyStatus(host.statusJson)
      for (var name of ["listenScroll", "mixScroll", "settingsScroll"]) item(name).contentY = 0
      host.commands = []
      waitForPolish(win); wait(40)
    }
    function click(name) {
      var control = item(name)
      mouseClick(control, control.width / 2, control.height / 2)
    }
    function openImport() {
      panel.showView(2); panel.soundLibraryOpen = true
      item("soundImport").expanded = true
      item("soundImportPath").text = "/tmp/missing-ambience.ogg"
      item("soundImportTitle").text = "My rain"
      waitForPolish(win); wait(40)
      panel.ensureVisible(item("settingsScroll"), item("soundImportConfirm"))
      waitForPolish(win); wait(40)
    }
    function setDenseMix() {
      var fixture = JSON.parse(host.statusJson), imports = [], layers = []
      for (var index = 0; index < 24; index++) {
        var id = "local-" + index
        imports.push({id:id,name:"Room sound " + (index + 1)})
        if (index < 16) layers.push({id:id,name:"Room sound " + (index + 1),enabled:true,running:true,volume:20})
      }
      fixture.imported_sounds = imports; fixture.nature_layers = layers
      host.statusJson = JSON.stringify(fixture); panel.applyStatus(host.statusJson)
      panel.showView(1)
      waitForPolish(win); wait(40)
    }
    function countNamed(parent, name) {
      var count = parent.objectName === name ? 1 : 0
      if (parent.children) for (var child of parent.children) count += countNamed(child, name)
      return count
    }
    function selectImportWithKeyboard() {
      phase = "open Mix"
      panel.showView(1)
      waitForPolish(win); wait(40)
      var picker = item("naturePicker")
      panel.ensureVisible(item("mixScroll"), picker)
      picker.focusTrigger(); keyClick(Qt.Key_Return)
      phase = "open Add sound"
      tryCompare(picker, "popupOpen", true)
      var search = findChild(picker, "focusDropdownSearch")
      tryCompare(search, "activeFocus", true)
      search.text = "Import audio"
      keyClick(Qt.Key_Return)
      phase = "route to importer"
      tryCompare(panel, "currentView", 2)
      tryCompare(panel, "soundLibraryOpen", true)
      tryCompare(item("soundImport"), "expanded", true)
    }
    function test_denseMixKeepsChannelAndSpaceActionsBeforeSoundList() {
      setDenseMix()
      var scroll = item("mixScroll"), ambience = item("ambienceControls")
      var first = item("sourceCard-local-0")
      verify(item("addVoiceButton").mapToItem(scroll.contentItem, 0, 0).y < ambience.mapToItem(scroll.contentItem, 0, 0).y)
      verify(item("soundSpaceDisclosureButton").mapToItem(scroll.contentItem, 0, 0).y < first.mapToItem(scroll.contentItem, 0, 0).y)
      compare(countNamed(panel, "addVoiceButton"), 1)
      compare(countNamed(panel, "soundSpaceDisclosureButton"), 1)
      panel.ensureVisible(scroll, item("soundSpaceDisclosureButton"))
      item("soundSpaceDisclosureButton").forceActiveFocus(); keyClick(Qt.Key_Return)
      tryCompare(panel, "soundSpaceOpen", true)
      item("soundSpaceBack").forceActiveFocus(); keyClick(Qt.Key_Return)
      compare(panel.soundSpaceOpen, false)
    }
    function test_denseMixOffersOnlyImportWithoutUnusableAddLayerActions() {
      setDenseMix()
      compare(panel.enabledNatureCount, 16)
      compare(item("naturePicker").visible, true)
      compare(item("naturePicker").enabled, true)
      compare(item("naturePicker").options.length, 1)
      compare(item("naturePicker").options[0].value, panel.importSoundAction)
      compare(item("ambienceLimitHint").visible, true)
      selectImportWithKeyboard()
      compare(host.commands.length, 0)
      var dialog = item("soundImportDialog")
      tryCompare(dialog, "visible", true)
      dialog.reject()
      // There is no window manager in offscreen mode to reactivate the owner.
      win.requestActivate()
      tryCompare(item("soundImportPath"), "activeFocus", true)
    }
    function test_importEntryRemainsUniqueForLegacySnapshotWithAllCatalogSoundsEnabled() {
      var picker = item("naturePicker"), entries = picker.options
      compare(entries.filter(function(option) { return option.value === panel.importSoundAction }).length, 1)
      compare(entries[entries.length - 1].value, panel.importSoundAction)
      var fixture = JSON.parse(host.statusJson)
      // Defensive legacy/corrupt snapshot: the current native engine caps mixes
      // at 16. The reachable dense-mix workflow is tested separately above.
      fixture.nature_layers = panel.noiseOptions.map(function(option) {
        return {id:option.value,name:option.label,enabled:true,running:true,volume:20}
      })
      host.statusJson = JSON.stringify(fixture); panel.applyStatus(host.statusJson)
      compare(panel.availableSounds.length, 0)
      compare(picker.options.length, 1)
      compare(picker.visible, false) // Mix is hidden until the shortcut opens it.
      selectImportWithKeyboard()
      compare(host.commands.length, 0)
      item("soundImportDialog").reject()
      win.requestActivate()
      tryCompare(item("soundImportPath"), "activeFocus", true)
      panel.showView(1)
      compare(picker.value, "")
    }
    function test_importShortcutPreservesExistingDraftWithoutReopeningDialog() {
      openImport()
      selectImportWithKeyboard()
      compare(item("soundImportDialog").visible, false)
      compare(item("soundImportPath").text, "/tmp/missing-ambience.ogg")
      compare(item("soundImportTitle").text, "My rain")
      tryCompare(item("soundImportPath"), "activeFocus", true)
      compare(host.commands.length, 0)
    }
    function test_importShortcutShowsPendingRequestWithoutStartingAnother() {
      openImport(); click("soundImportConfirm")
      compare(host.commands.length, 1)
      selectImportWithKeyboard()
      compare(item("soundImportDialog").visible, false)
      compare(item("soundImport").pending, true)
      compare(item("soundImportPath").readOnly, true)
      compare(item("soundImportPath").text, "/tmp/missing-ambience.ogg")
      compare(host.commands.length, 1)
      host.actionFinished(host.commands[0], 1, "Library is full.")
      compare(item("soundImportError").text, "Library is full.")
      compare(item("soundImportTitle").text, "My rain")
    }
    function test_addVoiceCanBeSelectedImmediatelyWithKeyboard() {
      panel.showView(1)
      waitForPolish(win); wait(40)
      panel.ensureVisible(item("mixScroll"), item("addVoiceButton"))
      click("addVoiceButton")
      var trigger = findChild(item("voicePicker"), "focusDropdownTrigger")
      tryCompare(trigger, "activeFocus", true)
      keyClick(Qt.Key_Return)
      tryCompare(item("voicePicker"), "popupOpen", true)
      var search = findChild(item("voicePicker"), "focusDropdownSearch")
      tryCompare(search, "activeFocus", true)
      keyClick(Qt.Key_Escape)
      tryCompare(item("voicePicker"), "popupOpen", false)
      tryCompare(trigger, "activeFocus", true)
    }
    function test_radioSearchShortcutRevealsFieldAfterScrolling() {
      var scroll = item("listenScroll")
      scroll.contentY = scroll.contentHeight - scroll.height
      verify(scroll.contentY > 0)
      keyClick(Qt.Key_F, Qt.ControlModifier)
      tryCompare(item("stationSearch"), "activeFocus", true)
      var point = item("stationSearch").mapToItem(scroll, 0, 0)
      verify(point.y >= 0 && point.y + item("stationSearch").height <= scroll.height)
    }
    function test_importPendingPreventsRepeatClickAndEnter() {
      openImport(); click("soundImportConfirm")
      compare(host.commands.length, 1)
      compare(item("soundImport").pending, true)
      compare(item("soundImportConfirm").enabled, false)
      compare(item("soundImportBrowse").enabled, false)
      compare(item("soundImportPath").readOnly, true)
      item("soundImportPath").forceActiveFocus()
      keyClick(Qt.Key_Return)
      item("soundImport").submit()
      compare(host.commands.length, 1)
      compare(item("soundImportPath").text, "/tmp/missing-ambience.ogg")
    }
    function test_radioSearchShortcutRevealsAlreadyFocusedField() {
      var search = item("stationSearch"), scroll = item("listenScroll")
      search.forceActiveFocus()
      scroll.contentY = scroll.contentHeight - scroll.height
      verify(search.activeFocus && scroll.contentY > 0)
      keyClick(Qt.Key_F, Qt.ControlModifier)
      var point = search.mapToItem(scroll, 0, 0)
      verify(point.y >= 0 && point.y + search.height <= scroll.height)
    }
    function test_importFailureKeepsContextAndAllowsCorrection() {
      openImport(); click("soundImportConfirm")
      panel.actionMessage = "An earlier playback action failed."
      host.actionFinished(host.commands[0], 1, "File not found. Choose another audio file.")
      compare(panel.actionMessage, "")
      compare(item("soundImport").pending, false)
      compare(item("soundImport").expanded, true)
      compare(item("soundImportPath").text, "/tmp/missing-ambience.ogg")
      compare(item("soundImportTitle").text, "My rain")
      compare(item("soundImportError").visible, true)
      compare(item("soundImportError").text, "File not found. Choose another audio file.")
      compare(item("soundImportGuidance").visible, false)
      tryCompare(item("soundImportPath"), "activeFocus", true)
      waitForPolish(win); wait(40)
      var scroll = item("settingsScroll"), path = item("soundImportPath")
      var position = path.mapToItem(scroll, 0, 0)
      verify(position.y >= 0 && position.y + path.height <= scroll.height)
      var error = item("soundImportError"), errorPosition = error.mapToItem(scroll, 0, 0)
      verify(errorPosition.y >= 0 && errorPosition.y + error.height <= scroll.height)
      compare(item("soundImportPath").readOnly, false)
      item("soundImportPath").text = "/tmp/rain.ogg"
      keyClick(Qt.Key_Return)
      compare(host.commands.length, 2)
      compare(host.commands[1], ["sound-import", "/tmp/rain.ogg", "My rain"])
      compare(item("soundImport").pending, true)
      compare(item("soundImportError").visible, false)
    }
    function test_importSuccessClearsOnlyAfterAcknowledgement() {
      openImport(); click("soundImportConfirm")
      compare(item("soundImport").expanded, true)
      compare(item("soundImportTitle").text, "My rain")
      host.actionFinished(host.commands[0], 0, "Imported")
      compare(item("soundImport").pending, false)
      compare(item("soundImport").expanded, false)
      compare(item("soundImportPath").text, "")
      compare(item("soundImportTitle").text, "")
      tryCompare(item("soundImportButton"), "activeFocus", true)
    }
    function test_failedImportAfterChangingTabsKeepsInputWithoutStealingFocus() {
      openImport(); click("soundImportConfirm")
      panel.showView(0); item("stationSearch").forceActiveFocus()
      host.actionFinished(host.commands[0], 1, "Library is full.")
      wait(40)
      compare(item("stationSearch").activeFocus, true)
      compare(item("soundImport").pending, false)
      panel.showView(2)
      compare(item("soundImport").expanded, true)
      compare(item("soundImportPath").text, "/tmp/missing-ambience.ogg")
      compare(item("soundImportError").text, "Library is full.")
    }
    function test_successfulImportAfterChangingTabsStillCompletes() {
      openImport(); click("soundImportConfirm")
      panel.showView(0); item("stationSearch").forceActiveFocus()
      host.actionFinished(host.commands[0], 0, "Imported")
      wait(40)
      compare(item("stationSearch").activeFocus, true)
      panel.showView(2)
      compare(item("soundImport").pending, false)
      compare(item("soundImport").expanded, false)
      compare(item("soundImportPath").text, "")
    }
    function test_pageTabsAcceptAccessiblePressActions() {
      item("mainTab-1").Accessible.pressAction()
      compare(panel.currentView, 1)
      item("mainTab-0").Accessible.pressAction()
      compare(panel.currentView, 0)
      item("savedSourceTab").Accessible.pressAction()
      compare(panel.libraryOpen, true)
      item("radioSourceTab").Accessible.pressAction()
      compare(panel.libraryOpen, false)
      item("mainTab-1").enabled = false
      item("mainTab-1").Accessible.pressAction()
      compare(panel.currentView, 0)
      item("mainTab-1").enabled = true
    }
    function cleanup() {
      if (qtest_results.failed) console.error("USABILITY FAILURE", qtest_results.functionName, phase,
        "view=" + panel.currentView, "focus=" + (win.activeFocusItem ? win.activeFocusItem.objectName : "null"),
        "dialog=" + item("soundImportDialog").visible, "commands=" + JSON.stringify(host.commands))
      item("voicePicker").close()
      item("naturePicker").close()
      item("soundImportDialog").close()
      win.requestActivate()
      wait(40)
    }
    function cleanupTestCase() {
      console.log("USABILITY_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
