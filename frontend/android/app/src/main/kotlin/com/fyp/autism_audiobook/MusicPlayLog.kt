package com.fyp.autism_audiobook

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/* A small log, kept on this phone only, of the songs heard in YouTube and
   YouTube Music: which app, the title and artist, and when. The Flutter
   side takes the plays out, works out each one's genre, and keeps only the
   genre counts, so song names don't stay here. */
object MusicPlayLog {
    const val YOUTUBE = "com.google.android.youtube"
    const val YOUTUBE_MUSIC = "com.google.android.apps.youtube.music"
    val WATCHED = setOf(YOUTUBE, YOUTUBE_MUSIC)

    private const val PREFS = "music_taste_log"
    private const val KEY_PLAYS = "plays"
    private const val MAX_PLAYS = 500
    private const val KEEP_MS = 35L * 24 * 60 * 60 * 1000
    // The same song again within this time is the same listen (a pause, a seek).
    private const val SAME_LISTEN_MS = 10L * 60 * 1000
    // A video's title can change this soon after it starts (see record).
    private const val SETTLE_MS = 5_000L

    @Synchronized
    fun record(context: Context, app: String, title: String, artist: String) {
        val now = System.currentTimeMillis()
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val plays = read(context)
        // Players often send the title first and the artist a moment later,
        // so the same title soon after is the same listen: fill in the
        // artist if it was missing, but don't count it again.
        val last = (plays.length() - 1 downTo 0).map { plays.getJSONObject(it) }.firstOrNull {
            it.optString("title") == title
        }
        if (last != null && now - last.optLong("at") < SAME_LISTEN_MS) {
            if (last.optString("artist").isEmpty() && artist.isNotEmpty()) {
                last.put("artist", artist)
                prefs.edit().putString(KEY_PLAYS, plays.toString()).apply()
            }
            return
        }
        // YouTube also renames a video moments after it starts: first the
        // uploader's title ("ヨルシカ - 花に亡霊"), then the one translated for
        // this phone ("Yorushika - Hana ni Bourei"). A new title from the
        // same app within a few seconds is that same video, so it replaces
        // the entry instead of counting again. (Nobody listens to a song
        // for under 5 seconds anyway.)
        val newest = if (plays.length() > 0) plays.getJSONObject(plays.length() - 1) else null
        if (newest != null && newest.optString("app") == app && now - newest.optLong("at") < SETTLE_MS) {
            newest.put("title", title)
            if (artist.isNotEmpty()) newest.put("artist", artist)
            prefs.edit().putString(KEY_PLAYS, plays.toString()).apply()
            return
        }
        val kept = JSONArray()
        for (i in 0 until plays.length()) {
            val p = plays.getJSONObject(i)
            if (now - p.optLong("at") < KEEP_MS) kept.put(p)
        }
        kept.put(JSONObject().put("app", app).put("title", title).put("artist", artist).put("at", now))
        while (kept.length() > MAX_PLAYS) kept.remove(0)
        prefs.edit()
            .putString(KEY_PLAYS, kept.toString())
            .putLong("last_seen_$app", now)
            .apply()
    }

    // Hands over every logged play and empties the log.
    @Synchronized
    fun take(context: Context): List<Map<String, Any>> {
        val plays = read(context)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_PLAYS).apply()
        return (0 until plays.length()).map {
            val p = plays.getJSONObject(it)
            mapOf(
                "app" to p.optString("app"),
                "title" to p.optString("title"),
                "artist" to p.optString("artist"),
                "at" to p.optLong("at"),
            )
        }
    }

    // When a watched app last played something (0 = never seen).
    fun lastSeen(context: Context, app: String): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("last_seen_$app", 0L)

    private fun read(context: Context): JSONArray {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PLAYS, null)
        return try {
            if (raw == null) JSONArray() else JSONArray(raw)
        } catch (e: Exception) {
            JSONArray()
        }
    }
}
