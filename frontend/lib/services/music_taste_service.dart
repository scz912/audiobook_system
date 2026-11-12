import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'music_genres.dart';

/// Whether the person has let the app see YouTube / YouTube Music.
class MusicTasteStatus {
  // False on phones where it can't work (iPhone: no app may see others).
  final bool supported;
  final bool granted;
  /* Android is running the listener. False with [granted] true means the
     phone stopped it (battery savers): nothing is seen until it's back. */
  final bool listening;
  /* Android 13+ app installed from an APK file: the access switch may be
     greyed out ("Restricted setting") until "Allow restricted settings"
     is tapped in App info. */
  final bool mayBeRestricted;
  final bool youtubeInstalled;
  final bool youtubeMusicInstalled;
  const MusicTasteStatus({
    required this.supported,
    required this.granted,
    this.listening = false,
    this.mayBeRestricted = false,
    this.youtubeInstalled = false,
    this.youtubeMusicInstalled = false,
  });
}

/* The personal account's music taste: the genres of what the person plays
   in YouTube and YouTube Music.

   With the person's notification access (Android), the phone logs each
   song's title and artist as it plays (MediaListenerService). Here those
   plays are collected, each song is looked up in Apple's public iTunes
   catalogue to find its genre (only the song and artist words are sent,
   nothing about the person), and only "genre + date" is kept, on this
   phone. Song names are dropped once looked up. */
class MusicTasteService {
  MusicTasteService._();

  static const _channel = MethodChannel('autism_audiobook/music_taste');
  static const _genresKey = 'music_taste_genres';
  static const _pendingKey = 'music_taste_pending';
  // Versioned: when title reading improves, songs not found before get another look.
  static const _cacheKey = 'music_taste_cache_v4';
  static const _keepDays = 35;
  static const _retryMissDays = 3;
  // Apple asks for about 20 searches a minute at most, and a song can take
  // two; the rest wait for the next visit.
  static const _lookupsPerSync = 10;

  static int _today() => DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<MusicTasteStatus> status() async {
    if (!supported) return const MusicTasteStatus(supported: false, granted: false);
    try {
      var s = await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
      if (s['granted'] == true && s['listening'] != true) {
        // Just after the app starts, Android may still be starting the
        // listener (the status call also asked it to): look once more.
        await Future.delayed(const Duration(seconds: 2));
        s = await _channel.invokeMapMethod<String, dynamic>('status') ?? s;
      }
      return MusicTasteStatus(
        supported: true,
        granted: s['granted'] == true,
        listening: s['listening'] == true,
        mayBeRestricted: s['mayBeRestricted'] == true,
        youtubeInstalled: s['youtubeInstalled'] == true,
        youtubeMusicInstalled: s['youtubeMusicInstalled'] == true,
      );
    } on MissingPluginException {
      return const MusicTasteStatus(supported: false, granted: false);
    }
  }

  // Android's notification-access page, at this app's switch.
  static Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod('openSettings');
  }

  // This app's App info page (restricted settings, battery, autostart).
  static Future<void> openAppInfo() async {
    if (supported) await _channel.invokeMethod('openAppInfo');
  }

  static Future<void>? _syncing;

  /// Collect new plays and work out their genres. Safe to call often.
  static Future<void> sync({http.Client? client}) =>
      _syncing ??= _sync(client).whenComplete(() => _syncing = null);

  static Future<void> _sync(http.Client? client) async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = _readList(prefs, _pendingKey);
    try {
      final plays = await _channel.invokeListMethod<Map>('takePlays') ?? [];
      for (final p in plays) {
        pending.add({'title': '${p['title']}', 'artist': '${p['artist']}', 'app': '${p['app']}', 'at': p['at']});
      }
    } on MissingPluginException {
      return;
    }

    final cache = _readMap(prefs, _cacheKey);
    final genres = _readList(prefs, _genresKey);
    final http.Client web = client ?? http.Client();
    var lookups = 0;
    final waiting = <Map<String, dynamic>>[];
    try {
      for (final p in pending) {
        final song = songFromPlay('${p['title']}', '${p['artist']}');
        final key = '${song.artist}|${song.title}'.toLowerCase();
        String? genre = cache[key];
        // A song not found is looked for again after a few days (Apple
        // may have been briefly unhelpful, or the app reads titles better).
        if (genre != null && genre.startsWith('~')) {
          final day = int.tryParse(genre.substring(1)) ?? 0;
          genre = _today() - day < _retryMissDays ? '' : null;
        }
        if (genre == null) {
          if (lookups >= _lookupsPerSync) {
            waiting.add(p);
            continue;
          }
          lookups++;
          final found = await _lookUp(web, song, '${p['title']} ${p['artist']}');
          if (found == null) {
            // The catalogue couldn't be reached: try again next time.
            waiting.add(p);
            continue;
          }
          genre = found;
          cache[key] = genre.isEmpty ? '~${_today()}' : genre;
        }
        // Not found: a song still counts, under Others; other videos don't.
        if (genre.isEmpty && looksLikeSong('${p['title']}', '${p['artist']}', '${p['app'] ?? ''}')) {
          genre = otherGenre;
        }
        if (genre.isNotEmpty) genres.add({'genre': genre, 'at': p['at']});
      }
    } finally {
      if (client == null) web.close();
    }

    final cutoff = DateTime.now().subtract(const Duration(days: _keepDays)).millisecondsSinceEpoch;
    genres.removeWhere((g) => (g['at'] as num? ?? 0) < cutoff);
    await prefs.setString(_genresKey, jsonEncode(genres));
    await prefs.setString(_pendingKey, jsonEncode(waiting.take(300).toList()));
    await prefs.setString(_cacheKey, jsonEncode(cache));
  }

  /* The listening genre of a song: '' when it isn't a song the catalogue
     knows (or not music at all), null when the catalogue can't be reached.
     A video that isn't one song (a compilation) gets the genre its own
     words name, if any ([played] is its raw title and channel). */
  static Future<String?> _lookUp(http.Client web, ({String artist, String title}) song, String played) async {
    final named = genreFromWords(played) ?? '';
    if (song.title.isEmpty) return named;
    final country = catalogueCountryFor('${song.artist} ${song.title}');
    // Artist and title together first; if that finds nothing, the title
    // alone (extra names such as a cover singer make Apple return nothing).
    final both = await _search(web, '${song.artist} ${song.title}', country);
    if (both == null) return null;
    final found = catalogueGenre(song, both, played: played);
    if (found != null) return found;
    if (song.artist.isEmpty) return named;
    final alone = await _search(web, song.title, country);
    if (alone == null) return null;
    return titleOnlyGenre(song, alone) ?? named;
  }

  // One catalogue search: its results, or null when it can't be reached.
  static Future<List<Map>?> _search(http.Client web, String term, String country) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term.replaceAll('/', ' ').trim(),
      'media': 'music',
      'entity': 'song',
      'limit': '8',
      'country': country,
      // Genre names in English everywhere ("Mandopop", not "華語流行樂").
      'lang': 'en_us',
    });
    try {
      final res = await web.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return ((jsonDecode(res.body)['results'] as List?) ?? const []).whereType<Map>().toList();
    } catch (_) {
      return null;
    }
  }

  /// Plays per listening genre over the last [days] days.
  static Future<Map<String, int>> genreCounts({int days = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final from = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final counts = <String, int>{};
    for (final g in _readList(prefs, _genresKey)) {
      if ((g['at'] as num? ?? 0) < from) continue;
      final genre = '${g['genre']}';
      counts[genre] = (counts[genre] ?? 0) + 1;
    }
    return counts;
  }

  static List<Map<String, dynamic>> _readList(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> _readMap(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }
}
