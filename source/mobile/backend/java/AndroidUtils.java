package mobile.backend.java;

import android.app.Activity;
import android.app.GameManager;
import android.app.GameState;
import android.content.Context;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.view.View;
import android.view.WindowManager;
import android.view.WindowInsetsController;
import org.haxe.extension.Extension;
import java.io.File;
import java.io.IOException;

public class AndroidUtils extends Extension {

    private static int _fullscreenMode = 0; // 0=off, 1=status bar only, 2=full immersive

    public static void keepScreenOn(final boolean enable) {
        final Activity activity = mainActivity;
        if (activity == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (enable) {
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                } else {
                    activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            }
        });
    }

    /**
     * Sets fullscreen/immersive mode.
     * mode: 0=off (normal), 1=hide status bar, 2=full immersive (hide both bars)
     */
    public static void setFullscreen(final int mode) {
        final Activity activity = mainActivity;
        if (activity == null) return;
        _fullscreenMode = mode;

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                View decorView = activity.getWindow().getDecorView();

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Android 11+ (API 30+)
                    WindowInsetsController controller = decorView.getWindowInsetsController();
                    if (controller != null) {
                        if (mode >= 1) {
                            // Hide system bars
                            controller.hide(android.view.WindowInsets.Type.statusBars());
                            controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                        }
                        if (mode >= 2) {
                            controller.hide(android.view.WindowInsets.Type.navigationBars());
                        }
                        if (mode == 0) {
                            // Show all bars
                            controller.show(android.view.WindowInsets.Type.statusBars() | android.view.WindowInsets.Type.navigationBars());
                        }
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    // Android 4.4 - 10 (API 19-29)
                    if (mode >= 1) {
                        decorView.setSystemUiVisibility(
                            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        );
                    } else {
                        decorView.setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE);
                    }
                }

                // Also set window flags for older compatibility
                if (mode >= 1) {
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
                } else {
                    activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
                    activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
                }
            }
        });
    }

    /**
     * Returns current fullscreen mode.
     * 0=off, 1=status bar only, 2=full immersive
     */
    public static int getFullscreen() {
        return _fullscreenMode;
    }

    /**
     * Toggles between current and off state.
     */
    public static void toggleFullscreen() {
        if (_fullscreenMode > 0) {
            setFullscreen(0);
        } else {
            setFullscreen(2); // Default to full immersive
        }
    }

    @SuppressWarnings("deprecation")
    public static void vibrate(int ms) {
        final Activity activity = mainActivity;
        if (activity == null) return;

        Vibrator vibrator;
        if (Build.VERSION.SDK_INT >= 31) {
            VibratorManager vm = (VibratorManager) activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            vibrator = (vm != null) ? vm.getDefaultVibrator() : null;
        } else {
            vibrator = (Vibrator) activity.getSystemService(Context.VIBRATOR_SERVICE);
        }

        if (vibrator == null || !vibrator.hasVibrator()) return;

        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE));
        } else {
            vibrator.vibrate(ms);
        }
    }

    /**
     * Scans a folder using Android's MediaScanner to make it visible in file managers.
     * Uses MediaScannerConnection to add the folder to the media store.
     * Similar to FunkinCrew/Funkin's "Data Folder" approach.
     */
    public static void scanFolder(final String folderPath) {
        if (folderPath == null || folderPath.isEmpty()) return;
        
        final Activity activity = mainActivity;
        if (activity == null) return;
        
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    File folder = new File(folderPath);
                    if (!folder.exists()) return;
                    
                    // Create a .nomedia file to prevent media scanning of game content
                    // but still make the folder itself visible
                    File nomediaFile = new File(folderPath, ".nomedia");
                    if (!nomediaFile.exists()) {
                        nomediaFile.createNewFile();
                    }
                    
                    // Use MediaScannerConnection to scan the folder
                    // This makes it visible in file managers like the native "Files" app
                    String[] paths = { folderPath };
                    MediaScannerConnection.scanFile(
                        activity.getApplicationContext(),
                        paths,
                        null,
                        new MediaScannerConnection.OnScanCompletedListener() {
                            @Override
                            public void onScanCompleted(String path, Uri uri) {
                                android.util.Log.i("AndroidUtils", "Scanned folder: " + path);
                            }
                        }
                    );
                } catch (Exception e) {
                    android.util.Log.e("AndroidUtils", "Error scanning folder: " + e.toString());
                }
            }
        });
    }

    /**
     * Signals Android's game scheduler what the app is currently doing.
     * inGameplay=true  → MODE_GAMEPLAY_INTERRUPTIBLE (2): raises CPU/GPU governor target
     * inGameplay=false → MODE_NONE (1): allows scheduler to throttle between sessions
     * Requires API 33 (Android 13); silently no-ops on older devices.
     */
    public static void setGameplayState(final boolean inGameplay) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return;
        final Activity activity = mainActivity;
        if (activity == null) return;
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    GameManager gm = (GameManager) activity.getSystemService(Context.GAME_SERVICE);
                    if (gm == null) return;
                    // API 33 GameState mode literals (avoids compileSdk 33 requirement):
                    // MODE_GAMEPLAY_INTERRUPTIBLE=2, MODE_NONE=1, MODE_UNKNOWN=0
                    int mode = inGameplay ? 2 : 1;
                    gm.setGameState(new GameState(false, mode));
                } catch (Exception e) {
                    android.util.Log.w("AndroidUtils", "setGameplayState: " + e);
                }
            }
        });
    }

    /**
     * Opens the data folder in the system file manager.
     * Similar to FunkinCrew/Funkin's "Open Data Folder" and Shadow Engine's approach.
     * This uses Android's Intent system to open the folder in the user's preferred file manager.
     */
    public static void openDataFolder(final String folderPath) {
        if (folderPath == null || folderPath.isEmpty()) return;
        
        final Activity activity = mainActivity;
        if (activity == null) return;
        
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    File folder = new File(folderPath);
                    if (!folder.exists()) {
                        android.util.Log.w("AndroidUtils", "Data folder does not exist: " + folderPath);
                        return;
                    }
                    
                    // First, scan the folder to ensure it's indexed
                    String[] paths = { folderPath };
                    MediaScannerConnection.scanFile(
                        activity.getApplicationContext(),
                        paths,
                        null,
                        null
                    );

                    String canonicalPath;
                    try { canonicalPath = folder.getCanonicalPath(); }
                    catch (IOException e) { canonicalPath = folder.getAbsolutePath(); }

                    // Jump straight into this app's own DocumentsProvider root
                    // (ModFolderDocumentsProvider, registered in AndroidManifest).
                    // The previous approach used Uri.fromFile() with ACTION_VIEW, which
                    // throws FileUriExposedException on Android 7+ when handed to
                    // another app — that was the file:// URI's fault, not ACTION_VIEW
                    // itself, so it's tried again below with the proper content:// URI.
                    android.net.Uri docUri = android.provider.DocumentsContract.buildDocumentUri(
                        "com.motorfrog.impostor.documents", canonicalPath);

                    // Three attempts, best (most direct) to worst (always works):
                    //   1. ACTION_VIEW — what most third-party file managers register
                    //      for a directory content:// URI.
                    //   2. ACTION_BROWSE ("android.provider.action.BROWSE") — @hide in
                    //      AOSP, never exposed as a public SDK field so it's referenced
                    //      by its literal string, but it's what the stock Google Files
                    //      app specifically implements.
                    //   3. The standard SAF tree picker, guaranteed to resolve on every
                    //      device — handed EXTRA_INITIAL_URI so it opens AT the mod
                    //      folder instead of dumping the user at the storage root to
                    //      dig through manually.
                    // Neither 1 nor 2 has a registered handler on plenty of real
                    // devices (MIUI, older Samsung skins, etc), throwing
                    // ActivityNotFoundException — that's expected, not an error.
                    boolean opened = false;
                    for (String action : new String[] { android.content.Intent.ACTION_VIEW, "android.provider.action.BROWSE" }) {
                        try {
                            android.content.Intent intent = new android.content.Intent(action);
                            intent.setDataAndType(docUri, android.provider.DocumentsContract.Document.MIME_TYPE_DIR);
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                            intent.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION);
                            activity.startActivity(intent);
                            opened = true;
                            break;
                        } catch (Exception e1) {
                            android.util.Log.w("AndroidUtils", action + " has no handler, trying next: " + e1);
                        }
                    }

                    if (!opened) {
                        android.content.Intent fallback = new android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT_TREE);
                        fallback.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                        fallback.putExtra(android.content.Intent.EXTRA_INITIAL_URI, docUri);
                        activity.startActivity(fallback);
                    }
                } catch (Exception e) {
                    android.util.Log.e("AndroidUtils", "Error opening data folder: " + e.toString());
                }
            }
        });
    }

    private static android.view.Display getDisplay(Activity activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return activity.getDisplay();
        }
        return activity.getWindowManager().getDefaultDisplay();
    }

    /**
     * Highest refresh rate (Hz) among the display's supported modes. Reflects
     * what the screen can actually do only after requestHighRefreshRate() has
     * been called — otherwise Android reports whatever mode is currently
     * active, which defaults to 60Hz even on faster panels.
     */
    public static float getMaxRefreshRate() {
        final Activity activity = mainActivity;
        if (activity == null) return 60f;

        try {
            android.view.Display display = getDisplay(activity);
            if (display == null) return 60f;

            float maxRate = display.getRefreshRate();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                for (android.view.Display.Mode mode : display.getSupportedModes()) {
                    if (mode.getRefreshRate() > maxRate) maxRate = mode.getRefreshRate();
                }
            }
            return maxRate;
        } catch (Exception e) {
            android.util.Log.e("AndroidUtils", "getMaxRefreshRate failed: " + e);
            return 60f;
        }
    }

    /**
     * Opts the window into its highest supported display refresh rate mode.
     * Android defaults every app to 60Hz regardless of the panel's real
     * capability until an app explicitly requests a faster mode.
     */
    public static void requestHighRefreshRate() {
        final Activity activity = mainActivity;
        if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return;

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    android.view.Display display = getDisplay(activity);
                    if (display == null) return;

                    android.view.Display.Mode best = display.getMode();
                    for (android.view.Display.Mode mode : display.getSupportedModes()) {
                        if (mode.getRefreshRate() > best.getRefreshRate()) best = mode;
                    }

                    android.view.WindowManager.LayoutParams params = activity.getWindow().getAttributes();
                    params.preferredDisplayModeId = best.getModeId();
                    activity.getWindow().setAttributes(params);
                } catch (Exception e) {
                    android.util.Log.e("AndroidUtils", "requestHighRefreshRate failed: " + e);
                }
            }
        });
    }
}
