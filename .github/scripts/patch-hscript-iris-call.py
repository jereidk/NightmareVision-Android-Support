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

IMPORTANT: the field must be lazily created *inside* call(), not given a
class-level default-value initializer. Every real script instance in this
codebase is actually an IrisEx/FunkinScript, and IrisEx.new() never really
calls `super(...)` -- it's hidden behind an `if (false == true) super(...)`
so the compiler's "must call super" check is satisfied without the parent
constructor's body (including its field initializers) ever running. A
class-level `var _reusableCall: IrisCall = {...};` on Iris silently stays
null forever for every script in the game, so call() would write into a
null object on its very first real invocation. Confirmed by reproducing the
exact pattern standalone (Haxe/Neko): the field is null post-construction
and mutating it throws. Lazy-init sidesteps the constructor chain entirely
since it runs from inside the method body, which always executes regardless
of how the instance was constructed.

This script must stay idempotent AND upgrade-safe: CI's "Cache Haxe
libraries" step persists .haxelib across runs, so a checkout patched by an
older/buggy version of this script (the class-level-initializer version
above) can come back from cache on a later run. A naive "does _reusableCall
already appear anywhere" check would treat that stale buggy patch as
"already done" and silently leave the null-field bug in place -- which is
exactly what happened once already. So three states are handled explicitly:
pristine (apply the full patch), already on the current lazy-init patch
(skip), or carrying the old buggy patch (upgrade it in place).

Usage: patch-hscript-iris-call.py <path to Iris.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

LAZY_INIT_MARKER = "if (_reusableCall == null)"

OLD_FIELD = (
    "\t// Reused by call() below instead of allocating a fresh IrisCall instance\n"
    "\t// every invocation. Safe as long as callers read the result synchronously\n"
    "\t// and don't retain it across a later call() on this same Iris instance\n"
    "\t// (true of every caller in NightmareVision-Android-Support as of this\n"
    "\t// patch: ScriptGroup.call() extracts .returnValue in the same expression).\n"
    "\tvar _reusableCall: IrisCall = {funName: \"\", signature: null, returnValue: null};\n"
)
NEW_FIELD = (
    "\t// Reused by call() below instead of allocating a fresh IrisCall instance\n"
    "\t// every invocation. Safe as long as callers read the result synchronously\n"
    "\t// and don't retain it across a later call() on this same Iris instance\n"
    "\t// (true of every caller in NightmareVision-Android-Support as of this\n"
    "\t// patch: ScriptGroup.call() extracts .returnValue in the same expression).\n"
    "\t// Left uninitialized here on purpose -- lazily created on first use inside\n"
    "\t// call() itself, since IrisEx (every real script in this codebase) never\n"
    "\t// actually runs Iris's own constructor body, so a field initializer here\n"
    "\t// would never execute and this would stay null forever.\n"
    "\tvar _reusableCall: IrisCall = null;\n"
)

OLD_CALL_BODY = (
    "\t\t\tfinal ret = Reflect.callMethod(null, ny, args);\n"
    "\t\t\t_reusableCall.funName = fun;\n"
    "\t\t\t_reusableCall.signature = ny;\n"
    "\t\t\t_reusableCall.returnValue = ret;\n"
    "\t\t\treturn _reusableCall;\n"
)
NEW_CALL_BODY = (
    "\t\t\tfinal ret = Reflect.callMethod(null, ny, args);\n"
    "\t\t\tif (_reusableCall == null)\n"
    "\t\t\t\t_reusableCall = {funName: fun, signature: ny, returnValue: ret};\n"
    "\t\t\telse {\n"
    "\t\t\t\t_reusableCall.funName = fun;\n"
    "\t\t\t\t_reusableCall.signature = ny;\n"
    "\t\t\t\t_reusableCall.returnValue = ret;\n"
    "\t\t\t}\n"
    "\t\t\treturn _reusableCall;\n"
)

if LAZY_INIT_MARKER in content:
    print("Already patched with the current (lazy-init) fix, skipping.")
    sys.exit(0)

if OLD_FIELD in content:
    print("Found the old buggy (class-level-initializer) patch from a stale cache -- upgrading in place.")
    assert content.count(OLD_FIELD) == 1, "expected exactly 1 match for the old field declaration"
    assert content.count(OLD_CALL_BODY) == 1, "expected exactly 1 match for the old call() body"
    content = content.replace(OLD_FIELD, NEW_FIELD, 1)
    content = content.replace(OLD_CALL_BODY, NEW_CALL_BODY, 1)

    assert LAZY_INIT_MARKER in content, "lazy-init marker still missing after upgrade"

    with open(path, 'w') as f:
        f.write(content)

    print("Upgraded Iris.hx: call() now lazily creates its reused IrisCall instance instead of relying on a field initializer")
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
        + NEW_FIELD +
        "\n"
        "\t/**\n"
        "\t * Calls a method on the script\n",
    ),
    (
        "\t\t\tfinal ret = Reflect.callMethod(null, ny, args);\n"
        "\t\t\treturn {funName: fun, signature: ny, returnValue: ret};\n",
        NEW_CALL_BODY,
    ),
]

for i, (old, new) in enumerate(edits):
    count = content.count(old)
    assert count == 1, f"edit {i}: expected exactly 1 match, found {count} -- hscript-iris Iris.hx changed upstream"
    content = content.replace(old, new, 1)

assert LAZY_INIT_MARKER in content, "_reusableCall lazy-init still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched Iris.hx: call() reuses a single IrisCall instance instead of allocating one per call")
