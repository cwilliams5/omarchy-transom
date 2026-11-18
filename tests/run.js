// Tests for TasksModel.js. Run: node tests/run.js
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "..", "TasksModel.js"))
const S = require(path.join(__dirname, "..", "Settings.js"))
const T = require(path.join(__dirname, "..", "TrayModel.js"))
const R = require(path.join(__dirname, "..", "Reorder.js"))

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

test("a minimized window with no tag belongs nowhere", () => {
  assert.ok(!M.belongsTo(win({ workspaceId: -97, workspaceName: "special:minimized" }), view({ mode: "all" })))
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

if (failures) {
  console.log("\n" + failures + " failed")
  process.exit(1)
}
console.log("\nall passed")
