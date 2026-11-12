import '_json_helpers.dart';

class MusicTrack {
  final String trackId;
  final String title;
  final String? composer;
  final String fileUrl;
  // Emotion tags (Calm, Happy...).
  final List<String> tags;
  // One word (Classical, Nature, Pop, Jazz...), set by the AI; null if unknown.
  final String? genre;
  final String? tempo;
  // Measured from the audio: beats per minute, null when there's no pulse
  // to follow...
  final int? bpm;
  // ...and how steady the pulse is: 'steady', 'loose' or 'none'.
  final String? beat;
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
    this.genre,
    this.tempo,
    this.bpm,
    this.beat,
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
      genre:       safeNullableString(json['genre']),
      tempo:       safeNullableString(json['tempo']),
      bpm:         safeInt(json['bpm']),
      beat:        safeNullableString(json['beat']),
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
