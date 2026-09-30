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

  test('rejects localhost and loopback API overrides for mobile clients', () {
    expect(
      ApiService.normalizeBaseUrl('http://127.0.0.1:8000/api'),
      'https://certitrust-yhzl.onrender.com/api',
    );
    expect(
      ApiService.normalizeBaseUrl('http://localhost:8000/api'),
      'https://certitrust-yhzl.onrender.com/api',
    );
    expect(
      ApiService.normalizeBaseUrl('https://certitrust-yhzl.onrender.com/api'),
      'https://certitrust-yhzl.onrender.com/api',
    );
  });

  test('rejects duplicated absolute URLs that include the full API host twice', () {
    expect(
      ApiService.normalizeBaseUrl(
        'https://certitrust-yhzl.onrender.com/apihttps://certitrust-yhzl.onrender.com/api/health',
      ),
      'https://certitrust-yhzl.onrender.com/api',
    );
  });
}
