import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// A live picture of one window, for the taskbar's thumbnails, through
// Quickshell's ScreencopyView. It fits in maxWidth x maxHeight, keeping the
// window's shape.
//
// Some windows refuse to be captured: Omarchy marks password managers
// (Bitwarden, 1Password) no_screen_share, and Hyprland then hands any
// capture an empty picture. Those are never captured; they show their app's
// icon and "Hidden from screen capture" instead. So does a window that gives
// no picture for another reason ("No preview").
Item {
  id: preview

  // A Hyprland toplevel (Quickshell.Hyprland); its Wayland side is captured.
  property var toplevel: null
  // The app's icon candidates, for the placeholder (ui/AppIcon.qml).
  property var iconSources: []
  // Keep updating while shown; off, it holds the last frame.
  property bool live: true
  property real maxWidth: Style.space(220)
  property real maxHeight: Style.space(140)

  // Hidden from capture by its window rules (Hyprland's no_screen_share).
  property bool protectedWindow: false
  // Checked before capturing anything.
  property bool checked: false

  readonly property string address: {
    var value = toplevel ? String(toplevel.address || "") : ""
    return !value ? "" : value.indexOf("0x") === 0 ? value : "0x" + value
  }

  onAddressChanged: {
    preview.protectedWindow = false
    preview.checked = false
    if (!preview.address) return
    privacy.command = ["hyprctl", "getprop", "address:" + preview.address, "no_screen_share"]
    privacy.running = true
  }

  Process {
    id: privacy
    stdout: StdioCollector {
      onStreamFinished: {
        preview.protectedWindow = text.trim() === "true"
        preview.checked = true
      }
    }
    // hyprctl failing (an old Hyprland without the property): capture as usual.
    onExited: function(code) { if (code !== 0) preview.checked = true }
  }

  readonly property bool capturing: checked && !protectedWindow
  readonly property bool hasContent: capturing && view.hasContent
  readonly property real sourceWidth: view.sourceSize.width
  readonly property real sourceHeight: view.sourceSize.height
  readonly property real fit: sourceWidth > 0 && sourceHeight > 0
    ? Math.min(maxWidth / sourceWidth, maxHeight / sourceHeight) : 1

  implicitWidth: hasContent ? Math.round(sourceWidth * fit) : maxWidth
  implicitHeight: hasContent ? Math.round(sourceHeight * fit) : Math.round(maxHeight * 0.6)

  ScreencopyView {
    id: view
    anchors.fill: parent
    visible: preview.capturing
    captureSource: preview.capturing && preview.toplevel && preview.toplevel.wayland ? preview.toplevel.wayland : null
    live: preview.live
    paintCursor: false
  }

  // No picture: the app's icon and why.
  Column {
    visible: !preview.hasContent
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
