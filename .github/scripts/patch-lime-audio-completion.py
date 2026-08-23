#!/usr/bin/env python3
"""patch-lime-audio-completion.py - Timer-based sound completion instead of
per-frame polling

lime/_internal/backend/native/NativeAudioSource.hx registers a checkPlay
listener on Application.current.onUpdate for every non-streaming sound
(hitsounds, UI clicks, any short SFX) it plays. checkPlay polls
AL.getSourcei(handle, AL.SOURCE_STATE) -- a native OpenAL call -- on the
MAIN thread, every single frame, for the sound's whole duration, to detect
when it finishes. This is untagged by any of our SystemMonitor profiling
and scales with however many short sounds are overlapping at once (e.g. a
dense note section with hitsoundVolume > 0).

The file already contains a complete, working one-shot Timer-based
completion mechanism (timer_onRun) -- it's just commented out at its three
call sites (setCurrentTime/setPitch/setLength), left in place when
checkPlay was added alongside it. This restores that mechanism and removes
checkPlay entirely, matching upstream lime's (and Psych Engine Mobile's)
original behavior: schedule one Timer for exactly when the sound is
expected to end, instead of asking every frame.

Usage: patch-lime-audio-completion.py <path to NativeAudioSource.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

if "checkPlay" not in content:
    print("Already patched, skipping.")
    sys.exit(0)

edits = [
    (
        "\t\t\tif (Application.current != null && !stream)\n"
        "\t\t\t{\n"
        "\t\t\t\tif (Application.current.onUpdate.has(checkPlay))\n"
        "\t\t\t\t{\n"
        "\t\t\t\t\t// trace('[AUDIO] removed play check event!');\n"
        "\t\t\t\t\tApplication.current.onUpdate.remove(checkPlay);\n"
        "\t\t\t\t}\n"
        "\t\t\t}\n"
        "\t\t\tstop();\n",
        "\t\t\tstop();\n",
    ),
    (
        "\n"
        "\t\tif (Application.current != null && !stream)\n"
        "\t\t{\n"
        "\t\t\tif (!Application.current.onUpdate.has(checkPlay))\n"
        "\t\t\t{\n"
        "\t\t\t\t\t// trace('[AUDIO] added play check event!');\n"
        "\t\t\t\tApplication.current.onUpdate.add(checkPlay);\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\t}\n",
        "\n\t}\n",
    ),
    (
        "\tprivate function checkPlay(_):Void\n"
        "\t{\n"
        "\t\tfinal finished:Bool = AL.getSourcei(handle, AL.SOURCE_STATE) != AL.PLAYING;\n"
        "\n"
        "\t\tif (!finished) return;\n"
        "\t\tif (loops > 0)\n"
        "\t\t{\n"
        "\t\t\tplaying = false;\n"
        "\t\t\tloops--;\n"
        "\t\t\tsetCurrentTime(0);\n"
        "\t\t\tplay();\n"
        "\t\t\treturn;\n"
        "\t\t}\n"
        "\t\telse\n"
        "\t\t{\n"
        "\t\t\tif (!completed)\tstop();\n"
        "\t\t}\n"
        "\n"
        "\t\tif (!completed)\n"
        "\t\t{\n"
        "\t\t\t// trace('[AUDIO] audio finished playing!');\n"
        "\t\t\tparent.onComplete.dispatch();\n"
        "\t\t}\n"
        "\t\tcompleted = true;\n"
        "\t}\n"
        "\n",
        "",
    ),
    (
        "\t\t\t\t// timer = new Timer(timeRemaining);\n"
        "\t\t\t\t// timer.run = timer_onRun;\n",
        "\t\t\t\ttimer = new Timer(timeRemaining);\n"
        "\t\t\t\ttimer.run = timer_onRun;\n",
    ),
    (
        "\t\t\t// var timeRemaining = Std.int((value - getCurrentTime()) / getPitch());\n"
        "\n"
        "\t\t\t// if (timeRemaining > 0)\n"
        "\t\t\t// {\n"
        "\t\t\t// \ttimer = new Timer(timeRemaining);\n"
        "\t\t\t// \ttimer.run = timer_onRun;\n"
        "\t\t\t// }\n",
        "\t\t\tvar timeRemaining = Std.int((value - getCurrentTime()) / getPitch());\n"
        "\n"
        "\t\t\tif (timeRemaining > 0)\n"
        "\t\t\t{\n"
        "\t\t\t\ttimer = new Timer(timeRemaining);\n"
        "\t\t\t\ttimer.run = timer_onRun;\n"
        "\t\t\t}\n",
    ),
    (
        "\t\t\t// var timeRemaining = Std.int((getLength() - getCurrentTime()) / value);\n"
        "\n"
        "\t\t\t// if (timeRemaining > 0)\n"
        "\t\t\t// {\n"
        "\t\t\t// \ttimer = new Timer(timeRemaining);\n"
        "\t\t\t// \ttimer.run = timer_onRun;\n"
        "\t\t\t// }\n",
        "\t\t\tvar timeRemaining = Std.int((getLength() - getCurrentTime()) / value);\n"
        "\n"
        "\t\t\tif (timeRemaining > 0)\n"
        "\t\t\t{\n"
        "\t\t\t\ttimer = new Timer(timeRemaining);\n"
        "\t\t\t\ttimer.run = timer_onRun;\n"
        "\t\t\t}\n",
    ),
]

for i, (old, new) in enumerate(edits):
    count = content.count(old)
    assert count == 1, f"edit {i}: expected exactly 1 match, found {count} -- lime NativeAudioSource.hx changed upstream"
    content = content.replace(old, new, 1)

assert "checkPlay" not in content, "checkPlay still present after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched NativeAudioSource.hx: checkPlay removed, timer-based completion restored")
