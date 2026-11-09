import '_json_helpers.dart';

class Caregiver {
  final String caregiverId;
  final String name;
  final String? email;
  final String? mobileNumber;
  /* 'caregiver' (a parent with child profiles and Child Mode) or
     'independent' (a teenager using one combined app on their own). */
  final String accountType;

  const Caregiver({
    required this.caregiverId,
    required this.name,
    this.email,
    this.mobileNumber,
    this.accountType = 'caregiver',
  });

  bool get isIndependent => accountType == 'independent';

  factory Caregiver.fromJson(Map<String, dynamic> json) {
    return Caregiver(
      caregiverId: safeString(json['caregiver_id']),
      name: safeString(json['name']),
      email: safeNullableString(json['email']),
      mobileNumber: safeNullableString(json['mobile_number']),
      accountType: safeString(json['account_type'], 'caregiver'),
    );
  }

  Map<String, dynamic> toJson() => {
        'caregiver_id': caregiverId,
        'name': name,
        'email': email,
        'mobile_number': mobileNumber,
        'account_type': accountType,
      };
}
