// The tray's logic that doesn't need Quickshell, so node can test it
// (tests/run.js): its settings spec, matching tray icons to names, and which
// icons sit on the bar versus in the overflow.
//
// A tray icon here is { key, id, title, tooltipTitle }: what an app
// publishes over the StatusNotifierItem protocol (Linux's notification area),
// plus a key the widget uses to find the real item again.

// Every tray setting, for Settings.parse. The README explains each one.
var SETTINGS = {
  overflow: { default: true },                   // extra icons go in a "^" flyout
  maxIcons: { default: 6, min: 0, max: 50 },     // icons on the bar before the overflow
  pinned: { default: [] },                       // names never put in the overflow
  order: { default: [] },                        // names in the order they sit (set by dragging)
  reorder: { default: true },                    // drag icons on the bar to reorder them
  hidden: { default: [] },                       // names never shown
  tooltip: { default: true },                    // the app's name on hover
  tooltipDelay: { default: 600, min: 0, max: 5000 },
  iconSize: { default: 16, min: 8, max: 32 },   // px; Omarchy's widgets and tray use 12
  replaceLeftClick: { default: true },           // step in when an app ignores a left click
  replaceLeftClickWaitMs: { default: 300, min: 0, max: 5000 }, // how long the app gets first
  nativeClick: { default: [] },                  // names whose left click is only ever the app's
  restoreTo: { default: "origin", choices: ["origin", "current"] } // a minimized window comes back where it was, or here
}

function text(value) {
  return String(value || "").toLowerCase()
}

// Whether a name from pinned/hidden matches an icon: case-insensitive, any
// part of its id, title or tooltip title. Apps name their icons loosely
// (Chrome's is chrome_status_icon_1, and the number can change between
// launches), so "chrome" is the reliable way to say it. Omarchy's tray
// matches the same way.
function matches(icon, name) {
  var wanted = text(name).trim()
  if (!icon || !wanted) return false
  return text(icon.id).indexOf(wanted) >= 0
    || text(icon.title).indexOf(wanted) >= 0
    || text(icon.tooltipTitle).indexOf(wanted) >= 0
}

// A short name to use in pinned/hidden for an icon: its id without
// Electron/Chrome's "_status_icon_<n>" or a trailing number, else its title.
function nameFor(icon) {
  var id = text(icon && icon.id).replace(/[_-]?status[_-]?icon([_-]?\d+)?$/, "").replace(/[_-]\d+$/, "")
  return id || text(icon && (icon.title || icon.tooltipTitle))
}

// Apps whose tray icon an Omarchy bar widget already stands in for: with the
// widget on either bar, the icon would show the same thing twice. LocalSend's
// icon is always left out; its menu is the whole app. (Same list as Omarchy's
// own tray, shell/plugins/bar/widgets/TrayModel.js.)
var WIDGETS_FOR_ICONS = [
  { widget: "omarchy.dropbox", icon: "dropbox" },
  { widget: "superwhisper.panel", icon: "superwhisper" }
]

// Whether any section of any of the layouts lists the widget id.
function layoutsHave(layouts, id) {
  for (var l = 0; l < (layouts || []).length; l++) {
    var layout = layouts[l]
    if (!layout || typeof layout !== "object") continue
    for (var section in layout) {
      var entries = layout[section]
      if (!entries || typeof entries === "string" || typeof entries.length !== "number") continue
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        var entryId = typeof entry === "string" ? entry : (entry && entry.id)
        if (entryId === id) return true
      }
    }
  }
  return false
}

function standsInFor(icon, layouts) {
  if (matches(icon, "localsend")) return true
  for (var i = 0; i < WIDGETS_FOR_ICONS.length; i++) {
    var pair = WIDGETS_FOR_ICONS[i]
    if (matches(icon, pair.icon) && layoutsHave(layouts, pair.widget)) return true
  }
  return false
}

// Whether any name in the list matches the icon.
function listed(icon, names) {
  return (names || []).some(function(name) { return matches(icon, name) })
}

// The index of the first name in the list that matches the icon, or -1.
function rankIn(icon, names) {
  var list = names || []
  for (var i = 0; i < list.length; i++) if (matches(icon, list[i])) return i
  return -1
}

// Icons in the order they sit: those in settings.order by their place
// there; then, for icons the order doesn't know yet, pinned ones (in pinned
// order) and finally the rest in the order apps registered them. So new
// apps join at the end until dragged somewhere.
function sorted(icons, settings) {
  var keyed = (icons || []).map(function(icon, arrival) {
    var rank = rankIn(icon, settings.order)
    var pin = rankIn(icon, settings.pinned)
    return { icon: icon, sort: rank >= 0 ? [0, rank] : pin >= 0 ? [1, pin] : [2, arrival] }
  })
  keyed.sort(function(a, b) { return a.sort[0] - b.sort[0] || a.sort[1] - b.sort[1] })
  return keyed.map(function(entry) { return entry.icon })
}

// Splits icons (in the order apps registered them) into those on the bar and
// those in the overflow, each in the order they sit (sorted). Pinned icons
// always sit on the bar, even past maxIcons. Unpinned ones fill what's left
// of maxIcons in order; the rest go in the overflow, so the unpinned icons
// last in the order are the first to overflow. With overflow off, every
// icon is on the bar. Hidden icons, and those a bar widget stands in for,
// are left out. layouts are the top bar's and this bar's, for standsInFor.
// Returns { bar: [keys], overflow: [keys], left_out: [keys] }.
function arrange(icons, settings, layouts) {
  var leftOut = []
  var visible = []
  for (var i = 0; i < (icons || []).length; i++) {
    var icon = icons[i]
    if (listed(icon, settings.hidden) || standsInFor(icon, layouts)) leftOut.push(icon.key)
    else visible.push(icon)
  }
  var inOrder = sorted(visible, settings)
  if (!settings.overflow) return { bar: inOrder.map(function(icon) { return icon.key }), overflow: [], left_out: leftOut }
  var pinnedCount = visible.filter(function(icon) { return listed(icon, settings.pinned) }).length
  var room = Math.max(0, settings.maxIcons - pinnedCount)
  var bar = []
  var overflow = []
  for (var j = 0; j < inOrder.length; j++) {
    if (listed(inOrder[j], settings.pinned)) bar.push(inOrder[j].key)
    else if (room > 0) { bar.push(inOrder[j].key); room-- }
    else overflow.push(inOrder[j].key)
  }
  return { bar: bar, overflow: overflow, left_out: leftOut }
}

// The pinned list after the user pins or unpins an icon from its menu.
function togglePin(icon, pinned) {
  var list = pinned || []
  if (listed(icon, list)) return list.filter(function(name) { return !matches(icon, name) })
  var name = nameFor(icon)
  return name ? list.concat([name]) : list
}

// The order list after icons on the bar are dragged into a new order.
// barBefore and barAfter are the bar's icons before and after the drag. Only
// the order changes; pinning is separate. Uses Reorder.placeWithin's rule:
// names the order already has for apps not on the bar keep their places.
function orderAfterDrag(order, barBefore, barAfter, placeWithin) {
  var before = uniqueNames(barBefore)
  var after = uniqueNames(barAfter)
  if (before.length !== after.length) return (order || []).slice()
  return placeWithin(order || [], before, after)
}

function uniqueNames(icons) {
  var names = []
  for (var i = 0; i < (icons || []).length; i++) {
    var name = nameFor(icons[i])
    if (name && names.indexOf(name) < 0) names.push(name)
  }
  return names
}

// ------------------------------------------------------------ left click

// Whether a left click goes only to the app: the replacing is off, or the
// app is in nativeClick.
function clickIsNative(icon, settings) {
  return !settings.replaceLeftClick || listed(icon, settings.nativeClick)
}

// What to do after the app had its chance at a left click. before and after
// are ./tray-window's view of the app (its windows, the focused one) taken
// just before the click and replaceLeftClickWaitMs after it. If anything
// changed, the app handled the click. If nothing did, step in, Windows-style:
// bring its window forward, else start it, else open its menu.
// Returns "app", "focus", "restore", "launch", "menu" or "nothing".
function afterClick(before, after, options) {
  if (snapshot(before) !== snapshot(after)) return "app"
  var now = after || {}
  if (now.window) return now.minimized ? "restore" : "focus"
  if (options && options.hasLauncher) return "launch"
  if (options && options.hasMenu) return "menu"
  return "nothing"
}

function snapshot(view) {
  var v = view || {}
  return JSON.stringify({ windows: (v.windows || []).slice().sort(), focused: v.focused || null })
}

if (typeof module !== "undefined") {
  module.exports = {
    SETTINGS: SETTINGS,
    matches: matches,
    listed: listed,
    sorted: sorted,
    togglePin: togglePin,
    orderAfterDrag: orderAfterDrag,
    clickIsNative: clickIsNative,
    afterClick: afterClick,
    nameFor: nameFor,
    layoutsHave: layoutsHave,
    standsInFor: standsInFor,
    arrange: arrange
  }
}
