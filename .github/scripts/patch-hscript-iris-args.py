#!/usr/bin/env python3
"""patch-hscript-iris-args.py - Reuse a shared empty array for zero-arg script calls

crowplexus/iris/Iris.hx's call() allocates a fresh empty Array<Dynamic> on
every invocation made with no arguments (`if (args == null) args = [];`).
Every zero-arg script hook this codebase fires -- onUpdate, onBeatHit,
onStepHit, onSectionHit, onDestroy, etc, many times per frame across every
loaded mod/chart script -- takes this path, so it's a real per-frame
allocation source independent of note/spawn events.

Same idea and same safety argument as the existing _emptyExclusions pattern
in source/funkin/scripts/ScriptGroup.hx: a shared static empty array is safe
here because nothing downstream mutates `args` in place for the zero-param
case. crowplexus/hscript/Interp.hx's function-call handling only ever
reassigns `args` to a brand new local array when padding it for optional
parameters (`args = args2;`), it never pushes/writes into the array it was
given -- so the shared instance can't leak a mutation between callers.

Deliberately anchored on call()'s own function signature line rather than
the doc comment above it or the `if (args == null)` body it shares a file
with patch-hscript-iris-call.py -- that script's edits land immediately
above this same doc comment, and matching there too would make the two
scripts' insertion order matter (whichever runs second would fail its exact
match). The signature line itself is untouched by that script, so this
patch is safe to run before or after it.

This script must stay idempotent: CI's "Cache Haxe libraries" step persists
.haxelib across runs, so a checkout already patched by an earlier run can
come back from cache on a later run.

Usage: patch-hscript-iris-args.py <path to Iris.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "_emptyArgs"

if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD_SIG = "\tpublic function call(fun: String, ?args: Array<Dynamic>): IrisCall {\n"
NEW_SIG = (
    "\t// Reused by call() below instead of allocating a fresh empty Array on\n"
    "\t// every zero-arg script call. Safe: nothing downstream mutates `args` in\n"
    "\t// place for the zero-param case (see Interp.hx's function-call handling).\n"
    "\tstatic final _emptyArgs: Array<Dynamic> = [];\n"
    "\n"
    + OLD_SIG
)

OLD_ARGS_CHECK = (
    "\t\tif (args == null)\n"
    "\t\t\targs = [];\n"
)
NEW_ARGS_CHECK = (
    "\t\tif (args == null)\n"
    "\t\t\targs = _emptyArgs;\n"
)

edits = [
    (OLD_SIG, NEW_SIG),
    (OLD_ARGS_CHECK, NEW_ARGS_CHECK),
]

for i, (old, new) in enumerate(edits):
    count = content.count(old)
    assert count == 1, f"edit {i}: expected exactly 1 match, found {count} -- hscript-iris Iris.hx changed upstream"
    content = content.replace(old, new, 1)

with open(path, 'w') as f:
    f.write(content)

print("Patched Iris.hx: call() reuses a shared empty array for zero-arg calls instead of allocating one per call")
