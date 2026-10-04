import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'qr_code_dialog.dart';
import 'diploma_preview.dart';

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
        Text('Quick Actions',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.5,
          children: [
            _buildActionCard(context,
                title: 'Issue Certificate',
                subtitle: 'Upload and hash new diploma',
                icon: Icons.add_moderator,
                color: Colors.blue,
                onTap: () => context.push('/issue')),
            _buildActionCard(context,
                title: 'Verify Hash / QR',
                subtitle: 'Check authenticity on chain',
                icon: Icons.qr_code_scanner,
                color: Colors.teal,
                onTap: () => context.push('/verify')),
            _buildActionCard(context,
                title: 'Recent Credentials',
                subtitle: 'View issued certificates',
                icon: Icons.history,
                color: Colors.amber.shade800,
                onTap: onShowAllCertificates),
          ],
        ),
        const SizedBox(height: 32),
        Text('Recent Records',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchCertificates(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading records: ${snapshot.error}'));
              }
              final certificates = snapshot.data ?? [];
              if (certificates.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                        child: Text(
                            'No certificates issued yet.\nUploaded student records will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey))));
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: certificates.length > 5 ? 5 : certificates.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = certificates[index];
                  final status = item['status'] ?? 'Verified';
                  final studentEmail =
                      item['student_email'] ?? 'No email linked';
                  final imageUrl =
                      item['diploma_url'] ?? item['cert_image_url'];
                  final publishedAt =
                      DateTime.tryParse(item['created_at']?.toString() ?? '');
                  final publishedLabel = publishedAt == null
                      ? 'N/A'
                      : publishedAt.toLocal().toString().substring(0, 16);
                  return ExpansionTile(
                    key: PageStorageKey(
                        'dashboard-credential-${item['id'] ?? item['cert_hash']}'),
                    initiallyExpanded: false,
                    leading: const Icon(Icons.verified_outlined,
                        color: Colors.green),
                    title: Text(
                      item['student_name']?.toString() ?? 'Unknown',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      _recordDetail('Student ID',
                          item['student_id']?.toString() ?? 'N/A'),
                      _recordDetail('Course / program',
                          item['degree']?.toString() ?? 'N/A'),
                      _recordDetail('Gmail', studentEmail.toString()),
                      _recordDetail('Degree number',
                          item['degree_number']?.toString() ?? '1'),
                      _recordDetail('Published', publishedLabel),
                      _recordDetail('Status', status.toString()),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: [
                          if (imageUrl != null &&
                              imageUrl.toString().isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('View This Diploma'),
                              onPressed: () => showDiplomaPreview(
                                  context, imageUrl.toString()),
                            ),
                          TextButton.icon(
                            icon: const Icon(Icons.qr_code),
                            label: const Text('Get QR Code'),
                            onPressed: () => showQRCodeDialog(context, item),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _recordDetail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  Widget _buildActionCard(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withAlpha(26),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ])),
          ]),
        ),
      ),
    );
  }
}
