package external.memory;

#if cpp
/**
 * Memory class to properly get accurate memory counts
 * for the program.
 * @author Leather128 (Haxe Bindings) - David Robert Nadeau (Original C Header)
 * even if the author is above this, thank you Leather128 for the Haxe Bindings!
 */
@:buildXml('<include name="../../../../source/external/memory/build.xml" />')
@:include("Memory.h")
extern class Memory
{
	/**
	 * Returns the current resident set size (physical memory use) measured
	 * in bytes, or zero if the value cannot be determined on this OS.
	 */
	@:native("getCurrentRSS")
	public static function getCurrentUsage():cpp.UInt64;

	/**
	 * Returns the system-wide total physical RAM in bytes, or zero if the
	 * value cannot be determined on this OS (Linux/Android only for now).
	 *
	 * The "::" is load-bearing, not decorative: external.Native.hx has its
	 * own Haxe function of this exact same name that just forwards here.
	 * Without the global-scope qualifier, the unqualified call this @:native
	 * generates inside Native_obj::getSystemTotalMemory()'s own compiled
	 * body resolves via ordinary C++ member-lookup to itself before it ever
	 * considers the free function in Memory.h -- infinite self-recursion,
	 * a real stack-overflow SIGSEGV confirmed via a debug-build native
	 * crash trace (508 identical repeated frames, all in this function).
	 */
	@:native("::getSystemTotalMemory")
	public static function getSystemTotalMemory():cpp.UInt64;

	/**
	 * Returns the system-wide currently available RAM in bytes (via
	 * /proc/meminfo's MemAvailable — the same figure Android's low-memory
	 * killer watches), or zero if it cannot be determined on this OS.
	 *
	 * See getSystemTotalMemory() above for why the "::" is required.
	 */
	@:native("::getSystemAvailableMemory")
	public static function getSystemAvailableMemory():cpp.UInt64;
}
#end
