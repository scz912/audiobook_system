import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/ai_suggestion.dart';
import '../models/audiobook.dart';
import '../models/caregiver.dart';
import '../models/child_profile.dart';
import '../models/content_item.dart';
import '../models/content_summary.dart';
import '../models/music_track.dart';
import '../models/insights_overview.dart';
import '../models/user_settings.dart';
import 'api_service.dart';

class DatabaseService {
  DatabaseService._();

  static const String baseUrl = AppConfig.databaseApiUrl;
  static const Duration _timeout = Duration(seconds: 30);

  // Keys used in SharedPreferences.
  static const String kSessionToken = 'session_token';
  static const String kSessionExpires = 'session_expires';
  static const String kCaregiverId = 'caregiver_id';
  static const String kCaregiverName = 'caregiver_name';
  static const String kCaregiverEmail = 'caregiver_email';
  static const String kCaregiverMobile = 'caregiver_mobile';

  // shared helpers

  static Future<bool> _hasNetworkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Map<String, String> _headers({String? sessionToken}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (sessionToken != null && sessionToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $sessionToken';
    }
    return headers;
  }

  static Future<String?> _currentToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kSessionToken);
  }

  static Future<ApiResponse> _post(
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
    Duration? timeout,
  }) async {
    if (!await _hasNetworkConnection()) {
      return ApiResponse.failure(
        'No internet connection. Please check your network settings.',
        error: 'NO_CONNECTIVITY',
      );
    }

    try {
      final token = requireAuth ? await _currentToken() : null;
      if (requireAuth && (token == null || token.isEmpty)) {
        return ApiResponse.failure('Not signed in', error: 'NO_SESSION');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers(sessionToken: token),
            body: jsonEncode(body ?? {}),
          )
          .timeout(timeout ?? _timeout);

      if (response.body.isEmpty) {
        return ApiResponse.failure('Empty response', error: 'EMPTY_BODY');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResponse.failure('Unexpected response shape', error: 'BAD_SHAPE');
      }
      return ApiResponse.fromBackend(decoded);
    } on TimeoutException {
      return ApiResponse.failure('Request timed out', error: 'TIMEOUT');
    } on SocketException {
      return ApiResponse.failure('Network error', error: 'NETWORK_ERROR');
    } catch (e) {
      return ApiResponse.failure('Network error: $e', error: 'UNKNOWN');
    }
  }

  // auth

  static Future<ApiResponse> register({
    required String name,
    required String pin,
    String? email,
    String? mobileNumber,
    String? deviceId,
    String? deviceName,
  }) async {
    final resp = await _post('/auth/register', requireAuth: false, body: {
      'name': name,
      'pin': pin,
      if (email != null && email.isNotEmpty) 'email': email,
      if (mobileNumber != null && mobileNumber.isNotEmpty)
        'mobile_number': mobileNumber,
      'device_id': ?deviceId,
      'device_name': ?deviceName,
    });
    if (resp.success) await _persistSession(resp);
    return resp;
  }

  static Future<ApiResponse> loginWithPin({
    required String pin,
    String? email,
    String? mobileNumber,
    String? deviceId,
    String? deviceName,
    String? fcmToken,
  }) async {
    final resp = await _post('/auth/login', requireAuth: false, body: {
      'pin': pin,
      if (email != null && email.isNotEmpty) 'email': email,
      if (mobileNumber != null && mobileNumber.isNotEmpty)
        'mobile_number': mobileNumber,
      'device_id': ?deviceId,
      'device_name': ?deviceName,
      'fcm_token': ?fcmToken,
    });
    if (resp.success) await _persistSession(resp);
    return resp;
  }

  static Future<ApiResponse> logout() async {
    final resp = await _post('/auth/logout');
    await _clearSession();
    return resp;
  }

  static Future<Caregiver?> me() async {
    final resp = await _post('/auth/me');
    if (resp.success && resp.data is Map<String, dynamic>) {
      return Caregiver.fromJson(resp.data as Map<String, dynamic>);
    }
    return null;
  }

  static Future<void> _persistSession(ApiResponse resp) async {
    if (resp.data is! Map<String, dynamic>) return;
    final data = resp.data as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    if (data['session_token'] != null) {
      await prefs.setString(kSessionToken, data['session_token'].toString());
    }
    if (data['session_expires'] != null) {
      await prefs.setString(kSessionExpires, data['session_expires'].toString());
    }
    final caregiver = data['caregiver'];
    if (caregiver is Map<String, dynamic>) {
      await prefs.setString(kCaregiverId, caregiver['caregiver_id']?.toString() ?? '');
      await prefs.setString(kCaregiverName, caregiver['name']?.toString() ?? '');
      if (caregiver['email'] != null) {
        await prefs.setString(kCaregiverEmail, caregiver['email'].toString());
      }
      if (caregiver['mobile_number'] != null) {
        await prefs.setString(kCaregiverMobile, caregiver['mobile_number'].toString());
      }
    }
  }

  static Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kSessionToken);
    await prefs.remove(kSessionExpires);
    await prefs.remove(kCaregiverId);
    await prefs.remove(kCaregiverName);
    await prefs.remove(kCaregiverEmail);
    await prefs.remove(kCaregiverMobile);
  }

  static Future<bool> isLoggedIn() async {
    final token = await _currentToken();
    return token != null && token.isNotEmpty;
  }

  static Future<bool> verifyCurrentPin(String pin) async {
    final resp = await _post('/auth/verify-pin', body: {'pin': pin});
    return resp.success;
  }

  // settings

  static Future<ApiResponse> getSettings() async {
    final resp = await _post('/settings/');
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse.fromBackend(
        {
          'status': 'SUCCESS',
          'message': resp.message,
        },
        data: UserSettings.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  static Future<ApiResponse> updateSettings(UserSettings settings) async {
    final resp = await _post('/settings/update', body: settings.toJson());
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse.fromBackend(
        {
          'status': 'SUCCESS',
          'message': resp.message,
        },
        data: UserSettings.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  static Future<ApiResponse> changePin({
    required String currentPin,
    required String newPin,
  }) {
    return _post('/settings/change-pin', body: {
      'current_pin': currentPin,
      'new_pin': newPin,
    });
  }

  // Per-child narration & sensory/playback settings.
  static Future<ApiResponse> getChildSettings(String childId) async {
    final resp = await _post('/child-profiles/$childId/settings');
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: UserSettings.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  static Future<ApiResponse> updateChildSettings(
    String childId,
    UserSettings settings,
  ) async {
    final resp = await _post(
      '/child-profiles/$childId/settings/update',
      body: settings.toJson(),
    );
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: UserSettings.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  // child profiles

  static Future<ApiResponse> listChildProfiles() async {
    final resp = await _post('/child-profiles/');
    if (resp.success && resp.data is List) {
      final profiles = (resp.data as List)
          .whereType<Map<String, dynamic>>()
          .map(ChildProfile.fromJson)
          .toList();
      return ApiResponse(success: true, message: resp.message, data: profiles);
    }
    return resp;
  }

  static Future<ApiResponse> createChildProfile({
    required String name,
    required int age,
    required String avatarEmoji,
    required String avatarColorHex,
    String? favoriteGenre,
  }) async {
    final resp = await _post('/child-profiles/create', body: {
      'name': name,
      'age': age,
      'avatar_emoji': avatarEmoji,
      'avatar_color': avatarColorHex,
      'favorite_genre': ?favoriteGenre,
    });
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: ChildProfile.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  static Future<ApiResponse> updateChildProfile(String childId, Map<String, dynamic> patch) {
    return _post('/child-profiles/$childId/update', body: patch);
  }

  static Future<ApiResponse> deleteChildProfile(String childId) {
    return _post('/child-profiles/$childId/delete');
  }

  // audiobooks

  static Future<ApiResponse> getAudiobookData(String audiobookId) async {
    final resp = await _post('/audiobooks/$audiobookId');
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: Audiobook.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  // content management

  static Future<ApiResponse> getContentSummary() async {
    final resp = await _post('/content/summary');
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: ContentSummary.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  static Future<ApiResponse> getContentList({
    String? filterType,
    String? search,
    String? category,
    String? ageGroup,
    String? language, // 'en' or 'ms' — narrows the library to one language
  }) async {
    final resp = await _post('/content/list', body: {
      'filter_type': ?filterType,
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null && category.isNotEmpty) 'category': category,
      if (ageGroup != null && ageGroup.isNotEmpty) 'age_group': ageGroup,
      if (language != null && language.isNotEmpty) 'language': language,
    });
    if (resp.success && resp.data is Map<String, dynamic>) {
      final items = (resp.data as Map<String, dynamic>)['items'];
      final list = items is List
          ? items
              .whereType<Map<String, dynamic>>()
              .map(ContentItem.fromJson)
              .toList()
          : <ContentItem>[];
      return ApiResponse(success: true, message: resp.message, data: list);
    }
    return resp;
  }

  static Future<ApiResponse> createContent(Map<String, dynamic> payload) {
    return _post('/content/create', body: payload);
  }

  /* Update a book's text fields (title, description, language, etc.).
     Only the keys you pass are sent. */
  static Future<ApiResponse> updateContent(
    String audiobookId,
    Map<String, dynamic> patch,
  ) async {
    final resp = await _post('/content/$audiobookId/update', body: patch);
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: ContentItem.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  /* Delete a book. The database also removes its pages and history. */
  static Future<ApiResponse> deleteContent(String audiobookId) {
    return _post('/content/$audiobookId/delete');
  }

  /* Update a single page on an existing audiobook. [imagePath] is optional
     — when omitted the existing image is left in place; when provided it
     replaces the current image via multipart upload. */
  static Future<ApiResponse> updateAudiobookPage({
    required String audiobookId,
    required String pageId,
    String? text,
    int? pageNumber,
    int? audioStartMs,
    String? imagePath,
  }) async {
    if (!await _hasNetworkConnection()) {
      return ApiResponse.failure(
        'No internet connection. Please check your network settings.',
        error: 'NO_CONNECTIVITY',
      );
    }
    try {
      final token = await _currentToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.failure('Not signed in', error: 'NO_SESSION');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/content/$audiobookId/pages/$pageId/update'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      if (text != null) request.fields['text'] = text;
      if (pageNumber != null) request.fields['page_number'] = '$pageNumber';
      if (audioStartMs != null) {
        request.fields['audio_start_ms'] = '$audioStartMs';
      }
      if (imagePath != null && imagePath.isNotEmpty) {
        request.files
            .add(await http.MultipartFile.fromPath('image', imagePath));
      }

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.body.isEmpty) {
        return ApiResponse.failure('Empty response', error: 'EMPTY_BODY');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResponse.failure('Unexpected response shape',
            error: 'BAD_SHAPE');
      }
      return ApiResponse.fromBackend(decoded);
    } on TimeoutException {
      return ApiResponse.failure('Upload timed out', error: 'TIMEOUT');
    } catch (e) {
      return ApiResponse.failure('Upload failed: $e', error: 'UNKNOWN');
    }
  }

  // Delete a single page from an audiobook.
  static Future<ApiResponse> deleteAudiobookPage({
    required String audiobookId,
    required String pageId,
  }) {
    return _post('/content/$audiobookId/pages/$pageId/delete');
  }

  /* Create an audiobook with an optional cover-image file (multipart).
     Returns the created ContentItem (with its audiobook_id) on success. */
  static Future<ApiResponse> createContentWithCover({
    required String title,
    String? topic,
    String? difficulty,
    String? tags,
    String? type,
    String? contentText,
    String? coverImagePath,
    String? audioFilePath, // optional whole-book narration recording
    String? language, // 'en' or 'ms'
    String? trackId,  // BGM track UUID, or null for none
    int bgmVolume = 30,
  }) async {
    if (!await _hasNetworkConnection()) {
      return ApiResponse.failure(
        'No internet connection. Please check your network settings.',
        error: 'NO_CONNECTIVITY',
      );
    }
    try {
      final token = await _currentToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.failure('Not signed in', error: 'NO_SESSION');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/content/create'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      request.fields['title'] = title;
      request.fields['type'] = type ?? 'Text';
      request.fields['is_user_uploaded'] = '1';
      if (topic != null && topic.isNotEmpty) request.fields['topic'] = topic;
      if (difficulty != null && difficulty.isNotEmpty) {
        request.fields['difficulty'] = difficulty;
      }
      if (tags != null && tags.isNotEmpty) request.fields['tags'] = tags;
      if (contentText != null && contentText.isNotEmpty) {
        request.fields['content_text'] = contentText;
      }
      if (coverImagePath != null && coverImagePath.isNotEmpty) {
        request.files
            .add(await http.MultipartFile.fromPath('cover_image', coverImagePath));
      }
      if (audioFilePath != null && audioFilePath.isNotEmpty) {
        request.files
            .add(await http.MultipartFile.fromPath('audio_file', audioFilePath));
      }
      if (language != null && language.isNotEmpty) {
        request.fields['language'] = language;
      }
      if (trackId != null && trackId.isNotEmpty) {
        request.fields['track_id'] = trackId;
      }
      request.fields['bgm_volume'] = bgmVolume.toString();

      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.body.isEmpty) {
        return ApiResponse.failure('Empty response', error: 'EMPTY_BODY');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResponse.failure('Unexpected response shape', error: 'BAD_SHAPE');
      }
      final resp = ApiResponse.fromBackend(decoded);
      if (resp.success && resp.data is Map<String, dynamic>) {
        return ApiResponse(
          success: true,
          message: resp.message,
          data: ContentItem.fromJson(resp.data as Map<String, dynamic>),
        );
      }
      return resp;
    } on TimeoutException {
      return ApiResponse.failure('Upload timed out', error: 'TIMEOUT');
    } catch (e) {
      return ApiResponse.failure('Upload failed: $e', error: 'UNKNOWN');
    }
  }

  // Add one page (text + optional image file) to an audiobook via multipart.
  static Future<ApiResponse> addAudiobookPage({
    required String audiobookId,
    required int pageNumber,
    String? text,
    String? imagePath,
    /* Offset (ms) of this page in the whole-book audio. Null = unmarked;
       page 1 is implicitly 0 so passing 0 is also fine. */
    int? audioStartMs,
  }) async {
    if (!await _hasNetworkConnection()) {
      return ApiResponse.failure(
        'No internet connection. Please check your network settings.',
        error: 'NO_CONNECTIVITY',
      );
    }
    try {
      final token = await _currentToken();
      if (token == null || token.isEmpty) {
        return ApiResponse.failure('Not signed in', error: 'NO_SESSION');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/content/$audiobookId/pages'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      request.fields['page_number'] = '$pageNumber';
      if (text != null && text.isNotEmpty) request.fields['text'] = text;
      if (imagePath != null && imagePath.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      }
      if (audioStartMs != null && audioStartMs >= 0) {
        request.fields['audio_start_ms'] = '$audioStartMs';
      }

      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      if (response.body.isEmpty) {
        return ApiResponse.failure('Empty response', error: 'EMPTY_BODY');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResponse.failure('Unexpected response shape', error: 'BAD_SHAPE');
      }
      return ApiResponse.fromBackend(decoded);
    } on TimeoutException {
      return ApiResponse.failure('Upload timed out', error: 'TIMEOUT');
    } catch (e) {
      return ApiResponse.failure('Upload failed: $e', error: 'UNKNOWN');
    }
  }

  /* Ask Gemini AI to generate a story (and optionally a cover image) and save
     it as a new audiobook. Returns the created ContentItem on success. */
  static Future<ApiResponse> generateAiContent({
    required String topic,
    String? ageGroup,
    String? category,
    String? difficulty,
    String? tags,
    String? sourceText,
    bool generateImage = true,
    int? pageCount,
    String? language,     // 'en' or 'ms'
    String? trackId,      // null = auto-select; omit key entirely = no BGM
    bool includeBgm = false,
    int bgmVolume = 30,
  }) async {
    final resp = await _post(
      '/content/generate',
      timeout: const Duration(seconds: 180),
      body: {
        'topic': topic,
        if (ageGroup != null && ageGroup.isNotEmpty) 'age_group': ageGroup,
        if (category != null && category.isNotEmpty) 'category': category,
        if (difficulty != null && difficulty.isNotEmpty) 'difficulty': difficulty,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
        if (sourceText != null && sourceText.isNotEmpty) 'source_text': sourceText,
        'generate_image': generateImage,
        'page_count': ?pageCount,
        if (language != null && language.isNotEmpty) 'language': language,
        // BGM: only send track_id key when BGM is enabled (null = auto-select)
        if (includeBgm) 'track_id': trackId,
        if (includeBgm) 'bgm_volume': bgmVolume,
      },
    );
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: ContentItem.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  /* Generate (or reuse) natural-voice narration for a page of text via Gemini
     TTS. Returns the audio URL string in `data` on success. */
  static Future<ApiResponse> getNaturalVoiceUrl({
    required String text,
    String? voice,
  }) async {
    final resp = await _post(
      '/tts/speak',
      timeout: const Duration(seconds: 70),
      body: {
        'text': text,
        if (voice != null && voice.isNotEmpty) 'voice': voice,
      },
    );
    if (resp.success && resp.data is Map<String, dynamic>) {
      final url = (resp.data as Map<String, dynamic>)['audio_url'];
      if (url is String && url.isNotEmpty) {
        return ApiResponse(success: true, message: resp.message, data: url);
      }
      return ApiResponse.failure('No audio was returned', error: 'NO_AUDIO');
    }
    return resp;
  }

  // listening history

  static Future<ApiResponse> recordListeningSession({
    required String childId,
    required String audiobookId,
    int? durationSeconds,
    int? lastPositionSeconds,
    String? mood,
    bool? completed,
    int? pauseCount,
    int? skipCount,
  }) {
    return _post('/listening-history/record', body: {
      'child_id': childId,
      'audiobook_id': audiobookId,
      'duration_seconds': ?durationSeconds,
      'last_position_seconds': ?lastPositionSeconds,
      'mood': ?mood,
      'completed': ?completed,
      'pause_count': ?pauseCount,
      'skip_count': ?skipCount,
    });
  }

  static Future<ApiResponse> listeningHistoryFor(String childId) {
    return _post('/listening-history/child/$childId');
  }

  // insights

  static Future<ApiResponse> getInsightsOverview({String? childId}) async {
    final resp = await _post('/insights/overview', body: {
      if (childId != null && childId.isNotEmpty) 'child_id': childId,
    });
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: InsightsOverview.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  // UC-9: AI listening-behaviour suggestions

  /* Fetch the cached suggestion snapshot for [childId] without triggering a
     new Gemini call. Used by the insights page when it first opens. */
  static Future<ApiResponse> getSuggestions(String childId) async {
    final resp = await _post('/insights/$childId/suggestions');
    return _wrapSuggestionResponse(resp);
  }

  /* Run a fresh listening-behaviour analysis for [childId]. May take a few
     seconds (Gemini text call); on failure the backend re-serves the previous
     cached snapshot with `isStale = true`. */
  static Future<ApiResponse> analyseListening(String childId) async {
    final resp = await _post('/insights/$childId/analyse');
    return _wrapSuggestionResponse(resp);
  }

  /* Accept a single suggestion item, optionally overriding the suggested
     value (UC-9 A2). The backend writes the value straight into the child's
     settings row and marks the suggestion as accepted/edited. */
  static Future<ApiResponse> applySuggestion({
    required String childId,
    required String itemId,
    dynamic overrideValue,
  }) async {
    final resp = await _post('/insights/$childId/suggestions/apply', body: {
      'item_id': itemId,
      'override_value': ?overrideValue,
    });
    return _wrapSuggestionResponse(resp);
  }

  // Mark a suggestion as dismissed without touching child_settings.
  static Future<ApiResponse> dismissSuggestion({
    required String childId,
    required String itemId,
  }) async {
    final resp = await _post('/insights/$childId/suggestions/dismiss', body: {
      'item_id': itemId,
    });
    return _wrapSuggestionResponse(resp);
  }

  static ApiResponse _wrapSuggestionResponse(ApiResponse resp) {
    if (resp.success && resp.data is Map<String, dynamic>) {
      return ApiResponse(
        success: true,
        message: resp.message,
        data: AiSuggestion.fromJson(resp.data as Map<String, dynamic>),
      );
    }
    return resp;
  }

  // music tracks

  /* List active music tracks. [tags] filters to tracks that have ALL listed
     tags. [search] matches against "title-composer" label. */
  static Future<ApiResponse> listMusicTracks({
    List<String>? tags,
    String? search,
  }) async {
    final resp = await _post('/music-tracks/list', body: {
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    if (resp.success && resp.data is Map<String, dynamic>) {
      final raw = (resp.data as Map<String, dynamic>)['tracks'];
      final list = raw is List
          ? raw.whereType<Map<String, dynamic>>().map(MusicTrack.fromJson).toList()
          : <MusicTrack>[];
      return ApiResponse(success: true, message: resp.message, data: list);
    }
    return resp;
  }

  // Return all distinct tags across active tracks (sorted).
  static Future<ApiResponse> getMusicTrackTags() async {
    final resp = await _post('/music-tracks/tags');
    if (resp.success && resp.data is Map<String, dynamic>) {
      final raw = (resp.data as Map<String, dynamic>)['tags'];
      final list = raw is List ? raw.map((t) => t.toString()).toList() : <String>[];
      return ApiResponse(success: true, message: resp.message, data: list);
    }
    return resp;
  }

  // Given already-selected tags, return only tags that still produce results.
  static Future<ApiResponse> getCompatibleMusicTags(List<String> selected) async {
    final resp = await _post('/music-tracks/compatible-tags', body: {
      'selected_tags': selected,
    });
    if (resp.success && resp.data is Map<String, dynamic>) {
      final raw = (resp.data as Map<String, dynamic>)['tags'];
      final list = raw is List ? raw.map((t) => t.toString()).toList() : <String>[];
      return ApiResponse(success: true, message: resp.message, data: list);
    }
    return resp;
  }
}
