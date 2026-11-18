import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A tooltip in the style of the top bar's: shows the hovered item's tipText
// after `delay` ms of hovering. It just appears; no animation. Widgets call
// hovered(item, inside) from their hover handlers and hide() on clicks.
AnchoredPopup {
  id: tip

  property int delay: 600
  property string fontFamily: Style.font.family
  // Text to show instead of the hovered item's tipText (for Omarchy's
  // widgets, which pass their tooltip text in showTooltip).
  property string textOverride: ""
  property Item pending: null

  interactive: false

  function hovered(item, inside) {
    if (inside) {
      tip.pending = item
      timer.restart()
    } else if (tip.pending === item || tip.target === item) {
      tip.hide()
    }
  }

  function hide() {
    timer.stop()
    tip.pending = null
    tip.open = false
    tip.target = null
  }

  Timer {
    id: timer
    interval: tip.delay
    onTriggered: {
      if (!tip.pending) return
      // Never an empty bubble.
      var text = tip.textOverride !== "" ? tip.textOverride
        : tip.pending.tipText !== undefined ? String(tip.pending.tipText) : ""
      if (text === "") return
      tip.target = tip.pending
      tip.open = true
    }
  }

  BorderSurface {
    id: bubble

    readonly property real maxTextWidth: Style.space(480)

    width: Math.min(label.implicitWidth, maxTextWidth) + Style.space(20)
    height: label.height + Style.space(14)
    radius: Style.cornerRadius
    color: Commons.Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)

    Text {
      id: label
      anchors.centerIn: parent
      width: Math.min(implicitWidth, bubble.maxTextWidth)
      textFormat: Text.PlainText
      // anchorTarget, not target: it stays set while the tooltip hides.
      text: tip.textOverride !== "" ? tip.textOverride
        : tip.anchorTarget && tip.anchorTarget.tipText !== undefined ? String(tip.anchorTarget.tipText) : ""
      wrapMode: Text.Wrap
      color: Commons.Color.tooltip.text
      font.family: tip.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
