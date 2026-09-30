import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiRequestException implements Exception {
  const ApiRequestException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

enum ApiConnectionState { operational, offline }

class ConnectionEvent {
  const ConnectionEvent({
    required this.state,
    required this.message,
    required this.timestamp,
  });

  final ApiConnectionState state;
  final String message;
  final DateTime timestamp;
}

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.state,
    required this.uptimePercentage,
    required this.lastChangedAt,
    required this.events,
    this.currentError,
  });

  final ApiConnectionState state;
  final double uptimePercentage;
  final DateTime? lastChangedAt;
  final List<ConnectionEvent> events;
  final String? currentError;

  bool get isOperational => state == ApiConnectionState.operational;
}

class ApiService {
  static const String productionApiUrl =
      'https://certitrust-yhzl.onrender.com/api';
  static const String _productionApiUrl = productionApiUrl;

  // Production builds must always target the live Render backend. Local IPs and
  // loopback hosts are explicitly rejected to prevent accidental offline or
  // private-network requests when the app is running over Wi‑Fi, hotspot, or LTE.
  static String get baseUrl {
    const override = String.fromEnvironment('CERTITRUST_API_URL');
    if (override.isNotEmpty) {
      final normalized = normalizeBaseUrl(override);
      return normalized.contains('certitrust-yhzl.onrender.com')
          ? normalized
          : _productionApiUrl;
    }

    return _productionApiUrl;
  }

  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return _productionApiUrl;

    final lower = trimmed.toLowerCase();
    if (lower.contains('localhost') ||
        lower.contains('127.0.0.1') ||
        lower.contains('::1') ||
        lower.contains('192.168.') ||
        lower.contains('10.0.2.2') ||
        lower.contains('172.')) {
      return _productionApiUrl;
    }

    var normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
    final firstApiMatch =
        RegExp(r'https?://[^/\s]+/api').firstMatch(normalized);
    if (firstApiMatch != null) {
      final firstApiUrl = firstApiMatch.group(0)!;
      if (normalized.startsWith(firstApiUrl) &&
          normalized.length > firstApiUrl.length &&
          (normalized.substring(firstApiUrl.length).contains('http://') ||
              normalized.substring(firstApiUrl.length).contains('https://'))) {
        return firstApiUrl;
      }
    }

    if (!normalized.toLowerCase().endsWith('/api')) {
      normalized = '$normalized/api';
    }

    return normalized;
  }

  // Session token storage after successful authentication
  static String? authToken;
  static String? authEmail;
  static String? authRole;
  static String? authUniversity;
  static String? authProfileImageUrl;
  static String? authProfileIcon;
  static final ValueNotifier<ConnectionSnapshot> connectionStatus =
      ValueNotifier(const ConnectionSnapshot(
    state: ApiConnectionState.operational,
    uptimePercentage: 100,
    lastChangedAt: null,
    events: [],
  ));
  static Timer? _healthCheckTimer;

  static bool get isAuthenticated => authToken != null && authToken!.isNotEmpty;
  static bool get isSuperAdmin =>
      authEmail?.toLowerCase() == 'certitrust256@gmail.com';

  static void startConnectionMonitoring() {
    _healthCheckTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => checkConnection(),
    );
    checkConnection();
  }

  static void stopConnectionMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  static Future<bool> checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/user'), headers: _getHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 500) {
        _recordConnectionSuccess();
        return true;
      }
      _recordConnectionFailure(
        'Backend returned HTTP ${response.statusCode}.',
      );
      return false;
    } catch (error) {
      _recordConnectionFailure(_connectionMessage(error));
      return false;
    }
  }

  static String _connectionMessage(Object error) {
    if (error is TimeoutException) return 'The API request timed out.';
    return 'Unable to reach the Laravel API: ${error.toString()}';
  }

  static void _recordConnectionSuccess() {
    final current = connectionStatus.value;
    if (current.isOperational) return;
    final now = DateTime.now();
    final events = [
      ConnectionEvent(
        state: ApiConnectionState.operational,
        message: 'Connection restored. API is responding normally.',
        timestamp: now,
      ),
      ...current.events,
    ].take(20).toList();
    connectionStatus.value = ConnectionSnapshot(
      state: ApiConnectionState.operational,
      uptimePercentage: 100,
      lastChangedAt: now,
      events: events,
    );
  }

  static void _recordConnectionFailure(String message) {
    final current = connectionStatus.value;
    final now = DateTime.now();
    final events = current.isOperational
        ? [
            ConnectionEvent(
              state: ApiConnectionState.offline,
              message: message,
              timestamp: now,
            ),
            ...current.events,
          ]
        : current.events;
    connectionStatus.value = ConnectionSnapshot(
      state: ApiConnectionState.offline,
      uptimePercentage: 0,
      lastChangedAt: current.isOperational ? now : current.lastChangedAt,
      events: events.take(20).toList(),
      currentError: message,
    );
  }

  /// Initialize and load saved token from local storage on app startup
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    authToken = prefs.getString('auth_token');
    authEmail = prefs.getString('auth_email');
    authRole = prefs.getString('auth_role');
    authUniversity = prefs.getString('auth_university');
    authProfileImageUrl = prefs.getString('auth_profile_image_url');
    authProfileIcon = prefs.getString('auth_profile_icon');
  }

  /// Save token locally
  static Future<void> _saveToken(String token) async {
    authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  /// Clear token on logout
  static Future<void> logout() async {
    authToken = null;
    authEmail = null;
    authRole = null;
    authUniversity = null;
    authProfileImageUrl = null;
    authProfileIcon = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_email');
    await prefs.remove('auth_role');
    await prefs.remove('auth_university');
    await prefs.remove('auth_profile_image_url');
    await prefs.remove('auth_profile_icon');
  }

  static Future<void> validateSession() async {
    if (!isAuthenticated) return;
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/user'), headers: _getHeaders);
      if (response.statusCode != 200) {
        _recordConnectionFailure(
            'Session validation failed with HTTP ${response.statusCode}.');
        await logout();
        return;
      }
      _recordConnectionSuccess();
      final user = jsonDecode(response.body) as Map<String, dynamic>;
      authEmail = user['email']?.toString();
      authRole = user['role']?.toString() ?? 'student';
      authUniversity = user['university_code']?.toString();
      authProfileImageUrl = user['profile_image_url']?.toString();
      authProfileIcon = user['profile_icon']?.toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_email', authEmail ?? '');
      await prefs.setString('auth_role', authRole ?? 'student');
      await prefs.setString('auth_university', authUniversity ?? '');
      await prefs.setString(
          'auth_profile_image_url', authProfileImageUrl ?? '');
      await prefs.setString('auth_profile_icon', authProfileIcon ?? '');
    } catch (error) {
      _recordConnectionFailure(_connectionMessage(error));
      // Keep the cached session when the API is temporarily offline.
    }
  }

  static Future<void> updatePresence() async {
    if (!isAuthenticated) return;
    try {
      await http.post(Uri.parse('$baseUrl/user/presence'),
          headers: _jsonHeaders);
    } catch (error) {
      _recordConnectionFailure(_connectionMessage(error));
      // Presence is best effort and must not block app startup.
    }
  }

  /// Helper for standard headers
  static Map<String, String> get _jsonHeaders {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  /// Helper for read-only headers (GET requests)
  static Map<String, String> get _getHeaders {
    final headers = {
      'Accept': 'application/json',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  /// Fetch recent issued certificates for dashboard
  static Future<List<dynamic>> getCertificates() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/certificates'),
        headers: _getHeaders,
      );

      if (response.statusCode == 200) {
        _recordConnectionSuccess();
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['data'] ?? [];
      } else {
        print(
            'Failed to load certificates [${response.statusCode}]: ${response.body}');
        return [];
      }
    } catch (e) {
      _recordConnectionFailure(_connectionMessage(e));
      print('Get certificates error: $e');
      return [];
    }
  }

  /// Fetch a single certificate by its unique hash/code (For verification screen)
  static Future<Map<String, dynamic>?> getCertificateByCode(String code) async {
    try {
      final normalizedCode = code.replaceAll(RegExp(r'\s+'), '').trim();
      final response = await http.get(
        Uri.parse(
            '$baseUrl/certificates/${Uri.encodeComponent(normalizedCode)}'),
        headers: _getHeaders,
      );

      if (response.statusCode == 200) {
        _recordConnectionSuccess();
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['data'] ?? jsonResponse;
      } else {
        return null;
      }
    } catch (e) {
      _recordConnectionFailure(_connectionMessage(e));
      print('Verification error: $e');
      return null;
    }
  }

  /// Authenticate or register a user via Google ID and Access tokens with Laravel backend
  static Future<Map<String, dynamic>?> loginWithGoogle({
    String? idToken,
    required String accessToken,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/google'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              if (idToken != null && idToken.isNotEmpty) 'id_token': idToken,
              if (accessToken.isNotEmpty) 'access_token': accessToken,
            }),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception(
              'Authentication request timed out. Check that Laravel is running and reachable at $baseUrl.',
            ),
          );

      // Attempt to decode JSON response safely
      Map<String, dynamic> jsonResponse = {};
      try {
        jsonResponse = jsonDecode(response.body);
      } catch (_) {
        jsonResponse = {'message': response.body};
      }

      if (response.statusCode == 200) {
        _recordConnectionSuccess();
        String? token;
        if (jsonResponse['token'] != null) {
          token = jsonResponse['token'];
        } else if (jsonResponse['access_token'] != null) {
          token = jsonResponse['access_token'];
        }

        if (token == null || token.isEmpty) {
          throw 'Server returned a successful response without an auth token.';
        }

        await _saveToken(token);
        authEmail = jsonResponse['email']?.toString();
        authRole = jsonResponse['role']?.toString();
        authUniversity = jsonResponse['university_code']?.toString();
        final user = jsonResponse['user'] as Map<String, dynamic>? ?? {};
        authProfileImageUrl = user['profile_image_url']?.toString();
        authProfileIcon = user['profile_icon']?.toString();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_email', authEmail ?? '');
        await prefs.setString('auth_role', authRole ?? 'student');
        await prefs.setString('auth_university', authUniversity ?? '');
        await prefs.setString(
            'auth_profile_image_url', authProfileImageUrl ?? '');
        await prefs.setString('auth_profile_icon', authProfileIcon ?? '');
        return jsonResponse;
      } else {
        throw ApiRequestException(
          response.statusCode,
          jsonResponse['message']?.toString() ?? 'Authentication failed.',
        );
      }
    } catch (e) {
      _recordConnectionFailure(_connectionMessage(e));
      print('Auth error: $e');
      rethrow; // Pass error up to login screen so it can show the exact reason
    }
  }

  /// Verify and map a student ID to a specific user account email via Laravel backend
  static Future<Map<String, dynamic>?> verifyStudentIdMapping({
    required String email,
    required String studentId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-student'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'email': email,
          'student_id': studentId,
        }),
      );

      Map<String, dynamic> jsonResponse = {};
      try {
        jsonResponse = jsonDecode(response.body);
      } catch (_) {
        jsonResponse = {'message': response.body};
      }

      if (response.statusCode == 200) {
        if (jsonResponse['token'] != null) {
          await _saveToken(jsonResponse['token']);
        }
        final profile = jsonResponse['profile'] as Map<String, dynamic>? ?? {};
        authProfileImageUrl = profile['profile_image_url']?.toString();
        authProfileIcon = profile['profile_icon']?.toString();
        return jsonResponse;
      } else {
        throw 'Server error [${response.statusCode}]: ${jsonResponse['message'] ?? response.body}';
      }
    } catch (e) {
      _recordConnectionFailure(_connectionMessage(e));
      print('Verification error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateProfile({
    List<int>? imageBytes,
    String? imageName,
    String? profileIcon,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/user/profile'));
    request.headers.addAll(_getHeaders);
    if (profileIcon != null) request.fields['profile_icon'] = profileIcon;
    if (imageBytes != null && imageName != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'profile_image',
        imageBytes,
        filename: imageName,
      ));
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
    if (response.statusCode != 200) {
      throw ApiRequestException(
        response.statusCode,
        body['message']?.toString() ?? 'Unable to update profile.',
      );
    }
    authProfileImageUrl = body['profile_image_url']?.toString();
    authProfileIcon = body['profile_icon']?.toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_profile_image_url', authProfileImageUrl ?? '');
    await prefs.setString('auth_profile_icon', authProfileIcon ?? '');
    return body;
  }

  static Future<Map<String, dynamic>> createAdminAccount({
    required String email,
    required String universityCode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/users'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'email': email,
        'university_code': universityCode,
      }),
    );

    if (response.statusCode != 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      throw ApiRequestException(
        response.statusCode,
        body['message']?.toString() ?? 'Administrator account creation failed.',
      );
    }

    _recordConnectionSuccess();
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getSubadmins(
      {String? universityCode}) async {
    final query = universityCode == null || universityCode.trim().isEmpty
        ? ''
        : '?university_code=${Uri.encodeQueryComponent(universityCode.trim())}';

    final response = await http.get(
      Uri.parse('$baseUrl/admin/subadmins$query'),
      headers: _getHeaders,
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      throw ApiRequestException(response.statusCode,
          body['message']?.toString() ?? 'Unable to load admin accounts.');
    }

    _recordConnectionSuccess();
    final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
    final items = body['data'];
    if (items is! List) return const [];
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<Map<String, dynamic>> bindSubadminAccount({
    required String email,
    required String universityCode,
    String? name,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/subadmins'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'email': email,
        'university_code': universityCode,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw ApiRequestException(response.statusCode,
          body['message']?.toString() ?? 'Unable to create admin account.');
    }

    _recordConnectionSuccess();
    return body;
  }

  static Future<Map<String, dynamic>> updateSubadminAccount({
    required int id,
    String? email,
    String? name,
    String? universityCode,
  }) async {
    final payload = <String, dynamic>{};
    if (email != null && email.trim().isNotEmpty)
      payload['email'] = email.trim();
    if (name != null)
      payload['name'] = name.trim().isEmpty ? null : name.trim();
    if (universityCode != null && universityCode.trim().isNotEmpty)
      payload['university_code'] = universityCode.trim();

    final response = await http.put(
      Uri.parse('$baseUrl/admin/subadmins/$id'),
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
    if (response.statusCode != 200) {
      throw ApiRequestException(response.statusCode,
          body['message']?.toString() ?? 'Unable to update admin account.');
    }

    _recordConnectionSuccess();
    return body;
  }

  static Future<Map<String, dynamic>> unbindSubadminGoogle(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/subadmins/$id/google'),
      headers: _getHeaders,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
    if (response.statusCode != 200) {
      throw ApiRequestException(response.statusCode,
          body['message']?.toString() ?? 'Unable to remove Google binding.');
    }

    _recordConnectionSuccess();
    return body;
  }

  static Future<Map<String, dynamic>> deleteSubadminAccount(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/subadmins/$id'),
      headers: _getHeaders,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
    if (response.statusCode != 200) {
      throw ApiRequestException(response.statusCode,
          body['message']?.toString() ?? 'Unable to remove admin account.');
    }

    _recordConnectionSuccess();
    return body;
  }

  static Future<Map<String, dynamic>> getSuperAdminOverview() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/overview'),
        headers: _getHeaders,
      );
      if (response.statusCode != 200) {
        throw ApiRequestException(
            response.statusCode, 'Unable to load global admin activity.');
      }
      _recordConnectionSuccess();
      return (jsonDecode(response.body) as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } catch (error) {
      _recordConnectionFailure(_connectionMessage(error));
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getSuperAdminActionHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/history'),
        headers: _getHeaders,
      );
      if (response.statusCode != 200) {
        throw ApiRequestException(
            response.statusCode, 'Unable to load super admin action history.');
      }
      _recordConnectionSuccess();
      final decoded = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      final items = decoded['data'];
      if (items is! List) return const [];
      return items
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (error) {
      _recordConnectionFailure(_connectionMessage(error));
      rethrow;
    }
  }

  /// Store or issue a new certificate (JSON payload)
  static Future<bool> createCertificate(
      Map<String, dynamic> certificateData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/certificates'),
        headers: _jsonHeaders,
        body: jsonEncode(certificateData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        _recordConnectionSuccess();
        return true;
      } else {
        print(
            'Create certificate failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      _recordConnectionFailure(_connectionMessage(e));
      print('Create certificate error: $e');
      return false;
    }
  }

  /// Issue a single certificate with an attached file (Multipart request)
  static Future<bool> issueCertificateWithFile({
    required String recipientName,
    required String courseOrEvent,
    required String universityCode,
    required String issueDate,
    required dynamic fileBytes,
    required String fileName,
  }) async {
    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse('$baseUrl/certificates/upload'));

      request.fields['recipient_name'] = recipientName;
      request.fields['course_or_event'] = courseOrEvent;
      request.fields['university_code'] = universityCode;
      request.fields['issue_date'] = issueDate;

      request.files.add(
        http.MultipartFile.fromBytes(
          'diploma_file',
          fileBytes,
          filename: fileName,
        ),
      );

      final headers = {'Accept': 'application/json'};
      if (authToken != null && authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $authToken';
      }
      request.headers.addAll(headers);

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _recordConnectionSuccess();
        return true;
      } else {
        print(
            'File issuance failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      _recordConnectionFailure(_connectionMessage(e));
      print('File issuance error: $e');
      return false;
    }
  }

  /// Issue multiple certificates in a batch payload
  static Future<bool> issueBatchCertificates(
      List<Map<String, dynamic>> certificates) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/certificates/batch'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'certificates': certificates,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        _recordConnectionSuccess();
        return true;
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
        throw ApiRequestException(
          response.statusCode,
          body['message']?.toString() ?? 'Batch issuance failed.',
        );
      }
    } catch (e) {
      _recordConnectionFailure(_connectionMessage(e));
      if (e is ApiRequestException) rethrow;
      print('Batch issuance error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>>
      getCertificatesForCurrentUser() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/certificates'),
          headers: _getHeaders);
      if (response.statusCode != 200)
        throw Exception('Failed to load certificates [${response.statusCode}]');
      _recordConnectionSuccess();
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['data'] ?? const []);
    } catch (error) {
      _recordConnectionFailure(_connectionMessage(error));
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getStudentCertificate(
      {String? studentId, String? email}) async {
    final records = await getCertificatesForCurrentUser();
    for (final record in records) {
      if ((studentId != null &&
              record['student_id']?.toString() == studentId) ||
          (email != null &&
              (record['student_email'] ?? record['email'])
                      ?.toString()
                      .toLowerCase() ==
                  email.toLowerCase())) {
        return record;
      }
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getChatMessages() async {
    final response = await http.get(Uri.parse('$baseUrl/chat/messages'),
        headers: _getHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to load chat [${response.statusCode}]');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<List<Map<String, dynamic>>> getChatMessagesForStudent(
      String userId) async {
    final response = await http.get(
        Uri.parse('$baseUrl/chat/messages?with_user_id=$userId'),
        headers: _getHeaders);
    if (response.statusCode != 200)
      throw Exception('Failed to load conversation [${response.statusCode}]');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<List<Map<String, dynamic>>> getChatContacts(
      {String search = ''}) async {
    final query = search.trim().isEmpty
        ? ''
        : '?search=${Uri.encodeQueryComponent(search.trim())}';
    final response = await http.get(Uri.parse('$baseUrl/chat/contacts$query'),
        headers: _getHeaders);
    if (response.statusCode != 200)
      throw Exception('Failed to load students [${response.statusCode}]');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<List<Map<String, dynamic>>> getChatPresence() async {
    final response = await http.get(Uri.parse('$baseUrl/chat/presence'),
        headers: _getHeaders);
    if (response.statusCode != 200)
      throw Exception('Failed to load presence [${response.statusCode}]');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<bool> sendChatMessage(String message,
      {String? recipientUserId,
      List<int>? fileBytes,
      String? fileName,
      String? replyToId,
      bool isReport = false}) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/chat/messages'));
    request.headers.addAll(_getHeaders);
    request.fields['message'] = message;
    if (replyToId != null) request.fields['reply_to_id'] = replyToId;
    if (isReport) request.fields['is_report'] = '1';
    if (recipientUserId != null)
      request.fields['recipient_user_id'] = recipientUserId;
    if (fileBytes != null && fileName != null) {
      request.files.add(http.MultipartFile.fromBytes('attachment', fileBytes,
          filename: fileName));
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return response.statusCode == 201;
  }

  static Future<bool> deleteChatMessage(int messageId,
      {bool forEveryone = false}) async {
    final response = await http.delete(
      Uri.parse(
          '$baseUrl/chat/messages/$messageId?mode=${forEveryone ? 'everyone' : 'me'}'),
      headers: _getHeaders,
    );
    return response.statusCode == 200;
  }

  static Future<bool> clearChatConversation(String userId,
      {bool forEveryone = false}) async {
    final response = await http.delete(
      Uri.parse(
          '$baseUrl/chat/conversation/$userId?mode=${forEveryone ? 'everyone' : 'me'}'),
      headers: _getHeaders,
    );
    return response.statusCode == 200;
  }

  static Future<void> requestCertificateDeletion({
    required String certificateId,
    String? reason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/certificates/$certificateId/deletion-request'),
      headers: _jsonHeaders,
      body: jsonEncode({'reason': reason?.trim()}),
    );
    if (response.statusCode != 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      throw ApiRequestException(
        response.statusCode,
        body['message']?.toString() ?? 'Unable to request credential deletion.',
      );
    }
  }

  static Future<List<Map<String, dynamic>>>
      getCertificateDeletionRequests() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/certificate-deletion-requests'),
      headers: _getHeaders,
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      throw ApiRequestException(
        response.statusCode,
        body['message']?.toString() ?? 'Unable to load deletion requests.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<void> reviewCertificateDeletionRequest({
    required String requestId,
    required String decision,
    String? reviewerNote,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/certificate-deletion-requests/$requestId'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'decision': decision,
        'reviewer_note': reviewerNote?.trim(),
      }),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
      throw ApiRequestException(
        response.statusCode,
        body['message']?.toString() ?? 'Unable to review deletion request.',
      );
    }
  }
}
