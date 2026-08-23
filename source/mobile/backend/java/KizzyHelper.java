package mobile.backend.java;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.util.Log;
import org.haxe.extension.Extension;
import java.io.File;
import java.io.InputStream;
import java.io.IOException;

// By ArkoseLabs
public class KizzyHelper extends Extension {
    private static MediaSession mediaSession;
    private static NotificationManager notificationManager;

    private static final String CHANNEL_ID = "psych_silent_mode_v1"; 
    private static final int NOTIFICATION_ID = 111;
    private static final String TAG = "KizzyHelper";

    public static void initialize() {
        if (Extension.mainActivity == null) return;

        Extension.mainActivity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    Context context = Extension.mainContext;
                    if (mediaSession == null) {
                        mediaSession = new MediaSession(context, "PsychSession");
                        mediaSession.setCallback(new MediaSession.Callback() {});
                        mediaSession.setFlags(MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS | MediaSession.FLAG_HANDLES_MEDIA_BUTTONS);
                        mediaSession.setActive(true);

                        notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
                        createNotificationChannel();
                        
                        Log.d(TAG, "Session started in the background.");
                        JavaCrashHandler.appendToGameLog(TAG, "INFO", "Session started in the background.");
                    }

                    if (Build.VERSION.SDK_INT >= 33) {
                        Extension.mainActivity.requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 101);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "INIT ERROR: " + e.getMessage());
                    JavaCrashHandler.appendToGameLog(TAG, "ERROR", "INIT ERROR: " + e);
                }
            }
        });
    }

    // Cache of the last decoded album art, keyed by the path it came from --
    // updateStatus() used to decode imagePath from scratch on every single
    // call, including the periodic resync calls PlayState now makes every
    // few seconds during gameplay to keep positionMs fresh (see
    // resyncIntervalSeconds in PlayState.hx) so Kizzy's progress bar
    // actually advances instead of sitting frozen at whatever position was
    // reported once. Re-decoding the same bitmap from disk/APK dozens of
    // times over a single song for no reason is exactly the kind of
    // per-frame-ish I/O churn this codebase has hunted down elsewhere.
    private static String lastImagePath = null;
    private static Bitmap lastAlbumArt = null;

    /**
     * @param positionMs Current elapsed playback position, milliseconds. Only
     *   meaningful while isPlaying -- Kizzy's own GetCurrentPlayingMedia only
     *   builds a progress-bar timestamp at all when PlaybackState.STATE_PLAYING,
     *   and computes it as `now - position` / `now + duration - position` on
     *   ITS OWN ~1s poll loop, not ours -- so a stale, never-updated position
     *   (e.g. always 0 from song start) makes the reported "start" timestamp
     *   drift later in lockstep with real time forever, which nets out to a
     *   progress bar that LOOKS frozen at that same original elapsed value,
     *   not one that resets or jumps. Needs periodic re-calls with a fresh
     *   position to actually advance.
     * @param durationMs Total song length, milliseconds. 0 disables the
     *   progress bar entirely (matches Kizzy's own `duration != 0L` check).
     *
     * int, not long, on this side of the JNI boundary -- matches every other
     * JNI call in this codebase (plain 32-bit ints/floats/strings/bools);
     * widened to long below only where Android's own MediaMetadata/
     * PlaybackState APIs require it. A song position/duration in
     * milliseconds comfortably fits an int (max ~24 days).
     */
    public static void updateStatus(final String title, final String artist, final String imagePath, final boolean isPlaying, final int positionMs, final int durationMs) {
        if (Extension.mainActivity == null) return;

        Extension.mainActivity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (mediaSession == null) { initialize(); return; }
                    Context context = Extension.mainContext;
                    Bitmap albumArt;

                    boolean pathChanged = imagePath != null ? !imagePath.equals(lastImagePath) : lastImagePath != null;
                    if (!pathChanged && lastAlbumArt != null) {
                        albumArt = lastAlbumArt;
                    } else {
                        albumArt = null;

                        if (imagePath != null && !imagePath.isEmpty()) {
                            try {
                                File imgFile = new File(imagePath);
                                if (imgFile.exists()) {
                                    albumArt = BitmapFactory.decodeFile(imgFile.getAbsolutePath());
                                }
                                else {
                                    AssetManager am = context.getAssets();
                                    InputStream istr = null;
                                    try {
                                        istr = am.open(imagePath);
                                    } catch (IOException e1) {
                                        try {
                                            istr = am.open("assets/" + imagePath);
                                        } catch (IOException e2) {
                                            if (imagePath.startsWith("assets/")) {
                                                istr = am.open(imagePath.substring(7));
                                            }
                                        }
                                    }
                                    if (istr != null) {
                                        albumArt = BitmapFactory.decodeStream(istr);
                                        istr.close();
                                    }
                                }
                            } catch (Exception e) {
                                Log.e(TAG, "Image could not be loaded: " + imagePath);
                                JavaCrashHandler.appendToGameLog(TAG, "ERROR", "Image could not be loaded: " + imagePath + " - " + e);
                            }
                        }

                        if (albumArt == null) {
                            albumArt = getAppIconAsBitmap(context);
                        }

                        lastImagePath = imagePath;
                        lastAlbumArt = albumArt;
                    }

                    MediaMetadata.Builder metadataBuilder = new MediaMetadata.Builder()
                            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                            .putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, albumArt);
                    if (durationMs > 0) {
                        metadataBuilder.putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs);
                    }
                    mediaSession.setMetadata(metadataBuilder.build());

                    // isPlaying=false (menus, or a paused song) must report STATE_PAUSED,
                    // not just skip the update -- Kizzy's own Media RPC polls this
                    // MediaSession independently of when we last called updateStatus(),
                    // so leaving it on STATE_PLAYING would keep showing "still playing"
                    // in Discord indefinitely after the player actually paused.
                    PlaybackState state = new PlaybackState.Builder()
                            .setActions(PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_SKIP_TO_NEXT)
                            .setState(isPlaying ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED, positionMs, isPlaying ? 1.0f : 0f)
                            .build();
                    mediaSession.setPlaybackState(state);

                    showNotification(title, artist, albumArt);

                } catch (Exception e) {
                    Log.e(TAG, "UPDATE ERROR: " + e.getMessage());
                    JavaCrashHandler.appendToGameLog(TAG, "ERROR", "UPDATE ERROR: " + e);
                }
            }
        });
    }

    private static void showNotification(String title, String artist, Bitmap art) {
        Context context = Extension.mainContext;
        Notification.Builder builder;

        if (Build.VERSION.SDK_INT >= 26) {
            builder = new Notification.Builder(context, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(context);
        }
        builder.setPriority(Notification.PRIORITY_MIN);

        Notification.MediaStyle style = new Notification.MediaStyle();
        style.setMediaSession(mediaSession.getSessionToken());
        style.setShowActionsInCompactView(0);

        builder.setVisibility(Notification.VISIBILITY_SECRET)
                .setSmallIcon(context.getApplicationInfo().icon)
                .setLargeIcon(art)
                .setContentTitle(title)
                .setContentText(artist)
                .setStyle(style)
                .setOngoing(true);

        notificationManager.notify(NOTIFICATION_ID, builder.build());
    }

    private static void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "Background Service", NotificationManager.IMPORTANCE_MIN);
            
            channel.setDescription("Running silently");
            channel.setShowBadge(false);
            channel.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
            
            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
            }
        }
    }

    public static void shutdown() {
        if (Extension.mainActivity == null) return;
        
        Extension.mainActivity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (mediaSession != null) {
                        mediaSession.setActive(false);
                        mediaSession.release();
                        mediaSession = null;
                    }
                    if (notificationManager != null) {
                        notificationManager.cancel(NOTIFICATION_ID);
                    }
                    Log.d(TAG, "MediaSession closed and cleared.");
                    JavaCrashHandler.appendToGameLog(TAG, "INFO", "MediaSession closed and cleared.");
                } catch (Exception e) {
                    Log.e(TAG, "SHUTDOWN ERROR: " + e.getMessage());
                    JavaCrashHandler.appendToGameLog(TAG, "ERROR", "SHUTDOWN ERROR: " + e);
                }
            }
        });
    }

    private static Bitmap getAppIconAsBitmap(Context context) {
        try {
            Drawable drawable = context.getPackageManager().getApplicationIcon(context.getPackageName());
            if (drawable instanceof BitmapDrawable) {
                return ((BitmapDrawable) drawable).getBitmap();
            }
            Bitmap bitmap = Bitmap.createBitmap(drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight(), Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bitmap);
            drawable.setBounds(0, 0, canvas.getWidth(), canvas.getHeight());
            drawable.draw(canvas);
            return bitmap;
        } catch (Exception e) {
            return null;
        }
    }
}