import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/diploma_download.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/diploma_preview.dart';
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
    final diplomaUrl = (certificate['diploma_url'] ??
            certificate['cert_image_url'] ??
            certificate['image_url'])
        ?.toString();
    final studentId = (certificate['student_id'] ?? 'Student')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final diplomaFileName = 'Diploma_$studentId.jpg';
    final status = certificate['status']?.toString().trim().toLowerCase();
    final hasVerificationCode =
        (certificate['cert_hash'] ?? certificate['certificate_code'])
                ?.toString()
                .isNotEmpty ==
            true;
    final isVerified =
        hasVerificationCode && (status == 'verified' || status == 'valid');
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
                  Icon(
                    isVerified ? Icons.verified : Icons.error_outline,
                    color: isVerified ? Colors.green : Colors.red,
                    size: 76,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isVerified
                        ? 'Legitimate Credential'
                        : 'Credential Not Verified',
                    style: TextStyle(
                      color: isVerified ? Colors.green : Colors.red,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                      isVerified
                          ? 'This credential proves that ${certificate['student_name'] ?? certificate['recipient_name'] ?? 'the student'} graduated from $schoolName and was verified by CertiTrust.'
                          : 'This credential record was found, but its status is not valid.',
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
                  if (diplomaUrl != null && diplomaUrl.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Attached diploma image',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => showDiplomaPreview(
                        context,
                        diplomaUrl,
                        fileName: diplomaFileName,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: double.infinity,
                          height: 200,
                          child: Image.network(
                            diplomaUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                              child: Text('Could not load diploma preview.'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          try {
                            await downloadDiplomaImage(
                              diplomaUrl,
                              fileName: diplomaFileName,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Diploma downloaded. Check your Downloads or gallery.'),
                              ),
                            );
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Could not download diploma: $error')),
                            );
                          }
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Download diploma'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(
                        isVerified ? Icons.verified_user : Icons.error_outline,
                        color: isVerified ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(isVerified
                            ? 'Verified on the CertiTrust ledger'
                            : 'Verification failed for this credential'),
                      ),
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
