#!/usr/bin/env python3
"""diagnose.py - Check Nanoleaf lightstrip connection and list USB HID devices"""

import hid

TARGET_VID = 0x37FA

print("=== Nanoleaf Device Scan ===\n")

found = False
for d in hid.enumerate():
    if d['vendor_id'] == TARGET_VID:
        found = True
        print(f"Found Nanoleaf device:")
        print(f"  Product:  {d['product_string']}")
        print(f"  VID:      {hex(d['vendor_id'])}")
        print(f"  PID:      {hex(d['pid'])}")
        print(f"  Serial:   {d['serial_number']}")
        print(f"  Manufacturer: {d['manufacturer_string']}")
        print(f"  Path:     {d['path']}")
        print()

if not found:
    print("No Nanoleaf device found (VID 0x37FA).\n")
    print("All USB HID devices:\n")
    for d in hid.enumerate():
        name = d['product_string'] or '(unknown)'
        mfr = d['manufacturer_string'] or '(unknown)'
        print(f"  {mfr} - {name}  VID:{hex(d['vendor_id'])} PID:{hex(d['pid'])}")
    print()
    print("Troubleshooting:")
    print("  - Make sure USB-C cable is plugged in and supports data (not charge-only)")
    print("  - Close Nanoleaf Desktop App: killall 'Nanoleaf Desktop'")
    print("  - Try a different USB-C port")
