#!/usr/bin/env python3
"""patch-lime-objectpool-release-guard.py - Make ObjectPool.release() safe
to call with a null/foreign object in ALL builds, not just #if debug.

lime.utils.ObjectPool<T>.release() only checks for a null or untracked
object inside "#if debug" -- and even there it's a Log.error() call with no
early return, so the check never actually stops execution even in a debug
build. In a release build the whole check compiles out entirely, so
release(null) (or release() on an object this pool never gave out) falls
straight through to clean(object) and __addInactive(object).

For FilterRenderer.matrixPool/cameraPool (flixel-animate), clean is
(m) -> m.identity() / (c) -> c -- calling .identity() on a null FlxMatrix
is a null pointer dereference with no Haxe-level exception to catch it.
We already patched ONE known caller of this (flixel-animate's
Element.destroy(), via patch-flixel-animate-element-destroy.py), but that
only protects that specific call site -- any other caller that releases a
null/already-released object hits the exact same crash. Confirmed via a
symbolicated native_crash_trace.log landing inside FilterRenderer's own
internal renderToBitmap()/matrixPool.get()/release() pair, independent of
Element.destroy() entirely.

Fixing ObjectPool.release() itself closes this off for every caller at
once instead of patching call sites one at a time.

Also logs (funkin.backend.Logger, WARN) every time the guard actually
skips a release -- a silent guard would hide the fact that something
upstream is still calling release() incorrectly; this keeps that visible
in game.log for whoever investigates next, instead of just making the
crash go away with no trace of the underlying bug.

Usage: patch-lime-objectpool-release-guard.py <path to lime/utils/ObjectPool.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "// Guarded so release() is safe"
if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD = (
    "\tpublic function release(object:T):Void\n"
    "\t{\n"
    "\t\t#if debug\n"
    "\t\tif (object == null || !__pool.exists(object))\n"
    "\t\t{\n"
    "\t\t\tLog.error(\"Object is not a member of the pool\");\n"
    "\t\t}\n"
    "\t\telse if (!__pool.get(object))\n"
    "\t\t{\n"
    "\t\t\tLog.error(\"Object has already been released\");\n"
    "\t\t}\n"
    "\t\t#end\n"
    "\n"
    "\t\tactiveObjects--;\n"
    "\n"
    "\t\tif (__size == null || activeObjects + inactiveObjects < __size)\n"
    "\t\t{\n"
    "\t\t\tclean(object);\n"
    "\t\t\t__addInactive(object);\n"
    "\t\t}\n"
    "\t\telse\n"
    "\t\t{\n"
    "\t\t\t__pool.remove(object);\n"
    "\t\t}\n"
    "\t}\n"
)
NEW = (
    "\tpublic function release(object:T):Void\n"
    "\t{\n"
    "\t\t// Guarded so release() is safe to call with a null or untracked\n"
    "\t\t// object in every build, not just #if debug -- letting it through\n"
    "\t\t// reaches clean(object) (e.g. FilterRenderer.matrixPool's\n"
    "\t\t// (m) -> m.identity()) with a null/foreign object, a null pointer\n"
    "\t\t// dereference with no catchable exception, instead of a no-op.\n"
    "\t\tif (object == null || !__pool.exists(object))\n"
    "\t\t{\n"
    "\t\t\t#if debug\n"
    "\t\t\tLog.error(\"Object is not a member of the pool\");\n"
    "\t\t\t#end\n"
    "\t\t\tfunkin.backend.Logger.log(\"ObjectPool.release() guard fired: skipped releasing a null/untracked object (would have crashed in clean()). Something upstream is still calling release() incorrectly -- worth tracking down.\", funkin.backend.Logger.Severity.WARN);\n"
    "\t\t\treturn;\n"
    "\t\t}\n"
    "\n"
    "\t\t#if debug\n"
    "\t\tif (!__pool.get(object))\n"
    "\t\t{\n"
    "\t\t\tLog.error(\"Object has already been released\");\n"
    "\t\t}\n"
    "\t\t#end\n"
    "\n"
    "\t\tactiveObjects--;\n"
    "\n"
    "\t\tif (__size == null || activeObjects + inactiveObjects < __size)\n"
    "\t\t{\n"
    "\t\t\tclean(object);\n"
    "\t\t\t__addInactive(object);\n"
    "\t\t}\n"
    "\t\telse\n"
    "\t\t{\n"
    "\t\t\t__pool.remove(object);\n"
    "\t\t}\n"
    "\t}\n"
)

count = content.count(OLD)
assert count == 1, f"expected exactly 1 match for ObjectPool.release(), found {count} -- lime changed upstream"

content = content.replace(OLD, NEW, 1)
assert MARKER in content, "guard marker still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched ObjectPool.hx: release() now guards against null/untracked objects in all builds")
