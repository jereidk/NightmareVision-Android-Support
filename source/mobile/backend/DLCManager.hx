package mobile.backend;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.thread.Thread;
import sys.thread.Mutex;
#end

import haxe.Http;
import haxe.Json;
import haxe.io.Path;
import haxe.io.Bytes;
import haxe.zip.Reader;

using StringTools;

import funkin.backend.Logger;
import funkin.backend.Logger.Severity;

/**
 * Metadata for a downloadable DLC entry (from registry JSON).
 */
typedef DLCEntry = {
    var id:String;
    var name:String;
    var description:String;
    var author:String;
    var version:String;
    var sizeMb:Float;
    var downloadUrl:String;
    var sha256:String;
    var ?tags:Array<String>;
}

/**
 * Root structure of the DLC registry JSON.
 */
typedef DLCRegistry = {
    var schemaVersion:Int;
    var dlcs:Array<DLCEntry>;
}

/**
 * Status of the current background DLC task.
 */
enum abstract DLCTaskState(Int) {
    var IDLE    = 0;
    var BUSY    = 1;
    var SUCCESS = 2;
    var FAILED  = 3;
}

/**
 * Handles downloading, installing, validating, and removing DLC mod folders.
 * All long-running operations run on a background thread; callers poll the
 * public static fields from the main/render thread.
 */
class DLCManager {
    /** URL of the community DLC registry JSON. */
    public static final REGISTRY_URL =
        "https://raw.githubusercontent.com/jereidk/NightmareVision-Android-Support/dev/dlc-registry.json";

    #if sys
    static var _mutex:Mutex = new Mutex();
    #end

    // ── Shared state (background thread writes; main thread reads) ─────────
    public static var taskState:DLCTaskState = IDLE;
    public static var taskProgress:Int       = 0;    // 0–100
    public static var taskMessage:String     = "";
    public static var activeTaskId:String    = "";   // DLC id currently being downloaded, or ""
    public static var registryData:Null<DLCRegistry> = null;

    // ── Path helpers ───────────────────────────────────────────────────────

    public static function getContentPath():String {
        return StorageSystem.getStorageDirectory() + "content/";
    }

    static function _getCachePath():String {
        return StorageSystem.getStorageDirectory() + ".dlc_cache/";
    }

    // ── Installed-DLC queries (sync, main thread safe) ─────────────────────

    /**
     * Returns all installed DLCs — folders in content/ whose meta.json has a
     * `dlcId` field, which is the marker we write on install.
     */
    public static function getInstalledDLCs():Array<{id:String, name:String, folder:String}> {
        var result:Array<{id:String, name:String, folder:String}> = [];
        #if sys
        var base = getContentPath();
        if (!FileSystem.exists(base)) return result;
        for (dir in FileSystem.readDirectory(base)) {
            var full = base + dir;
            if (!FileSystem.isDirectory(full)) continue;
            var metaPath = full + "/meta.json";
            if (!FileSystem.exists(metaPath)) continue;
            try {
                var meta:Dynamic = Json.parse(File.getContent(metaPath));
                if (meta.dlcId != null)
                    result.push({
                        id:     Std.string(meta.dlcId),
                        name:   meta.name != null ? Std.string(meta.name) : dir,
                        folder: full
                    });
            } catch (e:Dynamic) { Logger.log('DLCManager: Failed to parse meta.json for $dir: $e', WARN); }
        }
        #end
        return result;
    }

    public static function isDLCInstalled(id:String):Bool {
        for (d in getInstalledDLCs())
            if (d.id == id) return true;
        return false;
    }

    public static function uninstallDLC(id:String):Bool {
        for (d in getInstalledDLCs()) {
            if (d.id != id) continue;
            #if sys
            try { _deleteDir(d.folder); return true; } catch (e:Dynamic) { Logger.log('DLCManager: Failed to uninstall DLC $id: $e', WARN); }
            #end
        }
        return false;
    }

    // ── Async operations ───────────────────────────────────────────────────

    /** Fetches the community registry JSON asynchronously. */
    public static function fetchRegistryAsync():Void {
        #if sys
        if (taskState == BUSY) return;
        _setStatus(BUSY, 0, "Fetching DLC list...");
        activeTaskId = "_registry";

        Thread.create(() -> {
            try {
                var http = new Http(REGISTRY_URL);
                var data  = "";
                var error = "";
                http.onData  = (d) -> data  = d;
                http.onError = (e) -> error = e;
                http.request(false);

                if (error != "") throw error;
                if (data  == "") throw "Empty response from server";

                var reg:DLCRegistry = Json.parse(data);
                if (reg.schemaVersion != 1)
                    throw "Unsupported registry version: " + reg.schemaVersion;

                _mutex.acquire();
                registryData   = reg;
                taskState      = SUCCESS;
                taskProgress   = 100;
                taskMessage    = "Loaded " + reg.dlcs.length + " DLC" + (reg.dlcs.length == 1 ? "" : "s");
                activeTaskId   = "";
                _mutex.release();
            } catch (e:Dynamic) {
                _mutex.acquire();
                taskState    = FAILED;
                taskProgress = 0;
                taskMessage  = "Registry fetch failed: " + Std.string(e);
                activeTaskId = "";
                _mutex.release();
            }
        });
        #end
    }

    /**
     * Installs a DLC from a local ZIP file (e.g. selected via the native file picker).
     * No download or SHA-256 check — the user is responsible for what they install.
     */
    public static function installFromLocalZipAsync(zipPath:String):Void {
        #if sys
        if (taskState == BUSY) return;

        var fileName = Path.withoutDirectory(zipPath);
        var id       = ~/[^a-zA-Z0-9\-_]/.replace(Path.withoutExtension(fileName), "-");
        if (id == "" || id == "-") id = "local-dlc-" + Std.string(Math.floor(Date.now().getTime() / 1000));
        // Human-readable name: restore spaces from the original filename
        var name = ~/[-_]+/.replace(Path.withoutExtension(fileName), " ").trim();
        if (name == "") name = id;

        _setStatus(BUSY, 0, "Installing from local file...");
        activeTaskId = id;

        Thread.create(() -> {
            try {
                if (!FileSystem.exists(zipPath)) throw "File not found: " + zipPath;

                _setProgress(20, "Installing " + fileName + "...");
                var destPath = getContentPath() + id + "/";
                _mkdirs(destPath);

                var fakeEntry:DLCEntry = {
                    id: id, name: name, description: "", author: "",
                    version: "1.0", sizeMb: 0, downloadUrl: "", sha256: ""
                };
                _extractZip(zipPath, destPath, fakeEntry);

                _setProgress(96, "Cleaning up...");
                try {
                    if (zipPath.indexOf(".temp") >= 0 || zipPath.indexOf("dlc-import") >= 0)
                        if (FileSystem.exists(zipPath)) FileSystem.deleteFile(zipPath);
                } catch (e:Dynamic) { Logger.log('DLCManager: Failed to cleanup temp file: $e', WARN); }

                _mutex.acquire();
                taskState    = SUCCESS;
                taskProgress = 100;
                taskMessage  = name + " installed! Restart the game to load it.";
                activeTaskId = "";
                _mutex.release();
            } catch (e:Dynamic) {
                _mutex.acquire();
                taskState    = FAILED;
                taskProgress = 0;
                taskMessage  = Std.string(e);
                activeTaskId = id + "_failed";
                _mutex.release();
            }
        });
        #end
    }

    /** Downloads, validates (SHA-256), and installs a DLC asynchronously. */
    public static function downloadAndInstallAsync(entry:DLCEntry):Void {
        #if sys
        if (taskState == BUSY) return;
        _setStatus(BUSY, 0, "Starting download...");
        activeTaskId = entry.id;

        Thread.create(() -> {
            var cachePath = _getCachePath();
            var zipPath   = cachePath + entry.id + ".zip";

            try {
                _mkdirs(cachePath);
                _setProgress(5, "Connecting to download server...");

                // Stream the response body straight to disk through a counting Output so
                // we can report real byte-level progress and keep peak memory low.
                // haxe.Http.customRequest() is blocking but follows redirects (GitHub
                // release URLs 302 to *.githubusercontent.com), exactly like request().
                // The download phase is mapped onto 5%–55% of the overall task.
                var http:Http = new Http(entry.downloadUrl);
                var error = "";
                http.onError = (e) -> error = e;

                var estTotal  = entry.sizeMb > 0 ? Std.int(entry.sizeMb * 1024 * 1024) : 0;
                var startTime = haxe.Timer.stamp();
                var lastPct   = -1;

                var fileOut = File.write(zipPath, true);
                var counter = new DownloadProgressOutput(fileOut, (written) -> {
                    // Prefer the exact Content-Length from the (post-redirect) headers,
                    // fall back to the registry's declared size if it isn't available.
                    var total = estTotal;
                    var cl = http.responseHeaders != null ? http.responseHeaders.get("Content-Length") : null;
                    if (cl != null) { var p = Std.parseInt(cl); if (p != null && p > 0) total = p; }

                    var pct = total > 0 ? 5 + Std.int(Math.min(50, (written / total) * 50)) : 5;
                    if (pct != lastPct) {
                        lastPct = pct;
                        var mb    = written / (1024.0 * 1024.0);
                        var totMb = total   / (1024.0 * 1024.0);
                        var secs  = haxe.Timer.stamp() - startTime;
                        var spd   = secs > 0 ? mb / secs : 0.0;
                        _setProgress(pct, 'Downloading: ${_fmtMB(mb)} / ${total > 0 ? _fmtMB(totMb) : "?"} MB  •  ${_fmtMB(spd)} MB/s');
                    }
                });

                try {
                    http.customRequest(false, counter);
                } catch (e:Dynamic) {
                    try counter.close() catch (ce:Dynamic) { Logger.log('DLCManager: Failed to close counter: $ce', WARN); }
                    throw "Download failed: " + Std.string(e);
                }
                try counter.close() catch (ce:Dynamic) { Logger.log('DLCManager: Failed to close counter: $ce', WARN); }

                if (error != "") throw "Download failed: " + error;
                if (!FileSystem.exists(zipPath) || FileSystem.stat(zipPath).size == 0)
                    throw "Download returned an empty file";

                _setProgress(58, "Verifying integrity...");

                if (entry.sha256 != null && entry.sha256 != "") {
                    var fileBytes = File.getBytes(zipPath);
                    var actual = haxe.crypto.Sha256.make(fileBytes).toHex();
                    if (actual != entry.sha256)
                        throw "SHA-256 mismatch.\nExpected: " + entry.sha256 + "\nGot: " + actual;
                }

                _setProgress(65, "Installing...");
                var destPath = getContentPath() + entry.id + "/";
                _mkdirs(destPath);
                _extractZip(zipPath, destPath, entry);

                _setProgress(96, "Cleaning up...");
                if (FileSystem.exists(zipPath)) FileSystem.deleteFile(zipPath);

                _mutex.acquire();
                taskState    = SUCCESS;
                taskProgress = 100;
                taskMessage  = entry.name + " installed! Restart the game to load it.";
                activeTaskId = "";
                _mutex.release();
            } catch (e:Dynamic) {
                try { if (FileSystem.exists(zipPath)) FileSystem.deleteFile(zipPath); } catch (de:Dynamic) { Logger.log('DLCManager: Failed to cleanup zip after error: $de', WARN); }
                _mutex.acquire();
                taskState    = FAILED;
                taskProgress = 0;
                taskMessage  = Std.string(e);
                activeTaskId = entry.id + "_failed";
                _mutex.release();
            }
        });
        #end
    }

    // ── Private helpers ────────────────────────────────────────────────────

    #if sys
    static function _extractZip(zipPath:String, destPath:String, entry:DLCEntry):Void {
        var input   = File.read(zipPath, true);
        var entries = Reader.readZip(input);
        input.close();

        // Detect single top-level folder to strip (e.g. GitHub ZIPs: my-mod/songs/...)
        var stripPrefix = "";
        var topLevels = new haxe.ds.StringMap<Bool>();
        for (e in entries) {
            var fn = e.fileName;
            if (fn == null || fn == "" || fn.startsWith("__MACOSX") || fn.startsWith("._")) continue;
            var slash = fn.indexOf("/");
            topLevels.set(slash > 0 ? fn.substring(0, slash + 1) : "__root__", true);
        }
        var topKeys = [for (k in topLevels.keys()) k];
        if (topKeys.length == 1 && topKeys[0] != "__root__") stripPrefix = topKeys[0];

        var i     = 0;
        var total = entries.length;

        for (e in entries) {
            var fname = e.fileName;
            if (fname == null || fname == "") { i++; continue; }
            // Skip macOS metadata junk
            if (fname.startsWith("__MACOSX") || fname.startsWith("._")) { i++; continue; }

            // Strip single top-level folder prefix if detected
            if (stripPrefix != "" && fname.startsWith(stripPrefix))
                fname = fname.substring(stripPrefix.length);
            if (fname == "" || fname == "/") { i++; continue; }

            // Guard against path traversal: remove .., absolute segments, and Windows separators
            var rawParts = fname.replace("\\", "/").split("/");
            var safeParts:Array<String> = [];
            for (p in rawParts) { if (p != "" && p != "." && p != "..") safeParts.push(p); }
            if (safeParts.length == 0) { i++; continue; }
            var isDir = fname.endsWith("/");
            fname = safeParts.join("/") + (isDir ? "/" : "");

            var target = destPath + fname;
            if (fname.endsWith("/")) {
                if (!FileSystem.exists(target)) _mkdirs(target);
            } else {
                var dir = Path.directory(target);
                if (dir != "" && !FileSystem.exists(dir)) _mkdirs(dir);
                File.saveBytes(target, Reader.unzip(e));
            }

            i++;
            _setProgress(70 + (total > 0 ? Std.int(25 * i / total) : 25), "Installing (" + i + "/" + total + ")...");
        }

        // Ensure meta.json carries our dlcId marker and global:true
        var metaPath = destPath + "meta.json";
        if (FileSystem.exists(metaPath)) {
            try {
                var meta:Dynamic = Json.parse(File.getContent(metaPath));
                var changed = false;
                if (meta.dlcId  == null)  { meta.dlcId  = entry.id; changed = true; }
                if (meta.global != true)  { meta.global = true;      changed = true; }
                if (changed) File.saveContent(metaPath, Json.stringify(meta));
            } catch (e:Dynamic) { Logger.log('DLCManager: Failed to update meta.json: $e', WARN); }
        } else {
            var meta = {
                name:        entry.name,
                global:      true,   // load alongside the active mod, not only when selected
                description: entry.description,
                dlcId:       entry.id
            };
            File.saveContent(metaPath, Json.stringify(meta));
        }
    }

    static function _setStatus(state:DLCTaskState, progress:Int, msg:String):Void {
        _mutex.acquire();
        taskState    = state;
        taskProgress = progress;
        taskMessage  = msg;
        _mutex.release();
    }

    static function _setProgress(progress:Int, msg:String):Void {
        _mutex.acquire();
        taskProgress = progress;
        taskMessage  = msg;
        _mutex.release();
    }

    /** Formats a megabyte figure with a single decimal (e.g. 131.8). */
    static inline function _fmtMB(v:Float):String {
        return Std.string(Math.round(v * 10) / 10);
    }

    static function _deleteDir(path:String):Void {
        if (!FileSystem.exists(path)) return;
        for (item in FileSystem.readDirectory(path)) {
            var full = path + "/" + item;
            if (FileSystem.isDirectory(full)) _deleteDir(full);
            else FileSystem.deleteFile(full);
        }
        FileSystem.deleteDirectory(path);
    }

    static function _mkdirs(path:String):Void {
        if (FileSystem.exists(path)) return;
        var parts   = path.split("/");
        var current = "";
        if (path.startsWith("/")) {
            current = "/";
            if (parts.length > 0 && parts[0] == "") parts.shift();
        }
        for (part in parts) {
            if (part == "") continue;
            current = (current == "/" ? "/" : (current == "" ? "" : current + "/")) + part;
            if (!FileSystem.exists(current))
                try { FileSystem.createDirectory(current); } catch (e:Dynamic) { Logger.log('DLCManager: Failed to create directory $current: $e', WARN); }
        }
    }
    #end
}

#if sys
/**
 * An Output that forwards everything to a destination Output (the download file)
 * while reporting the cumulative byte count, so download progress can be tracked
 * as the HTTP body streams in. Only writeBytes/writeByte are overridden; the
 * onWritten callback is invoked after every chunk with the running total.
 */
private class DownloadProgressOutput extends haxe.io.Output {
    final dest:haxe.io.Output;
    final onWritten:Int->Void;
    var total:Int = 0;

    public function new(dest:haxe.io.Output, onWritten:Int->Void) {
        this.dest      = dest;
        this.onWritten = onWritten;
    }

    override public function writeByte(c:Int):Void {
        dest.writeByte(c);
        total++;
        onWritten(total);
    }

    override public function writeBytes(s:haxe.io.Bytes, pos:Int, len:Int):Int {
        var n = dest.writeBytes(s, pos, len);
        total += n;
        onWritten(total);
        return n;
    }

    override public function flush():Void dest.flush();
    override public function close():Void dest.close();
}
#end
