# Keep all classes and methods accessed from Haxe via JNI.
# R8 cannot see these cross-language call sites, so without explicit
# rules they'd be stripped as "unused" Java code.
-keep,allowoptimization class mobile.backend.java.** {
    public protected *;
}

# Keep Android Components registered in the manifest (ContentProvider).
-keep class mobile.backend.java.ModFolderDocumentsProvider { *; }

# Keep Lime/Haxe JNI bridge (HaxeObject, Extension base class).
-keep class org.haxe.lime.HaxeObject { *; }
-keep class org.haxe.extension.Extension { *; }
