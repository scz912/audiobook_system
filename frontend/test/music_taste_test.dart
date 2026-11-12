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
    test('lyrics and featuring are dropped', () {
      final s = songFromPlay('Ed Sheeran - Perfect [Lyrics] ft. Beyonce', '');
      expect(s.title, 'Perfect');
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
