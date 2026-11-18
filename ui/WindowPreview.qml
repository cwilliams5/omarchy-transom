import QtQuick
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// A live picture of one window, for the taskbar's thumbnails, through
// Quickshell's ScreencopyView. It fits in maxWidth x maxHeight, keeping the
// window's shape. A window that gives no picture (some minimized ones)
// shows "No preview" instead.
Item {
  id: preview

  // A Hyprland toplevel (Quickshell.Hyprland); its Wayland side is captured.
  property var toplevel: null
  // Keep updating while shown; off, it holds the last frame.
  property bool live: true
  property real maxWidth: Style.space(220)
  property real maxHeight: Style.space(140)

  readonly property bool hasContent: view.hasContent
  readonly property real sourceWidth: view.sourceSize.width
  readonly property real sourceHeight: view.sourceSize.height
  readonly property real fit: sourceWidth > 0 && sourceHeight > 0
    ? Math.min(maxWidth / sourceWidth, maxHeight / sourceHeight) : 1

  implicitWidth: hasContent ? Math.round(sourceWidth * fit) : maxWidth
  implicitHeight: hasContent ? Math.round(sourceHeight * fit) : Math.round(maxHeight * 0.5)

  ScreencopyView {
    id: view
    anchors.fill: parent
    captureSource: preview.toplevel && preview.toplevel.wayland ? preview.toplevel.wayland : null
    live: preview.live
    paintCursor: false
  }

  Text {
    visible: !view.hasContent
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: "No preview"
    color: Commons.Color.tooltip.text
    opacity: 0.6
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
