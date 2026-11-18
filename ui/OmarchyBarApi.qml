import QtQuick
import qs.Commons
import qs.Commons as Commons

// The `bar` object an Omarchy widget (omarchy.network, omarchy.power...)
// expects, answered by the bottom bar, so Omarchy's own widgets can sit on it
// unchanged. It mirrors Omarchy's PluginBarApi (shell/Ui/PluginBarApi.qml),
// the interface Omarchy gives widgets on bars other than its own, plus the
// few extras its first-party widgets read off the top bar (icon sizes,
// barSizeFor). If an Omarchy update breaks a hosted widget, compare this with
// PluginBarApi.qml and plugins/bar/Bar.qml first.
//
// One per hosted widget (widgets/OmarchyWidget.qml).
QtObject {
  id: api

  // The Transom service, the item hosting the widget, its tooltip.
  property var service: null
  property Item host: null
  property var tooltip: null
  property string moduleName: ""
  property string pluginId: moduleName

  // Look: the bottom bar's.
  readonly property color foreground: service ? service.foreground : Commons.Color.foreground
  readonly property color barForeground: foreground
  readonly property color background: service ? service.background : "transparent"
  readonly property color urgent: service ? service.urgent : Commons.Color.urgent
  readonly property string fontFamily: service ? service.fontFamily : Style.font.family
  readonly property string position: "bottom"
  readonly property bool vertical: false
  readonly property int barSize: service ? service.barSize : Style.bar.sizeHorizontal
  readonly property bool transparent: !!service && service.look === "none"
  property bool foregroundAnimationEnabled: true
  readonly property int iconSlot: Style.bar.iconSlot
  readonly property int iconSize: Style.bar.iconSize
  readonly property int iconFont: Style.bar.iconFont
  readonly property int iconCanvas: Style.bar.iconCanvas
  function barSizeFor(screenName) { return api.barSize }

  // Top-bar features the bottom bar doesn't have.
  property bool centerSectionRevealHeld: false
  property bool traySectionDragActive: false
  property bool traySectionPopoutOpen: false
  readonly property bool centerHoverRevealSuppressed: false
  function setCenterHoverRevealSuppressed(value) {}
  readonly property var foreignPopoutMarker: ({ foreign: true })
  readonly property var layoutConfig: service ? service.layout : ({})

  // Omarchy's shell API for the widget. The bottom bar's plugin gets a
  // narrower one than Omarchy's own bar, which can't open other plugins'
  // panels or save widget options. So this stands in for the two calls
  // Omarchy's widgets make: opening a panel goes through `omarchy-shell
  // shell summon/hide/toggle` (the same command anyone can run; e.g. the
  // network panel's Wi-Fi QR and speed test buttons), and saving a widget's
  // options saves them on its entry in the bottom bar's settings file (e.g.
  // the power widget's battery percentage). Everything else passes through.
  readonly property var shell: QtObject {
    readonly property var scoped: api.service ? api.service.shell : null
    readonly property string pluginId: scoped ? scoped.pluginId : ""
    readonly property var appLibrary: null
    readonly property var bar: scoped ? scoped.bar : null
    readonly property var barConfig: scoped ? scoped.barConfig : ({})
    readonly property var idleConfig: ({})

    function summon(id, payloadJson) {
      Util.execArgv(["omarchy-shell", "-q", "shell", "summon", String(id || ""), String(payloadJson || "{}")])
      return true
    }
    function hide(id) {
      Util.execArgv(["omarchy-shell", "-q", "shell", "hide", String(id || "")])
      return true
    }
    function toggle(id, payloadJson) {
      Util.execArgv(["omarchy-shell", "-q", "shell", "toggle", String(id || ""), String(payloadJson || "{}")])
      return true
    }
    function isPluginOpen(id) { return scoped ? scoped.isPluginOpen(id) : false }
    function updateEntryInline(id, settings) {
      if (!api.service || !settings || typeof settings !== "object") return false
      var changes = {}
      for (var key in settings) if (key !== "id") changes[key] = settings[key]
      api.service.updateWidget(String(id || api.moduleName), changes)
      return true
    }
    function serviceFor(id) { return scoped ? scoped.serviceFor(id) : null }
    function firstPartyServiceFor(id) { return scoped ? scoped.firstPartyServiceFor(id) : null }
    function pluginShellForBarEntry(ownerId, moduleName) { return null }
    function mutateShellConfig(mutator) { return false }
  }

  function run(command) { Util.execDetached(command) }

  // Tooltips, through the bottom bar's tooltip.
  // A widget with no tooltip text gets none, as on the top bar.
  function showTooltip(target, text) {
    if (!api.tooltip || !target) return
    if (String(text || "") === "") {
      api.tooltip.hovered(target, false)
      return
    }
    api.tooltip.textOverride = String(text)
    api.tooltip.hovered(target, true)
  }
  function hideTooltip(target) {
    if (api.tooltip) api.tooltip.hovered(target, false)
  }

  // One popout at a time. Opening one closes the previous, and tells the
  // bottom bar, which closes its own menus and flyouts too.
  property var activePopout: null
  function requestPopout(owner) {
    if (api.activePopout === owner) return
    var previous = api.activePopout
    api.activePopout = owner
    if (previous) {
      if ("closeForPopoutSwitch" in previous) previous.closeForPopoutSwitch()
      else if ("close" in previous) previous.close()
    }
    if (api.service && api.host) api.service.claimPopup(api.host)
  }
  function releasePopout(owner) {
    if (api.activePopout === owner) api.activePopout = null
  }

  // The top bar morphs a panel into its neighbour's; not here.
  function notePopoutCard(card) {}
  function popoutCardFor(owner) { return null }
  function switchPanelFrom(owner, direction) { return false }

  property var clickTargets: []
  function registerClickTarget(target) {
    if (target && api.clickTargets.indexOf(target) < 0) api.clickTargets = api.clickTargets.concat([target])
  }
  function unregisterClickTarget(target) {
    api.clickTargets = api.clickTargets.filter(function(other) { return other !== target })
  }
  function targetBelongsToWindow(target, window) {
    return !!target && !!window && !!target.QsWindow && target.QsWindow.window === window
  }

  function moduleWidgets(id) {
    return api.host && api.host.widget ? [api.host.widget] : []
  }
}
