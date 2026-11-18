// Which icon references may reach a Qt Image (tests in tests/run.js).
//
// Apps control some of the strings that end up as icon sources: a window's
// app id, a tray menu entry's icon. Qt's Image loads whatever URL it is
// given, network included, so an app could otherwise make the shell fetch
// a URL of its choosing (reported by a marketplace reviewer). Two rules:
//
//   themeName(value)  a string an app controls is only ever a theme icon
//                     name: letters, digits and . _ + - (no URL, no path)
//   resolve(value)    any icon reference becomes a local URL or nothing:
//                     image:// (Quickshell's icon providers), file:// (a
//                     path) or qrc:. http, https and every other scheme
//                     are refused.

function themeName(value) {
  var text = String(value || "").trim()
  return /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(text) ? text : ""
}

function isLocalUrl(url) {
  return /^(image|file):\/\//i.test(String(url || "")) || /^qrc:/i.test(String(url || ""))
}

// value: a theme icon name, an absolute path, a ~/ path, or a URL.
// iconPath(name): the theme's URL for an icon name ("" if none).
// home: the home folder, for ~/ paths.
function resolve(value, iconPath, home) {
  var text = String(value || "").trim()
  if (!text) return ""
  if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(text)) return isLocalUrl(text) ? text : ""
  if (text.charAt(0) === "/") return "file://" + text
  if (text.indexOf("~/") === 0) return home ? "file://" + home + text.slice(1) : ""
  var name = themeName(text)
  return name && iconPath ? String(iconPath(name) || "") : ""
}

if (typeof module !== "undefined") {
  module.exports = { themeName: themeName, isLocalUrl: isLocalUrl, resolve: resolve }
}
