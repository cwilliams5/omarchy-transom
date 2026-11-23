.pragma library

// Hands the running Service to the top-bar widget (BarWidget.qml). Omarchy
// looks up a plugin's service only for widgets on its own top bar; on a
// replacement bar that lookup returns nothing, so the plugin shares it here.
var service = null
