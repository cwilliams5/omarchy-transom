// Quick launch: app buttons on the bar, Windows-style. A click always opens
// a new window. Pure logic for widgets/QuickLaunch.qml and the taskbar
// buttons' "Pin to quick launch"; tests in tests/run.js.

// Names that stand for Omarchy's own launchers rather than an app.
var SPECIALS = {
  terminal: { name: "Terminal", command: ["omarchy-launch-terminal"] },
  agent: { name: "Agent", command: ["omarchy-agent", "--pick"] },
  browser: { name: "Browser", command: ["omarchy-launch-browser"] }
}

function trimmed(value) {
  return typeof value === "string" ? value.trim() : ""
}

// The same list as Settings.toList, kept here so this file stands alone.
function toList(value) {
  if (!value || typeof value === "string") return null
  if (Array.isArray(value)) return value
  if (typeof value.length !== "number") return null
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

// One element of the apps setting, made uniform:
//   "google-chrome"                    an app, by desktop entry id or name
//   "terminal" | "agent" | "browser"   Omarchy's launchers (SPECIALS)
//   { "app": "google-chrome", "args": ["--incognito"], "name": "...", "icon": "..." }
//   { "command": "btop", "name": "Activity", "icon": "utilities-system-monitor" }
// Returns { at, app, special, args, command, name, icon }, at being its
// index in the setting, or null when it's neither an app nor a command.
function normalizeItem(value, index) {
  var item = { at: index, app: "", special: "", args: [], command: "", name: "", icon: "" }
  if (typeof value === "string") {
    item.app = value.trim()
  } else if (value && typeof value === "object" && !Array.isArray(value)) {
    item.app = trimmed(value.app)
    item.command = trimmed(value.command)
    item.name = trimmed(value.name)
    item.icon = trimmed(value.icon)
    var args = toList(value.args) || []
    item.args = args.filter(function(arg) { return typeof arg === "string" })
  } else {
    return null
  }
  if (!item.app && !item.command) return null
  var lower = item.app.toLowerCase()
  if (!item.command && Object.prototype.hasOwnProperty.call(SPECIALS, lower)) item.special = lower
  return item
}

// Every quick launch setting, for Settings.parse. The README explains each.
var SETTINGS = {
  apps: { default: [], item: normalizeItem },       // the buttons, in order
  iconSize: { default: 16, min: 8, max: 32 },       // px, like the tray's
  tooltip: { default: true },                       // the app's name on hover
  tooltipDelay: { default: 600, min: 0, max: 5000 },
  reorder: { default: true }                        // drag to reorder
}

// A desktop entry id as written anywhere: case and ".desktop" don't matter.
function appKey(id) {
  return String(id || "").trim().toLowerCase().replace(/\.desktop$/, "")
}

// Whether an element of the apps setting launches the app with this id.
function launches(value, id) {
  var key = appKey(id)
  if (!key) return false
  if (typeof value === "string") return appKey(value) === key
  return !!value && typeof value === "object" && !trimmed(value.command) && appKey(value.app) === key
}

function isPinned(apps, id) {
  var list = toList(apps) || []
  for (var i = 0; i < list.length; i++) if (launches(list[i], id)) return true
  return false
}

// The apps setting with the app added at the end (unless it's there).
function appsAfterPin(apps, id) {
  var list = (toList(apps) || []).slice()
  if (!appKey(id) || isPinned(list, id)) return list
  // As written, minus ".desktop": desktop entry ids are case-sensitive.
  list.push(String(id).trim().replace(/\.desktop$/i, ""))
  return list
}

// The apps setting without any element that launches the app.
function appsAfterUnpin(apps, id) {
  return (toList(apps) || []).filter(function(value) { return !launches(value, id) })
}

// The apps setting without the element at index at.
function appsAfterRemove(apps, at) {
  var list = (toList(apps) || []).slice()
  if (at >= 0 && at < list.length) list.splice(at, 1)
  return list
}

// The apps setting after the shown buttons were dragged into a new order.
// shownAt: the shown buttons' indexes in the setting, in their old order;
// newAt: the same indexes in the new order. Elements that aren't shown
// (ones the bar skipped as invalid) keep their places.
function appsAfterReorder(apps, shownAt, newAt) {
  var list = toList(apps) || []
  var out = list.slice()
  var slots = shownAt.slice().sort(function(a, b) { return a - b })
  for (var i = 0; i < slots.length; i++) out[slots[i]] = list[newAt[i]]
  return out
}

// A desktop entry's command line without its field codes (%U, %f...), with
// extra arguments after it.
function commandWith(command, args) {
  var words = (toList(command) || []).filter(function(word) { return !/^%[a-zA-Z]$/.test(String(word)) })
  return words.concat(toList(args) || [])
}

// The agent's name for the tooltip: Omarchy's default agent id, as a name.
function agentName(id) {
  var names = { claude: "Claude Code", codex: "Codex", opencode: "OpenCode", copilot: "GitHub Copilot", "cursor-agent": "Cursor CLI", agy: "Antigravity" }
  var key = String(id || "").trim()
  if (!key) return "Agent"
  if (Object.prototype.hasOwnProperty.call(names, key)) return names[key]
  return key.charAt(0).toUpperCase() + key.slice(1)
}

if (typeof module !== "undefined") {
  module.exports = {
    SPECIALS: SPECIALS, SETTINGS: SETTINGS, normalizeItem: normalizeItem, appKey: appKey, launches: launches,
    isPinned: isPinned, appsAfterPin: appsAfterPin, appsAfterUnpin: appsAfterUnpin, appsAfterRemove: appsAfterRemove,
    appsAfterReorder: appsAfterReorder, commandWith: commandWith, agentName: agentName
  }
}
