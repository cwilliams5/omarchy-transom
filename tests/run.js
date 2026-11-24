// Tests for the plugin's pure logic (every .js file). Run: node tests/run.js
// The QML (widget, service) is tested by tests/widget.test.sh.
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "..", "TasksModel.js"))
const S = require(path.join(__dirname, "..", "Settings.js"))
const T = require(path.join(__dirname, "..", "TrayModel.js"))
const R = require(path.join(__dirname, "..", "Reorder.js"))
const Q = require(path.join(__dirname, "..", "QuickLaunchModel.js"))
const I = require(path.join(__dirname, "..", "IconSource.js"))
const W = require(path.join(__dirname, "..", "TopBarWidget.js"))
const IS = require(path.join(__dirname, "..", "IconStyle.js"))
const H = require(path.join(__dirname, "..", "Hosting.js"))

let failures = 0
function test(name, fn) {
  try {
    fn()
    console.log("ok   " + name)
  } catch (error) {
    failures++
    console.log("FAIL " + name + "\n     " + error.message)
  }
}

const win = (extra) => Object.assign({
  address: "0xabc", workspaceId: 1, workspaceName: "1", tags: [], hasParent: false
}, extra)
const view = (extra) => Object.assign({
  mode: "workspace", workspaceId: 1, monitorWorkspaces: [1, 2], knownWorkspaces: [1, 2, 3], showMinimized: true
}, extra)
const minimizedFrom = (id) => win({ workspaceId: -97, workspaceName: "special:minimized", tags: ["omarchy-minimized-from-" + id] })

// ------------------------------------------------------------- settings

test("settings default to the documented values", () => {
  const { settings, problems } = S.parse({ id: "tasks" }, M.SETTINGS)
  assert.deepStrictEqual(settings, S.defaults(M.SETTINGS))
  assert.strictEqual(settings.align, "center")
  assert.strictEqual(settings.buttonWidth, 180)
  assert.deepStrictEqual(problems, [])
})

test("valid settings override the defaults", () => {
  const { settings } = S.parse({ id: "tasks", align: "left", tooltip: false, buttonWidth: 150, windows: "all" }, M.SETTINGS)
  assert.strictEqual(settings.align, "left")
  assert.strictEqual(settings.tooltip, false)
  assert.strictEqual(settings.buttonWidth, 150)
  assert.strictEqual(settings.windows, "all")
})

test("invalid settings are ignored and reported", () => {
  const { settings, problems } = S.parse({ id: "tasks", align: "right", tooltip: "yes", buttonWidth: "wide", colour: 1 }, M.SETTINGS)
  assert.strictEqual(settings.align, "center")
  assert.strictEqual(settings.tooltip, true)
  assert.strictEqual(settings.buttonWidth, 180)
  assert.strictEqual(problems.length, 4)
})

test("numbers are clamped to a sane range", () => {
  const { settings } = S.parse({ buttonWidth: 5, workspaces: 40, tooltipDelay: -3 }, M.SETTINGS)
  assert.strictEqual(settings.buttonWidth, 40)
  assert.strictEqual(settings.workspaces, 10)
  assert.strictEqual(settings.tooltipDelay, 0)
})

test("list settings take names, from an array or a Qt sequence", () => {
  assert.deepStrictEqual(S.parse({ pinned: [" steam ", "discord"] }, T.SETTINGS).settings.pinned, ["steam", "discord"])
  assert.deepStrictEqual(S.parse({ pinned: { length: 1, 0: "steam" } }, T.SETTINGS).settings.pinned, ["steam"])
  const bad = S.parse({ pinned: "steam", hidden: ["ok", 3, ""] }, T.SETTINGS)
  assert.deepStrictEqual(bad.settings.pinned, [])
  assert.deepStrictEqual(bad.settings.hidden, ["ok"])
  assert.strictEqual(bad.problems.length, 2)
})

test("defaults are copies, not shared lists", () => {
  const a = S.parse({}, T.SETTINGS).settings
  a.pinned.push("x")
  assert.deepStrictEqual(S.parse({}, T.SETTINGS).settings.pinned, [])
})

// ----------------------------------------------------------------- tray

const icon = (key, id, title, tooltipTitle) => ({ key, id, title: title || "", tooltipTitle: tooltipTitle || "" })
const trayIcons = [
  icon(0, "chrome_status_icon_1"),
  icon(1, "superwhisper", "Superwhisper"),
  icon(2, "Notion_status_icon_6"),
  icon(3, "steam", "Steam"),
  icon(4, "discord", "", "Discord")
]
const traySettings = (extra) => Object.assign(S.parse({}, T.SETTINGS).settings, extra)

test("tray names match any part of id, title or tooltip, any case", () => {
  assert.ok(T.matches(trayIcons[0], "Chrome"))
  assert.ok(T.matches(trayIcons[4], "discord"))
  assert.ok(T.matches(trayIcons[1], "whisper"))
  assert.ok(!T.matches(trayIcons[3], "chrome"))
  assert.ok(!T.matches(trayIcons[3], "  "))
})

test("nameFor gives the short name to put in pinned/hidden", () => {
  assert.strictEqual(T.nameFor(trayIcons[0]), "chrome")
  assert.strictEqual(T.nameFor(trayIcons[2]), "notion")
  assert.strictEqual(T.nameFor(icon(9, "nm-applet")), "nm-applet")
  assert.strictEqual(T.nameFor(icon(9, "", "Some App")), "some app")
})

test("an icon a top-bar widget stands in for is left out", () => {
  const topBar = { right: [{ id: "superwhisper.panel" }] }
  assert.ok(T.standsInFor(trayIcons[1], [topBar, {}]))
  assert.ok(!T.standsInFor(trayIcons[1], [{ right: [] }, {}]))
  assert.ok(T.standsInFor(icon(9, "localsend_tray"), []))
})

test("arrange: everything on the bar when it fits", () => {
  const r = T.arrange(trayIcons, traySettings({}), [])
  assert.deepStrictEqual(r.bar, [0, 1, 2, 3, 4])
  assert.deepStrictEqual(r.overflow, [])
})

test("arrange: past maxIcons goes in the overflow", () => {
  const r = T.arrange(trayIcons, traySettings({ maxIcons: 2 }), [])
  assert.deepStrictEqual(r.bar, [0, 1])
  assert.deepStrictEqual(r.overflow, [2, 3, 4])
})

test("arrange: pinned first, in pinned order, then the rest", () => {
  const r = T.arrange(trayIcons, traySettings({ maxIcons: 3, pinned: ["steam", "notion"] }), [])
  assert.deepStrictEqual(r.bar, [3, 2, 0])
  assert.deepStrictEqual(r.overflow, [1, 4])
})

test("arrange: pinned stay on the bar even past maxIcons", () => {
  const r = T.arrange(trayIcons, traySettings({ maxIcons: 1, pinned: ["steam", "discord"] }), [])
  assert.deepStrictEqual(r.bar, [3, 4])
  assert.deepStrictEqual(r.overflow, [0, 1, 2])
})

test("arrange: overflow off puts every icon on the bar", () => {
  const r = T.arrange(trayIcons, traySettings({ overflow: false, maxIcons: 1, pinned: ["discord"] }), [])
  assert.deepStrictEqual(r.bar, [4, 0, 1, 2, 3])
  assert.deepStrictEqual(r.overflow, [])
})

test("arrange: hidden names and stood-in icons are left out", () => {
  const topBar = { right: [{ id: "superwhisper.panel" }] }
  const r = T.arrange(trayIcons, traySettings({ hidden: ["notion"] }), [topBar])
  assert.deepStrictEqual(r.bar, [0, 3, 4])
  assert.deepStrictEqual(r.left_out.sort(), [1, 2])
})

// ------------------------------------------------------- which windows

test("minimizedFrom reads the tag, static or dynamic", () => {
  assert.strictEqual(M.minimizedFrom(["terminal*", "omarchy-minimized-from-3"]), 3)
  assert.strictEqual(M.minimizedFrom(["omarchy-minimized-from-12*"]), 12)
  assert.strictEqual(M.minimizedFrom(["omarchy-minimized-from-x"]), null)
  assert.strictEqual(M.minimizedFrom(undefined), null)
})

test("minimizedFrom reads a list that isn't a JS array (Qt sequence)", () => {
  const sequence = { length: 2, 0: "chromium-based-browser*", 1: "omarchy-minimized-from-1" }
  assert.strictEqual(M.minimizedFrom(sequence), 1)
})

test("describe reads a Quickshell toplevel", () => {
  const toplevel = {
    address: "55e6ecc659e0",
    workspace: { id: -97, name: "special:minimized" },
    wayland: { parent: null },
    lastIpcObject: { tags: { length: 1, 0: "omarchy-minimized-from-1" }, mapped: true, hidden: false }
  }
  const d = M.describe(toplevel)
  assert.strictEqual(d.address, "0x55e6ecc659e0")
  assert.strictEqual(d.workspaceName, "special:minimized")
  assert.deepStrictEqual(d.tags, ["omarchy-minimized-from-1"])
  assert.ok(M.belongsTo(d, view()))
})

test("describe falls back to IPC data before Quickshell knows the workspace", () => {
  const d = M.describe({ address: "0x1", workspace: null, lastIpcObject: { workspace: { id: 2, name: "2" } } })
  assert.strictEqual(d.workspaceId, 2)
  assert.ok(M.belongsTo(d, view({ workspaceId: 2 })))
})

test("normalizeAddress adds 0x once", () => {
  assert.strictEqual(M.normalizeAddress("55e6"), "0x55e6")
  assert.strictEqual(M.normalizeAddress("0x55e6"), "0x55e6")
  assert.strictEqual(M.normalizeAddress(""), "")
})

test("workspace mode: this workspace's windows and those minimized from it", () => {
  assert.ok(M.belongsTo(win(), view()))
  assert.ok(!M.belongsTo(win({ workspaceId: 2, workspaceName: "2" }), view()))
  assert.ok(M.belongsTo(minimizedFrom(1), view()))
  assert.ok(!M.belongsTo(minimizedFrom(2), view()))
})

test("a window tagged skip-taskbar gets no button, in any mode, unless minimized", () => {
  // Legato's video window: the tag set by a window rule reads back with "*".
  for (const tags of [["skip-taskbar*"], ["omarchy-floating-workspace", "skip-taskbar"]]) {
    for (const mode of ["workspace", "monitor", "all"]) assert.ok(!M.belongsTo(win({ tags }), view({ mode })), mode)
  }
  assert.ok(M.belongsTo(win({ tags: ["skip-taskbar-not", "no-skip-taskbar"] }), view()))
  // Minimized, it still shows, or it couldn't be brought back.
  const minimized = win({ workspaceId: -97, workspaceName: "special:minimized", tags: ["omarchy-minimized-from-1", "skip-taskbar*"] })
  assert.ok(M.belongsTo(minimized, view()))
  // Qt sequences, as lastIpcObject hands tags over.
  assert.ok(M.skipsTaskbar({ length: 1, 0: "skip-taskbar*" }))
  assert.ok(!M.skipsTaskbar(undefined))
})

test("window data is re-read after a pin and group changes, never on a title change", () => {
  for (const name of ["openwindow", "movewindowv2", "changefloatingmode", "fullscreen", "pin", "togglegroup", "moveintogroup", "moveoutofgroup"]) {
    assert.ok(M.startsRefresh(name, false), name)
  }
  assert.ok(!M.startsRefresh("activewindowv2", false, false), "a plain focus change doesn't (R2-L9)")
  assert.ok(M.startsRefresh("activewindowv2", false, true), "a group tab switch does")
  assert.ok(M.hiddenOrGrouped({ hidden: true }) && M.hiddenOrGrouped({ hidden: false, grouped: ["0x1", "0x2"] }))
  assert.ok(!M.hiddenOrGrouped({ hidden: false, grouped: [] }) && !M.hiddenOrGrouped(null))
  for (const name of ["windowtitle", "windowtitlev2", "", "constructor"]) assert.ok(!M.startsRefresh(name, false), name)
})

test("the refresh is started, never restarted, so a stream of events can't starve it", () => {
  assert.ok(!M.startsRefresh("openwindow", true))
  const service = require("fs").readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  assert.ok(service.includes("if (TasksModel.startsRefresh(name, refreshTimer.running, activeWasHidden)) refreshTimer.start()"), "Service.qml uses it")
})

test("a tray click whose lookup failed or timed out is left to the app (R1-M3)", () => {
  const same = { windows: [], focused: null, window: null }
  assert.strictEqual(T.afterClick({ failed: true }, same, { hasLauncher: true }), "app")
  assert.strictEqual(T.afterClick(same, { failed: true }, { hasLauncher: true }), "app")
  assert.strictEqual(T.afterClick(null, same, { hasLauncher: true }), "app")
  assert.strictEqual(T.afterClick(same, same, { hasLauncher: true }), "launch", "a real unchanged view still steps in")
})

test("monitor mode: every workspace on this screen", () => {
  const v = view({ mode: "monitor" })
  assert.ok(M.belongsTo(win({ workspaceId: 2, workspaceName: "2" }), v))
  assert.ok(!M.belongsTo(win({ workspaceId: 3, workspaceName: "3" }), v))
  assert.ok(M.belongsTo(minimizedFrom(2), v))
  assert.ok(!M.belongsTo(minimizedFrom(3), v))
})

test("monitor mode: minimized from a workspace that's gone shows everywhere", () => {
  assert.ok(M.belongsTo(minimizedFrom(7), view({ mode: "monitor" })))
})

test("all mode: everything but other special workspaces", () => {
  const v = view({ mode: "all" })
  assert.ok(M.belongsTo(win({ workspaceId: 9, workspaceName: "9" }), v))
  assert.ok(M.belongsTo(minimizedFrom(9), v))
  assert.ok(!M.belongsTo(win({ workspaceId: -98, workspaceName: "special:scratchpad" }), v))
})

test("hidden minimized windows stay off", () => {
  assert.ok(!M.belongsTo(minimizedFrom(1), view({ showMinimized: false })))
  assert.ok(!M.belongsTo(minimizedFrom(1), view({ mode: "all", showMinimized: false })))
})

test("a minimized window with no tag shows on every bar (R1-M2: it had no way back)", () => {
  const untagged = win({ workspaceId: -97, workspaceName: "special:minimized" })
  for (const mode of ["workspace", "monitor", "all"]) assert.ok(M.belongsTo(untagged, view({ mode })), mode)
  assert.ok(!M.belongsTo(untagged, view({ showMinimized: false })), "unless minimized windows are hidden")
})

test("a minimized dialog or hidden window still gets a button (R1-H1)", () => {
  for (const extra of [{ hasParent: true }, { hidden: true }, { mapped: false }]) {
    const minimized = Object.assign(minimizedFrom(1), extra)
    assert.ok(M.belongsTo(minimized, view({ workspaceId: 1 })), JSON.stringify(extra))
    assert.ok(!M.belongsTo(minimized, view({ workspaceId: 2 })), "only on its own workspace")
  }
  // Through describe(), the real path: a dialog (wayland.parent) on special:minimized.
  const dialog = M.describe({ address: "0x1", workspace: { id: -97, name: "special:minimized" },
    wayland: { parent: {} }, lastIpcObject: { tags: ["omarchy-minimized-from-1"], mapped: true, hidden: false } })
  assert.ok(M.belongsTo(dialog, view({ workspaceId: 1 })))
})

test("a window minimized from a screen with no bar shows on the bars there are (R1-H2)", () => {
  const away = minimizedFrom(3)
  for (const mode of ["workspace", "monitor"]) {
    assert.ok(!M.belongsTo(away, view({ mode, workspaceId: 1, monitorWorkspaces: [1, 2] })), mode + ": not without the barless list")
    assert.ok(M.belongsTo(away, view({ mode, workspaceId: 1, monitorWorkspaces: [1, 2], barlessWorkspaces: [3] })), mode)
  }
  const workspaces = [{ id: 1, monitorName: "eDP-1" }, { id: 3, monitorName: "DP-2" }, { id: 4, monitorName: "DP-2" }, { id: 5, monitorName: "" }]
  assert.deepStrictEqual(M.barlessWorkspaces(workspaces, ["eDP-1"]), [3, 4])
  assert.deepStrictEqual(M.barlessWorkspaces(workspaces, ["eDP-1", "DP-2"]), [])
  assert.deepStrictEqual(M.barlessWorkspaces(null, null), [])
})

test("describe() carries the parent, hidden and mapped state through", () => {
  const plain = { address: "abc", workspace: { id: 2, name: "2" }, lastIpcObject: { tags: [], mapped: true, hidden: false } }
  assert.strictEqual(M.describe(plain).hasParent, false)
  assert.strictEqual(M.describe(plain).address, "0xabc")
  assert.ok(M.belongsTo(M.describe(plain), view({ workspaceId: 2 })))
  const dialog = Object.assign({}, plain, { wayland: { parent: {} } })
  assert.ok(!M.belongsTo(M.describe(dialog), view({ workspaceId: 2 })), "a dialog")
  const hidden = Object.assign({}, plain, { lastIpcObject: { tags: [], mapped: true, hidden: true } })
  assert.ok(!M.belongsTo(M.describe(hidden), view({ workspaceId: 2 })), "a hidden group tab")
})

test("the minimized-from tag must be exactly omarchy-minimized-from-<id> (or a rule's <id>*)", () => {
  assert.strictEqual(M.minimizedFrom(["omarchy-minimized-from-3"]), 3)
  assert.strictEqual(M.minimizedFrom(["omarchy-minimized-from-3*"]), 3)
  assert.strictEqual(M.minimizedFrom(["omarchy-minimized-from-3x"]), null)
  assert.strictEqual(M.minimizedFrom(["xomarchy-minimized-from-3"]), null)
})

test("other special workspaces, dialogs, unmapped and hidden windows are left out", () => {
  assert.ok(!M.belongsTo(win({ workspaceId: -98, workspaceName: "special:scratchpad" }), view({ workspaceId: -98 })))
  assert.ok(!M.belongsTo(win({ hasParent: true }), view()))
  assert.ok(!M.belongsTo(win({ mapped: false }), view()))
  assert.ok(!M.belongsTo(win({ hidden: true }), view()))
  assert.ok(!M.belongsTo(win({ address: "" }), view()))
})

// ---------------------------------------------------------------- order

test("applyOrder puts known keys in order and new ones after", () => {
  assert.deepStrictEqual(M.applyOrder(["a", "b", "c", "d"], ["c", "a"]), ["c", "a", "b", "d"])
  assert.deepStrictEqual(M.applyOrder(["a", "b"], []), ["a", "b"])
})

test("reorder moves a shown key among the shown slots only", () => {
  // x lives on another workspace and keeps its slot.
  const order = ["a", "x", "b", "c"]
  assert.deepStrictEqual(R.placeWithin(order, ["a", "b", "c"], R.moved(["a", "b", "c"], 2, 0)), ["c", "x", "a", "b"])
  assert.deepStrictEqual(R.placeWithin(order, ["a", "b", "c"], R.moved(["a", "b", "c"], 0, 2)), ["b", "x", "c", "a"])
})

test("reorder adds shown keys the order didn't have", () => {
  assert.deepStrictEqual(R.placeWithin([], ["a", "b", "c"], R.moved(["a", "b", "c"], 0, 1)), ["b", "a", "c"])
})

test("pruneOrder drops closed windows", () => {
  assert.deepStrictEqual(M.pruneOrder(["a", "b", "c"], ["c", "a"]), ["a", "c"])
})

test("dropIndex follows the pointer by whole slots, inside the row", () => {
  assert.strictEqual(R.dropIndex(1, 190, 184, 4), 2)
  assert.strictEqual(R.dropIndex(1, 80, 184, 4), 1)
  assert.strictEqual(R.dropIndex(1, -999, 184, 4), 0)
  assert.strictEqual(R.dropIndex(1, 999, 184, 4), 3)
})

test("dragShift moves the buttons between the gap and the drop", () => {
  // dragging index 0 to 2: buttons 1 and 2 move left one slot
  assert.strictEqual(R.dragShift(1, 0, 2, 100), -100)
  assert.strictEqual(R.dragShift(2, 0, 2, 100), -100)
  assert.strictEqual(R.dragShift(3, 0, 2, 100), 0)
  // dragging index 3 to 1: buttons 1 and 2 move right
  assert.strictEqual(R.dragShift(1, 3, 1, 100), 100)
  assert.strictEqual(R.dragShift(0, 3, 1, 100), 0)
  assert.strictEqual(R.dragShift(2, -1, 1, 100), 0)
})

// --------------------------------------------------------------- scroll

test("scrollTarget steps and wraps", () => {
  const keys = ["a", "b", "c"]
  assert.strictEqual(M.scrollTarget(keys, "a", 1), "b")
  assert.strictEqual(M.scrollTarget(keys, "c", 1), "a")
  assert.strictEqual(M.scrollTarget(keys, "a", -1), "c")
  assert.strictEqual(M.scrollTarget(keys, "", 1), "a")
  assert.strictEqual(M.scrollTarget(keys, "", -1), "c")
  assert.strictEqual(M.scrollTarget([], "a", 1), "")
})

// ----------------------------------------------------------- geometry

test("buttons keep their preferred width when they fit", () => {
  assert.deepStrictEqual(M.buttonLayout(1000, 3, 4, 180, 90, 36, false), { width: 180, showText: true })
})

test("buttons shrink evenly when they don't fit", () => {
  // (500 - 2*4) / 3 = 164
  assert.deepStrictEqual(M.buttonLayout(500, 3, 4, 180, 90, 36, false), { width: 164, showText: true })
})

test("buttons go icon-only below the text minimum, or always when set", () => {
  assert.deepStrictEqual(M.buttonLayout(500, 8, 4, 180, 90, 36, false), { width: 36, showText: false })
  assert.deepStrictEqual(M.buttonLayout(1000, 2, 4, 180, 90, 36, true), { width: 36, showText: false })
})

test("rowX centers on the screen and stays inside the taskbar", () => {
  assert.strictEqual(M.rowX(200, 1000, 500, "center"), 400)
  assert.strictEqual(M.rowX(200, 1000, 50, "center"), 0)
  assert.strictEqual(M.rowX(200, 1000, 990, "center"), 800)
  assert.strictEqual(M.rowX(1200, 1000, 500, "center"), 0)
})

test("rowX starts at the left edge when left-aligned", () => {
  assert.strictEqual(M.rowX(200, 1000, 500, "left"), 0)
})

test("rowWidth counts the gaps between buttons", () => {
  assert.strictEqual(M.rowWidth(3, 180, 4), 548)
  assert.strictEqual(M.rowWidth(0, 180, 4), 0)
})

test("claimingEntryId finds terminal apps", () => {
  const entries = [
    { id: "nvim", command: ["nvim"], runInTerminal: true, execString: "nvim %F" },
    { id: "agent", command: ["omarchy-launch-agent"], runInTerminal: false, execString: "alacritty --app-id=org.omarchy.agent -e claude" }
  ]
  assert.strictEqual(M.claimingEntryId("org.omarchy.nvim", entries), "nvim")
  assert.strictEqual(M.claimingEntryId("org.omarchy.agent", entries), "agent")
  assert.strictEqual(M.claimingEntryId("firefox", entries), "")
})

test("moved moves one item", () => {
  assert.deepStrictEqual(R.moved(["a", "b", "c"], 0, 2), ["b", "c", "a"])
  assert.deepStrictEqual(R.moved(["a", "b", "c"], 2, 0), ["c", "a", "b"])
})

test("settings accept enabled on any entry", () => {
  const { problems } = S.parse({ id: "tray", enabled: false }, T.SETTINGS)
  assert.deepStrictEqual(problems, [])
})

test("togglePin pins by short name and unpins every matching name", () => {
  const steam = icon(3, "steam", "Steam")
  assert.deepStrictEqual(T.togglePin(steam, ["discord"]), ["discord", "steam"])
  assert.deepStrictEqual(T.togglePin(steam, ["Steam", "discord", "stea"]), ["discord"])
  assert.deepStrictEqual(T.togglePin(icon(9, "", ""), ["x"]), ["x"])
})

// trayIcons: 0 chrome, 1 superwhisper, 2 notion, 3 steam, 4 discord

test("order sets where icons sit; unknown ones follow, pinned first", () => {
  const r = T.arrange(trayIcons, traySettings({ order: ["notion", "chrome"], pinned: ["discord"] }), [])
  assert.deepStrictEqual(r.bar, [2, 0, 4, 1, 3])
})

test("order doesn't pin: unpinned icons last in the order overflow first", () => {
  // chrome is dragged to the front but not pinned; discord is pinned.
  const r = T.arrange(trayIcons, traySettings({ maxIcons: 2, order: ["chrome", "notion", "steam", "discord"], pinned: ["discord"] }), [])
  assert.deepStrictEqual(r.bar, [0, 4])
  assert.deepStrictEqual(r.overflow, [2, 3, 1])
})

test("pinned icons sit where the order puts them", () => {
  const r = T.arrange(trayIcons, traySettings({ order: ["steam", "discord", "chrome"], pinned: ["discord"] }), [])
  assert.deepStrictEqual(r.bar.slice(0, 3), [3, 4, 0])
})

test("orderAfterDrag rearranges the bar's names and keeps others' places", () => {
  const before = [trayIcons[0], trayIcons[2], trayIcons[3]]   // chrome, notion, steam
  const after = [trayIcons[3], trayIcons[0], trayIcons[2]]    // steam dragged to the front
  // spotify isn't running: its place in the order stays put.
  assert.deepStrictEqual(T.orderAfterDrag(["chrome", "spotify", "notion"], before, after, R.placeWithin),
    ["steam", "spotify", "chrome", "notion"])
  assert.deepStrictEqual(T.orderAfterDrag([], before, after, R.placeWithin), ["steam", "chrome", "notion"])
})

test("clickIsNative: replacing off, or the app listed in nativeClick", () => {
  assert.ok(!T.clickIsNative(trayIcons[3], traySettings({})))
  assert.ok(T.clickIsNative(trayIcons[3], traySettings({ replaceLeftClick: false })))
  assert.ok(T.clickIsNative(trayIcons[3], traySettings({ nativeClick: ["steam"] })))
  assert.ok(!T.clickIsNative(trayIcons[0], traySettings({ nativeClick: ["steam"] })))
})

test("afterClick: any change means the app handled it", () => {
  const before = { windows: ["0x1"], focused: null, window: "0x1" }
  assert.strictEqual(T.afterClick(before, { windows: ["0x1"], focused: "0x1", window: "0x1" }, {}), "app")
  assert.strictEqual(T.afterClick(before, { windows: [], focused: null, window: null }, {}), "app")
  assert.strictEqual(T.afterClick(before, { windows: ["0x1", "0x2"], focused: null, window: "0x2" }, {}), "app")
})

test("afterClick: no change, so step in", () => {
  const same = (extra) => Object.assign({ windows: ["0x1"], focused: null, window: "0x1", minimized: false }, extra)
  assert.strictEqual(T.afterClick(same(), same(), {}), "focus")
  assert.strictEqual(T.afterClick(same({ minimized: true }), same({ minimized: true }), {}), "restore")
  const none = { windows: [], focused: null, window: null }
  assert.strictEqual(T.afterClick(none, none, { hasLauncher: true, hasMenu: true }), "launch")
  assert.strictEqual(T.afterClick(none, none, { hasLauncher: false, hasMenu: true }), "menu")
  assert.strictEqual(T.afterClick(none, none, {}), "nothing")
})

test("afterClick ignores the order windows are listed in", () => {
  assert.strictEqual(T.afterClick({ windows: ["0x2", "0x1"], window: "0x1" }, { windows: ["0x1", "0x2"], window: "0x1" }, {}), "focus")
})

// ------------------------------------------------- dragging whole widgets

const sides = {
  left: [{ id: "omarchy.menu", x: 8, width: 27 }],
  right: [
    { id: "tray", x: 1000, width: 81 },
    { id: "omarchy.network", x: 1081, width: 27 },
    { id: "omarchy.power", x: 1108, width: 54 },
    { id: "showdesktop", x: 1162, width: 10 }
  ]
}

test("dropSpot: the bar's half picks the section", () => {
  assert.deepStrictEqual(R.dropSpot(sides, 100, 600), { section: "left", index: 1 })
  assert.deepStrictEqual(R.dropSpot(sides, 10, 600), { section: "left", index: 0 })
  assert.deepStrictEqual(R.dropSpot(sides, 700, 600), { section: "right", index: 0 })
})

test("dropSpot: lands before the first widget whose center is past it", () => {
  assert.deepStrictEqual(R.dropSpot(sides, 1050, 600), { section: "right", index: 1 })
  assert.deepStrictEqual(R.dropSpot(sides, 1100, 600), { section: "right", index: 2 })
})

test("dropSpot: never after show desktop", () => {
  assert.deepStrictEqual(R.dropSpot(sides, 1199, 600), { section: "right", index: 3 })
  assert.deepStrictEqual(R.dropSpot({ left: [], right: [] }, 900, 600), { section: "right", index: 0 })
})

test("sidePositions: a left section grows rightward, a right one leftward", () => {
  assert.deepStrictEqual(R.sidePositions([27, 54], "left", 8, -1, 0), { xs: [8, 35], gapX: null })
  assert.deepStrictEqual(R.sidePositions([27, 54], "left", 8, 1, 30), { xs: [8, 65], gapX: 35 })
  assert.deepStrictEqual(R.sidePositions([27, 10], "right", 200, -1, 0), { xs: [163, 190], gapX: null })
  assert.deepStrictEqual(R.sidePositions([27, 10], "right", 200, 1, 30), { xs: [133, 190], gapX: 160 })
  assert.deepStrictEqual(R.sidePositions([], "right", 200, 0, 30), { xs: [], gapX: 170 })
})

const layout = {
  bar: { locked: false },
  left: [{ id: "omarchy.menu" }],
  center: [{ id: "tasks", align: "center" }],
  right: [{ id: "tray", maxIcons: 5 }, { id: "omarchy.network" }, { id: "omarchy.power", showPercentage: true }, { id: "showdesktop" }]
}

test("moveEntry: within a section, keeping its settings", () => {
  const next = R.moveEntry(layout, "omarchy.power", "right", "omarchy.network")
  assert.deepStrictEqual(next.right.map((e) => e.id), ["tray", "omarchy.power", "omarchy.network", "showdesktop"])
  assert.strictEqual(next.right[1].showPercentage, true)
  assert.deepStrictEqual(next.bar, { locked: false })
  assert.strictEqual(layout.right[2].id, "omarchy.power", "the original isn't changed")
})

test("moveEntry: between sections", () => {
  const next = R.moveEntry(layout, "omarchy.network", "left", "")
  assert.deepStrictEqual(next.left.map((e) => e.id), ["omarchy.menu", "omarchy.network"])
  assert.deepStrictEqual(next.right.map((e) => e.id), ["tray", "omarchy.power", "showdesktop"])
  const first = R.moveEntry(layout, "omarchy.network", "left", "omarchy.menu")
  assert.deepStrictEqual(first.left.map((e) => e.id), ["omarchy.network", "omarchy.menu"])
})

test("moveEntry: the end of the right section is before show desktop", () => {
  const next = R.moveEntry(layout, "omarchy.menu", "right", "")
  assert.deepStrictEqual(next.right.map((e) => e.id), ["tray", "omarchy.network", "omarchy.power", "omarchy.menu", "showdesktop"])
  assert.deepStrictEqual(next.left, [])
})

test("moveEntry: no change gives null", () => {
  assert.strictEqual(R.moveEntry(layout, "omarchy.network", "right", "omarchy.power"), null)
  assert.strictEqual(R.moveEntry(layout, "omarchy.power", "right", ""), null)
  assert.strictEqual(R.moveEntry(layout, "nothing", "right", ""), null)
  assert.strictEqual(R.moveEntry(layout, "omarchy.power", "right", "omarchy.power"), null)
})

test("accept rules validate custom values", () => {
  const spec = { screens: { default: "all", hint: "all or names", accept: (v) => v === "all" ? v : Array.isArray(v) && v.length ? v : undefined } }
  assert.deepStrictEqual(S.parse({ screens: ["DP-1"] }, spec).settings.screens, ["DP-1"])
  const bad = S.parse({ screens: 3 }, spec)
  assert.strictEqual(bad.settings.screens, "all")
  assert.deepStrictEqual(bad.problems, ["screens must be all or names (got 3)"])
})

// --------------------------------------------------------------- grouping

const wins = [
  { address: "0x1", group: "google-chrome" },
  { address: "0x2", group: "foot" },
  { address: "0x3", group: "google-chrome" },
  { address: "0x4", group: "code" },
  { address: "0x5", group: "google-chrome" }
]

test("groupButtons: never keeps one button per window", () => {
  assert.deepStrictEqual(M.groupButtons(wins, "never", true).map((b) => b.key), ["0x1", "0x2", "0x3", "0x4", "0x5"])
})

test("groupButtons: always groups by app, at the app's first window", () => {
  const buttons = M.groupButtons(wins, "always", false)
  assert.deepStrictEqual(buttons.map((b) => b.key), ["group:google-chrome", "group:foot", "group:code"])
  assert.deepStrictEqual(buttons[0].addresses, ["0x1", "0x3", "0x5"])
  assert.deepStrictEqual(buttons[1].addresses, ["0x2"])
})

test("groupButtons: full groups only when crowded, lone windows stay windows", () => {
  assert.deepStrictEqual(M.groupButtons(wins, "full", false).map((b) => b.key), ["0x1", "0x2", "0x3", "0x4", "0x5"])
  assert.deepStrictEqual(M.groupButtons(wins, "full", true).map((b) => b.key), ["group:google-chrome", "0x2", "0x4"])
})

test("isCrowded: when titled buttons would turn icon-only, or icons don't fit", () => {
  assert.strictEqual(M.isCrowded(1000, 5, 4, 180, 90, 36, false), false)
  assert.strictEqual(M.isCrowded(400, 5, 4, 180, 90, 36, false), true)
  assert.strictEqual(M.isCrowded(400, 5, 4, 180, 90, 36, true), false)
  assert.strictEqual(M.isCrowded(150, 5, 4, 180, 90, 36, true), true)
  assert.strictEqual(M.isCrowded(10, 0, 4, 180, 90, 36, false), false)
})

test("orderAfterGroupDrag: a group's windows move together", () => {
  const order = ["0x1", "0x2", "0x3", "0x9", "0x4", "0x5"]
  const buttons = [["0x1", "0x3", "0x5"], ["0x2"], ["0x4"]]
  const after = M.orderAfterGroupDrag(order, buttons, [["0x2"], ["0x1", "0x3", "0x5"], ["0x4"]], R.placeWithin)
  assert.deepStrictEqual(after, ["0x2", "0x1", "0x3", "0x9", "0x5", "0x4"])
  // Regrouped, the order puts chrome after foot.
  const regrouped = M.groupButtons(M.applyOrder(["0x1", "0x2", "0x3", "0x4", "0x5"], after).map((a) => wins.find((w) => w.address === a)), "always", false)
  assert.deepStrictEqual(regrouped.map((b) => b.key), ["group:foot", "group:google-chrome", "group:code"])
})

// ----------------------------------------------------------------- titles

test("stripSymbols: Claude's spinner frames and emoji go", () => {
  assert.strictEqual(M.stripSymbols("✳ Claude Code"), "Claude Code")
  assert.strictEqual(M.stripSymbols("◐ Omarchy bar now-…"), "Omarchy bar now-…")
  assert.strictEqual(M.stripSymbols("⠋ Building"), "Building")
  assert.strictEqual(M.stripSymbols("🚀 Launch 🎉 party"), "Launch party")
  assert.strictEqual(M.stripSymbols("👩‍💻 dev"), "dev")
  assert.strictEqual(M.stripSymbols("❤️ Music"), "Music")
  assert.strictEqual(M.stripSymbols(" nvim"), "nvim")
})

test("stripSymbols: ordinary text and punctuation stay", () => {
  assert.strictEqual(M.stripSymbols("README.md — Visual Studio Code"), "README.md — Visual Studio Code")
  assert.strictEqual(M.stripSymbols("Inbox (3) - Mail · Work"), "Inbox (3) - Mail · Work")
  assert.strictEqual(M.stripSymbols("Café № 5: 50% off → today"), "Café № 5: 50% off → today")
  assert.strictEqual(M.stripSymbols("日本語のタイトル"), "日本語のタイトル")
})

test("stripSymbols: a title of only symbols stays", () => {
  assert.strictEqual(M.stripSymbols("⏳"), "⏳")
  assert.strictEqual(M.stripSymbols(""), "")
})

// ------------------------------------------------------------ quick launch

test("quick launch: apps can be names, specials, apps with args, commands", () => {
  const { settings, problems } = S.parse({ id: "quicklaunch", apps: [
    "google-chrome", "Terminal", { app: "google-chrome", args: ["--incognito"], name: "Incognito" },
    { command: "btop", name: "Activity", icon: "utilities-system-monitor" }, { name: "nothing" }, 7, " "
  ] }, Q.SETTINGS)
  assert.deepStrictEqual(settings.apps.map((a) => [a.at, a.app, a.special, a.command]), [
    [0, "google-chrome", "", ""], [1, "Terminal", "terminal", ""], [2, "google-chrome", "", ""], [3, "", "", "btop"]
  ])
  assert.deepStrictEqual(settings.apps[2].args, ["--incognito"])
  assert.strictEqual(settings.apps[3].icon, "utilities-system-monitor")
  assert.strictEqual(problems.length, 3, "the three bad elements are reported")
})

test("quick launch: a command is never a special", () => {
  assert.strictEqual(Q.normalizeItem({ app: "terminal", command: "foot" }, 0).special, "")
  assert.strictEqual(Q.normalizeItem("agent", 0).special, "agent")
})

test("quick launch: pinning matches ids loosely and doesn't duplicate", () => {
  const apps = ["Google-Chrome.desktop", { app: "code", args: ["--new-window"] }, { command: "code" }]
  assert.ok(Q.isPinned(apps, "google-chrome"))
  assert.ok(Q.isPinned(apps, "code.desktop"))
  assert.ok(!Q.isPinned(apps, "foot"))
  assert.deepStrictEqual(Q.appsAfterPin(apps, "google-chrome"), apps)
  assert.deepStrictEqual(Q.appsAfterPin(apps, "org.gnome.Nautilus.desktop").slice(-1), ["org.gnome.Nautilus"])
  assert.deepStrictEqual(Q.appsAfterUnpin(apps, "code"), ["Google-Chrome.desktop", { command: "code" }])
})

test("quick launch: remove and reorder keep skipped elements in place", () => {
  const apps = ["a", 7, "b", "c"]
  assert.deepStrictEqual(Q.appsAfterRemove(apps, 2), ["a", 7, "c"])
  assert.deepStrictEqual(Q.appsAfterRemove(apps, 9), apps)
  // Shown: a(0) b(2) c(3); dragged into c, a, b.
  assert.deepStrictEqual(Q.appsAfterReorder(apps, [0, 2, 3], [3, 0, 2]), ["c", 7, "a", "b"])
})

test("quick launch: commands drop field codes and take extra args", () => {
  assert.deepStrictEqual(Q.commandWith(["/usr/bin/chrome", "%U"], ["--incognito"]), ["/usr/bin/chrome", "--incognito"])
  assert.deepStrictEqual(Q.commandWith(null, []), [])
})

test("quick launch: agent names", () => {
  assert.strictEqual(Q.agentName("claude"), "Claude Code")
  assert.strictEqual(Q.agentName("pi"), "Pi")
  assert.strictEqual(Q.agentName(""), "Agent")
})

// ------------------------------------------- names that are also JS builtins

const builtinNames = ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]

test("builtin-named app ids group like any other", () => {
  const windows = builtinNames.flatMap((name, i) => [
    { address: "0xa" + i, group: name },
    { address: "0xb" + i, group: name }
  ])
  const buttons = M.groupButtons(windows, "always", false)
  assert.deepStrictEqual(buttons.map((b) => b.group), builtinNames)
  assert.ok(buttons.every((b) => b.addresses.length === 2))
})

test("builtin-named keys order like any other", () => {
  assert.deepStrictEqual(M.applyOrder(["constructor", "toString"], ["toString", "constructor"]), ["toString", "constructor"])
})

test("builtin names aren't quick launch specials or agent names", () => {
  for (const name of builtinNames) {
    assert.strictEqual(Q.normalizeItem(name, 0).special, "", name)
    assert.strictEqual(typeof Q.agentName(name), "string", name)
  }
})

test("builtin-named settings are reported as unknown", () => {
  const { problems } = S.parse(JSON.parse('{"id": "tasks", "constructor": 1, "toString": 2}'), M.SETTINGS)
  assert.deepStrictEqual(problems, ["unknown setting constructor", "unknown setting toString"])
})

// ------------------------------------------------------------ icon sources

const fakeIconPath = (name) => "image://icon/" + name

test("icon sources: an app id is only ever a theme icon name", () => {
  assert.strictEqual(I.themeName("org.gnome.Nautilus"), "org.gnome.Nautilus")
  assert.strictEqual(I.themeName("steam_icon_440"), "steam_icon_440")
  assert.strictEqual(I.themeName("https://example.com/x.png"), "")
  assert.strictEqual(I.themeName("/etc/passwd"), "")
  assert.strictEqual(I.themeName("../../x"), "")
  assert.strictEqual(I.themeName("a b"), "")
  assert.strictEqual(I.themeName(""), "")
})

test("icon sources: only local URLs get through", () => {
  assert.strictEqual(I.resolve("https://example.com/x.png", fakeIconPath, "/h"), "")
  assert.strictEqual(I.resolve("HTTP://example.com/x.png", fakeIconPath, "/h"), "")
  assert.strictEqual(I.resolve("ftp://example.com/x.png", fakeIconPath, "/h"), "")
  assert.strictEqual(I.resolve("data:image/png;base64,AAAA", fakeIconPath, "/h"), "")
  assert.strictEqual(I.resolve("image://icon/firefox", fakeIconPath, "/h"), "image://icon/firefox")
  assert.strictEqual(I.resolve("file:///usr/share/x.svg", fakeIconPath, "/h"), "file:///usr/share/x.svg")
  assert.strictEqual(I.resolve("qrc:/x.png", fakeIconPath, "/h"), "qrc:/x.png")
})

test("icon sources: names, paths and ~ paths resolve locally", () => {
  assert.strictEqual(I.resolve("firefox", fakeIconPath, "/h"), "image://icon/firefox")
  assert.strictEqual(I.resolve("/usr/share/icons/x.png", fakeIconPath, "/h"), "file:///usr/share/icons/x.png")
  assert.strictEqual(I.resolve("~/icons/x.png", fakeIconPath, "/home/me"), "file:///home/me/icons/x.png")
  assert.strictEqual(I.resolve("weird name!", fakeIconPath, "/h"), "")
  assert.strictEqual(I.resolve("", fakeIconPath, "/h"), "")
})

// ------------------------------------------------------- top-bar widget

test("top-bar widget: found in Omarchy's bar layout as an id or an entry", () => {
  assert.ok(W.inLayout({ right: ["omarchy.clock", W.PLUGIN_ID] }))
  assert.ok(W.inLayout({ left: [], right: [{ id: W.PLUGIN_ID }] }))
  assert.ok(W.inLayout({ tray: [{ id: W.PLUGIN_ID, extra: 1 }] }), "any section, any extra keys")
  assert.ok(!W.inLayout({ right: [{ id: "omarchy.clock" }, "io.github.cwilliams5.latch"] }))
  assert.ok(!W.inLayout({ right: [{ id: W.PLUGIN_ID + ".extra" }] }))
})

test("top-bar widget: odd layouts are read safely", () => {
  for (const layout of [null, undefined, "x", 3, {}, { right: "x" }, { right: null }, { right: [null, 7, {}] }, { constructor: [] }, { right: [{ id: { toString() { return W.PLUGIN_ID } } }] }]) {
    assert.strictEqual(W.inLayout(layout), false, JSON.stringify(layout))
  }
  // A Qt sequence (indexable, with a length, not an Array).
  assert.ok(W.inLayout({ right: { length: 1, 0: { id: W.PLUGIN_ID } } }))
})

test("taskbar hides only while the widget is on a bar (its switch is the way back)", () => {
  assert.strictEqual(W.taskbarShown(true, true), true)
  assert.strictEqual(W.taskbarShown(undefined, true), true)
  assert.strictEqual(W.taskbarShown(false, true), false)
  assert.strictEqual(W.taskbarShown(false, false), true, "no widget anywhere: never hidden")
  assert.strictEqual(W.taskbarShown(true, false), true)
})

test("top-bar widget: status line", () => {
  assert.strictEqual(W.status(false, true), "Taskbar hidden")
  assert.strictEqual(W.status(true, false), "Taskbar shown")
  assert.ok(/bottom/.test(W.status(true, true)))
})

test("top-bar widget: its choices are the settings' own values", () => {
  const values = (list) => list.map((choice) => choice.value)
  assert.deepStrictEqual(values(W.WINDOWS), M.SETTINGS.windows.choices)
  assert.deepStrictEqual(values(W.COMBINE), M.SETTINGS.combine.choices)
  const service = require("fs").readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  const iconStyles = JSON.parse(service.match(/iconStyle: \{ default: "color", choices: (\[[^\]]*\])/)[1])
  assert.deepStrictEqual(values(W.ICON_STYLES), iconStyles)
  for (const list of [W.WINDOWS, W.COMBINE, W.ICON_STYLES]) {
    for (const choice of list) assert.ok(typeof choice.label === "string" && choice.label !== "")
  }
})

test("the bar option visible exists and defaults to shown", () => {
  const service = require("fs").readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  assert.ok(/\n    visible: \{ default: true \},/.test(service))
  assert.ok(/visible: !!bar && bar\.taskbarShown/.test(require("fs").readFileSync(path.join(__dirname, "..", "BarWindow.qml"), "utf8")))
})

test("manifest: the widget is optional and the service is still its own kind", () => {
  const manifest = JSON.parse(require("fs").readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
  assert.deepStrictEqual(manifest.kinds, ["service", "bar-widget"])
  assert.strictEqual(manifest.id, W.PLUGIN_ID)
  assert.strictEqual(manifest.entryPoints.service, "Service.qml")
  assert.strictEqual(manifest.entryPoints.barWidget, "BarWidget.qml")
  assert.strictEqual(manifest.barWidget.allowMultiple, false)
  // Omarchy 4.5 shows a widget's own settings nowhere, so the icon's switch
  // is Transom's (topBarIcon), not a widget setting.
  assert.ok(!("schema" in manifest.barWidget) && !("defaults" in manifest.barWidget))
})

test("the bar option topBarIcon exists and defaults to shown (behaviour: tests/widget.test.sh)", () => {
  const service = require("fs").readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  assert.ok(/\n    topBarIcon: \{ default: true \},/.test(service))
})

test("Transom in shell.json's plugins list: ids or entries, unknown when unreadable", () => {
  assert.strictEqual(W.listedInPlugins([{ id: "x" }, { id: W.PLUGIN_ID }]), true)
  assert.strictEqual(W.listedInPlugins(["x", W.PLUGIN_ID]), true)
  assert.strictEqual(W.listedInPlugins([{ id: "x" }, null, 3]), false)
  assert.strictEqual(W.listedInPlugins([]), false)
  for (const odd of [null, undefined, "x", 3, {}]) assert.strictEqual(W.listedInPlugins(odd), null, JSON.stringify(odd))
  assert.strictEqual(W.listedInPlugins({ length: 1, 0: { id: W.PLUGIN_ID } }), true, "a Qt sequence")
})

// ------------------------------------------------------------ icon styles

const iconSettings = (extra) => Object.assign({
  iconStyle: "color", windowIconStyle: "color", iconStyleExceptions: [],
  iconStyleOn: { tray: true, quickLaunch: true, inactiveWindows: false, activeWindow: false }
}, extra)
const styles = (settings) => ["tray", "quickLaunch", "inactiveWindows", "activeWindow"].map((target) => IS.styleFor(settings, target, ["app"]))

test("icon styles: everything in color by default", () => {
  assert.deepStrictEqual(styles(iconSettings()), ["color", "color", "color", "color"])
})

test("icon styles: app icons and window icons are styled apart", () => {
  assert.deepStrictEqual(styles(iconSettings({ iconStyle: "themed" })), ["themed", "themed", "color", "color"])
  assert.deepStrictEqual(styles(iconSettings({ windowIconStyle: "themed" })), ["color", "color", "themed", "color"])
  assert.deepStrictEqual(styles(iconSettings({ iconStyle: "mono", windowIconStyle: "themed" })), ["mono", "mono", "themed", "color"])
})

test("icon styles: the focused window keeps its color unless activeWindow is on", () => {
  const on = { tray: true, quickLaunch: true, inactiveWindows: false, activeWindow: true }
  assert.deepStrictEqual(styles(iconSettings({ windowIconStyle: "mono", iconStyleOn: on })), ["color", "color", "mono", "mono"])
})

test("icon styles: tray or quick launch can stay in color alone", () => {
  const on = { tray: false, quickLaunch: true, inactiveWindows: false, activeWindow: false }
  assert.deepStrictEqual(styles(iconSettings({ iconStyle: "themed", iconStyleOn: on })), ["color", "themed", "color", "color"])
})

test("icon styles: exceptions stay in color in both sets", () => {
  const settings = iconSettings({ iconStyle: "themed", windowIconStyle: "mono", iconStyleExceptions: ["Spot"] })
  assert.strictEqual(IS.styleFor(settings, "tray", ["spotify"]), "color")
  assert.strictEqual(IS.styleFor(settings, "inactiveWindows", ["com.spotify.Client"]), "color")
  assert.strictEqual(IS.styleFor(settings, "inactiveWindows", ["firefox"]), "mono")
})

test("icon styles: 0.1.0's iconStyleOn.inactiveWindows still styles window buttons", () => {
  const legacy = (active) => iconSettings({ iconStyle: "themed", iconStyleOn: { tray: true, quickLaunch: true, inactiveWindows: true, activeWindow: active } })
  assert.deepStrictEqual(styles(legacy(false)), ["themed", "themed", "themed", "color"])
  assert.deepStrictEqual(styles(legacy(true)), ["themed", "themed", "themed", "themed"])
  assert.strictEqual(IS.windowStyle(legacy(false)), "themed", "the menus show what the buttons get")
  // activeWindow alone never styled anything a menu would show.
  assert.strictEqual(IS.styleFor(iconSettings({ iconStyle: "mono", iconStyleOn: { tray: true, quickLaunch: true, inactiveWindows: false, activeWindow: true } }), "activeWindow", []), "color")
})

test("icon styles: unknown styles and targets fall back safely", () => {
  assert.strictEqual(IS.styleFor(iconSettings({ iconStyle: "sparkly" }), "tray", []), "color")
  assert.strictEqual(IS.styleFor(iconSettings({ iconStyle: "mono" }), "", []), "mono", "no target: the app style")
  assert.strictEqual(IS.styleFor(iconSettings({ iconStyle: "mono" }), "constructor", []), "color")
})

test("icon styles: picking a window style clears the older setting", () => {
  const legacy = iconSettings({ iconStyle: "themed", iconStyleOn: { tray: true, quickLaunch: false, inactiveWindows: true, activeWindow: true } })
  const changes = IS.windowStyleChanges(legacy, "color")
  assert.ok("windowIconStyle" in changes && changes.windowIconStyle === undefined, "color removes the key")
  assert.deepStrictEqual(changes.iconStyleOn, { tray: true, quickLaunch: false, inactiveWindows: false, activeWindow: true })
  const after = iconSettings({ iconStyle: "themed", iconStyleOn: changes.iconStyleOn })
  assert.strictEqual(IS.windowStyle(after), "color")
  const plain = IS.windowStyleChanges(iconSettings(), "mono")
  assert.deepStrictEqual(Object.keys(plain), ["windowIconStyle"], "iconStyleOn is left alone when there's nothing to clear")
  assert.strictEqual(plain.windowIconStyle, "mono")
})

test("icon styles: keeping the focused window in color", () => {
  assert.strictEqual(IS.focusedColorChanges(iconSettings(), false).iconStyleOn.activeWindow, true)
  assert.strictEqual(IS.focusedColorChanges(iconSettings(), true).iconStyleOn.activeWindow, false)
  assert.strictEqual(IS.focusedColorChanges(iconSettings(), true).iconStyleOn.tray, true)
})

test("icon styles: both bar options offer the same styles as IconStyle.js", () => {
  const service = require("fs").readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  for (const option of ["iconStyle", "windowIconStyle"]) {
    const choices = JSON.parse(service.match(new RegExp("\\n    " + option + ': \\{ default: "color", choices: (\\[[^\\]]*\\])'))[1])
    assert.deepStrictEqual(choices, IS.STYLES, option)
  }
})

test("top-bar widget: theme color choices are iconTint's, and the slider fits any saved count", () => {
  const service = require("fs").readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
  const tints = JSON.parse(service.match(/iconTint: \{ default: "accent", choices: (\[[^\]]*\])/)[1])
  assert.deepStrictEqual(W.TINTS.map((choice) => choice.value), tints)
  assert.strictEqual(W.sliderMax(5), W.MAX_ICONS_SLIDER)
  assert.strictEqual(W.sliderMax(30), 30, "a larger saved value stretches the slider instead of being cut")
  assert.strictEqual(W.sliderMax("x"), W.MAX_ICONS_SLIDER)
  assert.ok(T.SETTINGS.maxIcons.max >= W.MAX_ICONS_SLIDER && T.SETTINGS.maxIcons.min === 0)
})

test("the widget counts itself from service, not the serviceReady binding (stale in onServiceChanged)", () => {
  const widget = require("fs").readFileSync(path.join(__dirname, "..", "BarWidget.qml"), "utf8")
  const body = widget.match(/function syncCount\(\) \{([\s\S]*?)\n  \}/)[1]
  assert.ok(!body.includes("serviceReady"), "syncCount must not read serviceReady")
  assert.ok(body.includes("widgetCopies += 1"))
  assert.ok(/onServiceChanged: root\.syncCount\(\)/.test(widget))
})

test("order: keys named like Object's own properties sort as unknown, not first", () => {
  assert.deepStrictEqual(M.applyOrder(["b", "constructor", "a", "toString"], ["a", "b"]), ["a", "b", "constructor", "toString"])
})

test("drag: half a slot or more moves one place, less stays", () => {
  assert.strictEqual(R.dropIndex(0, 50, 100, 5), 1)
  assert.strictEqual(R.dropIndex(0, 49, 100, 5), 0)
  assert.strictEqual(R.dropIndex(2, -60, 100, 5), 1)
})

test("icon exceptions match any case on both sides", () => {
  const settings = { iconStyle: "mono", windowIconStyle: "mono", iconStyleExceptions: ["spot"],
    iconStyleOn: { tray: true, quickLaunch: true, inactiveWindows: false, activeWindow: false } }
  assert.strictEqual(IS.styleFor(settings, "tray", ["Spotify"]), "color")
  settings.iconStyleExceptions = ["SPOT"]
  assert.strictEqual(IS.styleFor(settings, "inactiveWindows", ["com.spotify.Client"]), "color")
})

test("tray names match the tooltip title alone too", () => {
  assert.ok(T.matches({ id: "item_7", title: "", tooltipTitle: "Discord" }, "discord"))
  assert.ok(!T.matches({ id: "item_7", title: "", tooltipTitle: "Discord" }, "slack"))
})

test("quick launch: a custom command never counts as the app it names", () => {
  const apps = [{ command: "google-chrome --app=x", app: "google-chrome" }, "foot"]
  assert.ok(!Q.isPinned(apps, "google-chrome"), "unpin must not remove a command entry")
  assert.ok(Q.isPinned(apps, "foot"))
})

test("quick launch: only string args reach the command line", () => {
  assert.deepStrictEqual(Q.normalizeItem({ app: "x", args: ["--a", 3, null, { b: 1 }, "--c"] }, 0).args, ["--a", "--c"])
})

test("hosting: never Transom's own widget, on its own bar it would hide its way back (R1-H3)", () => {
  const catalogue = {
    "omarchy.network": { metadata: { displayName: "Network", firstParty: true } },
    "omarchy.tray": { metadata: { displayName: "Tray", firstParty: true } },
    "io.github.cwilliams5.transom": { metadata: { displayName: "Transom", firstParty: false } },
    "io.github.cwilliams5.locus": { metadata: { displayName: "Locus", firstParty: false } },
    "omarchy.clock": { metadata: { displayName: "Clock", firstParty: true } }
  }
  assert.strictEqual(H.OWN_ID, W.PLUGIN_ID)
  assert.ok(!H.canHost(W.PLUGIN_ID, catalogue))
  assert.ok(H.canHost("omarchy.network", catalogue))
  assert.ok(H.canHost("io.github.cwilliams5.locus", catalogue), "typed into transom.json, another plugin's widget still loads")
  for (const odd of ["constructor", "toString", "", "omarchy.nope"]) assert.ok(!H.canHost(odd, catalogue), odd)
  assert.ok(!H.canHost("omarchy.network", null))
  assert.deepStrictEqual(H.menuList(catalogue).map((widget) => widget.id), ["omarchy.clock", "omarchy.network"],
    "the menu offers Omarchy's own, sorted by name, without its tray")
  assert.deepStrictEqual(H.menuList(null), [])
  const withServices = Object.assign({}, catalogue, {
    "omarchy.media": { metadata: { displayName: "Media", firstParty: true } },
    "omarchy.indicators": { metadata: { displayName: "Indicators", firstParty: true } }
  })
  assert.deepStrictEqual(H.menuList(withServices).map((widget) => widget.id), ["omarchy.clock", "omarchy.network"],
    "Media and Indicators need Omarchy's bar services, so they aren't offered (R2-M4)")
  assert.ok(H.canHost("omarchy.indicators", withServices), "...but one already in transom.json still loads")
})

test("a file broken at start-up runs on the defaults minus closing and launching (R2-L4)", () => {
  const sections = ["left", "center", "right"]
  const defaults = { left: [], center: [{ id: "tasks", middleClick: "close" }], right: [{ id: "tray", replaceLeftClick: true }, { id: "showdesktop" }] }
  const safe = S.safeLayout(defaults, sections)
  assert.strictEqual(safe.center[0].middleClick, "nothing")
  assert.strictEqual(safe.right[0].replaceLeftClick, false)
  assert.strictEqual(defaults.center[0].middleClick, "close", "the defaults themselves are untouched")
  assert.deepStrictEqual(S.safeLayout(null, sections), {})
})

test("reading transom.json: what's kept, what's a problem (R1-H4)", () => {
  const sections = ["left", "center", "right"]
  const good = S.readLayout(JSON.stringify({ bar: { locked: true }, _note: "mine", left: [], center: [{ id: "tasks" }], right: [{ id: "tray" }] }), sections)
  assert.deepStrictEqual(good.problems, [])
  assert.strictEqual(good.layout._note, "mine", "unknown top-level keys survive, so a save keeps them")
  assert.deepStrictEqual(good.layout.right, [{ id: "tray" }])
  assert.deepStrictEqual(S.readLayout("{}", sections).layout, { left: [], center: [], right: [] }, "missing sections are empty, not problems")
  for (const text of ["{,", "", "[]", "null", "3"]) {
    const read = S.readLayout(text, sections)
    assert.strictEqual(read.layout, null, text)
    assert.strictEqual(read.problems.length, 1, text)
  }
  const odd = S.readLayout(JSON.stringify({ bar: [], left: {}, right: [{ id: "tray" }, { x: 1 }, null, { id: "" }] }), sections)
  assert.deepStrictEqual(odd.problems, ['"bar" must be an object', '"left" must be a list', '"right" has 3 entries without an "id"'])
  assert.deepStrictEqual(odd.layout.right, [{ id: "tray" }], "what could be read is still shown")
  const proto = S.readLayout('{"__proto__": {"x": 1}, "right": []}', sections)
  assert.strictEqual(Object.getPrototypeOf(proto.layout), Object.prototype, "a __proto__ key can't change the layout's prototype")
})

test("a screen with no bar: its windows show on the bars there are, even after its workspace is dropped (R2-L5)", () => {
  // Minimized from workspace 3, which Hyprland has since dropped: remembered as barless.
  assert.ok(M.belongsTo(minimizedFrom(3), view({ workspaceId: 1, knownWorkspaces: [1], barlessWorkspaces: [3] })))
  // Open windows on the bar-less screen's workspace.
  const there = win({ workspaceId: 4, workspaceName: "4" })
  assert.ok(M.belongsTo(there, view({ workspaceId: 1, barlessActive: [4] })), "workspace mode: the workspace it shows")
  assert.ok(!M.belongsTo(there, view({ workspaceId: 1, barlessActive: [5] })), "...not its other workspaces")
  assert.ok(M.belongsTo(there, view({ mode: "monitor", monitorWorkspaces: [1], barlessWorkspaces: [4, 5] })), "monitor mode: all of them")
  assert.ok(!M.belongsTo(there, view({ workspaceId: 1 })), "every screen with a bar: unchanged")
})

test("maximized means Hyprland's fullscreen mode 1 only (rule 10)", () => {
  assert.ok(M.isMaximizedIpc({ fullscreen: 1 }))
  assert.ok(!M.isMaximizedIpc({ fullscreen: 2 }), "real fullscreen isn't")
  assert.ok(!M.isMaximizedIpc({ fullscreen: 0 }) && !M.isMaximizedIpc(null))
})

test("show desktop brings back only its own windows: still minimized, from here (R1-L1)", () => {
  assert.ok(M.restorable(minimizedFrom(1), 1))
  assert.ok(!M.restorable(minimizedFrom(3), 1), "an address reused by a window minimized elsewhere")
  assert.ok(!M.restorable(win({ workspaceId: 1, workspaceName: "1", tags: ["omarchy-minimized-from-1"] }), 1), "not minimized any more")
  assert.ok(!M.restorable(null, 1))
})

test("a click on the active window minimizes it, Windows-style, unless the pointer just focused it on its way down", () => {
  assert.strictEqual(M.SETTINGS.activeClick.default, "minimize")
  const t = 100000
  assert.ok(M.activeClickMinimizes("minimize", t - 5000, t), "active long before the pointer reached the bar")
  assert.ok(!M.activeClickMinimizes("minimize", t - 300, t), "focused 0.3 s before reaching the bar (focus follows mouse)")
  assert.ok(M.activeClickMinimizes("minimize", t - M.APPROACH_MS, t), "exactly the approach time: minimizes")
  assert.ok(M.activeClickMinimizes("minimize", t + 2000, t), "became active after reaching the bar (a key, a new window)")
  assert.ok(M.activeClickMinimizes("minimize", 0, 0), "nothing known: minimizes")
  assert.ok(!M.activeClickMinimizes("nothing", t - 5000, t), "activeClick: nothing")
})

if (failures) {
  console.log("\n" + failures + " failed")
  process.exit(1)
}
console.log("\nall passed")
