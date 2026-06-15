// Safe JSON readers used by every model's fromJson.
// The backend may send numbers as strings, booleans as 0/1, etc.

bool safeBool(dynamic value, [bool defaultValue = false]) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is int) return value == 1;
  if (value is String) {
    final lower = value.toLowerCase();
    return lower == '1' || lower == 'true';
  }
  return defaultValue;
}

int? safeInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? safeDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String safeString(dynamic value, [String defaultValue = '']) {
  if (value == null) return defaultValue;
  if (value is String) return value;
  return value.toString();
}

String? safeNullableString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return value.toString();
}

DateTime? safeDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
