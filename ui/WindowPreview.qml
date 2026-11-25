import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "../CaptureCache.js" as CaptureCache

// A live picture of one window, for the taskbar's thumbnails, through
// Quickshell's ScreencopyView. It fits in maxWidth x maxHeight, keeping the
// window's shape.
//
// Some windows refuse to be captured: Omarchy marks password managers
// (Bitwarden, 1Password) no_screen_share, and Hyprland then hands any
// capture an empty picture. Those are never captured; they show their app's
// icon and "Hidden from screen capture" instead. A window that gives no
// picture for another reason says "No preview", but only after a second:
// a placeholder never flashes up while a picture is on its way.
//
// Set toplevel early (while the pointer is still on the way) with live
// off: the protection check and the first frame are then done by the time
// it's shown, so it appears at once at its real size.
Item {
  id: preview

  // A Hyprland toplevel (Quickshell.Hyprland); its Wayland side is captured.
  property var toplevel: null
  // The app's icon candidates, for the placeholder (ui/AppIcon.qml).
  property var iconSources: []
  // Keep updating; off, it captures one frame and holds it.
  property bool live: true
  property real maxWidth: Style.space(220)
  property real maxHeight: Style.space(140)
  // Always take the full maxWidth x maxHeight, the picture centered in it,
  // so nothing moves when the first frame lands (the thumbnail strip, which
  // opens on a click with no time to get ready).
  property bool fixedSize: false

  // Hidden from capture by its window rules (Hyprland's no_screen_share).
  property bool protectedWindow: false
  // Known whether it's protected (nothing is captured before).
  property bool checked: false
  // Captured for a while and still no picture.
  property bool gaveUp: false
  // The check gave no answer (hyprctl failed, or the window had gone): no
  // capture then, "No preview" instead (strict review R1-L5: it captured).
  property bool unknown: false

  readonly property string address: {
    var value = toplevel ? String(toplevel.address || "") : ""
    return !value ? "" : value.indexOf("0x") === 0 ? value : "0x" + value
  }
  readonly property string appId: toplevel && toplevel.wayland ? String(toplevel.wayland.appId || "") : ""
  readonly property string cacheKey: address ? address + "|" + appId : ""

  onCacheKeyChanged: {
    preview.gaveUp = false
    preview.unknown = false
    var known = CaptureCache.lookup(preview.cacheKey)
    preview.protectedWindow = known === true
    preview.checked = known !== undefined
    preview.ask()
  }

  // Asks Hyprland whether the window is hidden from capture. While a check
  // is busy (until its answer is read) it tries again shortly: a Process
  // can't be restarted while it runs, and `asked` only changes between
  // checks, so an answer is always filed under the window it was for.
  function ask() {
    if (!preview.address || preview.checked) return
    if (privacy.busy && Date.now() - privacy.startedAt < 2000) {
      askAgain.restart()
      return
    }
    if (privacy.busy) {
      // A check that never reported back (one that couldn't start sends no
      // exit): no answer, so nothing is captured (CLAUDE.md rule 5).
      privacy.running = false
      privacy.busy = false
      preview.unknown = true
      preview.checked = true
      return
    }
    privacy.busy = true
    privacy.startedAt = Date.now()
    privacy.asked = preview.cacheKey
    // Under a deadline: a Hyprland that doesn't answer mustn't leave it running.
    privacy.command = ["timeout", "1", "hyprctl", "getprop", "address:" + preview.address, "no_screen_share"]
    privacy.running = true
  }

  Timer {
    id: askAgain
    interval: 50
    onTriggered: preview.ask()
  }

  Process {
    id: privacy
    property string asked: ""
    property bool busy: false
    property double startedAt: 0
    stdout: StdioCollector {
      onStreamFinished: {
        // Only "true" or "false" is an answer; anything else ("window not
        // found", an error) isn't, and isn't remembered.
        var answer = text.trim()
        var known = answer === "true" || answer === "false"
        if (known) CaptureCache.remember(privacy.asked, answer === "true")
        privacy.busy = false
        if (privacy.asked !== preview.cacheKey) return
        preview.protectedWindow = answer === "true"
        preview.unknown = !known
        preview.checked = true
      }
    }
    onExited: function(code) {
      if (code !== 0 && privacy.asked === preview.cacheKey) {
        preview.unknown = true
        preview.checked = true
      }
      // The answer is normally read first; if it never comes, free the check.
      Qt.callLater(function() { privacy.busy = false })
    }
  }

  readonly property bool capturing: checked && !protectedWindow && !unknown
  readonly property bool hasContent: capturing && view.hasContent
  readonly property real sourceWidth: view.sourceSize.width
  readonly property real sourceHeight: view.sourceSize.height
  readonly property real fit: sourceWidth > 0 && sourceHeight > 0
    ? Math.min(maxWidth / sourceWidth, maxHeight / sourceHeight) : 1

  readonly property real pictureWidth: Math.round(sourceWidth * fit)
  readonly property real pictureHeight: Math.round(sourceHeight * fit)

  implicitWidth: fixedSize ? maxWidth : hasContent ? pictureWidth : maxWidth
  implicitHeight: fixedSize ? maxHeight : hasContent ? pictureHeight : Math.round(maxHeight * 0.6)

  // No picture a second after capturing started: say so.
  Timer {
    interval: 1000
    running: preview.capturing && !view.hasContent
    onTriggered: preview.gaveUp = true
  }

  ScreencopyView {
    id: view
    anchors.centerIn: parent
    width: preview.hasContent ? preview.pictureWidth : parent.width
    height: preview.hasContent ? preview.pictureHeight : parent.height
    visible: preview.hasContent
    captureSource: preview.capturing && preview.toplevel && preview.toplevel.wayland ? preview.toplevel.wayland : null
    live: preview.live
    paintCursor: false
  }

  // No picture, for a known reason: the app's icon and why.
  Column {
    visible: preview.protectedWindow || preview.unknown || (preview.gaveUp && !preview.hasContent)
    anchors.centerIn: parent
    spacing: Style.space(8)

    AppIcon {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: preview.iconSources.length > 0
      width: Style.space(32)
      height: Style.space(32)
      sources: preview.iconSources
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: preview.protectedWindow ? "Hidden from screen capture" : "No preview"
      color: Commons.Color.tooltip.text
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
