package mobile.backend.java;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import org.haxe.extension.Extension;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.FilenameFilter;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Two-pronged native crash capture for Android:
 *
 *  1. Java UncaughtExceptionHandler — catches Java/JNI exceptions that escape
 *     all other handlers and writes them to crash.log before the process dies.
 *
 *  2. ApplicationExitInfo reader (API 30 / Android 11+) — reads Android's
 *     built-in record of why the PREVIOUS session ended (SIGSEGV, OOM, ANR…).
 *     Accessed via reflection so the file compiles against any SDK version.
 */
public class JavaCrashHandler extends Extension implements Thread.UncaughtExceptionHandler {

    private static Thread.UncaughtExceptionHandler sOriginalHandler;
    private static String sCrashLogPath;
    private static volatile boolean sInstalled = false;

    // ── public API called from Haxe via JNI ─────────────────────────────────

    /**
     * Install the Java-level uncaught exception handler.
     * Must be called once at startup.
     *
     * @param crashLogPath absolute path where crash.log should be written
     */
    public static void install(final String crashLogPath) {
        if (sInstalled) return;
        sInstalled = true;
        sCrashLogPath = crashLogPath;
        sOriginalHandler = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler(new JavaCrashHandler());
    }

    /**
     * Appends a line to game.log (Haxe's funkin.backend.GameLogger, same file
     * this class already writes crash.log/trace/logcat dumps next to), so
     * non-fatal Java-side Log.w/Log.e calls elsewhere in this package (Kizzy
     * Discord RPC, file-manager intents, refresh-rate queries, ...) show up
     * alongside everything Haxe already logs there instead of only ever
     * reaching Logcat -- which needs adb, not available to most players
     * reporting a bug, and isn't captured at all outside the ~3000-line
     * window saveLogcatDump() grabs at the moment of an actual crash/exit.
     *
     * Shared here (keyed off sCrashLogPath, already known once install() has
     * run) rather than each caller deriving its own path, since most of
     * those call sites have no directory to hand in themselves.
     * Only appends if game.log already exists -- GameLogger only creates it
     * when developer mode is on, and by the time any of these call sites can
     * fire, GameLogger.init() (called as early as possible in Init.create())
     * has already had its chance to create it for this session if so.
     */
    public static void appendToGameLog(String tag, String level, String message) {
        try {
            if (sCrashLogPath == null) return;
            File logFile = new File(new File(sCrashLogPath).getParent(), "game.log");
            if (!logFile.exists()) return;

            String stamp = new SimpleDateFormat("[HH:mm:ss]", Locale.US).format(new Date());
            String line = stamp + " [" + level + "] [Java/" + tag + "] " + message + "\n";

            FileOutputStream out = new FileOutputStream(logFile, true);
            out.write(line.getBytes("UTF-8"));
            out.close();
        } catch (Exception e) {
            android.util.Log.w("JavaCrashHandler", "Failed to append to game.log: " + e);
        }
    }

    /**
     * Read Android's ApplicationExitInfo (API 30 / Android 11+) for every
     * process exit since the last time this was checked. Uses reflection so
     * this compiles against any compileSdkVersion.
     *
     * Confirmed via AOSP's AppExitInfoTracker source: reading this history
     * does NOT clear or consume it -- entries stay available for future
     * queries until the OS itself evicts the oldest one past its own
     * retention cap. Two consequences this used to get wrong by only ever
     * asking for the single latest entry (maxNum=1) and overwriting one
     * fixed "native_crash_trace.log" filename every time:
     *
     *   1. Two crashes in a row, before the user extracts each trace, meant
     *      the second overwrote the first's saved file -- lost for good,
     *      even though Android itself still had both.
     *   2. Since Android never clears its own history, re-running this same
     *      maxNum=1 query on every subsequent launch kept re-surfacing (and
     *      re-overwriting the trace file for) the SAME old crash indefinitely,
     *      until enough newer exits pushed it out of the OS's own retention.
     *
     * Fixed by asking for the full available history each time (maxNum=0),
     * saving every new exit's trace under its own pid+timestamp filename,
     * and persisting the newest timestamp we've already processed so a
     * later launch only reports genuinely new exits.
     *
     * @return human-readable summary of any new abnormal exit(s), null if
     * none are new since the last check.
     */
    public static String readPreviousNativeCrash() {
        if (Build.VERSION.SDK_INT < 30) return null;

        Activity activity = mainActivity;
        if (activity == null) return null;

        try {
            ActivityManager am =
                (ActivityManager) activity.getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return null;

            // ActivityManager.getHistoricalProcessExitReasons(String pkgName, int pid, int maxNum)
            // maxNum=0 means "return everything the OS still has", not "return
            // nothing" -- confirmed via AOSP source (ActivityManager.java).
            Method getReasons = ActivityManager.class.getDeclaredMethod(
                "getHistoricalProcessExitReasons",
                String.class, int.class, int.class);

            @SuppressWarnings("unchecked")
            List<Object> exits = (List<Object>) getReasons.invoke(am, null, 0, 0);

            // Build-identity marker: read what build was running LAST launch
            // (i.e. the one whose exit we're about to inspect below) before
            // overwriting it with the CURRENT build. Without this, a crash
            // reported after the app was updated would get symbolicated
            // against the wrong .so -- the exact class of misattribution
            // that already burned us once with addr2line's nearest-symbol
            // guessing on unrelated code.
            String prevBuildInfo = loadPreviousBuildInfo();
            saveCurrentBuildInfo();

            if (exits == null || exits.isEmpty()) return null;

            long lastSeenTimestamp = loadLastSeenTimestamp();
            long newestTimestamp   = lastSeenTimestamp;
            int newCount = 0;
            StringBuilder sb = null;

            for (Object info : exits) {
                Class<?> cls = info.getClass();

                long timestamp = (long) cls.getMethod("getTimestamp").invoke(info);
                // Already reported on a previous launch -- Android's own
                // history isn't cleared by reading it, so without this check
                // the same old exit would resurface on every future launch.
                if (timestamp <= lastSeenTimestamp) continue;
                if (timestamp > newestTimestamp) newestTimestamp = timestamp;

                int reason = (int) cls.getMethod("getReason").invoke(info);

                // ApplicationExitInfo reason constants (API 30):
                //   UNKNOWN=0, EXIT_SELF=1, SIGNALED=2, LOW_MEMORY=3,
                //   CRASH=4, CRASH_NATIVE=5, ANR=6, INITIALIZATION_FAILURE=7,
                //   PERMISSION_CHANGE=8, EXCESSIVE_RESOURCE_USAGE=9, USER_REQUESTED=10
                // Skip clean/expected exits (UNKNOWN, EXIT_SELF, USER_REQUESTED).
                if (reason == 0 || reason == 1 || reason == 10) continue;

                newCount++;

                Object desc = cls.getMethod("getDescription").invoke(info);
                int importance = (int) cls.getMethod("getImportance").invoke(info);
                int status    = (int) cls.getMethod("getStatus").invoke(info);
                int pid       = (int) cls.getMethod("getPid").invoke(info);

                // Extra context so the trace can be diagnosed precisely
                // without guessing: which process actually exited (in case
                // Android reports a helper/isolated process, not our main
                // one), and memory pressure at the moment of exit (helps
                // tell a real code bug apart from an OOM-adjacent crash).
                String processName = null;
                long pss = -1L, rss = -1L;
                try { processName = (String) cls.getMethod("getProcessName").invoke(info); } catch (Exception ignored) {}
                try { pss = (long) cls.getMethod("getPss").invoke(info); } catch (Exception ignored) {}
                try { rss = (long) cls.getMethod("getRss").invoke(info); } catch (Exception ignored) {}

                if (sb == null) sb = new StringBuilder();
                else sb.append("\n---\n\n");

                sb.append("Crash detectado (sesión anterior)\n\n");
                sb.append("Fecha: ").append(formatTimestamp(timestamp)).append("\n");
                sb.append("Tipo: ").append(reasonLabel(reason)).append("\n");
                if (desc != null && !desc.toString().isEmpty())
                    sb.append("Descripción: ").append(desc).append("\n");
                sb.append("Estado del proceso: ").append(importanceLabel(importance)).append("\n");
                sb.append("Código de salida: ").append(status).append("\n");
                if (processName != null && !processName.isEmpty())
                    sb.append("Proceso: ").append(processName).append("\n");
                if (pss >= 0 || rss >= 0)
                    sb.append("Memoria PSS/RSS: ").append(pss).append("KB / ").append(rss).append("KB\n");

                // ApplicationExitInfo.getTraceInputStream() -- for CRASH_NATIVE (5) and
                // ANR (6) this can carry the actual native backtrace/tombstone data the
                // summary fields above never include. Requires API 31 (Android 12);
                // the reflective getMethod() call below would just throw
                // NoSuchMethodException and no-op on API 30, but checking explicitly
                // avoids relying on that silently swallowing the wrong kind of failure.
                // Best-effort even on 31+: these traces live in a system-wide circular
                // buffer shared with every other app on the device, so many OEM builds
                // (or ones simply queried too late) return null here -- this is
                // strictly additive, it never changes what gets returned on failure.
                if ((reason == 5 || reason == 6) && Build.VERSION.SDK_INT >= 31) {
                    // Every saved trace is stamped with the build/device/process
                    // it actually came from, so the file is self-describing --
                    // no need to separately track "which build was this from"
                    // when handing the .log off for symbolication later.
                    String header = "=== Native crash trace metadata ===\n"
                        + "Reason: " + reasonLabel(reason) + "\n"
                        + "Timestamp: " + timestamp + " (" + formatTimestamp(timestamp) + ")\n"
                        + "PID: " + pid + "\n"
                        + (processName != null && !processName.isEmpty() ? "Process: " + processName + "\n" : "")
                        + "Memory PSS/RSS KB: " + pss + " / " + rss + "\n"
                        + "Build: " + (prevBuildInfo != null ? prevBuildInfo : "unknown") + "\n"
                        + "=== raw tombstone data follows ===\n";
                    String tracePath = saveTraceIfPresent(cls, info, pid, timestamp, header);
                    if (tracePath != null) sb.append("Trace guardado en: ").append(tracePath).append("\n");
                }

                // logcat catches everything our own Haxe-level Logger/GameLogger
                // never sees -- GameLogger only hooks haxe.Log.trace, so any
                // native C/C++ logging from SDL, VLC, mbedtls, or debuggerd
                // itself (e.g. the human-readable "Fatal signal 11 (SIGSEGV)..."
                // line the kernel/debuggerd writes for every native crash,
                // often with a partial backtrace already in plain text) never
                // reaches a file at all otherwise. Not gated to reason 5/6 like
                // the tombstone above -- OOM kills and other exit reasons can
                // still have useful context in logcat (e.g. the low-memory
                // killer's own log lines), and this is cheap either way.
                String logcatPath = saveLogcatDump(pid, timestamp);
                if (logcatPath != null) sb.append("Logcat guardado en: ").append(logcatPath).append("\n");
            }

            // Persist even if nothing newsworthy was found this time, so a run
            // of clean exits (SIGNALED/LOW_MEMORY filtered out, etc.) doesn't
            // get re-scanned in full on every future launch either.
            saveLastSeenTimestamp(newestTimestamp);

            pruneOldTraceFiles();

            if (sb == null) return null;

            String header = "";
            if (prevBuildInfo != null) header += "Build (sesión anterior): " + prevBuildInfo + "\n\n";
            if (newCount > 1)
                header += "(" + newCount + " salidas anómalas detectadas desde el último inicio"
                    + " -- si hubo una actualización de la app entre ellas, el build de arriba"
                    + " solo aplica con certeza a la más reciente)\n\n";
            if (!header.isEmpty()) sb.insert(0, header);

            return sb.toString();

        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Copies ApplicationExitInfo.getTraceInputStream() (if the OEM/OS actually
     * populated it) to a file next to crash.log, so a native crash leaves
     * something more useful than the bare summary above to diagnose from.
     *
     * Named per pid+timestamp (not a single fixed "native_crash_trace.log")
     * so a second crash before the user has grabbed the first one's trace
     * doesn't silently overwrite it.
     *
     * @return the saved file's absolute path, or null if there was no trace
     * data to save (either the method returned null, or writing failed).
     */
    private static String saveTraceIfPresent(Class<?> infoClass, Object info, int pid, long timestamp, String header) {
        InputStream in = null;
        try {
            Method getTrace = infoClass.getMethod("getTraceInputStream");
            in = (InputStream) getTrace.invoke(info);
            if (in == null) return null;

            String dir = sCrashLogPath != null ? new File(sCrashLogPath).getParent() : null;
            if (dir == null) return null;
            File outFile = new File(dir, "native_crash_trace_" + pid + "_" + timestamp + ".log");

            File parent = outFile.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();

            FileOutputStream out = new FileOutputStream(outFile, false);
            if (header != null) out.write(header.getBytes("UTF-8"));
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            out.close();

            return outFile.getAbsolutePath();
        } catch (Exception e) {
            return null;
        } finally {
            if (in != null) {
                try { in.close(); } catch (IOException ignored) {}
            }
        }
    }

    /**
     * Dumps this app's own recent logcat history to a file, best-effort.
     *
     * No special permission needed: since Android 4.1, logd restricts a
     * non-privileged app's `logcat` read to its own UID's lines by default
     * (READ_LOGS is only required to read OTHER apps' logs) -- confirmed via
     * AOSP's logd source (LogReader's UID filtering). "-d" dumps the current
     * buffer and exits instead of streaming, "-t 3000" caps it to the most
     * recent 3000 lines so a device with a long-lived log buffer doesn't
     * balloon this into a huge file. No --pid filter: this app's own dead
     * process from a past run has no live PID for logd to filter by, and the
     * UID restriction above already scopes the dump to relevant lines
     * (plus this app's own logcat commonly also includes the crashing
     * process's own tag from debuggerd/ART even after it's gone, e.g. the
     * kernel's "Fatal signal 11 (SIGSEGV)..." line for a native crash).
     *
     * @return the saved file's absolute path, or null if the dump failed or
     * produced nothing (logcat access revoked by the OEM, no permission,
     * process spawn failure, etc.)
     */
    private static String saveLogcatDump(int pid, long timestamp) {
        Process proc = null;
        try {
            String dir = sCrashLogPath != null ? new File(sCrashLogPath).getParent() : null;
            if (dir == null) return null;

            // redirectErrorStream(true): merges stderr into the same stream we
            // read below. Without it, if logcat ever wrote enough to stderr to
            // fill its pipe buffer while we're only draining stdout, the child
            // would block on write() and this whole call would hang -- exactly
            // the kind of thing a crash handler must never risk doing.
            ProcessBuilder pb = new ProcessBuilder("logcat", "-d", "-t", "3000", "-v", "threadtime");
            pb.redirectErrorStream(true);
            proc = pb.start();

            File outFile = new File(dir, "logcat_dump_" + pid + "_" + timestamp + ".log");
            File parent = outFile.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();

            BufferedReader reader = new BufferedReader(
                new java.io.InputStreamReader(proc.getInputStream(), "UTF-8"));
            FileWriter writer = new FileWriter(outFile, false);
            String line;
            int lineCount = 0;
            while ((line = reader.readLine()) != null) {
                writer.write(line);
                writer.write('\n');
                lineCount++;
            }
            writer.close();
            reader.close();
            proc.waitFor();

            if (lineCount == 0) {
                outFile.delete();
                return null;
            }

            return outFile.getAbsolutePath();
        } catch (Exception e) {
            return null;
        } finally {
            if (proc != null) proc.destroy();
        }
    }

    /**
     * Each saved trace/logcat dump now gets its own pid+timestamp filename
     * (see saveTraceIfPresent()/saveLogcatDump()) specifically so multiple
     * crashes don't clobber each other -- but that also means they never got
     * cleaned up on their own. Keeps only the newest maxKept on disk per
     * prefix, oldest first by last-modified time, so a device that crashes
     * occasionally over a long install doesn't quietly accumulate files
     * forever. Each file category is pruned to its own cap independently
     * (called once per prefix) since logcat dumps and tombstones have very
     * different typical sizes.
     */
    private static final int MAX_KEPT_TRACES = 10;
    private static final int MAX_KEPT_LOGCAT_DUMPS = 10;

    private static void pruneOldFiles(final String prefix, int maxKept) {
        try {
            String dir = sCrashLogPath != null ? new File(sCrashLogPath).getParent() : null;
            if (dir == null) return;

            File[] matches = new File(dir).listFiles(new FilenameFilter() {
                @Override
                public boolean accept(File d, String name) {
                    return name.startsWith(prefix) && name.endsWith(".log");
                }
            });
            if (matches == null || matches.length <= maxKept) return;

            Arrays.sort(matches, new Comparator<File>() {
                @Override
                public int compare(File a, File b) {
                    return Long.compare(a.lastModified(), b.lastModified());
                }
            });

            int toDelete = matches.length - maxKept;
            for (int i = 0; i < toDelete; i++) {
                matches[i].delete();
            }
        } catch (Exception ignored) {}
    }

    private static void pruneOldTraceFiles() {
        pruneOldFiles("native_crash_trace_", MAX_KEPT_TRACES);
        pruneOldFiles("logcat_dump_", MAX_KEPT_LOGCAT_DUMPS);
    }

    /**
     * Timestamp (ApplicationExitInfo.getTimestamp(), ms since epoch) of the
     * newest exit already processed by readPreviousNativeCrash(), so Android's
     * own (non-clearing) exit history doesn't get re-reported forever.
     */
    private static long loadLastSeenTimestamp() {
        String dir = sCrashLogPath != null ? new File(sCrashLogPath).getParent() : null;
        if (dir == null) return 0L;
        File marker = new File(dir, ".last_exit_info_timestamp");
        if (!marker.exists()) return 0L;

        BufferedReader br = null;
        try {
            br = new BufferedReader(new FileReader(marker));
            String line = br.readLine();
            return line != null ? Long.parseLong(line.trim()) : 0L;
        } catch (Exception e) {
            return 0L;
        } finally {
            if (br != null) {
                try { br.close(); } catch (IOException ignored) {}
            }
        }
    }

    private static void saveLastSeenTimestamp(long timestamp) {
        String dir = sCrashLogPath != null ? new File(sCrashLogPath).getParent() : null;
        if (dir == null) return;
        try {
            File marker = new File(dir, ".last_exit_info_timestamp");
            FileWriter fw = new FileWriter(marker, false);
            fw.write(Long.toString(timestamp));
            fw.close();
        } catch (Exception ignored) {}
    }

    /**
     * A one-line fingerprint of the build/device currently running --
     * versionName/versionCode (which .so this maps to), ABI (which arch's
     * addresses these are), and device/OS (device-specific crash quirks).
     * Written to disk every launch (see saveCurrentBuildInfo()) so the NEXT
     * launch, reading a crash this session may not survive to report itself,
     * can attribute it to the exact build that produced it.
     */
    private static String buildCurrentBuildInfo() {
        try {
            Activity activity = mainActivity;
            if (activity == null) return null;
            PackageManager pm = activity.getPackageManager();
            PackageInfo pkgInfo = pm.getPackageInfo(activity.getPackageName(), 0);
            long versionCode = Build.VERSION.SDK_INT >= 28 ? pkgInfo.getLongVersionCode() : pkgInfo.versionCode;

            return "versionName=" + pkgInfo.versionName
                + " versionCode=" + versionCode
                + " abi=" + (Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "?")
                + " device=" + Build.MANUFACTURER + " " + Build.MODEL
                + " androidSdk=" + Build.VERSION.SDK_INT
                + " androidRelease=" + Build.VERSION.RELEASE;
        } catch (Exception e) {
            return null;
        }
    }

    private static String loadPreviousBuildInfo() {
        String dir = sCrashLogPath != null ? new File(sCrashLogPath).getParent() : null;
        if (dir == null) return null;
        File marker = new File(dir, ".last_build_info");
        if (!marker.exists()) return null;

        BufferedReader br = null;
        try {
            br = new BufferedReader(new FileReader(marker));
            return br.readLine();
        } catch (Exception e) {
            return null;
        } finally {
            if (br != null) {
                try { br.close(); } catch (IOException ignored) {}
            }
        }
    }

    private static void saveCurrentBuildInfo() {
        String dir = sCrashLogPath != null ? new File(sCrashLogPath).getParent() : null;
        if (dir == null) return;
        String info = buildCurrentBuildInfo();
        if (info == null) return;
        try {
            File marker = new File(dir, ".last_build_info");
            FileWriter fw = new FileWriter(marker, false);
            fw.write(info);
            fw.close();
        } catch (Exception ignored) {}
    }

    private static String formatTimestamp(long epochMillis) {
        try {
            return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date(epochMillis));
        } catch (Exception e) {
            return String.valueOf(epochMillis);
        }
    }

    // ── UncaughtExceptionHandler impl ────────────────────────────────────────

    @Override
    public void uncaughtException(Thread thread, Throwable throwable) {
        try {
            StringWriter sw = new StringWriter();
            throwable.printStackTrace(new PrintWriter(sw));

            String report = "Java/JNI crash\n"
                + "Thread: " + thread.getName() + "\n\n"
                + "Exception: " + throwable + "\n\n"
                + "Callstack:\n" + sw.toString();

            writeCrashLog(sCrashLogPath, report);
        } catch (Throwable ignored) {
            // If writing fails we still forward to the original handler.
        }

        if (sOriginalHandler != null)
            sOriginalHandler.uncaughtException(thread, throwable);
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    private static void writeCrashLog(String path, String content) throws IOException {
        File file = new File(path);
        File parent = file.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        FileWriter fw = new FileWriter(file, false);
        fw.write(content);
        fw.close();
    }

    private static String reasonLabel(int reason) {
        switch (reason) {
            case 2:  return "SIGNAL (SIGKILL / sistema)";
            case 3:  return "LOW MEMORY / OOM";
            case 4:  return "JAVA CRASH";
            case 5:  return "NATIVE CRASH (SIGSEGV / SIGABRT)";
            case 6:  return "ANR (App Not Responding)";
            case 7:  return "INITIALIZATION FAILURE";
            case 8:  return "PERMISSION CHANGE";
            case 9:  return "EXCESSIVE RESOURCE USAGE";
            default: return "CÓDIGO " + reason;
        }
    }

    private static String importanceLabel(int importance) {
        // ActivityManager.RunningAppProcessInfo importance levels
        if (importance <= 100) return "FOREGROUND";
        if (importance <= 130) return "FOREGROUND SERVICE";
        if (importance <= 200) return "VISIBLE";
        if (importance <= 300) return "PERCEPTIBLE";
        if (importance <= 400) return "SERVICE";
        return "BACKGROUND";
    }
}
