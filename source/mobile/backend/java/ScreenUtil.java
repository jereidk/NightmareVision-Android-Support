package mobile.backend.java;

import android.app.Activity;
import android.os.Build;
import android.view.DisplayCutout;
import android.view.View;
import android.view.WindowInsets;
import org.haxe.extension.Extension;

public class ScreenUtil extends Extension {

    private static int cachedTop    = -1;
    private static int cachedBottom =  0;
    private static int cachedLeft   =  0;
    private static int cachedRight  =  0;

    private static void ensureCached() {
        if (cachedTop >= 0) return;

        cachedTop = 0;

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return;

        Activity activity = mainActivity;
        if (activity == null) return;

        try {
            View decorView = activity.getWindow().getDecorView();
            WindowInsets windowInsets = decorView.getRootWindowInsets();
            if (windowInsets == null) return;

            DisplayCutout cutout = windowInsets.getDisplayCutout();
            if (cutout == null) return;

            float density = activity.getResources().getDisplayMetrics().density;
            if (density <= 0f) density = 1f;

            cachedTop    = Math.round(cutout.getSafeInsetTop()    / density);
            cachedBottom = Math.round(cutout.getSafeInsetBottom() / density);
            cachedLeft   = Math.round(cutout.getSafeInsetLeft()   / density);
            cachedRight  = Math.round(cutout.getSafeInsetRight()  / density);
        } catch (Exception e) {
            // Graceful fallback — zeros remain.
        }
    }

    public static int getSafeInsetTop()    { ensureCached(); return cachedTop;    }
    public static int getSafeInsetBottom() { ensureCached(); return cachedBottom; }
    public static int getSafeInsetLeft()   { ensureCached(); return cachedLeft;   }
    public static int getSafeInsetRight()  { ensureCached(); return cachedRight;  }
}
