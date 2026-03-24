#!/usr/bin/env python3
"""diagnose.py - Check Nanoleaf lightstrip connection and list USB HID devices"""

import hid

TARGET_VID = 0x37FA

print("=== Nanoleaf Device Scan ===\n")

# First, print all keys of the first device to understand the schema
devices = hid.enumerate()
if devices:
    print(f"HID device fields: {list(devices[0].keys())}\n")

found = False
for d in devices:
    if d.get('vendor_id') == TARGET_VID:
        found = True
        print("Found Nanoleaf device:")
        for key, val in d.items():
            if isinstance(val, int) and key.endswith('_id'):
                print(f"  {key}: {hex(val)}")
            else:
                print(f"  {key}: {val}")
        print()

if not found:
    print("No Nanoleaf device found (VID 0x37FA).\n")
    print("All USB HID devices:\n")
    for d in devices:
        vid = hex(d.get('vendor_id', 0))
        pid = hex(d.get('product_id', d.get('pid', 0)))
        name = d.get('product_string', '(unknown)') or '(unknown)'
        mfr = d.get('manufacturer_string', '(unknown)') or '(unknown)'
        print(f"  {mfr} - {name}  VID:{vid} PID:{pid}")
    print()
    print("Troubleshooting:")
    print("  - Make sure USB-C cable is plugged in and supports data (not charge-only)")
    print("  - Close Nanoleaf Desktop App: killall 'Nanoleaf Desktop'")
    print("  - Try a different USB-C port")
