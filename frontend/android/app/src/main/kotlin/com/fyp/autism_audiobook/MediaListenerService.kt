package com.fyp.autism_audiobook

import android.content.ComponentName
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService

/* Runs while the person has given this app notification access (Android's
   "notification access" setting), which is what lets an app see other
   apps' media players. It watches only YouTube and YouTube Music: when one
   of them is playing, it notes the title and artist in MusicPlayLog. It
   reads no notifications' contents and nothing from any other app. */
class MediaListenerService : NotificationListenerService() {
    private val main = Handler(Looper.getMainLooper())
    private var sessions: MediaSessionManager? = null
    private val watched = mutableMapOf<MediaSession.Token, Pair<MediaController, MediaController.Callback>>()

    private val onSessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { list ->
        follow(list ?: emptyList())
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        val manager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
        sessions = manager
        val me = ComponentName(this, MediaListenerService::class.java)
        try {
            manager.addOnActiveSessionsChangedListener(onSessionsChanged, me, main)
            follow(manager.getActiveSessions(me))
        } catch (e: SecurityException) {
            // Access was just taken away; nothing to watch.
        }
    }

    override fun onListenerDisconnected() {
        sessions?.removeOnActiveSessionsChangedListener(onSessionsChanged)
        for ((controller, callback) in watched.values) controller.unregisterCallback(callback)
        watched.clear()
        super.onListenerDisconnected()
    }

    // Watch the YouTube players that are open now; stop watching closed ones.
    private fun follow(list: List<MediaController>) {
        val open = list.filter { it.packageName in MusicPlayLog.WATCHED }
        val tokens = open.map { it.sessionToken }.toSet()
        for (token in watched.keys.toList()) {
            if (token !in tokens) {
                val (controller, callback) = watched.remove(token)!!
                controller.unregisterCallback(callback)
            }
        }
        for (controller in open) {
            if (controller.sessionToken in watched) continue
            val callback = object : MediaController.Callback() {
                override fun onMetadataChanged(metadata: MediaMetadata?) = note(controller)
                override fun onPlaybackStateChanged(state: PlaybackState?) = note(controller)
            }
            controller.registerCallback(callback, main)
            watched[controller.sessionToken] = controller to callback
            note(controller)
        }
    }

    // Log what is playing, if anything is.
    private fun note(controller: MediaController) {
        if (controller.playbackState?.state != PlaybackState.STATE_PLAYING) return
        val meta = controller.metadata ?: return
        val title = meta.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            ?: return
        val artist = meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            ?: ""
        if (title.isBlank()) return
        MusicPlayLog.record(this, controller.packageName, title.trim(), artist.trim())
    }
}
