.pragma library
// Which windows are hidden from screen capture, remembered once asked
// (ui/WindowPreview.qml), so a thumbnail shown again knows at once. Keyed by
// address and app id: Hyprland reuses addresses, and its no_screen_share
// rules go by app.

var known = {}

function lookup(key) {
  return key && Object.prototype.hasOwnProperty.call(known, key) ? known[key] : undefined
}

function remember(key, hidden) {
  if (key) known[key] = hidden
}
