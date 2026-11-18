import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// A popup that sits just above an item on the bar, centered on it and kept on
// screen: the base of every menu, flyout and tooltip in this plugin.
//
//   target   the item it sits above. Set it, then set open.
//   open     shown or not.
//   interactive: false  the pointer passes through (tooltips).
//   outsideClicked()    a click landed outside the popup and its bar; the
//                       owner should close it.
//
// Two traps it handles, both found the hard way (see the README):
// - It stays attached to the last target after the target is cleared.
//   Dropping the anchor while the popup is still mapped moves it to the
//   bar's corner for a frame before it disappears.
// - The outside-click grab arms only once the popup is on screen, so the
//   popup's own surface is in the grab's allowed list. Otherwise a click on
//   the popup counts as outside and closes it before the click lands.
PopupWindow {
  id: popup

  property Item target: null
  property bool open: false
  property bool interactive: true
  signal outsideClicked()

  default property alias content: holder.data

  property Item anchorTarget: null
  onTargetChanged: if (target) anchorTarget = target

  visible: open && !!anchorTarget
  color: "transparent"
  implicitWidth: Math.max(1, Math.ceil(holder.childrenRect.width))
  implicitHeight: Math.max(1, Math.ceil(holder.childrenRect.height))
  mask: Region { item: popup.interactive ? holder : null }

  anchor.item: anchorTarget
  anchor.rect.x: 0
  anchor.rect.y: -Style.spacing.sm
  anchor.rect.width: anchorTarget ? anchorTarget.width : 1
  anchor.rect.height: 1
  anchor.edges: Edges.Top
  anchor.gravity: Edges.Top
  anchor.adjustment: PopupAdjustment.Slide

  Item {
    id: holder
    width: childrenRect.width
    height: childrenRect.height
  }

  property bool grabArmed: false

  Timer {
    id: armTimer
    interval: 50
    onTriggered: popup.grabArmed = popup.visible
  }

  onVisibleChanged: {
    popup.grabArmed = false
    if (popup.visible) armTimer.restart()
  }

  HyprlandFocusGrab {
    active: popup.visible && popup.interactive && popup.grabArmed
    // The bar by its QsWindow.window, as Omarchy's PopupCard does.
    windows: popup.anchorTarget && popup.anchorTarget.QsWindow.window
      ? [popup, popup.anchorTarget.QsWindow.window] : [popup]
    onCleared: popup.outsideClicked()
  }
}
