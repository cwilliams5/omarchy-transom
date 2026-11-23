// Which style each app icon on the bar gets (tests in tests/run.js). Styles:
// "color" (as it is), "mono" (grays), "themed" (shades of a theme color).
//
// Two sets, each with its own bar option:
//   app icons     the tray and quick launch: iconStyle
//   window icons  the taskbar buttons: windowIconStyle
// The focused window's button keeps its color unless iconStyleOn.activeWindow
// is on, so it stands out among restyled ones. iconStyleOn.tray and
// .quickLaunch keep those in color alone. Names in iconStyleExceptions stay
// in color everywhere.
//
// Before windowIconStyle (Transom 0.1.0), window buttons took iconStyle
// where iconStyleOn.inactiveWindows / .activeWindow said so. That still
// works while windowIconStyle is "color" (windowStyle, styleFor).

var STYLES = ["color", "mono", "themed"]
var WINDOW_TARGETS = ["inactiveWindows", "activeWindow"]

function isWindow(target) {
  return WINDOW_TARGETS.indexOf(target) >= 0
}

// The style window buttons get, as the menus show it.
function windowStyle(settings) {
  var own = settings.windowIconStyle
  if (own && own !== "color") return own
  var on = settings.iconStyleOn || {}
  return on.inactiveWindows === true ? (settings.iconStyle || "color") : "color"
}

// The style for one icon. target: "tray", "quickLaunch", "inactiveWindows"
// or "activeWindow". names: the app's ids and names, for the exceptions.
function styleFor(settings, target, names) {
  var on = settings.iconStyleOn || {}
  var style
  if (isWindow(target)) {
    // windowStyle covers the older settings too; the focused window's
    // button joins in only with iconStyleOn.activeWindow.
    style = windowStyle(settings)
    if (target === "activeWindow" && on.activeWindow !== true) style = "color"
  } else {
    style = target && on[target] !== true ? "color" : settings.iconStyle
  }
  if (STYLES.indexOf(style) < 0 || style === "color") return "color"
  var exceptions = settings.iconStyleExceptions || []
  var list = names || []
  for (var i = 0; i < exceptions.length; i++) {
    var wanted = String(exceptions[i]).toLowerCase()
    for (var j = 0; j < list.length; j++) {
      if (String(list[j] || "").toLowerCase().indexOf(wanted) >= 0) return "color"
    }
  }
  return style
}

// The changes to save (for updateWidget("bar", ...)) to give window buttons
// the style next. Clears the older iconStyleOn.inactiveWindows, which would
// otherwise keep them styled after "color" is picked.
function windowStyleChanges(settings, next) {
  var changes = { windowIconStyle: next === "color" ? undefined : next }
  var on = settings.iconStyleOn || {}
  if (on.inactiveWindows === true) {
    var copy = {}
    for (var key in on) if (Object.prototype.hasOwnProperty.call(on, key)) copy[key] = on[key]
    copy.inactiveWindows = false
    changes.iconStyleOn = copy
  }
  return changes
}

// The changes that keep the focused window's button in color, or not.
function focusedColorChanges(settings, keepColor) {
  var on = settings.iconStyleOn || {}
  var copy = {}
  for (var key in on) if (Object.prototype.hasOwnProperty.call(on, key)) copy[key] = on[key]
  copy.activeWindow = !keepColor
  return { iconStyleOn: copy }
}

if (typeof module !== "undefined") {
  module.exports = {
    STYLES: STYLES,
    windowStyle: windowStyle,
    styleFor: styleFor,
    windowStyleChanges: windowStyleChanges,
    focusedColorChanges: focusedColorChanges
  }
}
