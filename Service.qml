import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import Quickshell.Services.SystemTray
import "Settings.js" as Settings
import "TasksModel.js" as TasksModel
import "TrayModel.js" as TrayModel

// Transom: a Windows-style taskbar along the bottom edge of every screen. It
// takes its look from Omarchy's top bar (theme colors, font, height, and the
// clear/glassy/opaque background in shell.json), and holds widgets in
// left/center/right sections. Widgets live in widgets/.
//
// Which widgets go where, and their settings: ~/.config/omarchy/transom.json
// (the user's), or the plugin's defaults.json until that file exists. The
// user's file is outside the plugin folder on purpose: Omarchy reloads the
// whole plugin when anything in its folder changes, and the bar writes the
// file itself when settings change from its menus.
//
// Omarchy's "bar" plugin kind replaces the top bar rather than adding one,
// so this is a service plugin that opens its own layer-shell windows.
Item {
  id: root

  // Injected by the Omarchy service-plugin host. For a third-party plugin,
  // shell is a narrow API: barConfig (the bar section of shell.json) and bar
  // (the top bar's size and hidden state).
  property var shell: null
  property var manifest: null
  // Omarchy's bar widget catalogue, so its own widgets can be hosted here
  // (widgets/OmarchyWidget.qml). Also injected by the host.
  property var barWidgetRegistry: null

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  // ------------------------------------------------------------------ look

  readonly property var barConfig: shell && shell.barConfig ? shell.barConfig : ({})
  // The same choice the top bar reads: opaque, glassy or none (clear). A
  // config from before "background" existed says transparent instead.
  readonly property string look: barConfig.background || (barConfig.transparent === true ? "none" : "opaque")
  readonly property color themeBackground: Commons.Color.bar.background
  // Glassy matches the top bar's glassBackground. The blur behind it comes
  // from Hyprland's layer rule for the omarchy-bar namespace (BarWindow.qml).
  readonly property color background: look === "none" ? "transparent"
    : look === "glassy" ? Qt.rgba(themeBackground.r, themeBackground.g, themeBackground.b, Math.min(themeBackground.a, 0.35))
    : themeBackground
  readonly property color foreground: Commons.Color.bar.text
  readonly property color urgent: Commons.Color.bar.active
  readonly property string fontFamily: Style.font.family
  readonly property int barSize: Style.bar.sizeHorizontal
  // Hidden whenever the top bar is.
  readonly property bool hidden: !!(shell && shell.bar && shell.bar.barHidden)

  // --------------------------------------------------------------- widgets

  // Widget ids the layout can use, and the file each one loads.
  readonly property var widgets: ({
    "tasks": "widgets/Tasks.qml",
    "tray": "widgets/Tray.qml",
    "showdesktop": "widgets/ShowDesktop.qml"
  })

  // Omarchy's bar widgets the bar menu offers, as [{ id, name }] sorted by
  // name. Its tray is left out (widgets/Tray.qml replaces it here).
  readonly property var omarchyWidgetList: {
    var widgets = root.barWidgetRegistry && root.barWidgetRegistry.widgets ? root.barWidgetRegistry.widgets : {}
    var out = []
    for (var id in widgets) {
      if (id === "omarchy.tray") continue
      var meta = widgets[id].metadata || {}
      out.push({ id: id, name: String(meta.displayName || id) })
    }
    out.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return out
  }

  // The top bar's layout (shell.json bar.layout), e.g. for the tray to leave
  // out an app icon a top-bar widget already shows.
  readonly property var topBarLayout: barConfig.layout || ({})

  // One popup open at a time across the bar, as on Omarchy's top bar. A
  // widget opening a menu, flyout or panel claims the bar; the previous
  // owner's closePopups() runs. A click on empty bar space closes it.
  property var popupOwner: null

  function claimPopup(owner) {
    if (root.popupOwner && root.popupOwner !== owner && typeof root.popupOwner.closePopups === "function")
      root.popupOwner.closePopups()
    root.popupOwner = owner
  }

  function dismissPopups() {
    if (root.popupOwner && typeof root.popupOwner.closePopups === "function") root.popupOwner.closePopups()
    root.popupOwner = null
  }

  // Whether id is one of Omarchy's own bar widgets (omarchy.network...).
  function isOmarchyWidget(id) {
    var widgets = root.barWidgetRegistry && root.barWidgetRegistry.widgets ? root.barWidgetRegistry.widgets : null
    return !!widgets && !!widgets[String(id || "")]
  }

  function widgetUrl(id) {
    if (!root.widgets[String(id || "")] && root.isOmarchyWidget(id)) return Qt.resolvedUrl("widgets/OmarchyWidget.qml")
    var file = root.widgets[String(id || "")]
    if (!file) {
      console.warn("transom: no widget called \"" + id + "\" (known: " + Object.keys(root.widgets).join(", ") + ")")
      return ""
    }
    return Qt.resolvedUrl(file)
  }

  // ---------------------------------------------------- layout and settings

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/transom.json"
  readonly property var sections: ["left", "center", "right"]
  // Where a widget goes when it's switched on but isn't in the file at all.
  readonly property var homeSection: ({ "tasks": "center", "tray": "right", "showdesktop": "right" })

  property var defaultLayout: ({ left: [], center: [{ id: "tasks" }], right: [{ id: "tray" }] })
  // Every entry, switched on or not. shownLayout is what the bar draws.
  property var layout: defaultLayout
  readonly property var shownLayout: {
    var out = {}
    for (var s = 0; s < root.sections.length; s++) {
      out[root.sections[s]] = (root.layout[root.sections[s]] || []).filter(function(entry) { return entry.enabled !== false })
    }
    return out
  }
  property bool userConfigExists: false
  // The file's text as last read or written, so our own write coming back
  // through the file watcher doesn't rebuild every widget a second time.
  property string layoutText: ""

  function normalize(parsed) {
    var out = {}
    if (parsed && parsed.bar && typeof parsed.bar === "object" && !Array.isArray(parsed.bar)) out.bar = parsed.bar
    for (var s = 0; s < root.sections.length; s++) {
      var list = parsed && Array.isArray(parsed[root.sections[s]]) ? parsed[root.sections[s]] : []
      out[root.sections[s]] = list.filter(function(entry) { return entry && typeof entry.id === "string" && entry.id !== "" })
    }
    return out
  }

  // Bar-wide options: the "bar" object at the top of the settings file.
  readonly property var barSettingsSpec: ({
    // See raiseSteps. Remove once Hyprland draws a focused maximized window
    // above floating ones: docs/upstream/hyprland-maximized-float-stacking/
    // in the dotfiles repo has the test and the removal steps.
    maximizedRaiseWorkaround: { default: true }
  })
  readonly property var parsedBarSettings: Settings.parse(layout.bar, barSettingsSpec)
  readonly property var settings: parsedBarSettings.settings
  onParsedBarSettingsChanged: {
    var problems = parsedBarSettings.problems
    for (var i = 0; i < problems.length; i++) console.warn("transom: bar setting ignored: " + problems[i])
  }

  function parseLayout(text, what) {
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object") return root.normalize(parsed)
    } catch (error) {
      console.warn("transom: " + what + " is not valid JSON: " + error)
    }
    return null
  }

  function applyUserText(text) {
    if (text === root.layoutText) return
    var parsed = root.parseLayout(text, root.configPath)
    if (!parsed) return
    root.layoutText = text
    root.layout = parsed
  }

  FileView {
    path: root.pluginDir + "/defaults.json"
    blockLoading: true
    printErrors: false
    onLoaded: {
      var parsed = root.parseLayout(text(), "defaults.json")
      if (!parsed) return
      root.defaultLayout = parsed
      if (!root.userConfigExists) root.layout = parsed
    }
  }

  FileView {
    id: userFile
    path: root.configPath
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.userConfigExists = true
      root.applyUserText(text())
    }
    onLoadFailed: {
      root.userConfigExists = false
      root.layoutText = ""
      root.layout = root.defaultLayout
    }
    onFileChanged: reload()
  }

  // Writes the whole layout to the user's file and applies it.
  function saveLayout(next) {
    var text = JSON.stringify(next, null, 2) + "\n"
    root.layoutText = text
    root.userConfigExists = true
    root.layout = next
    userFile.setText(text)
  }

  // The first entry for a widget id, or null.
  function entryFor(id) {
    for (var s = 0; s < root.sections.length; s++) {
      var list = root.layout[root.sections[s]] || []
      for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    }
    return null
  }

  function widgetEnabled(id) {
    var entry = root.entryFor(id)
    return !!entry && entry.enabled !== false
  }

  // Merges changes into a widget's entry and saves. A change to undefined
  // removes that key. A widget missing from the file is added to its home
  // section.
  function updateWidget(id, changes) {
    var next = JSON.parse(JSON.stringify(root.layout))
    var entry = null
    // "bar" is the bar-wide options object, not a widget.
    if (id === "bar") {
      if (!next.bar) next.bar = {}
      entry = next.bar
    }
    for (var s = 0; s < root.sections.length && !entry; s++) {
      var list = next[root.sections[s]]
      for (var i = 0; i < list.length; i++) if (list[i].id === id) { entry = list[i]; break }
    }
    if (!entry) {
      entry = { id: id }
      // Show desktop stays at the very end, as on Windows.
      var section = next[root.homeSection[id] || "right"]
      var last = section.length > 0 && section[section.length - 1].id === "showdesktop" && id !== "showdesktop"
      section.splice(last ? section.length - 1 : section.length, 0, entry)
    }
    for (var key in changes) {
      if (changes[key] === undefined) delete entry[key]
      else entry[key] = changes[key]
    }
    console.log("transom: setting " + id + " " + JSON.stringify(changes))
    root.saveLayout(next)
  }

  function setWidgetEnabled(id, on) {
    root.updateWidget(id, { enabled: on ? undefined : false })
  }

  // Opens the user's settings file in the editor, creating it first.
  function openSettingsFile() {
    if (!root.userConfigExists) root.saveLayout(root.layout)
    Util.execDetached("omarchy launch config editor " + Util.shellQuote(root.configPath))
  }

  // Omarchy's "Activity" (Super+Shift+T), its task manager.
  function openTaskManager() {
    Util.execDetached("omarchy launch or focus tui btop")
  }

  // ------------------------------------------------- windows and apps

  function target(address) {
    return "window = \"address:" + address + "\""
  }

  // Runs Hyprland dispatches in order, then any `after` ones 0.4s later.
  // Each one is logged to the shell log (see README, Developing).
  function dispatch(steps, after) {
    console.log("transom: " + steps.concat(after || []).join(" ; "))
    var run = function(step) { return "hyprctl dispatch " + Util.shellQuote(step) }
    var command = steps.map(run).join(" && ")
    if (after && after.length > 0) command += "; sleep 0.4; " + after.map(run).join("; ")
    Util.execDetached(command)
  }

  // Whether Hyprland has the window maximized (fullscreen mode 1).
  function isMaximized(address) {
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      if (TasksModel.normalizeAddress(list[i].address) !== address) continue
      var ipc = list[i].lastIpcObject || {}
      return Number(ipc.fullscreen) === 1
    }
    return false
  }

  // The steps that put a focused window on top of the others. A maximized
  // window needs more (when bar option maximizedRaiseWorkaround is on, the
  // default): Hyprland keeps drawing floating windows over it even
  // once it has focus (no raise or bring_to_top helps), and those windows
  // then look clickable but aren't. Taking it out of maximized, raising it
  // and maximizing it again does put it on top. Animation is off meanwhile,
  // so it isn't seen. Found 2026-11-17 with Superhuman over a maximized
  // Chrome; reproduced with test windows.
  function raiseSteps(t, maximized) {
    if (!maximized) return { steps: ["hl.dsp.window.alter_zorder({ mode = \"top\", " + t + " })"], after: [] }
    return {
      steps: [
        "hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", " + t + " })",
        "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\", " + t + " })",
        "hl.dsp.window.alter_zorder({ mode = \"top\", " + t + " })",
        "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"set\", " + t + " })"
      ],
      after: ["hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"unset\", " + t + " })"]
    }
  }

  // Focuses a window and puts it on top, switching to its workspace if it's
  // on another one.
  function focusWindow(address) {
    var t = root.target(address)
    var raise = root.raiseSteps(t, root.settings.maximizedRaiseWorkaround && root.isMaximized(address))
    root.dispatch(["hl.dsp.focus({ " + t + " })"].concat(raise.steps), raise.after)
  }

  // Brings a minimized window back to a workspace, focused and on top,
  // without its open animation (as Omarchy's dock does). Going to another
  // workspace switches the screen there.
  function restoreWindow(address, workspaceId) {
    if (!(workspaceId >= 1)) return
    var t = root.target(address)
    var raise = root.raiseSteps(t, root.settings.maximizedRaiseWorkaround && root.isMaximized(address))
    var noAnim = "hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", " + t + " })"
    root.dispatch([
      noAnim,
      "hl.dsp.window.move({ workspace = \"" + workspaceId + "\", " + t + " })",
      "hl.dsp.focus({ " + t + " })"
    ].concat(raise.steps.filter(function(step) { return step !== noAnim })), [
      "hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"unset\", " + t + " })"
    ])
  }

  // Minimizes several windows, one after another (show desktop).
  function minimizeWindows(addresses) {
    if (!addresses || addresses.length === 0) return
    var script = Util.shellQuote(root.pluginDir + "/minimize")
    console.log("transom: minimize " + addresses.join(" "))
    Util.execDetached(addresses.map(function(address) { return script + " " + Util.shellQuote(address) }).join("; "))
  }

  // Brings several minimized windows back to a workspace, in order; the
  // last one gets focus (show desktop's second click). Keeps going if one
  // has closed meanwhile.
  function restoreWindows(addresses, workspaceId) {
    if (!addresses || addresses.length === 0 || !(workspaceId >= 1)) return
    var steps = []
    var after = []
    addresses.forEach(function(address) {
      var t = root.target(address)
      steps.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", " + t + " })")
      steps.push("hl.dsp.window.move({ workspace = \"" + workspaceId + "\", " + t + " })")
      after.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"unset\", " + t + " })")
    })
    steps.push("hl.dsp.focus({ " + root.target(addresses[addresses.length - 1]) + " })")
    console.log("transom: restore " + addresses.join(" "))
    var run = function(step) { return "hyprctl dispatch " + Util.shellQuote(step) }
    Util.execDetached(steps.map(run).join("; ") + "; sleep 0.4; " + after.map(run).join("; "))
  }

  // Starts an app from its desktop entry, the way Omarchy's launcher does.
  // A single-instance app that's already running shows its window instead.
  function launchEntry(entry) {
    if (!entry) return
    console.log("transom: start " + entry.id)
    if (entry.runInTerminal) {
      var words = (entry.command || []).filter(function(word) { return !/^%[a-zA-Z]$/.test(String(word)) })
      if (words.length > 0) Util.execDetached("omarchy-launch-tui " + words.map(function(word) { return Util.shellQuote(word) }).join(" "))
      return
    }
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(entry.id + ".desktop"))
  }

  // ------------------------------------------------------- Hyprland state

  // Quickshell keeps each window's workspace and title current, but its
  // lastIpcObject (tags, floating, fullscreen) only updates on a refresh.
  // Refresh shortly after anything that can change those. start(), not
  // restart(): a steady stream of events must not keep pushing it back.
  // Title changes are left out; Quickshell tracks titles itself, and an
  // animated title (a Claude Code spinner) changes several times a second.
  Timer {
    id: refreshTimer
    interval: 100
    onTriggered: Hyprland.refreshToplevels()
  }

  readonly property var refreshEvents: ["openwindow", "movewindowv2", "changefloatingmode", "fullscreen"]

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (root.refreshEvents.indexOf(name) >= 0 && !refreshTimer.running) refreshTimer.start()
    }
  }

  Component.onCompleted: Hyprland.refreshToplevels()

  // The taskbar's window order for the session, as window addresses, set by
  // dragging buttons. Shared by every screen's taskbar; new windows go last.
  property var windowOrder: []

  // Diagnostics: what the taskbar sees for every window.
  //   omarchy-shell transom windows
  ShellIpc {
    target: "transom"

    function windows(): string {
      var taskbarEntry = null
      var sections = [root.layout.left, root.layout.center, root.layout.right]
      for (var s = 0; s < sections.length; s++) {
        for (var e = 0; e < sections[s].length; e++) if (sections[s][e].id === "tasks") taskbarEntry = sections[s][e]
      }
      var parsed = Settings.parse(taskbarEntry, TasksModel.SETTINGS)
      var known = Hyprland.workspaces.values.map(function(workspace) { return workspace.id })
      var monitors = Hyprland.monitors.values.map(function(monitor) {
        return {
          name: monitor.name,
          view: {
            mode: parsed.settings.windows,
            workspaceId: monitor.activeWorkspace ? monitor.activeWorkspace.id : -1,
            monitorWorkspaces: Hyprland.workspaces.values.filter(function(workspace) { return workspace.monitor === monitor })
              .map(function(workspace) { return workspace.id }),
            knownWorkspaces: known,
            showMinimized: parsed.settings.minimized !== "hidden"
          }
        }
      })
      var list = Hyprland.toplevels.values
      var windows = []
      for (var i = 0; i < list.length; i++) {
        var toplevel = list[i]
        var window = TasksModel.describe(toplevel)
        var ipc = toplevel.lastIpcObject || {}
        window.title = String(toplevel.title || "")
        window.tagsType = Object.prototype.toString.call(ipc.tags) + (Array.isArray(ipc.tags) ? " (array)" : " (not an array)")
        window.minimizedFrom = TasksModel.minimizedFrom(window.tags)
        window.onTaskbarOf = monitors.filter(function(monitor) {
          return TasksModel.belongsTo(window, monitor.view)
        }).map(function(monitor) { return monitor.name })
        windows.push(window)
      }
      return JSON.stringify({
        barSettings: root.settings,
        settings: parsed.settings,
        settingProblems: parsed.problems,
        order: root.windowOrder,
        monitors: monitors,
        windows: windows
      }, null, 2)
    }

    // Changes a widget's settings, as the bar's menus do, and saves them.
    //   omarchy-shell transom set tray '{"maxIcons": 3}'
    //   omarchy-shell transom set bar '{"maximizedRaiseWorkaround": false}'
    // Returns the entry afterwards (null removes a setting).
    function set(id: string, changes: string): string {
      var parsed = null
      try { parsed = JSON.parse(changes) } catch (error) { return "not JSON: " + error }
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return "changes must be a JSON object"
      for (var key in parsed) if (parsed[key] === null) parsed[key] = undefined
      root.updateWidget(id, parsed)
      return JSON.stringify(id === "bar" ? root.layout.bar : root.entryFor(id))
    }

    // Omarchy's bar widgets that can go on this bar, and where each is now.
    //   omarchy-shell transom widgets
    function widgets(): string {
      return JSON.stringify(root.omarchyWidgetList.map(function(widget) {
        var entry = root.entryFor(widget.id)
        return {
          id: widget.id,
          name: widget.name,
          bottomBar: !!entry && entry.enabled !== false,
          topBar: TrayModel.layoutsHave([root.topBarLayout], widget.id)
        }
      }), null, 2)
    }

    // Every tray icon, the name to use for it in pinned/hidden, and where it
    // goes with the current settings.
    //   omarchy-shell transom tray
    function tray(): string {
      var trayEntry = null
      var sections = [root.layout.left, root.layout.center, root.layout.right]
      for (var s = 0; s < sections.length; s++) {
        for (var e = 0; e < sections[s].length; e++) if (sections[s][e].id === "tray") trayEntry = sections[s][e]
      }
      var parsed = Settings.parse(trayEntry, TrayModel.SETTINGS)
      var values = SystemTray.items.values
      var icons = []
      for (var i = 0; i < values.length; i++) {
        var item = values[i]
        icons.push({
          key: i,
          id: String(item.id || ""),
          title: String(item.title || ""),
          tooltipTitle: String(item.tooltipTitle || ""),
          passive: item.status === Status.Passive
        })
      }
      var shown = icons.filter(function(icon) { return !icon.passive })
      var arranged = TrayModel.arrange(shown, parsed.settings, [root.topBarLayout, root.layout])
      var place = {}
      arranged.bar.forEach(function(key) { place[key] = "bar" })
      arranged.overflow.forEach(function(key) { place[key] = "overflow" })
      arranged.left_out.forEach(function(key) { place[key] = "left out (hidden, or a widget shows it)" })
      return JSON.stringify({
        settings: parsed.settings,
        settingProblems: parsed.problems,
        icons: icons.map(function(icon) {
          return {
            name: TrayModel.nameFor(icon),
            id: icon.id,
            title: icon.title,
            tooltipTitle: icon.tooltipTitle,
            where: icon.passive ? "not shown (the app marked it passive)" : (place[icon.key] || "?")
          }
        })
      }, null, 2)
    }
  }

  // --------------------------------------------------------------- screens

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarWindow {
        required property var modelData

        screen: modelData
        bar: root
      }
    }
  }
}
