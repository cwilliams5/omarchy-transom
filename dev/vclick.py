#!/usr/bin/env python3
"""Move the pointer and left-click, through the zwlr_virtual_pointer_v1
Wayland protocol (which Hyprland supports). No dependencies beyond Python:
it speaks the Wayland wire protocol directly.

    vclick.py X Y WIDTH HEIGHT [--move-only]
    vclick.py --click-here          (left-click wherever the pointer is)

X, Y: where to click, in layout pixels. WIDTH, HEIGHT: the size of the whole
layout (all monitors); the pointer starts from its top-left corner. Uses
$WAYLAND_DISPLAY, so it can drive a nested compositor too.
"""
import os
import socket
import struct
import sys
import time

BTN_LEFT = 0x110


def pad(b):
    return b + b"\0" * (-len(b) % 4)


def string(s):
    raw = s.encode() + b"\0"
    return struct.pack("<I", len(raw)) + pad(raw)


class Wayland:
    def __init__(self):
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.next_id = 2
        self.buf = b""

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj, opcode, payload=b""):
        self.sock.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | opcode) + payload)

    def events(self):
        while True:
            while len(self.buf) >= 8:
                obj, word = struct.unpack("<II", self.buf[:8])
                size, opcode = word >> 16, word & 0xFFFF
                if len(self.buf) < size:
                    break
                body, self.buf = self.buf[8:size], self.buf[size:]
                yield obj, opcode, body
            chunk = self.sock.recv(65536)
            if not chunk:
                return
            self.buf += chunk

    def roundtrip(self, on_event=None):
        callback = self.new_id()
        self.send(1, 0, struct.pack("<I", callback))  # wl_display.sync
        for obj, opcode, body in self.events():
            if obj == 1 and opcode == 0:  # wl_display.error
                oid, code = struct.unpack("<II", body[:8])
                raise SystemExit(f"wayland error on object {oid}, code {code}: {body[12:].rstrip(b'\0').decode()}")
            if obj == callback and opcode == 0:
                return
            if on_event:
                on_event(obj, opcode, body)


def main():
    click_here = "--click-here" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if click_here:
        args = ["0", "0", "1", "1"]
    if len(args) != 4:
        raise SystemExit(__doc__)
    x, y, width, height = (int(float(a)) for a in args)
    move_only = "--move-only" in sys.argv

    wl = Wayland()
    registry = wl.new_id()
    wl.send(1, 1, struct.pack("<I", registry))  # wl_display.get_registry

    found = {}

    def on_global(obj, opcode, body):
        if obj == registry and opcode == 0:  # wl_registry.global
            name, length = struct.unpack("<II", body[:8])
            interface = body[8:8 + length - 1].decode()
            (version,) = struct.unpack("<I", body[8 + len(pad(body[8:8 + length])):][:4])
            found[interface] = (name, version)

    wl.roundtrip(on_global)
    if "zwlr_virtual_pointer_manager_v1" not in found:
        raise SystemExit("this compositor has no zwlr_virtual_pointer_manager_v1")
    name, version = found["zwlr_virtual_pointer_manager_v1"]

    manager = wl.new_id()
    wl.send(registry, 0, struct.pack("<I", name) + string("zwlr_virtual_pointer_manager_v1")
            + struct.pack("<II", min(version, 2), manager))  # wl_registry.bind
    pointer = wl.new_id()
    wl.send(manager, 0, struct.pack("<II", 0, pointer))  # create_virtual_pointer(seat=null)

    def now():
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    # Absolute motion to the top-left corner, then relative motion to the
    # target, the way a real mouse moves. (Absolute coordinates alone land
    # wrong on a scaled screen: Hyprland 0.56 maps them onto
    # width/scale x height/scale, so half of a 2x screen is unreachable.)
    if not click_here:
        wl.send(pointer, 1, struct.pack("<IIIII", now(), 0, 0, width, height))  # motion_absolute
        wl.send(pointer, 4)  # frame
        wl.roundtrip()
    remaining_x, remaining_y = (0, 0) if click_here else (x, y)
    while remaining_x or remaining_y:  # small steps, like a real mouse
        dx = max(-40, min(40, remaining_x))
        dy = max(-40, min(40, remaining_y))
        wl.send(pointer, 0, struct.pack("<Iii", now(), dx * 256, dy * 256))  # motion (wl_fixed)
        wl.send(pointer, 4)
        remaining_x -= dx
        remaining_y -= dy
        time.sleep(0.004)
    wl.roundtrip()
    if not move_only:
        time.sleep(0.15)
        wl.send(pointer, 2, struct.pack("<III", now(), BTN_LEFT, 1))  # button pressed
        wl.send(pointer, 4)
        wl.roundtrip()
        time.sleep(0.08)
        wl.send(pointer, 2, struct.pack("<III", now(), BTN_LEFT, 0))  # button released
        wl.send(pointer, 4)
        wl.roundtrip()
    wl.send(pointer, 8)  # destroy
    wl.roundtrip()


if __name__ == "__main__":
    main()
