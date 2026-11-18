import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Reorder.js" as Reorder

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
  // Auto-hidden, the bar reserves no space: windows reach the bottom edge,
  // and the bar shows over them when it comes up, without moving them.
  exclusionMode: autohide ? ExclusionMode.Ignore : ExclusionMode.Normal
  exclusiveZone: autohide ? 0 : implicitHeight
  color: "transparent"
  surfaceFormat.opaque: false

  // ----------------------------------------------------------- auto-hide

  // Windows' "Automatically hide the taskbar" (bar option autohide). The
  // window stays mapped; hidden, its content sits below the screen edge and
  // only a 2px strip along the edge takes input. The pointer reaching it
  // brings the bar up. It goes again autohideDelay ms after the pointer
  // leaves, but never while one of its menus or panels is open, or while
  // something is being dragged.
  readonly property bool autohide: !!bar && bar.settings.autohide === true
  property bool revealed: false
  readonly property bool shown: !autohide || revealed || (!!bar && bar.popupOpen) || dragId !== ""
  onAutohideChanged: revealed = false

  mask: Region { item: window.shown ? content : trigger }

  HoverHandler {
    id: barHover
    onHoveredChanged: {
      if (hovered) {
        hideTimer.stop()
        window.revealed = true
      } else if (window.autohide) {
        hideTimer.restart()
      }
    }
  }

  Timer {
    id: hideTimer
    interval: window.bar ? window.bar.settings.autohideDelay : 600
    onTriggered: {
      if (barHover.hovered) return
      // Something is open or being dragged: look again later.
      if ((window.bar && window.bar.popupOpen) || window.dragId !== "") restart()
      else window.revealed = false
    }
  }

  // The edge strip that brings the bar up.
  Item {
    id: trigger
    anchors.bottom: parent.bottom
    width: parent.width
    height: 2
  }

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

  // Each section's widgets follow a model keyed by widget id, so saving the
  // settings file (a menu change, a drag) keeps the widgets that are still
  // there: a moved one is moved, not rebuilt, and changed settings reach
  // the widget in place. Rebuilding every widget on each save made Omarchy's
  // own widgets re-register their panels.
  ListModel { id: leftModel }
  ListModel { id: centerModel }
  ListModel { id: rightModel }

  readonly property var shownLayout: window.bar ? window.bar.shownLayout : ({})
  onShownLayoutChanged: window.syncSections()
  Component.onCompleted: window.syncSections()

  function syncSections() {
    window.syncModel(leftModel, window.shownLayout.left || [])
    window.syncModel(centerModel, window.shownLayout.center || [])
    window.syncModel(rightModel, window.shownLayout.right || [])
  }

  function syncModel(model, entries) {
    var keys = entries.map(function(entry) { return entry.id })
    for (var i = 0; i < keys.length; i++) {
      if (i < model.count && model.get(i).widgetId === keys[i]) continue
      var found = -1
      for (var j = i + 1; j < model.count; j++) {
        if (model.get(j).widgetId === keys[i]) { found = j; break }
      }
      if (found >= 0) model.move(found, i, 1)
      else model.insert(i, { widgetId: keys[i] })
    }
    if (model.count > keys.length) model.remove(keys.length, model.count - keys.length)
  }

  // A widget's entry (its settings) in a section of the shown layout.
  function entryIn(section, id) {
    var list = window.shownLayout[section] || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  BarMenu {
    id: barMenu
    bar: window.bar
  }

  // Everything the bar draws. Auto-hidden, it moves below the edge.
  Item {
    id: content
    width: window.width
    height: window.height
    y: window.shown ? 0 : height
    Behavior on y {
      enabled: !!window.bar && window.bar.settings.reveal === "slide"
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic }
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
        id: leftRepeater
        model: leftModel
        delegate: WidgetSlot { height: leftSection.height; section: "left" }
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
        id: rightRepeater
        model: rightModel
        delegate: WidgetSlot { height: rightSection.height; section: "right" }
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
        model: centerModel
        delegate: WidgetSlot {
          Layout.fillWidth: !!item && item.fills === true
          Layout.fillHeight: true
          Layout.preferredWidth: item ? item.implicitWidth : 0
        }
      }
    }

  }

  // ------------------------------------------------- dragging a widget

  // Omarchy's widgets (the start button, network, battery...) can be dragged
  // along the bar, within a side section or to the other side, unless the
  // bar is locked (Service.canDragWidget). The one being dragged follows the
  // pointer; the others step aside to show where it would land
  // (Reorder.dropSpot). Dropping saves the new layout.
  property string dragId: ""
  property real dragOffset: 0
  property real dragWidth: 0
  // Its x on the bar when the drag began.
  property real dragStartX: 0
  property var dragSpot: null
  // How far each other side widget moves aside, by widget id.
  property var dragShifts: ({})

  // A side section's widgets as { id, x, width } in bar coordinates,
  // leaving out the one being dragged.
  function sideWidgets(side) {
    var repeater = side === "left" ? leftRepeater : rightRepeater
    var section = side === "left" ? leftSection : rightSection
    var out = []
    for (var i = 0; i < repeater.count; i++) {
      var slot = repeater.itemAt(i)
      if (!slot || slot.widgetId === window.dragId) continue
      out.push({ id: slot.widgetId, x: section.x + slot.x, width: slot.width })
    }
    return out
  }

  function beginDrag(slot) {
    if (window.bar) window.bar.dismissPopups()
    if (slot.item && typeof slot.item.dragStarted === "function") slot.item.dragStarted()
    var section = slot.section === "left" ? leftSection : rightSection
    window.dragId = slot.widgetId
    window.dragWidth = slot.width
    window.dragStartX = section.x + slot.x
    window.dragOffset = 0
    window.updateDrag()
  }

  function moveDrag(offset) {
    if (!window.dragId) return
    // Keep it on the bar.
    var min = -window.dragStartX
    var max = window.width - window.dragWidth - window.dragStartX
    window.dragOffset = Math.max(min, Math.min(max, offset))
    window.updateDrag()
  }

  function updateDrag() {
    var sides = { left: window.sideWidgets("left"), right: window.sideWidgets("right") }
    var spot = Reorder.dropSpot(sides, window.dragStartX + window.dragOffset + window.dragWidth / 2, window.width / 2)
    var shifts = {}
    var edges = { left: leftSection.x, right: rightSection.x + rightSection.width }
    for (var side in sides) {
      var list = sides[side]
      var plan = Reorder.sidePositions(list.map(function(widget) { return widget.width }), side, edges[side],
        spot.section === side ? spot.index : -1, window.dragWidth)
      for (var i = 0; i < list.length; i++) shifts[list[i].id] = plan.xs[i] - list[i].x
    }
    window.dragSpot = spot
    window.dragShifts = shifts
  }

  function endDrag(commit) {
    if (!window.dragId) return
    var id = window.dragId
    var spot = window.dragSpot
    var list = spot ? window.sideWidgets(spot.section) : []
    window.dragId = ""
    window.dragSpot = null
    window.dragShifts = ({})
    window.dragOffset = 0
    if (!commit || !spot || !window.bar) return
    window.bar.moveWidget(id, spot.section, spot.index < list.length ? list[spot.index].id : "")
  }

  // Loads one widget from the layout and hands it the bar. A widget can
  // declare any of: bar (the service), panel (this window), settings (its
  // layout entry), screenCenterX (the screen's center in its own
  // coordinates, for centering on the screen rather than in its section).
  component WidgetSlot: Loader {
    id: slot

    required property string widgetId
    // "left", "center" or "right".
    property string section: "center"
    // Its layout entry: the id plus its settings.
    readonly property var entry: window.entryIn(section, widgetId)

    source: window.bar ? window.bar.widgetUrl(widgetId) : ""

    readonly property bool dragged: window.dragId !== "" && window.dragId === widgetId
    // Stepping aside for a widget being dragged past.
    readonly property real shift: window.dragId !== "" && !dragged ? (window.dragShifts[widgetId] || 0) : 0
    property real shownShift: shift
    Behavior on shownShift {
      enabled: window.dragId !== ""
      NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
    }
    z: dragged ? 1 : 0
    transform: Translate { x: slot.dragged ? window.dragOffset : slot.shownShift }

    // Past a few pixels a press becomes a drag; below that the widget gets
    // its click as usual (its MouseArea gives up the press once this takes
    // over). Positions are in scene coordinates, which don't move with the
    // widget.
    DragHandler {
      id: dragger
      enabled: slot.section !== "center" && !!window.bar && window.bar.canDragWidget(slot.widgetId)
      target: null
      acceptedButtons: Qt.LeftButton
      yAxis.enabled: false
      dragThreshold: Style.space(6)
      cursorShape: Qt.ClosedHandCursor
      // A drag that's cut short (something else grabs the pointer) still
      // lands where it was shown.
      onActiveChanged: {
        if (active) window.beginDrag(slot)
        else window.endDrag(true)
      }
      onCentroidChanged: if (active) window.moveDrag(centroid.scenePosition.x - centroid.scenePressPosition.x)
    }

    onLoaded: {
      if ("bar" in item) item.bar = window.bar
      if ("panel" in item) item.panel = window
      if ("settings" in item) item.settings = Qt.binding(function() { return slot.entry || ({ id: slot.widgetId }) })
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
