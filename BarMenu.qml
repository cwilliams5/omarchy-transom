import QtQuick
import Quickshell
import qs.Commons
import "Settings.js" as Settings
import "TasksModel.js" as TasksModel
import "TrayModel.js" as TrayModel
import "TopBarWidget.js" as TopBarWidget
import "ui"

// The bar's own right-click menu (empty bar space), like Windows' taskbar
// menu: switch widgets on and off, their main options, Omarchy's widgets
// (a second page), Omarchy's task manager, and the settings file. Toggles
// keep the menu open so several can be flipped in a row; the last two rows
// close it. Changes are saved to ~/.config/omarchy/transom.json through
// bar.updateWidget.
AnchoredPopup {
  id: menu

  property var bar: null
  // The bar window it belongs to (for the bar's one-popup rule).
  property var panel: null
  // "main", or "omarchy" for the page listing Omarchy's widgets.
  property string page: "main"

  function show(anchorItem) {
    if (menu.bar) menu.bar.claimPopup(menu)
    menu.page = "main"
    menu.target = anchorItem
    menu.open = true
  }

  // The bar calls this when another popup opens.
  function closePopups() {
    menu.open = false
  }

  // The bar stays up while this is open.
  readonly property bool popupVisible: menu.open

  onOutsideClicked: menu.open = false

  readonly property bool taskbarOn: !!bar && bar.widgetEnabled("tasks")
  readonly property bool trayOn: !!bar && bar.widgetEnabled("tray")
  readonly property bool quickLaunchOn: !!bar && bar.widgetEnabled("quicklaunch")
  readonly property bool showDesktopOn: !!bar && bar.widgetEnabled("showdesktop")
  readonly property var taskbar: Settings.parse(bar ? bar.entryFor("tasks") : null, TasksModel.SETTINGS).settings
  readonly property var tray: Settings.parse(bar ? bar.entryFor("tray") : null, TrayModel.SETTINGS).settings

  readonly property string iconStyle: bar ? bar.iconStyle : "color"
  readonly property string windowIconStyle: bar ? bar.windowIconStyle : "color"
  // The same choices as the top-bar dropdown (TopBarWidget.js), in the
  // menu's lowercase words: one list, so the two can't drift apart.
  function valuesOf(choices) { return choices.map(function(choice) { return choice.value }) }
  function namesOf(choices) {
    var out = ({})
    choices.forEach(function(choice) { out[choice.value] = choice.label.toLowerCase() })
    return out
  }
  readonly property var iconStyles: valuesOf(TopBarWidget.ICON_STYLES)
  readonly property var iconStyleNames: namesOf(TopBarWidget.ICON_STYLES)
  readonly property var combineModes: valuesOf(TopBarWidget.COMBINE)
  readonly property var combineNames: namesOf(TopBarWidget.COMBINE)
  readonly property var windowModes: valuesOf(TopBarWidget.WINDOWS)
  readonly property var windowModeNames: namesOf(TopBarWidget.WINDOWS)

  function change(id, changes) {
    if (menu.bar) menu.bar.updateWidget(id, changes)
  }

  MenuCard {
    contentWidth: Style.space(270)

    // ------------------------------------------------------- main page

    // While transom.json has a problem nothing here can save (the service
    // refuses); this says so and opens the file.
    MenuItemRow {
      visible: menu.page === "main" && !!menu.bar && menu.bar.settingsProblem !== ""
      text: "Settings file has a problem: changes paused…"
      checkColumn: true
      onTriggered: {
        menu.open = false
        menu.bar.openSettingsFile()
      }
    }

    MenuItemRow {
      visible: menu.page === "main" && !!menu.bar && menu.bar.settingsProblem !== ""
      separator: true
    }

    // Windows' wording. Locked, nothing on the bar can be dragged.
    MenuItemRow {
      visible: menu.page === "main"
      text: "Lock the taskbar"
      checkColumn: true
      checked: !!menu.bar && menu.bar.locked
      onTriggered: menu.change("bar", { locked: !checked })
    }

    // Windows' "Show taskbar on all displays", once there's more than one.
    MenuItemRow {
      visible: menu.page === "main" && Quickshell.screens.length > 1
      text: "Show on all displays"
      checkColumn: true
      checked: !!menu.bar && menu.bar.settings.screens === "all"
      // Later, not now: turning this off from another screen's bar removes
      // the very window this menu is running in.
      onTriggered: {
        var bar = menu.bar
        var next = checked ? "primary" : "all"
        menu.open = false
        Qt.callLater(function() { bar.updateWidget("bar", { screens: next }) })
      }
    }

    // Windows' wording again: hidden until the pointer reaches the edge.
    MenuItemRow {
      visible: menu.page === "main"
      text: "Automatically hide the taskbar"
      checkColumn: true
      checked: !!menu.bar && menu.bar.settings.autohide === true
      onTriggered: menu.change("bar", { autohide: !checked })
    }

    // The top-bar widget's icon (bar option topBarIcon). Here because a
    // hidden icon, or a widget dragged off the top bar, can't bring itself
    // back: unticked, a click shows the icon, putting the widget back on
    // Omarchy's bar first if it isn't on one.
    MenuItemRow {
      visible: menu.page === "main"
      text: "Top-bar icon"
      checkColumn: true
      checked: !!menu.bar && menu.bar.widgetOnBar && menu.bar.topBarIconShown
      onTriggered: menu.bar.setTopBarIconShown(!checked)
    }

    // Steps through the icon styles on each click: app icons (the tray and
    // quick launch), then window icons (the taskbar buttons).
    MenuItemRow {
      visible: menu.page === "main"
      text: "Icons: " + menu.iconStyleNames[menu.iconStyle]
      checkColumn: true
      hasChildren: true
      onTriggered: {
        var styles = menu.iconStyles
        menu.change("bar", { iconStyle: styles[(styles.indexOf(menu.iconStyle) + 1) % styles.length] })
      }
    }

    MenuItemRow {
      visible: menu.page === "main"
      text: "Window icons: " + menu.iconStyleNames[menu.windowIconStyle]
      checkColumn: true
      hasChildren: true
      onTriggered: {
        var styles = menu.iconStyles
        menu.bar.setWindowIconStyle(styles[(styles.indexOf(menu.windowIconStyle) + 1) % styles.length])
      }
    }

    MenuItemRow {
      visible: menu.page === "main"
      separator: true
    }

    MenuItemRow {
      visible: menu.page === "main"
      text: "Taskbar buttons"
      checkColumn: true
      checked: menu.taskbarOn
      onTriggered: menu.bar.setWidgetEnabled("tasks", !menu.taskbarOn)
    }

    MenuItemRow {
      visible: menu.page === "main" && menu.taskbarOn
      indent: 1
      text: "Centered"
      checkColumn: true
      checked: menu.taskbar.align === "center"
      onTriggered: menu.change("tasks", { align: checked ? "left" : "center" })
    }

    MenuItemRow {
      visible: menu.page === "main" && menu.taskbarOn
      indent: 1
      text: "Icons only"
      checkColumn: true
      checked: menu.taskbar.labels === "icon"
      onTriggered: menu.change("tasks", { labels: checked ? "title" : "icon" })
    }

    // Windows' behaviour: a click on the active window minimizes it.
    MenuItemRow {
      visible: menu.page === "main" && menu.taskbarOn
      indent: 1
      text: "Click the active window to minimize"
      checkColumn: true
      checked: menu.taskbar.activeClick === "minimize"
      onTriggered: menu.change("tasks", { activeClick: checked ? "nothing" : "minimize" })
    }

    // Windows' "Combine taskbar buttons": one per app. Steps through.
    MenuItemRow {
      visible: menu.page === "main" && menu.taskbarOn
      indent: 1
      text: "Combine: " + menu.combineNames[menu.taskbar.combine]
      checkColumn: true
      hasChildren: true
      onTriggered: {
        var modes = menu.combineModes
        menu.change("tasks", { combine: modes[(modes.indexOf(menu.taskbar.combine) + 1) % modes.length] })
      }
    }

    MenuItemRow {
      visible: menu.page === "main" && menu.taskbarOn
      indent: 1
      text: "Window thumbnails"
      checkColumn: true
      checked: menu.taskbar.thumbnails
      onTriggered: menu.change("tasks", { thumbnails: !checked })
    }

    MenuItemRow {
      visible: menu.page === "main" && menu.taskbarOn
      indent: 1
      text: "Plain titles (no emoji)"
      checkColumn: true
      checked: menu.taskbar.titleSymbols === "strip"
      onTriggered: menu.change("tasks", { titleSymbols: checked ? "keep" : "strip" })
    }

    // Steps through the choices on each click.
    MenuItemRow {
      visible: menu.page === "main" && menu.taskbarOn
      indent: 1
      text: "Windows: " + menu.windowModeNames[menu.taskbar.windows]
      checkColumn: true
      hasChildren: true
      onTriggered: {
        var modes = menu.windowModes
        menu.change("tasks", { windows: modes[(modes.indexOf(menu.taskbar.windows) + 1) % modes.length] })
      }
    }

    // Turned on for the first time, it starts with the browser and terminal.
    MenuItemRow {
      visible: menu.page === "main"
      text: "Quick launch"
      checkColumn: true
      checked: menu.quickLaunchOn
      onTriggered: menu.bar.setQuickLaunchEnabled(!menu.quickLaunchOn)
    }

    MenuItemRow {
      visible: menu.page === "main"
      text: "System tray"
      checkColumn: true
      checked: menu.trayOn
      onTriggered: menu.bar.setWidgetEnabled("tray", !menu.trayOn)
    }

    MenuItemRow {
      visible: menu.page === "main" && menu.trayOn
      indent: 1
      text: "Overflow \"^\""
      checkColumn: true
      checked: menu.tray.overflow
      onTriggered: menu.change("tray", { overflow: !checked })
    }

    MenuItemRow {
      visible: menu.page === "main" && menu.trayOn
      indent: 1
      text: "Windows-style left click"
      checkColumn: true
      checked: menu.tray.replaceLeftClick
      onTriggered: menu.change("tray", { replaceLeftClick: !checked })
    }

    // One row per hidden icon; clicking it shows the icon again.
    Repeater {
      model: menu.page === "main" && menu.trayOn ? menu.tray.hidden : []

      delegate: MenuItemRow {
        required property var modelData
        indent: 1
        text: "Show hidden: " + modelData
        checkColumn: true
        onTriggered: menu.change("tray", { hidden: menu.tray.hidden.filter(function(name) { return name !== modelData }) })
      }
    }

    MenuItemRow {
      visible: menu.page === "main"
      text: "Show desktop"
      checkColumn: true
      checked: menu.showDesktopOn
      onTriggered: menu.bar.setWidgetEnabled("showdesktop", !menu.showDesktopOn)
    }

    MenuItemRow {
      visible: menu.page === "main"
      text: "Omarchy widgets"
      checkColumn: true
      hasChildren: true
      onTriggered: menu.page = "omarchy"
    }

    MenuItemRow {
      visible: menu.page === "main"
      separator: true
    }

    MenuItemRow {
      visible: menu.page === "main"
      text: "Task manager"
      checkColumn: true
      onTriggered: {
        menu.open = false
        menu.bar.openTaskManager()
      }
    }

    MenuItemRow {
      visible: menu.page === "main"
      text: "Transom settings…"
      checkColumn: true
      onTriggered: {
        menu.open = false
        menu.bar.openSettingsFile()
      }
    }

    // ---------------------------------------------- Omarchy widgets page

    MenuItemRow {
      visible: menu.page === "omarchy"
      text: "‹  Omarchy widgets"
      onTriggered: menu.page = "main"
    }

    MenuItemRow {
      visible: menu.page === "omarchy"
      separator: true
    }

    // Each of Omarchy's bar widgets: ✓ when it's on this bar. "top bar" when
    // it's on Omarchy's bar too (take it off there by dragging it off).
    Repeater {
      model: menu.page === "omarchy" && menu.bar ? menu.bar.omarchyWidgetList : []

      delegate: MenuItemRow {
        required property var modelData
        readonly property bool here: menu.bar.widgetEnabled(modelData.id)
        readonly property bool onTop: TrayModel.layoutsHave([menu.bar.topBarLayout], modelData.id)

        text: modelData.name + (onTop ? "  · top bar" : "")
        checkColumn: true
        checked: here
        onTriggered: menu.bar.setWidgetEnabled(modelData.id, !here)
      }
    }
  }
}
