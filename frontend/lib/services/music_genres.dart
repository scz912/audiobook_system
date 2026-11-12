/* What the person listens to on YouTube and YouTube Music, sorted into a
   small set of listening genres, and how each one relates to the genres
   of the app's background music. Plain functions, no app state, so the
   rules can be tested on their own. */

/// The listening genres shown under "Top Music Genre" (translation keys
/// are `music.genre.<key>`).
const listeningGenres = [
  'pop', 'kpop', 'rock', 'hiphop', 'rnb', 'electronic', 'dance', 'jazz',
  'classical', 'soundtrack', 'country', 'folk', 'world', 'latin', 'ambient',
  'children', 'religious',
];

/* Songs whose genre can't be worked out: not in Apple's catalogue, or
   filed under a genre we can't place (Enka, Vocal, Holiday...). Shown on
   the card, but it says nothing about taste, so recommendations ignore it.
   Not in [listeningGenres] (it has no affinities). */
const otherGenre = 'others';

/* Whether a play we couldn't place is still a song (so it counts as
   [otherGenre]) rather than any other video - a vlog or a cat video
   shouldn't count as music. Everything in YouTube Music is music; on
   YouTube, a song's video says so: "Official Music Video", "MV",
   "Lyrics", "cover", 歌ってみた, a "- Topic" or VEVO channel... */
bool looksLikeSong(String rawTitle, String channel, String app) {
  if (app == 'com.google.android.apps.youtube.music') return true;
  if (RegExp(r'(\s-\s*Topic|VEVO)$', caseSensitive: false).hasMatch(channel.trim())) return true;
  return RegExp(
    r'\b(official\s+(music\s+|lyric\s+)?(video|audio|mv)|music\s+video|lyrics?|lirik|m/?v|cover|'
    r'karaoke|acoustic|live\s+(performance|session)|ft\.|feat\.|ost|instrumental)\b|'
    r'歌ってみた|弾いてみた|歌詞|官方|動態歌詞|가사|뮤직비디오',
    caseSensitive: false,
  ).hasMatch(rawTitle);
}

/* A catalogue genre name (Apple's, e.g. "Hip-Hop/Rap", "K-Pop",
   "Singer/Songwriter") to a listening genre, or null when it isn't music
   we can place. Checked in order: the more specific words first. */
String? listeningGenreFor(String catalogueGenre) {
  final g = catalogueGenre.toLowerCase();
  bool has(List<String> words) => words.any(g.contains);
  if (has(['k-pop'])) return 'kpop';
  if (has(['children', 'kids'])) return 'children';
  if (has(['soundtrack', 'anime', 'video game', 'film', 'musical'])) return 'soundtrack';
  if (has(['hip-hop', 'hip hop', 'rap'])) return 'hiphop';
  if (has(['r&b', 'soul', 'funk'])) return 'rnb';
  if (has(['dance', 'disco'])) return 'dance';
  if (has(['electronic', 'house', 'techno', 'trance', 'dubstep', 'edm', 'electronica'])) return 'electronic';
  if (has(['jazz', 'blues', 'swing'])) return 'jazz';
  if (has(['classical', 'opera', 'orchestral'])) return 'classical';
  if (has(['country', 'bluegrass'])) return 'country';
  if (has(['folk', 'singer/songwriter'])) return 'folk';
  if (has(['latin', 'reggaeton', 'salsa', 'bossa'])) return 'latin';
  if (has(['christian', 'gospel', 'religious', 'inspirational', 'devotional', 'nasheed'])) return 'religious';
  if (has(['new age', 'ambient', 'easy listening', 'instrumental', 'meditation', 'relaxation'])) return 'ambient';
  if (has(['world', 'reggae', 'afro', 'bollywood', 'indian', 'arabic', 'malay', 'indonesian',
      'chinese', 'j-pop', 'mandopop', 'cantopop', 'thai'])) {
    // A country's pop scene ("Malay Pop", "Mandopop") counts as pop.
    return has(['pop']) ? 'pop' : 'world';
  }
  if (has(['pop'])) return 'pop';
  if (has(['rock', 'metal', 'alternative', 'punk', 'indie', 'grunge'])) return 'rock';
  return null;
}

/* How well each background-music genre suits someone who listens to a
   listening genre, 0 to 1. A listening genre with no close match in the
   library (rock, hip-hop) leans on the nearest ones. "Others" never
   matches: its genre is unknown. */
const genreAffinity = <String, Map<String, double>>{
  'pop': {'Pop': 1.0, 'Acoustic': 0.5, 'Electronic': 0.4},
  'kpop': {'Pop': 1.0, 'Electronic': 0.6},
  'rock': {'Pop': 0.6, 'Acoustic': 0.5, 'Electronic': 0.4},
  'hiphop': {'Electronic': 0.7, 'Pop': 0.6},
  'rnb': {'Pop': 0.8, 'Jazz': 0.6},
  'electronic': {'Electronic': 1.0, 'Ambient & Lullaby': 0.4, 'Pop': 0.4},
  'dance': {'Electronic': 1.0, 'Pop': 0.7},
  'jazz': {'Jazz': 1.0, 'Acoustic': 0.4, 'Classical & Cinematic': 0.3},
  'classical': {'Classical & Cinematic': 1.0, 'Ambient & Lullaby': 0.4},
  'soundtrack': {'Classical & Cinematic': 1.0, 'Ambient & Lullaby': 0.4, 'Electronic': 0.3},
  'country': {'Acoustic': 0.8, 'Folk & World': 0.7},
  'folk': {'Folk & World': 1.0, 'Acoustic': 0.8},
  'world': {'Folk & World': 1.0, 'Nature': 0.3},
  'latin': {'Folk & World': 0.7, 'Pop': 0.6},
  'ambient': {'Ambient & Lullaby': 1.0, 'Nature': 0.7, 'Classical & Cinematic': 0.3},
  'children': {'Pop': 0.6, 'Ambient & Lullaby': 0.6, 'Acoustic': 0.4},
  'religious': {'Classical & Cinematic': 0.5, 'Folk & World': 0.5, 'Ambient & Lullaby': 0.5},
};

/* A YouTube video's title and channel, tidied into the song and artist a
   music catalogue would know: "Artist - Song (Official Video)" on the
   channel "ArtistVEVO" -> ("Artist", "Song"). */
({String artist, String title}) songFromPlay(String rawTitle, String rawArtist) {
  String tidy(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  var title = rawTitle;
  // Chinese and Japanese videos put the song name in 【】《》「」『』 -
  // unless it's a tag like 【MV】 or 【歌ってみた】. Read these first: the
  // name can hold a " | " itself (『花に亡霊 | ヨルシカ』).
  String? named;
  for (final m in RegExp(r'[【《「『〔]([^】》」』〕]+)[】》」』〕]').allMatches(title)) {
    if (!_isTag(m[1]!)) {
      named = m[1]!;
      break;
    }
  }
  title = title.replaceAll(RegExp(r'[【《「『〔][^】》」』〕]*[】》」』〕]'), ' ');
  // After " | " come extras ("| Official Video", "| Beethoven, Mozart...").
  title = title.split(RegExp(r'\s\|\s')).first;
  // Korean "뚜두뚜두 (DDU-DU DDU-DU)": Apple lists K-pop under the Latin
  // name, so keep that one.
  title = title.replaceAllMapped(
    RegExp(r'(\p{Script=Hangul}[\p{Script=Hangul}\s]*)\s*\(([A-Za-z][^()]*)\)', unicode: true),
    (m) => _isTag(m[2]!) ? m[1]! : m[2]!,
  );
  // Video extras in brackets: (Official Video), [Lyrics], （feat. X）, ...
  title = title.replaceAll(RegExp(r'[\(\[（][^\)\]）]*[\)\]）]'), ' ');
  title = _dropTagWords(title);
  title = title.replaceAll(RegExp(r'\s(ft\.?|feat\.?)\s.*$', caseSensitive: false), ' ');
  var artist = rawArtist
      .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(official\)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '');
  title = tidy(title);

  if (named != null) {
    final parts = named.split(RegExp(r'\s+[|/\-–—]\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.length > 1) {
      // 『花に亡霊 | ヨルシカ』: song, then artist, inside the brackets.
      title = _dropTagWords(parts[0]);
      artist = parts[1];
    } else {
      // "周杰倫 Jay Chou【晴天】": what's left outside is the artist.
      if (title.isNotEmpty) artist = title;
      title = _dropTagWords(named);
    }
  } else if (_kana.hasMatch(title)) {
    // Japanese videos name the song first: "プロポーズ / 可不",
    // "プロポーズ - 内緒のピアス / 町田ちま (Cover)" (song - artist / cover
    // singer). The second part is the artist; the rest is dropped.
    final parts = title.split(RegExp(r'\s*/\s*|\s+[-–—_]\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.length > 1) {
      title = parts[0];
      artist = parts[1];
    }
  } else {
    // "Artist - Song" (also "Artist _ Song") wins over a channel name.
    final dash = RegExp(r'^(.+?)\s+[-–—_]\s+(.+)$').firstMatch(title);
    // K-pop writes "Artist 'Song'".
    final quoted = RegExp(r"""^(.*?)(?:^|\s)['‘"“]([^'’"”]+)['’"”](?=\s|$)""").firstMatch(title);
    // "Song / Artist", as Japanese uploads write it in romaji too.
    final slash = RegExp(r'^(.+?)(?:\s+/\s*|\s*/\s+)(.+)$').firstMatch(title);
    if (dash != null) {
      artist = dash.group(1)!;
      title = dash.group(2)!;
    } else if (quoted != null) {
      if (quoted.group(1)!.trim().isNotEmpty) artist = quoted.group(1)!;
      title = quoted.group(2)!;
    } else if (slash != null) {
      title = slash.group(1)!;
      artist = slash.group(2)!;
    }
  }
  // Quotes left around a song name ("BLACKPINK - '뚜두뚜두'").
  title = title.replaceAll(RegExp(r"""^\s*['‘"“]|['’"”]\s*$"""), '');
  // "晴天 Sunny Day", "周杰倫 Jay Chou": Chinese and Japanese stores list
  // the name in its own script, so keep only that part.
  title = _ownScript(tidy(title));
  artist = _ownScript(tidy(artist));
  return (artist: tidy(artist), title: tidy(title));
}

final _cjk = RegExp(r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]', unicode: true);
final _kana = RegExp(r'[\p{Script=Hiragana}\p{Script=Katakana}]', unicode: true);

// The Han / kana words of a mixed "晴天 Sunny Day"; anything else as it is.
String _ownScript(String s) {
  if (!_cjk.hasMatch(s) || !RegExp(r'[A-Za-z]').hasMatch(s)) return s;
  return s.split(' ').where(_cjk.hasMatch).join(' ');
}

final _tagWords = RegExp(
  r'\b(official|music video|lyrics?|lyric video|audio|hd|4k|m/?v|visualizer|performance|ver\.?\d*|'
  r'cover|karaoke|teaser)\b|歌ってみた|中字|動態歌詞|官方|完整版|高清|伴奏',
  caseSensitive: false,
);

String _dropTagWords(String s) => s.replaceAll(_tagWords, ' ');

// A bracket that is only a tag (【MV】, 【歌ってみた】, (Official)).
bool _isTag(String s) => !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(_dropTagWords(s));

// Lower-case words of 2+ letters (digits kept), for loose comparison.
Set<String> _words(String s) => RegExp(r'[\p{L}\p{N}]{2,}', unicode: true)
    .allMatches(s.toLowerCase())
    .map((m) => m.group(0)!)
    .toSet();

/* How sure we are that a catalogue result is the song that was played,
   0 to 1: the share of the played title's words found in the result's
   title, with a bonus when the artist matches too. A video that isn't a
   song ("cat compilation") finds no result above the bar. */
double songMatch(
  ({String artist, String title}) played,
  String resultArtist,
  String resultTitle,
) {
  final want = _words(played.title);
  if (want.isEmpty) return 0;
  final got = _words(resultTitle);
  final titleShare = want.where(got.contains).length / want.length;
  final artistWords = _words(played.artist);
  final artistHit = artistWords.isNotEmpty &&
      artistWords.where(_words(resultArtist).contains).length >= (artistWords.length / 2).ceil();
  return (titleShare * 0.7 + (artistHit ? 0.3 : 0)).clamp(0, 1).toDouble();
}

/* Which of Apple's country stores to search for a song (checked live,
   Nov 2026). Japanese and Chinese songs are listed in their own script
   only in their home stores (the US store says "propose" for
   "プロポーズ"). Everything else, Korean included, uses the Malaysian
   store: it has the international catalogue plus local Malay songs the
   US store lacks (Aina Abdul, Faizal Tahir's "Sampai Syurga"), and the
   Korean store has no music at all. */
String catalogueCountryFor(String text) {
  if (RegExp(r'[\p{Script=Hiragana}\p{Script=Katakana}]', unicode: true).hasMatch(text)) return 'JP';
  if (RegExp(r'\p{Script=Han}', unicode: true).hasMatch(text)) return 'TW'; // Chinese, no kana
  if (RegExp(r'\p{Script=Thai}', unicode: true).hasMatch(text)) return 'TH';
  return 'MY';
}

/// Results under this are not trusted as the played song.
const songMatchBar = 0.6;

/* The listening genre of the played song among a catalogue search's
   results (Apple's JSON, best first), or null when none is it.

   Normally a result must share the played title's words. But Apple also
   matches a song across scripts - "IU 밤편지" finds IU's "Through the
   Night", "后来" (simplified) finds "後來" (traditional) - where no words
   are shared. So for a title in Chinese, Japanese or Korean script, the
   top result is trusted too when its artist matches, or when its title
   is Chinese of the same length (the other way of writing it).

   A result is also the song when both its title and its artist appear
   anywhere in what was played ([played]: the raw video title and
   channel), whatever the order: "Yorushika - Hana ni Bourei (Ghost In A
   Flower)" is Yorushika's "Ghost In A Flower".

   Results with no genre we can place (Karaoke, Comedy...) are covers or
   not music, so they never count: Apple lists karaoke versions of
   "Hana ni Bourei" above the song itself. */
String? catalogueGenre(({String artist, String title}) song, List<Map> results, {String played = ''}) {
  final all = results;
  results = results.where((r) => listeningGenreFor('${r['primaryGenreName'] ?? ''}') != null).toList();
  final found = _placeableGenre(song, results, played);
  if (found != null) return found;
  // The song itself (title and artist both match) under a genre we can't
  // place - Enka, Vocal, Holiday: still a song, of another genre.
  final playedWords = _words(played);
  for (final r in all) {
    if (songMatch(song, '${r['artistName'] ?? ''}', '${r['trackName'] ?? ''}') >= 0.9 || _inPlayed(r, playedWords)) {
      return otherGenre;
    }
  }
  return null;
}

// Both the result's title and its artist appear in what was played.
bool _inPlayed(Map r, Set<String> playedWords) {
  final t = _words(_bareTitle('${r['trackName'] ?? ''}'));
  final a = _words('${r['artistName'] ?? ''}');
  return t.isNotEmpty && a.isNotEmpty && t.every(playedWords.contains) && a.any(playedWords.contains);
}

String? _placeableGenre(({String artist, String title}) song, List<Map> results, String played) {
  String genreOf(Map r) => listeningGenreFor('${r['primaryGenreName'] ?? ''}')!;
  var best = 0.0;
  String? genre;
  for (final r in results) {
    final m = songMatch(song, '${r['artistName'] ?? ''}', '${r['trackName'] ?? ''}');
    if (m > best) {
      best = m;
      genre = genreOf(r);
    }
  }
  if (best >= songMatchBar) return genre;

  final playedWords = _words(played);
  for (final r in results) {
    if (_inPlayed(r, playedWords)) return genreOf(r);
  }

  final asian = RegExp(r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]', unicode: true);
  if (results.isEmpty || !asian.hasMatch(song.title)) return null;
  final top = results.first;
  final topTitle = _bareTitle('${top['trackName'] ?? ''}');
  final artistWords = _words(song.artist);
  final artistHit = artistWords.isNotEmpty &&
      artistWords.where(_words('${top['artistName'] ?? ''}').contains).length >= (artistWords.length / 2).ceil();
  final hanOnly = RegExp(r'^\p{Script=Han}+$', unicode: true);
  final sameChinese = hanOnly.hasMatch(song.title) && hanOnly.hasMatch(topTitle) &&
      song.title.runes.length == topTitle.runes.length;
  return artistHit || sameChinese ? genreOf(top) : null;
}

// A catalogue title without its "(Live)", "(feat. X)", "(Piano Ver.)".
String _bareTitle(String t) => t.replaceAll(RegExp(r'\s*[\(\[（].*$'), '').trim();

/* The genre from a search by the song title alone, used when searching
   artist and title together found nothing (a cover singer's name, as in
   "プロポーズ Cover / Gero", makes Apple return no results). Only results
   titled exactly like the played song count, and only if they all agree
   on the genre: a vague title like "Love" matches songs of every genre. */
String? titleOnlyGenre(({String artist, String title}) song, List<Map> results) {
  final want = _words(song.title);
  if (want.isEmpty) return null;
  final genres = <String>{};
  for (final r in results) {
    final g = listeningGenreFor('${r['primaryGenreName'] ?? ''}');
    final t = _words(_bareTitle('${r['trackName'] ?? ''}'));
    if (g != null && t.length == want.length && t.every(want.contains)) genres.add(g);
  }
  return genres.length == 1 ? genres.first : null;
}

/* The genre a video names outright, for videos that aren't one song
   ("50 Classical Music Masterpieces | Beethoven, Mozart...", "lofi beats
   to study to"), which the catalogue can't match. Only clear words count:
   "rock" or "rap" alone could be anything ("rock climbing"). Checked in
   order. Null when the words name no genre. */
const _genreWords = <String, List<String>>{
  'children': ['nursery rhymes', 'nursery rhyme', 'kids songs', 'children songs', "children's songs",
      'lagu kanak', 'lullaby', 'lullabies'],
  'religious': ['nasheed', 'nasyid', 'selawat', 'sholawat', 'zikir', 'qasidah', 'worship songs', 'gospel', 'hymns'],
  'kpop': ['kpop', 'k-pop'],
  'soundtrack': ['soundtrack', 'ost', 'film score', 'anime songs', 'anime openings'],
  'classical': ['classical', 'symphony', 'sonata', 'concerto', 'orchestra', 'beethoven', 'mozart', 'chopin',
      'bach', 'vivaldi', 'tchaikovsky', 'debussy', 'schubert', 'brahms', 'handel', 'haydn'],
  'jazz': ['jazz', 'blues', 'bossa nova', 'swing music'],
  'ambient': ['lofi', 'lo-fi', 'lo fi', 'ambient', 'meditation music', 'sleep music', 'relaxing music',
      'study music', 'spa music', 'white noise', 'rain sounds'],
  'electronic': ['edm', 'techno', 'trance music', 'house music', 'dubstep'],
  'dance': ['dance music', 'disco'],
};

String? genreFromWords(String text) {
  final t = ' ${text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\-\x27]+', unicode: true), ' ')} ';
  for (final e in _genreWords.entries) {
    if (e.value.any((w) => t.contains(' $w '))) return e.key;
  }
  return null;
}
