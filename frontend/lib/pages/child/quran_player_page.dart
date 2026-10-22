import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../i18n/i18n.dart';
import '../../models/quran.dart';
import '../../services/quran_pack_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/back_pill.dart';
import '../../widgets/player_controls.dart';
import '../../widgets/quran_element_thumb.dart';
import '../../widgets/soft_card.dart';

/* Plays one downloaded chapter of the Al-Quran pack like an audiobook: one
   page per verse, over the chapter's nature GIF. The verses play back to
   back from the device (no internet needed) and the page turns with the
   recitation. Swiping to a verse jumps the recitation there. */
class QuranPlayerPage extends StatefulWidget {
  final QuranChapter chapter;
  const QuranPlayerPage({super.key, required this.chapter});

  @override
  State<QuranPlayerPage> createState() => _QuranPlayerPageState();
}

class _QuranPlayerPageState extends State<QuranPlayerPage> {
  final QuranPackService _pack = QuranPackService.instance;
  final AudioPlayer _player = AudioPlayer();
  final PageController _pageController = PageController();
  final List<StreamSubscription<dynamic>> _subs = [];

  QuranChapterContent? _content;
  bool _loading = true;
  String? _error;
  int _page = 0;
  bool _playing = false;
  bool _repeatVerse = false;
  // 1 when a Bismillah clip plays before verse 1, so playlist index i is
  // verse (i - 1).
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final content = await _pack.loadChapter(widget.chapter.number);
      final n = widget.chapter.number;
      final sources = <AudioSource>[
        if (content.bismillahAudio != null)
          AudioSource.file(_pack.audioPath(n, content.bismillahAudio!)),
        for (final v in content.verses)
          AudioSource.file(_pack.audioPath(n, v.audioFile)),
      ];
      _offset = content.bismillahAudio != null ? 1 : 0;

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await _player.setAudioSource(ConcatenatingAudioSource(children: sources));

      _subs.add(_player.currentIndexStream.listen(_onTrackChanged));
      _subs.add(_player.playerStateStream.listen((s) {
        final playing =
            s.playing && s.processingState != ProcessingState.completed;
        if (playing != _playing && mounted) {
          setState(() => _playing = playing);
        }
      }));

      if (!mounted) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Quran player: could not open chapter: $e');
      if (!mounted) return;
      setState(() {
        _error = context.trRead('quran.load_error');
        _loading = false;
      });
    }
  }

  int _verseForTrack(int track) => math.max(0, track - _offset);

  // Verse 1 starts at the Bismillah clip when there is one.
  int _trackForVerse(int verse) => verse == 0 ? 0 : verse + _offset;

  // The recitation moved on to the next clip: turn the page with it.
  void _onTrackChanged(int? track) {
    if (track == null || !_pageController.hasClients) return;
    final verse = _verseForTrack(track);
    if (verse == _page) return;
    if ((verse - _page).abs() == 1) {
      _pageController.animateToPage(verse,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic);
    } else {
      _pageController.jumpToPage(verse);
    }
  }

  // The page changed. If the caregiver swiped (not the recitation moving
  // on), jump the recitation to that verse.
  void _onPageChanged(int verse) {
    setState(() => _page = verse);
    final track = _player.currentIndex;
    if (track != null && _verseForTrack(track) == verse) return;
    _player.seek(Duration.zero, index: _trackForVerse(verse));
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    // Finished the chapter: start again from the top.
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: 0);
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
    unawaited(_player.play());
  }

  void _goTo(int verse) {
    final total = _content?.verses.length ?? 0;
    if (verse < 0 || verse >= total || !_pageController.hasClients) return;
    _pageController.animateToPage(verse,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic);
  }

  Future<void> _setRepeat(bool value) async {
    setState(() => _repeatVerse = value);
    await _player.setLoopMode(value ? LoopMode.one : LoopMode.off);
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
            else if (_error != null)
              SoftCard(
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger)),
              )
            else ...[
              _buildVerseCard(),
              const SizedBox(height: 14),
              _buildVerseIndicator(),
              const SizedBox(height: 18),
              _buildControlBar(),
              const SizedBox(height: 16),
              _buildOptions(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final c = widget.chapter;
    return Row(
      children: [
        BackPill(onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              Text(
                '${c.number}. ${c.nameEn}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              Text(
                '${c.nameAr} • ${c.meaningEn}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 52),
      ],
    );
  }

  Widget _buildVerseCard() {
    final verses = _content!.verses;
    final gif = _pack.gifFor(widget.chapter.elementId);
    final visual = quranElementVisual(widget.chapter.elementId);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.softMint, AppColors.softLavender],
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 460,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The nature scene stays put while the verses slide over it.
              if (gif != null)
                Image.file(gif, fit: BoxFit.cover, gaplessPlayback: true)
              else
                Container(
                  color: visual.color,
                  child: Icon(visual.icon,
                      size: 120, color: Colors.white.withValues(alpha: 0.6)),
                ),
              // Darken towards the text so it stays readable on any scene.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x33000000), Color(0xB3000000)],
                  ),
                ),
              ),
              PageView.builder(
                controller: _pageController,
                itemCount: verses.length,
                onPageChanged: _onPageChanged,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, i) => _VersePage(verse: verses[i]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerseIndicator() {
    final total = _content!.verses.length;
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
              .tr('quran.player_verse')
              .replaceAll('{n}', '${_page + 1}')
              .replaceAll('{total}', '$total'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    final total = _content!.verses.length;
    return Row(
      children: [
        RoundIconButton(
          icon: Icons.chevron_left_rounded,
          label: context.tr('common.back'),
          color: AppColors.softLavender,
          enabled: _page > 0,
          onTap: () => _goTo(_page - 1),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BigPlayButton(playing: _playing, onTap: _togglePlay),
        ),
        const SizedBox(width: 12),
        RoundIconButton(
          icon: Icons.chevron_right_rounded,
          label: context.tr('common.next'),
          color: AppColors.softMint,
          enabled: _page < total - 1,
          onTap: () => _goTo(_page + 1),
        ),
      ],
    );
  }

  Widget _buildOptions() {
    final reciter = _pack.manifest?.reciter ?? '';
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _repeatVerse,
            onChanged: _setRepeat,
            title: Text(context.tr('quran.repeat_verse'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('quran.recited_by').replaceAll('{reciter}', reciter),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _VersePage extends StatelessWidget {
  final QuranVerse verse;
  const _VersePage({required this.verse});

  @override
  Widget build(BuildContext context) {
    // Long verses (e.g. 2:282) don't fit at full size, so let them scroll.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 404),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
                border: Border.all(color: Colors.white70),
              ),
              alignment: Alignment.center,
              child: Text('${verse.number}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 18),
            Text(
              verse.arabic,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiriQuran(
                fontSize: 26,
                height: 2.0,
                color: Colors.white,
                shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
