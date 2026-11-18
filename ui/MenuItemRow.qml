import QtQuick
import qs.Commons
import qs.Commons as Commons

// One row of a menu: text, or a separator line. Optional check mark, icon and
// submenu arrow, for the menus apps publish with their tray icons.
Rectangle {
  id: row

  property string text: ""
  property bool separator: false
  property bool interactive: true
  // A check column, for menus where any row has a check box or radio.
  property bool checkColumn: false
  property bool checked: false
  property string iconSource: ""
  property bool hasChildren: false
  // Drawn faded but still clickable (a minimized window in a list).
  property bool dimmed: false
  // Levels of indent, for options that belong to the row above.
  property int indent: 0
  signal triggered()

  readonly property real lead: Style.spacing.controlPaddingX + indent * Style.space(14)
  readonly property real checkWidth: checkColumn ? Style.space(18) : 0
  readonly property real iconWidth: iconSource !== "" ? Style.space(16) + Style.spacing.md : 0

  width: parent ? parent.width : 0
  height: !visible ? 0 : separator ? Style.spacing.sm * 2 + 1 : Style.spacing.popupRowHeight
  radius: Style.cornerRadius
  color: rowMouse.containsMouse && !separator && interactive ? Style.hoverFill : "transparent"
  opacity: !interactive && !separator ? 0.45 : dimmed ? 0.55 : 1

  Rectangle {
    visible: row.separator
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: 1
    color: Style.normalBorderColor
  }

  Text {
    visible: !row.separator && row.checkColumn
    anchors.verticalCenter: parent.verticalCenter
    x: row.lead
    width: row.checkWidth
    textFormat: Text.PlainText
    text: row.checked ? "✓" : ""
    color: Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Image {
    visible: !row.separator && row.iconSource !== ""
    anchors.verticalCenter: parent.verticalCenter
    x: row.lead + row.checkWidth
    width: Style.space(16)
    height: Style.space(16)
    sourceSize: Qt.size(width * 2, height * 2)
    fillMode: Image.PreserveAspectFit
    source: row.iconSource
  }

  Text {
    visible: !row.separator
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: row.lead + row.checkWidth + row.iconWidth
    anchors.right: arrow.left
    anchors.rightMargin: Style.spacing.sm
    textFormat: Text.PlainText
    text: row.text
    elide: Text.ElideRight
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    id: arrow
    visible: !row.separator && row.hasChildren
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX
    width: visible ? implicitWidth : 0
    textFormat: Text.PlainText
    text: "›"
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    enabled: !row.separator && row.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.triggered()
  }
}
