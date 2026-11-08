import '../_json_helpers.dart';
import 'member.dart';

/* A chat's background: the default, a solid colour (#RRGGBB), one of the
   app's gradients (by name), or an uploaded picture (its URL). */
class ChatBackground {
  final String type; // none | color | gradient | image
  final String? value;

  const ChatBackground({this.type = 'none', this.value});
  const ChatBackground.none() : this();
  const ChatBackground.color(String hex) : this(type: 'color', value: hex);
  const ChatBackground.gradient(String name) : this(type: 'gradient', value: name);
  const ChatBackground.image(String url) : this(type: 'image', value: url);

  bool get isNone => type == 'none' || value == null || value!.isEmpty;

  factory ChatBackground.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return const ChatBackground.none();
    return ChatBackground(
      type: safeString(json['type'], 'none'),
      value: safeNullableString(json['value']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatBackground &&
      (isNone && other.isNone || (other.type == type && other.value == value));

  @override
  int get hashCode => isNone ? 0 : Object.hash(type, value);
}

// My settings for another member.
class ContactSettings {
  final String contactId;
  final bool isFavorite;
  final bool isBlocked;
  final bool isMuted;
  final ChatBackground background;

  const ContactSettings({
    required this.contactId,
    this.isFavorite = false,
    this.isBlocked = false,
    this.isMuted = false,
    this.background = const ChatBackground.none(),
  });

  static ContactSettings? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return ContactSettings(
      contactId: safeString(json['contact_id']),
      isFavorite: safeBool(json['is_favorite']),
      isBlocked: safeBool(json['is_blocked']),
      isMuted: safeBool(json['is_muted']),
      background: ChatBackground.fromJson(json['background']),
    );
  }

  ContactSettings copyWith({
    bool? isFavorite,
    bool? isBlocked,
    bool? isMuted,
    ChatBackground? background,
  }) =>
      ContactSettings(
        contactId: contactId,
        isFavorite: isFavorite ?? this.isFavorite,
        isBlocked: isBlocked ?? this.isBlocked,
        isMuted: isMuted ?? this.isMuted,
        background: background ?? this.background,
      );
}

// A person in Settings > Favorite / Blocked contacts.
class ContactEntry {
  final Member member;
  final ContactSettings settings;
  const ContactEntry({required this.member, required this.settings});

  factory ContactEntry.fromJson(Map<String, dynamic> json) {
    final member = Member.fromJson(json);
    return ContactEntry(
      member: member,
      settings: ContactSettings.fromJson(json['settings']) ??
          ContactSettings(contactId: member.caregiverId),
    );
  }
}
