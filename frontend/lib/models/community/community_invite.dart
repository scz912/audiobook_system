import '../_json_helpers.dart';

// An invite code the caregiver created to bring another family into the hub.
class CommunityInvite {
  final String inviteId;
  final String code;
  final String? email;
  final String status; // pending | accepted | revoked
  final DateTime? createdAt;

  const CommunityInvite({
    required this.inviteId,
    required this.code,
    this.email,
    required this.status,
    this.createdAt,
  });

  factory CommunityInvite.fromJson(Map<String, dynamic> json) {
    return CommunityInvite(
      inviteId: safeString(json['invite_id']),
      code: safeString(json['code']),
      email: safeNullableString(json['email']),
      status: safeString(json['status'], 'pending'),
      createdAt: safeDate(json['created_at']),
    );
  }
}
