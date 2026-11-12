package com.fyp.autism_audiobook

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The personal account's "Top Music Genre" (see MediaListenerService).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "autism_audiobook/music_taste")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "granted" to accessGranted(),
                            "youtubeInstalled" to installed(MusicPlayLog.YOUTUBE),
                            "youtubeMusicInstalled" to installed(MusicPlayLog.YOUTUBE_MUSIC),
                            "youtubeLastSeen" to MusicPlayLog.lastSeen(this, MusicPlayLog.YOUTUBE),
                            "youtubeMusicLastSeen" to MusicPlayLog.lastSeen(this, MusicPlayLog.YOUTUBE_MUSIC),
                        ),
                    )
                    "openSettings" -> {
                        openAccessSettings()
                        result.success(null)
                    }
                    "takePlays" -> result.success(MusicPlayLog.take(this))
                    else -> result.notImplemented()
                }
            }
    }

    // Has the person turned on notification access for this app?
    private fun accessGranted(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, MediaListenerService::class.java)
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

    private fun installed(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
