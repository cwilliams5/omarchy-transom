import QtQuick
import qs.Commons
import "../ui"

// Hosts one of Omarchy's own bar widgets on the bottom bar, unchanged: a
// layout entry like { "id": "omarchy.network" } loads the widget Omarchy's
// top bar would, from Omarchy's widget catalogue (barWidgetRegistry), and
// hands it ui/OmarchyBarApi.qml as its `bar`. Its panel opens upward, as it
// would from a top bar moved to the bottom.
Item {
  id: host

  // Set by the bottom bar (BarWindow.qml).
  property var bar: null
  property var panel: null
  property var settings: ({})

  readonly property string widgetId: settings && settings.id ? String(settings.id) : ""
  readonly property var component: {
    var registry = bar ? bar.barWidgetRegistry : null
    var widgets = registry && registry.widgets ? registry.widgets : null
    return widgets && Object.prototype.hasOwnProperty.call(widgets, widgetId) && widgets[widgetId] ? widgets[widgetId].component : null
  }
  readonly property var widget: loader.item

  implicitWidth: widget && widget.visible ? widget.implicitWidth : 0
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  // The bar calls this when another widget opens a popup.
  function closePopups() {
    var open = api.activePopout
    if (open && "close" in open) open.close()
  }

  // Whether its panel is open (the bar stays up while it is).
  readonly property bool popupVisible: !!api.activePopout

  // The bar calls this when the widget starts being dragged.
  function dragStarted() {
    tooltip.hide()
    host.closePopups()
  }

  OmarchyBarApi {
    id: api
    service: host.bar
    host: host
    tooltip: tooltip
    moduleName: host.widgetId
  }

  TooltipPopup {
    id: tooltip
    fontFamily: host.bar ? host.bar.fontFamily : Style.font.family
  }

  Loader {
    id: loader
    height: parent.height
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: host.component
    onLoaded: host.inject()
    onStatusChanged: if (status === Loader.Error) console.warn("transom: " + host.widgetId + " failed to load")
  }

  onSettingsChanged: inject()

  // What Omarchy's top bar gives a widget it loads (Bar.qml injectProps).
  function inject() {
    var target = loader.item
    if (!target) return
    if ("fixedEdge" in target) target.fixedEdge = "end"
    if ("bar" in target) target.bar = api
    if ("moduleName" in target) target.moduleName = host.widgetId
    if ("settings" in target) target.settings = host.settings
  }

  // Going away with its bar (a screen removed): the widget's own teardown
  // talks to its bar, which is going too. Cut it loose first.
  Component.onDestruction: {
    var target = loader.item
    if (target && "bar" in target) target.bar = null
  }

  Component.onCompleted: {
    if (!host.component && host.widgetId) console.warn("transom: Omarchy has no bar widget called " + host.widgetId)
  }
}
