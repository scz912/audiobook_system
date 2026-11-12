package com.fyp.autism_audiobook

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Each time the app opens: if access is on but the phone stopped the
    // listener (battery savers, "clean up" tools), ask for it back.
    override fun onResume() {
        super.onResume()
        if (!MediaListenerService.connected && accessGranted()) MediaListenerService.rebind(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The personal account's "Top Music Genre" (see MediaListenerService).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "autism_audiobook/music_taste")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        val granted = accessGranted()
                        val listening = MediaListenerService.connected
                        // Access on but the listener isn't running: the
                        // phone stopped it. Ask Android to start it again.
                        if (granted && !listening) MediaListenerService.rebind(this)
                        result.success(mapOf(
                            "granted" to granted,
                            "listening" to listening,
                            "mayBeRestricted" to mayBeRestricted(),
                            "youtubeInstalled" to installed(MusicPlayLog.YOUTUBE),
                            "youtubeMusicInstalled" to installed(MusicPlayLog.YOUTUBE_MUSIC),
                            "youtubeLastSeen" to MusicPlayLog.lastSeen(this, MusicPlayLog.YOUTUBE),
                            "youtubeMusicLastSeen" to MusicPlayLog.lastSeen(this, MusicPlayLog.YOUTUBE_MUSIC),
                        ))
                    }
                    "openSettings" -> {
                        openAccessSettings()
                        result.success(null)
                    }
                    "openAppInfo" -> {
                        openAppInfo()
                        result.success(null)
                    }
                    "takePlays" -> result.success(MusicPlayLog.take(this))
                    else -> result.notImplemented()
                }
            }
    }

    // Has the person turned on notification access for this app?
    private fun accessGranted(): Boolean {
        val me = ComponentName(this, MediaListenerService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm != null) return nm.isNotificationListenerAccessGranted(me)
        }
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(":").any { ComponentName.unflattenFromString(it) == me }
    }

    // Straight to this app's switch where Android allows it, else the list.
    private fun openAccessSettings() {
        val me = ComponentName(this, MediaListenerService::class.java)
        val detail = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, me.flattenToString())
        } else {
            null
        }
        try {
            startActivity(detail ?: Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }

    /* Android 13+ greys out the notification-access switch ("Restricted
       setting") for apps installed from an APK file rather than an app
       store, until the person taps "Allow restricted settings" in the
       app's App info menu. Android doesn't say whether that has been done,
       so this only says it may apply: Android 13+ and not from Play. */
    private fun mayBeRestricted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val installer = try {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } catch (e: Exception) {
            null
        }
        return installer != "com.android.vending"
    }

    // This app's App info page: "Allow restricted settings" (in the ⋮
    // menu), and on many phones the battery / autostart switches.
    private fun openAppInfo() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private fun installed(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
