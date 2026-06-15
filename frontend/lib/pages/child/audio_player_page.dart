import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../audio/audio_engine.dart';
import '../../i18n/i18n.dart';
import '../../models/audiobook.dart';
import '../../models/user_settings.dart';
import '../../services/database_service.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/soft_card.dart';

class AudioPlayerPage extends StatefulWidget {
  final String title;
  final String? audiobookId;

  /* Caregiver preview: play the book to check it, with no settings panel
     and no listening session saved. */
  final bool previewMode;

  const AudioPlayerPage({
    super.key,
    required this.title,
    this.audiobookId,
    this.previewMode = false,
  });

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  final AudioEngine _engine = AudioEngine.instance;
  final PageController _pageController = PageController();

  Audiobook? _audiobook;
  List<_PlayerPage> _pages = [];
  bool _loading = true;
  bool _audioReady = false;
  bool _playingAudio = false;
  bool _useTts = true; // Gemini voice mode vs. uploaded audio mode
  int _page = 0;

  int _highlightStart = 0;
  int _highlightEnd = 0;

  // Tracks this listening session, saved to listening_history when it ends.
  final Stopwatch _listenWatch = Stopwatch();
  String? _activeChildId;
  String? _sessionMood;
  bool _reachedEnd = false;
  bool _sessionRecorded = false;
  // How many times the child paused or skipped forward this session.
  int _pauseCount = 0;
  int _skipCount = 0;
  bool _finishShowing = false;
  bool _naturalLoading = false;
  bool _naturalPlaying = false; // Gemini voice is playing
  // Bumped each time narration starts or stops. An in-flight load checks
  // this to see if a newer page has taken over, so the voice and read-along
  // don't drift apart when tapping Back/Next quickly.
  int _narrationSeq = 0;
  StreamSubscription<void>? _audioCompleteSub;
  StreamSubscription<Duration>? _naturalPosSub;
  // In uploaded-audio mode, follows playback to flip pages as the recording
  // plays. Subscribed as soon as the audio loads so we don't miss the
  // first ticks.
  StreamSubscription<Duration>? _audioPosSub;
  // Tracks the clip's total length as soon as just_audio knows it, used to
  // build _pageEndTimes.
  StreamSubscription<Duration?>? _audioDurSub;
  Duration? _knownAudioDuration;
  // When each page should end, split by each page's share of the words.
  // _pageEndTimes[i] is when page i hands off to i+1.
  List<Duration> _pageEndTimes = const [];
  // For uploaded audio: each page's words placed on the clip timeline, so
  // read-along still highlights the current word.
  List<List<_WordSpan>> _audioFilePageSpans = const [];
  // Set just before an auto page-flip so _onPageChanged knows not to seek
  // (we're already at the right spot).
  bool _suppressAudioPageSeek = false;
  // True while an auto page-flip is animating, so we don't start a second
  // one on every position tick during the 480 ms animation.
  bool _autoAdvanceInFlight = false;
  List<_WordSpan> _wordSpans = const [];
  String _narrationText = ''; // text of the page being read now

  // Background music — its own player so it doesn't clash with the voice.
  final AudioPlayer _bgmPlayer = AudioPlayer();
  int _bgmVolume = 30;    // 0-100, from Audiobook.bgmVolume
  bool _bgmStarted = false; // true once it has started playing

  // Settings just for this player session — changes here don't save back to
  // the child's stored settings (the caregiver owns those). Preview starts
  // at defaults; child mode starts from the caregiver's saved values.
  UserSettings? _localSettings;

  static const _defaultStoryText =
      'A gentle dragon lives in a quiet meadow where every day feels warm and safe. '
      'The dragon waves to friends with soft, slow wings. '
      'Birds sing kind little songs in the tall green trees. '
      'A small rabbit hops over to say a friendly hello. '
      'The sun glows gently across the bright blue sky. '
      'Together they share a picnic of sweet berries and warm tea. '
      'Everyone is calm. Everyone is safe. Everyone is happy.';

  @override
  void initState() {
    super.initState();
    // Preview starts fresh; child mode starts from the caregiver's settings.
    // Read once (don't watch) so in-player changes don't leak back out.
    _localSettings = widget.previewMode
        ? const UserSettings()
        : context.read<SettingsState>().settings;
    _loadAudiobook();
    // One listener for when playback finishes (voice or audio file).
    _audioCompleteSub = _engine.onComplete.listen((_) {
      if (!mounted) return;
      if (_naturalPlaying) {
        _onNaturalVoiceComplete();
        return;
      }
      // A real audio file finished -> celebrate.
      _listenWatch.stop();
      _reachedEnd = true;
      setState(() => _playingAudio = false);
      _recordSessionIfNeeded();
      _showFinishDialog();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Grab the active child and mood now, while we have a context, so we
    // can still save the session from dispose().
    final profiles = context.read<ProfilesState>();
    _activeChildId ??= profiles.activeProfile?.childId;
    _sessionMood = profiles.currentMood;
  }

  @override
  void dispose() {
    _listenWatch.stop();
    _recordSessionIfNeeded();
    _audioCompleteSub?.cancel();
    _naturalPosSub?.cancel();
    _audioPosSub?.cancel();
    _audioDurSub?.cancel();
    _engine.stop();
    _bgmPlayer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /* The settings in use — always the player-local copy. Child changes here
     stay in this session only. Both helpers return the same thing; the two
     names just read better at the call site (build vs. non-build). */
  UserSettings _watchSettings() => _localSettings ?? const UserSettings();

  UserSettings _readSettings() => _localSettings ?? const UserSettings();

  /* Change a setting in the player-local copy only — never save it back to
     SettingsState, so the child tapping a chip can't overwrite what the
     caregiver chose. */
  void _applySettingsChange(UserSettings Function(UserSettings) update) {
    setState(() {
      _localSettings = update(_localSettings ?? const UserSettings());
    });
  }

  /* Saves the finished listening session. Fire-and-forget — safe to call
     from dispose() since it uses saved values and the static
     DatabaseService (no BuildContext needed). */
  void _recordSessionIfNeeded() {
    if (_sessionRecorded) return;
    if (widget.previewMode) return; // a preview isn't a real session
    final childId = _activeChildId;
    final audiobookId = widget.audiobookId;
    final seconds = _listenWatch.elapsed.inSeconds;
    // Skip the built-in demo story and very short visits.
    if (childId == null || audiobookId == null || seconds < 3) return;
    _sessionRecorded = true;
    DatabaseService.recordListeningSession(
      childId: childId,
      audiobookId: audiobookId,
      durationSeconds: seconds,
      lastPositionSeconds: seconds,
      mood: _sessionMood,
      completed: _reachedEnd,
      pauseCount: _pauseCount,
      skipCount: _skipCount,
    );
  }

  Future<void> _loadAudiobook() async {
    if (widget.audiobookId == null) {
      _pages = _pagesFromText(_defaultStoryText, null);
      if (mounted) setState(() => _loading = false);
      return;
    }

    final settings = _readSettings();
    final resp = await DatabaseService.getAudiobookData(widget.audiobookId!);
    if (!mounted) return;

    // getAudiobookData gives us a ready-made Audiobook in resp.data.
    if (resp.success && resp.data is Audiobook) {
      final book = resp.data as Audiobook;
      _audiobook = book;
      _page = 0;
      if (book.pages.isNotEmpty) {
        // Caregiver-built storybook: one image + text per page. When
        // `audioStartMs` is set, it marks where the page starts in the
        // recording, giving exact page breaks instead of word-count guesses.
        _pages = book.pages
            .map((p) => _PlayerPage(
                  text: (p.text ?? '').trim(),
                  imageUrl: p.image,
                  audioStartMs: p.audioStartMs,
                ))
            .toList();
      } else {
        // Plain story text: split into pages by sentences, share the cover.
        _pages = _pagesFromText(
          book.contentText ?? _defaultStoryText,
          book.coverImage,
        );
      }
      if (book.audioFile != null && book.audioFile!.isNotEmpty) {
        try {
          final duration = await _engine.loadAudio(book.audioFile!);
          await _engine.setSpeed(settings.readingSpeed);
          _audioReady = true;
          _useTts = false;
          // Take the length just_audio gives us now, and keep watching in
          // case it arrives a bit later (streamed MP3s sometimes do).
          _knownAudioDuration = duration;
          _audioDurSub?.cancel();
          _audioDurSub = _engine.player.durationStream.listen((d) {
            if (d != null && d > Duration.zero) _knownAudioDuration = d;
          });
          // If we already know the length, build the page breaks and
          // read-along spans now; otherwise the position listener does it
          // on the first tick once the length is known.
          if (duration != null && duration > Duration.zero && _pages.isNotEmpty) {
            _pageEndTimes = _buildPageEndTimes(_pages, duration);
            _audioFilePageSpans =
                _buildAudioFilePageSpans(_pages, _pageEndTimes);
          }
          // Subscribe to the position stream now, not when Listen is
          // tapped, so page auto-flip and read-along are ready from the
          // first tick.
          _listenForAudioFilePosition();
        } catch (e) {
          // The book has a recording but it wouldn't load (usually the URL
          // isn't reachable from this device). Fall back to Gemini voice so
          // something plays, and tell the caregiver instead of switching
          // quietly.
          debugPrint('Audio file load failed for ${book.audioFile}: $e');
          _audioReady = false;
          _useTts = true;
          if (mounted) {
            AppSnackbar.warning(
              'Could not load this book\'s audio — using AI narration instead.',
              context: context,
            );
          }
        }
      }
    } else {
      _pages = _pagesFromText(_defaultStoryText, null);
      _page = 0;
    }

    if (mounted) setState(() => _loading = false);

    // Set the music volume so the slider is right before the first tap.
    // The music itself doesn't start until then (_startBgmIfNeeded).
    final book = _audiobook;
    if (book != null && book.musicTrackFileUrl != null) {
      _bgmVolume = book.bgmVolume;
    }

    // Load every page image into the cache now so tapping Next shows the
    // picture right away instead of waiting for it to download.
    if (mounted) _precachePageImages();
  }

  /* Start the music the first time (load, set volume, loop), or resume it
     after that. Does nothing if this book has no music. */
  Future<void> _startBgmIfNeeded() async {
    final url = _audiobook?.musicTrackFileUrl;
    if (url == null || url.isEmpty) return;
    try {
      if (!_bgmStarted) {
        _bgmStarted = true;
        await _bgmPlayer.setUrl(url);
        await _bgmPlayer.setVolume(_bgmVolume / 100.0);
        await _bgmPlayer.setLoopMode(LoopMode.one);
      }
      await _bgmPlayer.play();
    } catch (_) {
      // Music is optional; ignore failures.
    }
  }

  void _precachePageImages() {
    final seen = <String>{};
    final cover = _audiobook?.coverImage;
    if (cover != null && cover.isNotEmpty) seen.add(cover);
    for (final p in _pages) {
      final url = p.imageUrl;
      if (url == null || url.isEmpty) continue;
      seen.add(url);
    }
    for (final url in seen) {
      // Checks the disk cache first, then the network. After the first
      // fetch, later visits skip the download — handy on a slow emulator
      // or after restarting the app.
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: 800),
        context,
        onError: (_, _) {}, // ignore: the widget will retry when shown
      );
    }
  }

  // Break a long story into pages by sentence, all sharing [imageUrl].
  List<_PlayerPage> _pagesFromText(String text, String? imageUrl) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final chunks = <String>[];
    final buffer = StringBuffer();
    var sentenceCount = 0;
    for (final sentence in sentences) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
      sentenceCount++;
      if (sentenceCount >= 2 || buffer.length > 220) {
        chunks.add(buffer.toString());
        buffer.clear();
        sentenceCount = 0;
      }
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    if (chunks.isEmpty) chunks.add(text);
    return chunks.map((c) => _PlayerPage(text: c, imageUrl: imageUrl)).toList();
  }

  Future<void> _togglePlayPause() async {
    if (_useTts) {
      // Voice mode uses Gemini.
      await _toggleNarration();
      return;
    }
    if (_playingAudio) {
      await _engine.pause();
      unawaited(_bgmPlayer.pause());
      _listenWatch.stop();
      _pauseCount++; // count the pause for UC-9
    } else {
      unawaited(_engine.play()); // see note in _toggleNarration
      unawaited(_startBgmIfNeeded());
      _listenWatch.start();
      // No need to subscribe here — _loadAudiobook already set up the
      // position listener, so page auto-flip works from the first tick.
    }
    if (mounted) setState(() => _playingAudio = !_playingAudio);
  }

  /* Play/pause the current page with Gemini's voice, highlighting each word
     as it's spoken (karaoke-style) for read-along. */
  Future<void> _toggleNarration() async {
    if (_naturalLoading) return;

    // Already reading this page -> pause / resume.
    if (_naturalPlaying) {
      if (_playingAudio) {
        await _engine.pause();
        unawaited(_bgmPlayer.pause());
        _listenWatch.stop();
        _pauseCount++; // count the pause for UC-9
        if (mounted) setState(() => _playingAudio = false);
      } else {
        unawaited(_engine.play()); // see note in fresh-play branch below
        unawaited(_startBgmIfNeeded());
        _listenWatch.start();
        if (mounted) setState(() => _playingAudio = true);
      }
      return;
    }

    if (_pages.isEmpty) return;
    final text = _pages[_page].text.trim();
    if (text.isEmpty) return;

    // Read settings before any await (don't use context across async gaps).
    final settings = _readSettings();
    final voice = settings.narratorVoice.apiValue;
    final speed = settings.readingSpeed;

    // Tag this read; if a newer one or a page turn starts, this one stops.
    final seq = ++_narrationSeq;

    if (mounted) {
      setState(() {
        _highlightStart = 0;
        _highlightEnd = 0;
        _naturalLoading = true;
      });
    }

    final resp = await DatabaseService.getNaturalVoiceUrl(text: text, voice: voice);
    if (!mounted || seq != _narrationSeq) return; // a newer read took over
    setState(() => _naturalLoading = false);

    if (resp.success && resp.data is String) {
      try {
        await _engine.loadAudio(resp.data as String);
        if (!mounted || seq != _narrationSeq) return;
        await _engine.setSpeed(speed);
        // Read-along needs the clip length, which often isn't known right
        // after loading. We build the word spans on the first position tick
        // (see _listenForNaturalProgress) so read-along works on the first tap.
        _narrationText = text;
        _wordSpans = const [];
        _naturalPlaying = true;
        _listenForNaturalProgress();
        // just_audio's play() finishes only when playback ENDS, not when it
        // starts. Awaiting it would block the setState below until the clip
        // was done, so we don't await it.
        unawaited(_engine.play());
        unawaited(_startBgmIfNeeded());
        _listenWatch.start();
        if (mounted) setState(() => _playingAudio = true);
      } catch (e) {
        debugPrint('Narration playback failed: $e');
        _naturalPlaying = false;
        if (mounted) {
          AppSnackbar.error(context.trRead('msg.narration_failed'),
              context: context);
        }
      }
    } else {
      AppSnackbar.error(resp.message, context: context);
    }
  }

  // Follow the playback position and highlight the word being spoken.
  void _listenForNaturalProgress() {
    _naturalPosSub?.cancel();
    if (!_readSettings().readAlong) return;
    _naturalPosSub = _engine.positionStream.listen((pos) {
      if (!mounted || !_naturalPlaying) return;
      // Build the word spans once the clip length is known (usually not
      // right when playback starts).
      if (_wordSpans.isEmpty) {
        final total = _engine.player.duration;
        if (total == null || total <= Duration.zero) return;
        _wordSpans = _buildWordSpans(_narrationText, total);
        if (_wordSpans.isEmpty) return;
      }
      for (final span in _wordSpans) {
        if (pos >= span.start && pos < span.end) {
          if (_highlightStart != span.charStart || _highlightEnd != span.charEnd) {
            setState(() {
              _highlightStart = span.charStart;
              _highlightEnd = span.charEnd;
            });
          }
          return;
        }
      }
    });
  }

  /* When each page ends in a whole-book recording. If the caregiver marked
     page starts during upload (audioStartMs set and increasing), we use
     those exact marks — page i ends where page i+1 starts, last page ends
     at the clip's end. Otherwise we guess from word counts. */
  List<Duration> _buildPageEndTimes(List<_PlayerPage> pages, Duration total) {
    if (pages.length <= 1) return [total];
    // Are all the later pages marked and increasing?
    var monotonic = true;
    var prevMs = 0;
    for (var i = 1; i < pages.length; i++) {
      final m = pages[i].audioStartMs;
      if (m == null || m <= prevMs) {
        monotonic = false;
        break;
      }
      prevMs = m;
    }
    if (monotonic && pages.last.audioStartMs! < total.inMilliseconds) {
      // Each page ends where the next starts; the last ends at the total.
      final out = <Duration>[];
      for (var i = 0; i < pages.length; i++) {
        final endMs = i == pages.length - 1
            ? total.inMilliseconds
            : pages[i + 1].audioStartMs!;
        out.add(Duration(milliseconds: endMs));
      }
      return out;
    }
    return _computePageEndTimes(pages, total);
  }

  /* Work out each page's end time by its share of the total words.
     Splits evenly if there's no usable text. */
  List<Duration> _computePageEndTimes(List<_PlayerPage> pages, Duration total) {
    final counts = pages
        .map((p) => RegExp(r'\S+').allMatches(p.text).length)
        .toList();
    final totalWords = counts.fold<int>(0, (a, b) => a + b);
    final ms = total.inMilliseconds;
    final out = <Duration>[];
    if (totalWords == 0) {
      // No text — split the timeline evenly across pages.
      for (var i = 0; i < pages.length; i++) {
        out.add(Duration(milliseconds: ((ms * (i + 1)) / pages.length).round()));
      }
      return out;
    }
    var acc = 0;
    for (var i = 0; i < pages.length; i++) {
      acc += counts[i];
      out.add(Duration(milliseconds: ((ms * acc) / totalWords).round()));
    }
    return out;
  }

  /* Word spans for each page, placed on the full clip timeline. `out[i][j]`
     is word j of page i, with start/end times on the whole clip (not the
     page), so a position tick matches them directly. */
  List<List<_WordSpan>> _buildAudioFilePageSpans(
    List<_PlayerPage> pages,
    List<Duration> endTimes,
  ) {
    final out = <List<_WordSpan>>[];
    for (var i = 0; i < pages.length; i++) {
      final start = i == 0 ? Duration.zero : endTimes[i - 1];
      final end = endTimes[i];
      final pageDuration = end - start;
      if (pageDuration <= Duration.zero) {
        out.add(const []);
        continue;
      }
      final raw = _buildWordSpans(pages[i].text, pageDuration);
      out.add(
        raw
            .map((s) => _WordSpan(
                  s.charStart,
                  s.charEnd,
                  s.start + start,
                  s.end + start,
                ))
            .toList(),
      );
    }
    return out;
  }

  /* While the uploaded recording plays, drive both auto page-flips and
     read-along from the position stream. Subscribed early so page sync
     works from the first tick the length is known. */
  void _listenForAudioFilePosition() {
    _audioPosSub?.cancel();
    if (_useTts || !_audioReady || _pages.isEmpty) return;
    _audioPosSub = _engine.positionStream.listen((pos) async {
      if (!mounted || !_playingAudio || _useTts) return;

      // If the length wasn't known at load time, the page breaks and word
      // spans aren't built yet — build them once a real length shows up.
      // Prefer _knownAudioDuration (from the durationStream listener); for
      // some streamed MP3s only that ever becomes non-null.
      if (_pageEndTimes.length != _pages.length) {
        final dur = _knownAudioDuration ?? _engine.player.duration;
        if (dur == null || dur <= Duration.zero) return;
        _pageEndTimes = _buildPageEndTimes(_pages, dur);
        _audioFilePageSpans =
            _buildAudioFilePageSpans(_pages, _pageEndTimes);
      }

      // Flip the page once the recording passes the current page's end.
      // _autoAdvanceInFlight stops a second flip from starting during the
      // 480 ms animation while ticks keep coming.
      if (!_autoAdvanceInFlight &&
          _page < _pages.length - 1 &&
          pos >= _pageEndTimes[_page]) {
        _autoAdvanceInFlight = true;
        _suppressAudioPageSeek = true; // audio is already at the right spot
        try {
          await _changePage(_page + 1);
        } finally {
          _autoAdvanceInFlight = false;
        }
        return;
      }

      // Read-along: highlight the word of this page at the current position.
      // Stop quietly if read-along is off or this page has no word spans.
      if (!_readSettings().readAlong) return;
      if (_page >= _audioFilePageSpans.length) return;
      final pageSpans = _audioFilePageSpans[_page];
      if (pageSpans.isEmpty) return;
      for (final span in pageSpans) {
        if (pos >= span.start && pos < span.end) {
          if (_highlightStart != span.charStart ||
              _highlightEnd != span.charEnd) {
            setState(() {
              _highlightStart = span.charStart;
              _highlightEnd = span.charEnd;
            });
          }
          return;
        }
      }
    });
  }

  /* Spread the words of [text] across [total], giving longer words and
     punctuation more time, to estimate when each word is spoken. */
  List<_WordSpan> _buildWordSpans(String text, Duration? total) {
    if (total == null || total.inMilliseconds <= 0) return const [];
    final matches = RegExp(r'\S+').allMatches(text).toList();
    if (matches.isEmpty) return const [];

    final weights = <double>[];
    var totalWeight = 0.0;
    for (final m in matches) {
      final word = text.substring(m.start, m.end);
      var w = word.length + 1.0;
      if (RegExp(r'[.!?,;:]$').hasMatch(word)) w += 3; // pause after a mark
      weights.add(w);
      totalWeight += w;
    }

    final totalMs = total.inMilliseconds.toDouble();
    final spans = <_WordSpan>[];
    var acc = 0.0;
    for (var i = 0; i < matches.length; i++) {
      final startMs = (acc / totalWeight) * totalMs;
      acc += weights[i];
      final endMs = (acc / totalWeight) * totalMs;
      spans.add(_WordSpan(
        matches[i].start,
        matches[i].end,
        Duration(milliseconds: startMs.round()),
        Duration(milliseconds: endMs.round()),
      ));
    }
    return spans;
  }

  Future<void> _stopNaturalVoice() async {
    _narrationSeq++; // cancel any voice load in progress
    _naturalPosSub?.cancel();
    _naturalPosSub = null;
    _naturalPlaying = false;
    _naturalLoading = false;
    _wordSpans = const [];
    await _engine.stop();
  }

  // Runs when a page's voice clip finishes playing.
  void _onNaturalVoiceComplete() {
    _naturalPosSub?.cancel();
    _naturalPosSub = null;
    _naturalPlaying = false;
    _wordSpans = const [];
    _listenWatch.stop();
    if (!mounted) return;
    setState(() {
      _playingAudio = false;
      _highlightStart = 0;
      _highlightEnd = 0;
    });

    final isLastPage = _page >= _pages.length - 1;
    if (isLastPage) {
      unawaited(_bgmPlayer.pause()); // story done — stop the music
      _reachedEnd = true;
      _recordSessionIfNeeded();
      _showFinishDialog();
      return;
    }
    if (_readSettings().autoPlayNext) {
      // Music keeps playing through the page flip; _toggleNarration
      // resumes it if it ever paused.
      _changePage(_page + 1).then((_) {
        if (mounted) _toggleNarration();
      });
    } else {
      unawaited(_bgmPlayer.pause()); // wait for the next Listen tap
    }
  }

  Future<void> _changePage(int next, {bool autoSpeak = false}) async {
    if (next < 0 || next >= _pages.length || next == _page) return;
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOutCubic,
      );
    } else {
      setState(() => _page = next);
    }
    if (autoSpeak && _useTts && mounted) {
      await _toggleNarration();
    }
  }

  Future<void> _onPageChanged(int next) async {
    if (!mounted || next == _page) return;
    final wasNarrating = _naturalPlaying && _playingAudio;
    // Count a skip only when the child moves forward themselves (Next or
    // swipe). Going back or an auto page-flip don't count.
    if (next > _page && !_suppressAudioPageSeek) {
      _skipCount++;
    }
    // Voice is per-page, so stop it when the page turns.
    if (_naturalPlaying) {
      await _stopNaturalVoice();
    }
    final previousPage = _page;
    setState(() {
      _page = next;
      _highlightStart = 0;
      _highlightEnd = 0;
      if (_useTts) _playingAudio = false;
    });
    // If the child turned the page while reading, read the new page.
    if (wasNarrating && _useTts && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) await _toggleNarration();
      return;
    }
    // Uploaded-audio mode: move the audio to the page the user just chose.
    // If the page changed because the audio crossed the boundary itself,
    // skip the seek — we're already there.
    if (!_useTts &&
        _audioReady &&
        _pageEndTimes.length == _pages.length &&
        _pageEndTimes.isNotEmpty) {
      if (_suppressAudioPageSeek) {
        _suppressAudioPageSeek = false;
        return;
      }
      // Manual jump (Next/Back/swipe) — move the audio to the start of [next].
      // Page 0 starts at 0; later pages start at the previous page's end.
      final start = next == 0 ? Duration.zero : _pageEndTimes[next - 1];
      // Nudge just past the boundary so the listener doesn't think we're
      // still on the old page.
      const epsilon = Duration(milliseconds: 50);
      try {
        await _engine.seek(start + epsilon);
      } catch (_) {}
      // Stepping back can leave the engine in a finished state. Resume if
      // the user was already listening.
      if (_playingAudio && next < previousPage) {
        unawaited(_engine.play());
      }
    }
  }

  // Show a calm, happy dialog when the whole story is finished.
  Future<void> _showFinishDialog() async {
    if (!mounted || _finishShowing) return;
    _finishShowing = true;
    await _stopNaturalVoice();
    if (!mounted) {
      _finishShowing = false;
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _FinishReadingDialog(
        storyTitle: widget.title,
        onReadAgain: () {
          Navigator.of(dialogContext).pop();
          _restartStory();
        },
        onDone: () {
          Navigator.of(dialogContext).pop();
          Navigator.of(context).maybePop();
        },
      ),
    );
    _finishShowing = false;
  }

  // Go back to page one and start reading from the top.
  Future<void> _restartStory() async {
    _reachedEnd = false;
    _sessionRecorded = false;
    _listenWatch
      ..reset()
      ..start();
    if (_pageController.hasClients && _page != 0) {
      await _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted) return;
    setState(() => _page = 0);
    if (_useTts) {
      await _toggleNarration();
    } else if (_audioReady) {
      await _engine.seek(Duration.zero);
      unawaited(_engine.play()); // see note in _toggleNarration
      setState(() => _playingAudio = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildStorybook(),
              const SizedBox(height: 14),
              _buildPageIndicator(),
              const SizedBox(height: 18),
              _buildControlBar(),
              const SizedBox(height: 16),
              if (widget.previewMode) ...[
                const _PreviewNotice(),
                const SizedBox(height: 12),
              ],
              _buildSettingsPanel(),
              const SizedBox(height: 8),
              Text(
                widget.previewMode
                    ? context.tr('player.preview_helper')
                    : context.tr('player.helper_text'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        BackPill(onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 56),
      ],
    );
  }

  Widget _buildStorybook() {
    final settings = _watchSettings();
    final readAlongEnabled = settings.readAlong;
    final textScale = settings.textScale;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.softPeach, AppColors.softLavender],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 460,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: _onPageChanged,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                // Highlighting is on for both Gemini voice and uploaded
                // recordings, since both feed word spans to the listener.
                final narrating = _playingAudio &&
                    (_naturalPlaying || (!_useTts && _audioReady));
                final page = _StorybookPage(
                  imageUrl: _pages[index].imageUrl ?? _audiobook?.coverImage,
                  text: _pages[index].text,
                  highlightStart: (readAlongEnabled && index == _page && narrating)
                      ? _highlightStart
                      : 0,
                  highlightEnd: (readAlongEnabled && index == _page && narrating)
                      ? _highlightEnd
                      : 0,
                  pageNumber: index + 1,
                  totalPages: _pages.length,
                  author: _audiobook?.author,
                  textScale: textScale,
                );
                // The page flip is just PageView's slide. An earlier 3D
                // rotation looked nice in stills but made dark wedges
                // mid-swipe, so we dropped it. The plain slide is clean
                // and still feels like turning a page.
                return page;
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    final total = _pages.length;
    if (total <= 1) return const SizedBox.shrink();
    final showDots = total <= 12;
    if (!showDots) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Text(
            'Page ${_page + 1} of $total',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primaryBlueDark : AppColors.cardBorder,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }

  Widget _buildControlBar() {
    final isPlaying = _useTts ? (_naturalPlaying && _playingAudio) : _playingAudio;
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.chevron_left_rounded,
          label: 'Back',
          color: AppColors.softLavender,
          enabled: _page > 0,
          onTap: () => _changePage(_page - 1),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BigPlayButton(
            playing: isPlaying,
            loading: _useTts && _naturalLoading,
            onTap: _togglePlayPause,
          ),
        ),
        const SizedBox(width: 12),
        _RoundIconButton(
          icon: Icons.chevron_right_rounded,
          label: 'Next',
          color: AppColors.softMint,
          enabled: _page < _pages.length - 1,
          onTap: () => _changePage(_page + 1),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    final settings = _watchSettings();
    final speed = settings.readingSpeed;
    final textScale = settings.textScale;
    final currentVoice = settings.narratorVoice;
    // _loadAudiobook sets _useTts based on whether the book has a recording.
    // There's no manual toggle — most books have only one way to play.
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_useTts) ...[
            _SettingSectionLabel(
              icon: Icons.record_voice_over_rounded,
              label: context.tr('settings.narrator_voice'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NarratorVoice.values.map((voice) {
                return _VoicePill(
                  voice: voice,
                  label: context.tr('voice.${voice.apiValue}'),
                  selected: voice == currentVoice,
                  onTap: () => _setVoice(voice),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 18),
          _SettingSectionLabel(
            icon: Icons.speed_rounded,
            label: context.tr('settings.reading_speed'),
            trailing: _ValuePill(
              value: '${speed.toStringAsFixed(1)}x',
              subtitle: context.tr(_speedDescriptorKey(speed)),
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryBlueDark,
              thumbColor: AppColors.primaryBlueDark,
              overlayColor: AppColors.primaryBlue.withValues(alpha: 0.2),
              inactiveTrackColor: AppColors.cardBorder,
            ),
            child: Slider(
              value: speed.clamp(0.5, 2.0),
              min: 0.5,
              max: 2.0,
              divisions: 15,
              label: '${speed.toStringAsFixed(1)}x',
              onChanged: (value) async {
                _applySettingsChange((s) => s.copyWith(readingSpeed: value));
                // Both voice and audio play through the engine. Speed is
                // pitch-corrected and read-along uses media time, so they
                // stay in sync when the speed changes.
                if (_naturalPlaying || (!_useTts && _audioReady)) {
                  await _engine.setSpeed(value);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.tr('settings.slower'),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                Text(context.tr('settings.faster'),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          if (_audiobook?.trackId != null) ...[
            const SizedBox(height: 18),
            _SettingSectionLabel(
              icon: Icons.library_music_rounded,
              label: 'Background Music Volume',
              trailing: _ValuePill(value: '$_bgmVolume%'),
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primaryBlueDark,
                thumbColor: AppColors.primaryBlueDark,
                overlayColor: AppColors.primaryBlue.withValues(alpha: 0.2),
                inactiveTrackColor: AppColors.cardBorder,
              ),
              child: Slider(
                value: _bgmVolume.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '$_bgmVolume%',
                onChanged: (value) async {
                  setState(() => _bgmVolume = value.round());
                  await _bgmPlayer.setVolume(_bgmVolume / 100.0);
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          _SettingSectionLabel(
            icon: Icons.format_size_rounded,
            label: context.tr('settings.text_size'),
            trailing: _ValuePill(
              value: '${(textScale * 100).round()}%',
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryBlueDark,
              thumbColor: AppColors.primaryBlueDark,
              overlayColor: AppColors.primaryBlue.withValues(alpha: 0.2),
              inactiveTrackColor: AppColors.cardBorder,
            ),
            child: Slider(
              value: textScale.clamp(0.7, 2.0),
              min: 0.7,
              max: 2.0,
              divisions: 13,
              label: '${(textScale * 100).round()}%',
              onChanged: (value) =>
                  _applySettingsChange((s) => s.copyWith(textScale: value)),
            ),
          ),
        ],
      ),
    );
  }

  // Pick the speed label ("Slow" / "Normal" / "Fast") for the slider value.
  String _speedDescriptorKey(double speed) {
    if (speed <= 0.85) return 'player.speed_slow';
    if (speed >= 1.15) return 'player.speed_fast';
    return 'player.speed_normal';
  }

  Future<void> _setVoice(NarratorVoice voice) async {
    final wasNarrating = _naturalPlaying;
    _applySettingsChange((s) => s.copyWith(narratorVoice: voice));
    // If we were reading, restart this page so the new voice is heard.
    if (wasNarrating && mounted) {
      await _stopNaturalVoice();
      if (!mounted) return;
      setState(() => _playingAudio = false);
      await _toggleNarration();
    }
  }
}

// One storybook page: its text and optional image.
class _PlayerPage {
  final String text;
  final String? imageUrl;
  /* Where this page starts in the recording, in ms. Null on page 1 and on
     unmarked books — the player guesses from word counts when it's missing. */
  final int? audioStartMs;
  const _PlayerPage({required this.text, this.imageUrl, this.audioStartMs});
}

/* A word's character range and the time window it's spoken in, used for
   karaoke-style highlighting. */
class _WordSpan {
  final int charStart;
  final int charEnd;
  final Duration start;
  final Duration end;
  const _WordSpan(this.charStart, this.charEnd, this.start, this.end);
}

// The happy dialog shown when the child finishes the story.
class _FinishReadingDialog extends StatelessWidget {
  final String storyTitle;
  final VoidCallback onReadAgain;
  final VoidCallback onDone;

  const _FinishReadingDialog({
    required this.storyTitle,
    required this.onReadAgain,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.softYellow, AppColors.softPeach],
                ),
              ),
              child: const Center(
                child: Text('🌟', style: TextStyle(fontSize: 48)),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.tr('player.finish_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              storyTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('player.finish_subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: context.tr('player.read_again'),
                    icon: Icons.replay_rounded,
                    filled: false,
                    onTap: onReadAgain,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DialogButton(
                    label: context.tr('player.finish_done'),
                    icon: Icons.check_rounded,
                    filled: true,
                    onTap: onDone,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _DialogButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryBlueDark : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: filled ? AppColors.primaryBlueDark : AppColors.cardBorder,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: filled ? Colors.white : AppColors.textPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: filled ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorybookPage extends StatelessWidget {
  final String? imageUrl;
  final String text;
  final int highlightStart;
  final int highlightEnd;
  final int pageNumber;
  final int totalPages;
  final String? author;
  final double textScale;

  const _StorybookPage({
    required this.imageUrl,
    required this.text,
    required this.highlightStart,
    required this.highlightEnd,
    required this.pageNumber,
    required this.totalPages,
    this.author,
    this.textScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Illustration(imageUrl: imageUrl),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.softYellow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Page $pageNumber of $totalPages',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (author != null && author!.isNotEmpty)
                Flexible(
                  child: Text(
                    author!,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            // _HighlightedText has its own ScrollController to keep the
            // spoken word in view, so don't wrap it in another scroll view.
            child: _HighlightedText(
              text: text,
              highlightStart: highlightStart,
              highlightEnd: highlightEnd,
              textScale: textScale,
            ),
          ),
        ],
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  final String? imageUrl;
  const _Illustration({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: (imageUrl != null && imageUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                // Decode smaller — the AI images are 1024x1024 and decoding
                // several at full size can crash low-memory devices. The
                // disk copy is kept full-size, so re-views are still instant.
                memCacheWidth: 800,
                placeholder: (_, _) => _placeholder(loading: true),
                errorWidget: (_, _, _) => _placeholder(),
                fadeInDuration: const Duration(milliseconds: 120),
                fadeOutDuration: Duration.zero,
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder({bool loading = false}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.softLavender, AppColors.softPeach],
        ),
      ),
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : const Icon(
                Icons.auto_stories_rounded,
                size: 84,
                color: AppColors.primaryBlueDark,
              ),
      ),
    );
  }
}

/* Page text with karaoke-style highlighting that auto-scrolls to keep the
   spoken word in view, so the child doesn't have to scroll to follow along.
   The highlight is kept in the upper third of the view. */
class _HighlightedText extends StatefulWidget {
  final String text;
  final int highlightStart;
  final int highlightEnd;
  final double textScale;

  const _HighlightedText({
    required this.text,
    required this.highlightStart,
    required this.highlightEnd,
    this.textScale = 1.0,
  });

  @override
  State<_HighlightedText> createState() => _HighlightedTextState();
}

class _HighlightedTextState extends State<_HighlightedText> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _textKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HighlightedText old) {
    super.didUpdateWidget(old);
    // On a page turn, jump back to the top so the new page starts fresh.
    if (widget.text != old.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
      return;
    }
    if (widget.highlightStart != old.highlightStart ||
        widget.highlightEnd != old.highlightEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureHighlightVisible();
      });
    }
  }

  /* If the highlighted word is off-screen or near the edge, scroll so it
     sits about a third from the top — room above to look back, room below
     for what's next. */
  void _ensureHighlightVisible() {
    if (!mounted || !_scroll.hasClients) return;
    final ctx = _textKey.currentContext;
    if (ctx == null) return;
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null || renderBox.size.width <= 0) return;

    final start = widget.highlightStart;
    final end = widget.highlightEnd;
    if (end <= start || start < 0 || end > widget.text.length) return;

    // Lay out the same TextSpan we render so the positions match (the bold
    // highlight shifts line breaks slightly).
    final painter = TextPainter(
      text: _buildSpan(),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: start),
      Rect.zero,
    );
    final wordTopY = caret.dy;

    final viewport = _scroll.position.viewportDimension;
    final maxScroll = _scroll.position.maxScrollExtent;
    final current = _scroll.position.pixels;
    if (maxScroll <= 0) return;

    final desired = (wordTopY - viewport * 0.3).clamp(0.0, maxScroll);
    // Already close enough — skip the animation so rapid ticks don't jitter
    // the scroll.
    if ((desired - current).abs() < 8) return;

    _scroll.animateTo(
      desired,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  TextStyle get _baseStyle => TextStyle(
        fontSize: 20 * widget.textScale,
        height: 1.7,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      );

  TextSpan _buildSpan() {
    final base = _baseStyle;
    final start = widget.highlightStart;
    final end = widget.highlightEnd;
    final valid =
        end > start && start >= 0 && end <= widget.text.length;
    if (!valid) {
      return TextSpan(text: widget.text, style: base);
    }
    final highlightStyle = base.copyWith(
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      background: Paint()..color = AppColors.softYellow,
    );
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: widget.text.substring(0, start)),
        TextSpan(
          text: widget.text.substring(start, end),
          style: highlightStyle,
        ),
        TextSpan(text: widget.text.substring(end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      child: RichText(
        key: _textKey,
        text: _buildSpan(),
      ),
    );
  }
}

/* Small banner shown in caregiver preview — reminds them that voice/speed/
   text-size changes only affect this preview. */
class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.softLavender.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              color: AppColors.primaryBlueDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('player.preview_banner'),
              style: const TextStyle(
                  color: AppColors.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigPlayButton extends StatelessWidget {
  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  const _BigPlayButton({
    required this.playing,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 78,
        decoration: BoxDecoration(
          color: playing ? AppColors.primaryBlueDark : AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlueDark.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 40,
              ),
            const SizedBox(width: 6),
            Text(
              loading
                  ? context.tr('player.preparing')
                  : (playing
                      ? context.tr('player.pause')
                      : context.tr('player.listen')),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 34, color: AppColors.textPrimary),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* Settings-panel section header: icon + bold label, with an optional value
   pill on the right (e.g. "0.7x · Slow"). */
class _SettingSectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const _SettingSectionLabel({
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryBlueDark),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/* Rounded pill showing a value, with an optional subtitle after a thin
   divider (e.g. "0.7x · Slow"). */
class _ValuePill extends StatelessWidget {
  final String value;
  final String? subtitle;
  const _ValuePill({required this.value, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.softPeach.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13),
          ),
          if (subtitle != null) ...[
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.textSecondary.withValues(alpha: 0.35),
            ),
            Text(
              subtitle!,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* Narrator-voice chip with an icon and soft tint. When selected, it turns
   blue with a checkmark so the active voice is obvious. */
class _VoicePill extends StatelessWidget {
  final NarratorVoice voice;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _VoicePill({
    required this.voice,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const _icons = <NarratorVoice, IconData>{
    NarratorVoice.calmFemale: Icons.female_rounded,
    NarratorVoice.gentleFemale: Icons.female_rounded,
    NarratorVoice.warmMale: Icons.male_rounded,
    NarratorVoice.friendlyChild: Icons.child_care_rounded,
    NarratorVoice.soothingElder: Icons.elderly_rounded,
  };

  // A soft tint per voice so unselected chips look distinct but still calm.
  static const _tints = <NarratorVoice, Color>{
    NarratorVoice.calmFemale: AppColors.softPink,
    NarratorVoice.gentleFemale: AppColors.softLavender,
    NarratorVoice.warmMale: AppColors.softMint,
    NarratorVoice.friendlyChild: AppColors.softYellow,
    NarratorVoice.soothingElder: AppColors.softPeach,
  };

  @override
  Widget build(BuildContext context) {
    final tint = _tints[voice] ?? AppColors.surface;
    final iconData = _icons[voice] ?? Icons.person_outline_rounded;
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlueDark
                : tint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlueDark
                  : AppColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded,
                    size: 16, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Icon(iconData, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

