import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_lame/flutter_lame.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/piano_synth.dart';

enum StorageAccess { granted, denied, permanentlyDenied }

/* Saves piano recordings as MP3 files in the phone's Downloads folder.

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

  /* Encodes the recording to MP3 and writes it. Returns the saved file.
     Falls back to the app's own folder if Downloads can't be written. */
  static Future<File> saveMp3(Int16List pcm) async {
    final bytes = await _encodeMp3(pcm);
    final name = 'piano_${_timestamp()}.mp3';

    if (Platform.isAndroid) {
      try {
        final dir = Directory(_publicDownloads);
        await dir.create(recursive: true);
        return await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // Fall through to the app folder below.
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/$name').writeAsBytes(bytes, flush: true);
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
