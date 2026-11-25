import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "../Settings.js" as Settings
import "../TasksModel.js" as TasksModel
import "../ui"

// Show desktop: a thin button at the end of the bar, as on Windows. A click
// minimizes every window on this screen's workspace; the next click brings
// those back, the one that was active last. If something was opened or
// brought back in between, the click minimizes everything again instead
// (Windows does the same). Windows minimized this way are ordinary
// minimized windows: they're on the taskbar, dimmed, like any other.
//
// A second click while the first one's windows are still going down (one
// `minimize` per window, a few hyprctl calls each) waits until they're down
// and Transom has read their tags back, then brings them back: a quick
// double-click shows the desktop and returns, as on Windows. Acted on at
// once, it minimized again and cut the record down to the windows still
// open, or found nothing it could bring back and forgot the rest.
Item {
  id: root

  // Set by the bottom bar (BarWindow.qml).
  property var bar: null
  property var panel: null
  property var settings: ({})

  readonly property var spec: ({
    width: { default: 10, min: 4, max: 40 },   // px
    tooltip: { default: true }
  })
  readonly property var parsedSettings: Settings.parse(settings, spec)
  readonly property var cfg: parsedSettings.settings
  onParsedSettingsChanged: {
    var problems = parsedSettings.problems
    for (var i = 0; i < problems.length; i++) console.warn("transom: show desktop setting ignored: " + problems[i])
  }

  implicitWidth: Style.space(cfg.width)
  implicitHeight: bar ? bar.barSize : 26

  readonly property var monitor: panel ? Hyprland.monitorFor(panel.screen) : null
  // Not readonly, nor toplevels: tests/widget.test.sh sets both.
  property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  property var toplevels: Hyprland.toplevels.values
  readonly property string tipText: "Show desktop"

  // What the last click minimized, by workspace id.
  property var minimizedByUs: ({})

  // From a click that minimizes until its windows are down and their tags
  // read back (TasksModel.REFRESH_EVENTS refresh 100 ms after the moves;
  // settleMs leaves room for that). A click meanwhile is queued for the
  // workspace it was clicked on, and runs then if that workspace is still
  // the one showing; another click there takes it back.
  property bool busy: false
  property bool queued: false
  property int queuedWorkspace: -1
  property double chainStartedAt: 0
  property int settleMs: 300
  // The chain runs under `timeout`: past this, it and everything it started
  // (a hung hyprctl included) are stopped, and a queued click is dropped
  // rather than run late (CLAUDE.md rule 20). Each hyprctl in `minimize`
  // has its own deadline as well, so nothing outlives the shell for long.
  property int chainDeadlineMs: 10000

  // The windows open on this workspace (not minimized), least recently
  // used first, so the active one comes back last and gets focus.
  function openWindows() {
    var view = { mode: "workspace", workspaceId: root.workspaceId, showMinimized: false }
    var found = []
    var list = root.toplevels
    for (var i = 0; i < list.length; i++) {
      var window = TasksModel.describe(list[i])
      if (TasksModel.belongsTo(window, view)) {
        var ipc = list[i].lastIpcObject || {}
        found.push({ address: window.address, recency: Number(ipc.focusHistoryID) || 0 })
      }
    }
    found.sort(function(a, b) { return b.recency - a.recency })
    return found.map(function(window) { return window.address })
  }

  // The windows the last click minimized that are still minimized.
  function stillMinimized() {
    var ours = root.minimizedByUs[root.workspaceId] || []
    var list = root.toplevels
    return ours.filter(function(address) {
      for (var i = 0; i < list.length; i++) {
        var window = TasksModel.describe(list[i])
        if (window.address === address) return TasksModel.restorable(window, root.workspaceId)
      }
      return false
    })
  }

  function clicked() {
    if (!root.bar || !(root.workspaceId >= 1)) return
    if (root.busy) {
      if (root.queued && root.queuedWorkspace === root.workspaceId) {
        root.queued = false
      } else {
        root.queued = true
        root.queuedWorkspace = root.workspaceId
      }
      return
    }
    var open = root.openWindows()
    var next = Object.assign({}, root.minimizedByUs)
    if (open.length > 0) {
      root.busy = true
      root.chainStartedAt = Date.now()
      console.log("transom: show desktop: minimize " + open.join(" "))
      chain.command = ["timeout", "-k", "1", String(root.chainDeadlineMs / 1000), "bash", "-c", root.bar.minimizeCommand(open)]
      chain.running = true
      // A backstop for a chain that never reports back (one that couldn't
      // start sends no exit).
      backstop.interval = root.chainDeadlineMs + 3000
      backstop.restart()
      next[root.workspaceId] = open
    } else {
      var back = root.stillMinimized()
      root.bar.restoreWindows(back, root.workspaceId)
      // Nothing to bring back keeps the record: an empty answer may only
      // mean the tags weren't read back yet.
      if (back.length > 0) next[root.workspaceId] = []
    }
    root.minimizedByUs = next
  }

  // The minimizes are down: wait for the tags, then run a queued click.
  function settled() {
    backstop.stop()
    var again = root.queued && root.workspaceId === root.queuedWorkspace
    root.busy = false
    root.queued = false
    if (again) root.clicked()
  }

  // The chain's end: done, or stopped at its deadline (timeout's 124, or
  // 137 once it had to kill), when a queued click is dropped.
  function chainEnded(code) {
    if (!root.busy) return
    if (code === 124 || code === 137) {
      console.warn("transom: show desktop: minimizing took over " + root.chainDeadlineMs + " ms; stopped")
      root.giveUp()
      return
    }
    console.log("transom: show desktop: minimized in " + (Date.now() - root.chainStartedAt) + " ms")
    settle.interval = root.settleMs
    settle.restart()
  }

  function giveUp() {
    backstop.stop()
    root.busy = false
    root.queued = false
  }

  Process {
    id: chain
    onExited: function(code) { root.chainEnded(code) }
  }

  Timer {
    id: settle
    onTriggered: root.settled()
  }

  Timer {
    id: backstop
    onTriggered: {
      console.warn("transom: show desktop: the minimize chain never reported back; giving up on it")
      root.giveUp()
      chain.running = false
    }
  }

  // A thin line separating it from the widgets before it.
  Rectangle {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: parent.height * 0.5
    color: root.bar ? root.bar.foreground : Commons.Color.foreground
    opacity: 0.3
  }

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: 1
    color: mouse.containsMouse ? Style.hoverFill : "transparent"
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (root.cfg.tooltip) tooltip.hovered(root, containsMouse)
    onClicked: {
      tooltip.hide()
      if (root.bar) root.bar.dismissPopups()
      root.clicked()
    }
  }

  TooltipPopup {
    id: tooltip
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  }
}
