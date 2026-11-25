import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import "../Reorder.js" as Reorder
import "../Settings.js" as Settings
import "../TrayModel.js" as TrayModel
import "../IconSource.js" as IconSource
import "../ui"

// A Windows-style system tray: the icons apps publish while running in the
// background (Steam, Discord, Notion, Chrome with "continue running"...),
// over Linux's StatusNotifierItem protocol, which Quickshell's SystemTray
// reads.
//
//   left click    the app's own action; if it does nothing, bring its window
//                 forward or start it, Windows-style (see leftClick)
//   middle click  its secondary action
//   right click   its menu, drawn here in the theme's style, plus our own
//                 Pin/Unpin and Hide rows
//   scroll        passed to the app (some use it, e.g. volume)
//   drag          reorder the icons on the bar (the order setting)
//
// Icons sit in the order setting (set by dragging). Pinned ones always stay
// on the bar; the rest fill up to maxIcons, and the unpinned icons last in
// the order wait behind a "^" button in a flyout. Icons an Omarchy widget already
// shows (Superwhisper's, with its widget on a bar) are left out, as Omarchy's
// own tray does. Settings: TrayModel.SETTINGS and the README.
Item {
  id: tray

  // Set by the bottom bar (BarWindow.qml).
  property var bar: null
  property var panel: null
  property var settings: ({})

  readonly property var parsedSettings: Settings.parse(settings, TrayModel.SETTINGS)
  readonly property var cfg: parsedSettings.settings

  onParsedSettingsChanged: {
    var problems = parsedSettings.problems
    for (var i = 0; i < problems.length; i++) console.warn("transom: tray setting ignored: " + problems[i])
  }

  // ---------------------------------------------------------------- icons

  // Every app icon that wants to be seen. Passive ones are asking not to be.
  readonly property var items: {
    var values = SystemTray.items.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      if (values[i].status !== Status.Passive) out.push(values[i])
    }
    return out
  }

  // The top bar's layout and this bar's (only the widgets switched on), to
  // spot icons a widget stands in for (strict review R1-L7).
  readonly property var layouts: bar ? [bar.topBarLayout, bar.shownLayout] : []

  // { bar: [items], overflow: [items] }
  readonly property var arranged: {
    var icons = tray.items.map(function(item, index) {
      return { key: index, id: String(item.id || ""), title: String(item.title || ""), tooltipTitle: String(item.tooltipTitle || "") }
    })
    var result = TrayModel.arrange(icons, tray.cfg, tray.layouts)
    return {
      bar: result.bar.map(function(key) { return tray.items[key] }),
      overflow: result.overflow.map(function(key) { return tray.items[key] })
    }
  }

  readonly property bool hasOverflow: arranged.overflow.length > 0
  readonly property int slot: Style.bar.iconSlot
  readonly property int iconSize: Style.space(cfg.iconSize)
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground

  implicitWidth: (hasOverflow ? slot : 0) + arranged.bar.length * slot
  implicitHeight: bar ? bar.barSize : 26

  function nameOf(item) {
    return TrayModel.nameFor({ id: String(item.id || ""), title: String(item.title || ""), tooltipTitle: String(item.tooltipTitle || "") })
  }

  // ------------------------------------------------------------- clicks

  function clicked(button, which) {
    var item = button.trayItem
    if (!item) return
    tooltip.hide()
    // An icon in the flyout opens its menu from the "^" button instead,
    // since the flyout closes.
    var anchor = button.inFlyout ? overflowButton : button
    if (which === Qt.RightButton) {
      tray.openMenu(item, anchor)
      return
    }
    tray.closePopups()
    if (which === Qt.MiddleButton) {
      console.log("transom: tray secondary action for " + tray.nameOf(item))
      item.secondaryActivate()
    } else {
      tray.leftClick(item, anchor)
    }
  }

  // A left click. Each app decides what a click on its icon does; some do
  // something real (Discord toggles its window, Flameshot takes a
  // screenshot), others nothing at all (Chrome, Notion), and some icons are
  // only a menu (Steam's AppIndicator). So the app goes first, and the tray
  // steps in only if nothing happened, Windows-style:
  //   1. the click goes to the app
  //   2. replaceLeftClickWaitMs later, if the app's windows or focus changed,
  //      the app handled it: done
  //   3. otherwise bring its window forward (restoring a minimized one),
  //      else start it from its launcher (a running single-instance app
  //      shows its window), else open its menu
  // replaceLeftClick: false, or the app in nativeClick, skips 2 and 3.
  // ./tray-window gives the app's windows (by process, over D-Bus). The
  // "before" view is fetched when the pointer reaches the icon, so the
  // app's own click is never delayed: with no fresh view from the hover (or
  // a click already being judged), the app gets its click and that's all
  // (strict review R2-L6: clicks used to wait for a lookup, or be dropped).
  function leftClick(item, anchor) {
    var icon = tray.iconOf(item)
    var name = tray.nameOf(item)
    // An icon that says it is only a menu: the menu is the app's own answer.
    if (item.onlyMenu && item.hasMenu) {
      tray.openMenu(item, anchor)
      return
    }
    if (TrayModel.clickIsNative(icon, tray.cfg)) {
      console.log("transom: tray " + name + " -> its own click only")
      item.activate()
      return
    }
    var fresh = tray.hoverView && tray.hoverView.item === item && Date.now() - tray.hoverView.at < 5000
    if (!fresh || clickLookup.running || clickTimer.running) {
      console.log("transom: tray " + name + " -> its own click (no view to judge it by)")
      item.activate()
      return
    }
    tray.clickItem = item
    tray.clickAnchor = anchor
    tray.clickBefore = tray.hoverView.view
    tray.clickAndWait()
  }

  property var clickItem: null
  property Item clickAnchor: null
  property var clickBefore: null

  function clickAndWait() {
    if (!tray.clickItem) return
    console.log("transom: tray " + tray.nameOf(tray.clickItem) + " -> its own click first")
    tray.clickItem.activate()
    clickTimer.interval = tray.cfg.replaceLeftClickWaitMs
    clickTimer.restart()
  }

  Timer {
    id: clickTimer
    onTriggered: if (tray.clickItem) tray.lookUp(clickLookup, tray.clickItem, "after")
  }

  // Step 3, once the app has had its chance.
  function stepIn(after) {
    var item = tray.clickItem
    var anchor = tray.clickAnchor
    tray.clickItem = null
    if (!item) return
    var entry = tray.entryForIcon(item)
    var plan = TrayModel.afterClick(tray.clickBefore, after, { hasLauncher: !!entry, hasMenu: item.hasMenu })
    console.log("transom: tray " + tray.nameOf(item) + " -> " + (plan === "app" ? "the app handled it" : plan))
    if (plan === "focus") tray.bar.focusWindow(after.window)
    else if (plan === "restore") tray.bar.restoreWindow(after.window,
      tray.cfg.restoreTo === "origin" && after.minimizedFrom >= 1 ? after.minimizedFrom : tray.workspaceId)
    else if (plan === "launch") tray.bar.launchEntry(entry)
    else if (plan === "menu") tray.openMenu(item, anchor)
  }

  // The app's view (./tray-window) as the pointer reaches its icon.
  property var hoverView: null

  function hovering(item) {
    if (!item || hoverLookup.running || TrayModel.clickIsNative(tray.iconOf(item), tray.cfg)) return
    tray.lookUp(hoverLookup, item, "hover")
  }

  // ./tray-window under an overall deadline: 3 s, then killed. A click's
  // lookup that answers later than staleMs is dropped rather than acted on
  // (strict review R1-M3: one hung app made the step-in land a minute late).
  readonly property int staleMs: 1500

  function lookUp(process, item, phase) {
    process.item = item
    process.phase = phase
    process.startedAt = Date.now()
    process.command = ["timeout", "-k", "1", "3", tray.bar.pluginDir + "/tray-window", String(item.id || ""), tray.nameOf(item)]
    process.running = true
  }

  function lookedUp(process, text) {
    var view = null
    try { view = JSON.parse(text) } catch (error) { view = null }
    // A lookup that failed or timed out: never read as "nothing changed".
    if (!view || typeof view !== "object" || Array.isArray(view)) view = { failed: true }
    var late = Date.now() - process.startedAt > tray.staleMs
    if (process.phase === "hover") {
      tray.hoverView = view.failed ? null : { item: process.item, view: view, at: Date.now() }
    } else if (process.phase === "after") {
      if (late) {
        console.log("transom: tray " + tray.nameOf(process.item) + " -> no answer in time; the app had its click")
        tray.clickItem = null
        return
      }
      tray.stepIn(view)
    }
  }

  component Lookup: Process {
    id: lookup
    property var item: null
    property string phase: ""
    property double startedAt: 0
    stdout: StdioCollector {
      onStreamFinished: tray.lookedUp(lookup, text)
    }
  }

  Lookup { id: hoverLookup }
  Lookup { id: clickLookup }

  readonly property var monitor: panel ? Hyprland.monitorFor(panel.screen) : null
  readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1

  // The app's launcher, by the names the icon carries ("notion" finds
  // Notion's through its StartupWMClass).
  function entryForIcon(item) {
    var names = [tray.nameOf(item), String(item.tooltipTitle || ""), String(item.title || ""), String(item.id || "")]
    for (var i = 0; i < names.length; i++) {
      if (!names[i]) continue
      var entry = DesktopEntries.heuristicLookup(names[i])
      if (entry && !entry.noDisplay) return entry
    }
    return null
  }

  // The icon as TrayModel sees it.
  function iconOf(item) {
    return { id: String(item.id || ""), title: String(item.title || ""), tooltipTitle: String(item.tooltipTitle || "") }
  }

  function togglePin(item) {
    tray.bar.updateWidget("tray", { pinned: TrayModel.togglePin(tray.iconOf(item), tray.cfg.pinned) })
  }

  function hideIcon(item) {
    var name = tray.nameOf(item)
    if (name && tray.cfg.hidden.indexOf(name) < 0) tray.bar.updateWidget("tray", { hidden: tray.cfg.hidden.concat([name]) })
  }

  // The bar calls this to close our popups when another widget opens one.
  function closePopups() {
    tray.menuOpen = false
    tray.flyoutOpen = false
  }

  // Whether one of its popups is open (the bar stays up while one is).
  readonly property bool popupVisible: flyout.open || menuPopup.open

  // ------------------------------------------------------------- the row

  Row {
    height: parent.height

    Item {
      id: overflowButton

      readonly property string tipText: tray.arranged.overflow.length === 1
        ? "1 more icon" : tray.arranged.overflow.length + " more icons"

      visible: tray.hasOverflow
      width: visible ? tray.slot : 0
      height: parent.height

      Rectangle {
        anchors.fill: parent
        anchors.topMargin: Style.spacing.xxs
        anchors.bottomMargin: Style.spacing.xxs
        radius: Style.cornerRadius
        color: tray.flyoutOpen ? Style.selectedFill : overflowMouse.containsMouse ? Style.hoverFill : "transparent"
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        // Nerd Font chevrons: up when closed, down when open (Windows' ^).
        text: tray.flyoutOpen ? "" : ""
        color: tray.foreground
        font.family: tray.bar ? tray.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: overflowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (tray.cfg.tooltip) tooltip.hovered(overflowButton, containsMouse)
        onClicked: {
          tooltip.hide()
          var opening = !tray.flyoutOpen
          tray.closePopups()
          if (opening) {
            if (tray.bar) tray.bar.claimPopup(tray)
            tray.flyoutOpen = true
          }
        }
      }
    }

    Repeater {
      model: tray.arranged.bar
      delegate: TrayButton {
        required property var modelData
        required property int index
        trayItem: modelData
        barIndex: index
        height: tray.height
      }
    }
  }

  // ------------------------------------------------------------- flyout

  property bool flyoutOpen: false
  onHasOverflowChanged: if (!hasOverflow) flyoutOpen = false

  AnchoredPopup {
    id: flyout
    target: overflowButton
    open: tray.flyoutOpen && tray.hasOverflow
    onOutsideClicked: tray.flyoutOpen = false

    MenuCard {
      readonly property int columns: Math.max(1, Math.min(5, tray.arranged.overflow.length))
      contentWidth: columns * tray.slot

      Grid {
        columns: parent ? Math.max(1, Math.min(5, tray.arranged.overflow.length)) : 1

        Repeater {
          model: tray.arranged.overflow
          delegate: TrayButton {
            required property var modelData
            trayItem: modelData
            inFlyout: true
            height: tray.slot
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- menu

  // The app's menu (DBusMenu), drawn in our own popup. Qt's native menus
  // can't open in Omarchy's shell, so submenus open in place, with a back
  // row on top: each level keeps its own QsMenuOpener, deepest destroyed
  // first (a child entry belongs to its parent's model). Same approach as
  // Omarchy's tray widget.
  property var menuItem: null
  property bool menuOpen: false
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentEntries: submenuDepth > 0 ? submenuStack[submenuDepth - 1].opener.children : rootOpener.children
  readonly property string menuAppTitle: menuItem ? String(menuItem.title || menuItem.id || "").toLowerCase() : ""
  readonly property bool checkColumn: {
    var values = currentEntries && currentEntries.values ? currentEntries.values : []
    for (var i = 0; i < values.length; i++) {
      if (values[i].buttonType !== QsMenuButtonType.None) return true
    }
    return false
  }

  // Changing level swaps the rows under a pointer that hasn't moved; ignore
  // clicks for a beat so a double click doesn't fire the row that lands
  // there.
  property bool menuSettling: false

  QsMenuOpener {
    id: rootOpener
    menu: tray.menuItem ? tray.menuItem.menu : null
  }

  Component {
    id: openerComponent
    QsMenuOpener {}
  }

  Timer {
    id: settleTimer
    interval: 250
    onTriggered: tray.menuSettling = false
  }

  function settle() {
    tray.menuSettling = true
    settleTimer.restart()
  }

  function openMenu(item, anchor) {
    tray.closePopups()
    tray.resetSubmenus()
    console.log("transom: tray menu for " + tray.nameOf(item))
    if (tray.bar) tray.bar.claimPopup(tray)
    tray.menuItem = item
    menuPopup.target = anchor
    tray.menuOpen = true
  }

  function resetSubmenus() {
    var openers = tray.submenuStack
    tray.submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
    tray.menuSettling = false
  }

  function enterSubmenu(entry, title) {
    var opener = openerComponent.createObject(tray, { menu: entry })
    if (!opener) return
    var stack = tray.submenuStack.slice()
    stack.push({ opener: opener, title: title })
    tray.submenuStack = stack
    tray.settle()
  }

  function leaveSubmenu() {
    if (tray.submenuStack.length === 0) return
    var stack = tray.submenuStack.slice()
    var top = stack.pop()
    tray.submenuStack = stack
    top.opener.destroy()
    tray.settle()
  }

  function entryClicked(entry, label) {
    if (tray.menuSettling) return
    if (entry.hasChildren) {
      tray.enterSubmenu(entry, label)
      return
    }
    console.log("transom: tray menu \"" + label + "\" for " + (tray.menuItem ? tray.nameOf(tray.menuItem) : "?"))
    entry.triggered()
    tray.menuOpen = false
  }

  AnchoredPopup {
    id: menuPopup
    open: tray.menuOpen && !!tray.menuItem
    onOutsideClicked: tray.menuOpen = false
    // Reset once hidden, not on close: the rows would change while it hides.
    onVisibleChanged: if (!visible) tray.resetSubmenus()

    MenuCard {
      contentWidth: Style.space(220)

      MenuItemRow {
        visible: tray.submenuDepth > 0
        text: "‹  " + tray.currentTitle
        onTriggered: if (!tray.menuSettling) tray.leaveSubmenu()
      }

      MenuItemRow {
        visible: tray.submenuDepth > 0
        separator: true
      }

      Repeater {
        model: tray.currentEntries

        delegate: MenuItemRow {
          required property var modelData
          required property int index

          readonly property string label: String(modelData.text || "")
          readonly property bool atRoot: tray.submenuDepth === 0
          // At the top level, some apps lead with an entry named after
          // themselves, or with separators; Omarchy's tray skips those too.
          readonly property bool titleEntry: atRoot && index === 0 && modelData.hasChildren && label.toLowerCase() === tray.menuAppTitle
          readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1

          visible: !titleEntry && !leadingSeparator
          text: label
          separator: modelData.isSeparator
          interactive: modelData.enabled
          checkColumn: tray.checkColumn
          checked: modelData.checkState === Qt.Checked
          // The app supplies its menu's icons: a theme name or Quickshell's
          // own image providers, never a path (IconSource.appIcon).
          iconSource: IconSource.appIcon(modelData.icon, function(iconName) { return Quickshell.iconPath(iconName, true) })
          hasChildren: modelData.hasChildren
          onTriggered: tray.entryClicked(modelData, label)
        }
      }

      // Ours, under the app's own entries (top level only).
      MenuItemRow {
        visible: tray.submenuDepth === 0 && tray.appEntryCount > 0
        separator: true
      }

      MenuItemRow {
        visible: tray.submenuDepth === 0
        text: tray.menuPinned ? "Unpin from bar" : "Pin to bar"
        checkColumn: tray.checkColumn
        onTriggered: {
          if (tray.menuItem) tray.togglePin(tray.menuItem)
          tray.menuOpen = false
        }
      }

      MenuItemRow {
        visible: tray.submenuDepth === 0
        text: "Hide this icon"
        checkColumn: tray.checkColumn
        onTriggered: {
          if (tray.menuItem) tray.hideIcon(tray.menuItem)
          tray.menuOpen = false
        }
      }
    }
  }

  readonly property int appEntryCount: currentEntries && currentEntries.values ? currentEntries.values.length : 0
  readonly property bool menuPinned: !!menuItem && TrayModel.listed(iconOf(menuItem), cfg.pinned)

  // ------------------------------------------------------------- tooltip

  TooltipPopup {
    id: tooltip
    delay: tray.cfg.tooltipDelay
    fontFamily: tray.bar ? tray.bar.fontFamily : Style.font.family
  }

  // ----------------------------------------------------------- components

  // Dragging an icon on the bar: its index there, and where it would land.
  property int dragFrom: -1
  property int dragDrop: -1

  // A drag on the bar changes where icons sit (the order setting). It
  // doesn't pin them; pinning is the menu's Pin to bar.
  function commitDrag(from, to) {
    if (!tray.bar || from < 0 || to < 0 || from === to) return
    var before = tray.arranged.bar.map(tray.iconOf)
    var after = Reorder.moved(before, from, to)
    tray.bar.updateWidget("tray", { order: TrayModel.orderAfterDrag(tray.cfg.order, before, after, Reorder.placeWithin) })
  }

  component TrayButton: Item {
    id: button

    property var trayItem: null
    property bool inFlyout: false
    // Its position on the bar, or -1 in the flyout (which doesn't drag).
    property int barIndex: -1
    readonly property string tipText: trayItem
      ? String(trayItem.tooltipTitle || trayItem.title || tray.nameOf(trayItem) || "") : ""

    // Dragging: this icon follows the pointer; the ones it passes step
    // aside by one slot.
    property bool dragging: false
    property real dragOffset: 0
    property real pressX: 0
    property bool suppressClick: false
    readonly property real shift: barIndex >= 0 ? Reorder.dragShift(barIndex, tray.dragFrom, tray.dragDrop, tray.slot) : 0
    property real shownShift: shift
    Behavior on shownShift {
      enabled: tray.dragFrom >= 0
      NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
    }

    width: tray.slot
    z: dragging ? 1 : 0
    transform: Translate { x: button.dragging ? button.dragOffset : button.shownShift }

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: button.inFlyout ? 0 : Style.spacing.xxs
      anchors.bottomMargin: button.inFlyout ? 0 : Style.spacing.xxs
      radius: Style.cornerRadius
      color: mouse.containsMouse || button.dragging ? Style.hoverFill : "transparent"
    }

    AppIcon {
      anchors.centerIn: parent
      width: tray.iconSize
      height: tray.iconSize
      sources: button.trayItem ? [button.trayItem.icon] : []
      iconStyle: tray.bar && button.trayItem
        ? tray.bar.iconStyleFor([button.trayItem.id, button.trayItem.title, tray.nameOf(button.trayItem)], "tray") : "color"
      tint: tray.bar ? tray.bar.iconTintFor(iconStyle) : tray.foreground
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: {
        if (tray.cfg.tooltip) tooltip.hovered(button, containsMouse)
        if (containsMouse) tray.hovering(button.trayItem)
      }

      onPressed: function(event) {
        button.suppressClick = false
        button.pressX = mouse.mapToItem(tray, event.x, 0).x
        tooltip.hide()
      }

      onPositionChanged: function(event) {
        var count = tray.arranged.bar.length
        if (button.barIndex < 0 || !(event.buttons & Qt.LeftButton) || !tray.cfg.reorder || (tray.bar && tray.bar.locked) || count < 2) return
        var offset = mouse.mapToItem(tray, event.x, 0).x - button.pressX
        if (!button.dragging) {
          if (Math.abs(offset) < Style.space(6)) return
          button.dragging = true
          tray.dragFrom = button.barIndex
          tray.closePopups()
        }
        var min = -button.barIndex * tray.slot
        var max = (count - 1 - button.barIndex) * tray.slot
        button.dragOffset = Math.max(min, Math.min(max, offset))
        tray.dragDrop = Reorder.dropIndex(button.barIndex, button.dragOffset, tray.slot, count)
      }

      onReleased: button.endDrag(true)
      onCanceled: button.endDrag(false)

      onClicked: function(event) {
        if (button.suppressClick) {
          button.suppressClick = false
          return
        }
        tray.clicked(button, event.button)
      }

      onWheel: function(wheel) {
        if (button.trayItem) button.trayItem.scroll(wheel.angleDelta.y, false)
      }
    }

    // A drag ends in a release, which isn't a click.
    function endDrag(commit) {
      if (!button.dragging) return
      var from = tray.dragFrom
      var to = tray.dragDrop
      tray.dragFrom = -1
      tray.dragDrop = -1
      button.dragging = false
      button.dragOffset = 0
      button.suppressClick = true
      if (commit) tray.commitDrag(from, to)
    }
  }
}
