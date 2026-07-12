package mobile.backend.java;

import android.app.Activity;
import android.app.GameManager;
import android.app.GameState;
import android.content.Context;
import android.content.Intent;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.view.View;
import android.view.WindowManager;
import android.view.WindowInsetsController;
import android.widget.Toast;
import org.haxe.extension.Extension;
import java.io.File;
import java.io.IOException;

public class AndroidUtils extends Extension {

    private static int _fullscreenMode = 0; // 0=off, 1=status bar only, 2=full immersive

    // FileUtils.java (same package) already uses 1024-1026 for its own
    // startActivityForResult() calls -- keep this distinct so results don't collide.
    private static final int OPEN_DATA_FOLDER_CODE = 1027;

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
                    android.net.Uri docUri = android.provider.DocumentsContract.buildDocumentUri(
                        "com.motorfrog.impostor.documents", canonicalPath);

                    // ModFolderDocumentsProvider is declared with
                    // android:permission="android.permission.MANAGE_DOCUMENTS" (the
                    // correct, standard way to expose a DocumentsProvider) — but that
                    // permission is signature-only and no third-party app can ever hold
                    // it. There is also no universal "open this exact folder" intent
                    // that arbitrary file manager apps support (confirmed against real
                    // reports, e.g. github.com/syncthing/syncthing-android/issues/838),
                    // so ACTION_VIEW/ACTION_BROWSE straight to a random file manager
                    // isn't reliable either. The system's own SAF tree picker
                    // (DocumentsUI) is the one caller guaranteed to hold MANAGE_DOCUMENTS
                    // on every device, so it's the only reliably-working path.
                    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
                    // Intent.EXTRA_INITIAL_URI is API 26+ and isn't exposed by this
                    // project's compileSdk stub jar ("cannot find symbol"), so it's
                    // referenced by its literal Bundle key instead. The key itself works
                    // on any OS version; older ones that don't understand it just
                    // ignore it and open at the default root.
                    intent.putExtra("android.provider.extra.INITIAL_URI", docUri);
                    // No FLAG_ACTIVITY_NEW_TASK here -- per Android's own
                    // startActivityForResult() docs, that flag makes the launched
                    // activity run in a different task, so "you will immediately
                    // receive a cancel result" instead of the real one. It was also
                    // never needed: this call already runs from a real Activity
                    // instance, not a bare Application/Service Context.
                    activity.startActivityForResult(intent, OPEN_DATA_FOLDER_CODE);
                } catch (Exception e) {
                    android.util.Log.e("AndroidUtils", "Error opening data folder: " + e.toString());
                }
            }
        });
    }

    /**
     * Handles the result of the OPEN_DATA_FOLDER_CODE picker started in
     * openDataFolder(). Without this override the picker's "confirm"/"use this
     * folder" button had nothing to report to -- this is what makes it
     * actually do something instead of silently closing.
     */
    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == OPEN_DATA_FOLDER_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Uri treeUri = data.getData();
                if (treeUri != null) {
                    try {
                        // Persist the grant so it survives past this process (otherwise
                        // it's revoked as soon as the app is killed).
                        mainActivity.getContentResolver().takePersistableUriPermission(treeUri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                    } catch (Exception e) {
                        android.util.Log.w("AndroidUtils", "Could not persist data folder permission: " + e);
                    }
                    Toast.makeText(mainActivity, "Data folder selected", Toast.LENGTH_SHORT).show();
                }
            }
            return true;
        }
        return false;
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
