import '_json_helpers.dart';
import 'music_track.dart';

class ContentItem {
  final String? audiobookId;
  final String title;
  final String? author;
  final String? description;
  final String? topic;
  final String? category;
  final String? difficulty;
  final String? type;
  final String? contentText;
  final String? coverImage;
  final String? audioFile;
  final String? videoFile;
  final int? durationMinutes;
  final String? ageGroup;
  final String? tags;
  final bool isGenerated;
  final bool isUserUploaded;
  final String? status;
  final String? language; // 'en' or 'ms'
  final DateTime? createdAt;
  final String? trackId;
  final int bgmVolume; // 0-100
  final MusicTrack? musicTrack;

  ContentItem({
    this.audiobookId,
    required this.title,
    this.author,
    this.description,
    this.topic,
    this.category,
    this.difficulty,
    this.type,
    this.contentText,
    this.coverImage,
    this.audioFile,
    this.videoFile,
    this.durationMinutes,
    this.ageGroup,
    this.tags,
    this.isGenerated = false,
    this.isUserUploaded = false,
    this.status,
    this.language,
    this.createdAt,
    this.trackId,
    this.bgmVolume = 30,
    this.musicTrack,
  });

  factory ContentItem.fromJson(Map<String, dynamic> json) {
    final rawTrack = json['music_track'];
    return ContentItem(
      audiobookId: safeNullableString(json['audiobook_id']),
      title: safeString(json['title'], 'Untitled'),
      author: safeNullableString(json['author']),
      description: safeNullableString(json['description']),
      topic: safeNullableString(json['topic']),
      category: safeNullableString(json['category']),
      difficulty: safeNullableString(json['difficulty']),
      type: safeNullableString(json['type']),
      contentText: safeNullableString(json['content_text']),
      coverImage: safeNullableString(json['cover_image']),
      audioFile: safeNullableString(json['audio_file']),
      videoFile: safeNullableString(json['video_file']),
      durationMinutes: safeInt(json['duration_minutes']),
      ageGroup: safeNullableString(json['age_group']),
      tags: safeNullableString(json['tags']),
      isGenerated: safeBool(json['is_generated']),
      isUserUploaded: safeBool(json['is_user_uploaded']),
      status: safeNullableString(json['status']),
      language: safeNullableString(json['language']),
      createdAt: safeDate(json['created_at']),
      trackId: safeNullableString(json['track_id']),
      bgmVolume: safeInt(json['bgm_volume']) ?? 30,
      musicTrack: rawTrack is Map<String, dynamic>
          ? MusicTrack.fromJson(rawTrack)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'audiobook_id': audiobookId,
        'title': title,
        'author': author,
        'description': description,
        'topic': topic,
        'category': category,
        'difficulty': difficulty,
        'type': type,
        'content_text': contentText,
        'cover_image': coverImage,
        'audio_file': audioFile,
        'video_file': videoFile,
        'duration_minutes': durationMinutes,
        'age_group': ageGroup,
        'tags': tags,
        'is_generated': isGenerated,
        'is_user_uploaded': isUserUploaded,
        'status': status,
        'language': language,
        'created_at': createdAt?.toIso8601String(),
      };
}
