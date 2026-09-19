import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_html/html.dart' as html;
import 'qr_code_dialog.dart';

class AdminDashboardView extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> Function() fetchCertificates;
  final VoidCallback onShowAllCertificates;

  const AdminDashboardView({
    super.key,
    required this.fetchCertificates,
    required this.onShowAllCertificates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.5,
          children: [
            _buildActionCard(
              context,
              title: 'Issue Certificate',
              subtitle: 'Upload and hash new diploma',
              icon: Icons.add_moderator,
              color: Colors.blue,
              onTap: () => context.push('/issue'),
            ),
            _buildActionCard(
              context,
              title: 'Verify Hash / QR',
              subtitle: 'Check authenticity on chain',
              icon: Icons.qr_code_scanner,
              color: Colors.teal,
              onTap: () => context.push('/verify'),
            ),
            _buildActionCard(
              context,
              title: 'Recent Credentials',
              subtitle: 'View issued certificates',
              icon: Icons.history,
              color: Colors.amber.shade800,
              onTap: onShowAllCertificates,
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Recent Records',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchCertificates(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading records: ${snapshot.error}'),
                );
              }

              final certificates = snapshot.data ?? [];

              if (certificates.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      'No certificates issued yet.\nUploaded student records will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: certificates.length > 5 ? 5 : certificates.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = certificates[index];
                  final status = item['status'] ?? 'Verified';
                  final studentEmail = item['student_email'] ?? 'No email linked';
                  final imageUrl = item['cert_image_url'];

                  return ListTile(
                    leading: const Icon(Icons.verified_outlined, color: Colors.green),
                    title: Text(item['student_name'] ?? 'Unknown'),
                    subtitle: Text('${item['degree']}\nID: ${item['student_id']} • $studentEmail'),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (imageUrl != null && imageUrl.toString().isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.download, color: Colors.blue),
                            tooltip: 'Download Diploma',
                            onPressed: () async {
                              if (kIsWeb) {
                                html.AnchorElement(href: imageUrl)
                                  ..setAttribute('download', 'Diploma_${item['student_name']?.replaceAll(' ', '_')}.jpg')
                                  ..setAttribute('target', '_blank')
                                  ..click();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Opening diploma image link...')),
                                );
                              }
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.qr_code, color: Colors.teal),
                          tooltip: 'Get QR Code',
                          onPressed: () => showQRCodeDialog(context, item),
                        ),
                        Chip(
                          label: Text(
                            status,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: status == 'Verified'
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          labelStyle: TextStyle(
                            color: status == 'Verified' ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}