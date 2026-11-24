# Transom: plan

What's left to build and fix. Read `CLAUDE.md` first; update this list in
the same commit as the work.

## 0.2.0 (in progress)

The optional top-bar widget, window icon styles and the icon switch are on
main (CLAUDE.md, Status). `omarchy plugin update` has already brought them
to existing users, still labelled 0.1.0 (R1-M4), so: finish the list below,
then release 0.2.0 through the ship-update skill.

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

Fixed 2026-11-23, each with a test that fails without the fix: every item
above is a mutation in tests/mutations.json (47, all killed with --all;
`minimize-any-address` was dropped as equivalent: the client lookup already
stops a fake address). R1-M4 waits for the release. R1-M5 is documented.

- [ ] **R2** A second strict-review round (fresh reviewers) on the fixes.

Kept as known limits: English only (F L5); `dev/` ships with the plugin
(F L7); Hyprland's own `no_screen_share` blanking stays the real privacy
guarantee for thumbnails.
