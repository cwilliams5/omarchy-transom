import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Reorder.js" as Reorder
import "../Settings.js" as Settings
import "../TasksModel.js" as TasksModel
import "../QuickLaunchModel.js" as QuickLaunchModel
import "../IconSource.js" as IconSource
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
    var all = []
    var workspaces = Hyprland.workspaces.values
    for (var i = 0; i < workspaces.length; i++) {
      known.push(workspaces[i].id)
      if (workspaces[i].monitor === taskbar.monitor) onMonitor.push(workspaces[i].id)
      all.push({ id: workspaces[i].id, monitorName: workspaces[i].monitor ? workspaces[i].monitor.name : "" })
    }
    // Screens with no bar (bar option screens): their minimized windows
    // show here, or nowhere would.
    var barNames = (Settings.toList(taskbar.bar ? taskbar.bar.barScreens : []) || []).map(function(screen) { return String(screen.name) })
    return {
      mode: taskbar.cfg.windows,
      workspaceId: taskbar.workspaceId,
      monitorWorkspaces: onMonitor,
      knownWorkspaces: known,
      barlessWorkspaces: TasksModel.barlessWorkspaces(all, barNames),
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
    // Maps keyed by window-supplied strings have no prototype, so a key
    // like "constructor" is never mistaken for an existing entry.
    var byKey = Object.create(null)
    for (var j = 0; j < found.length; j++) byKey[found[j].address] = found[j]
    var keys = TasksModel.applyOrder(found.map(function(entry) { return entry.address }), taskbar.bar ? taskbar.bar.windowOrder : [])
    return keys.map(function(key) { return byKey[key] })
  }

  readonly property var byAddress: {
    var map = Object.create(null)
    for (var i = 0; i < shown.length; i++) map[shown[i].address] = shown[i]
    return map
  }

  // ---------------------------------------------------------- combining

  // Windows' "combine taskbar buttons" (the combine setting): one button
  // per app, always, or only once the windows' own buttons would be
  // squeezed ("full"). Labels are hidden when always combining, as on
  // Windows 11.
  readonly property bool iconsOnly: cfg.labels === "icon" || cfg.combine === "always"
  readonly property bool crowded: cfg.combine === "full"
    && TasksModel.isCrowded(width, shown.length, spacing, preferredWidth, minTextWidth, iconOnlyWidth, cfg.labels === "icon")

  // A window's app, for combining: its desktop entry id, else its app id.
  function groupOf(entry) {
    var appId = taskbar.appIdOf(entry.toplevel)
    if (appId === taskbar.agentAppId) return appId
    var desktop = taskbar.entryFor(appId)
    return desktop ? String(desktop.id) : appId
  }

  // The buttons, in order: { key, group, addresses } (TasksModel.groupButtons).
  readonly property var groupedButtons: {
    var combining = taskbar.cfg.combine === "always" || taskbar.crowded
    return TasksModel.groupButtons(taskbar.shown.map(function(entry) {
      return { address: entry.address, group: combining ? taskbar.groupOf(entry) : "" }
    }), taskbar.cfg.combine, taskbar.crowded)
  }

  readonly property var buttonByKey: {
    var map = Object.create(null)
    for (var i = 0; i < groupedButtons.length; i++) map[groupedButtons[i].key] = groupedButtons[i]
    return map
  }

  // An app's name for its combined button: its desktop entry's name, or the
  // agent's.
  function groupName(group, appId) {
    if (appId === taskbar.agentAppId) return QuickLaunchModel.agentName(taskbar.bar ? taskbar.bar.agentId : "")
    var desktop = taskbar.entryFor(appId)
    return desktop && desktop.name ? String(desktop.name) : String(group || appId)
  }

  // The buttons follow this model, keyed by button key (a window's address,
  // or an app when combined), so a button survives title and focus changes
  // instead of being rebuilt under the pointer (the same approach as
  // Omarchy's dock).
  ListModel { id: buttons }

  onGroupedButtonsChanged: syncButtons()
  Component.onCompleted: syncButtons()

  function syncButtons() {
    taskbar.syncKeyed(buttons, "key", taskbar.groupedButtons.map(function(button) { return button.key }))
  }

  // Makes a ListModel hold keys (in its role) in order with the fewest
  // moves, inserts and removes, so delegates for keys still there live on.
  function syncKeyed(model, role, keys) {
    for (var i = 0; i < keys.length; i++) {
      if (i < model.count && model.get(i)[role] === keys[i]) continue
      var found = -1
      for (var j = i + 1; j < model.count; j++) {
        if (model.get(j)[role] === keys[i]) { found = j; break }
      }
      if (found >= 0) model.move(found, i, 1)
      else {
        var row = {}
        row[role] = keys[i]
        model.insert(i, row)
      }
    }
    if (model.count > keys.length) model.remove(keys.length, model.count - keys.length)
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

  // An app's name, from its desktop entry (for iconStyleExceptions).
  function appName(appId) {
    var desktop = taskbar.entryFor(appId)
    return desktop && desktop.name ? String(desktop.name) : ""
  }

  // Omarchy runs every coding agent in a terminal with this app id.
  readonly property string agentAppId: "org.omarchy.agent"

  // Icon candidates for a window, best first (ui/AppIcon.qml picks).
  // Agent windows get the default agent's logo.
  function iconsFor(appId) {
    if (appId === taskbar.agentAppId && taskbar.bar) {
      var agent = taskbar.bar.agentIcons()
      if (agent.length > 0) return agent.concat(["utilities-terminal"])
    }
    var entry = taskbar.entryFor(appId)
    // The window picks its own app id, so it's only ever a theme icon name
    // (never a URL or a path: IconSource.js).
    var name = IconSource.themeName(appId)
    return [entry ? entry.icon : "", name, name.toLowerCase(), "application-x-executable"]
      .filter(function(candidate) { return !!candidate })
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
    if (taskbar.appIdOf(entry.toplevel) === taskbar.agentAppId) Util.execArgv(["omarchy-agent", "--pick"])
    else if (taskbar.bar) taskbar.bar.launchEntry(taskbar.entryFor(taskbar.appIdOf(entry.toplevel)))
  }

  // A combined button with more than one window: left click lists them,
  // middle click opens another, right click is the app's menu.
  function clickedGroup(group, mouseButton, slot) {
    taskbar.hideTooltip()
    if (mouseButton === Qt.MiddleButton) {
      taskbar.closeMenu()
      taskbar.newWindow(taskbar.byAddress[group.addresses[0]])
    } else if (mouseButton === Qt.RightButton) {
      taskbar.openGroupMenu(group.key, slot)
    } else {
      taskbar.openList(group.key, slot)
    }
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

  // A combined button's windows move together.
  function commitReorder(from, to) {
    if (!taskbar.bar || from < 0 || to < 0 || from === to) return
    var groups = taskbar.groupedButtons.map(function(button) { return button.addresses })
    var existing = Hyprland.toplevels.values.map(function(toplevel) { return TasksModel.normalizeAddress(toplevel.address) })
    taskbar.bar.windowOrder = TasksModel.orderAfterGroupDrag(TasksModel.pruneOrder(taskbar.bar.windowOrder, existing),
      groups, Reorder.moved(groups, from, to), Reorder.placeWithin)
  }

  // -------------------------------------------------------------- layout

  readonly property real spacing: Style.spacing.xs
  readonly property real preferredWidth: Style.space(cfg.buttonWidth)
  readonly property real minTextWidth: Style.space(cfg.minTextWidth)
  readonly property real iconOnlyWidth: Style.space(36)
  readonly property int iconSize: Style.bar.iconCanvas

  readonly property var geometry: TasksModel.buttonLayout(width, buttons.count, spacing, preferredWidth, minTextWidth, iconOnlyWidth, iconsOnly)
  readonly property real slotSize: geometry.width + spacing
  readonly property real rowWidth: TasksModel.rowWidth(buttons.count, geometry.width, spacing)
  readonly property real rowX: TasksModel.rowX(rowWidth, width, screenCenterX, cfg.align)

  clip: true

  Repeater {
    model: buttons

    delegate: Item {
      id: button

      required property string key
      required property int index

      // Its windows: one, or an app's several when combined.
      readonly property var group: taskbar.buttonByKey[key] || null
      readonly property var entries: group ? group.addresses.map(function(address) { return taskbar.byAddress[address] }).filter(function(entry) { return !!entry }) : []
      readonly property bool grouped: entries.length > 1
      readonly property var entry: entries.length > 0 ? entries[0] : null
      readonly property var toplevel: entry ? entry.toplevel : null
      readonly property bool minimized: entries.length > 0 && entries.every(function(one) { return one.minimized })
      readonly property bool active: entries.some(function(one) { return one.toplevel.activated && !one.minimized })
      readonly property bool urgent: taskbar.cfg.urgentTint && entries.some(function(one) { return one.toplevel.urgent })
      readonly property string appId: taskbar.appIdOf(toplevel)
      readonly property string rawTitle: grouped ? taskbar.groupName(group.group, appId)
        : toplevel && toplevel.title ? toplevel.title : appId
      // Without emoji and symbols, if titleSymbols says so (this also stops
      // an animated title, like Claude Code's spinner, from moving).
      readonly property string title: taskbar.cfg.titleSymbols === "strip" ? TasksModel.stripSymbols(rawTitle) : rawTitle
      // The title isn't fully visible, so hovering shows it in a tooltip.
      readonly property bool cutOff: !taskbar.geometry.showText || titleText.truncated
      // What the tooltip shows (TooltipPopup reads it).
      readonly property string tipText: grouped ? title + " (" + entries.length + " windows)" : title
      // What a hover thumbnail shows (ThumbnailPopup reads it).
      readonly property var previewToplevel: !grouped && toplevel ? toplevel : null
      readonly property var previewIcons: taskbar.iconsFor(appId)

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

        AppIcon {
          id: icon
          x: taskbar.geometry.showText ? 0 : Math.round((parent.width - width) / 2)
          anchors.verticalCenter: parent.verticalCenter
          width: taskbar.iconSize
          height: taskbar.iconSize
          sources: taskbar.iconsFor(button.appId)
          // The active window's button and the others can be styled apart
          // (iconStyleOn), e.g. only the active one left in color.
          iconStyle: taskbar.bar
            ? taskbar.bar.iconStyleFor([button.appId, taskbar.appName(button.appId)], button.active ? "activeWindow" : "inactiveWindows") : "color"
          tint: taskbar.bar ? taskbar.bar.iconTintFor(iconStyle) : Commons.Color.foreground
        }

        // How many windows a combined button holds: a small number on the
        // icon's corner.
        Rectangle {
          visible: button.grouped
          anchors.horizontalCenter: icon.right
          anchors.verticalCenter: icon.bottom
          anchors.horizontalCenterOffset: -Style.space(1)
          anchors.verticalCenterOffset: -Style.space(2)
          width: Math.max(height, countText.implicitWidth + Style.space(4))
          height: Style.space(11)
          radius: height / 2
          color: taskbar.bar ? taskbar.bar.foreground : Commons.Color.foreground

          Text {
            id: countText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(button.entries.length)
            color: Commons.Color.bar.background
            font.family: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
            font.pixelSize: Style.space(8)
            font.bold: true
          }
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
          if (button.grouped) taskbar.clickedGroup(button.group, event.button, button)
          else taskbar.clicked(button.entry, event.button, button)
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

  // With thumbnails on, a window's button shows its thumbnail on hover
  // instead (a combined button's thumbnails come with its list).
  ThumbnailPopup {
    id: thumbnail
    delay: taskbar.cfg.tooltipDelay
    fontFamily: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
  }

  function hovered(slot, inside) {
    var busy = taskbar.dragFrom >= 0 || taskbar.popupVisible
    if (taskbar.cfg.thumbnails && slot.previewToplevel) {
      if (inside && busy) return
      thumbnail.hovered(slot, inside)
      return
    }
    if (inside && !(taskbar.cfg.tooltip && slot.cutOff && !busy)) return
    tooltip.hovered(slot, inside)
  }

  function hideTooltip() {
    tooltip.hide()
    thumbnail.hide()
  }

  // The bar calls this to close our popups when another widget opens one.
  function closePopups() {
    taskbar.closeMenu()
    taskbar.hideTooltip()
  }

  // Whether one of its popups is open (the bar stays up while one is).
  readonly property bool popupVisible: menuPopup.open || listPopup.open || stripPopup.open || groupMenuPopup.open

  // ---------------------------------------------------------------- menu

  property string menuAddress: ""
  readonly property var menuEntry: menuAddress ? (byAddress[menuAddress] || null) : null
  readonly property bool menuMinimized: !!menuEntry && menuEntry.minimized
  readonly property bool menuFloating: !!menuEntry && !!(menuEntry.toplevel.lastIpcObject || {}).floating
  readonly property bool menuIsAgent: !!menuEntry && appIdOf(menuEntry.toplevel) === agentAppId
  readonly property var menuDesktopEntry: menuEntry && !menuIsAgent ? entryFor(appIdOf(menuEntry.toplevel)) : null
  // What Pin to quick launch adds: the app's desktop entry, or "agent".
  readonly property string menuPinId: menuIsAgent ? "agent" : menuDesktopEntry ? String(menuDesktopEntry.id) : ""
  readonly property bool menuCanLaunch: menuPinId !== ""
  readonly property bool menuPinned: menuPinId !== "" && !!bar && bar.isPinnedToQuickLaunch(menuPinId)
  readonly property int menuWorkspaceId: {
    if (!menuEntry || menuMinimized) return -1
    var workspace = menuEntry.toplevel.workspace
    return workspace ? workspace.id : -1
  }

  function openMenu(address, slot) {
    console.log("transom: menu opened for " + address)
    if (taskbar.bar) taskbar.bar.claimPopup(taskbar)
    taskbar.listKey = ""
    taskbar.groupMenuKey = ""
    menuPopup.target = slot
    taskbar.menuAddress = address
  }

  function closeMenu() {
    taskbar.menuAddress = ""
    taskbar.listKey = ""
    taskbar.groupMenuKey = ""
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
          var id = taskbar.menuPinId
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

  // ------------------------------------------- combined buttons: list, menu

  // Clicking a combined button lists its windows, like Windows' thumbnail
  // strip: the active one ticked, minimized ones dimmed. Picking one brings
  // it forward (or back, if minimized).
  property string listKey: ""
  readonly property var listGroup: listKey ? (buttonByKey[listKey] || null) : null
  readonly property var listEntries: listGroup
    ? listGroup.addresses.map(function(address) { return taskbar.byAddress[address] }).filter(function(entry) { return !!entry }) : []

  // The list's rows follow this model, keyed by window address, so a row
  // (and its live thumbnail) survives the window list being recomputed.
  ListModel { id: listModel }
  onListEntriesChanged: taskbar.syncKeyed(listModel, "address", taskbar.listEntries.map(function(entry) { return entry.address }))

  function openList(key, slot) {
    // A second click on the same button closes it, as on Windows.
    if (taskbar.listKey === key) {
      taskbar.closeMenu()
      return
    }
    if (taskbar.bar) taskbar.bar.claimPopup(taskbar)
    taskbar.menuAddress = ""
    taskbar.groupMenuKey = ""
    listPopup.target = slot
    stripPopup.target = slot
    taskbar.listKey = key
  }

  // The group went away (its windows closed or were split apart).
  onListGroupChanged: if (listKey !== "" && !listGroup) closeMenu()

  function windowTitle(entry) {
    var raw = entry && entry.toplevel && entry.toplevel.title ? String(entry.toplevel.title) : ""
    return taskbar.cfg.titleSymbols === "strip" ? TasksModel.stripSymbols(raw) : raw
  }

  // An icon URL for menu rows, which take one image.
  function iconUrl(appId) {
    var names = taskbar.iconsFor(appId)
    for (var i = 0; i < names.length; i++) {
      var url = IconSource.resolve(names[i], function(iconName) { return Quickshell.iconPath(iconName, true) }, Quickshell.env("HOME"))
      if (url) return url
    }
    return ""
  }

  AnchoredPopup {
    id: listPopup
    open: taskbar.listEntries.length > 0 && !taskbar.cfg.thumbnails
    onOutsideClicked: taskbar.closeMenu()
    onVisibleChanged: if (visible) taskbar.hideTooltip()

    MenuCard {
      contentWidth: Style.space(260)

      Repeater {
        model: listModel
        delegate: MenuItemRow {
          required property string address
          readonly property var entry: taskbar.byAddress[address] || null
          checkColumn: true
          checked: !!entry && entry.toplevel.activated && !entry.minimized
          dimmed: !!entry && entry.minimized
          iconSource: entry ? taskbar.iconUrl(taskbar.appIdOf(entry.toplevel)) : ""
          text: entry ? (taskbar.windowTitle(entry) || taskbar.appIdOf(entry.toplevel)) : ""
          // Act first: closing the list destroys this row.
          onTriggered: {
            var picked = entry
            if (!picked) return
            if (picked.minimized) taskbar.restoreWindow(picked)
            else taskbar.focusWindow(picked)
            taskbar.closeMenu()
          }
        }
      }
    }
  }

  // With thumbnails on, the list is a strip of them, like Windows': each
  // window's icon, title and live picture. Click one to bring it forward.
  AnchoredPopup {
    id: stripPopup
    open: taskbar.listEntries.length > 0 && taskbar.cfg.thumbnails
    onOutsideClicked: taskbar.closeMenu()
    onVisibleChanged: if (visible) taskbar.hideTooltip()

    BorderSurface {
      width: strip.width + Style.space(12)
      height: strip.height + Style.space(12)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)

      Row {
        id: strip
        x: Style.space(6)
        y: Style.space(6)
        spacing: Style.space(6)

        Repeater {
          // Built only while open: each card captures its window live.
          model: stripPopup.open ? listModel : null
          delegate: Rectangle {
            id: card

            required property string address
            readonly property var modelData: taskbar.byAddress[address] || null
            readonly property bool current: !!modelData && modelData.toplevel.activated && !modelData.minimized

            width: Style.space(200) + Style.space(12)
            height: cardColumn.height + Style.space(12)
            radius: Style.cornerRadius
            color: cardMouse.containsMouse ? Style.hoverFill : current ? Style.selectedFill : "transparent"
            opacity: !!modelData && modelData.minimized ? 0.6 : 1

            Column {
              id: cardColumn
              x: Style.space(6)
              y: Style.space(6)
              width: Style.space(200)
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(6)

                AppIcon {
                  width: Style.space(14)
                  height: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter
                  sources: card.modelData ? taskbar.iconsFor(taskbar.appIdOf(card.modelData.toplevel)) : []
                }

                Text {
                  width: parent.width - Style.space(20)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: card.modelData ? (taskbar.windowTitle(card.modelData) || taskbar.appIdOf(card.modelData.toplevel)) : ""
                  elide: Text.ElideRight
                  color: Commons.Color.popups.text
                  font.family: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              WindowPreview {
                anchors.horizontalCenter: parent.horizontalCenter
                width: implicitWidth
                height: implicitHeight
                maxWidth: Style.space(200)
                maxHeight: Style.space(125)
                fixedSize: true
                toplevel: card.modelData ? card.modelData.toplevel : null
                iconSources: card.modelData ? taskbar.iconsFor(taskbar.appIdOf(card.modelData.toplevel)) : []
              }
            }

            MouseArea {
              id: cardMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // Act first: closing the strip destroys this card.
              onClicked: {
                var entry = card.modelData
                if (!entry) return
                if (entry.minimized) taskbar.restoreWindow(entry)
                else taskbar.focusWindow(entry)
                taskbar.closeMenu()
              }
            }
          }
        }
      }
    }
  }

  // Right-clicking a combined button: the app's menu.
  property string groupMenuKey: ""
  readonly property var groupMenuGroup: groupMenuKey ? (buttonByKey[groupMenuKey] || null) : null
  readonly property var groupMenuEntry: groupMenuGroup ? (byAddress[groupMenuGroup.addresses[0]] || null) : null
  readonly property bool groupMenuIsAgent: !!groupMenuEntry && appIdOf(groupMenuEntry.toplevel) === agentAppId
  readonly property var groupMenuDesktopEntry: groupMenuEntry && !groupMenuIsAgent ? entryFor(appIdOf(groupMenuEntry.toplevel)) : null
  readonly property string groupMenuPinId: groupMenuIsAgent ? "agent" : groupMenuDesktopEntry ? String(groupMenuDesktopEntry.id) : ""
  readonly property bool groupMenuPinned: groupMenuPinId !== "" && !!bar && bar.isPinnedToQuickLaunch(groupMenuPinId)

  function openGroupMenu(key, slot) {
    if (taskbar.bar) taskbar.bar.claimPopup(taskbar)
    taskbar.menuAddress = ""
    taskbar.listKey = ""
    groupMenuPopup.target = slot
    taskbar.groupMenuKey = key
  }

  onGroupMenuGroupChanged: if (groupMenuKey !== "" && !groupMenuGroup) closeMenu()

  AnchoredPopup {
    id: groupMenuPopup
    open: !!taskbar.groupMenuGroup
    onOutsideClicked: taskbar.closeMenu()
    onVisibleChanged: if (visible) taskbar.hideTooltip()

    MenuCard {
      contentWidth: Style.space(210)

      MenuItemRow {
        visible: taskbar.groupMenuPinId !== ""
        text: "New window"
        onTriggered: {
          var entry = taskbar.groupMenuEntry
          taskbar.closeMenu()
          if (entry) taskbar.newWindow(entry)
        }
      }

      MenuItemRow {
        visible: taskbar.groupMenuPinId !== ""
        text: taskbar.groupMenuPinned ? "Unpin from quick launch" : "Pin to quick launch"
        onTriggered: {
          var id = taskbar.groupMenuPinId
          var pinned = taskbar.groupMenuPinned
          taskbar.closeMenu()
          if (pinned) taskbar.bar.unpinFromQuickLaunch(id)
          else taskbar.bar.pinToQuickLaunch(id)
        }
      }

      MenuItemRow {
        separator: true
        visible: taskbar.groupMenuPinId !== ""
      }

      MenuItemRow {
        text: "Close all windows"
        onTriggered: {
          var addresses = taskbar.groupMenuGroup ? taskbar.groupMenuGroup.addresses.slice() : []
          taskbar.closeMenu()
          console.log("transom: close all " + addresses.join(" "))
          for (var i = 0; i < addresses.length; i++) {
            var entry = taskbar.byAddress[addresses[i]]
            if (entry) taskbar.closeWindow(entry)
          }
        }
      }
    }
  }
}
