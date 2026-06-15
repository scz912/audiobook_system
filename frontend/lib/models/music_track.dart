import '_json_helpers.dart';

class MusicTrack {
  final String trackId;
  final String title;
  final String? composer;
  final String fileUrl;
  final List<String> tags;
  final String? tempo;
  final int? durationSecs;

  const MusicTrack({
    required this.trackId,
    required this.title,
    this.composer,
    required this.fileUrl,
    this.tags = const [],
    this.tempo,
    this.durationSecs,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags = rawTags is List
        ? rawTags.map((t) => t.toString()).toList()
        : <String>[];
    return MusicTrack(
      trackId:     safeString(json['track_id'], ''),
      title:       safeString(json['title'], 'Unknown'),
      composer:    safeNullableString(json['composer']),
      fileUrl:     safeString(json['file_url'], ''),
      tags:        tags,
      tempo:       safeNullableString(json['tempo']),
      durationSecs: safeInt(json['duration_secs']),
    );
  }

  // Display label used in the picker list and search.
  String get label => composer != null && composer!.isNotEmpty
      ? '$title - $composer'
      : title;
}
