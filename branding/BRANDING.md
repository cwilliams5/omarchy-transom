# Transom branding

Three options to pick from. Each has an icon, a wordmark and a palette, as
SVGs plus a preview sheet. Nothing is final until one is picked; the README
uses none of them yet.

## The name

A **transom** is the horizontal bar across a window or above a door: the
crosspiece that divides the glass. This is a horizontal bar across the bottom
of your screen, holding your windows. Several more meanings fit too:

- **A bar for Windows people.** It's a Windows-style taskbar, so it's a bar
  across *your windows* in both senses.
- **Arch.** A transom is architecture, and architecture leads to *Arch*, the
  Linux that Omarchy is built on. Many transoms literally hold an arched
  fanlight.
- **A building-trade name.** It sits next to Cody's *Rebar*: both are bars
  from construction, and both hold something up.
- **It ends in "om",** like Omarchy.
- **It's short, pronounceable and unclaimed** in the Omarchy plugin world.

(The nautical transom, the flat back of a boat, is a coincidence; the
branding doesn't use it.)

## Rules for every option

- **One color first.** Every icon and wordmark works in a single color
  (`currentColor` in the SVGs), so it can follow the user's Omarchy theme,
  as the bar does, and matches Transom's own monochrome icon style. The
  accent is optional: `icon-color.svg` and `wordmark-color.svg` show it.
- **16px matters.** The icon is designed to read at the bar's icon size. The
  preview sheets show 64, 32, 24 and 16px.
- **Lowercase in running text:** "Transom" in sentences, the wordmark only as
  a logo.
- **Voice:** plain and practical, Windows terms where they help ("Lock the
  taskbar", "Combine taskbar buttons"). No hype, no emoji.

## Option 1: Crossbar

![Option 1, Crossbar](option-1-crossbar/preview.png)

- **Icon:** a four-pane window whose bottom rail is a solid bar in the
  accent color. It's a window, and it's a taskbar.
- **Wordmark:** geometric monoline lowercase **transom**, sitting on its own
  bar: the underline is the transom.
- **Palette:** Slate `#2E3440` (background), Glass `#88C0D0` (accent), Amber
  `#EBCB8B` (highlight), Snow `#ECEFF4` (text). Cool, Nord-like, calm.
- **Strengths:** the most literal and the clearest at 16px; says "window +
  bar" instantly. Neutral enough to sit beside any theme.
- **Trade-off:** a window-grid icon is common (it's close to the Windows
  logo's idea), so it's the least distinctive.

## Option 2: Fanlight

![Option 2, Fanlight](option-2-fanlight/preview.png)

- **Icon:** an arched fanlight (the sunburst window above a door) resting
  on a solid bar: a transom in the architectural sense, and a nod to Arch.
  It also reads as a sunrise over the horizon.
- **Wordmark:** widely spaced monoline capitals, **TRANSOM**, like
  lettering cut into a building.
- **Palette:** Charcoal `#22201E` (background), Brass `#C8A24A` (accent), Brick
  `#A0503C` (highlight), Limestone `#EAE4D6` (text). Warm, crafted, a
  little old-world.
- **Strengths:** the most distinctive and the best story; elegant at large
  sizes.
- **Trade-off:** the busiest icon at 16px (the rays merge), and the
  furthest from "taskbar" at a glance.

## Option 3: T-bar

![Option 3, T-bar](option-3-tbar/preview.png)

- **Icon:** a bold **T** whose crossbar is a little taskbar with three
  window dots. Simple shapes, so it stays crisp at 16px.
- **Wordmark:** heavy geometric lowercase **transom** whose "o" is a tiny
  screen with a taskbar along its bottom.
- **Palette:** Midnight `#0B1220` (background), Sky `#38BDF8` (accent), Mint
  `#34D399` (highlight), Paper `#F8FAFC` (text). Modern, bright, techy.
- **Strengths:** the strongest small-size mark, the most "app-like", and the
  T works as a monogram on its own.
- **Trade-off:** the playful screen-"o" makes the wordmark a little less
  readable at a glance; the palette is the least Omarchy-like.

## My recommendation

**Crossbar** for clarity, with **T-bar** as the runner-up if a bolder, more
ownable mark matters more. Fanlight has the best story but is weakest
where it matters most: 16px on a bar.

Mixing is fine: e.g. the Crossbar icon with the T-bar wordmark, or any icon
with a different palette. The generator makes that a few-line change.

## Files

```
branding/
  build.py                 makes everything below: python3 branding/build.py
  option-N-name/
    icon.svg               one color (currentColor): use this
    icon-color.svg         with the accent
    wordmark.svg           one color
    wordmark-color.svg     with the accent
    preview.png            the sheet shown above
```

The SVGs draw everything as paths, so no font is needed. The preview
sheets' labels use JetBrains Mono.

## After picking

Tell Claude which one, for example "go with option 1". The pick will then
be applied:

- the icon and wordmark at the top of the README
- `icon.svg` at the repo root, for the marketplace listing later
- the other two options moved out of the way
