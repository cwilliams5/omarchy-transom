import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "ui" as TransomUi
import "Registry.js" as Registry
import "Settings.js" as Settings
import "TasksModel.js" as TasksModel
import "TrayModel.js" as TrayModel
import "TopBarWidget.js" as TopBarWidget

// The optional top-bar widget: Transom's mark on Omarchy's top bar, with a
// dropdown to show or hide the taskbar and change its settings. The taskbar
// works without it.
//
//   left click    the dropdown
//   right click   the dropdown
//   middle click  show or hide the taskbar
//
// The dropdown: "Show the taskbar" across the top, then two columns. Left:
// the bar (auto-hide, lock, all displays) and the taskbar buttons. Right:
// the tray, quick launch, and icon styles. A section that can be switched
// off hides its rows while it's off. Keyboard: j/k or the arrows move, h/l
// step the slider, Enter acts.
//
// Service.qml does the work; this reads its state and calls it. The
// dropdown's "Top-bar icon" switch (the bar option topBarIcon, also in the
// bottom bar's menu) hides the icon: the widget then takes no room but
// stays on the bar. That matters because Omarchy runs a plugin with a
// widget only while the widget is on a bar, unless the plugin is also in
// shell.json's plugins list (see the README, "Top-bar widget"); the switch
// warns when that's the case here (Service.iconKeepsTransomOn). A hidden
// taskbar needs the icon: its switch is the way back (Service.taskbarShown).
// Omarchy 4.5 has no screen for a widget's own settings, which is why this
// isn't one.
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

  // Reads service itself, not serviceReady: in onServiceChanged that
  // binding can still hold its old value (seen live: the widget never
  // counted itself).
  function syncCount() {
    var service = root.service
    if (root.countedBy === service) return
    root.uncount()
    if (service === null || service === undefined) return
    root.countedBy = service
    service.widgetCopies += 1
  }

  // ---------------------------------------------------------------- state

  readonly property bool taskbarShown: !serviceReady || service.taskbarShown
  readonly property var barSettings: serviceReady ? service.settings : ({})
  readonly property bool autohide: barSettings.autohide === true
  readonly property bool locked: barSettings.locked === true
  readonly property bool severalScreens: Quickshell.screens.length > 1

  readonly property bool tasksOn: serviceReady && service.widgetEnabled("tasks")
  readonly property var tasks: Settings.parse(serviceReady ? service.entryFor("tasks") : null, TasksModel.SETTINGS).settings
  readonly property bool trayOn: serviceReady && service.widgetEnabled("tray")
  readonly property var tray: Settings.parse(serviceReady ? service.entryFor("tray") : null, TrayModel.SETTINGS).settings
  readonly property bool quickLaunchOn: serviceReady && service.widgetEnabled("quicklaunch")

  readonly property string iconStyle: serviceReady ? service.iconStyle : "color"
  readonly property string windowIconStyle: serviceReady ? service.windowIconStyle : "color"
  readonly property bool focusedInColor: !(barSettings.iconStyleOn && barSettings.iconStyleOn.activeWindow === true)
  readonly property bool anyThemed: iconStyle === "themed" || windowIconStyle === "themed"

  readonly property bool showIcon: !serviceReady || service.topBarIconShown
  readonly property bool vertical: !!bar && bar.vertical === true

  // Not zero without the icon, or the bar leaves it out when Tab moves
  // between panels (as Locus's widget does).
  implicitWidth: showIcon ? button.implicitWidth : (vertical ? 0 : 1)
  implicitHeight: showIcon ? button.implicitHeight : (vertical ? 1 : 0)

  // The two columns share whatever width the panel gets: it asks for
  // wantedWidth, but stays on screen, so near a screen edge it gets less.
  readonly property real wantedWidth: Style.space(640)
  readonly property real columnGap: Style.space(24)
  property real contentWidth: wantedWidth
  readonly property real columnWidth: Math.max(Style.space(200), (contentWidth - columnGap) / 2)
  // How far a section's rows sit in under its switch.
  readonly property real indent: Style.space(14)

  // ----------------------------------------------------------- actions

  function change(id, changes) {
    if (root.serviceReady) root.service.updateWidget(id, changes)
  }

  function toggleTaskbar() {
    if (root.serviceReady) root.service.toggleTaskbar()
  }

  // The dropdown hangs off the icon, so it closes first.
  function hideIcon() {
    if (!root.serviceReady) return
    root.close()
    root.service.setTopBarIconShown(false)
  }

  function setMaxIcons(value) {
    var next = Math.max(0, Math.round(value))
    if (next !== root.tray.maxIcons) root.change("tray", { maxIcons: next })
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

  // The rows the cursor can stop on, in reading order: the top row, the
  // left column, the right column, the buttons. Rows hidden right now
  // (a section switched off) are left out.
  readonly property var navKeys: {
    var keys = ["shown", "autohide", "locked"]
    if (root.severalScreens) keys.push("screens")
    keys.push("topBarIcon")
    keys.push("tasks")
    if (root.tasksOn) keys = keys.concat(["iconsOnly", "combine", "thumbnails", "plainTitles", "windows"])
    keys.push("tray")
    if (root.trayOn) {
      keys.push("overflow")
      if (root.tray.overflow) keys.push("maxIcons")
      keys.push("trayClick")
    }
    keys.push("quicklaunch")
    keys.push("appIcons", "windowIcons")
    if (root.windowIconStyle !== "color") keys.push("focusedColor")
    if (root.anyThemed) keys.push("tint")
    if (root.taskbarShown) keys.push("menu")
    keys.push("file")
    return keys
  }
  property string cursorKey: ""
  property int dropdownsOpen: 0
  // What Enter does on each row, and what h/l do on the slider, by key.
  // Rows register themselves.
  property var rowActions: Object.create(null)

  function registerRow(key, action) {
    var next = Object.create(null)
    for (var existing in root.rowActions) next[existing] = root.rowActions[existing]
    next[key] = action
    root.rowActions = next
  }

  onOpenedChanged: if (opened) root.cursorKey = ""

  function moveCursor(dx, dy) {
    if (!root.serviceReady) return
    var keys = root.navKeys
    var at = keys.indexOf(root.cursorKey)
    if (at < 0) {
      root.cursorKey = keys[0]
      return
    }
    if (dx !== 0 && root.cursorKey === "maxIcons") {
      root.setMaxIcons(root.tray.maxIcons + dx)
      return
    }
    var next = at + dy
    if (dy !== 0 && next >= 0 && next < keys.length) root.cursorKey = keys[next]
  }

  function activateCursor() {
    if (!root.serviceReady || root.navKeys.indexOf(root.cursorKey) < 0) return
    var action = root.rowActions[root.cursorKey]
    if (typeof action === "function") action()
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
    contentWidth: panel.fittedContentWidth(root.wantedWidth)
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(720))

    content: PanelKeyCatcher {
      // An open dropdown takes the keys (j/k, Enter, Esc) for itself.
      blocked: root.dropdownsOpen > 0
      implicitHeight: panelColumn.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Scrolls only on a screen too short for it all.
      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: panelColumn
          width: flick.width
          spacing: Style.space(12)
          onWidthChanged: if (width > 0) root.contentWidth = width

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
            width: panelColumn.width
            heading: true
            label: "Show the taskbar"
            checked: root.taskbarShown
            onToggled: root.toggleTaskbar()
          }

          PanelSeparator {
            width: parent.width
            foreground: root.bar.foreground
          }

          Row {
            spacing: root.columnGap

            // ------------------------------------------- left column
            Column {
              width: root.columnWidth
              spacing: Style.space(10)

              PanelSectionHeader {
                text: "Bar"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              // Windows' wording, as in the bar's own menu.
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

              // Windows' "Show taskbar on all displays", once there's more
              // than one.
              SwitchRow {
                key: "screens"
                visible: root.severalScreens
                label: "Show on all displays"
                checked: root.barSettings.screens === "all"
                onToggled: root.change("bar", { screens: root.barSettings.screens === "all" ? "primary" : "all" })
              }

              // This icon. Off, it's gone from the top bar (the bottom bar's
              // menu brings it back) and the taskbar shows.
              SwitchRow {
                key: "topBarIcon"
                label: "Top-bar icon"
                checked: root.showIcon
                onToggled: {
                  if (root.showIcon) root.hideIcon()
                  else if (root.serviceReady) root.service.setTopBarIconShown(true)
                }
              }

              // Only where removing the icon would turn Transom off.
              Text {
                visible: root.serviceReady && root.service.iconKeepsTransomOn
                width: root.columnWidth
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: "Removing this icon from the bar turns Transom off on this computer. To get rid of it, switch it off here instead."
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item { width: 1; height: Style.space(4) }

              SwitchRow {
                key: "tasks"
                heading: true
                label: "Taskbar buttons"
                checked: root.tasksOn
                onToggled: root.service.setWidgetEnabled("tasks", !root.tasksOn)
              }

              SwitchRow {
                key: "iconsOnly"
                visible: root.tasksOn
                indented: true
                label: "Icons only"
                checked: root.tasks.labels === "icon"
                onToggled: root.change("tasks", { labels: root.tasks.labels === "icon" ? "title" : "icon" })
              }

              ChoiceRow {
                key: "combine"
                visible: root.tasksOn
                indented: true
                label: "Combine"
                options: TopBarWidget.COMBINE
                value: root.tasks.combine
                onPicked: function(value) { root.change("tasks", { combine: value }) }
              }

              SwitchRow {
                key: "thumbnails"
                visible: root.tasksOn
                indented: true
                label: "Window thumbnails"
                checked: root.tasks.thumbnails === true
                onToggled: root.change("tasks", { thumbnails: !root.tasks.thumbnails })
              }

              SwitchRow {
                key: "plainTitles"
                visible: root.tasksOn
                indented: true
                label: "Plain titles (no emoji)"
                checked: root.tasks.titleSymbols === "strip"
                onToggled: root.change("tasks", { titleSymbols: root.tasks.titleSymbols === "strip" ? "keep" : "strip" })
              }

              ChoiceRow {
                key: "windows"
                visible: root.tasksOn
                indented: true
                label: "Windows"
                options: TopBarWidget.WINDOWS
                value: root.tasks.windows
                onPicked: function(value) { root.change("tasks", { windows: value }) }
              }
            }

            // ------------------------------------------ right column
            Column {
              width: root.columnWidth
              spacing: Style.space(10)

              SwitchRow {
                key: "tray"
                heading: true
                label: "System tray"
                checked: root.trayOn
                onToggled: root.service.setWidgetEnabled("tray", !root.trayOn)
              }

              SwitchRow {
                key: "overflow"
                visible: root.trayOn
                indented: true
                label: "Overflow \"^\""
                checked: root.tray.overflow === true
                onToggled: root.change("tray", { overflow: !root.tray.overflow })
              }

              SliderRow {
                key: "maxIcons"
                visible: root.trayOn && root.tray.overflow === true
                indented: true
                label: "Icons before \"^\""
                value: root.tray.maxIcons
              }

              SwitchRow {
                key: "trayClick"
                visible: root.trayOn
                indented: true
                label: "Windows-style left click"
                checked: root.tray.replaceLeftClick === true
                onToggled: root.change("tray", { replaceLeftClick: !root.tray.replaceLeftClick })
              }

              Item { width: 1; height: Style.space(4) }

              SwitchRow {
                key: "quicklaunch"
                heading: true
                label: "Quick launch"
                checked: root.quickLaunchOn
                onToggled: root.service.setQuickLaunchEnabled(!root.quickLaunchOn)
              }

              Item { width: 1; height: Style.space(4) }

              PanelSectionHeader {
                text: "Icons"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              ChoiceRow {
                key: "appIcons"
                label: "Tray, quick launch"
                options: TopBarWidget.ICON_STYLES
                value: root.iconStyle
                onPicked: function(value) { root.change("bar", { iconStyle: value }) }
              }

              ChoiceRow {
                key: "windowIcons"
                label: "Window buttons"
                options: TopBarWidget.ICON_STYLES
                value: root.windowIconStyle
                onPicked: function(value) { root.service.setWindowIconStyle(value) }
              }

              SwitchRow {
                key: "focusedColor"
                visible: root.windowIconStyle !== "color"
                indented: true
                label: "Focused window in color"
                checked: root.focusedInColor
                onToggled: root.service.setFocusedWindowColor(!root.focusedInColor)
              }

              ChoiceRow {
                key: "tint"
                visible: root.anyThemed
                label: "Theme color"
                options: TopBarWidget.TINTS
                value: root.barSettings.iconTint || "accent"
                onPicked: function(value) { root.change("bar", { iconTint: value }) }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.bar.foreground
          }

          Row {
            spacing: Style.space(8)

            // Omarchy's widgets, the tray's hidden icons and the rest are
            // in the bar's own right-click menu; this opens it on the taskbar.
            Button {
              visible: root.taskbarShown
              text: "Bar menu…"
              fontFamily: root.bar.fontFamily
              foreground: root.bar.foreground
              bordered: true
              hasCursor: root.cursorKey === "menu"
              onHovered: function(isHovered) { if (isHovered) root.cursorKey = "menu" }
              onClicked: root.openBarMenu()
              Component.onCompleted: root.registerRow("menu", function() { root.openBarMenu() })
            }

            Button {
              text: "Settings file…"
              fontFamily: root.bar.fontFamily
              foreground: root.bar.foreground
              bordered: true
              hasCursor: root.cursorKey === "file"
              onHovered: function(isHovered) { if (isHovered) root.cursorKey = "file" }
              onClicked: root.openSettingsFile()
              Component.onCompleted: root.registerRow("file", function() { root.openSettingsFile() })
            }
          }
        }
      }
    }
  }

  // A label on the left, a switch on the right. heading: a section's own
  // on/off, in bold. indented: a row under one.
  component SwitchRow: Item {
    id: switchRow
    property string key: ""
    property string label: ""
    property bool checked: false
    property bool heading: false
    property bool indented: false
    signal toggled()
    width: root.columnWidth
    implicitHeight: Math.max(switchLabel.implicitHeight, rowSwitch.implicitHeight)
    Component.onCompleted: root.registerRow(switchRow.key, function() { switchRow.toggled() })

    Text {
      id: switchLabel
      textFormat: Text.PlainText
      text: switchRow.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: switchRow.heading
      elide: Text.ElideRight
      x: switchRow.indented ? root.indent : 0
      width: parent.width - x - rowSwitch.width - Style.space(8)
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
    property bool indented: false
    signal picked(string value)
    width: root.columnWidth
    implicitHeight: Math.max(choiceLabel.implicitHeight, choice.implicitHeight)

    readonly property bool popupOpen: choice.popupOpen
    onPopupOpenChanged: root.dropdownsOpen = Math.max(0, root.dropdownsOpen + (popupOpen ? 1 : -1))
    Component.onCompleted: root.registerRow(choiceRow.key, function() { choice.open() })

    Text {
      id: choiceLabel
      textFormat: Text.PlainText
      text: choiceRow.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      x: choiceRow.indented ? root.indent : 0
      width: parent.width - x - choice.width - Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Dropdown {
      id: choice
      width: Style.space(140)
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

  // The tray's maxIcons: a label with the number, a slider under it. Saves
  // when the slider is let go (or on each h/l step), not while it moves.
  component SliderRow: Item {
    id: sliderRow
    property string key: ""
    property string label: ""
    property int value: 0
    property bool indented: false
    width: root.columnWidth
    implicitHeight: sliderLabel.implicitHeight + Style.space(6) + slider.implicitHeight

    Text {
      id: sliderLabel
      textFormat: Text.PlainText
      text: sliderRow.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      x: sliderRow.indented ? root.indent : 0
    }

    Text {
      textFormat: Text.PlainText
      text: String(Math.round(slider.liveValue))
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.right: parent.right
      anchors.top: parent.top
    }

    PanelSlider {
      id: slider
      bar: root.bar
      x: sliderRow.indented ? root.indent : 0
      width: parent.width - x
      anchors.top: sliderLabel.bottom
      anchors.topMargin: Style.space(6)
      minimum: 0
      maximum: TopBarWidget.sliderMax(sliderRow.value)
      step: 1
      integer: true
      value: sliderRow.value
      enabled: root.serviceReady
      onReleased: function(value) { root.setMaxIcons(value) }
    }

    // The cursor's mark, as a ring around the slider.
    Rectangle {
      visible: root.cursorKey === sliderRow.key
      anchors.fill: slider
      anchors.margins: -Style.space(4)
      color: "transparent"
      radius: Style.cornerRadius
      border.width: 1
      border.color: root.bar.foreground
      opacity: 0.5
    }

    HoverHandler {
      onHoveredChanged: if (hovered) root.cursorKey = sliderRow.key
    }
  }
}
