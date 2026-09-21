import 'package:certitrust_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
