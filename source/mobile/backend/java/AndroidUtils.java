package mobile.backend.java;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.view.View;
import android.view.WindowManager;
import android.view.WindowInsetsController;
import org.haxe.extension.Extension;

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
}
