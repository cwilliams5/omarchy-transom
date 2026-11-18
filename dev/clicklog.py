#!/usr/bin/env python3
"""Runs inside a test terminal: fills it with a solid color, shows the
window's name, and counts the left clicks the window actually receives
(xterm mouse reporting), appending each to a log file.

    clicklog.py NAME RRGGBB LOGFILE

The color is painted by the program itself, so it works in any terminal
and config.
"""
import os
import re
import signal
import sys
import termios
import tty

name, color, log = sys.argv[1], sys.argv[2], sys.argv[3]
r, g, b = (int(color[i:i + 2], 16) for i in (0, 2, 4))
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
tty.setraw(fd)
out = sys.stdout
clicks = 0


def draw():
    # Paint every cell: not every terminal fills erased cells with the
    # current background color.
    cols, rows = os.get_terminal_size(fd)
    lines = ["", f"  window {name}", "", f"  clicks received: {clicks}"]
    out.write(f"\x1b[H\x1b[48;2;{r};{g};{b}m\x1b[97m")
    for row in range(rows):
        text = lines[row] if row < len(lines) else ""
        out.write(f"\x1b[{row + 1};1H" + text.ljust(cols)[:cols])
    out.flush()


# Repaint when the window is resized (the repro resizes and maximizes it).
signal.signal(signal.SIGWINCH, lambda *_: draw())

try:
    out.write("\x1b[?1000h\x1b[?1006h\x1b[?25l")  # report clicks (SGR), hide cursor
    open(log, "a").close()
    draw()
    buf = b""
    while True:
        buf += os.read(fd, 64)
        if b"\x1b[" not in buf and b"\x1b" not in buf[-1:]:
            buf = b""
        for match in re.finditer(rb"\x1b\[<(\d+);(\d+);(\d+)([Mm])", buf):
            if match.group(4) == b"M" and int(match.group(1)) == 0:
                clicks += 1
                with open(log, "a") as f:
                    f.write(f"{name}\n")
                draw()
        last = buf.rfind(b"\x1b[<")
        tail = buf[last:] if last >= 0 else b""
        buf = tail if tail and not re.match(rb"\x1b\[<\d+;\d+;\d+[Mm]", tail) else b""
finally:
    out.write("\x1b[?1000l\x1b[?1006l\x1b[?25h\x1b[0m")
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
