#!/usr/bin/env python3
"""patch-hscript-iris-call.py - Reuse the IrisCall result object instead of
allocating a fresh one on every script call

crowplexus/iris/Iris.hx's call() -- the method ScriptGroup.call() invokes for
every hook on every loaded mod script (onUpdate, onBeatHit, note-hit events,
etc, many times per frame) -- allocates a brand new @:structInit IrisCall
instance on every single invocation just to carry back three fields.

ScriptGroup.call() (source/funkin/scripts/ScriptGroup.hx) is the only caller
in this codebase, and it reads the result synchronously in the same
expression (`i.call(event, args)?.returnValue`), never retaining the
IrisCall object past that statement. That makes it safe to reuse a single
instance field and mutate it in place instead of constructing a new one each
time -- same idea already used for GlobalScriptManager's `_updateArgs`.

Usage: patch-hscript-iris-call.py <path to Iris.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

if "_reusableCall" in content:
    print("Already patched, skipping.")
    sys.exit(0)

edits = [
    (
        "\tif (allowOverride || !interp.variables.exists(name))\n"
        "\t\t\tinterp.variables.set(name, value);\n"
        "\t}\n"
        "\n"
        "\t/**\n"
        "\t * Calls a method on the script\n",
        "\tif (allowOverride || !interp.variables.exists(name))\n"
        "\t\t\tinterp.variables.set(name, value);\n"
        "\t}\n"
        "\n"
        "\t// Reused by call() below instead of allocating a fresh IrisCall instance\n"
        "\t// every invocation. Safe as long as callers read the result synchronously\n"
        "\t// and don't retain it across a later call() on this same Iris instance\n"
        "\t// (true of every caller in NightmareVision-Android-Support as of this\n"
        "\t// patch: ScriptGroup.call() extracts .returnValue in the same expression).\n"
        "\tvar _reusableCall: IrisCall = {funName: \"\", signature: null, returnValue: null};\n"
        "\n"
        "\t/**\n"
        "\t * Calls a method on the script\n",
    ),
    (
        "\t\t\tfinal ret = Reflect.callMethod(null, ny, args);\n"
        "\t\t\treturn {funName: fun, signature: ny, returnValue: ret};\n",
        "\t\t\tfinal ret = Reflect.callMethod(null, ny, args);\n"
        "\t\t\t_reusableCall.funName = fun;\n"
        "\t\t\t_reusableCall.signature = ny;\n"
        "\t\t\t_reusableCall.returnValue = ret;\n"
        "\t\t\treturn _reusableCall;\n",
    ),
]

for i, (old, new) in enumerate(edits):
    count = content.count(old)
    assert count == 1, f"edit {i}: expected exactly 1 match, found {count} -- hscript-iris Iris.hx changed upstream"
    content = content.replace(old, new, 1)

assert "_reusableCall" in content, "_reusableCall still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched Iris.hx: call() reuses a single IrisCall instance instead of allocating one per call")
