// The top-bar widget's logic that doesn't need Quickshell, so node can test
// it (tests/run.js): when the taskbar may be hidden, and the choices the
// widget's dropdown (BarWidget.qml) offers.

var PLUGIN_ID = "io.github.cwilliams5.transom"

// Whether Transom's widget sits in a bar layout: Omarchy's bar.layout from
// shell.json, sections of widget ids or { id, ... } entries. Its icon may
// be switched off (showIcon); it still counts, since the widget's settings
// in Omarchy's bar are where that switch comes back on.
function inLayout(layout) {
  if (!layout || typeof layout !== "object") return false
  for (var section in layout) {
    if (!Object.prototype.hasOwnProperty.call(layout, section)) continue
    var entries = layout[section]
    if (!entries || typeof entries === "string" || typeof entries.length !== "number") continue
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var id = typeof entry === "string" ? entry : (entry && typeof entry === "object" ? entry.id : "")
      if (id === PLUGIN_ID) return true
    }
  }
  return false
}

// Whether the taskbar is drawn. The bar option `visible` hides it, but only
// while there's a way back: the widget on a bar with its icon showing (its
// "Show the taskbar" switch). Take the widget off the bar, or hide its
// icon, and a hidden taskbar comes back by itself.
function taskbarShown(visibleSetting, wayBack) {
  return visibleSetting !== false || !wayBack
}

// Whether shell.json's plugins list (entries are ids or { id }) names
// Transom: true or false, or null when the list can't be read.
function listedInPlugins(plugins) {
  if (!plugins || typeof plugins === "string" || typeof plugins.length !== "number") return null
  for (var i = 0; i < plugins.length; i++) {
    var entry = plugins[i]
    var id = typeof entry === "string" ? entry : (entry && typeof entry === "object" ? entry.id : "")
    if (id === PLUGIN_ID) return true
  }
  return false
}

// One line on the taskbar's state, for the dropdown's header and the
// icon's tooltip.
function status(shown, autohide) {
  if (!shown) return "Taskbar hidden"
  return autohide ? "Taskbar hides until the pointer reaches the bottom" : "Taskbar shown"
}

// The dropdown's choices. Values are the settings' own (TasksModel.SETTINGS
// windows and combine; the bar option iconStyle); labels use the bar
// menu's words.
var WINDOWS = [
  { value: "workspace", label: "This workspace" },
  { value: "monitor", label: "This screen" },
  { value: "all", label: "All" }
]
var COMBINE = [
  { value: "never", label: "Never" },
  { value: "full", label: "When full" },
  { value: "always", label: "Always" }
]
var ICON_STYLES = [
  { value: "color", label: "Color" },
  { value: "mono", label: "Gray" },
  { value: "themed", label: "Theme color" }
]
// The bar option iconTint: which theme color "themed" uses.
var TINTS = [
  { value: "accent", label: "Accent" },
  { value: "text", label: "Text" }
]

// The tray slider's range (the tray setting maxIcons allows 0-50; the
// slider stretches to a larger saved value rather than clamping it).
var MAX_ICONS_SLIDER = 12
function sliderMax(maxIcons) {
  return Math.max(MAX_ICONS_SLIDER, Math.round(Number(maxIcons) || 0))
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    inLayout: inLayout,
    taskbarShown: taskbarShown,
    listedInPlugins: listedInPlugins,
    status: status,
    WINDOWS: WINDOWS,
    COMBINE: COMBINE,
    ICON_STYLES: ICON_STYLES,
    TINTS: TINTS,
    MAX_ICONS_SLIDER: MAX_ICONS_SLIDER,
    sliderMax: sliderMax
  }
}
