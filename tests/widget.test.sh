#!/bin/bash
# The top-bar widget (BarWidget.qml) loaded for real next to the real
# Service.qml, and driven through its own functions. Node tests cover the
# .js logic only; this catches what only shows when QML runs: a widget that
# never counted itself with the service (found live 2026-11-23), the
# dropdown's rows and keyboard, and what each control saves.
#
# Nothing can reach the desktop or the user's files:
# - Qt's offscreen platform, so no window appears; Omarchy's KeyboardPanel (a
#   full-screen layer-shell surface) is swapped for a stub that builds the
#   dropdown's content in place; every other Ui component is Omarchy's own.
# - HOME and the XDG folders point into a throwaway folder, so transom.json
#   and shell.json are scratch files (Transom finds both through HOME).
# - No Hyprland connection (HYPRLAND_INSTANCE_SIGNATURE unset).
# - It runs a copy of the repo with BarWindow.qml (the bars, layer-shell
#   windows the offscreen platform can't make) swapped for a stub; the
#   service and the widget are the real files.
# - Logging stand-ins for every command Transom can run come first on PATH;
#   the test fails if any was called.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d -t transom-widget.XXXXXX)
qs_pid=""
trap '[ -n "$qs_pid" ] && kill $qs_pid 2>/dev/null; rm -rf "$dir"' EXIT

# The repo (code only), with the bars stubbed.
mkdir -p "$dir/repo"
(cd "$repo" && tar --exclude=.git --exclude=media --exclude=branding --exclude=preview.png -cf - .) | (cd "$dir/repo" && tar -xf -)
printf 'import QtQuick\n// Test stand-in for the bars.\nQtObject { property var screen: null; property var bar: null }\n' > "$dir/repo/BarWindow.qml"

home="$dir/home"
mkdir -p "$dir/cfg/Ui" "$home/.config/omarchy" "$home/.local/state" "$home/.cache" "$home/.local/share" "$dir/bin"
# Omarchy's colors follow the theme in use; read it where it is.
[ -e "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/current" ] && ln -s "$(readlink -f "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/current")" "$home/.config/omarchy/current"
ln -s /usr/share/omarchy/shell/Commons "$dir/cfg/Commons"
for f in /usr/share/omarchy/shell/Ui/*; do
  [ "$(basename "$f")" = KeyboardPanel.qml ] || ln -s "$f" "$dir/cfg/Ui/"
done
cat > "$dir/cfg/Ui/KeyboardPanel.qml" <<'EOF'
import QtQuick
// Test stand-in for Omarchy's KeyboardPanel: the properties Transom's
// widget uses, its content built at once, and never a window.
Item {
  id: root
  required property Item anchorItem
  property var owner: null
  property QtObject bar: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 640
  property int contentHeight: 700
  property Component content: null
  readonly property Item loadedContent: loader.item
  readonly property real loadedContentHeight: loader.item ? loader.item.implicitHeight : 0
  function fittedContentWidth(w) { return w }
  function fittedContentHeight(h, max) { return Math.min(h, max) }
  width: contentWidth
  height: 2000
  Loader { id: loader; sourceComponent: root.content; width: root.contentWidth; height: 2000 }
}
EOF

# Every command Transom runs, logged instead of run.
for c in hyprctl omarchy omarchy-shell omarchy-launch-tui uwsm-app gtk-launch xdg-terminal-exec notify-send busctl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls.txt"\n' "$c" "$dir" > "$dir/bin/$c"
  chmod +x "$dir/bin/$c"
done

# Omarchy's bar layout with the widget on it, and Transom not in plugins
# (an `omarchy plugin add --enable` install).
cat > "$home/.config/omarchy/shell.json" <<'EOF'
{
  "bar": { "layout": { "right": [{ "id": "omarchy.clock" }, { "id": "io.github.cwilliams5.transom" }] } },
  "plugins": []
}
EOF

cat > "$dir/cfg/shell.qml" <<EOF
import QtQuick
import Quickshell
import qs.Commons
import "file://$dir/repo" as T
ShellRoot {
  // The bar config the plugin host hands a service: Omarchy's bar section.
  QtObject {
    id: fakeShell
    property var barConfig: ({ layout: widgetOnLayout ? { right: [{ id: "io.github.cwilliams5.transom" }] } : {} })
    property bool widgetOnLayout: true
    property var bar: ({ barHidden: false })
  }
  T.Service { id: svc; shell: fakeShell; startupGraceMs: 1500 }
  // What Omarchy's bar hands a widget. shell is null, so the widget finds
  // the service through Registry.js, as on a bar that isn't Omarchy's.
  QtObject {
    id: fakeBar
    property color foreground: "white"
    property color barForeground: "white"
    property color background: "black"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    property string fontFamily: "sans"
    property bool vertical: false
    property string position: "top"
    property int barSize: 26
    property var shell: null
    function hideTooltip(item) {}
    function showTooltip(item, text) {}
  }
  // Not loaded at first: the start-up grace is tested before it appears.
  Loader { id: widgetLoader; active: false; sourceComponent: Component { T.BarWidget { bar: fakeBar } } }
  readonly property var w: widgetLoader.item
  ShellIpc {
    target: "transom.widgettest"
    function state(): string {
      return JSON.stringify({
        loaded: !!w, ready: !!w && w.serviceReady, copies: svc.widgetCopies, problem: svc.settingsProblem,
        onBar: svc.widgetOnBar, shown: svc.taskbarShown, iconShown: svc.topBarIconShown,
        warn: svc.iconKeepsTransomOn, width: w ? w.implicitWidth : -1,
        keys: w ? w.navKeys : [], cursor: w ? w.cursorKey : ""
      })
    }
    function move(dx: int, dy: int): string { w.moveCursor(dx, dy); return w.cursorKey }
    function cursor(key: string): string { w.cursorKey = key; return key }
    function activate(): string { w.activateCursor(); return w.cursorKey }
    function maxIcons(n: int): string { w.setMaxIcons(n); return "ok" }
    function hideBar(): string { return svc.hideTaskbar() }
    function showBar(): string { return svc.showTaskbar() }
    function widget(on: bool): string { widgetLoader.active = on; return String(svc.widgetCopies) }
    function layout(on: bool): string { fakeShell.widgetOnLayout = on; return String(svc.widgetOnBar) }
  }
}
EOF

# The release defaults, with the taskbar saved as hidden.
jq '.bar.visible = false' "$dir/repo/defaults.json" > "$home/.config/omarchy/transom.json"

export PATH="$dir/bin:$PATH"
unset HYPRLAND_INSTANCE_SIGNATURE
HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
  XDG_CACHE_HOME="$home/.cache" XDG_DATA_HOME="$home/.local/share" \
  QT_QPA_PLATFORM=offscreen qs -p "$dir/cfg" > "$dir/log.txt" 2>&1 &
qs_pid=$!

fail=0
wt() { qs ipc -p "$dir/cfg" call transom.widgettest "$@" 2>/dev/null; }
st() { wt state | jq -r "$1"; }
file() { jq -c "$1" "$home/.config/omarchy/transom.json" 2>/dev/null; }
check() { if [ "$2" = "$3" ]; then echo "ok - $1"; else echo "not ok - $1"; echo "    got:  $2"; echo "    want: $3"; fail=1; fi; }
for _ in $(seq 1 60); do [ "$(st .loaded 2>/dev/null)" = "false" ] && break; sleep 0.25; done

check "start-up, the widget listed but not loaded yet: a saved hidden is kept (no flash)" "$(st .onBar),$(st .shown)" "true,false"
sleep 1.8
check "...the grace over and still no widget: the taskbar shows (no way back otherwise, R1-M1)" "$(st .onBar),$(st .shown)" "false,true"
check "...without clearing the saved hidden" "$(file .bar.visible)" "false"
wt widget true >/dev/null
for _ in $(seq 1 60); do [ "$(st .ready 2>/dev/null)" = "true" ] && break; sleep 0.25; done
sleep 0.3
check "the widget arrives: hidden again, as saved" "$(st .copies),$(st .shown)" "1,false"
wt showBar >/dev/null; sleep 0.4
check "Show: shown and saved" "$(st .shown),$(file .bar.visible)" "true,null"

check "the widget loads and finds the service (through Registry.js)" "$(st .ready)" "true"
check "...and counts itself with it (the widget never did, 2026-11-23)" "$(st .copies)" "1"
check "the rows the keyboard stops on" "$(st '.keys | join(" ")')" "shown autohide locked topBarIcon tasks iconsOnly combine thumbnails plainTitles windows tray overflow maxIcons trayClick quicklaunch appIcons windowIcons menu file"
check "the first key lands on the first row" "$(wt move 0 1)" "shown"
check "down moves to the next" "$(wt move 0 1)" "autohide"

wt activate >/dev/null; sleep 0.4
check "Enter on auto-hide saves it" "$(file .bar.autohide)" "true"
wt cursor locked >/dev/null; wt activate >/dev/null; sleep 0.4
check "Enter on Lock saves it" "$(file .bar.locked)" "true"

wt cursor shown >/dev/null; wt activate >/dev/null; sleep 0.4
check "Show the taskbar off: hidden and saved" "$(st .shown),$(file .bar.visible)" "false,false"
check "...the bar menu button is gone while hidden" "$(st '.keys | index("menu")')" "null"
wt cursor topBarIcon >/dev/null; wt activate >/dev/null; sleep 0.4
check "hiding the icon shows the taskbar in the same save" "$(st .iconShown),$(st .shown),$(file .bar.topBarIcon),$(file .bar.visible)" "false,true,false,null"
check "...and the widget takes no room" "$(st .width)" "1"
check "hiding the taskbar is refused while the icon is hidden" "$(wt hideBar | cut -c1-10)" "not hidden"
wt cursor topBarIcon >/dev/null; wt activate >/dev/null; sleep 0.4
check "the icon comes back" "$(st .iconShown),$(file .bar.topBarIcon)" "true,null"

jq '.bar.visible = false | .bar.topBarIcon = false' "$home/.config/omarchy/transom.json" > "$dir/t.tmp" && mv "$dir/t.tmp" "$home/.config/omarchy/transom.json"; sleep 0.6
check "a file edited to hide both: the taskbar still shows (no way back otherwise)" "$(st .iconShown),$(st .shown)" "false,true"
jq 'del(.bar.visible) | del(.bar.topBarIcon)' "$home/.config/omarchy/transom.json" > "$dir/t.tmp" && mv "$dir/t.tmp" "$home/.config/omarchy/transom.json"; sleep 0.6

wt cursor maxIcons >/dev/null; wt move 1 0 >/dev/null; wt move 1 0 >/dev/null; wt move -1 0 >/dev/null; sleep 0.1
check "l and h on the slider wait for the key to stop" "$(file '.right[] | select(.id == "tray") | .maxIcons')" "6"
sleep 0.5
check "...then save once: one icon more" "$(file '.right[] | select(.id == "tray") | .maxIcons'),$(grep -c 'setting tray {"maxIcons":' "$dir/log.txt")" "7,1"
wt maxIcons 3 >/dev/null; sleep 0.4
check "the slider saves its value" "$(file '.right[] | select(.id == "tray") | .maxIcons')" "3"

wt cursor tasks >/dev/null; wt activate >/dev/null; sleep 0.4
check "Taskbar buttons off hides its rows" "$(st '.keys | map(select(. == "combine" or . == "windows")) | length'),$(file '.center[] | select(.id == "tasks") | .enabled')" "0,false"
wt cursor tasks >/dev/null; wt activate >/dev/null; sleep 0.4
check "...and back on" "$(st '.keys | map(select(. == "combine" or . == "windows")) | length')" "2"

check "the warning shows on an install Omarchy lists only on the bar" "$(st .warn)" "true"
jq '.plugins = [{ "id": "io.github.cwilliams5.transom" }]' "$home/.config/omarchy/shell.json" > "$dir/s.tmp" && mv "$dir/s.tmp" "$home/.config/omarchy/shell.json"; sleep 0.6
check "...and not once Transom is in the plugins list" "$(st .warn)" "false"

wt hideBar >/dev/null; sleep 0.3
check "hidden again, with the widget on the bar" "$(st .shown)" "false"
wt widget false >/dev/null; wt layout false >/dev/null; sleep 0.3
check "the widget gone: it uncounts itself, but counts as there for a second (a rebuild)" "$(st .copies),$(st .onBar),$(st .shown)" "0,true,false"
sleep 1.3
check "...then the taskbar shows and the saved hidden is cleared" "$(st .onBar),$(st .shown),$(file .bar.visible)" "false,true,null"
wt widget true >/dev/null; sleep 0.3; wt widget false >/dev/null; sleep 0.3; wt widget true >/dev/null; sleep 0.3
check "a quick rebuild (gone and back within a second) keeps it on the bar" "$(st .copies),$(st .onBar)" "1,true"
wt layout true >/dev/null; sleep 0.4
check "the widget back: the taskbar stays shown" "$(st .copies),$(st .shown)" "1,true"

# A typo in transom.json: shown, and nothing saved over it (R1-H4).
printf '{ "bar": { "locked": true, }, "right": [] }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
check "a broken file is reported" "$(st '.problem | test("valid JSON")')" "true"
cp "$home/.config/omarchy/transom.json" "$dir/broken.json"
wt cursor autohide >/dev/null; wt activate >/dev/null; wt cursor shown >/dev/null; wt activate >/dev/null; wt maxIcons 2 >/dev/null; sleep 0.5
check "...and clicks save nothing over it" "$(cmp -s "$dir/broken.json" "$home/.config/omarchy/transom.json" && echo same)" "same"
check "...one notification says so" "$(grep -c '^notify-send' "$dir/calls.txt" 2>/dev/null)" "1"
printf '{ "bar": { "locked": true }, "_note": "kept", "center": [{ "id": "tasks" }], "right": [{ "id": "tray" }] }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
check "fixed: the problem clears" "$(st .problem)" ""
wt cursor autohide >/dev/null; wt activate >/dev/null; sleep 0.5
check "...saving works again, and keeps keys Transom doesn't know" "$(file .bar.autohide),$(file ._note)" 'true,"kept"'
printf '{ "right": { "id": "tray" } }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
check "a section that isn't a list is a problem too" "$(st '.problem | test("must be a list")')" "true"

errors=$(grep -aE 'ReferenceError|TypeError|is not defined|Cannot assign|unavailable|Failed to load|Unable to assign' "$dir/log.txt" | grep -v qmlscanner || true)
check "no QML errors" "$errors" ""
# Omarchy's own Style reads a few Hyprland options (hyprctl -j getoption):
# read-only, and not Transom's. Anything else is a failure.
check "nothing else ran on the desktop" "$(grep -v -e '^hyprctl -j getoption ' -e '^notify-send ' "$dir/calls.txt" 2>/dev/null)" ""
[ $fail = 0 ] || { echo "--- shell log (last 30 lines)"; tail -30 "$dir/log.txt"; }
exit $fail
