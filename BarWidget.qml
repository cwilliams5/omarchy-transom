import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "ui" as TransomUi
import "Registry.js" as Registry
import "Settings.js" as Settings
import "TasksModel.js" as TasksModel
import "TopBarWidget.js" as TopBarWidget

// The optional top-bar widget: Transom's mark on Omarchy's top bar, with a
// dropdown to show or hide the taskbar and change its main settings. The
// taskbar works without it.
//
//   left click    the dropdown
//   right click   the dropdown
//   middle click  show or hide the taskbar
//
// Service.qml does the work; this reads its state and calls it. Omarchy's
// bar settings give the widget a "Show icon" switch: off, it takes no room
// but stays on the bar. That matters because Omarchy runs a plugin with a
// widget only while the widget is on a bar, unless the plugin is also in
// shell.json's plugins list (see the README, "Top-bar widget"). A hidden
// taskbar also needs the widget on a bar: its switch is the way back
// (Service.taskbarShown).
Panel {
  id: root
  moduleName: TopBarWidget.PLUGIN_ID
  ipcTarget: TopBarWidget.PLUGIN_ID

  // Services can finish loading after the bar, and looking one up isn't a
  // binding, so keep asking until it answers. Omarchy's lookup works on its
  // own top bar; Registry covers a replacement bar.
  property var service: null
  readonly property bool serviceReady: service !== null && service !== undefined

  Timer {
    interval: 250
    running: !root.serviceReady
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var shell = root.bar ? root.bar.shell : null
      var found = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(TopBarWidget.PLUGIN_ID) : null
      root.service = found || Registry.service
    }
  }

  // The service counts this widget while it exists (Service.widgetCopies),
  // so a taskbar hidden from here comes back if the widget goes.
  property var countedBy: null
  onServiceChanged: root.syncCount()
  Component.onDestruction: root.uncount()

  function uncount() {
    // A service that was reloaded first is already gone; nothing to undo.
    try {
      if (root.countedBy) root.countedBy.widgetCopies = Math.max(0, root.countedBy.widgetCopies - 1)
    } catch (error) {}
    root.countedBy = null
  }

  function syncCount() {
    if (root.countedBy === root.service) return
    root.uncount()
    if (!root.serviceReady) return
    root.countedBy = root.service
    root.countedBy.widgetCopies += 1
  }

  // ---------------------------------------------------------------- state

  readonly property bool taskbarShown: !serviceReady || service.taskbarShown
  readonly property var barSettings: serviceReady ? service.settings : ({})
  readonly property bool autohide: barSettings.autohide === true
  readonly property bool locked: barSettings.locked === true
  readonly property string iconStyle: serviceReady ? service.iconStyle : "color"
  readonly property bool tasksOn: serviceReady && service.widgetEnabled("tasks")
  readonly property var tasks: Settings.parse(serviceReady ? service.entryFor("tasks") : null, TasksModel.SETTINGS).settings
  readonly property bool severalScreens: Quickshell.screens.length > 1

  readonly property bool showIcon: setting("showIcon", true) !== false
  readonly property bool vertical: !!bar && bar.vertical === true

  // Not zero without the icon, or the bar leaves it out when Tab moves
  // between panels (as Locus's widget does).
  implicitWidth: showIcon ? button.implicitWidth : (vertical ? 0 : 1)
  implicitHeight: showIcon ? button.implicitHeight : (vertical ? 1 : 0)

  function change(id, changes) {
    if (root.serviceReady) root.service.updateWidget(id, changes)
  }

  function toggleTaskbar() {
    if (root.serviceReady) root.service.toggleTaskbar()
  }

  // The screen this widget's bar is on, so the bar menu opens there.
  function screenName() {
    try {
      var window = button.QsWindow.window
      return window && window.screen ? String(window.screen.name) : ""
    } catch (error) {
      return ""
    }
  }

  function openBarMenu() {
    if (!root.serviceReady || !root.taskbarShown) return
    var name = root.screenName()
    root.close()
    // After the dropdown has let go of the pointer, or its outside-click
    // grab and the menu's would fight.
    menuLater.screenName = name
    menuLater.restart()
  }

  Timer {
    id: menuLater
    property string screenName: ""
    interval: Style.duration(150) + 50
    onTriggered: if (root.serviceReady) root.service.openBarMenu(screenName)
  }

  function openSettingsFile() {
    if (!root.serviceReady) return
    root.close()
    root.service.openSettingsFile()
  }

  // --------------------------------------------------- keyboard cursor

  // The rows the cursor can stop on, top to bottom (j/k or the arrows).
  readonly property var navKeys: {
    var keys = ["shown", "autohide", "locked"]
    if (root.tasksOn) keys = keys.concat(["windows", "combine", "thumbnails"])
    keys.push("icons")
    if (root.severalScreens) keys.push("screens")
    if (root.taskbarShown) keys.push("menu")
    keys.push("file")
    return keys
  }
  property string cursorKey: ""
  property int dropdownsOpen: 0
  // The choice rows' dropdowns, by key, for Enter.
  property var choiceRows: ({})

  onOpenedChanged: if (opened) root.cursorKey = ""

  function moveCursor(dy) {
    if (!root.serviceReady) return
    var keys = root.navKeys
    var at = keys.indexOf(root.cursorKey)
    if (at < 0) {
      root.cursorKey = keys[0]
      return
    }
    var next = at + dy
    if (dy !== 0 && next >= 0 && next < keys.length) root.cursorKey = keys[next]
  }

  function activateCursor() {
    if (!root.serviceReady) return
    var key = root.cursorKey
    if (key === "shown") root.toggleTaskbar()
    else if (key === "autohide") root.change("bar", { autohide: !root.autohide })
    else if (key === "locked") root.change("bar", { locked: !root.locked })
    else if (key === "thumbnails") root.change("tasks", { thumbnails: !root.tasks.thumbnails })
    else if (key === "screens") root.change("bar", { screens: root.barSettings.screens === "all" ? "primary" : "all" })
    else if (key === "menu") root.openBarMenu()
    else if (key === "file") root.openSettingsFile()
    else if (Object.prototype.hasOwnProperty.call(root.choiceRows, key)) root.choiceRows[key].open()
  }

  // ------------------------------------------------------------ the icon

  Item {
    id: anchorPoint
    anchors.fill: parent
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    visible: root.showIcon
    bar: root.bar
    iconComponent: Component {
      TransomUi.CrossbarIcon {
        stroke: 6
        color: button.foreground
        barShown: root.taskbarShown
      }
    }
    tooltipText: TopBarWidget.status(root.taskbarShown, root.autohide)
      + (root.taskbarShown ? " · middle-click hides it" : " · middle-click shows it")
    onPressed: function(pressedButton) {
      if (pressedButton === Qt.MiddleButton) root.toggleTaskbar()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------ the panel

  KeyboardPanel {
    id: panel
    anchorItem: anchorPoint
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      // An open dropdown takes the keys (j/k, Enter, Esc) for itself.
      blocked: root.dropdownsOpen > 0
      implicitHeight: panelColumn.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Transom"
          meta: root.serviceReady ? TopBarWidget.status(root.taskbarShown, root.autohide) : "Starting…"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          iconComponent: Component {
            TransomUi.CrossbarIcon {
              size: Style.font.display
              stroke: 5
              color: root.bar.foreground
              barShown: root.taskbarShown
            }
          }
        }

        SwitchRow {
          key: "shown"
          label: "Show the taskbar"
          checked: root.taskbarShown
          onToggled: root.toggleTaskbar()
        }

        PanelSeparator {
          width: parent.width
          foreground: root.bar.foreground
        }

        // Windows' wording for these two, as in the bar's own menu.
        SwitchRow {
          key: "autohide"
          label: "Automatically hide the taskbar"
          checked: root.autohide
          onToggled: root.change("bar", { autohide: !root.autohide })
        }

        SwitchRow {
          key: "locked"
          label: "Lock the taskbar"
          checked: root.locked
          onToggled: root.change("bar", { locked: !root.locked })
        }

        ChoiceRow {
          key: "windows"
          visible: root.tasksOn
          label: "Windows"
          options: TopBarWidget.WINDOWS
          value: root.tasks.windows
          onPicked: function(value) { root.change("tasks", { windows: value }) }
        }

        ChoiceRow {
          key: "combine"
          visible: root.tasksOn
          label: "Combine buttons"
          options: TopBarWidget.COMBINE
          value: root.tasks.combine
          onPicked: function(value) { root.change("tasks", { combine: value }) }
        }

        SwitchRow {
          key: "thumbnails"
          visible: root.tasksOn
          label: "Window thumbnails"
          checked: root.tasks.thumbnails === true
          onToggled: root.change("tasks", { thumbnails: !root.tasks.thumbnails })
        }

        ChoiceRow {
          key: "icons"
          label: "Icons"
          options: TopBarWidget.ICON_STYLES
          value: root.iconStyle
          onPicked: function(value) { root.change("bar", { iconStyle: value }) }
        }

        // Windows' "Show taskbar on all displays", once there's more than one.
        SwitchRow {
          key: "screens"
          visible: root.severalScreens
          label: "Show on all displays"
          checked: root.barSettings.screens === "all"
          onToggled: root.change("bar", { screens: root.barSettings.screens === "all" ? "primary" : "all" })
        }

        PanelSeparator {
          width: parent.width
          foreground: root.bar.foreground
        }

        Row {
          spacing: Style.space(8)

          // The rest (every widget, the tray, quick launch...) is in the
          // bar's own right-click menu; this opens it on the taskbar.
          Button {
            visible: root.taskbarShown
            text: "Bar menu…"
            fontFamily: root.bar.fontFamily
            foreground: root.bar.foreground
            bordered: true
            hasCursor: root.cursorKey === "menu"
            onHovered: function(isHovered) { if (isHovered) root.cursorKey = "menu" }
            onClicked: root.openBarMenu()
          }

          Button {
            text: "Settings file…"
            fontFamily: root.bar.fontFamily
            foreground: root.bar.foreground
            bordered: true
            hasCursor: root.cursorKey === "file"
            onHovered: function(isHovered) { if (isHovered) root.cursorKey = "file" }
            onClicked: root.openSettingsFile()
          }
        }
      }
    }
  }

  // A label on the left, a switch on the right.
  component SwitchRow: Item {
    id: switchRow
    property string key: ""
    property string label: ""
    property bool checked: false
    signal toggled()
    width: panelColumn.width
    implicitHeight: Math.max(switchLabel.implicitHeight, rowSwitch.implicitHeight)

    Text {
      id: switchLabel
      textFormat: Text.PlainText
      text: switchRow.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      width: parent.width - rowSwitch.width - Style.space(12)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    ToggleSwitch {
      id: rowSwitch
      checked: switchRow.checked
      hasCursor: root.cursorKey === switchRow.key
      interactive: root.serviceReady
      opacity: root.serviceReady ? 1.0 : 0.45
      foreground: root.bar.foreground
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      onToggled: switchRow.toggled()
      onHovered: function(isHovered) { if (isHovered) root.cursorKey = switchRow.key }
    }
  }

  // A label on the left, a dropdown of choices on the right.
  component ChoiceRow: Item {
    id: choiceRow
    property string key: ""
    property string label: ""
    property var options: []
    property string value: ""
    signal picked(string value)
    width: panelColumn.width
    implicitHeight: Math.max(choiceLabel.implicitHeight, choice.implicitHeight)

    readonly property bool popupOpen: choice.popupOpen
    onPopupOpenChanged: root.dropdownsOpen = Math.max(0, root.dropdownsOpen + (popupOpen ? 1 : -1))
    Component.onCompleted: {
      var rows = Object.assign(Object.create(null), root.choiceRows)
      rows[choiceRow.key] = choice
      root.choiceRows = rows
    }

    Text {
      id: choiceLabel
      textFormat: Text.PlainText
      text: choiceRow.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      width: parent.width - choice.width - Style.space(12)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Dropdown {
      id: choice
      width: Style.space(150)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      showLabel: false
      enabled: root.serviceReady
      fontFamily: root.bar.fontFamily
      options: choiceRow.options
      value: choiceRow.value
      hasCursor: root.cursorKey === choiceRow.key
      onChanged: function(value) { choiceRow.picked(value) }
      onHovered: function(isHovered) { if (isHovered) root.cursorKey = choiceRow.key }
    }
  }
}
