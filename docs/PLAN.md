# Transom: plan

What's left to build and fix. Read `CLAUDE.md` first; update this list in
the same commit as the work.

## 0.2.0 (in progress)

The optional top-bar widget, window icon styles and the icon switch are on
main (CLAUDE.md, Status). `omarchy plugin update` has already brought them
to existing users, still labelled 0.1.0 (R1-M4), so: finish the list below,
then release 0.2.0 through the ship-update skill.

### Added after the reviews

- [x] **Click the active window to minimize** (Cody, 2026-11-24): the
  `activeClick` setting existed (default "nothing", a choice from the first
  build); now it defaults to "minimize" as on Windows, with a row in the
  bar menu and the dropdown. A window that became active less than a
  second before the pointer reached the bar isn't minimized by that click
  (focus follows the mouse on Omarchy's tiled workspaces, so the pointer
  focuses the window it passes on its way down). Tested
  (`TasksModel.activeClickMinimizes`, the dropdown toggle; two mutations).
  The click itself (Tasks.qml) and the timing on a real desktop: by Cody.

- [x] **The bar's clicks leave the pointer where it is** (Cody, 2026-11-24):
  Hyprland moves the pointer to a window focused by command, so each
  taskbar click threw it into the window. New bar option `pointerToWindow`
  (off, as on Windows; a row in both menus). Every action now goes to
  Hyprland as one Lua chunk that turns the pointer moves off and puts the
  user's values back (CLAUDE.md rule 17, Latch's approach), and `minimize
  --keep-pointer` does it for the bar's minimizes. Verified in a nested
  Hyprland; tested (the chunk, the script, the dispatch path; three
  mutations).

- [x] **Hide with the top bar** (Cody, 2026-11-24): the taskbar always
  hid while Omarchy's top bar was toggled off. New bar option
  `hideWithTopBar` (on, today's behaviour; a row in both menus): off keeps
  the taskbar up then, for using Transom as the only bar. Tested (the
  dropdown switch, the service's hidden state; three mutations).

- [x] **Show desktop double-click** (S nit in R2, Cody asked 2026-11-24):
  each window's `minimize` is a few hyprctl calls, so the first click's
  chain takes a moment per window, and Transom reads the tags back 100 ms
  after. A second click inside that minimized again and cut the record
  down to the windows still open, or found nothing to bring back and
  forgot them. Fix: show desktop runs the chain itself (a Process, from
  `Service.minimizeCommand`); until it ends and the tags are read, a click
  is queued and runs then (dropped if the workspace changed, or the chain
  passed its 10 s deadline); a click that finds nothing keeps the record.
  Tested on fake windows in widget.test.sh (six mutations). The real
  chain's timing: by Cody.

- [x] **Tray: the app's own window first** (Cody asked 2026-11-24 whether
  the process-family guess had a better alternative): a Windows-style
  left click the app ignores brought forward the most recent window of the
  icon's process or any child process, so an app that starts other apps
  could bring one of those forward. Now the process's own windows come
  first, a child's only when it has none (Steam), then the name match and
  recency as before. Matching by desktop entry was weighed and left out:
  tray icon ids are app-chosen and often match none. Tested (scripts.test.sh,
  two mutations).

### R3. Pre-release review (2026-11-24, at 244160a)

The release runbook's review of the delta since the verified commit: a
fresh correctness reviewer on the commits after R2, and a "predict the
marketplace reviewer" agent on everything since `eb20a13` (with the
reviewer's comment history). Each finding checked in the code first;
Cody chose what to fix.

- [x] **R3-1 The active-click guard held back every click** until the
  pointer left the bar, not just the first. Fix: it holds back one
  (`activeClickMinimizes`' spentFor). Tested (node; a mutation).
- [x] **R3-2 Show desktop:** a click on another workspace during a chain
  was swallowed; the deadline stopped only the chain's shell, not a hung
  `minimize` or `hyprctl` under it. Fix: the queued click remembers its
  workspace; the chain runs under `timeout`, with a backstop for a chain
  that never reports back. Tested (harness; mutations).
- [x] **R3-3 The pointer chunk's save and set weren't guarded:** with a
  renamed option every action stopped, or `warp_on_change_workspace` was
  left at 0 (shown in a nested Hyprland). Fix: guarded, steps run either
  way. Tested in Lua against a stand-in API (both chunks; mutations).
- [x] **R3-4 "Top-bar icon" from the bar menu could hide the bar just
  clicked** (a saved "hidden" applying again with the widget back). Fix:
  putting the widget back clears it. Tested (harness; a mutation).
- [x] **R3-5 An unreadable transom.json counted as "no file"**, so the
  next click wrote the defaults over it (predicted reviewer Medium,
  their #15522). Fix: only FileNotFound means no file. Tested (harness:
  chmod 000; a mutation).
- [x] **R3-6 Tray menu icons loaded synchronously from any path an app
  named** (a pipe would stall the shell; their #13977, Medium). Fix:
  `IconSource.appIcon` (theme names and Quickshell's providers, never a
  path) and asynchronous loading. Tested (node; a mutation).
- [x] **R3-7 hyprctl without deadlines** in `minimize`, `tray-window`,
  `Service.dispatch` and the thumbnail check (their repeated Lows on
  teardown and watchdogs). Fix: each call under `timeout`; the thumbnail
  check fails closed if its check never reports back. Tested for the
  scripts (a hung stand-in hyprctl); the QML ones by reading.
- [x] **R3-8 Omarchy's copyright notice** for the code adapted from it
  (their Low on another taskbar's copy of the dock logic, #14047). Fix:
  `NOTICE` (LICENSE stays plain MIT so GitHub still recognises it).
- [x] **R3-9 Docs:** the README's pointer row named one setting of two and
  didn't mention focus following the mouse; CLAUDE.md rule 17 claimed more
  than `minimize` does.
- [x] **R3-10 Two tray icons with the same id** brought forward the first
  one's app. Fix: `failed` then (Cody, 2026-11-24). Checked live: current
  Chromium-based apps name their ids after the app (`chrome_status_icon_1`,
  `Bitwarden_status_icon_1`, `Claude_status_icon_1`), so this needs a
  very old Electron app next to Chrome. Tested (scripts; a mutation).

Checked and not an issue: the maximized raise workaround run as one chunk
(R3 reviewer's worry): still raises the maximized window over floating ones
in a nested Hyprland, 2026-11-24.

Kept as known limits (Cody, 2026-11-24): with Hyprland 0.56.2's stacking
bug, a click on an active maximized window drawn under floating ones
minimizes it (a second click brings it back on top; README, "Maximized
windows and stacking"); `activeClick` stays "nothing" for upgraders whose
file 0.1.0 wrote it into (the release notes and README say how to turn it
on; no write nobody clicked for).

### R1. First strict review (2026-11-23, at f5c2fbf): fix list

Two fresh reviewers (safety and correctness; fit, cost and honesty), with
the strict-review skill's checklist and the marketplace reviewer's patterns
as the bar. Their reports are kept outside the repo
(`transom-review1-safety.md`, `transom-review1-fit.md` in the maintainer's
review folder). Every item below was checked in the code by the author
before fixing. Ids: S = safety report, F = fit report.

Mutation runs: safety, 8 of 8 pure-JS mutants killed but 14 of 16 in QML
and scripts survived; fit, 9 of 24 killed. The "way back" rule was tested
only by regexes over Service.qml.

**High**
- [x] **R1-H1 A minimized dialog is lost** (S F1). `belongsTo` rejects a
  window with a parent before checking whether it's minimized, and the
  minimize script minimizes dialogs. Fix: a minimized window always
  belongs (parent, hidden or not), as in Omarchy's dock.
- [x] **R1-H2 With "Show on all displays" off, a window minimized on a
  screen without a bar is lost** (S F2). Fix: a bar also shows windows
  minimized from the workspaces of screens that have no bar.
- [x] **R1-H3 Transom's own widget, hosted on its own bar, can hide the
  taskbar for good** (S F3, F M2). The "Omarchy widgets" page offers it.
  Fix: never host Transom's own widget on its bar; list only Omarchy's own
  widgets there (F M5: third-party ones can't reach their services).
- [x] **R1-H4 A broken transom.json is overwritten by the next click,**
  with the defaults if it was broken at start-up (S F5, F M1); unknown
  top-level keys are dropped on every save. Fix: while the file doesn't
  parse, refuse every save and say so (bar menu, dropdown, one
  notification); keep unknown keys.

**Medium**
- [x] **R1-M1 "In the layout" counts as a way back even when the widget
  isn't drawn** (S F4): a broken widget, a replacement bar. Fix: only a
  live copy counts, after a start-up grace; losing it shows the taskbar
  and clears a saved "hidden".
- [x] **R1-M2 Untagged minimized windows never show** (S F6), and the
  test at tests/run.js:244 asserts it. Fix: show them on every bar.
- [x] **R1-M3 `tray-window` has no deadline** (S F10, F L2): one hung app
  delays tray clicks by 25 s per call, then the step-in acts a minute
  late; a failed probe reads as "launch". Fix: `busctl --timeout`, an
  overall `timeout`, a QML watchdog, stale results dropped, a failed probe
  does nothing.
- [ ] **R1-M4 Unreleased 0.2.0 shipped from main, labelled 0.1.0**
  (F M4). Release soon; keep unreleased work on a branch from now on.
- [x] **R1-M5 Omarchy's bar at the bottom stacks both bars there**
  (F M3). By reading. Documented as a known limit for 0.2.0; following
  Omarchy's bar to the other edge is a later feature (popups would open
  downward).
- [x] **R1-M6 `minimize` always ends by focusing the window's workspace**
  (S F7), which yanks the screen when minimizing a window that isn't the
  active one (a button menu on another workspace; show desktop's chain).
  Fix: only when it minimized the active window.

**Low**
- [x] **R1-L1** Show desktop can restore a different window that reused an
  address (S F8). Fix: only windows still tagged as minimized from here.
- [x] **R1-L2** Group tab switches aren't refresh events (S F9). Fix: add
  the group events and `activewindowv2`.
- [x] **R1-L3** An app-chosen D-Bus name reaches `busctl` as an option
  (S F11). Fix: `--` before it.
- [x] **R1-L4** Dispatch targets aren't checked to be addresses (S F12).
  Fix: `target()` accepts only `0x` + hex.
- [x] **R1-L5** The thumbnail privacy check fails open and can store one
  window's answer under another (S F13, F L4). Fix: fail closed; ask again
  when the window changed mid-check.
- [x] **R1-L6** Failed saves are invisible and leave memory ahead of disk
  (S F14). Fix: roll back and say so.
- [x] **R1-L7** A switched-off Superwhisper entry still hides its tray
  icon (F L1). Fix: the tray reads the shown layout.
- [x] **R1-L8** "Re-adding the widget doesn't hide the taskbar by
  surprise" is false on `--enable` installs (both): removing the widget
  stops Transom before anything runs. Fix the docs.
- [x] **R1-L9** Personal and private details in public files (F L6):
  CLAUDE.md's maintainer setup and preferences, `minimize`, Service.qml.
- [x] **R1-L10** The agent-logo watch is dead on a fresh install (F L8).
- [x] **R1-L11** The widget polls for its service for ever if none
  answers (F L9).
- [x] **R1-L12** Nits from both: stale comments and tests from the "Show
  icon" design; `tray-window`'s old IPC name; tests/run.js's header;
  BarMenu and the dropdown each with their own option lists; dropped
  layout entries not reported; a hosted widget can save into any entry;
  `dragId` left set by a save mid-drag; the slider's key repeat writes per
  step; README claims ("toggles keep the menu open", "only captured while
  shown").
- [x] **R1-T Tests:** tests/widget.test.sh (the real widget and service,
  offscreen, nothing on the desktop), tests/mutate.js with
  tests/mutations.json (every reviewer survivor), behaviour tests in place
  of the regex checks, and the scripts tested with stand-in commands.

Fixed 2026-11-23 (c61acf3). Round 2 found the claim "each with a test that
fails without the fix" false for R1-L1, L4, L5, L6, L7, L10, L11 and the QML
half of M3 (the code was fixed; no test failed without it). Those get
tests in R2 where a seam allows, and are marked "by reading" below where
none does. R1-M4 waits for the release. R1-M5 is documented.

### R2. Second strict review (2026-11-24, at c61acf3): fix list

Two fresh reviewers again (`transom-review2-{safety,fit}.md`). Both found
R1's high fixes holding (H1-H4, M1, M2, M6); no critical or high this
round. Their own mutations: safety 5 of 17 killed, fit 7 of 32; nearly
every survivor was QML or a script that no test loads.

**Medium**
- [x] **R2-M1 A click saves stale settings over a change the watcher
  missed** (S F1, F L6): a symlinked transom.json replaced by a plain
  file, or re-pointed, is never re-read. Fix: re-read the file before
  every save and apply the change on top of what's there.
- [x] **R2-M2 A tray lookup that failed still launches the app** (S F2):
  tray-window's "not found" answer has no failure flag. Fix: it says
  `failed` when the icon isn't found or a call fails.
- [x] **R2-M3 The dropdown's choice rows stop following the settings
  after a pick** (F M1): Omarchy's Dropdown assigns its own value; a
  refused save then shows the picked value. Fix: re-bind after each pick.
- [x] **R2-M4 Media and Indicators are offered for the bottom bar but
  can't work there** (F M2): they need first-party services Omarchy gives
  only to bar plugins. Fix: not offered; the README says which.
- [x] **R2-M5 PLAN's test claim** (F M3): corrected above; tests added.

**Low**
- [x] **R2-L1 A failed save is cleared at once and reported once a
  session** (S F3, F L1). Fix: keep it until a save works; notify again
  after a problem has cleared; a readable message.
- [x] **R2-L2 An editor's in-place save notifies** (F L5): the file is
  read empty for a moment. Fix: pause at once, notify only if the
  problem is still there half a second later.
- [x] **R2-L3 "Show the taskbar" does nothing while saving is paused,
  and says "shown"** (S F4). Fix: showing works in memory then, and
  says it wasn't saved.
- [x] **R2-L4 A file broken at start-up runs on the defaults,** middle-
  click closing included (S F5). Fix: then the defaults minus anything
  that closes or launches.
- [x] **R2-L5 R1-H2 lasts only while the screen without a bar keeps the
  workspace** (S F6). Fix: remember which screen each workspace was on.
  Also (F L8): windows open on a screen without a bar show on the bars
  there are, as on Windows.
- [x] **R2-L6 Tray clicks swallowed** (S F7): during a lookup, or with a
  late answer. Fix: the app always gets its click at once; the step-in
  needs a fresh view from the hover.
- [x] **R2-L7 The widget-gone timer writes transom.json** without a user
  action (S F8). Fix: no write; a saved "hidden" applies again when the
  widget comes back.
- [x] **R2-L8 The slider's wheel writes per event** (F L2). Fix: one
  debounce for keys and wheel.
- [x] **R2-L9 Every focus change refreshes window data** (F L3). Fix:
  `activewindowv2` refreshes only when the window was hidden (a group
  tab).
- [x] **R2-L10 The `tray` diagnostic reads switched-off entries** (F L4).
- [x] **R2-L11 A hidden icon still counts as a panel** for Tab and
  Omarchy's numbered panel keys (F L7). Fix: invisible, zero width.
- [x] **R2-L13 A widget dragged off the top bar had no way back from the
  taskbar** (found by Cody, 2026-11-24): the bar menu's "Top-bar icon" row
  showed only while the widget was on a bar. Fix: the row is always there,
  and ticking it puts the widget back through Omarchy's own `putBarWidget`
  (rule 1's one exception, on a click). Tested (widget.test.sh, a mutation).
- [x] **R2-L12 Nits** (both): an empty id through `set`; a duplicated
  line in WindowPreview; the diagnostics' own entry lookup; a stray
  "the"; README test and file docs, dependencies; CLAUDE.md's "every pure
  .js file"; exits not shorter than entrances in the slide.

Fixed 2026-11-24. With a test that fails without the fix (each is a
mutation in tests/mutations.json): M1, M2, M3, M4, L1, L2, L3, L5's
belongsTo half, L7, L9, L11, and the R1 items round 2 found untested where a
seam allowed (L1's `restorable`, L4's `target()` and `restoreWindow`
through a stand-in hyprctl). By reading only: L4's use of the safe layout
at start-up, L5's workspace memory, L6 (Tray.qml's click flow), L8's wheel
path (the keys are tested), L10, and R1-L5/L7/L10/L11. Round 2 found no
critical or high, so by the strict-review skill's rule the loop stops
here; the mutation check runs every entry with --all before the release.

Documented, not changed: with Omarchy's bar at the bottom and
auto-hide on, they overlap (R1-M5); the public CLAUDE.md keeps its
maintainer section and working-copy path (the accepted template lines);
`dev/` ships. (The show-desktop double-click race, an S nit, is fixed above.)

Kept as known limits: English only (F L5); `dev/` ships with the plugin
(F L7); Hyprland's own `no_screen_share` blanking stays the real privacy
guarantee for thumbnails.
