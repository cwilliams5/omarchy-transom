import QtQuick
import QtQuick.Effects
import Quickshell

// An app's icon on the bar (taskbar buttons, tray, quick launch).
//
// sources lists candidates, best first (a theme icon name, a path, a
// file:// or image:// URL); the first one that loads is shown, so a missing
// icon falls back to the next instead of a blank.
//
// iconStyle is the bar option of the same name: "color" shows the icon as
// it is, "mono" in grays, "themed" in shades of tint (the bar's text color),
// so it follows the theme. Symbolic icons ("-symbolic", made to be
// recolored) are always painted in tint, as Omarchy's own tray does.
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

  // Mono and themed: the colors taken out and every shade squeezed into the
  // brighter part of the range on a dark bar (the darker part on a light
  // one), so a dark icon (Steam's) stays visible and a busy one keeps its
  // detail. Themed then tints it with the bar's text color.
  MultiEffect {
    anchors.fill: image
    source: image
    visible: icon.restyled
    saturation: -1
    contrast: -0.45
    brightness: icon.lightTint ? 0.225 : -0.225
    colorization: icon.iconStyle === "themed" ? 1 : 0
    colorizationColor: icon.tint
  }

  // A light text color means a dark bar, and the other way round.
  readonly property bool lightTint: 0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b > 0.5
}
