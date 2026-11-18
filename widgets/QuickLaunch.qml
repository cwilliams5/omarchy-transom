import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "../Reorder.js" as Reorder
import "../Settings.js" as Settings
import "../QuickLaunchModel.js" as QuickLaunchModel
import "../ui"

// Quick launch, as on Windows: a row of app buttons, by default left of the
// taskbar buttons.
//
//   left click    a NEW window of the app, on this workspace (the app's
//                 own "New window" action when it has one; apps that only
//                 ever have one window just come forward)
//   middle click  the same
//   right click   menu: the app, its own actions (e.g. Chrome's New
//                 Incognito Window), Remove from quick launch
//   drag          reorder
//
// Which apps: the apps setting on its entry in transom.json (see
// QuickLaunchModel.normalizeItem and the README). The taskbar buttons'
// menu has "Pin to quick launch" too.
Item {
  id: launcher

  // Set by the bar (BarWindow.qml).
  property var bar: null
  property var panel: null
  property var settings: ({})

  readonly property var parsedSettings: Settings.parse(settings, QuickLaunchModel.SETTINGS)
  readonly property var cfg: parsedSettings.settings

  onParsedSettingsChanged: {
    var problems = parsedSettings.problems
    for (var i = 0; i < problems.length; i++) console.warn("transom: quick launch setting ignored: " + problems[i])
  }

  // Every icon sits on the bar's icon grid, like the tray's.
  readonly property int slot: Style.bar.iconSlot
  readonly property int iconSize: Style.space(cfg.iconSize)
  readonly property bool canDrag: cfg.reorder && !(bar && bar.locked) && buttons.length > 1

  implicitWidth: buttons.length * slot
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  // ----------------------------------------- Omarchy's terminal, browser, agent

  property string terminalId: ""
  property string browserId: ""

  Process {
    command: ["xdg-terminal-exec", "--print-id"]
    running: true
    stdout: StdioCollector { onStreamFinished: launcher.terminalId = text.trim().replace(/\.desktop$/, "") }
  }

  Process {
    command: ["omarchy-cmd-default-browser"]
    running: true
    stdout: StdioCollector { onStreamFinished: launcher.browserId = text.trim().replace(/\.desktop$/, "") }
  }

  // ------------------------------------------------------------ the buttons

  function lookup(id) {
    if (!id) return null
    return DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id)
  }

  // A button: the setting's item plus its desktop entry, name and icons.
  function describe(item) {
    var entry = null
    var name = item.name
    var icons = item.icon ? [item.icon] : []
    if (item.special === "terminal") entry = launcher.lookup(launcher.terminalId)
    else if (item.special === "browser") entry = launcher.lookup(launcher.browserId)
    else if (item.special === "agent" && launcher.bar) icons = icons.concat(launcher.bar.agentIcons())
    else if (item.app) entry = launcher.lookup(item.app)
    if (!name) {
      if (item.special === "agent") name = QuickLaunchModel.agentName(launcher.bar ? launcher.bar.agentId : "")
      else if (entry && entry.name) name = String(entry.name)
      else if (item.special) name = QuickLaunchModel.SPECIALS[item.special].name
      else name = item.app || item.command.split(" ")[0]
    }
    if (entry && entry.icon) icons.push(String(entry.icon))
    if (item.app && !item.special) icons.push(item.app, item.app.toLowerCase())
    icons.push(item.special === "terminal" || item.special === "agent" ? "utilities-terminal" : "application-x-executable")
    return { item: item, entry: entry, name: name, icons: icons }
  }

  readonly property var buttons: {
    // Read so the buttons follow apps being installed or removed.
    var installed = DesktopEntries.applications.values.length
    return launcher.cfg.apps.map(launcher.describe)
  }

  // ----------------------------------------------------------- launching

  // The app's own "open a new window" action, if its desktop entry has one
  // (Chrome, Firefox, VS Code...).
  function newWindowAction(entry) {
    var actions = entry ? (Settings.toList(entry.actions) || []) : []
    for (var i = 0; i < actions.length; i++) {
      // new-window (Chrome, Firefox), new-empty-window (VS Code), and spellings of them.
      if (/^new[-_ ]?(empty[-_ ]?)?window$/i.test(String(actions[i].id || ""))) return actions[i]
    }
    return null
  }

  // Runs a command line as its own app (uwsm-app), like Omarchy's launchers.
  function runApp(argv) {
    if (!argv || argv.length === 0) return
    Util.execArgv(["uwsm-app", "--"].concat(argv))
  }

  function launch(button) {
    if (!button) return
    var item = button.item
    console.log("transom: quick launch " + button.name)
    if (item.command) {
      launcher.runApp(["bash", "-lc", item.command])
    } else if (item.special) {
      // Omarchy's own launchers start their app themselves. The agent's
      // takes no arguments.
      var args = item.args
      if (item.special === "agent" && args.length > 0) {
        console.warn("transom: quick launch: the agent takes no args; ignoring " + JSON.stringify(args))
        args = []
      }
      Util.execArgv(QuickLaunchModel.SPECIALS[item.special].command.concat(args))
    } else if (!button.entry) {
      console.warn("transom: quick launch: no app called " + item.app)
    } else if (item.args.length > 0) {
      var words = QuickLaunchModel.commandWith(button.entry.command, item.args)
      // A terminal app (btop, nvim) needs a terminal around it.
      if (button.entry.runInTerminal) Util.execArgv(["omarchy-launch-tui"].concat(words))
      else launcher.runApp(words)
    } else {
      var action = launcher.newWindowAction(button.entry)
      if (action) launcher.runApp(QuickLaunchModel.commandWith(action.command, []))
      else if (launcher.bar) launcher.bar.launchEntry(button.entry)
    }
  }

  function runAction(action) {
    console.log("transom: quick launch action " + action.name)
    launcher.runApp(QuickLaunchModel.commandWith(action.command, []))
  }

  function clicked(index, mouseButton, slotItem) {
    var button = launcher.buttons[index]
    if (!button) return
    tooltip.hide()
    if (mouseButton === Qt.RightButton) {
      launcher.openMenu(index, slotItem)
      return
    }
    if (launcher.bar) launcher.bar.dismissPopups()
    launcher.launch(button)
  }

  // ------------------------------------------------------------- editing

  function rawApps() {
    return Settings.toList(launcher.settings ? launcher.settings.apps : null) || []
  }

  function remove(at) {
    if (launcher.bar) launcher.bar.updateWidget("quicklaunch", { apps: QuickLaunchModel.appsAfterRemove(launcher.rawApps(), at) })
  }

  property int dragFrom: -1
  property int dragDrop: -1

  function commitDrag(from, to) {
    if (!launcher.bar || from < 0 || to < 0 || from === to) return
    var shownAt = launcher.buttons.map(function(button) { return button.item.at })
    var newAt = Reorder.moved(shownAt, from, to)
    launcher.bar.updateWidget("quicklaunch", { apps: QuickLaunchModel.appsAfterReorder(launcher.rawApps(), shownAt, newAt) })
  }

  // ---------------------------------------------------------------- row

  Row {
    height: parent.height

    Repeater {
      model: launcher.buttons.length
      delegate: LaunchButton {
        required property int index
        height: parent.height
        buttonIndex: index
        button: launcher.buttons[index] || null
      }
    }
  }

  component LaunchButton: Item {
    id: slotItem

    property int buttonIndex: -1
    property var button: null
    readonly property string tipText: button ? button.name : ""

    property bool dragging: false
    property real dragOffset: 0
    property real pressX: 0
    property bool suppressClick: false
    readonly property real shift: Reorder.dragShift(buttonIndex, launcher.dragFrom, launcher.dragDrop, launcher.slot)
    property real shownShift: shift
    Behavior on shownShift {
      enabled: launcher.dragFrom >= 0
      NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
    }

    width: launcher.slot
    z: dragging ? 1 : 0
    transform: Translate { x: slotItem.dragging ? slotItem.dragOffset : slotItem.shownShift }

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.spacing.xxs
      anchors.bottomMargin: Style.spacing.xxs
      radius: Style.cornerRadius
      color: mouse.containsMouse || slotItem.dragging ? Style.hoverFill : "transparent"
    }

    AppIcon {
      anchors.centerIn: parent
      width: launcher.iconSize
      height: launcher.iconSize
      sources: slotItem.button ? slotItem.button.icons : []
      iconStyle: launcher.bar && slotItem.button
        ? launcher.bar.iconStyleFor([slotItem.button.item.app, slotItem.button.item.special, slotItem.button.name], "quickLaunch") : "color"
      tint: launcher.bar ? launcher.bar.iconTintFor(iconStyle) : "white"
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (launcher.cfg.tooltip && !menuPopup.visible) tooltip.hovered(slotItem, containsMouse)

      onPressed: function(event) {
        slotItem.suppressClick = false
        slotItem.pressX = mouse.mapToItem(launcher, event.x, 0).x
        tooltip.hide()
      }

      onPositionChanged: function(event) {
        if (!(event.buttons & Qt.LeftButton) || !launcher.canDrag) return
        var count = launcher.buttons.length
        var offset = mouse.mapToItem(launcher, event.x, 0).x - slotItem.pressX
        if (!slotItem.dragging) {
          if (Math.abs(offset) < Style.space(6)) return
          slotItem.dragging = true
          launcher.dragFrom = slotItem.buttonIndex
          launcher.closePopups()
        }
        var min = -slotItem.buttonIndex * launcher.slot
        var max = (count - 1 - slotItem.buttonIndex) * launcher.slot
        slotItem.dragOffset = Math.max(min, Math.min(max, offset))
        launcher.dragDrop = Reorder.dropIndex(slotItem.buttonIndex, slotItem.dragOffset, launcher.slot, count)
      }

      onReleased: slotItem.endDrag(true)
      onCanceled: slotItem.endDrag(false)

      onClicked: function(event) {
        if (slotItem.suppressClick) {
          slotItem.suppressClick = false
          return
        }
        launcher.clicked(slotItem.buttonIndex, event.button, slotItem)
      }
    }

    // A drag ends in a release, which isn't a click.
    function endDrag(commit) {
      if (!slotItem.dragging) return
      var from = launcher.dragFrom
      var to = launcher.dragDrop
      launcher.dragFrom = -1
      launcher.dragDrop = -1
      slotItem.dragging = false
      slotItem.dragOffset = 0
      slotItem.suppressClick = true
      if (commit) launcher.commitDrag(from, to)
    }
  }

  // --------------------------------------------------- tooltip and menu

  TooltipPopup {
    id: tooltip
    delay: launcher.cfg.tooltipDelay
    fontFamily: launcher.bar ? launcher.bar.fontFamily : Style.font.family
  }

  // The bar calls this when another widget opens a popup.
  function closePopups() {
    launcher.closeMenu()
    tooltip.hide()
  }

  property int menuIndex: -1
  // Whether its menu is open (the bar stays up while it is).
  readonly property bool popupVisible: menuPopup.open
  readonly property var menuButton: menuIndex >= 0 ? (buttons[menuIndex] || null) : null
  // The app's own actions, except the new window the top row already is.
  readonly property var menuActions: {
    var entry = menuButton ? menuButton.entry : null
    var actions = entry ? (Settings.toList(entry.actions) || []) : []
    var skip = launcher.newWindowAction(entry)
    return actions.filter(function(action) { return action !== skip })
  }

  function openMenu(index, slotItem) {
    if (launcher.bar) launcher.bar.claimPopup(launcher)
    menuPopup.target = slotItem
    launcher.menuIndex = index
  }

  function closeMenu() {
    launcher.menuIndex = -1
  }

  // Runs a menu choice, then closes the menu.
  function choose(action) {
    var button = launcher.menuButton
    launcher.closeMenu()
    if (button) action(button)
  }

  AnchoredPopup {
    id: menuPopup
    open: !!launcher.menuButton
    onOutsideClicked: launcher.closeMenu()

    MenuCard {
      contentWidth: Style.space(220)

      MenuItemRow {
        text: launcher.menuButton ? launcher.menuButton.name : ""
        onTriggered: launcher.choose(launcher.launch)
      }

      Repeater {
        model: launcher.menuActions
        delegate: MenuItemRow {
          required property var modelData
          text: String(modelData.name || modelData.id || "")
          // Act first: closing the menu destroys this row.
          onTriggered: {
            launcher.runAction(modelData)
            launcher.closeMenu()
          }
        }
      }

      MenuItemRow {
        separator: true
      }

      MenuItemRow {
        text: "Remove from quick launch"
        onTriggered: launcher.choose(function(button) { launcher.remove(button.item.at) })
      }
    }
  }
}
