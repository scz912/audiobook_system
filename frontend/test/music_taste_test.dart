import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:autism_audiobook/models/content_item.dart';
import 'package:autism_audiobook/models/music_track.dart';
import 'package:autism_audiobook/services/audiobook_recommender.dart';
import 'package:autism_audiobook/services/music_genres.dart';
import 'package:autism_audiobook/state/language_state.dart';
import 'package:autism_audiobook/widgets/difficulty_badge.dart';

ContentItem _book(String title, {String? genre, List<String> tags = const [], String? status, bool music = true}) =>
    ContentItem(
      audiobookId: title,
      title: title,
      status: status,
      musicTrack: music
          ? MusicTrack(trackId: 't-$title', title: 'bgm', fileUrl: '', genre: genre, tags: tags)
          : null,
    );

void main() {
  group('catalogue genre -> listening genre', () {
    final cases = {
      'Hip-Hop/Rap': 'hiphop',
      'K-Pop': 'kpop',
      'Pop': 'pop',
      'Malaysian Pop': 'pop',
      'Mandopop': 'pop',
      'Alternative': 'rock',
      'Soundtrack': 'soundtrack',
      'Singer/Songwriter': 'folk',
      'New Age': 'ambient',
      "Children's Music": 'children',
      'R&B/Soul': 'rnb',
      'Dance': 'dance',
      'Electronic': 'electronic',
      'Worldwide': 'world',
      'Christian & Gospel': 'religious',
    };
    for (final c in cases.entries) {
      test('${c.key} -> ${c.value}', () => expect(listeningGenreFor(c.key), c.value));
    }
    test('not music -> nothing', () => expect(listeningGenreFor('Comedy'), isNull));
    test('every listening genre has an affinity row', () {
      for (final g in listeningGenres) {
        expect(genreAffinity.containsKey(g), isTrue, reason: g);
      }
    });
  });

  group('YouTube titles -> song and artist', () {
    test('artist - song (official video), VEVO channel', () {
      final s = songFromPlay('Taylor Swift - Shake It Off (Official Video)', 'TaylorSwiftVEVO');
      expect(s.artist, 'Taylor Swift');
      expect(s.title, 'Shake It Off');
    });
    test('YouTube Music: title and "- Topic" channel', () {
      final s = songFromPlay('Blinding Lights', 'The Weeknd - Topic');
      expect(s.artist, 'The Weeknd');
      expect(s.title, 'Blinding Lights');
    });
    test('Japanese "Song / Artist" with an 【MV】 tag', () {
      final s = songFromPlay('【MV】プロポーズ/ 9Lana cover', '内緒のピアス');
      expect(s.title, 'プロポーズ');
      expect(s.artist, '9Lana');
    });
    test('Chinese song name in 【】, bilingual artist and title', () {
      final s = songFromPlay('周杰倫 Jay Chou【晴天 Sunny Day】Official MV', '周杰倫 Jay Chou');
      expect(s.artist, '周杰倫');
      expect(s.title, '晴天');
    });
    test('Japanese song name in 「」', () {
      final s = songFromPlay('YOASOBI「アイドル」Official Music Video', 'Ayase / YOASOBI');
      expect(s.artist, 'YOASOBI');
      expect(s.title, 'アイドル');
    });
    test("K-pop: Artist 'Song' on a label channel", () {
      final s = songFromPlay("BTS (방탄소년단) 'Dynamite' Official MV", 'HYBE LABELS');
      expect(s.artist, 'BTS');
      expect(s.title, 'Dynamite');
    });
    test('K-pop: Latin name kept from "한글 (Latin)", M/V dropped', () {
      final s = songFromPlay("BLACKPINK - '뚜두뚜두 (DDU-DU DDU-DU)' M/V", 'BLACKPINK');
      expect(s.artist, 'BLACKPINK');
      expect(s.title, 'DDU-DU DDU-DU');
    });
    test('K-pop: " _ " separator, channel in brackets', () {
      final s = songFromPlay('IU(아이유) _ Palette(팔레트) (Feat. G-DRAGON) MV', '1theK (원더케이)');
      expect(s.artist, 'IU');
      expect(s.title, 'Palette');
    });
    test('apostrophes in English names are not quotes', () {
      final s = songFromPlay("Guns N' Roses - Sweet Child O' Mine (Official Music Video)", 'GunsNRosesVEVO');
      expect(s.artist, "Guns N' Roses");
      expect(s.title, "Sweet Child O' Mine");
    });
    test('the catalogue store follows the title script', () {
      expect(catalogueCountryFor('9Lana プロポーズ'), 'JP');
      expect(catalogueCountryFor('周杰倫 晴天'), 'TW');
      expect(catalogueCountryFor('IU 밤편지'), 'MY'); // Apple's Korean store has no music
      expect(catalogueCountryFor('Siti Nurhaliza Cindai'), 'MY');
    });
    test('extras after " | " are dropped', () {
      final s = songFromPlay('Siti Nurhaliza - Cindai | Official Music Video', '');
      expect(s.artist, 'Siti Nurhaliza');
      expect(s.title, 'Cindai');
    });
    test('a compilation names its genre in words', () {
      expect(
        genreFromWords('50 Classical Music Masterpieces for Relaxation & the Soul | Beethoven, Mozart, Chopin, '
            'Bach, Vivaldi Classical Stars'),
        'classical',
      );
      expect(genreFromWords('lofi hip hop radio - beats to relax/study to Lofi Girl'), 'ambient');
      expect(genreFromWords('Funny cats compilation 2024 Cat Channel'), isNull);
      expect(genreFromWords('Rock climbing vlog'), isNull);
    });
    test('lyrics and featuring are dropped', () {
      final s = songFromPlay('Ed Sheeran - Perfect [Lyrics] ft. Beyonce', '');
      expect(s.title, 'Perfect');
    });
  });

  group('songs of unknown genre (Others)', () {
    const yt = 'com.google.android.youtube';
    const ytMusic = 'com.google.android.apps.youtube.music';
    test('anything in YouTube Music is a song', () {
      expect(looksLikeSong('Hati Kering', 'Hael Husaini', ytMusic), isTrue);
    });
    test('a YouTube video that says it is a song', () {
      expect(looksLikeSong('Hael Husaini - Hati Kering (Official Music Video)', 'Hael Husaini', yt), isTrue);
      expect(looksLikeSong('Hati Kering', 'Hael Husaini - Topic', yt), isTrue);
      expect(looksLikeSong('【歌ってみた】プロポーズ', 'Someone', yt), isTrue);
      expect(looksLikeSong('Lagu Raya 2026 (Lirik)', 'Someone', yt), isTrue);
    });
    test('other YouTube videos are not', () {
      expect(looksLikeSong('My morning routine vlog', 'Daily Life', yt), isFalse);
      expect(looksLikeSong('Funny cats compilation 2024', 'Cat Channel', yt), isFalse);
      expect(looksLikeSong('How to cover a sofa', 'DIY Home', yt), isTrue); // "cover": a known false positive
    });
    test('Others is shown on the card but never takes a top place', () {
      final counts = {otherGenre: 9, 'pop': 3, 'rock': 2, 'jazz': 1, 'kpop': 1};
      expect(AudiobookRecommender.topGenres(counts).map((g) => g.genre), ['pop', 'rock', 'jazz']);
      final card = AudiobookRecommender.topGenres(counts, withOthers: true);
      expect(card.map((g) => g.genre), ['pop', 'rock', 'jazz', otherGenre]);
      expect(card.last.share, closeTo(9 / 15, 1e-9));
    });
  });

  group('catalogue results across scripts', () {
    Map r(String artist, String title, String genre) =>
        {'artistName': artist, 'trackName': title, 'primaryGenreName': genre};
    test('Korean title, English catalogue name, same artist', () {
      final s = songFromPlay('밤편지', 'IU - Topic');
      expect(catalogueGenre(s, [r('IU', 'Through the Night', 'K-Pop')]), 'kpop');
    });
    test('simplified title, traditional catalogue name', () {
      final s = songFromPlay('后来', 'Rene Liu - Topic');
      expect(catalogueGenre(s, [r('劉若英', '後來', 'Mandopop')]), 'pop');
    });
    test('a Korean title with an unrelated top result is not trusted', () {
      final s = songFromPlay('밤편지', 'Some Channel');
      expect(catalogueGenre(s, [r('Other Artist', 'Night', 'Rock')]), isNull);
    });
    test('karaoke versions never win; the English name in brackets matches', () {
      const raw = 'Yorushika - Hana ni Bourei (Ghost In A Flower)  [OFFICIAL VIDEO]';
      const channel = 'ヨルシカ / n-buna Official';
      final s = songFromPlay(raw, channel);
      final results = [
        r('Uta-Cha-Oh', 'HANA NI BOUREI KARAOKE Original by yorushika', 'Karaoke'),
        r('Yorushika', 'Ghost In A Flower', 'Rock'),
      ];
      expect(catalogueGenre(s, results, played: '$raw $channel'), 'rock');
    });
    test('『song | artist』 cover, with a " | " inside the brackets', () {
      final s = songFromPlay('『花に亡霊 | ヨルシカ』acoustic cover. 優里 × May J. × 川崎鷹也', '優里ちゃんねる【公式】');
      expect(s.title, '花に亡霊');
      expect(s.artist, 'ヨルシカ');
    });
    test('Japanese "song - artist / cover singer"', () {
      final s = songFromPlay('プロポーズ - 内緒のピアス / 町田ちま (Cover)', '町田ちま【にじさんじ】');
      expect(s.title, 'プロポーズ');
      expect(s.artist, '内緒のピアス');
    });
    test('title-only search: same title, one genre', () {
      final s = songFromPlay('プロポーズ Cover / Gero', 'Gero Channel');
      expect(titleOnlyGenre(s, [r('なとり', 'プロポーズ', 'J-Pop'), r('9Lana', 'プロポーズ', 'J-Pop')]), 'pop');
    });
    test('title-only search: a vague title across genres is not trusted', () {
      final s = songFromPlay('Love', 'Random Uploads');
      expect(titleOnlyGenre(s, [r('A', 'Love', 'Pop'), r('B', 'Love', 'Rock')]), isNull);
    });
    test('the song found under a genre we cannot place is Others', () {
      final s = songFromPlay('石川さゆり - 天城越え', '');
      expect(catalogueGenre(s, [r('石川さゆり', '天城越え', 'Enka')], played: '石川さゆり - 天城越え'), otherGenre);
    });
    test('a karaoke version of the song is not the song, so not Others', () {
      final s = songFromPlay('Hana ni Bourei', 'Yorushika - Topic');
      expect(catalogueGenre(s, [r('Uta-Cha-Oh', 'Hana ni Bourei Karaoke', 'Karaoke')]), isNull);
    });
    test('English titles still need shared words', () {
      final s = songFromPlay('Funny cats compilation 2024', 'Cat Channel');
      expect(catalogueGenre(s, [r('The Police', 'Every Breath You Take', 'Rock')]), isNull);
    });
  });

  group('trusting a catalogue result', () {
    final played = songFromPlay('Shake It Off', 'Taylor Swift');
    test('the same song passes', () {
      expect(songMatch(played, 'Taylor Swift', 'Shake It Off'), greaterThanOrEqualTo(songMatchBar));
    });
    test('a cat video does not match a random song', () {
      final cats = songFromPlay('Funny cats compilation 2024', 'Cat Channel');
      expect(songMatch(cats, 'Some Band', 'Cats in the Cradle'), lessThan(songMatchBar));
    });
  });

  group('recommender (no AI)', () {
    test('top genres: three most played, as shares', () {
      final top = AudiobookRecommender.topGenres({'pop': 6, 'rock': 3, 'jazz': 1, 'dance': 1});
      expect(top.map((g) => g.genre), ['pop', 'rock', 'dance']);
      expect(top.first.share, closeTo(0.6, 1e-9));
    });

    final books = [
      _book('A', genre: 'Pop', tags: ['Happy', 'Playful', 'Upbeat']),
      _book('B', genre: 'Classical & Cinematic', tags: ['Calm', 'Peaceful', 'Gentle']),
      _book('C', genre: 'Electronic', tags: ['Energetic', 'Upbeat']),
      _book('D', genre: 'Others', tags: ['Calm']),
      _book('E', music: false),
      _book('F', genre: 'Pop', tags: ['Calm'], status: 'processing'),
      _book('G', genre: 'Acoustic', tags: ['Calm', 'Gentle']),
    ];
    const top = [(genre: 'pop', share: 0.7), (genre: 'dance', share: 0.3)];

    test('taste and a calm mood together', () {
      final recs = AudiobookRecommender.recommend(books, top, 'calm');
      // A: 0.6 x 0.91 = 0.546 · G: 0.6 x 0.35 + 0.4 x 2/3 = 0.477 · B: 0.4 x 1 = 0.4
      expect(recs.map((r) => r.book.title), ['A', 'G', 'B']);
      expect(recs.first.becauseGenre, 'pop');
      expect(recs[1].moodTags, ['Calm', 'Gentle']);
    });

    test('no mood today: taste alone', () {
      final recs = AudiobookRecommender.recommend(books, top, null);
      expect(recs.map((r) => r.book.title), ['A', 'C', 'G']);
    });

    test('no music, still being made, or Others never win on taste', () {
      final recs = AudiobookRecommender.recommend(books, top, null, limit: 10);
      expect(recs.map((r) => r.book.title), isNot(contains('E')));
      expect(recs.map((r) => r.book.title), isNot(contains('F')));
      expect(recs.map((r) => r.book.title), isNot(contains('D')));
    });

    test('a clashing emotion lowers the mood fit', () {
      expect(AudiobookRecommender.moodFit(['Calm', 'Energetic'], 'sleepy').score, lessThan(
          AudiobookRecommender.moodFit(['Calm'], 'sleepy').score));
    });
  });

  group('difficulty badge', () {
    Widget host(String? d) => ChangeNotifierProvider(
          create: (_) => LanguageState(),
          child: MaterialApp(home: Scaffold(body: Center(child: DifficultyBadge(difficulty: d)))),
        );

    testWidgets('easy, medium and hard are green, yellow and orange', (tester) async {
      final fills = <Color>[];
      for (final d in ['easy', 'Medium', 'HARD']) {
        await tester.pumpWidget(host(d));
        final box = tester.widget<Container>(find.descendant(of: find.byType(DifficultyBadge), matching: find.byType(Container)));
        fills.add((box.decoration as BoxDecoration).color!);
      }
      expect(find.text('Hard'), findsOneWidget);
      expect(fills, [const Color(0xFF7BCB72), const Color(0xFFFFD43B), const Color(0xFFFF9F45)]);
    });

    testWidgets('no difficulty: nothing shown', (tester) async {
      await tester.pumpWidget(host(null));
      expect(find.byType(Container), findsNothing);
    });
  });
}
