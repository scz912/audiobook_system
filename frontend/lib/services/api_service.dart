import '../i18n/api_messages.dart';

class ApiResponse {
  final bool success;
  final String message;
  final dynamic data;
  final String? error;

  const ApiResponse({
    required this.success,
    required this.message,
    this.data,
    this.error,
  });

  factory ApiResponse.fromBackend(Map<String, dynamic> json, {dynamic data}) {
    final status = (json['status']?.toString() ?? '').toUpperCase();
    return ApiResponse(
      success: status == 'SUCCESS',
      message: localizeApiMessage(json['message']?.toString() ?? ''),
      data: data ?? json['data'],
      error: json['error_code']?.toString(),
    );
  }

  factory ApiResponse.failure(String message, {String error = 'CLIENT_ERROR'}) =>
      ApiResponse(success: false, message: localizeApiMessage(message), error: error);
}
