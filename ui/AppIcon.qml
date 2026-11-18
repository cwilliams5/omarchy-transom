import QtQuick
import Quickshell

// An app's icon on the bar. sources lists candidates, best first (a theme
// icon name, a path, a file:// or image:// URL); the first one that loads is
// shown, so a missing icon falls back to the next instead of a blank.
Item {
  id: icon

  property var sources: []
  // Which candidate is showing; moves on when one fails to load.
  property int tried: 0
  onSourcesChanged: tried = 0

  readonly property url current: {
    var list = icon.sources || []
    for (var i = icon.tried; i < list.length; i++) {
      var resolved = icon.resolve(list[i])
      if (resolved) return resolved
    }
    return ""
  }

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
    onStatusChanged: {
      if (status !== Image.Error) return
      // Skip to the candidate after the one that failed.
      var list = icon.sources || []
      for (var i = icon.tried; i < list.length; i++) {
        if (icon.resolve(list[i]) === String(icon.current)) {
          if (i + 1 < list.length) icon.tried = i + 1
          return
        }
      }
    }
  }
}
