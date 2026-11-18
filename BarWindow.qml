import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// One screen's bottom bar: a strip as tall as the top bar along the bottom
// edge, reserving its height so tiled windows stop above it.
PanelWindow {
  id: window

  // The Transom service (Service.qml): look, layout, widget files.
  property var bar: null

  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null

  // A real fullscreen window (not a maximized one) on this screen's
  // workspace hides the bar, as the top bar fades out. Same test as Omarchy's
  // BarModel.fullscreenOn.
  readonly property bool underFullscreen: {
    var current = window.workspace
    if (!current) return false
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var toplevel = list[i]
      if (!toplevel || !toplevel.workspace || toplevel.workspace.id !== current.id) continue
      var ipc = toplevel.lastIpcObject
      if (ipc && (Number(ipc.fullscreen) & 2) !== 0) return true
    }
    return false
  }

  visible: !!bar && !bar.hidden && !underFullscreen

  anchors {
    bottom: true
    left: true
    right: true
  }

  implicitHeight: bar ? bar.barSize : 26
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: implicitHeight
  color: "transparent"
  surfaceFormat.opaque: false

  // Omarchy's own bar namespace, on purpose: Hyprland's layer rules for the
  // top bar (glassy blur, no slide-in animation, the window-glassy toggle)
  // then apply to this bar too, so it always looks like the top one.
  WlrLayershell.namespace: "omarchy-bar"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  readonly property int gutter: Style.spacing.md
  readonly property bool endsWithShowDesktop: {
    var right = window.bar ? window.bar.shownLayout.right : []
    return right.length > 0 && right[right.length - 1].id === "showdesktop"
  }

  Rectangle {
    anchors.fill: parent
    color: window.bar ? window.bar.background : "transparent"
  }

  // A click on empty bar space closes whatever popup is open; a right click
  // opens the bar's own menu there (BarMenu.qml), like Windows' taskbar
  // menu. Widgets sit on top of this, so their own clicks never reach it;
  // empty space inside a widget (the taskbar's sides) does.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onPressed: function(event) {
      if (!window.bar) return
      if (event.button === Qt.RightButton) {
        menuAnchor.x = event.x
        barMenu.show(menuAnchor)
      } else {
        window.bar.dismissPopups()
      }
    }
  }

  // Where the bar menu opens: the point that was right-clicked.
  Item {
    id: menuAnchor
    width: 1
    height: parent.height
  }

  BarMenu {
    id: barMenu
    bar: window.bar
  }

  // Left and right sections are as wide as their widgets.
  Row {
    id: leftSection
    anchors.left: parent.left
    anchors.leftMargin: window.gutter
    height: parent.height
    // No gap between widgets, as on Omarchy's top bar: every icon sits on
    // the same grid (Style.bar.iconSlot).
    spacing: 0

    Repeater {
      model: window.bar ? window.bar.shownLayout.left : []
      delegate: WidgetSlot { height: leftSection.height }
    }
  }

  Row {
    id: rightSection
    anchors.right: parent.right
    // Show desktop sits in the very corner, as on Windows.
    anchors.rightMargin: window.endsWithShowDesktop ? 0 : window.gutter
    height: parent.height
    spacing: 0

    Repeater {
      model: window.bar ? window.bar.shownLayout.right : []
      delegate: WidgetSlot { height: rightSection.height }
    }
  }

  // The center section takes the width between them. A widget that sets
  // fills: true (the taskbar) gets whatever its neighbours leave.
  RowLayout {
    id: centerSection
    anchors.left: leftSection.right
    anchors.right: rightSection.left
    anchors.leftMargin: window.gutter
    anchors.rightMargin: window.gutter
    height: parent.height
    spacing: Style.spacing.sm

    Repeater {
      model: window.bar ? window.bar.shownLayout.center : []
      delegate: WidgetSlot {
        Layout.fillWidth: !!item && item.fills === true
        Layout.fillHeight: true
        Layout.preferredWidth: item ? item.implicitWidth : 0
      }
    }
  }

  // Loads one widget from the layout and hands it the bar. A widget can
  // declare any of: bar (the service), panel (this window), settings (its
  // layout entry), screenCenterX (the screen's center in its own
  // coordinates, for centering on the screen rather than in its section).
  component WidgetSlot: Loader {
    id: slot

    required property var modelData

    source: window.bar ? window.bar.widgetUrl(modelData.id) : ""

    onLoaded: {
      if ("bar" in item) item.bar = window.bar
      if ("panel" in item) item.panel = window
      if ("settings" in item) item.settings = slot.modelData
      if ("screenCenterX" in item) {
        item.screenCenterX = Qt.binding(function() {
          // Read so the binding follows the slot as the sections move.
          var follow = slot.x + slot.width + centerSection.x + leftSection.width + window.width
          return window.width / 2 - slot.mapToItem(window.contentItem, 0, 0).x
        })
      }
    }
  }
}
