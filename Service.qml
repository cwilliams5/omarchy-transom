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
import "Reorder.js" as Reorder
import "QuickLaunchModel.js" as QuickLaunchModel
import "TopBarWidget.js" as TopBarWidget
import "Registry.js" as Registry
import "IconStyle.js" as IconStyle
import "Hosting.js" as Hosting

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
  // Omarchy's top bar is toggled off (omarchy-toggle-bar).
  readonly property bool topBarHidden: !!(shell && shell.bar && shell.bar.barHidden)
  // The taskbar hides with it, unless the bar option hideWithTopBar is off
  // (Transom as the only bar, the more Windows-like setup).
  readonly property bool hidden: topBarHidden && root.settings.hideWithTopBar !== false

  // --------------------------------------------------------------- widgets

  // Widget ids the layout can use, and the file each one loads.
  readonly property var widgets: ({
    "tasks": "widgets/Tasks.qml",
    "quicklaunch": "widgets/QuickLaunch.qml",
    "tray": "widgets/Tray.qml",
    "showdesktop": "widgets/ShowDesktop.qml"
  })

  // Omarchy's own bar widgets the bar menu offers, as [{ id, name }] sorted
  // by name (Hosting.menuList: not its tray, not other plugins' widgets).
  readonly property var omarchyWidgetList: Hosting.menuList(root.barWidgetRegistry ? root.barWidgetRegistry.widgets : null)

  // The top bar's layout (shell.json bar.layout), e.g. for the tray to leave
  // out an app icon a top-bar widget already shows.
  readonly property var topBarLayout: barConfig.layout || ({})

  // One popup open at a time across the bar, as on Omarchy's top bar. A
  // widget opening a menu, flyout or panel claims the bar; the previous
  // owner's closePopups() runs. A click on empty bar space closes it.
  property var popupOwner: null
  // The bar window (screen) the open popup belongs to: owners say with
  // their panel property. An auto-hidden bar stays up only for its own.
  property var popupWindow: null

  function claimPopup(owner) {
    if (root.popupOwner && root.popupOwner !== owner && typeof root.popupOwner.closePopups === "function")
      root.popupOwner.closePopups()
    root.popupOwner = owner
    root.popupWindow = owner && owner.panel ? owner.panel : null
  }

  // Whether the popup that claimed the bar is still open. Owners say so
  // with popupVisible.
  readonly property bool popupOpen: !!popupOwner && popupOwner.popupVisible === true

  function dismissPopups() {
    if (root.popupOwner && typeof root.popupOwner.closePopups === "function") root.popupOwner.closePopups()
    root.popupOwner = null
    root.popupWindow = null
  }

  // Whether id is a bar widget from Omarchy's catalogue this bar can host
  // (omarchy.network...; never Transom's own, Hosting.canHost).
  function isOmarchyWidget(id) {
    return Hosting.canHost(id, root.barWidgetRegistry ? root.barWidgetRegistry.widgets : null)
  }

  // Omarchy hands over its widget catalogue a moment after the plugin
  // (re)loads. Its widgets load then; until then they aren't unknown.
  readonly property bool catalogueReady: !!(root.barWidgetRegistry && root.barWidgetRegistry.widgets
    && Object.keys(root.barWidgetRegistry.widgets).length > 0)

  function widgetUrl(id) {
    var key = String(id || "")
    if (Object.prototype.hasOwnProperty.call(root.widgets, key)) return Qt.resolvedUrl(root.widgets[key])
    if (root.isOmarchyWidget(key)) return Qt.resolvedUrl("widgets/OmarchyWidget.qml")
    if (root.catalogueReady) console.warn("transom: no widget called \"" + key + "\" (known: " + Object.keys(root.widgets).join(", ") + ", and Omarchy's)")
    return ""
  }

  // ---------------------------------------------------- layout and settings

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/transom.json"
  readonly property var sections: ["left", "center", "right"]
  // Where a widget goes when it's switched on but isn't in the file at all.
  readonly property var homeSection: ({ "tasks": "center", "quicklaunch": "left", "tray": "right", "showdesktop": "right" })

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


  // Bar-wide options: the "bar" object at the top of the settings file.
  readonly property var barSettingsSpec: ({
    // See raiseSteps. Remove once Hyprland draws a focused maximized window
    // above floating ones (tracked as omacom/omarchy#16241; CLAUDE.md,
    // "Platform facts", says what to remove).
    maximizedRaiseWorkaround: { default: true },
    // "Lock the taskbar": nothing on the bar can be dragged.
    locked: { default: false },
    // Hyprland moves the pointer to a window focused by command. Off (the
    // default, as with Windows' taskbar), the bar's own clicks leave the
    // pointer where it is; nothing else changes (TasksModel.dispatchChunk).
    pointerToWindow: { default: false },
    // Show the taskbar. False hides it on every screen, from the top-bar
    // widget (BarWidget.qml) or `omarchy-shell transom hide`, but only
    // while that widget is on a bar with its icon showing: see taskbarShown.
    visible: { default: true },
    // Show the top-bar widget's icon. False leaves the widget on Omarchy's
    // bar taking no room, so it keeps Transom running (see
    // iconKeepsTransomOn) without being seen. Never together with a hidden
    // taskbar: one of the two stays as the way back.
    topBarIcon: { default: true },
    // App icons (the tray and quick launch): as they are, in grays, or in
    // shades of the theme's color. IconStyle.js decides each icon's style.
    iconStyle: { default: "color", choices: ["color", "mono", "themed"] },
    // Window icons (the taskbar buttons), the same three styles. The
    // focused window's button keeps its color unless iconStyleOn.activeWindow.
    windowIconStyle: { default: "color", choices: ["color", "mono", "themed"] },
    // The theme color "themed" uses: its accent (changes most visibly with
    // the theme) or its bar text color (matches Omarchy's widget glyphs).
    iconTint: { default: "accent", choices: ["accent", "text"] },
    // tray / quickLaunch: false keeps that one in color. activeWindow: the
    // focused window's button takes windowIconStyle too. inactiveWindows is
    // the older way to style window buttons (with iconStyle), still read
    // while windowIconStyle is "color".
    iconStyleOn: {
      default: { tray: true, quickLaunch: true, inactiveWindows: false, activeWindow: false },
      hint: "an object like {\"tray\": true, \"quickLaunch\": true, \"inactiveWindows\": false, \"activeWindow\": false}",
      accept: function(value) {
        if (!value || typeof value !== "object" || Array.isArray(value)) return undefined
        var out = { tray: true, quickLaunch: true, inactiveWindows: false, activeWindow: false }
        for (var key in value) {
          if (!Object.prototype.hasOwnProperty.call(out, key) || typeof value[key] !== "boolean") return undefined
          out[key] = value[key]
        }
        return out
      }
    },
    // Names (any part of an app id or name, any case) whose icons stay in color.
    iconStyleExceptions: { default: [] },
    // Windows' "Automatically hide the taskbar": hidden until the pointer
    // reaches the bottom edge, and windows get the space back.
    autohide: { default: false },
    // Hide while Omarchy's top bar is toggled off. Off keeps the taskbar up
    // then, for using it as the only bar.
    hideWithTopBar: { default: true },
    // How long after the pointer leaves the bar it hides (ms).
    autohideDelay: { default: 600, min: 0, max: 10000 },
    // How it appears and goes: at once, or sliding (a short slide).
    reveal: { default: "instant", choices: ["instant", "slide"] },
    // Which screens get a bar: "all", "primary" (Hyprland's first
    // monitor), or a list of monitor names like ["eDP-1"].
    screens: {
      default: "all",
      hint: "\"all\", \"primary\" or a list of monitor names",
      accept: function(value) {
        if (value === "all" || value === "primary") return value
        var list = Settings.toList(value)
        if (!list) return undefined
        list = list.filter(function(name) { return typeof name === "string" && name.trim() !== "" })
        return list.length > 0 ? list.map(function(name) { return name.trim() }) : undefined
      }
    }
  })
  readonly property var parsedBarSettings: Settings.parse(layout.bar, barSettingsSpec)
  readonly property var settings: parsedBarSettings.settings
  readonly property bool locked: settings.locked === true
  readonly property string iconStyle: settings.iconStyle
  // What window buttons get, older settings included (for the menus).
  readonly property string windowIconStyle: IconStyle.windowStyle(settings)

  // The style for one app's icon, given where it is (target: "tray",
  // "quickLaunch", "inactiveWindows" or "activeWindow") and its ids and
  // names, for iconStyleExceptions. IconStyle.styleFor has the rules.
  function iconStyleFor(names, target) {
    return IconStyle.styleFor(root.settings, target, Settings.toList(names) || [])
  }

  // Saves a new style for window buttons (from the menus).
  function setWindowIconStyle(style) {
    root.updateWidget("bar", IconStyle.windowStyleChanges(root.settings, style))
  }

  // Saves whether the focused window's button keeps its color.
  function setFocusedWindowColor(keep) {
    root.updateWidget("bar", IconStyle.focusedColorChanges(root.settings, keep))
  }

  // The color an icon of this style is drawn in: for themed, the theme's
  // accent or bar text color (iconTint); otherwise the bar text color, which
  // symbolic icons are always filled with.
  function iconTintFor(style) {
    if (style === "themed" && root.settings.iconTint === "accent") return Commons.Color.accent
    return root.foreground
  }

  // ------------------------------------------------------ top-bar widget

  // Live copies of the optional top-bar widget (BarWidget.qml) using this
  // service; each counts itself while it exists.
  property int widgetCopies: 0
  // A live copy exists, or left less than a second ago (the top bar
  // rebuilds a widget now and then).
  property bool widgetLive: false
  onWidgetCopiesChanged: {
    if (root.widgetCopies > 0) {
      root.widgetLive = true
      widgetGoneTimer.stop()
    } else if (root.widgetLive) {
      widgetGoneTimer.restart()
    }
  }
  // For a while after start-up, Omarchy's layout listing the widget counts
  // too, until a copy has had time to count itself, so a hidden taskbar
  // doesn't flash up at every shell start. After that only a live copy is a
  // way back: a widget in the layout that never loads (broken by an update,
  // or a replacement bar that doesn't draw it) isn't (strict review R1-M1).
  property int startupGraceMs: 10000
  property bool startupGrace: true
  Timer {
    interval: root.startupGraceMs
    running: root.startupGrace
    onTriggered: root.startupGrace = false
  }
  // The widget is on a bar (its icon showing or not).
  readonly property bool widgetOnBar: root.widgetLive || (root.startupGrace && TopBarWidget.inLayout(root.topBarLayout))
  // The bar option topBarIcon: the widget draws its icon.
  readonly property bool topBarIconShown: root.settings.topBarIcon !== false
  // Drawn or not: the bar option visible, which only counts while the
  // widget's icon is on a bar, since its "Show the taskbar" switch is the
  // way back. Take the widget off, or hide its icon, and the taskbar shows.
  readonly property bool taskbarShown: TopBarWidget.taskbarShown(root.settings.visible, root.widgetOnBar && root.topBarIconShown)
  onTaskbarShownChanged: if (!taskbarShown) root.dismissPopups()

  // Whether removing the widget would turn Transom off: Omarchy runs a
  // plugin with a widget only while the widget is on a bar, unless its id
  // is also in shell.json's plugins list (`omarchy plugin add --enable`
  // doesn't put it there). Read from shell.json, never written; while it
  // can't be read, assume not (no warning).
  property var shellPlugins: null
  readonly property bool iconKeepsTransomOn: root.widgetOnBar && TopBarWidget.listedInPlugins(root.shellPlugins) === false
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var config = JSON.parse(text())
        root.shellPlugins = config && typeof config === "object" ? config.plugins : null
      } catch (error) {
        root.shellPlugins = null
      }
    }
    onLoadFailed: root.shellPlugins = null
  }

  // Shows or hides the widget's icon and saves it. Hiding it shows the
  // taskbar too, so one of the two is always there to bring the other back.
  // Showing it when the widget isn't on any bar (dragged off) puts it back.
  function setTopBarIconShown(on) {
    if (on && !root.widgetOnBar) {
      // Put back from the taskbar's own menu: the taskbar stays, even if
      // it was saved as hidden before the widget went (a saved "hidden"
      // otherwise applies again when the widget is back, R2-L7, and the
      // bar just clicked would vanish).
      root.putWidgetOnTopBar()
      root.updateWidget("bar", { topBarIcon: undefined, visible: undefined })
      return
    }
    if (on) root.updateWidget("bar", { topBarIcon: undefined })
    else root.updateWidget("bar", { topBarIcon: false, visible: undefined })
  }

  // Puts the widget back on Omarchy's top bar after it was dragged off, so
  // the taskbar can always bring back the widget, as the widget brings back
  // the taskbar. Done by Omarchy's own command (putBarWidget: only when the
  // widget isn't on the bar, in the section its manifest names), which
  // writes Omarchy's own shell.json as dragging a widget onto the bar does:
  // the one change to Omarchy's config Transom asks for, and only on a
  // click (CLAUDE.md rule 1).
  function putWidgetOnTopBar() {
    if (root.widgetOnBar) return "already on a bar"
    console.log("transom: putting the top-bar widget back (omarchy-shell shell putBarWidget)")
    Util.execDetached("omarchy-shell shell putBarWidget " + Util.shellQuote(TopBarWidget.PLUGIN_ID) + " '{}'")
    return "put back"
  }

  // When the last copy has been gone for a second, the taskbar shows
  // (taskbarShown). Nothing is written: a saved "hidden" applies again when
  // the widget comes back, as the user left it (R2-L7: a monitor change
  // could otherwise rewrite the file).
  Timer {
    id: widgetGoneTimer
    interval: 1000
    onTriggered: {
      if (root.widgetCopies > 0) return
      root.widgetLive = false
      if (root.settings.visible === false) console.log("transom: the top-bar widget is gone, so the taskbar shows")
    }
  }

  // Shows or hides the taskbar and saves it. Hiding needs the widget on a
  // bar; without it this says so and changes nothing.
  function showTaskbar() {
    if (root.settings.visible !== false) return "shown"
    if (root.settingsError !== "") {
      // Showing is the way back, so it works while saving is paused, in
      // memory only (R2-L3).
      var next = JSON.parse(JSON.stringify(root.layout))
      if (next.bar) delete next.bar.visible
      root.layout = next
      return "shown, but not saved: " + root.configPath + " has a problem"
    }
    return root.updateWidget("bar", { visible: undefined }) ? "shown" : "not shown: " + root.settingsProblem
  }
  function hideTaskbar() {
    if (!root.widgetOnBar) return "not hidden: put Transom's widget on the top bar first (the bar menu's \"Top-bar icon\" does it; its \"Show the taskbar\" switch brings the taskbar back)"
    if (!root.topBarIconShown) return "not hidden: show Transom's top-bar icon first (bar menu, \"Top-bar icon\"): it's the way back"
    if (root.settings.visible === false) return "hidden"
    return root.updateWidget("bar", { visible: false }) ? "hidden" : "not hidden: " + root.settingsProblem
  }
  function toggleTaskbar() {
    return root.taskbarShown ? root.hideTaskbar() : root.showTaskbar()
  }

  // Opens the bar's right-click menu (BarMenu.qml) from the top-bar widget,
  // on the bar of the screen named, or the first bar.
  signal barMenuRequested(string screenName)
  function openBarMenu(screenName) {
    if (!root.taskbarShown) return
    var screens = Settings.toList(root.barScreens) || []
    if (screens.length === 0) return
    var name = String(screens[0].name)
    for (var i = 0; i < screens.length; i++) if (String(screens[i].name) === String(screenName || "")) name = String(screens[i].name)
    root.barMenuRequested(name)
  }

  // Omarchy's default coding agent (omarchy default agent <name>), for its
  // logo on quick launch and on its windows' taskbar buttons. The logos ship
  // with Omarchy's agents panel, some with a twin for light surfaces.
  property string agentId: ""
  // Omarchy's plugin host sets this on services; the fallback covers the gap.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property bool lightBar: 0.2126 * themeBackground.r + 0.7152 * themeBackground.g + 0.0722 * themeBackground.b > 0.5

  // Omarchy creates its defaults folder only when an agent is first picked,
  // and a watch on a missing folder never fires, so while no agent is known
  // the file is read again on window events too (strict review R1-L10).
  FileView {
    id: agentFile
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.agentId = text().trim()
  }

  // Agent ids whose logo file is named differently.
  readonly property var agentLogoNames: ({ "cursor-agent": "cursor", "ori": "openrouter" })

  function agentIcons() {
    if (!root.agentId) return []
    var base = root.omarchyPath + "/shell/plugins/agents/assets/" + (Object.prototype.hasOwnProperty.call(root.agentLogoNames, root.agentId) ? root.agentLogoNames[root.agentId] : root.agentId)
    return root.lightBar ? [base + "-light.svg", base + ".svg"] : [base + ".svg"]
  }
  onParsedBarSettingsChanged: {
    var problems = parsedBarSettings.problems
    for (var i = 0; i < problems.length; i++) console.warn("transom: bar setting ignored: " + problems[i])
  }

  // What's wrong with the user's file, or "" (Settings.readLayout). While
  // it's set, nothing is saved: a click would otherwise replace a file the
  // bar couldn't fully read (strict review R1-H4). The bar shows what it
  // could read, or the last good settings, or the defaults.
  property string settingsError: ""
  // The last save failed (an unwritable file or folder): the bar went back
  // to what's on disk, and says so until a save works (R1-L6, R2-L1).
  property string saveError: ""
  readonly property string settingsProblem: settingsError !== "" ? settingsError : saveError
  // The text on disk as last read or saved, to go back to after a failed save.
  property string diskText: ""
  // A good file has been read this session. Until then a broken one runs on
  // the defaults minus anything that closes or launches (R2-L4).
  property bool readGood: false

  // A problem is notified once it has lasted half a second (an editor
  // saving in place empties the file for a moment, R2-L2), and a later one
  // again once the first has cleared (R2-L1). The bar menu and the
  // dropdown say it too, for as long as it lasts.
  property string notifiedProblem: ""
  onSettingsProblemChanged: {
    if (root.settingsProblem === "") {
      root.notifiedProblem = ""
      problemNotice.stop()
    } else {
      problemNotice.restart()
    }
  }
  Timer {
    id: problemNotice
    interval: 500
    onTriggered: {
      var problem = root.settingsProblem
      if (problem === "" || problem === root.notifiedProblem) return
      root.notifiedProblem = problem
      console.warn("transom: " + root.configPath + ": " + problem)
      var effect = root.settingsError !== "" ? "Changes from the menus are paused until it's fixed." : "Changes from the menus can't be saved."
      Util.execDetached("notify-send -a Transom " + Util.shellQuote("Transom's settings file has a problem")
        + " " + Util.shellQuote(root.configPath + ": " + problem + ". " + effect))
    }
  }

  function applyUserText(text) {
    if (text === root.layoutText && root.settingsError === "") return
    var read = Settings.readLayout(text, root.sections)
    root.layoutText = text
    root.diskText = text
    if (read.problems.length > 0) {
      root.settingsError = read.problems.join("; ")
      if (read.layout) root.layout = read.layout
      else if (!root.readGood) root.layout = Settings.safeLayout(root.defaultLayout, root.sections)
      return
    }
    root.settingsError = ""
    root.readGood = true
    root.layout = read.layout
  }

  // Reads the file again right before a change is saved, so a change the
  // watcher missed is never saved over (R2-M1): once a symlinked
  // transom.json is replaced or re-pointed, the watching FileView keeps
  // reading the old target, even on reload. diskCheck opens the path afresh
  // (reload() on a FileView of its own, read synchronously), and anything
  // new is applied before the change goes on top of it.
  function refreshFromDisk() {
    diskCheck.path = root.configPath
    diskCheck.reload()
    var text = diskCheck.text()
    if (text !== "" && text !== root.diskText) {
      console.log("transom: " + root.configPath + " changed on disk unseen; read it again before saving")
      root.applyUserText(text)
      root.reattachUserFile()
    }
  }

  // Points the watching FileView at the path afresh, after a change it
  // missed (it was watching a replaced symlink's old target), so it sees
  // later edits again. Its load while re-attaching changes nothing: the
  // text is what Transom already has.
  property bool reattaching: false
  function reattachUserFile() {
    root.reattaching = true
    userFile.path = ""
    userFile.path = Qt.binding(function() { return root.configPath })
    root.reattaching = false
  }

  // blockAllReads: text() waits for the read, so the check is done before
  // the save (blockLoading alone doesn't make reload() wait).
  FileView {
    id: diskCheck
    blockAllReads: true
    printErrors: false
  }

  FileView {
    path: root.pluginDir + "/defaults.json"
    blockLoading: true
    printErrors: false
    onLoaded: {
      var read = Settings.readLayout(text(), root.sections)
      if (read.problems.length > 0) console.warn("transom: defaults.json: " + read.problems.join("; "))
      if (!read.layout) return
      root.defaultLayout = read.layout
      if (!root.userConfigExists) root.layout = read.layout
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
    onLoadFailed: function(error) {
      if (root.reattaching) return
      // Only a file that isn't there means "no settings yet". One that is
      // there but can't be read (permissions, not a file) is a problem like
      // invalid JSON: nothing is saved over it (rule 19), and until it's
      // readable the bar runs on what it had, or the safe defaults.
      if (error !== FileViewError.FileNotFound) {
        root.userConfigExists = true
        // Forgotten, so the next click's re-read (refreshFromDisk) applies
        // the file once it's readable again, even unchanged.
        root.layoutText = ""
        root.diskText = ""
        root.settingsError = "it couldn't be read (" + FileViewError.toString(error) + ")"
        if (!root.readGood) root.layout = Settings.safeLayout(root.defaultLayout, root.sections)
        return
      }
      root.userConfigExists = false
      root.layoutText = ""
      root.diskText = ""
      root.settingsError = ""
      root.layout = root.defaultLayout
    }
    onFileChanged: reload()
    onSaved: {
      root.diskText = root.layoutText
      root.saveError = ""
    }
    onSaveFailed: function(error) {
      // Back to what's on disk (memory had already moved on), then say so.
      var disk = root.diskText
      root.layoutText = ""
      if (disk !== "") root.applyUserText(disk)
      else root.layout = root.defaultLayout
      root.saveError = "it couldn't be saved (is it, or its folder, read-only?)"
    }
  }

  // Writes the whole layout to the user's file and applies it. Refused
  // while the file has a problem (settingsError): returns false.
  function saveLayout(next) {
    if (root.settingsError !== "") {
      console.warn("transom: not saved: " + root.configPath + ": " + root.settingsError)
      return false
    }
    var text = JSON.stringify(next, null, 2) + "\n"
    root.layoutText = text
    root.userConfigExists = true
    root.layout = next
    userFile.setText(text)
    return true
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
    if (typeof id !== "string" || id === "") return false
    root.refreshFromDisk()
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
      var section = next[Object.prototype.hasOwnProperty.call(root.homeSection, id) ? root.homeSection[id] : "right"]
      var last = section.length > 0 && section[section.length - 1].id === "showdesktop" && id !== "showdesktop"
      section.splice(last ? section.length - 1 : section.length, 0, entry)
    }
    for (var key in changes) {
      if (changes[key] === undefined) delete entry[key]
      else entry[key] = changes[key]
    }
    console.log("transom: setting " + id + " " + JSON.stringify(changes))
    return root.saveLayout(next)
  }

  // Omarchy's own widgets (the start button, network, battery...) are
  // dragged as a whole along the side sections. Transom's own widgets
  // aren't: the tray, the taskbar buttons and quick launch drag their icons
  // instead, and show desktop stays in the corner.
  function canDragWidget(id) {
    return !root.locked && !Object.prototype.hasOwnProperty.call(root.widgets, String(id || "")) && root.isOmarchyWidget(id)
  }

  // Moves a widget into section, before the widget beforeId (or to the
  // end, before show desktop), keeping its settings. From a drag.
  function moveWidget(id, section, beforeId) {
    root.refreshFromDisk()
    var next = Reorder.moveEntry(root.layout, id, section, beforeId)
    if (!next) return
    console.log("transom: moved " + id + " to " + section + (beforeId ? " before " + beforeId : ""))
    root.saveLayout(next)
  }

  function setWidgetEnabled(id, on) {
    root.updateWidget(id, { enabled: on ? undefined : false })
  }

  // Quick launch on or off. Turned on for the first time, it starts with the
  // browser and terminal.
  function setQuickLaunchEnabled(on) {
    if (!on) {
      root.setWidgetEnabled("quicklaunch", false)
      return
    }
    var entry = root.entryFor("quicklaunch")
    var changes = { enabled: undefined }
    if (!entry || !entry.apps) changes.apps = ["browser", "terminal"]
    root.updateWidget("quicklaunch", changes)
  }

  // Quick launch, from the taskbar buttons' menu: is the app with this
  // desktop entry id on it, add it (adding quick launch to the bar if it
  // isn't there), take it off.
  function quickLaunchApps() {
    var entry = root.entryFor("quicklaunch")
    return entry ? (Settings.toList(entry.apps) || []) : []
  }

  function isPinnedToQuickLaunch(id) {
    var entry = root.entryFor("quicklaunch")
    return !!entry && entry.enabled !== false && QuickLaunchModel.isPinned(entry.apps, id)
  }

  function pinToQuickLaunch(id) {
    root.updateWidget("quicklaunch", { apps: QuickLaunchModel.appsAfterPin(root.quickLaunchApps(), id), enabled: undefined })
  }

  function unpinFromQuickLaunch(id) {
    root.updateWidget("quicklaunch", { apps: QuickLaunchModel.appsAfterUnpin(root.quickLaunchApps(), id) })
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

  // A dispatch's window. Only ever a Hyprland address (0x and hex): nothing
  // else may reach Hyprland's Lua (rule 18; strict review R1-L4).
  function target(address) {
    var value = TasksModel.normalizeAddress(address)
    if (!/^0x[0-9a-fA-F]+$/.test(value)) value = "0x0"
    return "window = \"address:" + value + "\""
  }

  // The bar's clicks leave the pointer where it is (bar option
  // pointerToWindow off).
  readonly property bool keepPointer: root.settings.pointerToWindow !== true

  // Runs Hyprland dispatches in order, as one Lua chunk inside Hyprland
  // (TasksModel.dispatchChunk: nothing interleaves, and the pointer stays
  // put unless pointerToWindow), then any `after` ones 0.4s later. Each is
  // logged to the shell log (see README, Developing).
  function dispatch(steps, after) {
    console.log("transom: " + steps.concat(after || []).join(" ; "))
    // Each hyprctl under a deadline: a Hyprland that doesn't answer mustn't
    // leave these running (CLAUDE.md rule 20).
    var command = "timeout 2 hyprctl repl " + Util.shellQuote(TasksModel.dispatchChunk(steps, root.keepPointer))
    if (after && after.length > 0) command += "; sleep 0.4; timeout 2 hyprctl repl " + Util.shellQuote(TasksModel.dispatchChunk(after, false))
    Util.execDetached(command)
  }

  // A window's last snapshot (lastIpcObject), by address, or null.
  function ipcOf(address) {
    var wanted = TasksModel.normalizeAddress(address)
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      if (TasksModel.normalizeAddress(list[i].address) === wanted) return list[i].lastIpcObject || null
    }
    return null
  }

  // Whether Hyprland has the window maximized (fullscreen mode 1).
  function isMaximized(address) {
    return TasksModel.isMaximizedIpc(root.ipcOf(address))
  }

  // The steps that put a focused window on top of the others. A maximized
  // window needs more (when bar option maximizedRaiseWorkaround is on, the
  // default): Hyprland keeps drawing floating windows over it even
  // once it has focus (no raise or bring_to_top helps), and those windows
  // then look clickable but aren't. Taking it out of maximized, raising it
  // and maximizing it again does put it on top. Animation is off meanwhile,
  // so it isn't seen. Found 2026-11-17 with a floating window over a
  // maximized browser; reproduced with test windows.
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

  // Minimizes windows, one after another (a button's click or menu).
  function minimizeWindows(addresses) {
    if (!addresses || addresses.length === 0) return
    console.log("transom: minimize " + addresses.join(" "))
    Util.execDetached(root.minimizeCommand(addresses))
  }

  // The shell command that minimizes windows one after another (show
  // desktop runs it itself, to know when it's done). --keep-pointer: the
  // script's focus leaves the pointer where it is, as the bar's other
  // clicks do.
  function minimizeCommand(addresses) {
    var script = Util.shellQuote(root.pluginDir + "/minimize") + (root.keepPointer ? " --keep-pointer" : "")
    return (addresses || []).map(function(address) { return script + " " + Util.shellQuote(address) }).join("; ")
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
    root.dispatch(steps, after)
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
    onTriggered: {
      Hyprland.refreshToplevels()
      if (root.agentId === "") agentFile.reload()
    }
  }

  // Which screen each workspace was last on, kept after Hyprland drops an
  // empty workspace, so a window minimized from a screen with no bar keeps
  // its button on the bars there are (strict review R2-L5). As
  // [{ id, monitorName }] for TasksModel.barlessWorkspaces.
  property var workspaceScreenNames: Object.create(null)
  readonly property var currentWorkspaceScreens: Hyprland.workspaces.values.map(function(workspace) {
    return { id: workspace.id, monitorName: workspace.monitor ? String(workspace.monitor.name) : "" }
  })
  onCurrentWorkspaceScreensChanged: {
    var next = Object.create(null)
    for (var key in root.workspaceScreenNames) next[key] = root.workspaceScreenNames[key]
    root.currentWorkspaceScreens.forEach(function(workspace) { if (workspace.monitorName) next[workspace.id] = workspace.monitorName })
    root.workspaceScreenNames = next
  }
  readonly property var workspaceScreens: {
    var out = []
    for (var key in root.workspaceScreenNames) out.push({ id: Number(key), monitorName: root.workspaceScreenNames[key] })
    return out
  }
  // The screens that have a bar, by name.
  readonly property var barScreenNames: (Settings.toList(root.barScreens) || []).map(function(screen) { return String(screen.name) })
  // The workspaces shown on screens with no bar.
  readonly property var barlessActive: (Settings.toList(Hyprland.monitors.values) || []).filter(function(monitor) {
    return root.barScreenNames.indexOf(String(monitor.name)) < 0 && monitor.activeWorkspace
  }).map(function(monitor) { return monitor.activeWorkspace.id })

  // Which events start it: TasksModel.REFRESH_EVENTS ("pin", because a
  // pinned window's tags can change with it; the group events, because a
  // group's other tabs are hidden).

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      var activeWasHidden = name === "activewindowv2" && TasksModel.hiddenOrGrouped(root.ipcOf(event.data))
      if (TasksModel.startsRefresh(name, refreshTimer.running, activeWasHidden)) refreshTimer.start()
    }
  }

  Component.onCompleted: {
    Registry.service = root
    Hyprland.refreshToplevels()
  }
  Component.onDestruction: if (Registry.service === root) Registry.service = null

  // The taskbar's window order for the session, as window addresses, set by
  // dragging buttons. Shared by every screen's taskbar; new windows go last.
  property var windowOrder: []

  // Diagnostics: what the taskbar sees for every window.
  //   omarchy-shell transom windows
  ShellIpc {
    target: "transom"

    function windows(): string {
      var parsed = Settings.parse(root.entryFor("tasks"), TasksModel.SETTINGS)
      var known = Hyprland.workspaces.values.map(function(workspace) { return workspace.id })
      var barless = TasksModel.barlessWorkspaces(root.workspaceScreens, root.barScreenNames)
      var monitors = Hyprland.monitors.values.map(function(monitor) {
        return {
          name: monitor.name,
          view: {
            mode: parsed.settings.windows,
            workspaceId: monitor.activeWorkspace ? monitor.activeWorkspace.id : -1,
            monitorWorkspaces: Hyprland.workspaces.values.filter(function(workspace) { return workspace.monitor === monitor })
              .map(function(workspace) { return workspace.id }),
            knownWorkspaces: known,
            barlessWorkspaces: barless,
            barlessActive: root.barlessActive,
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
      if (!root.updateWidget(id, parsed)) return "not saved: " + (id === "" ? "no widget id" : root.settingsProblem)
      return JSON.stringify(id === "bar" ? root.layout.bar : root.entryFor(id))
    }

    // Shows, hides or toggles the taskbar, as the top-bar widget's switch
    // does (for a key binding). Hiding needs that widget on a bar, icon
    // shown or not: it's the way back.
    //   omarchy-shell transom toggle
    function show(): string { return root.showTaskbar() }
    function hide(): string { return root.hideTaskbar() }
    function toggle(): string { return root.toggleTaskbar() }

    // What the service knows about its top-bar widget.
    //   omarchy-shell transom widget
    function widget(): string {
      return JSON.stringify({
        onBar: root.widgetOnBar,
        inTopBarLayout: TopBarWidget.inLayout(root.topBarLayout),
        liveCopies: root.widgetCopies,
        iconShown: root.topBarIconShown,
        taskbarShown: root.taskbarShown,
        listedInPlugins: TopBarWidget.listedInPlugins(root.shellPlugins),
        removingTurnsTransomOff: root.iconKeepsTransomOn
      }, null, 2)
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
      var parsed = Settings.parse(root.entryFor("tray"), TrayModel.SETTINGS)
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
      // The same layouts the bar's tray reads (switched-off entries left out).
      var arranged = TrayModel.arrange(shown, parsed.settings, [root.topBarLayout, root.shownLayout])
      var place = Object.create(null)
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

  // The screens that get a bar (bar option screens). Names that match no
  // connected monitor fall back to every screen, so an unplugged monitor
  // never leaves the bar nowhere.
  readonly property var barScreens: {
    var all = Settings.toList(Quickshell.screens) || []
    var wanted = root.settings.screens
    if (wanted === "all" || all.length <= 1) return all
    var names = []
    if (wanted === "primary") {
      var monitors = Settings.toList(Hyprland.monitors.values) || []
      var first = null
      for (var i = 0; i < monitors.length; i++) if (!first || monitors[i].id < first.id) first = monitors[i]
      names = first ? [first.name] : []
    } else {
      names = wanted.map(function(name) { return name.toLowerCase() })
    }
    var picked = all.filter(function(screen) {
      return names.some(function(name) { return name.toLowerCase() === String(screen.name).toLowerCase() })
    })
    return picked.length > 0 ? picked : all
  }

  Variants {
    model: root.barScreens

    delegate: Component {
      BarWindow {
        required property var modelData

        screen: modelData
        bar: root
      }
    }
  }
}
