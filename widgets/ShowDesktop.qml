import QtQuick
import Quickshell
import Quickshell.Hyprland
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
  readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  readonly property string tipText: "Show desktop"

  // What the last click minimized, by workspace id.
  property var minimizedByUs: ({})

  // The windows open on this workspace (not minimized), least recently
  // used first, so the active one comes back last and gets focus.
  function openWindows() {
    var view = { mode: "workspace", workspaceId: root.workspaceId, showMinimized: false }
    var found = []
    var list = Hyprland.toplevels.values
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
    var list = Hyprland.toplevels.values
    return ours.filter(function(address) {
      for (var i = 0; i < list.length; i++) {
        var window = TasksModel.describe(list[i])
        // Still minimized, and from here: Hyprland reuses the address of a
        // closed window (strict review R1-L1).
        if (window.address === address) return window.workspaceName === TasksModel.MINIMIZED_WORKSPACE
          && TasksModel.minimizedFrom(window.tags) === root.workspaceId
      }
      return false
    })
  }

  function clicked() {
    if (!root.bar || !(root.workspaceId >= 1)) return
    var open = root.openWindows()
    var next = Object.assign({}, root.minimizedByUs)
    if (open.length > 0) {
      root.bar.minimizeWindows(open)
      next[root.workspaceId] = open
    } else {
      root.bar.restoreWindows(root.stillMinimized(), root.workspaceId)
      next[root.workspaceId] = []
    }
    root.minimizedByUs = next
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
