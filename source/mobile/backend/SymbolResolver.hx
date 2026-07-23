package mobile.backend;

/**
 * Loads the per-ABI symbol table asset (assets/data/symbols-{arm64,armv7}.txt,
 * generated at build time by .github/scripts/extract-symbol-table.sh -- see
 * its own doc comment for the exact "<16-hex address> <demangled name>"
 * format) and resolves a native_crash_trace.log frame's rel_pc offset to the
 * nearest-preceding function's name.
 *
 * Read via JavaCrashHandler.readRawTextAsset() (Android's AssetManager
 * directly), not funkin.FunkinAssets/openfl.Assets -- see that function's
 * doc comment for why OpenFL's own asset system can't see this file.
 *
 * Nearest-preceding (binary search for the largest table address <= the
 * target) rather than an exact/ranged match -- no symbol size is kept, so
 * this is the same approximation addr2line itself falls back to between
 * exact symbol boundaries. Good enough to identify which function a crash
 * happened in (confirmed this session: bare function names alone were
 * enough to find and fix both the touch-nav-mode and Double Trouble native
 * crashes), just without file/line.
 */
class SymbolResolver
{
	static var _addresses:Null<Array<Int>> = null;
	static var _names:Null<Array<String>> = null;
	static var _loadAttempted:Bool = false;

	/**
	 * Loads and parses the symbol table for the given ABI (as recorded in a
	 * trace file's own "abi=" header field -- see
	 * TombstoneParser.readHeaderField(), e.g. "arm64-v8a"/"armeabi-v7a") if
	 * not already loaded. Safe to call repeatedly -- only the first call
	 * does any work; later calls with a DIFFERENT abi than what's already
	 * loaded are a no-op (this process only ever needs to resolve crashes
	 * from its own current build/ABI, never a foreign one).
	 *
	 * Returns false if no table could be loaded (missing asset, unrecognized
	 * ABI, parse failure), in which case resolve() always returns null.
	 */
	public static function load(abi:Null<String>):Bool
	{
		if (_addresses != null) return true;
		if (_loadAttempted) return false;
		_loadAttempted = true;

		#if (android && sys)
		try
		{
			final mapped = mapAbi(abi);
			if (mapped == null) return false;

			// Read via JavaCrashHandler's AssetManager-backed reader, not
			// funkin.FunkinAssets/openfl.Assets -- this file is written into
			// src/main/assets/ by the CI's Gradle-side extractNativeSymbols
			// task, which runs AFTER Lime's own asset manifest is already
			// finalized, so OpenFL's Assets.exists()/getContent() never see
			// it even though it's genuinely inside the APK (see
			// JavaCrashHandler.java's readRawTextAsset() doc comment).
			final path = 'data/symbols-$mapped.txt';
			final content = mobile.backend.JavaCrashHandler.readRawTextAsset(path);
			if (content == null) return false;

			final addresses:Array<Int> = [];
			final names:Array<String> = [];

			for (line in content.split('\n'))
			{
				if (line.length == 0) continue;
				final spaceIdx = line.indexOf(' ');
				if (spaceIdx < 0) continue;

				final addrHex = line.substr(0, spaceIdx);
				final name = line.substr(spaceIdx + 1);

				final addr = Std.parseInt('0x' + addrHex);
				if (addr == null) continue;

				addresses.push(addr);
				names.push(name);
			}

			if (addresses.length == 0) return false;

			// Extraction already sorts ascending by address, so no need to
			// re-sort here -- just trust the build script's own output.
			_addresses = addresses;
			_names = names;
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#else
		return false;
		#end
	}

	/**
	 * Resolves a rel_pc offset to the nearest-preceding function's name, or
	 * null if no table is loaded or the address falls before the first
	 * known symbol.
	 */
	public static function resolve(relPc:Int):Null<String>
	{
		if (_addresses == null) return null;

		final addrs = _addresses;
		var lo = 0;
		var hi = addrs.length - 1;
		var result = -1;

		while (lo <= hi)
		{
			final mid = (lo + hi) >> 1;
			if (addrs[mid] <= relPc)
			{
				result = mid;
				lo = mid + 1;
			}
			else
			{
				hi = mid - 1;
			}
		}

		if (result < 0) return null;
		return _names[result];
	}

	/**
	 * Maps Android's own Build.SUPPORTED_ABIS[0] naming (what actually gets
	 * stamped into a trace file's "abi=" header field) to this project's own
	 * symbol table file suffix (matching extract-symbol-table.sh's two
	 * output filenames). Returns null for anything not shipped (x86, etc.)
	 * or unrecognized.
	 */
	static function mapAbi(abi:Null<String>):Null<String>
	{
		if (abi == null) return null;
		if (abi.indexOf('arm64') == 0) return 'arm64';
		if (abi.indexOf('armeabi') == 0) return 'armv7';
		return null;
	}
}
