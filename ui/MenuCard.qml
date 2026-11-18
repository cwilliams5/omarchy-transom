import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The card behind a menu, styled like Omarchy's popups. Its children stack
// in a column (MenuItemRow, or any Item that fills the width).
BorderSurface {
  id: card

  property real contentWidth: Style.space(210)
  default property alias rows: column.data

  width: contentWidth + contentLeftInset + contentRightInset
  height: column.implicitHeight + contentTopInset + contentBottomInset
  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
  padding: Style.spacing.sm

  Column {
    id: column
    x: card.contentLeftInset
    y: card.contentTopInset
    width: card.contentWidth
  }
}
