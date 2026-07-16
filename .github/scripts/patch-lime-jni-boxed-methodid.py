#!/usr/bin/env python3
"""patch-lime-jni-boxed-methodid.py - Fix wrong JNI method signatures for
boxed Boolean/Character unboxing, which crashes with a null pointer
dereference the moment any boxed Boolean or Character value crosses the
JNI boundary (confirmed via a symbolicated native_crash_trace.log: SIGSEGV,
null pointer dereference, fault addr 0x10, at hxcpp_main+40 -- i.e. before
a single line of our own Haxe code runs).

lime/project/src/system/JNI.cpp's JNIType::init() resolves a jmethodID for
each boxed-number wrapper class via the INIT_ELEMENT macro, which hardcodes
the JNI signature "()D" (double) for EVERY type -- correct for
Byte/Short/Integer/Long/Float/Double (all really do have doubleValue()
returning double), but wrong for exactly two of the eight:
Boolean.booleanValue() returns boolean ("()Z"), and Character.charValue()
returns char ("()C"), not double.

GetMethodID() with a signature that doesn't match any real method just
returns null and raises a pending NoSuchMethodError -- which is exactly
what shows up in logcat right before the crash:
    NoSuchMethodError: no non-static method "Ljava/lang/Boolean;.booleanValue()D"
    NoSuchMethodError: no non-static method "Ljava/lang/Character;.charValue()D"
JNIType::init() calls CheckException(inEnv, false) right after, which
clears/swallows that pending exception -- so init() itself doesn't crash,
it just silently leaves elementGetValue[jniBoolean] and
elementGetValue[jniChar] as null.

The actual crash happens later: JNI.cpp's own unboxing code (further down
in the same file) correctly calls CallBooleanMethod/CallCharMethod for
these two types (not CallDoubleMethod -- that part was never wrong), but
passes the now-null jmethodID from elementGetValue[...] into it. Calling a
JNI Call*Method with a null jmethodID is undefined behavior, and crashes
with a null pointer dereference the first time any boxed Boolean or
Character value gets unboxed through this path -- which can happen as
early as Haxe's own static field initializers, before main() proper even
runs, matching the observed hxcpp_main+40 crash site exactly.

Usage: patch-lime-jni-boxed-methodid.py <path to lime/project/src/system/JNI.cpp>
"""

import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

MARKER = "// SIGNATURE is per-call now"
if MARKER in content:
    print("Already patched, skipping.")
    sys.exit(0)

OLD = (
    "\t#define INIT_ELEMENT(TYPE, CLASS_NAME, METHOD_NAME) \\\n"
    "\t\telementClass[jni##TYPE] = FindClass (CLASS_NAME); \\\n"
    "\t\telementGetValue[jni##TYPE] = inEnv->GetMethodID (elementClass[jni##TYPE], METHOD_NAME, \"()D\"); \\\n"
    "\t\tCheckException (inEnv, false);\n"
    "\n"
    "\n"
    "\tvoid JNIType::init (JNIEnv *inEnv) {\n"
    "\n"
    "\t\tfor (int i = 0; i < jniELEMENTS; i++) {\n"
    "\n"
    "\t\t\telementGetValue[i] = 0;\n"
    "\n"
    "\t\t}\n"
    "\n"
    "\t\tINIT_ELEMENT (Boolean, \"java/lang/Boolean\", \"booleanValue\")\n"
    "\t\tINIT_ELEMENT (Byte, \"java/lang/Byte\", \"doubleValue\")\n"
    "\t\tINIT_ELEMENT (Char, \"java/lang/Character\", \"charValue\")\n"
    "\t\tINIT_ELEMENT (Short, \"java/lang/Short\", \"doubleValue\")\n"
    "\t\tINIT_ELEMENT (Int, \"java/lang/Integer\", \"doubleValue\")\n"
    "\t\tINIT_ELEMENT (Long, \"java/lang/Long\", \"doubleValue\")\n"
    "\t\tINIT_ELEMENT (Float, \"java/lang/Float\", \"doubleValue\")\n"
    "\t\tINIT_ELEMENT (Double, \"java/lang/Double\", \"doubleValue\")\n"
)
NEW = (
    "\t// SIGNATURE is per-call now (not hardcoded \"()D\" for every type) --\n"
    "\t// booleanValue() returns boolean (\"()Z\") and charValue() returns char\n"
    "\t// (\"()C\"), not double. The old hardcoded \"()D\" made GetMethodID fail\n"
    "\t// for exactly those two (silently -- CheckException(inEnv, false)\n"
    "\t// swallows the resulting NoSuchMethodError), leaving\n"
    "\t// elementGetValue[jniBoolean]/elementGetValue[jniChar] null. Unboxing\n"
    "\t// a boxed Boolean/Character later calls CallBooleanMethod/\n"
    "\t// CallCharMethod with that null jmethodID -- undefined behavior, a\n"
    "\t// null pointer dereference with no catchable Haxe exception.\n"
    "\t#define INIT_ELEMENT(TYPE, CLASS_NAME, METHOD_NAME, SIGNATURE) \\\n"
    "\t\telementClass[jni##TYPE] = FindClass (CLASS_NAME); \\\n"
    "\t\telementGetValue[jni##TYPE] = inEnv->GetMethodID (elementClass[jni##TYPE], METHOD_NAME, SIGNATURE); \\\n"
    "\t\tCheckException (inEnv, false);\n"
    "\n"
    "\n"
    "\tvoid JNIType::init (JNIEnv *inEnv) {\n"
    "\n"
    "\t\tfor (int i = 0; i < jniELEMENTS; i++) {\n"
    "\n"
    "\t\t\telementGetValue[i] = 0;\n"
    "\n"
    "\t\t}\n"
    "\n"
    "\t\tINIT_ELEMENT (Boolean, \"java/lang/Boolean\", \"booleanValue\", \"()Z\")\n"
    "\t\tINIT_ELEMENT (Byte, \"java/lang/Byte\", \"doubleValue\", \"()D\")\n"
    "\t\tINIT_ELEMENT (Char, \"java/lang/Character\", \"charValue\", \"()C\")\n"
    "\t\tINIT_ELEMENT (Short, \"java/lang/Short\", \"doubleValue\", \"()D\")\n"
    "\t\tINIT_ELEMENT (Int, \"java/lang/Integer\", \"doubleValue\", \"()D\")\n"
    "\t\tINIT_ELEMENT (Long, \"java/lang/Long\", \"doubleValue\", \"()D\")\n"
    "\t\tINIT_ELEMENT (Float, \"java/lang/Float\", \"doubleValue\", \"()D\")\n"
    "\t\tINIT_ELEMENT (Double, \"java/lang/Double\", \"doubleValue\", \"()D\")\n"
)

count = content.count(OLD)
assert count == 1, f"expected exactly 1 match for JNIType::init(), found {count} -- lime changed upstream"

content = content.replace(OLD, NEW, 1)
assert MARKER in content, "guard marker still missing after patching"

with open(path, 'w') as f:
    f.write(content)

print("Patched JNI.cpp: Boolean/Character boxed-value jmethodID now uses the correct signature")
