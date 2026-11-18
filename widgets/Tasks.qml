import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Reorder.js" as Reorder
import "../Settings.js" as Settings
import "../TasksModel.js" as TasksModel
import "../ui"

// A Windows-style taskbar: one button per window on this screen's workspace,
// plus the windows minimized from it (dimmed), in the order they opened or
// were dragged into.
//
//   left click    focus a window, or bring a minimized one back
//                 (clicking the active window does nothing, by default)
//   middle click  close it
//   right click   menu: new window, pin to quick launch, minimize/restore, move to workspace,
//                 float/tile, close
//   scroll        step through the windows
//   drag          reorder
//
// Buttons are ~180px with icon and title, shrink evenly when they don't fit,
// then turn icon-only. Titles are cut off with "…" and never scroll; hovering
// a cut-off one shows the full title. All of this is configurable from the
// taskbar's entry in transom.json (see TasksModel.SETTINGS and the README).
Item {
  id: taskbar

  // Set by the bottom bar (BarWindow.qml).
  property var bar: null
  property var panel: null
  property var settings: ({})
  property real screenCenterX: width / 2

  // Takes all the width its section has left.
  readonly property bool fills: true

  // Its natural width: every button at full size. (Not rowWidth, which
  // depends on the width the section gives it.)
  implicitWidth: TasksModel.rowWidth(buttons.count, preferredWidth, spacing)
  implicitHeight: bar ? bar.barSize : 26

  // ------------------------------------------------------------ settings

  readonly property var parsedSettings: Settings.parse(settings, TasksModel.SETTINGS)
  readonly property var cfg: parsedSettings.settings

  onParsedSettingsChanged: {
    var problems = parsedSettings.problems
    for (var i = 0; i < problems.length; i++) console.warn("transom: tasks setting ignored: " + problems[i])
  }

  // ------------------------------------------------------------- windows

  readonly property var monitor: panel ? Hyprland.monitorFor(panel.screen) : null
  readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1

  // The taskbar's point of view, for TasksModel.belongsTo.
  readonly property var view: {
    var onMonitor = []
    var known = []
    var workspaces = Hyprland.workspaces.values
    for (var i = 0; i < workspaces.length; i++) {
      known.push(workspaces[i].id)
      if (workspaces[i].monitor === taskbar.monitor) onMonitor.push(workspaces[i].id)
    }
    return {
      mode: taskbar.cfg.windows,
      workspaceId: taskbar.workspaceId,
      monitorWorkspaces: onMonitor,
      knownWorkspaces: known,
      showMinimized: taskbar.cfg.minimized !== "hidden"
    }
  }

  // The windows this taskbar shows, in order: { address, toplevel, minimized }.
  readonly property var shown: {
    var found = []
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var toplevel = list[i]
      var window = TasksModel.describe(toplevel)
      if (TasksModel.belongsTo(window, taskbar.view)) {
        found.push({
          address: window.address,
          toplevel: toplevel,
          minimized: window.workspaceName === TasksModel.MINIMIZED_WORKSPACE
        })
      }
    }
    var byKey = {}
    for (var j = 0; j < found.length; j++) byKey[found[j].address] = found[j]
    var keys = TasksModel.applyOrder(found.map(function(entry) { return entry.address }), taskbar.bar ? taskbar.bar.windowOrder : [])
    return keys.map(function(key) { return byKey[key] })
  }

  readonly property var byAddress: {
    var map = {}
    for (var i = 0; i < shown.length; i++) map[shown[i].address] = shown[i]
    return map
  }

  // The buttons follow this model, keyed by window address, so a button
  // survives title and focus changes instead of being rebuilt under the
  // pointer (the same approach as Omarchy's dock).
  ListModel { id: buttons }

  onShownChanged: syncButtons()
  Component.onCompleted: syncButtons()

  function syncButtons() {
    var keys = taskbar.shown.map(function(entry) { return entry.address })
    for (var i = 0; i < keys.length; i++) {
      if (i < buttons.count && buttons.get(i).address === keys[i]) continue
      var found = -1
      for (var j = i + 1; j < buttons.count; j++) {
        if (buttons.get(j).address === keys[i]) { found = j; break }
      }
      if (found >= 0) buttons.move(found, i, 1)
      else buttons.insert(i, { address: keys[i] })
    }
    if (buttons.count > keys.length) buttons.remove(keys.length, buttons.count - keys.length)
  }

  // --------------------------------------------------------- app lookups

  // Entries that can claim a terminal app's window (see claimingEntryId).
  readonly property var terminalEntries: {
    var values = DesktopEntries.applications.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0)
        out.push({ id: entry.id, execString: entry.execString, command: entry.command, runInTerminal: entry.runInTerminal })
    }
    return out
  }

  function appIdOf(toplevel) {
    if (!toplevel) return ""
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    var ipc = toplevel.lastIpcObject || {}
    return String(ipc.class || ipc.initialClass || "")
  }

  function entryFor(appId) {
    if (!appId) return null
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry
    var id = TasksModel.claimingEntryId(appId, taskbar.terminalEntries)
    return id ? DesktopEntries.byId(id) : null
  }

  function iconFor(appId) {
    var entry = taskbar.entryFor(appId)
    var names = [entry ? entry.icon : "", appId, String(appId).toLowerCase(), "application-x-executable"]
    for (var i = 0; i < names.length; i++) {
      var name = String(names[i] || "")
      if (!name) continue
      if (name.charAt(0) === "/") return "file://" + name
      var path = Quickshell.iconPath(name, true)
      if (path) return path
    }
    return ""
  }

  // ------------------------------------------------------------- actions
  // Hyprland commands and app launching live in the bar (Service.qml), shared
  // with the tray.

  function target(address) {
    return taskbar.bar ? taskbar.bar.target(address) : ""
  }

  function dispatch(steps, after) {
    if (taskbar.bar) taskbar.bar.dispatch(steps, after)
  }

  // Focuses a window, switching to its workspace if it's on another one.
  function focusWindow(entry) {
    if (taskbar.bar) taskbar.bar.focusWindow(entry.address)
  }

  // Brings a minimized window back to this screen's workspace.
  function restoreWindow(entry) {
    if (taskbar.bar) taskbar.bar.restoreWindow(entry.address, taskbar.workspaceId)
  }

  function minimizeWindow(entry) {
    if (!taskbar.bar) return
    console.log("transom: minimize " + entry.address)
    Util.execDetached(Util.shellQuote(taskbar.bar.pluginDir + "/minimize") + " " + Util.shellQuote(entry.address))
  }

  function closeWindow(entry) {
    taskbar.dispatch(["hl.dsp.window.close({ " + taskbar.target(entry.address) + " })"])
  }

  function moveToWorkspace(entry, workspace) {
    taskbar.dispatch(["hl.dsp.window.move({ workspace = \"" + workspace + "\", follow = false, " + taskbar.target(entry.address) + " })"])
  }

  function toggleFloating(entry) {
    taskbar.dispatch(["hl.dsp.window.float({ action = \"toggle\", " + taskbar.target(entry.address) + " })"])
  }

  // Starts the app again. Most apps open a new window when started while
  // running.
  function newWindow(entry) {
    if (taskbar.bar) taskbar.bar.launchEntry(taskbar.entryFor(taskbar.appIdOf(entry.toplevel)))
  }

  function clicked(entry, button, slot) {
    if (!entry) return
    taskbar.hideTooltip()
    if (button === Qt.RightButton) {
      taskbar.openMenu(entry.address, slot)
      return
    }
    taskbar.closeMenu()
    if (button === Qt.MiddleButton) {
      if (taskbar.cfg.middleClick === "close") taskbar.closeWindow(entry)
    } else if (entry.minimized) {
      taskbar.restoreWindow(entry)
    } else if (!entry.toplevel.activated) {
      taskbar.focusWindow(entry)
    } else if (taskbar.cfg.activeClick === "minimize") {
      taskbar.minimizeWindow(entry)
    }
  }

  // --------------------------------------------------------------- scroll

  // A mouse wheel notch is 120; a touchpad sends many small steps, which
  // add up to one window per 120.
  property real scrollRemainder: 0

  Timer {
    id: scrollReset
    interval: 400
    onTriggered: taskbar.scrollRemainder = 0
  }

  function scrolled(delta) {
    taskbar.hideTooltip()
    taskbar.scrollRemainder += delta
    scrollReset.restart()
    if (Math.abs(taskbar.scrollRemainder) < 120) return
    var step = taskbar.scrollRemainder < 0 ? 1 : -1
    taskbar.scrollRemainder = 0
    // Minimized windows are skipped: scrolling shouldn't pop them back.
    var open = taskbar.shown.filter(function(entry) { return !entry.minimized })
    var active = open.filter(function(entry) { return entry.toplevel.activated })[0]
    var key = TasksModel.scrollTarget(open.map(function(entry) { return entry.address }), active ? active.address : "", step)
    if (key && (!active || key !== active.address)) taskbar.focusWindow(taskbar.byAddress[key])
  }

  WheelHandler {
    enabled: taskbar.cfg.scroll
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      var delta = Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x) ? event.angleDelta.y : -event.angleDelta.x
      taskbar.scrolled(delta)
    }
  }

  // ----------------------------------------------------------------- drag

  // While a button is dragged: its index, and where it would land.
  property int dragFrom: -1
  property int dragDrop: -1

  function commitReorder(from, to) {
    if (!taskbar.bar || from < 0 || to < 0 || from === to) return
    var keys = taskbar.shown.map(function(entry) { return entry.address })
    var existing = Hyprland.toplevels.values.map(function(toplevel) { return TasksModel.normalizeAddress(toplevel.address) })
    taskbar.bar.windowOrder = Reorder.placeWithin(TasksModel.pruneOrder(taskbar.bar.windowOrder, existing), keys, Reorder.moved(keys, from, to))
  }

  // -------------------------------------------------------------- layout

  readonly property real spacing: Style.spacing.xs
  readonly property real preferredWidth: Style.space(cfg.buttonWidth)
  readonly property real minTextWidth: Style.space(cfg.minTextWidth)
  readonly property real iconOnlyWidth: Style.space(36)
  readonly property int iconSize: Style.bar.iconCanvas

  readonly property var geometry: TasksModel.buttonLayout(width, buttons.count, spacing, preferredWidth, minTextWidth, iconOnlyWidth, cfg.labels === "icon")
  readonly property real slotSize: geometry.width + spacing
  readonly property real rowWidth: TasksModel.rowWidth(buttons.count, geometry.width, spacing)
  readonly property real rowX: TasksModel.rowX(rowWidth, width, screenCenterX, cfg.align)

  clip: true

  Repeater {
    model: buttons

    delegate: Item {
      id: button

      required property string address
      required property int index

      readonly property var entry: taskbar.byAddress[address] || null
      readonly property var toplevel: entry ? entry.toplevel : null
      readonly property bool minimized: !!entry && entry.minimized
      readonly property bool active: !!toplevel && toplevel.activated && !minimized
      readonly property bool urgent: taskbar.cfg.urgentTint && !!toplevel && toplevel.urgent
      readonly property string appId: taskbar.appIdOf(toplevel)
      readonly property string title: toplevel && toplevel.title ? toplevel.title : appId
      // The title isn't fully visible, so hovering shows it in a tooltip.
      readonly property bool cutOff: !taskbar.geometry.showText || titleText.truncated
      // What the tooltip shows (TooltipPopup reads it).
      readonly property string tipText: title

      // Dragging: this button follows the pointer; the ones it passes step
      // aside by one slot.
      property bool dragging: false
      property real dragOffset: 0
      property real pressX: 0
      property bool suppressClick: false
      readonly property real shift: Reorder.dragShift(index, taskbar.dragFrom, taskbar.dragDrop, taskbar.slotSize)
      property real shownShift: shift
      Behavior on shownShift {
        enabled: taskbar.dragFrom >= 0
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }

      x: taskbar.rowX + index * taskbar.slotSize + (dragging ? dragOffset : shownShift)
      z: dragging ? 1 : 0
      width: taskbar.geometry.width
      height: taskbar.height

      Rectangle {
        anchors.fill: parent
        anchors.topMargin: Style.spacing.xxs
        anchors.bottomMargin: Style.spacing.xxs
        radius: Style.cornerRadius
        color: button.active ? Style.selectedFill
          : mouse.containsMouse || button.dragging ? Style.hoverFill
          : button.urgent ? Util.alpha(taskbar.bar ? taskbar.bar.urgent : Commons.Color.urgent, 0.3)
          : "transparent"
      }

      // The active window's underline, like Windows'.
      Rectangle {
        visible: button.active
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.xxs
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Style.spacing.md * 2
        height: Math.max(2, Style.spacing.xxs)
        radius: height / 2
        color: Commons.Color.accent
      }

      Item {
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.md
        anchors.rightMargin: Style.spacing.md
        opacity: button.minimized && taskbar.cfg.minimized === "dimmed" ? 0.5 : 1

        Image {
          id: icon
          x: taskbar.geometry.showText ? 0 : Math.round((parent.width - width) / 2)
          anchors.verticalCenter: parent.verticalCenter
          width: taskbar.iconSize
          height: taskbar.iconSize
          sourceSize: Qt.size(taskbar.iconSize * 2, taskbar.iconSize * 2)
          source: taskbar.iconFor(button.appId)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
        }

        Text {
          id: titleText
          visible: taskbar.geometry.showText
          anchors.left: icon.right
          anchors.leftMargin: Style.spacing.md
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: button.title
          elide: Text.ElideRight
          maximumLineCount: 1
          color: taskbar.bar ? taskbar.bar.foreground : Commons.Color.foreground
          font.family: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onContainsMouseChanged: taskbar.hovered(button, containsMouse)

        onPressed: function(event) {
          button.suppressClick = false
          button.pressX = mouse.mapToItem(taskbar, event.x, 0).x
          taskbar.hideTooltip()
        }

        onPositionChanged: function(event) {
          if (!(event.buttons & Qt.LeftButton) || !taskbar.cfg.reorder || (taskbar.bar && taskbar.bar.locked) || buttons.count < 2) return
          var offset = mouse.mapToItem(taskbar, event.x, 0).x - button.pressX
          if (!button.dragging) {
            if (Math.abs(offset) < Style.space(6)) return
            button.dragging = true
            taskbar.dragFrom = button.index
            taskbar.closeMenu()
          }
          var min = -button.index * taskbar.slotSize
          var max = (buttons.count - 1 - button.index) * taskbar.slotSize
          button.dragOffset = Math.max(min, Math.min(max, offset))
          taskbar.dragDrop = Reorder.dropIndex(button.index, button.dragOffset, taskbar.slotSize, buttons.count)
        }

        onReleased: button.endDrag(true)
        onCanceled: button.endDrag(false)

        onClicked: function(event) {
          if (button.suppressClick) {
            button.suppressClick = false
            return
          }
          taskbar.clicked(button.entry, event.button, button)
        }
      }

      // A drag ends in a release, which isn't a click.
      function endDrag(commit) {
        if (!button.dragging) return
        var from = taskbar.dragFrom
        var to = taskbar.dragDrop
        taskbar.dragFrom = -1
        taskbar.dragDrop = -1
        button.dragging = false
        button.dragOffset = 0
        button.suppressClick = true
        if (commit) taskbar.commitReorder(from, to)
      }
    }
  }


  // -------------------------------------------------------------- tooltip

  // The full title, shown after hovering a button whose title is cut off
  // (or hidden, in icon-only mode).
  TooltipPopup {
    id: tooltip
    delay: taskbar.cfg.tooltipDelay
    fontFamily: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
  }

  function hovered(slot, inside) {
    if (inside && !(taskbar.cfg.tooltip && slot.cutOff && taskbar.dragFrom < 0 && !menuPopup.visible)) return
    tooltip.hovered(slot, inside)
  }

  function hideTooltip() {
    tooltip.hide()
  }

  // The bar calls this to close our popups when another widget opens one.
  function closePopups() {
    taskbar.closeMenu()
  }

  // ---------------------------------------------------------------- menu

  property string menuAddress: ""
  readonly property var menuEntry: menuAddress ? (byAddress[menuAddress] || null) : null
  readonly property bool menuMinimized: !!menuEntry && menuEntry.minimized
  readonly property bool menuFloating: !!menuEntry && !!(menuEntry.toplevel.lastIpcObject || {}).floating
  readonly property var menuDesktopEntry: menuEntry ? entryFor(appIdOf(menuEntry.toplevel)) : null
  readonly property bool menuCanLaunch: !!menuDesktopEntry
  readonly property bool menuPinned: !!menuDesktopEntry && !!bar && bar.isPinnedToQuickLaunch(menuDesktopEntry.id)
  readonly property int menuWorkspaceId: {
    if (!menuEntry || menuMinimized) return -1
    var workspace = menuEntry.toplevel.workspace
    return workspace ? workspace.id : -1
  }

  function openMenu(address, slot) {
    console.log("transom: menu opened for " + address)
    if (taskbar.bar) taskbar.bar.claimPopup(taskbar)
    menuPopup.target = slot
    taskbar.menuAddress = address
  }

  function closeMenu() {
    taskbar.menuAddress = ""
  }

  // The window went away, or the screen changed workspace.
  onMenuEntryChanged: if (menuAddress !== "" && !menuEntry) closeMenu()
  onWorkspaceIdChanged: {
    closeMenu()
    hideTooltip()
  }

  // Runs a menu choice for the window the menu is open for, then closes it.
  function choose(label, action) {
    var entry = taskbar.menuEntry
    console.log("transom: menu \"" + label + "\" clicked" + (entry ? "" : " but its window is gone"))
    if (entry) action(entry)
    taskbar.closeMenu()
  }

  AnchoredPopup {
    id: menuPopup
    open: !!taskbar.menuEntry
    onOutsideClicked: {
      console.log("transom: menu closed by a click outside it")
      taskbar.closeMenu()
    }
    onVisibleChanged: if (visible) taskbar.hideTooltip()

    MenuCard {
      contentWidth: Style.space(210)

      MenuItemRow {
        visible: taskbar.menuCanLaunch
        text: "New window"
        onTriggered: taskbar.choose(text, taskbar.newWindow)
      }

      // Windows' "Pin to taskbar", for the quick launch buttons.
      MenuItemRow {
        visible: taskbar.menuCanLaunch
        text: taskbar.menuPinned ? "Unpin from quick launch" : "Pin to quick launch"
        onTriggered: {
          var id = taskbar.menuDesktopEntry.id
          var pinned = taskbar.menuPinned
          taskbar.choose(text, function() {
            if (pinned) taskbar.bar.unpinFromQuickLaunch(id)
            else taskbar.bar.pinToQuickLaunch(id)
          })
        }
      }

      MenuItemRow {
        text: taskbar.menuMinimized ? "Restore" : "Minimize"
        onTriggered: taskbar.choose(text, taskbar.menuMinimized ? taskbar.restoreWindow : taskbar.minimizeWindow)
      }

      // Move to workspace: one button per workspace.
      Item {
        width: parent.width
        height: Style.spacing.popupRowHeight

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Move to"
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Repeater {
            model: taskbar.cfg.workspaces

            delegate: Rectangle {
              id: chip

              required property int index
              readonly property int workspace: index + 1
              // The window's own workspace; a minimized one has none.
              readonly property bool current: workspace === taskbar.menuWorkspaceId

              width: height
              height: Style.spacing.popupRowHeight - Style.spacing.sm * 2
              radius: Style.cornerRadius
              color: chip.current ? Style.selectedFill : chipMouse.containsMouse ? Style.hoverFill : "transparent"

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(chip.workspace)
                color: Commons.Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: chipMouse
                anchors.fill: parent
                enabled: !chip.current
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: taskbar.choose("Move to " + chip.workspace, function(entry) {
                  taskbar.moveToWorkspace(entry, chip.workspace)
                })
              }
            }
          }
        }
      }

      MenuItemRow {
        visible: !taskbar.menuMinimized
        text: taskbar.menuFloating ? "Tile" : "Float"
        onTriggered: taskbar.choose(text, taskbar.toggleFloating)
      }

      MenuItemRow {
        separator: true
      }

      MenuItemRow {
        text: "Close"
        onTriggered: taskbar.choose(text, taskbar.closeWindow)
      }
    }
  }
}
