import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:certitrust_mobile/services/api_service.dart';
import 'package:certitrust_mobile/core/utils/hash_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credential hash fingerprints the exact attached document bytes', () {
    final hash = HashUtil.generateCredentialHash(
      studentId: '20260002',
      studentName: 'Issued Student',
      studentEmail: 'student@example.edu',
      degree: 'BSIT',
      universityCode: 'PSU',
      documentBytes: 'abc'.codeUnits,
    );

    expect(
      hash,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('metadata-only credential hashes are stable and normalized', () {
    String hash({required String email, required String school}) =>
        HashUtil.generateCredentialHash(
          studentId: ' 20260002 ',
          studentName: ' Issued Student ',
          studentEmail: email,
          degree: ' BSIT ',
          universityCode: school,
        );

    expect(hash(email: 'STUDENT@example.edu', school: 'psu'),
        hash(email: 'student@example.edu', school: 'PSU'));
  });

  test('uses the public Render API by default on mobile clients', () {
    expect(
      ApiService.baseUrl,
      'https://certitrust-yhzl.onrender.com/api',
    );
  });

  test('supports local and production API overrides', () {
    expect(
      ApiService.normalizeBaseUrl('http://127.0.0.1:8000/api'),
      'http://127.0.0.1:8000/api',
    );
    expect(
      ApiService.normalizeBaseUrl('http://localhost:8000/api'),
      'http://localhost:8000/api',
    );
    expect(
      ApiService.normalizeBaseUrl('http://10.0.2.2:8000/api'),
      'http://10.0.2.2:8000/api',
    );
    expect(
      ApiService.normalizeBaseUrl('https://certitrust-yhzl.onrender.com/api'),
      'https://certitrust-yhzl.onrender.com/api',
    );
  });

  test('rejects duplicated absolute URLs that include the full API host twice',
      () {
    expect(
      ApiService.normalizeBaseUrl(
        'https://certitrust-yhzl.onrender.com/apihttps://certitrust-yhzl.onrender.com/api/health',
      ),
      'https://certitrust-yhzl.onrender.com/api',
    );
  });

  test('certificate requests can be limited for recent dashboard records',
      () async {
    Uri? requestedUri;

    await http.runWithClient(
      () async {
        final certificates =
            await ApiService.getCertificatesForCurrentUser(limit: 5);
        expect(certificates, isEmpty);
      },
      () => MockClient((request) async {
        requestedUri = request.url;
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );

    expect(requestedUri?.path, endsWith('/certificates'));
    expect(requestedUri?.queryParameters['limit'], '5');
  });

  test('recent verification requests use the scoped activity endpoint',
      () async {
    Uri? requestedUri;

    await http.runWithClient(
      () async {
        final verifications = await ApiService.getRecentVerifications();
        expect(verifications, isEmpty);
      },
      () => MockClient((request) async {
        requestedUri = request.url;
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );

    expect(requestedUri?.path, endsWith('/admin/recent-verifications'));
    expect(requestedUri?.queryParameters['limit'], '5');
  });

  test('removed credential lookups preserve the backend removed status',
      () async {
    await http.runWithClient(
      () async {
        await expectLater(
          ApiService.getCertificateByCode('OLD-CREDENTIAL-CODE'),
          throwsA(
            isA<ApiRequestException>()
                .having((error) => error.statusCode, 'statusCode', 410)
                .having(
                  (error) => error.message,
                  'message',
                  contains('removed from the database'),
                ),
          ),
        );
      },
      () => MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'removed',
              'message':
                  'This credential was removed from the database and is no longer valid.',
            }),
            410,
          )),
    );
  });

  test('global account and credential cleanup uses the shared admin API',
      () async {
    Uri? requestedUri;
    String? requestMethod;

    await http.runWithClient(
      () async {
        final result = await ApiService.purgeAccountsAndCredentials();
        expect(result['data']['deleted_certificate_count'], 3);
      },
      () => MockClient((request) async {
        requestedUri = request.url;
        requestMethod = request.method;
        return http.Response(
          jsonEncode({
            'message': 'Cleanup complete.',
            'data': {'deleted_certificate_count': 3},
          }),
          200,
        );
      }),
    );

    expect(requestMethod, 'DELETE');
    expect(requestedUri?.path, endsWith('/admin/accounts-and-credentials'));
  });

  test(
      'student removal returns a pending approval instead of deleting immediately',
      () async {
    Uri? requestedUri;
    String? requestMethod;

    await http.runWithClient(
      () async {
        final result = await ApiService.deleteStudentAccount(userId: 42);
        expect(result['data']['status'], 'pending');
      },
      () => MockClient((request) async {
        requestedUri = request.url;
        requestMethod = request.method;
        return http.Response(
          jsonEncode({
            'message': 'Student removal request sent for approval.',
            'data': {'request_id': 5, 'status': 'pending'},
          }),
          202,
        );
      }),
    );

    expect(requestMethod, 'DELETE');
    expect(requestedUri?.path, endsWith('/admin/students/42'));
  });

  test('Junk screen loads and permanently deletes through the shared API',
      () async {
    final requestedPaths = <String>[];
    final requestedMethods = <String>[];

    await http.runWithClient(
      () async {
        final items = await ApiService.getJunkItems();
        expect(items.single['record_type'], 'student_account');
        await ApiService.permanentlyDeleteJunkItem(junkItemId: '9');
      },
      () => MockClient((request) async {
        requestedPaths.add(request.url.path);
        requestedMethods.add(request.method);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 9, 'record_type': 'student_account'},
                {'record_type': 'student_account'},
                {'id': 10, 'record_type': 'unknown_record'},
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'message': 'Deleted.'}), 200);
      }),
    );

    expect(requestedPaths[0], endsWith('/admin/junk'));
    expect(requestedPaths[1], endsWith('/admin/junk/9'));
    expect(requestedMethods, ['GET', 'DELETE']);
  });
}
