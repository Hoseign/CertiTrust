import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HashUtil {
  /// Converts raw file bytes (PDF or Image) into a SHA-256 hexadecimal string.
  static String generateDocumentHash(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Converts a standard text string into a SHA-256 hexadecimal hash.
  static String generateStringHash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Checks Supabase to see if a certificate with this hash already exists.
  static Future<bool> isHashRegistered(String hash) async {
    try {
      final response = await Supabase.instance.client
          .from('certificates')
          .select('id')
          .eq('cert_hash', hash)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      print('Error checking hash in Supabase: $e');
      return false;
    }
  }

  /// Fetches certificate details from Supabase using its hash (for verification).
  static Future<Map<String, dynamic>?> verifyCertificateByHash(String hash) async {
    try {
      final response = await Supabase.instance.client
          .from('certificates')
          .select()
          .eq('cert_hash', hash)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error verifying certificate by hash: $e');
      return null;
    }
  }
}