#!/usr/bin/env python3
"""patch-lime-audio-resampler.py - Cheaper OpenAL resampler for Android

lime/media/AudioManager.hx generates an OpenAL-Soft config for
windows/mac/linux/android/ios using resampler=fast_bsinc24 -- one of the
most expensive resamplers OpenAL-Soft offers (confirmed against its own
alsoftrc.sample docs: only bsinc48 costs more). It runs continuously on
OpenAL's own mixer thread for the whole session, invisible to our
SystemMonitor profiling (which only measures the main thread), and our
44.1kHz assets almost certainly get resampled against the device's native
mixing rate on real hardware.

Switches to `linear` on Android specifically; desktop/iOS keep
fast_bsinc24 unchanged.

Usage: patch-lime-audio-resampler.py <path to AudioManager.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

if "resampler=linear" in content:
    print("Already patched, skipping.")
    sys.exit(0)

old = "\t\talConfig.push('resampler=fast_bsinc24');\n"
new = (
    "\t\t#if android\n"
    "\t\talConfig.push('resampler=linear');\n"
    "\t\t#else\n"
    "\t\talConfig.push('resampler=fast_bsinc24');\n"
    "\t\t#end\n"
)

assert old in content, "pattern not found -- lime AudioManager.hx changed upstream"
content = content.replace(old, new, 1)

with open(path, 'w') as f:
    f.write(content)

print("Patched AudioManager.hx: resampler=linear on Android")
