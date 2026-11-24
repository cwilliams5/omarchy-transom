# CLAUDE.md: Transom

For an agent (or the maintainer, months later) picking this up with no memory
of how it was built. Read this first, then `README.md` (what users see: every
setting, how each part works) and `branding/BRANDING.md` (the name, logo and
palette). The reasons below matter as much as the rules.

This file is public with the repo: no personal details, nothing about the
maintainer's work setup.

## Status (2026-11-23)

Released and listed. 0.1.0 (2026-11-19) is the latest release; listed on
the Omarchy plugin marketplace (omarchyplugins.com, id
`io.github.cwilliams5.transom`, issue omacom/omarchy-plugin-marketplace#15342,
approved-and-verified at `eb20a13`). Every commit after that shows as
"Update unverified" on the listing until a newer one is verified.

Since 0.1.0: windows tagged `skip-taskbar` get no button unless minimized
(`cd5ee47`), and pin events re-read window data (`c7db3fe`).

In progress, for 0.2.0, in this order:
1. The optional top-bar widget (`BarWidget.qml`): show or hide the taskbar,
   and a two-column dropdown with nearly every bar-menu setting. Built on
   branch `topbar-widget`, tested live by command and by Cody (clicks, the
   bar menu button, removing it). Cody asked for the fuller dropdown and for
   window icons to get their own style (`windowIconStyle`, a "Window icons"
   row in the bar menu); he'll trim the dropdown from there.
2. A strict review of the whole plugin (fresh reviewers, fixes with
   regression tests).
3. Release 0.2.0 and a "Plugin verification" request (the maintainer
   approves it first).

Decided 2026-11-23 with Cody: removing the widget turns Transom off for
installs made with `--enable` (see "Platform facts", the bar-widget kind),
and nothing Transom may do changes that. So the way to go without the icon
is Transom's own switch, the bar option `topBarIcon` (dropdown, and the
bottom bar's menu to bring it back), and the dropdown warns under it when
removing would turn Transom off here (`Service.iconKeepsTransomOn`, from a
read-only look at shell.json's plugins list). A first try used a widget
setting ("Show icon" in `barWidget.schema`) until it turned out Omarchy 4.5
shows those nowhere.

## What Transom is

An Omarchy shell plugin: a Windows-style taskbar in a second bar along the
bottom of the screen, styled like Omarchy's top bar (theme colors, font,
height, the clear/glassy/opaque background). Left to right: an optional
start button (Omarchy's own menu widget) and quick launch, the taskbar
buttons, then the system tray, any of Omarchy's own bar widgets, and show
desktop. The taskbar is workspace-aware: it shows the windows on this
screen's workspace plus the ones minimized *from* it, so minimizing works on
every workspace, not only floating ones. It replaces Omarchy's dock.

It's for people who came from Windows and want its taskbar habits: one
button per window, click to focus, middle-click to close, right-click menus
worded like Windows', no Mac-style dock. It only writes its own settings
file. It never edits Omarchy's config, Hyprland's config or anything else
of the user's: moving widgets off the top bar or turning off the dock is the
user's call, and the README tells them how.

## The people and the projects around it

- **Maintainer: Cody** (GitHub `cwilliams5`). Came to Linux from Windows and
  knows Windows deeply. Explain Linux things plainly, with Windows
  comparisons where they help. Cody reviews anything outward-facing
  (publishing, posting, filing upstream) before it happens, and writes any
  upstream bug report in his own words. He dislikes motion and visual noise
  (scrolling titles, flashing, slide-ins), so the plugin has none by default.
- **Sister projects** (Cody's, each in its own repo):
  - **Latch** (Windows-style Alt+Tab) leaves `skip-taskbar` windows out of
    Alt+Tab the same way, and lists minimized windows using the same
    `omarchy-minimized-from-<id>` tags.
  - **Legato** (a Pocket Casts player) tags its picture-in-picture video
    window `skip-taskbar` while it's set to Always on top, and re-tags it
    when that changes; Transom re-reads window data on `pin` events for it.
  - **Sash** (Windows-style maximize on floating workspaces) maximizes by
    resizing, so its windows have `fullscreen` 0 and never need the
    stacking workaround below.
  - **Locus** (night light) and **Quiesce** (power options) are independent;
    their bar widgets are the models for Transom's planned one (a service
    lookup with a fallback, a dropdown in Omarchy's panel style).
- **Omarchy** (the desktop: Arch + Hyprland + a Quickshell shell) is the
  platform. Transom borrows its minimize protocol, its dock's dispatch forms
  and drag math, its tray's icon matching, and hosts its bar widgets
  unchanged.
- **On Cody's laptop:** working copy `~/Work/omarchy-transom`; installed
  with `omarchy plugin add` from this repo, so the live folder
  `~/.config/omarchy/plugins/io.github.cwilliams5.transom` is a plain git
  clone, updated with `omarchy plugin update`. **Never commit inside the live
  folder:** a local commit blocks `omarchy plugin update`. (Transom was
  developed inside its live folder until 2026-11-23; that's why older notes
  say "edit in place".) Cody's dotfiles (`~/Work/dotfiles`, chezmoi) list it
  by URL in `home/.chezmoidata/plugins.yaml` and track his `transom.json`
  and his Super+M binding.
- **Origin:** started 2026-11-17 as a local plugin (`local.bottom-bar`) in
  Cody's dotfiles, then split out and renamed (first commit `ee7afb1`
  imports it). Most features were built in one planned overnight run; that
  plan, its progress log and the morning report are in the dotfiles repo
  (private), `docs/plans/transom-overnight-2026-11-18.md`.

## Identity

- Name: Transom (the horizontal bar across a window: a bar on windows, and a
  building-trade word, like Omarchy's Arch). Repo `cwilliams5/omarchy-transom`.
- Ids:
  - plugin id `io.github.cwilliams5.transom`; manifest kinds `service` and
    `bar-widget` (the optional top-bar widget, `BarWidget.qml`; its
    dropdown's IPC target is the plugin id, as for any Omarchy panel)
  - settings file `~/.config/omarchy/transom.json` (until it exists,
    `defaults.json`)
  - IPC target `transom`: `omarchy-shell transom windows | widgets | tray |
    set <id> '<json>' | show | hide | toggle | widget`
  - log prefix `transom:`
  - layer-shell namespace `omarchy-bar` (Omarchy's own, on purpose; see the
    rules)
  - window tags it reads: `omarchy-minimized-from-<id>` (Omarchy's), and
    `skip-taskbar` (leave a window off the taskbar)
  - widget ids in the layout: `tasks`, `quicklaunch`, `tray`, `showdesktop`,
    plus any Omarchy bar widget id (`omarchy.network`, `omarchy.menu`...)
- Version: 0.1.0 in `manifest.json`; tag `v0.1.0`.
- Branding: `branding/` (`python3 branding/build.py` regenerates it); the
  mark is "Crossbar", `icon.svg` at the root is the app icon.

## Layout

```
manifest.json         plugin id, kind service, entry point Service.qml
Service.qml           the service: look, layout + settings (transom.json),
                      saving (updateWidget), Hyprland dispatches and app
                      launches for the widgets, the one-popup rule, the IPC
                      commands; one BarWindow per screen
BarWindow.qml         one screen's bar: layer-shell window, the three
                      sections, WidgetSlot loader, auto-hide, widget drag
BarMenu.qml           the right-click menu on empty bar space
BarWidget.qml         the optional top-bar widget: icon + dropdown
TopBarWidget.js       its pure logic: when the taskbar may hide, choices
Registry.js           hands the service to the widget on non-Omarchy bars
IconStyle.js          which style each app icon gets: app icons (tray,
                      quick launch) and window icons apart
defaults.json         the release layout (plain on purpose)
Settings.js           checks a layout entry against a widget's spec
TasksModel.js         taskbar settings spec + pure logic (which windows,
                      order, sizes, grouping)
TrayModel.js          tray settings spec + pure logic (names, pins, overflow)
QuickLaunchModel.js   quick launch settings + pinning
Reorder.js            drag math: icons within a row, whole widgets on the bar
IconSource.js         which icon references may reach a Qt Image
CaptureCache.js       which windows are hidden from screen capture
widgets/              Tasks, QuickLaunch, Tray, ShowDesktop, OmarchyWidget
ui/                   CrossbarIcon (the mark, drawn for the top-bar
                      widget), AnchoredPopup (base of every popup), MenuCard,
                      MenuItemRow, TooltipPopup, AppIcon, WindowPreview,
                      ThumbnailPopup, OmarchyBarApi (the `bar` Omarchy's
                      widgets expect)
shaders/tint.frag     icon tint for mono/themed; .qsb is the compiled form
                      (rebuild with qsb from qt6-shadertools)
minimize              minimize a window (Omarchy's, minus its floating check)
tray-window           tray left click: the icon's process and its windows
tests/run.js          node tests for the .js files
dev/                  vclick.py (scripted clicks/drags), clicklog.py
media/                README screenshots and GIFs
branding/             logo, lockups, alternatives, BRANDING.md, build.py
```

## Rules that must not be broken (and why)

1. **Only ever write `~/.config/omarchy/transom.json`.** Never `shell.json`,
   Hyprland config or anything else. Users trust a plugin that keeps to its
   own file, the README promises it, and the marketplace review checks what
   a plugin writes.
2. **The settings file lives outside the plugin folder.** Omarchy reloads a
   plugin whenever any file in its folder changes, and the bar writes its
   settings from its menus: a file inside would reload the plugin on every
   click.
3. **Strings from outside never index a plain object.** Window classes, tray
   ids, group keys and setting names go into `Object.create(null)` maps or
   are read through `hasOwnProperty`. A window class named `constructor`
   crashed the grouping (marketplace review round 2, fixed in `eb20a13`).
4. **Icons never load from the network.** Anything an app controls (a
   window's app id, a tray menu icon) is only a theme icon name; any other
   reference becomes a local URL or nothing (`IconSource.js`). Qt's Image
   fetches whatever URL it's given (review round 1, fixed in `d17665e`).
5. **Windows hidden from screen capture are never captured.** Omarchy marks
   password managers `no_screen_share`; thumbnails show their icon and say so
   instead (`ui/WindowPreview.qml`, `CaptureCache.js`).
6. **No motion or noise by default.** Titles are cut off with "…" and never
   scroll; nothing flashes for attention; every animation goes through
   `Style.duration()` so reduced motion turns it off; slide-in reveal is an
   option, off by default.
7. **Release defaults stay plain** (`defaults.json`: taskbar in the center,
   tray and show desktop on the right, everything else off). Anything
   optional is a setting with a sensible default, and the important ones are
   a switch in the bar menu. Nobody's personal setup goes in the defaults.
8. **Minimize the way Omarchy does:** the window goes to `special:minimized`
   with the tag `omarchy-minimized-from-<workspace id>`. Omarchy's own
   minimize, Latch and Transom all read it; don't invent another protocol.
9. **A `skip-taskbar` window still gets a button once minimized.** Otherwise
   nothing on screen could bring it back.
10. **`isMaximized` means Hyprland's real maximized state (`fullscreen` 1).**
    Only those need the stacking workaround; a resize-style maximize (Sash)
    takes the plain raise.
11. **Lists from Quickshell aren't JS arrays.** `tags` from `lastIpcObject`
    and lists passed through QML properties are Qt sequences:
    `Array.isArray` is false. Use `toList()` (`Settings.js`,
    `TasksModel.js`). The first version hid every minimized window this way.
12. **Re-read window data on events, never on title changes.**
    `lastIpcObject` (tags, floating, fullscreen) only updates on
    `Hyprland.refreshToplevels()`. `Service.qml` refreshes after the events in
    `refreshEvents`, with a timer that's started, not restarted, so a stream
    of events can't starve it. Titles are left out: an animated title (a
    coding agent's spinner) changes several times a second.
13. **A save must not rebuild widgets.** `BarWindow.qml` keeps each section in
    a ListModel keyed by widget id and moves or updates entries in place;
    rebuilding every widget made Omarchy's hosted widgets re-register their
    panels.
14. **Popups go through `ui/AnchoredPopup.qml` and the one-popup rule.** Call
    `bar.claimPopup(owner)` before opening and give the owner
    `closePopups()`. The outside-click grab arms 50 ms after showing (armed
    earlier, a click on the menu counted as outside and closed it before the
    row ran), and the popup keeps its last anchor while hiding (dropping it
    moved the popup to the corner for a frame).
15. **Use the `omarchy-bar` layer namespace.** Hyprland's layer rules for
    Omarchy's top bar (glassy blur, no slide-in, the window-glassy toggle)
    then apply to this bar too, so it always looks like the top one.
16. **The top-bar widget stays optional, and a hidden taskbar always has a
    way back.** Transom must work the same with no widget anywhere. The bar
    option `visible` only hides the taskbar while the widget is on a bar
    (`Service.widgetOnBar`: in Omarchy's layout, or a live copy counting
    itself) with its icon showing (`topBarIcon`). When the widget goes, the
    taskbar shows and the saved "hidden" is cleared, so re-adding the widget
    doesn't hide it by surprise (never at start-up, before the shell has
    handed over its config); hiding the icon shows the taskbar in the same
    save. Transom reads shell.json (the plugins list) but never writes it.
17. **Strings in `hyprctl` Lua dispatches are only Hyprland's own values**
    (window addresses, workspace ids). The marketplace reviewer blocks
    untrusted text reaching Hyprland's Lua. Quote shell arguments with
    `Util.shellQuote`.

## How it works, in one screen

- **Service.qml** loads as an Omarchy `service` plugin. Omarchy's `bar` kind
  would replace the top bar, so this opens its own layer-shell windows: one
  `BarWindow` per screen in `barScreens` (bar option `screens`).
- **Look** comes from Omarchy: `Commons.Color.bar`, `Style.font`,
  `Style.bar.sizeHorizontal`, and the top bar's `background` choice read
  from `shell.barConfig`. The bar hides when the top bar does
  (`shell.bar.barHidden`) and under a real fullscreen window (`fullscreen`
  bit 2), not under a maximized one.
- **Layout and settings:** `transom.json` holds `left`, `center`, `right`
  (lists of `{ id, enabled?, ...settings }`) and a `bar` object (bar-wide
  options, `barSettingsSpec`). `Settings.parse` checks each entry against its
  widget's spec; bad values fall back to defaults and are logged, so a typo
  never breaks the bar. Menus save through `updateWidget` → `saveLayout`,
  which writes the whole file; `layoutText` stops our own write coming back
  through the file watcher as a second rebuild.
- **Widgets** are loaded by `WidgetSlot` (BarWindow.qml) from the `widgets`
  map in Service.qml, or `widgets/OmarchyWidget.qml` for an Omarchy widget
  id. A widget can declare `bar`, `panel`, `settings`, `screenCenterX`, and
  `fills: true`; the slot fills them in. The README's "Adding a widget" has
  the recipe.
- **Windows** come from Quickshell's `Hyprland.toplevels`, turned into plain
  objects by `TasksModel.describe`; `TasksModel.belongsTo` decides which
  taskbar shows each one (`windows`: workspace, monitor or all).
- **Actions** are Hyprland Lua dispatches run with `hyprctl dispatch`
  through `Util.execDetached` (`Service.dispatch`, logged with the
  `transom:` prefix). Bringing a window forward is focus + `alter_zorder
  top`; a real maximized window gets the un-maximize/raise/re-maximize
  workaround (`raiseSteps`, bar option `maximizedRaiseWorkaround`) for a
  Hyprland 0.56.2 stacking bug.
- **The tray** reads Quickshell's `SystemTray` (StatusNotifierItem). Its
  Windows-style left click asks `tray-window` which process owns the icon
  (over D-Bus) and which window to bring forward, compares before and after
  the app's own click, and steps in only if the app did nothing. App menus
  are drawn by Transom: Qt's native menus can't open in Omarchy's shell.
- **Omarchy's own widgets** come from `barWidgetRegistry` (injected by the
  host a moment after load) and get `ui/OmarchyBarApi.qml` as their `bar`;
  their panels open upward. Their settings are saved on their entry in
  `transom.json`.
- **Auto-hide:** the window stays mapped; hidden, its content sits below the
  edge and the input mask is a 2 px strip that brings it back. It reserves
  no space while auto-hiding, so windows reach the edge.
- **The top-bar widget** (`BarWidget.qml`, an Omarchy `Panel`) finds the
  service through `shell.serviceFor` (Omarchy's top bar) or `Registry.js`
  (any other bar), counts itself in `Service.widgetCopies`, and only reads
  state and calls the service: `toggleTaskbar`, `updateWidget`,
  `openBarMenu` (BarWindow opens BarMenu mid-bar on that screen),
  `openSettingsFile`. Its icon is `ui/CrossbarIcon.qml`, a Shape on the
  logo's 64-unit grid that Omarchy's `BarIconContent` scales into the slot.
  Its dropdown is built from Omarchy's kit (`KeyboardPanel`, `PanelHero`,
  `ToggleSwitch`, `Dropdown`, `Button`), so it looks and moves like
  Omarchy's own panels.
- **Diagnostics:** `omarchy-shell transom windows` prints every window, its
  tags, where it was minimized from and which screens' taskbars show it;
  `tray` does the same for tray icons; `widgets` lists Omarchy's widgets and
  which bar has them.

## Platform facts this depends on (re-check after updates)

Tested with Omarchy 4.5.0-3, Hyprland 0.56.2, Quickshell 0.3.2, on a
2x-scaled laptop screen and a virtual second monitor.

- **A third-party service gets a narrow `shell` API:** `barConfig` (the
  `bar` section of shell.json) and `bar` (the top bar's size and hidden
  state). No app library and no full config, hence `gtk-launch` for apps and
  a settings file of its own.
- **Omarchy enables a plugin when its id appears anywhere in shell.json:**
  in `plugins[]`, or as a widget in `bar.layout` (`PluginRegistry.isEnabled`).
- **The bar-widget kind changes what enable and disable mean.** For a plugin
  with a `bar-widget` kind, `omarchy plugin enable` (and
  `omarchy plugin add --enable`) puts its widget on the top bar and adds no
  `plugins[]` entry; `disable` and dragging the widget off the bar only remove
  that bar entry; `omarchy plugin list` (and Omaplug, which reads it) calls
  it disabled unless its widget is on the bar (`setEnabled`, `listPlugins`,
  `inBar`). So a plugin installed that way stops entirely when its widget
  is removed, while one already in `plugins[]` keeps running. No Omarchy
  command adds a bar-widget plugin to `plugins[]`. `omarchy plugin remove`
  only clears an entry when the list says enabled, so it can leave a stale
  `plugins[]` entry behind (harmless). Checked in Omarchy 4.5.0-3's source,
  and live on 2026-11-23 for the `plugins[]` case.
- **Omarchy 4.5 has no screen for a widget's own settings**
  (`barWidget.schema` in a manifest): only third-party settings apps show
  them, or `omarchy-shell shell setBarWidget <id> <key> <json> '{}'`. So
  anything users must find goes in Transom's own menus. A widget saves its
  own settings by assigning `settings` (Omarchy's power widget does), which
  rewrites shell.json; Transom keeps its settings in transom.json instead.
- **Inside a property's change handler, a binding that depends on it can
  still hold its old value.** `BarWidget.syncCount` read `serviceReady` in
  `onServiceChanged` and never counted the widget; read the property
  itself there.
- **Omarchy's bar doesn't claim right or middle clicks on widgets** (only
  its custom-command widget uses them), so the widget can.
- **Quickshell caches QML.** Saving a file in the plugin folder makes Omarchy
  reload the plugin, but already-loaded QML stays cached, so the old code
  runs. `omarchy restart shell` after any QML change (it refuses while the
  screen is locked; the bar blinks once).
- **Hyprland's IPC is the Lua API** (`hl.dsp.window.move({ ... })`). Copy
  forms from `/usr/share/omarchy/default/hypr/` and Omarchy's dock
  (`/usr/share/omarchy/shell/plugins/dock/Dock.qml`).
- **Tags a window rule set read back with a trailing `*`**
  (`skip-taskbar*`, `omarchy-minimized-from-3*`); match both forms.
- **`lastIpcObject` is a snapshot** from the last `refreshToplevels()`;
  Quickshell keeps `workspace` and `title` current on its own.
- **Hyprland 0.56.2 stacking bug:** floating windows stay drawn over a focused
  maximized window and look clickable but aren't; neither `alter_zorder` nor
  `bring_to_top` helps. Tracked upstream as omacom/omarchy#16241 (fix PR
  #16404). When Hyprland or Omarchy fixes it, re-test, then remove
  `raiseSteps`' maximized branch, `isMaximized` and the bar option.
- **Omarchy's dock** does the same job; users turn it off with
  `omarchy plugin disable omarchy.dock`.
- **Omarchy's own widgets on two bars** (two screens, or top and bottom):
  their keyboard shortcuts open the first copy's panel.
- **On a 2x-scaled screen a virtual pointer's absolute moves are confined
  to the top-left quarter** (dev/vclick.py): place the pointer with
  `hyprctl dispatch 'hl.dsp.cursor.move({ x = X, y = Y })'` first; relative
  moves work anywhere.

## Working on it

- **Tests:** `node tests/run.js` (105 tests, about a second, nothing on
  screen). They cover the pure `.js` logic only; QML is checked when the
  shell loads it, so watch the log after a restart. Run before every commit.
- **Try a change live:** commit on a branch in the working copy, then
  ```bash
  live=~/.config/omarchy/plugins/io.github.cwilliams5.transom
  git -C "$live" fetch ~/Work/omarchy-transom <branch>
  git -C "$live" checkout --detach FETCH_HEAD
  omarchy restart shell
  ```
  Afterwards `git -C "$live" checkout main` and, once pushed,
  `omarchy plugin update io.github.cwilliams5.transom --yes`.
- **The top-bar widget without clicking:** open its dropdown with
  `omarchy-shell shell toggle io.github.cwilliams5.transom '{}'` (and `hide`
  to close it); hide and show the taskbar with `omarchy-shell transom
  hide|show`. Never script clicks on the top bar: leave clicking the icon
  to a person. Check `QML` syntax first with
  `/usr/lib/qt6/bin/qmllint --bare <file>` (it can't resolve Omarchy's
  imports, so read only its syntax errors). Try icon drawings offscreen
  with `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml` and `grabToImage`.
- **Log:** `/run/user/$UID/quickshell/by-pid/<pid>/log.log`, pid from
  `pgrep -f 'quickshell -n -p /usr/share/omarchy/shell'`. Grep `transom:`.
- **Is the bar there:**
  `hyprctl layers -j | jq '.. | objects | select(.namespace? == "omarchy-bar")'`
  lists the top bar and this one (`h=26` at the bottom on a default setup).
- **Settings from a script:** `omarchy-shell transom set bar '{"autohide": true}'`
  (null removes a setting). The user's `transom.json` is theirs: note it
  before a test and put it back after.
- **Clicking and dragging from a script:** `dev/vclick.py` (Wayland virtual
  pointer; `--click-here`, `--right`, `--middle`, `--drag DX`).
  `dev/clicklog.py` runs in a test terminal and counts the clicks it gets.
  Before every press, read `hyprctl cursorpos` and abort unless the pointer
  is where you meant and below the top bar: a drifted press once dragged
  widgets off Omarchy's top bar. Hyprland warps the pointer when the taskbar
  focuses a window, so positions go stale after a click.
- **Test windows:** open them on a workspace that's on screen, never a hidden
  one (a window on an unseen workspace never draws, stops answering pings,
  and Hyprland shows a "not responding" dialog). `foot --app-id=<desktop id>
  -T "<title>"` stands in for a real app on the taskbar (icons are looked up
  by app id).
- **Screenshots:** `grim -g "X,Y WxH"` (logical coordinates). Check visual
  features by pixel color, not by eye: "themed" icons once looked right and
  weren't. Nothing personal in anything kept: no email-titled windows, no
  network panel (SSID, IP), no notifications.
- **Don't run `omarchy agent` with no arguments** to check it: it opens an
  agent window. (It's the right command for quick launch's agent item.)
- Comments explain why. Each widget's header comment lists its clicks;
  keep it and the README's tables current with the code.

## Credits

Everything Transom builds on or borrows from. Add each one when it lands.
The README's "Built on" section should be made from this list.

- Omarchy: the platform, and pieces borrowed from it: the minimize protocol
  and script (`minimize` is `omarchy-hyprland-window-minimize` minus its
  floating-only check), the dock's dispatch forms and drag-reorder math,
  the tray's icon-name matching and its list of icons a widget stands in
  for, the popup outside-click grab (PopupCard), and the bar API its widgets
  expect (PluginBarApi) (https://omarchy.org, https://github.com/omacom/omarchy)
- Quickshell: the shell toolkit (layer-shell windows, Hyprland and
  SystemTray services, ScreencopyView for thumbnails) (https://quickshell.org)
- Hyprland: the compositor, its IPC and window rules (https://hyprland.org)
- Windows' taskbar: the model for the behavior and the wording of the menus
  ("Lock the taskbar", "Automatically hide the taskbar", "Combine taskbar
  buttons", show desktop)

## Distribution

The Omarchy plugin marketplace. Transom is a shell plugin with nothing to
install in Hyprland (the Super+M line is optional and printed in the
README), so `omarchy plugin add <url> --enable` is the whole install. Listed
2026-11-19 after two review rounds (both fixed: rules 3 and 4).

## Releasing

1. CLAUDE.md current (status, rules, platform facts, Credits).
2. The `ship-update` skill (it points to the go-public skill's
   `updates.md`): review the diff since the verified commit, version bump,
   tag, GitHub release, then the marketplace's "Plugin verification" form
   with the full SHA. The privacy scan runs last before every push.
3. The maintainer approves the release notes and the verification request
   before they're filed.

## Voice and conventions

Plain, practical, Windows terms where they help, no hype, no emoji. Menu
wording follows Windows' where Windows has a name for the thing. Commit
messages say why. "Transom" in sentences; the wordmark only as a logo.
