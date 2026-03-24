#!/usr/bin/env python3
"""nanoleaf.py - Control Nanoleaf PC Screen Mirror Lightstrip via USB HID"""

import sys
import hid

VID = 0x37FA
PID = 0x8202
NUM_ZONES = 9  # default, updated at runtime by detect_zones()

# 预设颜色 (R, G, B)
COLORS = {
    "red":     (255, 0, 0),
    "green":   (0, 255, 0),
    "blue":    (0, 0, 255),
    "white":   (255, 255, 255),
    "warm":    (255, 180, 100),
    "yellow":  (255, 255, 0),
    "cyan":    (0, 255, 255),
    "magenta": (255, 0, 255),
    "orange":  (255, 100, 0),
    "purple":  (128, 0, 255),
    "pink":    (255, 50, 100),
}

def send(dev, cmd_type, payload=b''):
    length = len(payload)
    msg = bytes([0x00, cmd_type, (length >> 8) & 0xFF, length & 0xFF]) + payload
    dev.write(msg)
    return dev.read(64, timeout=1000)

def connect():
    try:
        dev = hid.Device(vid=VID, pid=PID)
        return dev
    except hid.HIDException:
        print("Error: Cannot connect to Nanoleaf lightstrip.")
        print("Make sure it's plugged in and Nanoleaf Desktop App is closed.")
        sys.exit(1)

def cmd_on(dev):
    send(dev, 0x07, b'\x01')
    print("Turned on")

def cmd_off(dev):
    send(dev, 0x07, b'\x00')
    print("Turned off")

def cmd_brightness(dev, val):
    val = max(0, min(255, int(val)))
    send(dev, 0x09, bytes([val]))
    print(f"Brightness: {val}/255 ({val * 100 // 255}%)")

def detect_zones(dev):
    global NUM_ZONES
    resp = send(dev, 0x03)
    if resp and resp[3] == 0:
        NUM_ZONES = resp[4]

def cmd_color(dev, r, g, b):
    r, g, b = max(0, min(255, int(r))), max(0, min(255, int(g))), max(0, min(255, int(b)))
    # 设备使用 GRB 顺序
    grb = bytes([g, r, b]) * NUM_ZONES
    send(dev, 0x07, b'\x01')
    send(dev, 0x02, grb)
    print(f"Color: RGB({r}, {g}, {b})")

def cmd_preset(dev, name):
    name = name.lower()
    if name not in COLORS:
        print(f"Unknown color: {name}")
        print(f"Available: {', '.join(sorted(COLORS.keys()))}")
        return
    r, g, b = COLORS[name]
    cmd_color(dev, r, g, b)

def cmd_gradient(dev, color1, color2):
    c1 = COLORS.get(color1.lower())
    c2 = COLORS.get(color2.lower())
    if not c1 or not c2:
        print(f"Unknown color. Available: {', '.join(sorted(COLORS.keys()))}")
        return
    send(dev, 0x07, b'\x01')
    grb_data = b''
    for i in range(NUM_ZONES):
        t = i / (NUM_ZONES - 1)
        r = int(c1[0] + (c2[0] - c1[0]) * t)
        g = int(c1[1] + (c2[1] - c1[1]) * t)
        b = int(c1[2] + (c2[2] - c1[2]) * t)
        grb_data += bytes([g, r, b])
    send(dev, 0x02, grb_data)
    print(f"Gradient: {color1} -> {color2}")

def cmd_zones(dev, zone_colors):
    """Set individual zone colors: zone_colors is list of 'R,G,B' strings"""
    send(dev, 0x07, b'\x01')
    grb_data = b''
    for i in range(NUM_ZONES):
        if i < len(zone_colors):
            parts = zone_colors[i].split(',')
            r, g, b = int(parts[0]), int(parts[1]), int(parts[2])
        else:
            r, g, b = 0, 0, 0
        grb_data += bytes([max(0, min(255, g)), max(0, min(255, r)), max(0, min(255, b))])
    send(dev, 0x02, grb_data)
    print(f"Set {min(len(zone_colors), NUM_ZONES)} zones")

def cmd_info(dev):
    resp = send(dev, 0x03)
    zones = resp[4] if resp[3] == 0 else '?'
    print(f"Zones: {zones}")

    resp = send(dev, 0x06)
    state = "On" if resp[4] == 1 else "Off"
    print(f"State: {state}")

    resp = send(dev, 0x08)
    brightness = resp[4]
    print(f"Brightness: {brightness}/255 ({brightness * 100 // 255}%)")

    resp = send(dev, 0x0A)
    if resp[3] == 0:
        fw = resp[4]
        print(f"Firmware: {fw >> 4}.{fw & 0x0F}")

    resp = send(dev, 0x0C)
    if resp[3] == 0:
        model = bytes(resp[4:10]).decode('ascii', errors='ignore')
        print(f"Model: {model}")

def usage():
    print("""Nanoleaf PC Screen Mirror Lightstrip Controller

Usage: nanoleaf.py <command> [args]

Commands:
  on                          Turn on
  off                         Turn off
  brightness <0-255>          Set brightness
  color <R> <G> <B>           Set color (RGB, 0-255 each)
  <color_name>                Set preset color
  gradient <color1> <color2>  Gradient between two preset colors
  zones <R,G,B> <R,G,B> ...  Set each zone individually (up to 9)
  info                        Show device info

Preset colors:
  red, green, blue, white, warm, yellow,
  cyan, magenta, orange, purple, pink

Examples:
  nanoleaf.py red
  nanoleaf.py color 255 100 0
  nanoleaf.py brightness 128
  nanoleaf.py gradient blue purple
  nanoleaf.py zones 255,0,0 0,255,0 0,0,255""")

def main():
    if len(sys.argv) < 2:
        usage()
        return

    cmd = sys.argv[1].lower()
    dev = connect()
    detect_zones(dev)

    try:
        if cmd == "on":
            cmd_on(dev)
        elif cmd == "off":
            cmd_off(dev)
        elif cmd == "brightness":
            cmd_brightness(dev, sys.argv[2])
        elif cmd == "color":
            cmd_color(dev, sys.argv[2], sys.argv[3], sys.argv[4])
        elif cmd == "gradient":
            cmd_gradient(dev, sys.argv[2], sys.argv[3])
        elif cmd == "zones":
            cmd_zones(dev, sys.argv[2:])
        elif cmd == "info":
            cmd_info(dev)
        elif cmd in COLORS:
            cmd_preset(dev, cmd)
        else:
            print(f"Unknown command: {cmd}")
            usage()
    finally:
        dev.close()

if __name__ == "__main__":
    main()
