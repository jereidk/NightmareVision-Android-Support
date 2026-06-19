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
        "https://raw.githubusercontent.com/jereidk/NightmareVision-Android-Support/main/dlc-registry.json";

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
            } catch (_:Dynamic) {}
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
            try { _deleteDir(d.folder); return true; } catch (_:Dynamic) {}
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

                _mutex.acquire();
                registryData   = reg;
                taskState      = SUCCESS;
                taskProgress   = 100;
                taskMessage    = "Loaded " + reg.dlcs.length + " DLC" + (reg.dlcs.length == 1 ? "" : "s");
                activeTaskId   = "";
                _mutex.release();
            } catch (e:Dynamic) {
                _setStatus(FAILED, 0, "Registry fetch failed: " + Std.string(e));
                activeTaskId = "";
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
                _setProgress(5, "Downloading " + entry.name + "...");

                var http:Http  = new Http(entry.downloadUrl);
                var bytes:Null<Bytes> = null;
                var error = "";
                http.onBytes = (b) -> bytes = b;
                http.onError = (e) -> error = e;
                http.request(false);

                if (error != "") throw "Download failed: " + error;
                if (bytes == null || bytes.length == 0) throw "Download returned an empty file";

                _setProgress(60, "Verifying integrity...");

                if (entry.sha256 != null && entry.sha256 != "") {
                    var actual = haxe.crypto.Sha256.make(bytes).toHex();
                    if (actual != entry.sha256)
                        throw "SHA-256 mismatch.\nExpected: " + entry.sha256 + "\nGot: " + actual;
                }

                _setProgress(65, "Saving archive...");
                File.saveBytes(zipPath, bytes);

                _setProgress(70, "Installing...");
                var destPath = getContentPath() + entry.id + "/";
                _mkdirs(destPath);
                _extractZip(zipPath, destPath, entry);

                _setProgress(96, "Cleaning up...");
                if (FileSystem.exists(zipPath)) FileSystem.deleteFile(zipPath);

                _mutex.acquire();
                taskState    = SUCCESS;
                taskProgress = 100;
                taskMessage  = entry.name + " installed!";
                activeTaskId = "";
                _mutex.release();
            } catch (e:Dynamic) {
                try { if (FileSystem.exists(zipPath)) FileSystem.deleteFile(zipPath); } catch (_:Dynamic) {}
                _setStatus(FAILED, 0, Std.string(e));
                activeTaskId = entry.id + "_failed";
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

        var i     = 0;
        var total = entries.length;

        for (e in entries) {
            var fname = e.fileName;
            if (fname == null || fname == "") { i++; continue; }
            // Skip macOS metadata junk
            if (fname.startsWith("__MACOSX") || fname.startsWith("._")) { i++; continue; }

            var target = destPath + fname;
            if (fname.endsWith("/")) {
                if (!FileSystem.exists(target)) _mkdirs(target);
            } else {
                var dir = Path.directory(target);
                if (dir != "" && !FileSystem.exists(dir)) _mkdirs(dir);
                File.saveBytes(target, Reader.unzip(e));
            }

            i++;
            _setProgress(70 + Std.int(25 * i / total), "Installing (" + i + "/" + total + ")...");
        }

        // Ensure meta.json carries our dlcId marker
        var metaPath = destPath + "meta.json";
        if (FileSystem.exists(metaPath)) {
            try {
                var meta:Dynamic = Json.parse(File.getContent(metaPath));
                if (meta.dlcId == null) {
                    meta.dlcId = entry.id;
                    File.saveContent(metaPath, Json.stringify(meta));
                }
            } catch (_:Dynamic) {}
        } else {
            var meta = {
                name:        entry.name,
                global:      false,
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
                try { FileSystem.createDirectory(current); } catch (_:Dynamic) {}
        }
    }
    #end
}
