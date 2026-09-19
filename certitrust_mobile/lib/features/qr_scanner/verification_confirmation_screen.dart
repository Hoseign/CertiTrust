import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class VerificationConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic> certificate;
  const VerificationConfirmationScreen({super.key, required this.certificate});

  @override
  Widget build(BuildContext context) {
    final school = (certificate['university_code'] ??
            ApiService.authUniversity ??
            'Verified Institution')
        .toString()
        .toUpperCase();
    final schoolName = school == 'PSU'
        ? 'Pangasinan State University'
        : school == 'UCU'
            ? 'Urdaneta City University'
            : 'Verified academic institution';
    final schoolLogo = school == 'PSU'
        ? 'web/assets/images/PSU_LOGO.png'
        : school == 'UCU'
            ? 'web/assets/images/UCU_LOGO.png'
            : 'web/assets/images/certitrustlogo.png';
    return Scaffold(
      appBar: AppBar(title: const Text('Credential Status')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 76),
                  const SizedBox(height: 12),
                  const Text('Legitimate Credential',
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const Divider(height: 32),
                  Image.asset(schoolLogo, height: 92, fit: BoxFit.contain),
                  const SizedBox(height: 12),
                  Text(school,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.red)),
                  Text(schoolName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text(
                      'This credential proves that ${certificate['student_name'] ?? certificate['recipient_name'] ?? 'the student'} graduated from $schoolName and was verified by CertiTrust.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  _row(
                      'Student name',
                      certificate['student_name'] ??
                          certificate['recipient_name'] ??
                          'N/A'),
                  _row('Student ID', certificate['student_id'] ?? 'N/A'),
                  _row(
                      'Degree and program',
                      certificate['degree'] ??
                          certificate['course_or_event'] ??
                          'N/A'),
                  _row('Issue date', certificate['issue_date'] ?? 'N/A'),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: [
                      Icon(Icons.verified_user, color: Colors.green),
                      SizedBox(width: 10),
                      Expanded(child: Text('Verified on the CertiTrust ledger'))
                    ]),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                      onPressed: () => context.pop(), child: const Text('OK')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value.toString()))
        ]),
      );
}
