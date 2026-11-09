import '../_json_helpers.dart';

// An audiobook someone shared in a chat message or hub post.
class SharedBook {
  final String audiobookId;
  final String title;
  final String? coverImage;
  final String bookFormat; // 'linear' or 'interactive'
  // I made it or already saved a copy, so there's nothing to save.
  final bool inMyLibrary;

  const SharedBook({
    required this.audiobookId,
    required this.title,
    this.coverImage,
    this.bookFormat = 'linear',
    this.inMyLibrary = false,
  });

  bool get isInteractive => bookFormat == 'interactive';

  static SharedBook? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final id = safeNullableString(json['audiobook_id']);
    if (id == null || id.isEmpty) return null;
    return SharedBook(
      audiobookId: id,
      title: safeString(json['title'], 'Story'),
      coverImage: safeNullableString(json['cover_image']),
      bookFormat: safeString(json['book_format'], 'linear'),
      inMyLibrary: safeBool(json['in_my_library']),
    );
  }

  SharedBook copyWith({bool? inMyLibrary}) => SharedBook(
        audiobookId: audiobookId,
        title: title,
        coverImage: coverImage,
        bookFormat: bookFormat,
        inMyLibrary: inMyLibrary ?? this.inMyLibrary,
      );
}
