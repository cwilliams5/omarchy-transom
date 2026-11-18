import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The taskbar's hover thumbnail (tasks setting thumbnails): after `delay`
// ms of hovering a window's button, its title and a live picture of the
// window, in the tooltip's style. Same calls as TooltipPopup: hovered(item,
// inside) and hide(). The hovered item gives previewToplevel and tipText.
AnchoredPopup {
  id: thumb

  property int delay: 600
  property string fontFamily: Style.font.family
  property Item pending: null

  interactive: false

  function hovered(item, inside) {
    if (inside) {
      thumb.pending = item
      timer.restart()
    } else if (thumb.pending === item || thumb.target === item) {
      thumb.hide()
    }
  }

  function hide() {
    timer.stop()
    thumb.pending = null
    thumb.open = false
    thumb.target = null
  }

  Timer {
    id: timer
    interval: thumb.delay
    onTriggered: {
      if (!thumb.pending || !thumb.pending.previewToplevel) return
      thumb.target = thumb.pending
      thumb.open = true
    }
  }

  BorderSurface {
    id: card

    width: preview.width + Style.space(16)
    height: column.height + Style.space(16)
    radius: Style.cornerRadius
    color: Commons.Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)

    Column {
      id: column
      x: Style.space(8)
      y: Style.space(8)
      spacing: Style.space(6)

      Text {
        width: preview.width
        textFormat: Text.PlainText
        // anchorTarget, not target: it stays set while the popup hides.
        text: thumb.anchorTarget && thumb.anchorTarget.tipText !== undefined ? String(thumb.anchorTarget.tipText) : ""
        elide: Text.ElideRight
        maximumLineCount: 1
        color: Commons.Color.tooltip.text
        font.family: thumb.fontFamily
        font.pixelSize: Style.font.body
      }

      WindowPreview {
        id: preview
        width: implicitWidth
        height: implicitHeight
        // Captures only while shown.
        toplevel: thumb.open && thumb.anchorTarget ? thumb.anchorTarget.previewToplevel : null
        live: thumb.open
      }
    }
  }
}
