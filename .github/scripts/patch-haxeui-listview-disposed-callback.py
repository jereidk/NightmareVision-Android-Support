#!/usr/bin/env python3
"""patch-haxeui-listview-disposed-callback.py - Guard a deferred callLater
callback against running after its component has been disposed.

haxe.ui.containers.ListView's private DataSourceBehaviour.dispatchChanged()
schedules a callback via Toolkit.callLater() that dereferences _component
(a field inherited from Behaviour) once the callback actually runs, one
frame later:

    private function dispatchChanged() {
        Toolkit.callLater(function() {
            _component.dispatch(new UIEvent(UIEvent.PROPERTY_CHANGE, false, "dataSource"));
        });
    }

haxe.ui.behaviours.Behaviours.dispose() (called from
Component.disposeComponent(), e.g. when a state/screen holding this
ListView closes) explicitly nulls every behaviour instance's _component
field: `inst._component = null;`. If the deferred callback above is still
queued when that disposal happens -- entirely possible, since callLater
defers to the NEXT frame and disposal can happen in between -- it fires
against a null _component, and `.dispatch(...)` on it is a null pointer
dereference with no catchable Haxe exception on cpp.

Confirmed live via a symbolicated native_crash_trace.log (file:line
resolution, SIGSEGV / null pointer dereference) landing inside
ComponentBase.dispatch()'s own first field access, called from this exact
closure via CallLaterImpl's next-frame queue -- entering CharacterEditorState.
The specific over-triggering call site in our own project (updateCurrentAnimOffsets()
re-queuing this every single frame while dragging an offset) is fixed
separately in CharacterEditorState.hx -- this guard is a library-wide
safety net for any OTHER caller that races the same way.

Also logs (plain trace(), captured into game.log via GameLogger's
haxe.Log.trace interceptor) whenever the guard actually skips a dispatch
-- a silent guard would hide that some other call site is still racing
dataSource updates against the list being disposed; this keeps that
visible in game.log instead of just making the crash go away with no
trace of it.

Usage: patch-haxeui-listview-disposed-callback.py <path to ListView.hx>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "if (_component != null)"
if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD = (
    "    private function dispatchChanged() {\n"
    "        Toolkit.callLater(function() {\n"
    "            _component.dispatch(new UIEvent(UIEvent.PROPERTY_CHANGE, false, \"dataSource\"));\n"
    "        });\n"
    "    }\n"
)
NEW = (
    "    private function dispatchChanged() {\n"
    "        Toolkit.callLater(function() {\n"
    "            // Behaviours.dispose() (Component.disposeComponent(), e.g. this\n"
    "            // ListView's owning state/screen closing) nulls every behaviour's\n"
    "            // _component field -- callLater defers to the NEXT frame, so this\n"
    "            // closure can still be queued when that happens. Dispatching on a\n"
    "            // null _component is a null pointer dereference with no catchable\n"
    "            // exception on cpp; confirmed via a real crash trace.\n"
    "            if (_component != null) {\n"
    "                _component.dispatch(new UIEvent(UIEvent.PROPERTY_CHANGE, false, \"dataSource\"));\n"
    "            } else {\n"
    "                trace(\"ListView.DataSourceBehaviour guard fired: skipped a deferred dispatch because _component was already disposed. If this fires often, something is re-triggering dataSource updates too close to the list being closed.\");\n"
    "            }\n"
    "        });\n"
    "    }\n"
)

count = content.count(OLD)
assert count == 1, f"expected exactly 1 match for DataSourceBehaviour.dispatchChanged(), found {count} -- haxeui-core changed upstream"

content = content.replace(OLD, NEW, 1)
assert MARKER in content, "null-guard marker still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched ListView.hx: DataSourceBehaviour.dispatchChanged()'s deferred callback now guards against a disposed _component")
