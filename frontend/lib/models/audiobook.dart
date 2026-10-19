import '_json_helpers.dart';

class AudiobookPage {
  final String? pageId;
  final int pageNumber;
  final String? text;
  final String? image;
  /* Where this page starts in the recording, in ms. Page 1 is 0; later
     pages are null until the caregiver marks them in the upload screen. */
  final int? audioStartMs;
  /* Interactive books only. A page with [choices] pauses for the child to
     pick one. If [isSplit], the next page number has two versions and
     [branchIndex] (0 or 1) on each says which choice leads to it. Otherwise
     the next page's text holds [choiceToken] for the picked answer. */
  final List<String> choices;
  final bool isSplit;
  final int? branchIndex;

  static const choiceToken = '{choice}';

  const AudiobookPage({
    this.pageId,
    required this.pageNumber,
    this.text,
    this.image,
    this.audioStartMs,
    this.choices = const [],
    this.isSplit = false,
    this.branchIndex,
  });

  bool get isInteraction => choices.isNotEmpty;

  factory AudiobookPage.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'];
    return AudiobookPage(
      pageId: safeNullableString(json['page_id']),
      pageNumber: safeInt(json['page_number']) ?? 1,
      text: safeNullableString(json['text']),
      image: safeNullableString(json['image']),
      audioStartMs: safeInt(json['audio_start_ms']),
      choices: rawChoices is List
          ? rawChoices.map((c) => c.toString()).toList()
          : const [],
      isSplit: safeBool(json['is_split']),
      branchIndex: safeInt(json['branch_index']),
    );
  }
}

class Audiobook {
  final String? audiobookId;
  final String title;
  final String? author;
  final String? description;
  final String? topic;
  final String? category;
  final String? difficulty;
  final String? type;
  final String bookFormat; // 'linear' or 'interactive'
  final String? contentText;
  final String? audioFile;
  final String? videoFile;
  final String? sourceFile;
  final String? coverImage;
  final int? durationMinutes;
  final String? language;
  final String? ageGroup;
  final String? tags;
  final bool isGenerated;
  final bool isUserUploaded;
  final String? status;
  final List<AudiobookPage> pages;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? trackId;         // music track id (null = no music)
  final int bgmVolume;           // 0-100, default 30
  final String? musicTrackFileUrl; // full URL of the music file

  Audiobook({
    this.audiobookId,
    required this.title,
    this.author,
    this.description,
    this.topic,
    this.category,
    this.difficulty,
    this.type,
    this.bookFormat = 'linear',
    this.contentText,
    this.audioFile,
    this.videoFile,
    this.sourceFile,
    this.coverImage,
    this.durationMinutes,
    this.language,
    this.ageGroup,
    this.tags,
    this.isGenerated = false,
    this.isUserUploaded = false,
    this.status,
    this.pages = const [],
    this.createdAt,
    this.updatedAt,
    this.trackId,
    this.bgmVolume = 30,
    this.musicTrackFileUrl,
  });

  bool get isInteractive => bookFormat == 'interactive';

  factory Audiobook.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'];
    final pages = rawPages is List
        ? rawPages
            .whereType<Map<String, dynamic>>()
            .map(AudiobookPage.fromJson)
            .toList()
        : <AudiobookPage>[];
    return Audiobook(
      audiobookId: safeNullableString(json['audiobook_id']),
      title: safeString(json['title'], 'Untitled'),
      author: safeNullableString(json['author']),
      description: safeNullableString(json['description']),
      topic: safeNullableString(json['topic']),
      category: safeNullableString(json['category']),
      difficulty: safeNullableString(json['difficulty']),
      type: safeNullableString(json['type']),
      bookFormat: safeString(json['book_format'], 'linear'),
      contentText: safeNullableString(json['content_text']),
      audioFile: safeNullableString(json['audio_file']),
      videoFile: safeNullableString(json['video_file']),
      sourceFile: safeNullableString(json['source_file']),
      coverImage: safeNullableString(json['cover_image']),
      durationMinutes: safeInt(json['duration_minutes']),
      language: safeNullableString(json['language']),
      ageGroup: safeNullableString(json['age_group']),
      tags: safeNullableString(json['tags']),
      isGenerated: safeBool(json['is_generated']),
      isUserUploaded: safeBool(json['is_user_uploaded']),
      status: safeNullableString(json['status']),
      pages: pages,
      createdAt: safeDate(json['created_at']),
      updatedAt: safeDate(json['updated_at']),
      trackId: safeNullableString(json['track_id']),
      bgmVolume: safeInt(json['bgm_volume']) ?? 30,
      musicTrackFileUrl: json['music_track'] is Map<String, dynamic>
          ? safeNullableString(
              (json['music_track'] as Map<String, dynamic>)['file_url'])
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
        'audio_file': audioFile,
        'source_file': sourceFile,
        'cover_image': coverImage,
        'duration_minutes': durationMinutes,
        'language': language,
        'age_group': ageGroup,
        'tags': tags,
        'is_generated': isGenerated,
        'is_user_uploaded': isUserUploaded,
        'status': status,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}
