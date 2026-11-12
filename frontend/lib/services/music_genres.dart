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
  var title = rawTitle;
  // Video extras in brackets: (Official Video), [Lyrics], (feat. X), ...
  title = title.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
  title = title.replaceAll(
      RegExp(r'\b(official|music video|lyrics?|lyric video|audio|hd|4k|mv|visualizer)\b',
          caseSensitive: false),
      ' ');
  title = title.replaceAll(RegExp(r'\s(ft\.?|feat\.?)\s.*$', caseSensitive: false), ' ');
  var artist = rawArtist
      .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(official\)$', caseSensitive: false), '');
  // "Artist - Song" in the title wins over a channel name.
  final dash = RegExp(r'^(.+?)\s+[-–—|]\s+(.+)$').firstMatch(title.trim());
  if (dash != null) {
    artist = dash.group(1)!;
    title = dash.group(2)!;
  }
  String tidy(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return (artist: tidy(artist), title: tidy(title));
}

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

/// Results under this are not trusted as the played song.
const songMatchBar = 0.6;
