import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Configured for local development network IP (Update back to Render URL for production release)
  static const String baseUrl = 'http://192.168.1.10:8000/api';
  // static const String baseUrl = 'https://certitrust-yhzl.onrender.com/api';

  // Session token storage after successful authentication
  static String? authToken;
  static String? authEmail;
  static String? authRole;
  static String? authUniversity;

  static bool get isAuthenticated => authToken != null && authToken!.isNotEmpty;

  /// Initialize and load saved token from local storage on app startup
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    authToken = prefs.getString('auth_token');
    authEmail = prefs.getString('auth_email');
    authRole = prefs.getString('auth_role');
    authUniversity = prefs.getString('auth_university');
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_email');
    await prefs.remove('auth_role');
    await prefs.remove('auth_university');
  }

  static Future<void> validateSession() async {
    if (!isAuthenticated) return;
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/user'), headers: _getHeaders);
      if (response.statusCode != 200) await logout();
    } catch (_) {
      // Keep the cached session when the API is temporarily offline.
    }
  }

  static Future<void> updatePresence() async {
    if (!isAuthenticated) return;
    try {
      await http.post(Uri.parse('$baseUrl/user/presence'), headers: _jsonHeaders);
    } catch (_) {
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
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['data'] ?? [];
      } else {
        print(
            'Failed to load certificates [${response.statusCode}]: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Get certificates error: $e');
      return [];
    }
  }

  /// Fetch a single certificate by its unique hash/code (For verification screen)
  static Future<Map<String, dynamic>?> getCertificateByCode(String code) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/certificates/$code'),
        headers: _getHeaders,
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['data'] ?? jsonResponse;
      } else {
        return null;
      }
    } catch (e) {
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_email', authEmail ?? '');
        await prefs.setString('auth_role', authRole ?? 'student');
        await prefs.setString('auth_university', authUniversity ?? '');
        return jsonResponse;
      } else {
        throw 'Server error [${response.statusCode}]: ${jsonResponse['message'] ?? response.body}';
      }
    } catch (e) {
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
        return jsonResponse;
      } else {
        throw 'Server error [${response.statusCode}]: ${jsonResponse['message'] ?? response.body}';
      }
    } catch (e) {
      print('Verification error: $e');
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
        return true;
      } else {
        print(
            'Create certificate failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
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
        return true;
      } else {
        print(
            'File issuance failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
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
        return true;
      } else {
        print(
            'Batch issuance failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Batch issuance error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>>
      getCertificatesForCurrentUser() async {
    final response = await http.get(Uri.parse('$baseUrl/certificates'),
        headers: _getHeaders);
    if (response.statusCode != 200)
      throw Exception('Failed to load certificates [${response.statusCode}]');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
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

  static Future<List<Map<String, dynamic>>> getChatMessagesForStudent(String studentId) async {
    final response = await http.get(Uri.parse('$baseUrl/chat/messages?student_id=$studentId'), headers: _getHeaders);
    if (response.statusCode != 200) throw Exception('Failed to load conversation [${response.statusCode}]');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<List<Map<String, dynamic>>> getChatContacts({String search = ''}) async {
    final query = search.trim().isEmpty ? '' : '?search=${Uri.encodeQueryComponent(search.trim())}';
    final response = await http.get(Uri.parse('$baseUrl/chat/contacts$query'), headers: _getHeaders);
    if (response.statusCode != 200) throw Exception('Failed to load students [${response.statusCode}]');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<List<Map<String, dynamic>>> getChatPresence() async {
    final response = await http.get(Uri.parse('$baseUrl/chat/presence'), headers: _getHeaders);
    if (response.statusCode != 200) throw Exception('Failed to load presence [${response.statusCode}]');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['data'] ?? const []);
  }

  static Future<bool> sendChatMessage(String message, {String? recipientUserId, List<int>? fileBytes, String? fileName}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chat/messages'));
    request.headers.addAll(_getHeaders);
    request.fields['message'] = message;
    if (recipientUserId != null) request.fields['recipient_user_id'] = recipientUserId;
    if (fileBytes != null && fileName != null) {
      request.files.add(http.MultipartFile.fromBytes('attachment', fileBytes, filename: fileName));
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return response.statusCode == 201;
  }
}
