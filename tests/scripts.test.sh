#!/bin/bash
# The two shell helpers, minimize and tray-window, run against stand-in
# hyprctl and busctl commands that log what they're asked and answer from
# fixtures. Nothing reaches Hyprland or D-Bus.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d -t transom-scripts.XXXXXX)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/bin"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok - $1"; else echo "not ok - $1"; echo "    got:  $2"; echo "    want: $3"; fail=1; fi; }

# hyprctl: the active window and clients from fixture files; dispatches
# logged, answered "ok" unless the request contains $DISPATCH_FAILS.
cat > "$dir/bin/hyprctl" <<EOF
#!/bin/bash
case "\$1" in
  activewindow) cat "$dir/active.json" ;;
  clients) cat "$dir/clients.json" ;;
  repl)
    echo "repl \$2" >> "$dir/dispatches.txt"; echo ok ;;
  dispatch)
    echo "\$2" >> "$dir/dispatches.txt"
    if [ -n "\${DISPATCH_FAILS:-}" ] && [[ "\$2" == *"\$DISPATCH_FAILS"* ]]; then echo "error: refused"; else echo ok; fi ;;
esac
EOF
# busctl: every call's argv logged; answers for a watcher with two items,
# one of them registered under a name that looks like an option.
cat > "$dir/bin/busctl" <<EOF
#!/bin/bash
echo "\$*" >> "$dir/busctl.txt"
args=" \$* "
case "\$args" in
  *" RegisteredStatusNotifierItems "*) echo '{"type":"as","data":["-Hevil.example/StatusNotifierItem",":1.5/StatusNotifierItem"]}' ;;
  *" :1.5 /StatusNotifierItem org.kde.StatusNotifierItem Id "*) [ -n "\${ID_FAILS:-}" ] && exit 1; echo '{"type":"s","data":"discord"}' ;;
  *" GetConnectionUnixProcessID s :1.5 "*) echo '{"type":"u","data":[4242]}' ;;
  *" ItemIsMenu "*) echo '{"type":"b","data":false}' ;;
  *" Menu "*) echo '{"type":"o","data":"/MenuBar"}' ;;
esac
EOF
chmod +x "$dir/bin/hyprctl" "$dir/bin/busctl"
export PATH="$dir/bin:$PATH"

# ---------------------------------------------------------------- minimize

echo '{"address":"0xa1","workspace":{"id":2,"name":"2"}}' > "$dir/active.json"
echo '[{"address":"0xa1","workspace":{"id":2,"name":"2"},"tags":[]},{"address":"0xb2","workspace":{"id":3,"name":"3"},"tags":["omarchy-minimized-from-1"]},{"address":"0xc3","workspace":{"id":-98,"name":"special:scratchpad"},"tags":[]}]' > "$dir/clients.json"

: > "$dir/dispatches.txt"
"$repo/minimize"
check "minimize (the active window): tagged, moved, and focus stays on its workspace" \
  "$(grep -c 'omarchy-minimized-from-2' "$dir/dispatches.txt"),$(grep -c 'special:minimized' "$dir/dispatches.txt"),$(grep -c 'hl.dsp.focus({ workspace = "2" })' "$dir/dispatches.txt")" "1,1,1"

: > "$dir/dispatches.txt"
"$repo/minimize" --keep-pointer
check "--keep-pointer: the move and the focus run as one chunk with the pointer's moves off, then back" \
  "$(grep -c '^repl ' "$dir/dispatches.txt"),$(grep '^repl ' "$dir/dispatches.txt" | grep -c 'no_warps = true.*special:minimized.*hl.dsp.focus({ workspace = "2" }).*no_warps = w')" "1,1"
check "...and nothing went through a plain dispatch but the tag" "$(grep -v -c -e '^repl ' -e 'omarchy-minimized-from' "$dir/dispatches.txt")" "0"

: > "$dir/dispatches.txt"
"$repo/minimize" 0xb2
check "minimize another window: no jump to its workspace (R1-M6)" "$(grep -c 'hl.dsp.focus' "$dir/dispatches.txt")" "0"
check "...its old minimized-from tag is replaced" "$(grep -c -- '-omarchy-minimized-from-1' "$dir/dispatches.txt"),$(grep -c '+omarchy-minimized-from-3' "$dir/dispatches.txt")" "1,1"

: > "$dir/dispatches.txt"
DISPATCH_FAILS="+omarchy-minimized-from" "$repo/minimize" 0xb2; status=$?
check "the tag refused: the window isn't moved (it would have no way back)" "$status,$(grep -c 'special:minimized' "$dir/dispatches.txt")" "1,0"

: > "$dir/dispatches.txt"
"$repo/minimize" 0xc3; status=$?
check "a window on a special workspace isn't minimized" "$status,$(wc -l < "$dir/dispatches.txt")" "1,0"
"$repo/minimize" '0x1" })'; status=$?
check "an address that isn't one is refused before any dispatch" "$status,$(wc -l < "$dir/dispatches.txt")" "1,0"

# ------------------------------------------------------------- tray-window

echo '{"address":"0xd4"}' > "$dir/active.json"
echo '[{"address":"0xd4","pid":4242,"class":"discord","workspace":{"id":1,"name":"1"},"focusHistoryID":0,"tags":[]}]' > "$dir/clients.json"
: > "$dir/busctl.txt"
out=$("$repo/tray-window" discord discord)
check "tray-window finds the app's window" "$(jq -c '{pid, window, focused}' <<<"$out")" '{"pid":4242,"window":"0xd4","focused":"0xd4"}'
check "every busctl call has a deadline and \"--\" before app-chosen names (R1-M3, R1-L3)" \
  "$(grep -c -v -e '--timeout=1 -- ' "$dir/busctl.txt")" "0"
check "a bus name shaped like an option is never passed on" "$(grep -c 'evil' "$dir/busctl.txt")" "0"
check "the app's D-Bus call failing: \"failed\", never a plain \"nothing\" (R2-M2)" "$(ID_FAILS=1 "$repo/tray-window" discord discord | jq -c .failed)" "true"
check "no icon id: \"failed\"" "$("$repo/tray-window" "" "" | jq -c .failed)" "true"
check "...and the answer for a found app has no failure flag" "$(jq -c .failed <<<"$out")" "null"

exit $fail
