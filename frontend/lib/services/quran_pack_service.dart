import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/quran.dart';

enum QuranChapterState {
  notDownloaded,
  queued,
  downloading,
  installing,
  installed,
  failed,
}

/* Downloads, stores and removes the Al-Quran pack (downloadable content).

   Unlike the rest of the app this doesn't talk to our backend: chapter zips
   and element GIFs are GitHub release assets listed in the bundled
   manifest. Each chapter unpacks to <app support>/quran/chapters/NNN/ and
   is "installed" once its verses.json is there.

   Chapters the caregiver removes are remembered, so the optional
   auto-download (AppConfig.quranAutoDownload) never brings them back. */
class QuranPackService extends ChangeNotifier {
  QuranPackService._();
  static final QuranPackService instance = QuranPackService._();

  static const _manifestAsset = 'assets/quran/quran_manifest.json';
  static const _removedKey = 'quran_removed_chapters';
  static const _maxParallel = 2;

  QuranManifest? _manifest;
  Directory? _root;
  Future<void>? _initFuture;

  final Set<int> _installed = {};
  final Set<String> _gifsPresent = {};
  final List<int> _queue = [];
  final Map<int, double> _progress = {}; // active download -> 0..1
  final Set<int> _installing = {};
  final Set<int> _failed = {};
  final Set<int> _cancelled = {};
  // One download per GIF, even when several chapters share an element.
  final Map<String, Future<void>> _gifDownloads = {};
  int _running = 0;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  QuranManifest? get manifest => _manifest;
  bool get isReady => _manifest != null && _root != null;
  bool get isBusy => _queue.isNotEmpty || _running > 0;
  int get installedCount => _installed.length;

  Directory get _chaptersDir => Directory('${_root!.path}/chapters');
  Directory get _elementsDir => Directory('${_root!.path}/elements');
  Directory get _tmpDir => Directory('${_root!.path}/tmp');

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    final raw = await rootBundle.loadString(_manifestAsset);
    _manifest =
        QuranManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final support = await getApplicationSupportDirectory();
    _root = Directory('${support.path}/quran');
    await _chaptersDir.create(recursive: true);
    await _elementsDir.create(recursive: true);
    // Leftovers from a download that was interrupted (app killed).
    if (await _tmpDir.exists()) await _tmpDir.delete(recursive: true);
    await _scanDisk();
    notifyListeners();
  }

  Future<void> _scanDisk() async {
    _installed.clear();
    _gifsPresent.clear();
    for (final c in _manifest!.chapters) {
      if (await File('${_chapterDir(c.number).path}/verses.json').exists()) {
        _installed.add(c.number);
      }
    }
    for (final e in _manifest!.elements) {
      if (await File('${_elementsDir.path}/${e.file}').exists()) {
        _gifsPresent.add(e.file);
      }
    }
  }

  // ---- state queries (used by the list UI) ----

  QuranChapterState stateOf(int chapter) {
    if (_installed.contains(chapter)) return QuranChapterState.installed;
    if (_installing.contains(chapter)) return QuranChapterState.installing;
    if (_progress.containsKey(chapter)) return QuranChapterState.downloading;
    if (_queue.contains(chapter)) return QuranChapterState.queued;
    if (_failed.contains(chapter)) return QuranChapterState.failed;
    return QuranChapterState.notDownloaded;
  }

  double progressOf(int chapter) => _progress[chapter] ?? 0;

  // Space the installed chapters (and their GIFs) take on the device.
  int get installedBytes {
    final m = _manifest;
    if (m == null) return 0;
    var total = 0;
    for (final c in m.chapters) {
      if (_installed.contains(c.number)) total += c.installedBytes;
    }
    for (final e in m.elements) {
      if (_gifsPresent.contains(e.file)) total += e.bytes;
    }
    return total;
  }

  // What "Download all" would still have to fetch.
  int get remainingDownloadBytes {
    final m = _manifest;
    if (m == null) return 0;
    var total = 0;
    final neededGifs = <String>{};
    for (final c in m.chapters) {
      if (_installed.contains(c.number)) continue;
      total += c.downloadBytes;
      final e = m.elementById(c.elementId);
      if (e != null && !_gifsPresent.contains(e.file)) neededGifs.add(e.file);
    }
    for (final e in m.elements) {
      if (neededGifs.contains(e.file)) total += e.bytes;
    }
    return total;
  }

  // Download size of one chapter, including its GIF if we don't have it yet.
  int downloadBytesFor(QuranChapter chapter) {
    final e = _manifest?.elementById(chapter.elementId);
    final gif = (e != null && !_gifsPresent.contains(e.file)) ? e.bytes : 0;
    return chapter.downloadBytes + gif;
  }

  File? gifFor(String elementId) {
    final e = _manifest?.elementById(elementId);
    if (e == null || !_gifsPresent.contains(e.file)) return null;
    return File('${_elementsDir.path}/${e.file}');
  }

  Directory _chapterDir(int chapter) =>
      Directory('${_chaptersDir.path}/${chapter.toString().padLeft(3, '0')}');

  String audioPath(int chapter, String fileName) =>
      '${_chapterDir(chapter).path}/$fileName';

  Future<QuranChapterContent> loadChapter(int chapter) async {
    await init();
    final file = File('${_chapterDir(chapter).path}/verses.json');
    final raw = await file.readAsString();
    return QuranChapterContent.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  // ---- downloading ----

  Future<void> download(int chapter) async {
    await init();
    await _setRemoved([chapter], removed: false);
    _enqueue([chapter]);
  }

  Future<void> downloadAll() async {
    await init();
    final all = _manifest!.chapters.map((c) => c.number).toList();
    await _setRemoved(all, removed: false);
    _enqueue(all);
  }

  /* Debug/test helper: on the emulator we want the whole pack without
     tapping anything. Skips chapters the caregiver removed. */
  Future<void> autoDownloadIfEnabled() async {
    if (!AppConfig.quranAutoDownload) return;
    await init();
    final removed = await _removedChapters();
    _enqueue(_manifest!.chapters
        .map((c) => c.number)
        .where((n) => !removed.contains(n))
        .toList());
  }

  void _enqueue(List<int> chapters) {
    for (final n in chapters) {
      if (stateOf(n) == QuranChapterState.notDownloaded ||
          stateOf(n) == QuranChapterState.failed) {
        _failed.remove(n);
        _queue.add(n);
      }
    }
    notifyListeners();
    _pump();
  }

  void cancel(int chapter) {
    if (_queue.remove(chapter)) {
      notifyListeners();
    } else if (_progress.containsKey(chapter) ||
        _installing.contains(chapter)) {
      _cancelled.add(chapter); // the download loop checks this
    }
  }

  void cancelAll() {
    _queue.clear();
    _cancelled.addAll(_progress.keys);
    notifyListeners();
  }

  void _pump() {
    while (_running < _maxParallel && _queue.isNotEmpty) {
      final n = _queue.removeAt(0);
      _running++;
      _progress[n] = 0;
      _downloadChapter(n).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  Future<void> _downloadChapter(int n) async {
    final m = _manifest!;
    final chapter = m.chapters.firstWhere((c) => c.number == n);
    final part = File('${_tmpDir.path}/${chapter.file}.part');
    try {
      final element = m.elementById(chapter.elementId);
      if (element != null) await _ensureGif(element);

      await _downloadFile(
        m.baseUrl + chapter.file,
        part,
        expectedBytes: chapter.downloadBytes,
        isCancelled: () => _cancelled.contains(n),
        onProgress: (p) {
          _progress[n] = p;
          _notifyThrottled();
        },
      );

      _progress.remove(n);
      _installing.add(n);
      notifyListeners();

      // Unzip off the UI thread, into a staging folder, then swap it in so
      // a half-extracted chapter is never mistaken for an installed one.
      final target = _chapterDir(n);
      final staging = Directory('${target.path}.staging');
      if (await staging.exists()) await staging.delete(recursive: true);
      await _extractInBackground(part.path, staging.path);
      if (!await File('${staging.path}/verses.json').exists()) {
        throw StateError('unzipped chapter $n has no verses.json');
      }
      // Removed while it was unpacking: throw the result away.
      if (_cancelled.contains(n)) {
        await staging.delete(recursive: true);
        throw const _DownloadCancelled();
      }
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      _installed.add(n);
    } on _DownloadCancelled {
      // Nothing to report - the caregiver asked for it.
    } catch (e) {
      // Errors from a chapter being removed mid-download aren't failures.
      if (!_cancelled.contains(n)) _failed.add(n);
      debugPrint('Quran pack: chapter $n failed: $e');
    } finally {
      _progress.remove(n);
      _installing.remove(n);
      _cancelled.remove(n);
      if (await part.exists()) await part.delete();
      notifyListeners();
    }
  }

  /* The GIF is decoration: if it fails the chapter still installs and the
     player falls back to the element's icon. */
  Future<void> _ensureGif(QuranElement element) async {
    if (_gifsPresent.contains(element.file)) return;
    try {
      // Block body on purpose: `=> remove(...)` would return this same
      // future to whenComplete, which then waits on itself forever.
      await (_gifDownloads[element.file] ??=
          _fetchGif(element).whenComplete(() {
        _gifDownloads.remove(element.file);
      }));
    } catch (e) {
      debugPrint('Quran pack: GIF ${element.file} failed: $e');
    }
  }

  Future<void> _fetchGif(QuranElement element) async {
    final dest = File('${_elementsDir.path}/${element.file}');
    final part = File('${_tmpDir.path}/${element.file}.part');
    await _downloadFile(_manifest!.baseUrl + element.file, part,
        expectedBytes: element.bytes);
    await part.rename(dest.path);
    _gifsPresent.add(element.file);
  }

  Future<void> _downloadFile(
    String url,
    File dest, {
    required int expectedBytes,
    bool Function()? isCancelled,
    void Function(double progress)? onProgress,
  }) async {
    await dest.parent.create(recursive: true);
    // Timeouts so a stalled connection fails (and can be retried) instead
    // of sitting at 0% forever - emulator and mobile links can be slow.
    final client = IOClient(
        HttpClient()..connectionTimeout = const Duration(seconds: 30));
    IOSink? sink;
    try {
      // GitHub release links redirect to a CDN; http follows that for GET.
      final resp = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
      }
      final total = resp.contentLength ?? expectedBytes;
      sink = dest.openWrite();
      var received = 0;
      // Fails if no data arrives for a minute.
      await for (final chunk
          in resp.stream.timeout(const Duration(seconds: 60))) {
        if (isCancelled?.call() ?? false) throw const _DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
    } finally {
      await sink?.close();
      client.close();
    }
  }

  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 200) return;
    _lastNotify = now;
    notifyListeners();
  }

  // ---- removing ----

  Future<void> delete(int chapter) async {
    await init();
    cancel(chapter);
    await _setRemoved([chapter], removed: true);
    final dir = _chapterDir(chapter);
    if (await dir.exists()) await dir.delete(recursive: true);
    _installed.remove(chapter);
    _failed.remove(chapter);
    await _deleteUnusedGifs();
    notifyListeners();
  }

  Future<void> deleteAll() async {
    await init();
    cancelAll();
    await _setRemoved(_manifest!.chapters.map((c) => c.number).toList(),
        removed: true);
    for (final dir in [_chaptersDir, _elementsDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    _installed.clear();
    _gifsPresent.clear();
    _failed.clear();
    notifyListeners();
  }

  // A GIF is shared by every chapter with that element; drop it once no
  // installed chapter needs it.
  Future<void> _deleteUnusedGifs() async {
    final m = _manifest!;
    final needed = <String>{};
    for (final c in m.chapters) {
      if (_installed.contains(c.number) || _progress.containsKey(c.number)) {
        final e = m.elementById(c.elementId);
        if (e != null) needed.add(e.file);
      }
    }
    for (final file in _gifsPresent.toList()) {
      if (needed.contains(file)) continue;
      final f = File('${_elementsDir.path}/$file');
      if (await f.exists()) await f.delete();
      _gifsPresent.remove(file);
    }
  }

  Future<Set<int>> _removedChapters() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_removedKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<void> _setRemoved(List<int> chapters, {required bool removed}) async {
    final prefs = await SharedPreferences.getInstance();
    final set = await _removedChapters();
    removed ? set.addAll(chapters) : set.removeAll(chapters);
    await prefs.setStringList(
        _removedKey, set.map((n) => n.toString()).toList());
  }

  static String formatBytes(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) {
      return '${(bytes / 1e9).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    if (bytes >= 1000) return '${(bytes / 1e3).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

/* Unzips on a background isolate so the UI doesn't freeze. Top-level on
   purpose: a closure made inside the service would carry the service
   itself (and its Futures) into the isolate message, which Dart rejects
   as unsendable. Here the closure only holds the two path strings. */
Future<void> _extractInBackground(String zipPath, String outDir) =>
    Isolate.run(() => _extractZip(zipPath, outDir));

void _extractZip(String zipPath, String outDir) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    // The Sync variant: extractArchiveToDisk is async in archive 3.6, and
    // the isolate would exit before it wrote anything.
    extractArchiveToDiskSync(archive, outDir);
  } finally {
    input.closeSync();
  }
}
