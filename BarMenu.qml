import QtQuick
import qs.Commons
import "Settings.js" as Settings
import "TasksModel.js" as TasksModel
import "TrayModel.js" as TrayModel
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

  onOutsideClicked: menu.open = false

  readonly property bool taskbarOn: !!bar && bar.widgetEnabled("tasks")
  readonly property bool trayOn: !!bar && bar.widgetEnabled("tray")
  readonly property bool quickLaunchOn: !!bar && bar.widgetEnabled("quicklaunch")
  readonly property bool showDesktopOn: !!bar && bar.widgetEnabled("showdesktop")
  readonly property var taskbar: Settings.parse(bar ? bar.entryFor("tasks") : null, TasksModel.SETTINGS).settings
  readonly property var tray: Settings.parse(bar ? bar.entryFor("tray") : null, TrayModel.SETTINGS).settings

  readonly property var windowModes: ["workspace", "monitor", "all"]
  readonly property var windowModeNames: ({ "workspace": "this workspace", "monitor": "this screen", "all": "all" })

  function change(id, changes) {
    if (menu.bar) menu.bar.updateWidget(id, changes)
  }

  MenuCard {
    contentWidth: Style.space(240)

    // ------------------------------------------------------- main page

    // Windows' wording. Locked, nothing on the bar can be dragged.
    MenuItemRow {
      visible: menu.page === "main"
      text: "Lock the taskbar"
      checkColumn: true
      checked: !!menu.bar && menu.bar.locked
      onTriggered: menu.change("bar", { locked: !checked })
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
      onTriggered: {
        if (menu.quickLaunchOn) {
          menu.bar.setWidgetEnabled("quicklaunch", false)
          return
        }
        var entry = menu.bar.entryFor("quicklaunch")
        var changes = { enabled: undefined }
        if (!entry || !entry.apps) changes.apps = ["browser", "terminal"]
        menu.change("quicklaunch", changes)
      }
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
