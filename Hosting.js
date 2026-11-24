// Which of Omarchy's bar widgets the bottom bar can host (tests/run.js).
//
// widgets is the catalogue Omarchy hands a service (barWidgetRegistry
// .widgets): id -> { component, metadata }, metadata.firstParty true for
// Omarchy's own.

var OWN_ID = "io.github.cwilliams5.transom"

// Omarchy widgets that read Omarchy's own services (firstPartyServiceFor),
// which Omarchy gives only to plugins of kind "bar": on Transom's bar media
// never appears and most indicators never light (strict review R2-M4). Not
// offered in the menu; typed into transom.json they still load.
var NEEDS_BAR_SERVICES = ["omarchy.media", "omarchy.indicators"]

// Whether an id in transom.json may be loaded as a hosted widget. Never
// Transom's own: on its own bar it would hide with the taskbar it's the
// way back to (strict review R1-H3).
function canHost(id, widgets) {
  var key = String(id || "")
  if (key === OWN_ID || !widgets) return false
  return Object.prototype.hasOwnProperty.call(widgets, key) && !!widgets[key]
}

// What the bar menu's "Omarchy widgets" page offers, as [{ id, name }]
// sorted by name: Omarchy's own widgets only. Another plugin's widget gets
// no service of its own on a bar that isn't Omarchy's (R1-H3), and
// Omarchy's tray is replaced here by Transom's.
function menuList(widgets) {
  var out = []
  if (!widgets) return out
  for (var id in widgets) {
    if (!Object.prototype.hasOwnProperty.call(widgets, id) || id === "omarchy.tray" || !canHost(id, widgets)) continue
    if (NEEDS_BAR_SERVICES.indexOf(id) >= 0) continue
    var meta = (widgets[id] && widgets[id].metadata) || {}
    if (meta.firstParty !== true) continue
    out.push({ id: id, name: String(meta.displayName || id) })
  }
  out.sort(function(a, b) { return a.name.localeCompare(b.name) })
  return out
}

if (typeof module !== "undefined") {
  module.exports = { OWN_ID: OWN_ID, NEEDS_BAR_SERVICES: NEEDS_BAR_SERVICES, canHost: canHost, menuList: menuList }
}
