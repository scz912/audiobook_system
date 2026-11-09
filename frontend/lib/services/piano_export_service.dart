import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_lame/flutter_lame.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/piano_synth.dart';

enum StorageAccess { granted, denied, permanentlyDenied }

/* Saves piano recordings as MP3 files in the phone's Downloads folder (on
   iPhone, the app's folder in the Files app).

   Android 10 and older need the storage permission for that, so it is
   requested from the system. Android 11+ lets apps add files to Downloads
   without one, so there the user's in-app "Allow" (asked once by the
   piano page) is all that's needed. */
class PianoExportService {
  PianoExportService._();

  static const _consentKey = 'piano.save_consent';
  static const _publicDownloads = '/storage/emulated/0/Download';

  // Whether the user already said yes to saving into Downloads.
  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  static Future<void> giveConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, true);
  }

  // Asks the system for storage access, on the Android versions that have it.
  static Future<StorageAccess> requestStorageAccess() async {
    if (!Platform.isAndroid) return StorageAccess.granted;
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk >= 30) return StorageAccess.granted;

    final status = await Permission.storage.request();
    if (status.isGranted || status.isLimited) return StorageAccess.granted;
    if (status.isPermanentlyDenied) return StorageAccess.permanentlyDenied;
    return StorageAccess.denied;
  }

  static Future<void> openSettings() => openAppSettings();

  /* iPhones have no Downloads folder: recordings go to the app's own
     folder, which Info.plist makes visible in the Files app. */
  static bool get savesToFilesApp => Platform.isIOS;

  /* Encodes the recording to MP3 and writes it. Returns the saved file.
     [name] is what the child called it; empty or null gives a dated name.
     Falls back to the app's own folder if Downloads can't be written. */
  static Future<File> saveMp3(Int16List pcm, {String? name}) async {
    final bytes = await _encodeMp3(pcm);
    final base = _fileName(name);

    if (Platform.isAndroid) {
      try {
        final dir = Directory(_publicDownloads);
        await dir.create(recursive: true);
        return await _freeFile(dir, base).writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // Fall through to the app folder below.
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    return _freeFile(docs, base).writeAsBytes(bytes, flush: true);
  }

  // A safe file name from what was typed (no slashes and the like).
  static String _fileName(String? name) {
    final cleaned = (name ?? '')
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'piano_${_timestamp()}' : cleaned;
  }

  // "My song.mp3", or "My song (2).mp3" if that's taken, so nothing is overwritten.
  static File _freeFile(Directory dir, String base) {
    var file = File('${dir.path}/$base.mp3');
    for (var n = 2; file.existsSync(); n++) {
      file = File('${dir.path}/$base ($n).mp3');
    }
    return file;
  }

  static Future<Uint8List> _encodeMp3(Int16List pcm) async {
    final encoder = LameMp3Encoder(
      numChannels: 1,
      sampleRate: PianoSynth.sampleRate,
      bitRate: 128,
    );
    final out = BytesBuilder(copy: false);
    try {
      // A few seconds per call keeps each native buffer small.
      const chunk = PianoSynth.sampleRate * 5;
      for (var i = 0; i < pcm.length; i += chunk) {
        final end = i + chunk < pcm.length ? i + chunk : pcm.length;
        out.add(await encoder.encode(
          leftChannel: pcm.sublist(i, end),
        ));
      }
      out.add(await encoder.flush());
    } finally {
      await encoder.close();
    }
    return out.takeBytes();
  }

  static String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
