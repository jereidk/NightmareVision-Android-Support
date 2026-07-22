package mobile.backend;

#if (android && sys)
import sys.io.File;
import haxe.io.Bytes;
#end

typedef PBField =
{
	var field:Int;
	var wireType:Int;
	var dataStart:Int;
	var dataEnd:Int;
}

typedef CrashFrame =
{
	/** Address relative to the containing library's load base -- what a symbol table (or addr2line) needs, directly. */
	var relPc:Int;
	/** Path of the mapped library/file this frame's pc falls in (e.g. ".../base.apk" for our own code, or a system .so). */
	var fileName:String;
	/** Function name the OS's own unwinder already resolved, or '' if this frame needs a symbol table lookup (always true for our own stripped code). */
	var funcName:String;
}

typedef CrashThreadInfo =
{
	var tid:Int;
	var name:String;
	var frames:Array<CrashFrame>;
}

/**
 * Minimal protobuf wire-format reader, specialized for Android's tombstone
 * schema (system/core/debuggerd/proto/tombstone.proto) -- just enough to
 * find the thread that actually crashed and its backtrace, not a general
 * protobuf library. Ports the pbdump.py/extract_thread.py scripts used to
 * manually symbolicate a native_crash_trace.log this session (the
 * touch-nav-mode and Double Trouble crashes) onto the device itself, so
 * SymbolResolver can resolve function names on the next launch without any
 * external tooling or CI job.
 *
 * Field numbers below were confirmed empirically against real captured
 * traces (see pbdump.py), not derived from a compiled .proto -- there's no
 * protobuf codegen in this project. If Android ever changes tombstone.proto's
 * field numbers this would need updating to match.
 *
 * Deliberately narrow: only reads the handful of fields needed to identify
 * the crashing thread and its backtrace's rel_pc/file_name/function_name.
 * Register values (x0-x29, sp, pc, lr) are true 64-bit values that would
 * overflow Haxe's 32-bit Int on cpp -- skipped by position only, their
 * values are never read, since nothing here needs them.
 */
class TombstoneParser
{
	#if (android && sys)
	static inline var FIELD_TID = 6;
	static inline var FIELD_THREADS = 16;
	static inline var FIELD_THREAD_ID = 1;
	static inline var FIELD_THREAD_NAME = 2;
	static inline var FIELD_THREAD_BACKTRACE = 4;
	static inline var FIELD_FRAME_REL_PC = 1;
	static inline var FIELD_FRAME_FUNCTION_NAME = 4;
	static inline var FIELD_FRAME_FILE_NAME = 6;

	static inline var RAW_TOMBSTONE_MARKER = "=== raw tombstone data follows ===\n";
	#end

	/**
	 * Reads a native_crash_trace_*.log (our own text header + raw tombstone
	 * protobuf bytes, see JavaCrashHandler.java's saveTraceIfPresent()) and
	 * returns the thread that actually crashed, with its full backtrace.
	 * Returns null on any parse failure -- never throws, since this runs
	 * during otherwise-normal startup and a malformed/unexpected trace file
	 * shouldn't be able to break anything else.
	 */
	public static function parse(traceFilePath:String):Null<CrashThreadInfo>
	{
		#if (android && sys)
		try
		{
			var raw = File.getBytes(traceFilePath);
			var markerBytes = Bytes.ofString(RAW_TOMBSTONE_MARKER);
			var markerPos = indexOfBytes(raw, markerBytes);
			if (markerPos < 0) return null;

			var start = markerPos + markerBytes.length;
			var buf = raw.sub(start, raw.length - start);

			return parseTombstone(buf);
		}
		catch (e:Dynamic)
		{
			return null;
		}
		#else
		return null;
		#end
	}

	/**
	 * Reads a "key=value" token out of the trace file's own plain-text
	 * header (everything before RAW_TOMBSTONE_MARKER -- see
	 * JavaCrashHandler.java's saveTraceIfPresent(), which stamps this file
	 * with the exact build/device/ABI it came from). Used to find "abi="
	 * (e.g. "arm64-v8a") so the right per-ABI symbol table gets loaded,
	 * without needing a separate device-ABI query on the Haxe side.
	 * Returns null if the key isn't present or the file can't be read.
	 */
	public static function readHeaderField(traceFilePath:String, key:String):Null<String>
	{
		#if (android && sys)
		try
		{
			var raw = File.getBytes(traceFilePath);
			var markerBytes = Bytes.ofString(RAW_TOMBSTONE_MARKER);
			var markerPos = indexOfBytes(raw, markerBytes);
			final headerLen = (markerPos < 0) ? raw.length : markerPos;
			final header = raw.sub(0, headerLen).toString();

			final needle = key + '=';
			final idx = header.indexOf(needle);
			if (idx < 0) return null;

			var valueStart = idx + needle.length;
			var valueEnd = valueStart;
			while (valueEnd < header.length)
			{
				final c = header.charCodeAt(valueEnd);
				// Stop at whitespace/newline -- every "key=value" token this
				// file writes (abi=arm64-v8a, versionCode=1, ...) is a single
				// space-separated word on its own line.
				if (c == ' '.code || c == '\n'.code || c == '\r'.code || c == '\t'.code) break;
				valueEnd++;
			}

			return header.substring(valueStart, valueEnd);
		}
		catch (e:Dynamic)
		{
			return null;
		}
		#else
		return null;
		#end
	}

	#if (android && sys)
	static function indexOfBytes(haystack:Bytes, needle:Bytes):Int
	{
		final hLen = haystack.length;
		final nLen = needle.length;
		if (nLen == 0 || nLen > hLen) return -1;
		final limit = hLen - nLen;
		var i = 0;
		while (i <= limit)
		{
			var matched = true;
			for (j in 0...nLen)
			{
				if (haystack.get(i + j) != needle.get(j))
				{
					matched = false;
					break;
				}
			}
			if (matched) return i;
			i++;
		}
		return -1;
	}

	/**
	 * Advances past a single varint without computing its value -- see the
	 * class doc comment on why register fields are skipped this way instead
	 * of read.
	 */
	static function skipVarint(buf:Bytes, pos:Int):Int
	{
		while (true)
		{
			final b = buf.get(pos);
			pos++;
			if ((b & 0x80) == 0) break;
		}
		return pos;
	}

	static function readVarint(buf:Bytes, pos:Int):{value:Int, pos:Int}
	{
		var result = 0;
		var shift = 0;
		while (true)
		{
			final b = buf.get(pos);
			pos++;
			result |= (b & 0x7f) << shift;
			if ((b & 0x80) == 0) break;
			shift += 7;
		}
		return {value: result, pos: pos};
	}

	/**
	 * Parses one length-delimited message's raw bytes into a flat list of
	 * top-level (fieldNum, wireType, dataStart, dataEnd) entries -- doesn't
	 * recurse, callers slice out and re-parse whichever nested message they
	 * actually need via the same function.
	 */
	static function parseFields(buf:Bytes, start:Int, end:Int):Array<PBField>
	{
		final out:Array<PBField> = [];
		var pos = start;
		while (pos < end)
		{
			final keyR = readVarint(buf, pos);
			final key = keyR.value;
			pos = keyR.pos;
			final fieldNum = key >> 3;
			final wireType = key & 0x7;

			switch (wireType)
			{
				case 0: // varint
					final vStart = pos;
					pos = skipVarint(buf, pos);
					out.push({field: fieldNum, wireType: wireType, dataStart: vStart, dataEnd: pos});
				case 1: // fixed64
					out.push({field: fieldNum, wireType: wireType, dataStart: pos, dataEnd: pos + 8});
					pos += 8;
				case 2: // length-delimited
					final lenR = readVarint(buf, pos);
					final len = lenR.value;
					pos = lenR.pos;
					out.push({field: fieldNum, wireType: wireType, dataStart: pos, dataEnd: pos + len});
					pos += len;
				case 5: // fixed32
					out.push({field: fieldNum, wireType: wireType, dataStart: pos, dataEnd: pos + 4});
					pos += 4;
				default:
					// Unknown wire type -- can't safely skip past it, bail
					// out of this message with whatever fields were already
					// collected rather than risk reading garbage forever.
					return out;
			}
		}
		return out;
	}

	static function findField(fields:Array<PBField>, num:Int):Null<PBField>
	{
		for (f in fields) if (f.field == num) return f;
		return null;
	}

	static function findAllFields(fields:Array<PBField>, num:Int):Array<PBField>
	{
		return [for (f in fields) if (f.field == num) f];
	}

	static function readVarintField(buf:Bytes, f:Null<PBField>):Null<Int>
	{
		if (f == null || f.wireType != 0) return null;
		return readVarint(buf, f.dataStart).value;
	}

	static function readStringField(buf:Bytes, f:Null<PBField>):Null<String>
	{
		if (f == null || f.wireType != 2) return null;
		return buf.sub(f.dataStart, f.dataEnd - f.dataStart).toString();
	}

	static function parseTombstone(buf:Bytes):Null<CrashThreadInfo>
	{
		final top = parseFields(buf, 0, buf.length);
		final crashingTid = readVarintField(buf, findField(top, FIELD_TID));
		if (crashingTid == null) return null;

		final threadEntries = findAllFields(top, FIELD_THREADS);
		for (entry in threadEntries)
		{
			// map<int32, Thread> encodes each entry as its own little
			// message: field 1 = key (thread id), field 2 = value (Thread).
			final entryFields = parseFields(buf, entry.dataStart, entry.dataEnd);
			final key = readVarintField(buf, findField(entryFields, 1));
			final valueField = findField(entryFields, 2);
			if (valueField == null) continue;

			final threadFields = parseFields(buf, valueField.dataStart, valueField.dataEnd);
			var tid = readVarintField(buf, findField(threadFields, FIELD_THREAD_ID));
			if (tid == null) tid = key;
			if (tid != crashingTid) continue;

			final name = readStringField(buf, findField(threadFields, FIELD_THREAD_NAME));
			final frameFields = findAllFields(threadFields, FIELD_THREAD_BACKTRACE);
			final frames:Array<CrashFrame> = [];
			for (ff in frameFields)
			{
				final frameData = parseFields(buf, ff.dataStart, ff.dataEnd);
				final relPc = readVarintField(buf, findField(frameData, FIELD_FRAME_REL_PC));
				if (relPc == null) continue;
				final funcName = readStringField(buf, findField(frameData, FIELD_FRAME_FUNCTION_NAME));
				final fileName = readStringField(buf, findField(frameData, FIELD_FRAME_FILE_NAME));
				frames.push({relPc: relPc, fileName: fileName ?? '', funcName: funcName ?? ''});
			}

			return {tid: tid, name: name ?? '', frames: frames};
		}

		return null;
	}
	#end
}
