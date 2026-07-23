#!/usr/bin/env python3
"""patch-flixel-animate-element-destroy.py - Make Element.destroy() safe to
call more than once on the same instance.

animate.internal.elements.Element.destroy() (the base class for every
FlxAnimate element -- MovieClipInstance, AtlasInstance, our own
FlxSpriteElement wrapper, etc.) unconditionally releases its two pooled
FlxMatrix fields back to FilterRenderer.matrixPool:

    FilterRenderer.matrixPool.release(_mat);
    _mat = null;
    FilterRenderer.matrixPool.release(matrix);
    matrix = null;

If destroy() ever runs twice on the same element -- confirmed happening
live during normal gameplay via a symbolicated native_crash_trace.log,
independent of anything this codebase's own stage scripts do -- the second
call passes the already-nulled _mat/matrix straight into
matrixPool.release(null). lime.utils.ObjectPool.release() only guards
against a null/foreign object inside "#if debug" (a Log.error call with no
early return even there); in a release build that whole check compiles out,
so release(null) falls straight through to clean(object), i.e.
matrixPool's own clean callback ((m) -> m.identity()) -- calling .identity()
on a null FlxMatrix. That's a null pointer dereference with no Haxe-level
exception to catch it, which is exactly the SIGSEGV this patches.

Guarding both releases with a null check makes destroy() idempotent: a
second call is now a safe no-op for these two fields instead of a crash,
regardless of what upstream in this pinned commit is causing destroy() to
run twice in the first place.

Also logs (funkin.backend.Logger, WARN) whenever a guard actually skips a
release -- a silent guard would hide that something is still calling
destroy() twice (or destroy()ing a never-initialized element); this keeps
that visible in game.log instead of just making the crash go away with no
trace of it.

Usage: patch-flixel-animate-element-destroy.py <path to Element.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "if (_mat != null)"
if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD = (
    "\tpublic function destroy()\n"
    "\t{\n"
    "\t\tFilterRenderer.matrixPool.release(_mat);\n"
    "\t\t_mat = null;\n"
    "\n"
    "\t\tFilterRenderer.matrixPool.release(matrix);\n"
    "\t\tmatrix = null;\n"
    "\n"
    "\t\ttransform = null;\n"
    "\t\t_transform = null;\n"
    "\t\tparentFrame = null;\n"
    "\t\tshader = null;\n"
    "\t\tdrawCommand = FlxDestroyUtil.destroy(drawCommand);\n"
    "\t}\n"
)
NEW = (
    "\tpublic function destroy()\n"
    "\t{\n"
    "\t\t// Guarded so destroy() is safe to call more than once on the same\n"
    "\t\t// element -- releasing an already-null field into matrixPool.release()\n"
    "\t\t// reaches its clean() callback ((m) -> m.identity()) with a null\n"
    "\t\t// FlxMatrix in a release build (the pool's own null/foreign-object\n"
    "\t\t// check only exists under \"#if debug\"), crashing with SIGSEGV instead\n"
    "\t\t// of throwing a catchable exception.\n"
    "\t\tif (_mat != null)\n"
    "\t\t{\n"
    "\t\t\tFilterRenderer.matrixPool.release(_mat);\n"
    "\t\t\t_mat = null;\n"
    "\t\t}\n"
    "\t\telse\n"
    "\t\t{\n"
    "\t\t\tfunkin.backend.Logger.log(\"Element.destroy() guard fired: _mat already null (likely a repeat destroy() call on the same element). Worth tracking down the double-destroy source.\", funkin.backend.Logger.Severity.WARN);\n"
    "\t\t}\n"
    "\n"
    "\t\tif (matrix != null)\n"
    "\t\t{\n"
    "\t\t\tFilterRenderer.matrixPool.release(matrix);\n"
    "\t\t\tmatrix = null;\n"
    "\t\t}\n"
    "\t\telse\n"
    "\t\t{\n"
    "\t\t\tfunkin.backend.Logger.log(\"Element.destroy() guard fired: matrix already null (likely a repeat destroy() call on the same element). Worth tracking down the double-destroy source.\", funkin.backend.Logger.Severity.WARN);\n"
    "\t\t}\n"
    "\n"
    "\t\ttransform = null;\n"
    "\t\t_transform = null;\n"
    "\t\tparentFrame = null;\n"
    "\t\tshader = null;\n"
    "\t\tdrawCommand = FlxDestroyUtil.destroy(drawCommand);\n"
    "\t}\n"
)

count = content.count(OLD)
assert count == 1, f"expected exactly 1 match for Element.destroy(), found {count} -- flixel-animate changed upstream"

content = content.replace(OLD, NEW, 1)
assert MARKER in content, "null-guard marker still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched Element.hx: destroy() now guards its two matrixPool.release() calls against already-null fields")
