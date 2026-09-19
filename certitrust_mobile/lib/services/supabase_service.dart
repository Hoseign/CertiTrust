import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Access the Supabase client instance initialized in main.dart
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Verifies and retrieves a certificate using the backend certificate code.
  Future<Map<String, dynamic>?> getCertificateByHash(String code) async {
    try {
      final trimmedCode = code.trim();
      if (trimmedCode.isEmpty) return null;

      final response = await _supabase
          .from('certificates')
          .select()
          .eq('certificate_code', trimmedCode)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error querying Supabase for certificate: $e');
      return null;
    }
  }

  // Legacy method name mapped to the new implementation for compatibility
  Future<Map<String, dynamic>?> verifyCertificate(String code) async {
    return await getCertificateByHash(code);
  }
}