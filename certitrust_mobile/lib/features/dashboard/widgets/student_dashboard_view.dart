import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'qr_code_dialog.dart';

class StudentDashboardView extends StatelessWidget {
  final bool isLoadingCertificate;
  final Map<String, dynamic>? studentCertificate;

  const StudentDashboardView({
    super.key,
    required this.isLoadingCertificate,
    required this.studentCertificate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoadingCertificate) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (studentCertificate == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300, width: 2),
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 48, color: Colors.orange),
                SizedBox(height: 16),
                Text(
                  'No Certificate Found',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'No issued academic certificate is currently linked to your student account or email address. Please contact the registrar office if you believe this is an error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.verified, color: Colors.green, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Credential Status',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Chip(
                      label: Text(studentCertificate!['status'] ?? 'Verified'),
                      backgroundColor: Colors.green.shade50,
                      labelStyle: const TextStyle(color: Colors.green, fontSize: 12),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const Divider(height: 32),
                _buildDetailRow('Student Name', studentCertificate!['student_name'] ?? studentCertificate!['name'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildDetailRow('Student ID', studentCertificate!['student_id'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildDetailRow('Degree / Program', studentCertificate!['degree'] ?? studentCertificate!['program'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildDetailRow('Email', studentCertificate!['student_email'] ?? studentCertificate!['email'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildDetailRow('Issue Date', studentCertificate!['issue_date'] ?? studentCertificate!['created_at'] ?? 'N/A'),

                if (studentCertificate!['cert_image_url'] != null && 
                    studentCertificate!['cert_image_url'].toString().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Digital Diploma Copy:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppBar(
                                title: const Text('Digital Diploma Copy'),
                                automaticallyImplyLeading: false,
                                actions: [
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              Flexible(
                                child: InteractiveViewer(
                                  child: Image.network(studentCertificate!['cert_image_url']),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        color: Colors.grey.shade200,
                        child: Image.network(
                          studentCertificate!['cert_image_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Text('Could not load image preview'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => showQRCodeDialog(context, studentCertificate!),
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Get QR Code', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          final hash = studentCertificate!['cert_hash'] ?? 
                                     studentCertificate!['ipfs_hash'] ?? 
                                     studentCertificate!['hash'] ?? '';
                          context.push('/verify?hash=$hash');
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Verify on Chain', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }
}