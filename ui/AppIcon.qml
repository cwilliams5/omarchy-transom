import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons as Commons

// An app's icon on the bar (taskbar buttons, tray, quick launch).
//
// sources lists candidates, best first (a theme icon name, a path, a
// file:// or image:// URL); the first one that loads is shown, so a missing
// icon falls back to the next instead of a blank.
//
// iconStyle (the bar options iconStyle and iconStyleOn decide it per icon):
//   "color"   as it is
//   "mono"    in grays
//   "themed"  in shades of tint (the theme's accent, or its bar text color:
//             the bar option iconTint), so it changes with the theme
// Symbolic icons ("-symbolic", made to be recolored) are always filled with
// tint, as Omarchy's own tray does.
//
// Mono and themed go through shaders/tint.frag: each pixel's brightness
// becomes a shade of one color, lifted so dark icons (Steam's) stay visible.
Item {
  id: icon

  property var sources: []
  property string iconStyle: "color"
  property color tint: "white"

  // The candidates as loadable URLs, each once (several names often
  // resolve to the same file).
  readonly property var candidates: {
    var out = []
    var list = icon.sources || []
    for (var i = 0; i < list.length; i++) {
      var resolved = icon.resolve(list[i])
      if (resolved && out.indexOf(resolved) < 0) out.push(resolved)
    }
    return out
  }

  // Which candidate is showing; moves on when one fails to load.
  property int tried: 0
  onCandidatesChanged: tried = 0

  readonly property url current: icon.tried < icon.candidates.length ? icon.candidates[icon.tried] : ""
  readonly property bool symbolic: String(current).split("?")[0].slice(-9) === "-symbolic"
  readonly property bool restyled: !symbolic && (iconStyle === "mono" || iconStyle === "themed")

  // Shades go toward light on a dark bar, toward dark on a light one.
  readonly property color barColor: Commons.Color.bar.background
  readonly property bool darkBar: 0.2126 * barColor.r + 0.7152 * barColor.g + 0.0722 * barColor.b < 0.5

  // A theme icon name, a path or a URL, as something Image can load.
  function resolve(name) {
    var value = String(name || "")
    if (!value) return ""
    if (value.indexOf("://") > 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    if (value.indexOf("~/") === 0) return "file://" + Quickshell.env("HOME") + value.slice(1)
    return Quickshell.iconPath(value, true) || ""
  }

  Image {
    id: image
    anchors.fill: parent
    source: icon.current
    sourceSize: Qt.size(icon.width * 2, icon.height * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    visible: !icon.symbolic && !icon.restyled
    layer.enabled: icon.symbolic
    // Failed: on to the next candidate.
    onStatusChanged: if (status === Image.Error && icon.tried + 1 < icon.candidates.length) icon.tried++
  }

  // Symbolic: the icon's shape filled with tint.
  Rectangle {
    anchors.fill: image
    visible: icon.symbolic
    color: icon.tint
    layer.enabled: icon.symbolic
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: image
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
  }

  // Mono and themed: the same picture, drawn through the tint shader.
  Image {
    anchors.fill: parent
    visible: icon.restyled
    source: icon.restyled ? icon.current : ""
    sourceSize: Qt.size(icon.width * 2, icon.height * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    layer.enabled: icon.restyled
    layer.effect: ShaderEffect {
      // Mono: grays (white or black shades). Themed: shades of tint.
      property color tint: icon.iconStyle === "themed" ? icon.tint : "white"
      property real low: icon.iconStyle === "themed" ? (icon.darkBar ? 0.6 : 0.45) : (icon.darkBar ? 0.42 : 0.05)
      property real high: icon.iconStyle === "themed" ? (icon.darkBar ? 1.2 : 0.95) : (icon.darkBar ? 1.0 : 0.5)
      fragmentShader: Qt.resolvedUrl("../shaders/tint.frag.qsb")
    }
  }
}
