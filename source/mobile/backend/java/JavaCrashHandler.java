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
import java.lang.reflect.Method;
import java.util.List;

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
     * Read Android's ApplicationExitInfo (API 30 / Android 11+) for the most
     * recent process exit from the previous session.  Uses reflection so this
     * compiles against any compileSdkVersion.
     *
     * @return human-readable summary if the exit was abnormal, null otherwise
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
            Method getReasons = ActivityManager.class.getDeclaredMethod(
                "getHistoricalProcessExitReasons",
                String.class, int.class, int.class);

            @SuppressWarnings("unchecked")
            List<Object> exits = (List<Object>) getReasons.invoke(am, null, 0, 1);
            if (exits == null || exits.isEmpty()) return null;

            Object info = exits.get(0);
            Class<?> cls = info.getClass();

            int reason = (int) cls.getMethod("getReason").invoke(info);

            // ApplicationExitInfo reason constants (API 30):
            //   UNKNOWN=0, EXIT_SELF=1, SIGNALED=2, LOW_MEMORY=3,
            //   CRASH=4, CRASH_NATIVE=5, ANR=6, INITIALIZATION_FAILURE=7,
            //   PERMISSION_CHANGE=8, EXCESSIVE_RESOURCE_USAGE=9, USER_REQUESTED=10
            // Skip clean/expected exits (UNKNOWN, EXIT_SELF, USER_REQUESTED).
            if (reason == 0 || reason == 1 || reason == 10) return null;

            Object desc = cls.getMethod("getDescription").invoke(info);
            int importance = (int) cls.getMethod("getImportance").invoke(info);
            int status    = (int) cls.getMethod("getStatus").invoke(info);

            StringBuilder sb = new StringBuilder("Crash detectado (sesión anterior)\n\n");
            sb.append("Tipo: ").append(reasonLabel(reason)).append("\n");
            if (desc != null && !desc.toString().isEmpty())
                sb.append("Descripción: ").append(desc).append("\n");
            sb.append("Estado del proceso: ").append(importanceLabel(importance)).append("\n");
            sb.append("Código de salida: ").append(status).append("\n");
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
