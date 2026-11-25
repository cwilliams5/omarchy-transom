// The taskbar's logic that doesn't need Quickshell, so node can test it
// (tests/run.js): its settings spec, which windows a taskbar shows, their
// order, button sizes, and where the row of buttons sits.

// ------------------------------------------------------------- settings

// Every taskbar setting, for Settings.parse. transom.json overrides them on
// the taskbar's entry, e.g. { "id": "tasks", "align": "left" }. The README
// explains each one.
var SETTINGS = {
  align: { default: "center", choices: ["center", "left"] },              // on the screen, or left
  labels: { default: "title", choices: ["title", "icon"] },               // icon + title, or icon only
  buttonWidth: { default: 180, min: 40, max: 600 },                       // px, before shrinking to fit
  minTextWidth: { default: 90, min: 0, max: 600 },                        // narrower than this: icon-only
  windows: { default: "workspace", choices: ["workspace", "monitor", "all"] },
  minimized: { default: "dimmed", choices: ["dimmed", "normal", "hidden"] },
  activeClick: { default: "minimize", choices: ["nothing", "minimize"] },  // clicking the active window (Windows minimizes it)
  middleClick: { default: "close", choices: ["close", "nothing"] },
  tooltip: { default: true },                                              // full title when cut off
  tooltipDelay: { default: 600, min: 0, max: 5000 },                      // ms of hovering first
  scroll: { default: true },                                               // scroll steps through windows
  reorder: { default: true },                                              // drag to reorder
  urgentTint: { default: true },                                           // steady tint for attention
  workspaces: { default: 5, min: 1, max: 10 },                            // in the menu's "Move to"
  titleSymbols: { default: "keep", choices: ["keep", "strip"] },          // strip: drop emoji and symbols from titles
  combine: { default: "never", choices: ["never", "full", "always"] },    // one button per app: never, when full, always
  thumbnails: { default: false }                                           // hover shows a live picture of the window
}

// ------------------------------------------------------- which windows

// Minimizing moves a window to this special workspace. Omarchy's minimize
// command and ours (./minimize) both tag the window with the workspace it
// left, as omarchy-minimized-from-<id>.
var MINIMIZED_WORKSPACE = "special:minimized"
var FROM_TAG = /^omarchy-minimized-from-(-?\d+)\*?$/
// Hyprland events after which window data (tags, floating, fullscreen,
// hidden) is re-read. Title changes are left out on purpose: an animated
// title (a coding agent's spinner) changes several times a second.
var REFRESH_EVENTS = ["openwindow", "movewindowv2", "changefloatingmode", "fullscreen", "pin",
  "togglegroup", "moveintogroup", "moveoutofgroup", "activewindowv2"]

// Whether an event starts the refresh timer: one of REFRESH_EVENTS, and only
// when it isn't already running. Started, never restarted, so a steady
// stream of events can't keep pushing the refresh back. activewindowv2
// fires on every focus change (often, with focus following the pointer), so
// it counts only when the window now active was hidden or grouped in the
// last snapshot: a group tab switch (strict review R2-L9).
function startsRefresh(name, timerRunning, activeWasHidden) {
  var event = String(name || "")
  if (timerRunning || REFRESH_EVENTS.indexOf(event) < 0) return false
  return event !== "activewindowv2" || activeWasHidden === true
}

// Whether a window's last snapshot (lastIpcObject) shows it hidden or in a
// group, for startsRefresh.
function hiddenOrGrouped(ipc) {
  if (!ipc) return false
  var grouped = toList(ipc.grouped) || []
  return ipc.hidden === true || grouped.length > 0
}

// A window that asks to be left off taskbars. Hyprland has no such
// convention of its own: Legato tags its video window with it, and a rule
// of your own can tag anything (`tag = "+skip-taskbar"`). A tag a window
// rule set reads back with a trailing "*".
var SKIP_TAG = /^skip-taskbar\*?$/

// A list from Hyprland IPC data as a plain array. Quickshell can hand nested
// lists over as Qt sequence types, which Array.isArray rejects but which
// still have length and indexes.
function toList(value) {
  if (!value || typeof value === "string") return []
  if (Array.isArray(value)) return value
  var out = []
  var count = Number(value.length) || 0
  for (var i = 0; i < count; i++) out.push(value[i])
  return out
}

// The workspace a minimized window was minimized from, or null.
function minimizedFrom(tags) {
  var list = toList(tags)
  for (var i = 0; i < list.length; i++) {
    var match = FROM_TAG.exec(String(list[i]))
    if (match) return Number(match[1])
  }
  return null
}

// The workspaces on screens that have no bar: workspaces is [{ id,
// monitorName }], barScreenNames the screens that have one.
function barlessWorkspaces(workspaces, barScreenNames) {
  var names = toList(barScreenNames) || []
  var out = []
  var list = toList(workspaces) || []
  for (var i = 0; i < list.length; i++) {
    var monitor = list[i] && list[i].monitorName
    if (monitor && names.indexOf(String(monitor)) < 0) out.push(list[i].id)
  }
  return out
}

// Whether a window's tags ask taskbars to leave it out.
function skipsTaskbar(tags) {
  var list = toList(tags)
  for (var i = 0; i < list.length; i++) {
    if (SKIP_TAG.test(String(list[i]))) return true
  }
  return false
}

// Whether a click on the active window's button minimizes it (activeClick
// "minimize", as on Windows). Not when the window became active less than
// APPROACH_MS before the pointer reached the bar: with focus following the
// mouse (Omarchy's tiled workspaces), the pointer passing over a window on
// its way down focuses it, and that click was meant to bring it forward.
// It holds back one click only: spentFor is the activeSince of a click it
// already held back, and the next click on that window minimizes (without
// it, every click stayed held back until the pointer left the bar).
// activeSince, barEnteredAt and spentFor are times in ms; 0 when unknown.
var APPROACH_MS = 1000
function activeClickMinimizes(setting, activeSince, barEnteredAt, spentFor) {
  if (setting !== "minimize") return false
  if (activeSince > 0 && activeSince === spentFor) return true
  var gap = barEnteredAt - activeSince
  return !(activeSince > 0 && barEnteredAt > 0 && gap >= 0 && gap < APPROACH_MS)
}

// One Lua chunk for `hyprctl repl`: the steps (Hyprland dispatcher
// expressions) run in order inside Hyprland, each on its own, so one that
// fails stops neither the rest nor the clean-up. keepPointer: Hyprland's
// pointer moves are off for exactly these steps (cursor.no_warps on,
// cursor.warp_on_change_workspace 0, then the user's values back), the way
// Latch does it. Hyprland runs the chunk start to finish, so nothing else
// can focus a window while they're off: the user's setting never visibly
// changes (verified in a nested Hyprland, 2026-11-24). Saving and setting
// are guarded too: should Hyprland rename or drop one of those options, the
// steps still run (the pointer just moves) and nothing is left switched
// off; unguarded, a missing option stopped every action, or left
// warp_on_change_workspace at 0 for the session (tried in a nested
// Hyprland, 2026-11-24).
var POINTER_SAVE = "local ok, w, c = pcall(function() return hl.get_config(\"cursor.no_warps\"), hl.get_config(\"cursor.warp_on_change_workspace\") end)"
  + "; local saved = ok and w ~= nil and c ~= nil"
  + "; if saved then pcall(function() hl.config({ cursor = { no_warps = true, warp_on_change_workspace = 0 } }) end) end"
var POINTER_RESTORE = "if saved then pcall(function() hl.config({ cursor = { no_warps = w, warp_on_change_workspace = c } }) end) end"
function dispatchChunk(steps, keepPointer) {
  var body = (steps || []).map(function(step) { return "pcall(function() hl.dispatch(" + step + ") end)" })
  if (!keepPointer) return body.join("; ")
  return [POINTER_SAVE].concat(body, [POINTER_RESTORE]).join("; ")
}

// Whether a window's last snapshot shows it maximized: Hyprland's
// fullscreen mode 1 (2 is real fullscreen). Only those need the stacking
// workaround (CLAUDE.md rule 10).
function isMaximizedIpc(ipc) {
  return !!ipc && Number(ipc.fullscreen) === 1
}

// Whether show desktop may bring a window back to workspaceId: still
// minimized, and minimized from there. Hyprland reuses a closed window's
// address (strict review R1-L1).
function restorable(window, workspaceId) {
  return !!window && String(window.workspaceName || "") === MINIMIZED_WORKSPACE && minimizedFrom(window.tags) === workspaceId
}

// Hyprland's IPC writes addresses as 0x…; Quickshell sometimes drops the 0x.
function normalizeAddress(address) {
  var value = String(address || "")
  if (!value) return ""
  return value.indexOf("0x") === 0 ? value : "0x" + value
}

// A plain-object view of a Quickshell HyprlandToplevel, the shape belongsTo
// takes. Quickshell keeps workspace current on its own; lastIpcObject (tags,
// mapped, hidden) is as of the last Hyprland.refreshToplevels().
function describe(toplevel) {
  var ipc = (toplevel && toplevel.lastIpcObject) || {}
  var workspace = toplevel ? toplevel.workspace : null
  var ipcWorkspace = ipc.workspace || {}
  return {
    address: normalizeAddress(toplevel ? toplevel.address : ""),
    workspaceId: workspace ? workspace.id : (ipcWorkspace.id !== undefined ? ipcWorkspace.id : -1),
    workspaceName: workspace ? String(workspace.name || "") : String(ipcWorkspace.name || ""),
    tags: toList(ipc.tags),
    hasParent: !!(toplevel && toplevel.wayland && toplevel.wayland.parent),
    mapped: ipc.mapped,
    hidden: ipc.hidden
  }
}

// Whether a window gets a button on a taskbar. window is describe()'s shape.
// view is the taskbar's point of view:
//   mode               "workspace" | "monitor" | "all" (the windows setting)
//   workspaceId        the workspace the taskbar's screen is showing
//   monitorWorkspaces  ids of the workspaces on the taskbar's screen
//   knownWorkspaces    ids of every workspace that exists right now
//   barlessWorkspaces  ids of the workspaces on screens with no Transom bar
//                      (bar option screens), as last seen (Hyprland drops
//                      empty ones): their windows have no taskbar of their own
//   barlessActive      ids of the workspaces those screens are showing
//   showMinimized      false when minimized windows are hidden
//
// workspace: windows on the shown workspace, plus those minimized from it.
// monitor:   windows on any workspace of this screen, plus those minimized
//            from one. A window minimized from a workspace that no longer
//            exists (Hyprland drops empty ones) shows on every screen.
// all:       every window, plus every minimized one.
//
// A minimized window always has a button somewhere, because the taskbar is
// the only way back to it (as in Omarchy's dock): dialogs, hidden windows
// and skip-taskbar ones included. One minimized from a screen with no bar,
// or with no minimized-from tag (another tool's minimize, or a tag that
// failed), shows on every bar.
// Otherwise dialogs (windows with a parent), unmapped and hidden windows
// never show, nor does anything on other special workspaces (scratchpad,
// agent console), nor a window tagged skip-taskbar (a picture-in-picture
// video, say).
function belongsTo(window, view) {
  if (!window || !window.address) return false
  var mode = view.mode || "workspace"
  var onMonitor = view.monitorWorkspaces || []
  var name = String(window.workspaceName || "")
  if (name === MINIMIZED_WORKSPACE) {
    if (view.showMinimized === false) return false
    var from = minimizedFrom(window.tags)
    if (mode === "all" || from === null) return true
    if ((view.barlessWorkspaces || []).indexOf(from) >= 0) return true
    if (mode === "monitor") return onMonitor.indexOf(from) >= 0 || (view.knownWorkspaces || []).indexOf(from) < 0
    return from === view.workspaceId
  }
  if (window.hasParent) return false
  if (window.mapped === false || window.hidden === true) return false
  if (name.indexOf("special:") === 0) return false
  if (skipsTaskbar(window.tags)) return false
  if (mode === "all") return true
  // A screen with no bar: its windows show on the bars there are, as on
  // Windows with the taskbar on the main display only (strict review R2-L5).
  if (mode === "monitor") return onMonitor.indexOf(window.workspaceId) >= 0 || (view.barlessWorkspaces || []).indexOf(window.workspaceId) >= 0
  return window.workspaceId === view.workspaceId || (view.barlessActive || []).indexOf(window.workspaceId) >= 0
}

// ---------------------------------------------------------------- order

// keys sorted by the user's order (from dragging). Keys the order doesn't
// have yet keep their own order, after the ones it does.
function applyOrder(keys, order) {
  // No prototype: keys come from windows (Object.create(null), not {}).
  var rank = Object.create(null)
  for (var i = 0; i < (order || []).length; i++) rank[order[i]] = i
  var known = []
  var unknown = []
  for (var j = 0; j < (keys || []).length; j++) {
    if (rank[keys[j]] !== undefined) known.push(keys[j])
    else unknown.push(keys[j])
  }
  known.sort(function(a, b) { return rank[a] - rank[b] })
  return known.concat(unknown)
}

// The order without windows that no longer exist.
function pruneOrder(order, existing) {
  return (order || []).filter(function(key) { return existing.indexOf(key) >= 0 })
}

// --------------------------------------------------------------- scroll

// The window a scroll step lands on. keys are the windows to step through,
// active is the active one's key (or ""), step is +1 (next) or -1. Wraps
// around. With no active window it starts from the near end.
function scrollTarget(keys, active, step) {
  var count = (keys || []).length
  if (count === 0) return ""
  var index = keys.indexOf(active)
  if (index < 0) return step > 0 ? keys[0] : keys[count - 1]
  return keys[(index + step + count) % count]
}

// ----------------------------------------------------------- geometry

// Button size for count buttons in the available width. Each button is
// preferred wide and shrinks evenly when they don't all fit. Below
// minWithText it drops its title and becomes an icon-only button, as it
// always is when iconOnly is set. Returns { width, showText }.
function buttonLayout(available, count, spacing, preferred, minWithText, iconWidth, iconOnly) {
  if (iconOnly) return { width: iconWidth, showText: false }
  if (count <= 0) return { width: preferred, showText: true }
  var share = (Math.max(0, available) - spacing * (count - 1)) / count
  var width = Math.min(preferred, Math.floor(share))
  if (width >= minWithText) return { width: width, showText: true }
  return { width: iconWidth, showText: false }
}

// Total width of a row of count buttons.
function rowWidth(count, buttonWidth, spacing) {
  return count <= 0 ? 0 : count * buttonWidth + (count - 1) * spacing
}

// Where the row starts inside the taskbar: at its left edge, or centered on
// the screen (centerX is the screen's center in the taskbar's coordinates)
// without spilling out of the taskbar.
function rowX(rowWidth, available, centerX, align) {
  if (align === "left") return 0
  var x = Math.round(centerX - rowWidth / 2)
  return Math.max(0, Math.min(Math.max(0, available - rowWidth), x))
}

// ------------------------------------------------------------- app ids

// A terminal app's window carries the app id its launcher gave the terminal,
// which no desktop entry names as its class. The entry that passes that app id
// claims it, and so does a terminal entry for the command Omarchy's TUI
// launcher named it after (org.omarchy.nvim for nvim). Copied from Omarchy's
// dock (shell/plugins/dock/DockModel.js), which can't be imported from here.
// Entries are { id, execString, command, runInTerminal }.
function claimingEntryId(appId, entries) {
  var id = String(appId || "")
  if (!id) return ""
  var list = entries || []
  var flag = "--app-id=" + id
  for (var i = 0; i < list.length; i++) {
    var words = String(list[i].execString || "").split(/\s+/)
    if (words.indexOf(flag) >= 0) return list[i].id
  }
  if (id.indexOf("org.omarchy.") !== 0) return ""
  var command = id.slice("org.omarchy.".length)
  for (var j = 0; j < list.length; j++) {
    var program = String((list[j].command || [])[0] || "")
    if (list[j].runInTerminal && program.slice(program.lastIndexOf("/") + 1) === command) return list[j].id
  }
  return ""
}

// ----------------------------------------------------------- grouping

// Whether the windows' own buttons would be squeezed: below their minimum
// with a title they'd turn icon-only (or, icon-only already, they wouldn't
// fit). That's when combine: "full" groups them, like Windows' "combine
// when the taskbar is full".
function isCrowded(available, count, spacing, preferred, minWithText, iconWidth, iconOnly) {
  if (count <= 0) return false
  if (iconOnly) return rowWidth(count, iconWidth, spacing) > Math.max(0, available)
  return !buttonLayout(available, count, spacing, preferred, minWithText, iconWidth, false).showText
}

// The taskbar's buttons for its windows. windows are { address, group } in
// taskbar order, group being the app (its desktop entry id). Returns
// [{ key, group, addresses }] in order: one per window, or with combining
// one per app, placed where the app's first window is. Buttons keep a
// stable key: the window's address for a lone window, "group:<app>" for an
// app's button when combining always (so a second window joining it doesn't
// rebuild it).
function groupButtons(windows, combine, crowded) {
  var list = windows || []
  var single = function(window) { return { key: window.address, group: window.group || window.address, addresses: [window.address] } }
  if (combine !== "always" && !(combine === "full" && crowded)) return list.map(single)
  var out = []
  // No prototype: a group key can be an app id the window chose, and a
  // plain object would already "have" groups like constructor or toString.
  var byGroup = Object.create(null)
  for (var i = 0; i < list.length; i++) {
    var group = list[i].group || list[i].address
    if (byGroup[group]) {
      byGroup[group].addresses.push(list[i].address)
    } else {
      byGroup[group] = { key: "group:" + group, group: group, addresses: [list[i].address] }
      out.push(byGroup[group])
    }
  }
  if (combine === "full") {
    out = out.map(function(button) { return button.addresses.length === 1 ? single({ address: button.addresses[0], group: button.group }) : button })
  }
  return out
}

// The window order after buttons were dragged into a new order: each
// button's windows move together. buttons and newButtons are lists of
// address lists.
function orderAfterGroupDrag(order, buttons, newButtons, placeWithin) {
  var shown = [].concat.apply([], buttons)
  var shownNew = [].concat.apply([], newButtons)
  return placeWithin(order, shown, shownNew)
}

// ------------------------------------------------------------- titles

// Symbols apps put in window titles: emoji and pictographs, dingbats (✳),
// shapes (● ◐), block and Braille spinner frames (▁ ⠋), stars and weather
// (★ ☀), Nerd Font icons (private use), and the joiners and selectors that
// glue emoji together. Letters, digits and ordinary punctuation stay.
var SYMBOLS = new RegExp("[" +
  "\u2300-\u23FF" +            // misc technical (⌛ ⏳ ⏸)
  "\u2580-\u25FF" +            // blocks, geometric shapes
  "\u2600-\u27BF" +            // misc symbols, dingbats
  "\u2800-\u28FF" +            // Braille (spinners)
  "\u2B00-\u2BFF" +            // misc symbols and arrows (⭐ ⬤)
  "\uE000-\uF8FF" +            // private use (Nerd Font icons)
  "\uFE00-\uFE0F\u200D\u20E3" + // variation selectors, joiner, keycap
  "]|[\uD83C-\uD83E][\uDC00-\uDFFF]" + // emoji and pictographs (U+1F000-U+1FBFF)
  "|\uDB80[\uDC00-\uDFFF]|[\uDB81-\uDBFF][\uDC00-\uDFFF]", "g") // supplementary private use

// A window title without symbols: "✳ Claude Code" is "Claude Code". Spaces
// left doubled are collapsed. A title that's nothing but symbols stays as it is.
function stripSymbols(title) {
  var text = String(title || "")
  var out = text.replace(SYMBOLS, " ").replace(/\s+/g, " ").trim()
  return out || text
}

if (typeof module !== "undefined") {
  module.exports = {
    SETTINGS: SETTINGS,
    stripSymbols: stripSymbols,
    isCrowded: isCrowded,
    groupButtons: groupButtons,
    orderAfterGroupDrag: orderAfterGroupDrag,
    MINIMIZED_WORKSPACE: MINIMIZED_WORKSPACE,
    toList: toList,
    describe: describe,
    minimizedFrom: minimizedFrom,
    normalizeAddress: normalizeAddress,
    belongsTo: belongsTo,
    REFRESH_EVENTS: REFRESH_EVENTS,
    startsRefresh: startsRefresh,
    hiddenOrGrouped: hiddenOrGrouped,
    isMaximizedIpc: isMaximizedIpc,
    dispatchChunk: dispatchChunk,
    APPROACH_MS: APPROACH_MS,
    activeClickMinimizes: activeClickMinimizes,
    restorable: restorable,
    barlessWorkspaces: barlessWorkspaces,
    skipsTaskbar: skipsTaskbar,
    applyOrder: applyOrder,
    pruneOrder: pruneOrder,
    scrollTarget: scrollTarget,
    buttonLayout: buttonLayout,
    rowWidth: rowWidth,
    rowX: rowX,
    claimingEntryId: claimingEntryId
  }
}
