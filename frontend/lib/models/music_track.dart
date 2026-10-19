import '_json_helpers.dart';

class MusicTrack {
  final String trackId;
  final String title;
  final String? composer;
  final String fileUrl;
  final List<String> tags;
  final String? tempo;
  final int? durationSecs;
  // True when the caregiver uploaded it (only they can see it).
  final bool isUserUploaded;
  // AI's one-line description of the music, for uploaded tracks.
  final String? aiSummary;
  // AI's sensory caution (e.g. a sudden loud part), or null if none.
  final String? sensoryNotes;

  const MusicTrack({
    required this.trackId,
    required this.title,
    this.composer,
    required this.fileUrl,
    this.tags = const [],
    this.tempo,
    this.durationSecs,
    this.isUserUploaded = false,
    this.aiSummary,
    this.sensoryNotes,
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
      isUserUploaded: safeBool(json['is_user_uploaded']),
      aiSummary:    safeNullableString(json['ai_summary']),
      sensoryNotes: safeNullableString(json['sensory_notes']),
    );
  }

  // Display label used in the picker list and search.
  String get label => composer != null && composer!.isNotEmpty
      ? '$title - $composer'
      : title;
}
