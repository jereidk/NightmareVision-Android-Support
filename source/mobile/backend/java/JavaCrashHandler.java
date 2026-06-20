package mobile.backend.java;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.os.Build;
import org.haxe.extension.Extension;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.List;

/**
 * Two-pronged native crash capture for Android:
 *
 *  1. Java UncaughtExceptionHandler — catches Java/JNI exceptions that escape
 *     all other handlers and writes them to crash.log before the process dies.
 *
 *  2. ApplicationExitInfo reader (API 30+) — reads Android's built-in record
 *     of why the PREVIOUS session ended (SIGSEGV, OOM, ANR, …).  The OS writes
 *     this automatically even for pure-C++ crashes that kill the process before
 *     any Java or Haxe handler can run.
 */
public class JavaCrashHandler extends Extension implements Thread.UncaughtExceptionHandler {

    private static Thread.UncaughtExceptionHandler sOriginalHandler;
    private static String sCrashLogPath;
    private static volatile boolean sInstalled = false;

    // ── public API called from Haxe via JNI ─────────────────────────────────

    /**
     * Install the Java-level uncaught exception handler.
     * Must be called once at startup, before any other init.
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
     * Check Android's ApplicationExitInfo (API 30 / Android 11+) for the
     * most recent process exit that was a crash, native crash, ANR or OOM.
     *
     * @return a human-readable summary string, or null if none found / API < 30
     */
    public static String readPreviousNativeCrash() {
        if (Build.VERSION.SDK_INT < 30) return null;

        Activity activity = mainActivity;
        if (activity == null) return null;

        try {
            ActivityManager am =
                (ActivityManager) activity.getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return null;

            // Most-recent-first; we care only about the last exit.
            List<ActivityManager.ApplicationExitInfo> exits =
                am.getHistoricalProcessExitReasons(null, 0, 1);

            if (exits == null || exits.isEmpty()) return null;

            ActivityManager.ApplicationExitInfo info = exits.get(0);
            int reason = info.getReason();

            // Only surface abnormal exits.
            if (reason != ActivityManager.ApplicationExitInfo.REASON_CRASH
                && reason != ActivityManager.ApplicationExitInfo.REASON_CRASH_NATIVE
                && reason != ActivityManager.ApplicationExitInfo.REASON_ANR
                && reason != ActivityManager.ApplicationExitInfo.REASON_SIGNAL
                && reason != ActivityManager.ApplicationExitInfo.REASON_OOM) {
                return null;
            }

            StringBuilder sb = new StringBuilder();
            sb.append("Crash detectado (sesión anterior)\n\n");
            sb.append("Tipo: ").append(reasonLabel(reason)).append("\n");

            String desc = info.getDescription();
            if (desc != null && !desc.isEmpty())
                sb.append("Descripción: ").append(desc).append("\n");

            sb.append("Estado del proceso: ").append(importanceLabel(info.getImportance())).append("\n");
            sb.append("Código de salida: ").append(info.getStatus()).append("\n");

            return sb.toString();

        } catch (Exception e) {
            return null;
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
            // If writing fails we still want the original handler to run.
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
            case ActivityManager.ApplicationExitInfo.REASON_CRASH:
                return "JAVA CRASH";
            case ActivityManager.ApplicationExitInfo.REASON_CRASH_NATIVE:
                return "NATIVE CRASH (SIGSEGV / SIGABRT / similar)";
            case ActivityManager.ApplicationExitInfo.REASON_ANR:
                return "ANR (App Not Responding)";
            case ActivityManager.ApplicationExitInfo.REASON_SIGNAL:
                return "SIGNAL";
            case ActivityManager.ApplicationExitInfo.REASON_OOM:
                return "OUT OF MEMORY";
            default:
                return "CODE " + reason;
        }
    }

    private static String importanceLabel(int importance) {
        // Values from ActivityManager.RunningAppProcessInfo
        if (importance <= 100) return "FOREGROUND";
        if (importance <= 130) return "FOREGROUND SERVICE";
        if (importance <= 200) return "VISIBLE";
        if (importance <= 300) return "PERCEPTIBLE";
        if (importance <= 400) return "SERVICE";
        return "BACKGROUND";
    }
}
