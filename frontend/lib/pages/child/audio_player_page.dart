import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../audio/audio_engine.dart';
import '../../audio/audio_safety.dart';
import '../../i18n/i18n.dart';
import '../../models/audiobook.dart';
import '../../models/user_settings.dart';
import '../../services/database_service.dart';
import '../../services/reading_progress.dart';
import '../../state/profiles_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/player_controls.dart';
import '../../widgets/soft_card.dart';

class AudioPlayerPage extends StatefulWidget {
  final String title;
  final String? audiobookId;

  /* Caregiver preview: play the book to check it, with no settings panel
     and no listening session saved. */
  final bool previewMode;

  // "Continue reading": open at the page (and answers) saved last time.
  final ReadingProgress? resumeFrom;

  const AudioPlayerPage({
    super.key,
    required this.title,
    this.audiobookId,
    this.previewMode = false,
    this.resumeFrom,
  });

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  final AudioEngine _engine = AudioEngine.instance;
  // Swapped once for one that opens at the saved page, before it's shown.
  PageController _pageController = PageController();

  Audiobook? _audiobook;
  // The pages being shown. For an interactive book this is only the path
  // the child has unlocked so far (see _buildInteractivePath).
  List<_PlayerPage> _pages = [];
  // Interactive books: every page row from the server, both versions of
  // split pages included. Empty for linear books.
  List<_PlayerPage> _allPages = [];
  // Interactive books: the child's answers, keyed by the question page's
  // index in _allPages, value = the picked choice's index.
  final Map<int, int> _answers = {};
  // True once a question page has been read aloud to the end, so picking
  // an answer carries on reading (if auto-play is on).
  bool _heardQuestion = false;
  // True while a picked answer turns the page - ignores repeat taps and
  // keeps the turn from counting as a skip.
  bool _pickingChoice = false;
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
  /* For the settings advisor: times the child went back a page, the
     furthest page reached, and the settings this book started with (so a
     session only reports speed, text size or voice the child changed). */
  int _backCount = 0;
  int _furthestPage = 0;
  UserSettings? _startSettings;
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
  // Errors while playing (dropped connection, broken clip) - FR19.
  StreamSubscription<PlaybackEvent>? _playbackErrorSub;
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
  // Set by a playback error so the next Play reloads the recording (FR19).
  bool _playbackFailed = false;
  // True while an auto page-flip is animating, so we don't start a second
  // one on every position tick during the 480 ms animation.
  bool _autoAdvanceInFlight = false;
  List<_WordSpan> _wordSpans = const [];
  String _narrationText = ''; // text of the page being read now

  // Background music - its own player so it doesn't clash with the voice.
  final AudioPlayer _bgmPlayer = AudioPlayer();
  // Fades the music in and out instead of starting/stopping it abruptly.
  late final AudioFader _bgmFader = AudioFader(_bgmPlayer);
  int _bgmVolume = 30;    // 0-[AudioSafety.bgmCeiling], from Audiobook.bgmVolume
  bool _bgmStarted = false; // true once it has started playing

  // Settings just for this player session - changes here don't save back to
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
    _startSettings = _localSettings;
    _loadAudiobook();
    // One listener for when playback finishes (voice or audio file).
    _audioCompleteSub = _engine.onComplete.listen((_) {
      if (!mounted) return;
      if (_naturalPlaying) {
        _onNaturalVoiceComplete();
        return;
      }
      // In voice mode a clip that was already stopped (page turn, choice
      // tap) can still report completed - it is not the end of the story.
      if (_useTts) return;
      // A real audio file finished -> celebrate.
      _listenWatch.stop();
      _reachedEnd = true;
      setState(() => _playingAudio = false);
      _recordSessionIfNeeded();
      _showFinishDialog();
    });
    // FR19: an error mid-playback stops everything gently and keeps the
    // child on the same page, instead of cutting out or leaving music on.
    _playbackErrorSub = _engine.player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) => _onPlaybackError(e),
    );
  }

  /* Back to a safe, quiet state after a playback error (FR19): music fades
     out, nothing is left "playing", the page and position stay where they
     were, and the child sees a calm message. The next Play tap reloads. */
  void _onPlaybackError(Object error) {
    debugPrint('Playback error: $error');
    // Load failures are handled where the clip is loaded; this is for
    // errors while something is actually playing.
    if (!mounted || !_playingAudio) return;
    unawaited(_pauseBgm());
    _listenWatch.stop();
    _naturalPlaying = false; // voice mode: the next tap fetches the page again
    _playbackFailed = true; // recording mode: the next tap reloads the file
    setState(() => _playingAudio = false);
    AppSnackbar.warning(context.trRead('player.err_playback'), context: context);
  }

  /* After a playback error the recording has to be loaded again before it
     can play. Pick up from the same spot. */
  Future<bool> _reloadRecordingIfFailed() async {
    if (!_playbackFailed) return true;
    final url = _audiobook?.audioFile;
    if (url == null || url.isEmpty) return false;
    final at = _engine.player.position;
    try {
      await _engine.loadAudio(url);
      await _engine.seek(at);
      _playbackFailed = false;
      return true;
    } catch (e) {
      debugPrint('Reloading the recording failed: $e');
      if (mounted) {
        AppSnackbar.warning(context.trRead('player.err_playback'), context: context);
      }
      return false;
    }
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
    _saveProgress(); // before stop(), while the recording's position is real
    _audioCompleteSub?.cancel();
    _naturalPosSub?.cancel();
    _audioPosSub?.cancel();
    _audioDurSub?.cancel();
    _playbackErrorSub?.cancel();
    _engine.stop();
    _bgmFader.cancel();
    _bgmPlayer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /* The settings in use - always the player-local copy. Child changes here
     stay in this session only. Both helpers return the same thing; the two
     names just read better at the call site (build vs. non-build). */
  UserSettings _watchSettings() => _localSettings ?? const UserSettings();

  UserSettings _readSettings() => _localSettings ?? const UserSettings();

  /* Change a setting in the player-local copy only - never save it back to
     SettingsState, so the child tapping a chip can't overwrite what the
     caregiver chose. */
  void _applySettingsChange(UserSettings Function(UserSettings) update) {
    setState(() {
      _localSettings = update(_localSettings ?? const UserSettings());
    });
  }

  /* Saves the finished listening session. Fire-and-forget - safe to call
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
    final start = _startSettings;
    final end = _readSettings();
    DatabaseService.recordListeningSession(
      childId: childId,
      audiobookId: audiobookId,
      durationSeconds: seconds,
      lastPositionSeconds: seconds,
      mood: _sessionMood,
      completed: _reachedEnd,
      pauseCount: _pauseCount,
      skipCount: _skipCount,
      pagesTotal: _pages.isEmpty ? null : _pages.length,
      pagesReached: _pages.isEmpty ? null : (_page > _furthestPage ? _page : _furthestPage) + 1,
      backCount: _backCount,
      // Only what the child changed with the icon buttons.
      speedUsed: start != null && end.readingSpeed != start.readingSpeed ? end.readingSpeed : null,
      textScaleUsed: start != null && end.textScale != start.textScale ? end.textScale : null,
      voiceUsed: start != null && end.narratorVoice != start.narratorVoice
          ? end.narratorVoice.apiValue
          : null,
    );
  }

  /* Remember where the child stopped, for "Continue reading" on the home
     page; forget it once the book is finished. Fire-and-forget, so it's
     safe from dispose(). */
  void _saveProgress() {
    if (widget.previewMode) return;
    final childId = _activeChildId;
    final audiobookId = widget.audiobookId;
    final book = _audiobook;
    if (childId == null || audiobookId == null || book == null || _pages.isEmpty) return;
    if (_reachedEnd) {
      ReadingProgress.clear(childId, audiobookId: audiobookId);
      return;
    }
    final positionMs =
        (!_useTts && _audioReady) ? _engine.player.position.inMilliseconds : 0;
    // Only peeked at the first page: keep whatever was saved before.
    if (_page == 0 && positionMs < 3000) return;
    final page = _page.clamp(0, _pages.length - 1);
    ReadingProgress.save(
      childId,
      ReadingProgress(
        audiobookId: audiobookId,
        title: widget.title,
        coverImage: book.coverImage,
        page: page,
        pageNumber: _displayPageNumber(page),
        totalPages: _displayTotalPages,
        audioPositionMs: positionMs,
        answers: Map.of(_answers),
      ),
    );
  }

  // Open at the saved page: same answers, same page, same spot in the
  // recording. Runs before the pages are first shown.
  Future<void> _applyResume() async {
    final resume = widget.resumeFrom;
    if (resume == null || resume.audiobookId != widget.audiobookId || _pages.isEmpty) return;
    if (_allPages.isNotEmpty && resume.answers.isNotEmpty) {
      _answers
        ..clear()
        ..addAll(resume.answers);
      _pages = _buildInteractivePath();
    }
    final page = resume.page.clamp(0, _pages.length - 1);
    if (page > 0) {
      _page = page;
      _pageController.dispose();
      _pageController = PageController(initialPage: page);
    }
    if (!_useTts && _audioReady && resume.audioPositionMs > 0) {
      try {
        await _engine.seek(Duration(milliseconds: resume.audioPositionMs));
      } catch (_) {}
    }
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
      if (book.isInteractive && book.pages.isNotEmpty) {
        // Interactive storybook: keep every row, then show only the path
        // the child's answers unlock.
        _answers.clear();
        _allPages = book.pages
            .map((p) => _PlayerPage(
                  text: (p.text ?? '').trim(),
                  imageUrl: p.image,
                  number: p.pageNumber,
                  choices: p.choices,
                  isSplit: p.isSplit,
                  branchIndex: p.branchIndex,
                ))
            .toList();
        _pages = _buildInteractivePath();
      } else if (book.pages.isNotEmpty) {
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
      // A whole-book recording can't follow the child's choices, so
      // interactive books are always read page by page with the voice.
      if (!book.isInteractive &&
          book.audioFile != null &&
          book.audioFile!.isNotEmpty) {
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
              context.trRead('player.err_audio'),
              context: context,
            );
          }
        }
      }
      await _applyResume();
      if (!mounted) return;
    } else {
      _pages = _pagesFromText(_defaultStoryText, null);
      _page = 0;
    }

    if (mounted) setState(() => _loading = false);

    // Set the music volume so the slider is right before the first tap.
    // The music itself doesn't start until then (_startBgmIfNeeded).
    final book = _audiobook;
    if (book != null && book.musicTrackFileUrl != null) {
      // Older books may have been saved louder than the ceiling allows.
      _bgmVolume = AudioSafety.clampBgm(book.bgmVolume);
    }

    // Load every page image into the cache now so tapping Next shows the
    // picture right away instead of waiting for it to download.
    if (mounted) _precachePageImages();
  }

  /* Start the music the first time (load, loop), or resume it after that.
     Either way it fades in from silence to the book's level (NFR5).
     Does nothing if this book has no music. */
  Future<void> _startBgmIfNeeded() async {
    final url = _audiobook?.musicTrackFileUrl;
    if (url == null || url.isEmpty) return;
    try {
      if (!_bgmStarted) {
        _bgmStarted = true;
        await _bgmPlayer.setUrl(url);
        await _bgmPlayer.setLoopMode(LoopMode.one);
      }
      await _bgmFader.fadeInPlay(_bgmVolume / 100.0);
    } catch (_) {
      // Music is optional; ignore failures.
    }
  }

  /// Fade the music out, then pause it (NFR5).
  Future<void> _pauseBgm() => _bgmFader.fadeOutPause();

  void _precachePageImages() {
    final seen = <String>{};
    final cover = _audiobook?.coverImage;
    if (cover != null && cover.isNotEmpty) seen.add(cover);
    // Interactive books: cache every branch, not just the current path.
    for (final p in _allPages.isNotEmpty ? _allPages : _pages) {
      final url = p.imageUrl;
      if (url == null || url.isEmpty) continue;
      seen.add(url);
    }
    for (final url in seen) {
      // Checks the disk cache first, then the network. After the first
      // fetch, later visits skip the download - handy on a slow emulator
      // or after restarting the app.
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: 800),
        context,
        onError: (_, _) {}, // ignore: the widget will retry when shown
      );
    }
  }

  /* The pages the child can reach in an interactive book, given _answers.
     Walks _allPages in order and:
     - stops after a question page that has no answer yet, so nothing past
       it can be read, swiped to or auto-played;
     - shows only the version of a split page that the answer leads to;
     - fills {choice} with the most recent answer. */
  List<_PlayerPage> _buildInteractivePath() {
    final path = <_PlayerPage>[];
    String? answer; // last picked choice, fills {choice}
    int? branch; // which split version comes next, if any
    for (var i = 0; i < _allPages.length; i++) {
      final p = _allPages[i];
      if (p.branchIndex != null) {
        if (p.branchIndex != branch) continue; // the other version
      } else {
        branch = null; // split pages are over
      }
      final text = answer == null
          ? p.text
          : p.text.replaceAll(AudiobookPage.choiceToken, answer);
      path.add(p.forPath(text: text, sourceIndex: i));
      if (p.isInteraction) {
        final picked = _answers[i];
        if (picked == null || picked >= p.choices.length) break;
        answer = p.choices[picked];
        branch = p.isSplit ? picked : null;
      }
    }
    return path;
  }

  // The question on screen if it still needs an answer, else null.
  _PlayerPage? get _pendingQuestion {
    if (_page >= _pages.length) return null;
    final p = _pages[_page];
    if (!p.isInteraction || _answers.containsKey(p.sourceIndex)) return null;
    return p;
  }

  /* The child picked [choice] on the current question page. Unlocks the
     next page(s), turns to it, and keeps reading if the child was
     listening. Picking again after going Back replaces later answers. */
  Future<void> _pickChoice(int choice) async {
    if (_pickingChoice || _page >= _pages.length) return;
    final source = _pages[_page].sourceIndex;
    if (source == null) return;
    _pickingChoice = true;
    try {
      final wasReading =
          (_naturalPlaying && _playingAudio) || _naturalLoading;
      final keepReading =
          wasReading || (_heardQuestion && _readSettings().autoPlayNext);
      if (_naturalPlaying || _naturalLoading) await _stopNaturalVoice();
      if (!mounted) return;
      setState(() {
        _answers.removeWhere((k, _) => k >= source);
        _answers[source] = choice;
        _pages = _buildInteractivePath();
        _playingAudio = false;
        _highlightStart = 0;
        _highlightEnd = 0;
      });
      // The question was the last page - the story is done.
      if (_page >= _pages.length - 1) {
        unawaited(_pauseBgm());
        _listenWatch.stop();
        _reachedEnd = true;
        _recordSessionIfNeeded();
        _showFinishDialog();
        return;
      }
      // Let the picked button show as selected before the page turns.
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await _changePage(_page + 1);
      if (keepReading && _useTts && mounted) await _toggleNarration();
    } finally {
      _pickingChoice = false;
    }
  }

  /* Page number and count shown to the child. Interactive books use the
     book's page numbers, so both split versions count as one page and the
     total doesn't grow as answers unlock more pages. */
  List<int> get _bookPageNumbers =>
      (_allPages.map((p) => p.number ?? 0).toSet().toList()..sort());

  int _displayPageNumber(int index) {
    final number = _pages[index].number;
    if (_allPages.isEmpty || number == null) return index + 1;
    return _bookPageNumbers.indexOf(number) + 1;
  }

  int get _displayTotalPages =>
      _allPages.isEmpty ? _pages.length : _bookPageNumbers.length;

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
      // Soft fade-out instead of a hard stop (NFR5).
      unawaited(_engine.fadeOutPause());
      unawaited(_pauseBgm());
      _listenWatch.stop();
      _pauseCount++; // count the pause for UC-9
    } else {
      if (!await _reloadRecordingIfFailed()) return;
      unawaited(_engine.fadeInPlay()); // fades in; see note in _toggleNarration
      unawaited(_startBgmIfNeeded());
      _listenWatch.start();
      // No need to subscribe here - _loadAudiobook already set up the
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
        unawaited(_engine.fadeOutPause()); // soft fade-out (NFR5)
        unawaited(_pauseBgm());
        _listenWatch.stop();
        _pauseCount++; // count the pause for UC-9
        if (mounted) setState(() => _playingAudio = false);
      } else {
        unawaited(_engine.fadeInPlay()); // fades in; see note in fresh-play branch below
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
        // was done, so we don't await it. It fades in (NFR5).
        unawaited(_engine.fadeInPlay());
        unawaited(_startBgmIfNeeded());
        _listenWatch.start();
        if (mounted) setState(() => _playingAudio = true);
      } catch (e) {
        debugPrint('Narration playback failed: $e');
        _naturalPlaying = false;
        unawaited(_pauseBgm()); // FR19: no music left running on its own
        if (mounted) {
          setState(() => _playingAudio = false);
          AppSnackbar.error(context.trRead('msg.narration_failed'),
              context: context);
        }
      }
    } else {
      unawaited(_pauseBgm()); // FR19: no music left running on its own
      setState(() => _playingAudio = false);
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
     those exact marks - page i ends where page i+1 starts, last page ends
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
      // No text - split the timeline evenly across pages.
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
      // spans aren't built yet - build them once a real length shows up.
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

    // Interactive question with no answer yet: wait for the child to pick.
    // Never turn the page or finish the story from here.
    if (_pendingQuestion != null) {
      _heardQuestion = true;
      unawaited(_pauseBgm());
      return;
    }

    final isLastPage = _page >= _pages.length - 1;
    if (isLastPage) {
      unawaited(_pauseBgm()); // story done - stop the music
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
      unawaited(_pauseBgm()); // wait for the next Listen tap
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
    if (next > _page && !_suppressAudioPageSeek && !_pickingChoice) {
      _skipCount++;
    }
    if (next < _page && !_suppressAudioPageSeek) _backCount++;
    // A resumed book starts part-way, so count from where it opened.
    if (_page > _furthestPage) _furthestPage = _page;
    if (next > _furthestPage) _furthestPage = next;
    // Voice is per-page, so stop it when the page turns.
    if (_naturalPlaying) {
      await _stopNaturalVoice();
    }
    final previousPage = _page;
    _heardQuestion = false;
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
    // skip the seek - we're already there.
    if (!_useTts &&
        _audioReady &&
        _pageEndTimes.length == _pages.length &&
        _pageEndTimes.isNotEmpty) {
      if (_suppressAudioPageSeek) {
        _suppressAudioPageSeek = false;
        return;
      }
      // Manual jump (Next/Back/swipe) - move the audio to the start of [next].
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
    // Back on page one, so the path can shrink safely: forget the answers.
    setState(() {
      _page = 0;
      if (_allPages.isNotEmpty) {
        _answers.clear();
        _heardQuestion = false;
        _pages = _buildInteractivePath();
      }
    });
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
              if (_page < _pages.length && _pages[_page].isInteraction) ...[
                const SizedBox(height: 14),
                _ChoicePanel(
                  // Keyed per question so it pops in again on each one.
                  key: ValueKey(_pages[_page].sourceIndex),
                  choices: _pages[_page].choices,
                  selected: _answers[_pages[_page].sourceIndex],
                  onPick: _pickChoice,
                ),
              ],
              const SizedBox(height: 14),
              _buildPageIndicator(),
              const SizedBox(height: 18),
              _buildControlBar(),
              const SizedBox(height: 16),
              /* No settings panel or helper text: too much to read. Voice,
                 speed and text size are icon buttons; a caregiver's preview
                 adds a small "preview" tag above them. */
              if (widget.previewMode) ...[
                const Center(child: _PreviewNotice()),
                const SizedBox(height: 12),
              ],
              _buildQuickControls(),
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
        // A long title glides by in a loop instead of being cut off.
        Expanded(
          child: MarqueeText(
            widget.title,
            textAlign: TextAlign.center,
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
                  pageNumber: _displayPageNumber(index),
                  totalPages: _displayTotalPages,
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
    final total = _displayTotalPages;
    if (total <= 1 || _pages.isEmpty) return const SizedBox.shrink();
    final current = _displayPageNumber(_page.clamp(0, _pages.length - 1));
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
            context
                .tr('player.page_of')
                .replaceAll('{current}', '$current')
                .replaceAll('{total}', '$total'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current - 1;
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
        RoundIconButton(
          icon: Icons.chevron_left_rounded,
          label: context.tr('player.back_btn'),
          color: AppColors.softLavender,
          enabled: _page > 0,
          onTap: () => _changePage(_page - 1),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BigPlayButton(
            playing: isPlaying,
            loading: _useTts && _naturalLoading,
            onTap: _togglePlayPause,
          ),
        ),
        const SizedBox(width: 12),
        RoundIconButton(
          icon: Icons.chevron_right_rounded,
          label: context.tr('player.next_btn'),
          color: AppColors.softMint,
          enabled: _page < _pages.length - 1,
          onTap: () => _changePage(_page + 1),
        ),
      ],
    );
  }

  /* Voice, speed and text size, with no words. Each is its own coloured
     row with a picture of what it changes on the left, and big buttons
     that look like what they do: a woman / man for the voice, a turtle /
     rabbit for slow / fast, a small / big "A" for the text. Changes only
     last for this book (the saved settings stay as they are). A preview
     also gets the music volume. */
  Widget _buildQuickControls() {
    final settings = _watchSettings();
    final speed = settings.readingSpeed;
    final textScale = settings.textScale;
    final voice = settings.narratorVoice;

    Future<void> setSpeed(double value) async {
      final v = (value * 10).round() / 10;
      _applySettingsChange((s) => s.copyWith(readingSpeed: v));
      // Speed is pitch-corrected and read-along follows media time, so
      // both stay in sync when it changes mid-page.
      if (_naturalPlaying || (!_useTts && _audioReady)) {
        await _engine.setSpeed(v);
      }
    }

    void setText(double value) {
      final v = (value * 10).round() / 10;
      _applySettingsChange((s) => s.copyWith(textScale: v));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_useTts) ...[
          _ControlRow(
            icon: Icons.record_voice_over_rounded,
            color: const Color(0xFFFFD9E6),
            accent: const Color(0xFFD94A82),
            label: context.tr('player.voice'),
            children: [
              _ControlButton(
                label: context.tr('voice.calm_female'),
                selected: voice == NarratorVoice.calmFemale,
                accent: const Color(0xFFD94A82),
                onTap: () => _setVoice(NarratorVoice.calmFemale),
                child: const _Emoji('\u{1F469}'),
              ),
              _ControlButton(
                label: context.tr('voice.warm_male'),
                selected: voice == NarratorVoice.warmMale,
                accent: const Color(0xFFD94A82),
                onTap: () => _setVoice(NarratorVoice.warmMale),
                child: const _Emoji('\u{1F468}'),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _ControlRow(
          icon: Icons.speed_rounded,
          color: const Color(0xFFD6EBFF),
          accent: const Color(0xFF2F7BD6),
          label: context.tr('player.speed'),
          children: [
            _ControlButton(
              label: context.tr('settings.slower'),
              accent: const Color(0xFF2F7BD6),
              onTap: speed > 0.55 ? () => setSpeed(speed - 0.1) : null,
              child: const _Emoji('\u{1F422}'),
            ),
            _ControlButton(
              label: context.tr('settings.faster'),
              accent: const Color(0xFF2F7BD6),
              onTap: speed < 1.95 ? () => setSpeed(speed + 0.1) : null,
              child: const _Emoji('\u{1F407}'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ControlRow(
          icon: Icons.format_size_rounded,
          color: const Color(0xFFD8F3DF),
          accent: const Color(0xFF2E9455),
          label: context.tr('player.text'),
          children: [
            _ControlButton(
              label: context.tr('player.text_smaller'),
              accent: const Color(0xFF2E9455),
              onTap: textScale > 0.75 ? () => setText(textScale - 0.1) : null,
              child: const _SizeA(small: true),
            ),
            _ControlButton(
              label: context.tr('player.text_larger'),
              accent: const Color(0xFF2E9455),
              onTap: textScale < 1.95 ? () => setText(textScale + 0.1) : null,
              child: const _SizeA(small: false),
            ),
          ],
        ),
        if (widget.previewMode && _audiobook?.trackId != null) ...[
          const SizedBox(height: 10),
          _ControlRow(
            icon: Icons.music_note_rounded,
            color: const Color(0xFFEDE1FF),
            accent: const Color(0xFF7457F5),
            label: context.tr('player.music'),
            children: [
              _ControlButton(
                label: context.tr('player.music_quieter'),
                accent: const Color(0xFF7457F5),
                onTap: _bgmVolume > 0 ? () => _setBgmVolume(_bgmVolume - 10) : null,
                child: const _Emoji('\u{1F509}'),
              ),
              _ControlButton(
                label: context.tr('player.music_louder'),
                accent: const Color(0xFF7457F5),
                // Can't go past the music ceiling (FR10, NFR5).
                onTap: _bgmVolume < AudioSafety.bgmCeiling
                    ? () => _setBgmVolume(_bgmVolume + 10)
                    : null,
                child: const _Emoji('\u{1F50A}'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _setBgmVolume(int value) async {
    setState(() => _bgmVolume = AudioSafety.clampBgm(value));
    if (!_bgmPlayer.playing) return; // the next fade-in uses the new level
    // Glide to the new level rather than jumping (NFR5).
    await _bgmFader.rampTo(_bgmVolume / 100.0,
        duration: const Duration(milliseconds: 250));
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
     unmarked books - the player guesses from word counts when it's missing. */
  final int? audioStartMs;
  /* Interactive books only (see AudiobookPage). [number] is the book's page
     number - split versions share one. [sourceIndex] is this page's index
     in _allPages, set on pages in the current path. */
  final int? number;
  final List<String> choices;
  final bool isSplit;
  final int? branchIndex;
  final int? sourceIndex;

  const _PlayerPage({
    required this.text,
    this.imageUrl,
    this.audioStartMs,
    this.number,
    this.choices = const [],
    this.isSplit = false,
    this.branchIndex,
    this.sourceIndex,
  });

  bool get isInteraction => choices.isNotEmpty;

  _PlayerPage forPath({required String text, required int sourceIndex}) =>
      _PlayerPage(
        text: text,
        imageUrl: imageUrl,
        audioStartMs: audioStartMs,
        number: number,
        choices: choices,
        isSplit: isSplit,
        branchIndex: branchIndex,
        sourceIndex: sourceIndex,
      );
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
                  context
                      .tr('player.page_of')
                      .replaceAll('{current}', '$pageNumber')
                      .replaceAll('{total}', '$totalPages'),
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

/* The answers for an interactive question page. Pops in under the page;
   the story waits until one is tapped. [selected] marks the answer already
   picked when the child comes Back to this page. */
class _ChoicePanel extends StatelessWidget {
  final List<String> choices;
  final int? selected;
  final ValueChanged<int> onPick;

  const _ChoicePanel({
    super.key,
    required this.choices,
    required this.selected,
    required this.onPick,
  });

  // Soft tints so each answer looks different but still calm.
  static const _tints = [
    AppColors.softMint,
    AppColors.softPeach,
    AppColors.softLavender,
    AppColors.softYellow,
  ];

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      ),
      child: SoftCard(
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('player.choose_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('player.choose_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _choiceButton(i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choiceButton(int i) {
    final isSelected = selected == i;
    final tint = _tints[i % _tints.length];
    final fg = isSelected ? Colors.white : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPick(i),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryBlueDark : tint,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryBlueDark
                  : AppColors.cardBorder,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isSelected) ...[
                const Icon(Icons.check_rounded, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  choices[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
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
                // Decode smaller - the AI images are 1024x1024 and decoding
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
     sits about a third from the top - room above to look back, room below
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
    // Already close enough - skip the animation so rapid ticks don't jitter
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

/* Small banner shown in caregiver preview - reminds them that voice/speed/
   text-size changes only affect this preview. */
// One word and an eye: this is a preview, nothing is recorded.
class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.softLavender,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_rounded, size: 22, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Text(
            context.tr('player.preview_short'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

/* One control: a coloured row with a picture of what it changes (voice,
   speed, text, music) on the left and its two big buttons on the right.
   [label] names it for screen readers only. */
class _ControlRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color accent;
  final String label;
  final List<Widget> children;

  const _ControlRow({
    required this.icon,
    required this.color,
    required this.accent,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.45), width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 8),
            for (final child in children) ...[
              const SizedBox(width: 8),
              Expanded(child: child),
            ],
          ],
        ),
      ),
    );
  }
}

/* A big white button showing a picture (an emoji or a sized "A"). The
   chosen voice gets a thick coloured border and a tick. Null [onTap]
   fades it (at the slowest speed or smallest text). */
class _ControlButton extends StatelessWidget {
  final Widget child;
  final String label;
  final Color accent;
  final VoidCallback? onTap;
  final bool selected;

  const _ControlButton({
    required this.child,
    required this.label,
    required this.accent,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? accent : Colors.transparent,
                    width: 3.5,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(child: ExcludeSemantics(child: child)),
                    if (selected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Emoji extends StatelessWidget {
  final String emoji;
  const _Emoji(this.emoji);

  @override
  Widget build(BuildContext context) =>
      Text(emoji, style: const TextStyle(fontSize: 32, height: 1.1));
}

// A small or a big letter A, for smaller / bigger text.
class _SizeA extends StatelessWidget {
  final bool small;
  const _SizeA({required this.small});

  @override
  Widget build(BuildContext context) {
    return Text(
      'A',
      style: TextStyle(
        fontSize: small ? 18 : 34,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
        height: 1,
      ),
    );
  }
}
