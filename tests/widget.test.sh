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
import "file://$dir/repo/widgets" as TW
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
  // Show desktop (widgets/ShowDesktop.qml) on a stand-in bar, with fake
  // windows: its minimize chain is a sleep, and restores are only recorded.
  QtObject {
    id: fakeTaskbar
    property int barSize: 26
    property color foreground: "white"
    property string fontFamily: "sans"
    property string chainCommand: "sleep 1"
    property var minimizes: []
    property var restores: []
    function minimizeCommand(addresses) { minimizes = minimizes.concat([addresses.join(",")]); return chainCommand }
    function restoreWindows(addresses, workspaceId) { restores = restores.concat([workspaceId + ":" + addresses.join(",")]) }
    function dismissPopups() {}
  }
  TW.ShowDesktop { id: sd; bar: fakeTaskbar; workspaceId: 2; toplevels: [] }
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
        keys: w ? w.navKeys : [], cursor: w ? w.cursorKey : "", hidden: svc.hidden
      })
    }
    function move(dx: int, dy: int): string { w.moveCursor(dx, dy); return w.cursorKey }
    function cursor(key: string): string { w.cursorKey = key; return key }
    function activate(): string { w.activateCursor(); return w.cursorKey }
    function maxIcons(n: int): string { w.setMaxIcons(n); return "ok" }
    function hideBar(): string { return svc.hideTaskbar() }
    function showBar(): string { return svc.showTaskbar() }
    function widget(on: bool): string { widgetLoader.active = on; return String(svc.widgetCopies) }
    // As Omarchy's Dropdown does on a pick: assign its value, then emit changed.
    function pick(key: string, value: string): string {
      var d = w.dropdowns[key]
      if (!d) return "no dropdown"
      d.value = value
      d.changed(value)
      return "ok"
    }
    function dropdownValue(key: string): string { var d = w.dropdowns[key]; return d ? String(d.value) : "no dropdown" }
    function queueMaxIcons(n: int): string { w.queueMaxIcons(n); return "ok" }
    function visibleIcon(): string { return String(w.visible) }
    function focus(address: string): string { svc.focusWindow(address); return "ok" }
    function restore(address: string, workspace: int): string { svc.restoreWindow(address, workspace); return "ok" }
    function setIcon(on: bool): string { svc.setTopBarIconShown(on); return "ok" }
    function layout(on: bool): string { fakeShell.widgetOnLayout = on; return String(svc.widgetOnBar) }
    function sdReset(chain: string, deadline: int, settle: int): string {
      fakeTaskbar.minimizes = []; fakeTaskbar.restores = []; fakeTaskbar.chainCommand = chain
      sd.chainDeadlineMs = deadline; sd.settleMs = settle; sd.workspaceId = 2; sd.minimizedByUs = ({})
      return "ok"
    }
    // Base64: qs ipc splits an argument at its commas.
    function sdWindows(json64: string): string { sd.toplevels = JSON.parse(Qt.atob(json64)); return "ok" }
    function sdWorkspace(id: int): string { sd.workspaceId = id; return "ok" }
    function sdClick(): string { sd.clicked(); return "ok" }
    function sdState(): string {
      return JSON.stringify({ busy: sd.busy, queued: sd.queued, minimizes: fakeTaskbar.minimizes, restores: fakeTaskbar.restores, windows: sd.toplevels.length, open: sd.openWindows() })
    }
    function topBar(hidden: bool): string { fakeShell.bar = { barHidden: hidden }; return String(svc.hidden) }
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
check "the rows the keyboard stops on" "$(st '.keys | join(" ")')" "shown autohide withTopBar locked pointer topBarIcon tray overflow maxIcons trayClick quicklaunch tasks iconsOnly activeClick combine thumbnails plainTitles windows appIcons windowIcons menu file"
check "the first key lands on the first row" "$(wt move 0 1)" "shown"
check "down moves to the next" "$(wt move 0 1)" "autohide"

wt activate >/dev/null; sleep 0.4
check "Enter on auto-hide saves it" "$(file .bar.autohide)" "true"
wt cursor locked >/dev/null; wt activate >/dev/null; sleep 0.4
check "Enter on Lock saves it" "$(file .bar.locked)" "true"

# Omarchy's top bar toggled off: the taskbar hides with it by default; the
# "Hide with the top bar" switch off keeps it up (Transom as the only bar).
check "the top bar toggled off: the taskbar hides with it" "$(wt topBar true)" "true"
wt cursor withTopBar >/dev/null; wt activate >/dev/null; sleep 0.4
check "Hide with the top bar off: saved, and the taskbar stays up" "$(file .bar.hideWithTopBar),$(st .hidden)" "false,false"
wt cursor withTopBar >/dev/null; wt activate >/dev/null; sleep 0.4
check "...on again: back to the default, hidden with the top bar" "$(file .bar.hideWithTopBar),$(st .hidden)" "null,true"
wt topBar false >/dev/null
check "...and shown when the top bar is" "$(st .hidden)" "false"

wt cursor shown >/dev/null; wt activate >/dev/null; sleep 0.4
check "Show the taskbar off: hidden and saved" "$(st .shown),$(file .bar.visible)" "false,false"
check "...the bar menu button is gone while hidden" "$(st '.keys | index("menu")')" "null"
wt cursor topBarIcon >/dev/null; wt activate >/dev/null; sleep 0.4
check "hiding the icon shows the taskbar in the same save" "$(st .iconShown),$(st .shown),$(file .bar.topBarIcon),$(file .bar.visible)" "false,true,false,null"
check "...and the widget is invisible and takes no room (R2-L11)" "$(st .width),$(wt visibleIcon)" "0,false"
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

wt cursor activeClick >/dev/null; wt activate >/dev/null; sleep 0.4
check "Click active to minimize: on by default, off when switched" "$(file '.center[] | select(.id == "tasks") | .activeClick')" '"nothing"'
wt cursor activeClick >/dev/null; wt activate >/dev/null; sleep 0.4
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
check "...then the taskbar shows, and nothing is written (R2-L7)" "$(st .onBar),$(st .shown),$(file .bar.visible)" "false,true,false"
wt widget true >/dev/null; sleep 0.3; wt widget false >/dev/null; sleep 0.3; wt widget true >/dev/null; sleep 0.3
check "a quick rebuild (gone and back within a second) keeps it on the bar" "$(st .copies),$(st .onBar)" "1,true"
wt layout true >/dev/null; sleep 0.4
check "the widget back: hidden again, as it was left" "$(st .copies),$(st .shown)" "1,false"
wt showBar >/dev/null; sleep 0.4

# The dropdown's choice rows follow the setting after a pick (R2-M3).
wt pick combine always >/dev/null; sleep 0.4
check "a pick in the dropdown is saved" "$(file '.center[] | select(.id == "tasks") | .combine')" '"always"'
qs ipc -p "$dir/cfg" call transom set tasks '{"combine": "never"}' >/dev/null; sleep 0.4
check "...and a change from elsewhere shows in the row afterwards" "$(wt dropdownValue combine)" "never"

# The slider: a burst of releases (a touchpad flick) saves once (R2-L8).
before=$(grep -c 'setting tray {"maxIcons":' "$dir/log.txt")
for n in 4 5 6 7 8; do wt queueMaxIcons $n >/dev/null; done; sleep 0.6
check "a burst on the slider saves once" "$(( $(grep -c 'setting tray {"maxIcons":' "$dir/log.txt") - before )),$(file '.right[] | select(.id == "tray") | .maxIcons')" "1,8"
check "an empty widget id is refused, not saved" "$(qs ipc -p "$dir/cfg" call transom set '' '{}' | cut -c1-9)" "not saved"

# A change the file watcher misses (a symlinked file replaced) isn't saved over (R2-M1).
cfgfile="$home/.config/omarchy/transom.json"
cp "$cfgfile" "$dir/target.json"; rm "$cfgfile"; ln -s "$dir/target.json" "$cfgfile"; sleep 0.6
rm "$cfgfile"; jq '._marker = "kept"' "$dir/target.json" > "$cfgfile"; sleep 0.6
wt cursor locked >/dev/null; wt activate >/dev/null; sleep 0.5
check "a symlink replaced by a plain file: the next click keeps what's there" "$(file ._marker)" '"kept"'
check "...and saves its change on top" "$(file .bar.locked)" "false"

# In-place saves (an editor truncating first): no notification (R2-L2).
before=$(grep -c '^notify-send' "$dir/calls.txt" 2>/dev/null || true)
text=$(cat "$cfgfile"); : > "$cfgfile"; sleep 0.15; printf '%s\n' "$text" > "$cfgfile"; sleep 1
check "an in-place save doesn't notify" "$(( $(grep -c '^notify-send' "$dir/calls.txt" 2>/dev/null || true) - before ))" "0"

# A failed save: rolled back, and said until a save works (R2-L1).
chmod 444 "$cfgfile"; chmod 555 "$home/.config/omarchy"
wt cursor autohide >/dev/null; wt activate >/dev/null; sleep 0.6
check "a save that fails rolls back and says so" "$(st '.problem | test("couldn.t be saved")'),$(file .bar.autohide)" "true,true"
sleep 0.6
check "...and keeps saying so" "$(st '.problem | test("couldn.t be saved")')" "true"
chmod 755 "$home/.config/omarchy"; chmod 644 "$cfgfile"
wt cursor autohide >/dev/null; wt activate >/dev/null; sleep 0.6
check "...until a save works" "$(st .problem),$(file .bar.autohide)" ",false"

# A typo in transom.json: shown, and nothing saved over it (R1-H4).
printf '{ "bar": { "locked": true, }, "right": [] }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
check "a broken file is reported" "$(st '.problem | test("valid JSON")')" "true"
cp "$home/.config/omarchy/transom.json" "$dir/broken.json"
wt cursor autohide >/dev/null; wt activate >/dev/null; wt cursor shown >/dev/null; wt activate >/dev/null; wt maxIcons 2 >/dev/null; sleep 0.5
check "...and clicks save nothing over it" "$(cmp -s "$dir/broken.json" "$home/.config/omarchy/transom.json" && echo same)" "same"
sleep 0.4
check "...one notification says so" "$(grep -c "^notify-send.*isn't valid JSON" "$dir/calls.txt" 2>/dev/null)" "1"
wt hideBar >/dev/null; sleep 0.3
check "...hiding is refused while it's broken, and says so" "$(wt hideBar | cut -c1-10)" "not hidden"
wt pick combine always >/dev/null; sleep 0.4
check "...a pick that couldn't be saved snaps back to the setting" "$(wt dropdownValue combine)" "never"
printf '{ "bar": { "locked": true }, "_note": "kept", "center": [{ "id": "tasks" }], "right": [{ "id": "tray" }] }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
check "fixed: the problem clears" "$(st .problem)" ""
wt cursor autohide >/dev/null; wt activate >/dev/null; sleep 0.5
check "...saving works again, and keeps keys Transom doesn't know" "$(file .bar.autohide),$(file ._note)" 'true,"kept"'
printf '{ "bar": { "visible": false }, "center": [{ "id": "tasks" }], "right": [{ "id": "tray" }] }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
check "hidden in a good file" "$(st .shown)" "false"
printf '{ "bar": { "visible": false, }, "right": [] }\n' > "$home/.config/omarchy/transom.json"; sleep 1
check "the same JSON error a second time notifies again (R2-L1)" "$(grep -c "^notify-send.*isn't valid JSON" "$dir/calls.txt")" "2"
check "while broken, Show the taskbar still works, in memory (R2-L3)" "$(wt showBar | cut -c1-22),$(st .shown)" "shown, but not saved: ,true"
printf '{ "right": { "id": "tray" } }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
check "a section that isn't a list is a problem too" "$(st '.problem | test("must be a list")')" "true"

# Show desktop: a second click while the first one's windows are going down
# waits until they're down and their tags are read back, then brings them
# back (it minimized again, or restored nothing, before).
win() { # address workspace-id workspace-name tags focus-order
  printf '{"address":"%s","workspace":{"id":%s,"name":"%s"},"lastIpcObject":{"tags":%s,"mapped":true,"focusHistoryID":%s}}' "$@"
}
windows() { printf '[%s]' "$(IFS=,; echo "$*")" | base64 -w0; }
open2=$(windows "$(win 0xa 2 2 '[]' 1)" "$(win 0xb 2 2 '[]' 0)")
half=$(windows "$(win 0xa -98 special:minimized '[]' 1)" "$(win 0xb 2 2 '[]' 0)")
stale=$(windows "$(win 0xa -98 special:minimized '[]' 1)" "$(win 0xb -98 special:minimized '[]' 0)")
tag='["omarchy-minimized-from-2"]'
down=$(windows "$(win 0xa -98 special:minimized "$tag" 1)" "$(win 0xb -98 special:minimized "$tag" 0)")
sdst() { wt sdState | jq -c "$1"; }
until_t() { sleep "$(awk -v t0="$1" -v at="$2" -v now="$(date +%s.%N)" 'BEGIN { d = t0 + at - now; print (d > 0 ? d : 0) }')"; }

# The chain takes 1 s, then 1 s for the tags; they arrive at 1.5 s.
wt sdReset "sleep 1" 5000 1000 >/dev/null; wt sdWindows "$open2" >/dev/null
t0=$(date +%s.%N); wt sdClick >/dev/null
first=$(sdst '[.minimizes, .busy]')
wt sdWindows "$half" >/dev/null; wt sdClick >/dev/null
second=$(sdst '[.minimizes, .queued]')
wt sdWindows "$stale" >/dev/null
until_t "$t0" 1.5; wt sdWindows "$down" >/dev/null
until_t "$t0" 2.6
check "show desktop: a click minimizes the workspace's windows, the active one last" "$first" '[["0xa,0xb"],true]'
check "...a second click while they go down waits: no second minimize" "$second" '[["0xa,0xb"],true]'
check "...and once they're down and tagged, brings them all back" "$(sdst '[.restores, .busy, .queued]')" '[["2:0xa,0xb"],false,false]'

wt sdReset "sleep 0.2" 5000 200 >/dev/null; wt sdWindows "$open2" >/dev/null
wt sdClick >/dev/null; sleep 0.8; wt sdWindows "$stale" >/dev/null; wt sdClick >/dev/null
wt sdWindows "$down" >/dev/null; wt sdClick >/dev/null
check "...a click that finds nothing to bring back (tags not read yet) keeps the record" "$(sdst .restores)" '["2:","2:0xa,0xb"]'
wt sdReset "sleep 0.5" 5000 300 >/dev/null; wt sdWindows "$open2" >/dev/null
wt sdClick >/dev/null; wt sdClick >/dev/null; wt sdClick >/dev/null; sleep 1.2
check "...a third click takes the queued one back" "$(sdst '[.minimizes, .restores, .queued]')" '[["0xa,0xb"],[],false]'
wt sdReset "sleep 0.5" 5000 300 >/dev/null; wt sdWindows "$open2" >/dev/null
wt sdClick >/dev/null; wt sdClick >/dev/null; wt sdWorkspace 3 >/dev/null; sleep 1.2
check "...a queued click is dropped when the workspace changed meanwhile" "$(sdst '[.restores, .queued, .busy]')" '[[],false,false]'
wt sdReset "sleep 0.5" 5000 300 >/dev/null
wt sdWindows "$(windows "$(win 0xa 2 2 '[]' 1)" "$(win 0xb 2 2 '[]' 0)" "$(win 0xc 3 3 '[]' 2)")" >/dev/null
wt sdClick >/dev/null; wt sdClick >/dev/null; wt sdWorkspace 3 >/dev/null; wt sdClick >/dev/null; sleep 1.2
check "...a click on another workspace meanwhile (one was queued here) runs there once the first is done" "$(sdst .minimizes)" '["0xa,0xb","0xc"]'
# The chain's child stands in for a hung hyprctl: the deadline must stop it
# too, not only the shell running the chain.
wt sdReset "sleep 5.4321; true" 800 300 >/dev/null; wt sdWindows "$open2" >/dev/null
wt sdClick >/dev/null; wt sdClick >/dev/null; sleep 1.5
check "...a chain past its deadline is stopped and the queued click dropped (rule 20)" "$(sdst '[.restores, .queued, .busy]')" '[[],false,false]'
check "...everything it started stopped too" "$(pgrep -f 'sleep 5.4321' | wc -l)" "0"

# A settings file that's there but can't be read is a problem, not "no
# file yet": nothing is saved over it, and it's read again once it can be.
printf '{ "bar": { "locked": true }, "center": [{ "id": "tasks" }], "right": [{ "id": "tray" }] }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
cp "$home/.config/omarchy/transom.json" "$dir/unreadable.json"; chmod 000 "$dir/unreadable.json"
mv "$dir/unreadable.json" "$home/.config/omarchy/transom.json"; sleep 0.6
check "an unreadable settings file is a problem" "$(st '.problem | test("couldn.t be read")')" "true"
wt cursor autohide >/dev/null; wt activate >/dev/null; sleep 0.5
chmod 644 "$home/.config/omarchy/transom.json"
check "...and a click saves nothing over it" "$(file .bar)" '{"locked":true}'
wt cursor autohide >/dev/null; wt activate >/dev/null; sleep 0.5
check "readable again: the next click reads it and saves on top" "$(st .problem),$(file '[.bar.locked, .bar.autohide]')" ',[true,true]'

errors=$(grep -aE 'ReferenceError|TypeError|is not defined|Cannot assign|unavailable|Failed to load|Unable to assign' "$dir/log.txt" | grep -v qmlscanner || true)
check "no QML errors" "$errors" ""
# Omarchy's own Style reads a few Hyprland options (hyprctl -j getoption):
# read-only, and not Transom's. Anything else is a failure.
check "nothing else ran on the desktop" "$(grep -v -e '^hyprctl -j getoption ' -e '^notify-send ' "$dir/calls.txt" 2>/dev/null)" ""
# The real dispatch path (Service.qml), through the stand-in hyprctl, with
# a good settings file again (the checks above leave it broken).
printf '{ "center": [{ "id": "tasks" }], "right": [{ "id": "tray" }] }\n' > "$home/.config/omarchy/transom.json"; sleep 0.6
: > "$dir/calls.txt"
wt focus '0x1" }) ; hl.exec("x' >/dev/null; wt restore 0xabc -1 >/dev/null; wt restore 0xabc 2 >/dev/null; sleep 0.8
check "a target that isn't an address never reaches Hyprland's Lua (R1-L4)" "$(grep -c 'hl.exec' "$dir/calls.txt"),$(grep -c 'address:0x0' "$dir/calls.txt")" "0,1"
check "...an action runs as one chunk, the pointer kept where it is by default" "$(grep -c '^hyprctl repl .*no_warps = true.*address:0x0.*no_warps = w' "$dir/calls.txt")" "1"
check "a restore to a workspace that isn't one does nothing; a real one dispatches there" \
  "$(grep -c 'workspace = "-1"' "$dir/calls.txt"),$(grep -c 'workspace = "2"' "$dir/calls.txt")" "0,1"
qs ipc -p "$dir/cfg" call transom set bar '{"pointerToWindow": true}' >/dev/null; sleep 0.3; : > "$dir/calls.txt"
wt focus 0xabc >/dev/null; sleep 0.4
check "Move pointer to window on: Hyprland's own behaviour" "$(grep -c 'address:0xabc' "$dir/calls.txt"),$(grep -c 'no_warps' "$dir/calls.txt")" "1,0"

# The widget dragged off the top bar: the bar menu's "Top-bar icon" puts it
# back, through Omarchy's own command, and only when it isn't on a bar. A
# taskbar saved as hidden before the widget went stays shown (the click came
# from it).
wt hideBar >/dev/null; sleep 0.4
check "(hidden and saved, the widget on the bar)" "$(file .bar.visible)" "false"
wt widget false >/dev/null; wt layout false >/dev/null; sleep 1.3
: > "$dir/calls.txt"
wt setIcon true >/dev/null; sleep 0.4
check "the widget gone: Top-bar icon asks Omarchy to put it back" "$(grep -c '^omarchy-shell shell putBarWidget io.github.cwilliams5.transom' "$dir/calls.txt")" "1"
check "...and the taskbar's saved hidden is cleared, so it stays" "$(file .bar.visible)" "null"
wt layout true >/dev/null; wt widget true >/dev/null; sleep 0.6
: > "$dir/calls.txt"
wt setIcon true >/dev/null; sleep 0.4
check "...and not while it's on a bar" "$(grep -c 'putBarWidget' "$dir/calls.txt")" "0"

[ $fail = 0 ] || { echo "--- shell log (last 30 lines)"; tail -30 "$dir/log.txt"; }
exit $fail
