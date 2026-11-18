#!/usr/bin/env python3
"""Builds Transom's three branding options: icon and wordmark SVGs (single
color, `currentColor`, so they can follow a theme), a two-color version, and
a preview sheet per option rendered to PNG with rsvg-convert.

    python3 branding/build.py

Everything is drawn from paths here, so no font is needed except for the
preview sheets' labels.
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent

# ------------------------------------------------------------------ letters
# Monoline lowercase on a 40-unit x-height (baseline y=60, x-height y=20).
# Each returns (path data, advance width) for a letter starting at x.

def t(x):
    return (f"M{x+10} 6 V48 A12 12 0 0 0 {x+22} 60 M{x} 22 H{x+23}", 26)

def r(x):
    return (f"M{x} 22 V60 M{x} 38 A18 18 0 0 1 {x+18} 20 H{x+22}", 26)

def a(x):
    return (f"M{x+40} 40 A20 20 0 1 0 {x} 40 A20 20 0 1 0 {x+40} 40 Z M{x+40} 22 V60", 44)

def n(x):
    return (f"M{x} 22 V60 M{x} 38 A16 16 0 0 1 {x+32} 38 V60", 36)

def s(x):
    return (f"M{x+27} 25 C{x+24} 21 {x+19} 20 {x+14} 20 C{x+7} 20 {x+2} 24 {x+2} 30 "
            f"C{x+2} 36 {x+9} 38 {x+15} 40 C{x+21} 42 {x+28} 44 {x+28} 51 "
            f"C{x+28} 57 {x+22} 60 {x+14} 60 C{x+8} 60 {x+3} 58 {x+1} 54", 32)

def o(x):
    return (f"M{x+40} 40 A20 20 0 1 0 {x} 40 A20 20 0 1 0 {x+40} 40 Z", 44)

def o_window(x):
    # A rounded square with a mullion and transom: a window for an "o".
    return (f"M{x+6} 20 H{x+34} A6 6 0 0 1 {x+40} 26 V54 A6 6 0 0 1 {x+34} 60 H{x+6} "
            f"A6 6 0 0 1 {x} 54 V26 A6 6 0 0 1 {x+6} 20 Z M{x} 49 H{x+40}", 44)

def m(x):
    return (f"M{x} 22 V60 M{x} 36 A13 13 0 0 1 {x+26} 36 V60 M{x+26} 36 A13 13 0 0 1 {x+52} 36 V60", 52)

def word(letters, x=8, gap=10):
    parts = []
    for letter in letters:
        d, w = letter(x)
        parts.append(d)
        x += w + gap
    return " ".join(parts), x - gap

# Monoline capitals on a 40-unit cap height (y=20..60), for option 2.
def T(x):  return (f"M{x} 20 H{x+30} M{x+15} 20 V60", 30)
def R(x):  return (f"M{x} 60 V20 H{x+16} A10 10 0 0 1 {x+16} 40 H{x} M{x+14} 40 L{x+28} 60", 28)
def A(x):  return (f"M{x} 60 L{x+16} 20 L{x+32} 60 M{x+6} 46 H{x+26}", 32)
def N(x):  return (f"M{x} 60 V20 L{x+28} 60 V20", 28)
def S(x):  return (f"M{x+26} 26 C{x+23} 21 {x+18} 20 {x+13} 20 C{x+6} 20 {x+1} 24 {x+1} 30 "
                   f"C{x+1} 37 {x+8} 38 {x+14} 40 C{x+20} 42 {x+27} 44 {x+27} 51 "
                   f"C{x+27} 57 {x+21} 60 {x+13} 60 C{x+7} 60 {x+2} 58 {x} 54", 28)
def O(x):  return (f"M{x+40} 40 A20 20 0 1 0 {x} 40 A20 20 0 1 0 {x+40} 40 Z", 40)
def M(x):  return (f"M{x} 60 V20 L{x+18} 46 L{x+36} 20 V60", 36)

# -------------------------------------------------------------------- icons
# 64x64, drawn to read at 16px. Lines in currentColor; the accent part in
# var(--accent, currentColor), so one-color use just works.

ICONS = {
    "crossbar": """
  <rect x="8" y="8" width="48" height="48" rx="7" fill="none" stroke="currentColor" stroke-width="4"/>
  <path d="M32 8 V42 M8 25 H56" fill="none" stroke="currentColor" stroke-width="3.5"/>
  <path d="M6 41 H58 V49 A9 9 0 0 1 49 58 H15 A9 9 0 0 1 6 49 Z" fill="var(--accent, currentColor)"/>""",
    "fanlight": """
  <path d="M8 44 A24 24 0 0 1 56 44" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round"/>
  <path d="M23 44 A9 9 0 0 1 41 44" fill="none" stroke="currentColor" stroke-width="3"/>
  <path d="M24.2 39.5 L13.2 33.2 M27.5 36.2 L21.2 25.2 M32 35 V22.5 M36.5 36.2 L42.8 25.2 M39.8 39.5 L50.8 33.2" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/>
  <rect x="4" y="47" width="56" height="9" rx="4.5" fill="var(--accent, currentColor)"/>""",
    "tbar": """
  <rect x="6" y="10" width="52" height="16" rx="8" fill="none" stroke="currentColor" stroke-width="4"/>
  <circle cx="20" cy="18" r="3" fill="var(--accent, currentColor)"/>
  <circle cx="32" cy="18" r="3" fill="var(--accent, currentColor)"/>
  <circle cx="44" cy="18" r="3" fill="var(--accent, currentColor)"/>
  <path d="M32 26 V56" fill="none" stroke="currentColor" stroke-width="9" stroke-linecap="round"/>""",
}

# ----------------------------------------------------------------- options

OPTIONS = [
    {
        "slug": "crossbar",
        "picked": True,
        "name": "Crossbar",
        "icon": "crossbar",
        "letters": [t, r, a, n, s, o, m],
        "stroke": 7,
        "underline": True,
        "palette": [("Slate", "#2E3440", "background"), ("Glass", "#88C0D0", "accent"),
                    ("Amber", "#EBCB8B", "highlight"), ("Snow", "#ECEFF4", "text")],
    },
    {
        "slug": "alternatives/fanlight",
        "name": "Fanlight",
        "icon": "fanlight",
        "letters": [T, R, A, N, S, O, M],
        "stroke": 4,
        "gap": 16,
        "underline": False,
        "palette": [("Charcoal", "#22201E", "background"), ("Brass", "#C8A24A", "accent"),
                    ("Brick", "#A0503C", "highlight"), ("Limestone", "#EAE4D6", "text")],
    },
    {
        "slug": "alternatives/tbar",
        "name": "T-bar",
        "icon": "tbar",
        "letters": [t, r, a, n, s, o_window, m],
        "stroke": 9,
        "underline": False,
        "palette": [("Midnight", "#0B1220", "background"), ("Sky", "#38BDF8", "accent"),
                    ("Mint", "#34D399", "highlight"), ("Paper", "#F8FAFC", "text")],
    },
]


def icon_svg(body, size=64, color=None, accent=None):
    style = ""
    if color or accent:
        style = f' style="color:{color or "currentColor"};--accent:{accent or color or "currentColor"}"'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="{size}" height="{size}"{style}>'
            f'{resolve_accent(body, accent or color)}\n</svg>\n')


def resolve_accent(body, accent):
    # rsvg doesn't do CSS variables; spell the accent out when one is given.
    return body.replace("var(--accent, currentColor)", accent or "currentColor")


def wordmark(option):
    gap = option.get("gap", 10)
    d, width = word(option["letters"], gap=gap)
    stroke = option["stroke"]
    under = ""
    height = 72
    if option["underline"]:
        under = f'<path d="M8 76 H{width}" stroke="ACCENT" stroke-width="{stroke + 1}" stroke-linecap="round"/>'
        height = 86
    return d, width + 8, height, stroke, under


def wordmark_svg(option, color="currentColor", accent="currentColor"):
    d, width, height, stroke, under = wordmark(option)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width * 2}" height="{height * 2}">'
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'{under.replace("ACCENT", accent)}</svg>\n')


def sheet_svg(option):
    """A 1200x760 preview: icon big, icon small sizes, wordmark on dark and
    light, the palette, the icon as a start button on a bar, and the
    one-color icon in several theme colors."""
    pal = {role: hexv for _, hexv, role in option["palette"]}
    bg, accent, hi, text = pal["background"], pal["accent"], pal["highlight"], pal["text"]
    body = ICONS[option["icon"]]
    d, ww, wh, stroke, under = wordmark(option)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="760" viewBox="0 0 1200 760" '
           f'font-family="JetBrainsMono Nerd Font, Liberation Mono, monospace">',
           f'<rect width="1200" height="760" fill="{bg}"/>']
    # Big icon
    out.append(f'<g transform="translate(60 60) scale(5)" style="color:{text}">{resolve_accent(body, accent)}</g>')
    # Small sizes
    x = 420
    for size in (64, 32, 24, 16):
        out.append(f'<g transform="translate({x} {60 + (64 - size)}) scale({size / 64})" style="color:{text}">{resolve_accent(body, accent)}</g>')
        out.append(f'<text x="{x}" y="150" fill="{text}" opacity="0.6" font-size="13">{size}px</text>')
        x += size + 40
    # Wordmark on dark
    scale = 560 / ww
    out.append(f'<g transform="translate(420 190) scale({scale:.3f})">'
               f'<path d="{d}" fill="none" stroke="{text}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round"/>'
               f'{under.replace("ACCENT", accent)}</g>')
    # Light panel with wordmark and icon in background color
    out.append(f'<rect x="60" y="420" width="520" height="150" rx="14" fill="{text}"/>')
    out.append(f'<g transform="translate(90 455) scale(1.25)" style="color:{bg}">{resolve_accent(body, accent)}</g>')
    s2 = 340 / ww
    out.append(f'<g transform="translate(200 {470 - 10 * s2:.1f}) scale({s2:.3f})">'
               f'<path d="{d}" fill="none" stroke="{bg}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round"/>'
               f'{under.replace("ACCENT", accent)}</g>')
    # Palette
    x = 620
    for name, hexv, role in option["palette"]:
        out.append(f'<rect x="{x}" y="420" width="120" height="96" rx="12" fill="{hexv}" stroke="{text}" stroke-opacity="0.25"/>')
        out.append(f'<text x="{x}" y="540" fill="{text}" font-size="15">{name}</text>')
        out.append(f'<text x="{x}" y="560" fill="{text}" opacity="0.7" font-size="13">{hexv}</text>')
        out.append(f'<text x="{x}" y="578" fill="{text}" opacity="0.5" font-size="13">{role}</text>')
        x += 135
    # A bar with the icon as the start button
    out.append(f'<rect x="0" y="690" width="1200" height="70" fill="#000" opacity="0.35"/>')
    out.append(f'<g transform="translate(24 703) scale(0.69)" style="color:{text}">{resolve_accent(body, accent)}</g>')
    for i, w in enumerate((210, 210, 210)):
        bx = 300 + i * 220
        out.append(f'<rect x="{bx}" y="702" width="{w}" height="46" rx="8" fill="{text}" opacity="{0.16 if i == 1 else 0.06}"/>')
        out.append(f'<rect x="{bx + 14}" y="716" width="18" height="18" rx="4" fill="{text}" opacity="0.5"/>')
        out.append(f'<rect x="{bx + 44}" y="721" width="{w - 70}" height="8" rx="4" fill="{text}" opacity="0.45"/>')
    out.append(f'<rect x="{300 + 220 + 20}" y="744" width="170" height="4" rx="2" fill="{accent}"/>')
    # One-color icon following theme colors
    x = 60
    out.append(f'<text x="60" y="618" fill="{text}" opacity="0.6" font-size="13">one color, following themes:</text>')
    for color in ("#F8F8F2", "#A6E3A1", "#7AA2F7", "#EBDBB2", "#F5C2E7", "#E0DEF4", "#1E1E2E"):
        out.append(f'<rect x="{x}" y="630" width="48" height="48" rx="8" fill="{"#E6E6E6" if color == "#1E1E2E" else "#16161E"}"/>')
        out.append(f'<g transform="translate({x + 8} 638) scale(0.5)" style="color:{color}">{resolve_accent(body, color)}</g>')
        x += 58
    out.append(f'<text x="1140" y="660" text-anchor="end" fill="{text}" font-size="34" opacity="0.9">{option["name"]}</text>')
    out.append('</svg>\n')
    return "\n".join(out)


def lockup_svg(option, text, accent):
    """The icon and the wordmark side by side, for the README's header."""
    body = resolve_accent(ICONS[option["icon"]], accent)
    d, ww, wh, stroke, under = wordmark(option)
    scale = 64 / 86  # the wordmark's height (with its bar) matched to the icon's
    width = 64 + 18 + ww * scale
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} 64" width="{width * 3:.0f}" height="192">'
            f'<g style="color:{text}">{body}</g>'
            f'<g transform="translate(82 2) scale({scale:.4f})">'
            f'<path d="{d}" fill="none" stroke="{text}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'{under.replace("ACCENT", accent)}</g></svg>\n')


def tile_svg(option, background, text, accent):
    """The icon on a rounded tile: an app icon that reads on any background."""
    body = resolve_accent(ICONS[option["icon"]], accent)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="256" height="256">'
            f'<rect width="64" height="64" rx="14" fill="{background}"/>'
            f'<g transform="translate(9 9) scale(0.72)" style="color:{text}">{body}</g></svg>\n')


def main():
    for option in OPTIONS:
        folder = HERE / option["slug"]
        folder.mkdir(parents=True, exist_ok=True)
        body = ICONS[option["icon"]]
        pal = {role: hexv for _, hexv, role in option["palette"]}
        (folder / "icon.svg").write_text(icon_svg(body))
        (folder / "icon-color.svg").write_text(icon_svg(body, color=pal["text"], accent=pal["accent"]))
        (folder / "wordmark.svg").write_text(wordmark_svg(option))
        (folder / "wordmark-color.svg").write_text(wordmark_svg(option, color=pal["text"], accent=pal["accent"]))
        if option.get("picked"):
            (folder / "lockup-dark.svg").write_text(lockup_svg(option, pal["text"], pal["accent"]))
            (folder / "lockup-light.svg").write_text(lockup_svg(option, pal["background"], pal["accent"]))
            (folder / "tile.svg").write_text(tile_svg(option, pal["background"], pal["text"], pal["accent"]))
            # The repo's own icon (marketplace listings, the README).
            (HERE.parent / "icon.svg").write_text(tile_svg(option, pal["background"], pal["text"], pal["accent"]))
        sheet = folder / "preview.svg"
        sheet.write_text(sheet_svg(option))
        subprocess.run(["rsvg-convert", "-w", "1200", "-o", str(folder / "preview.png"), str(sheet)], check=True)
        sheet.unlink()
        print("built", option["slug"])


if __name__ == "__main__":
    main()
