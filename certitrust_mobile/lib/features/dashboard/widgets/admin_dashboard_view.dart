import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchCertificates(),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <Map<String, dynamic>>[];
        final verified = records.where((record) => record['status'] == 'Verified').length;
        final pending = records.length - verified;
        return RefreshIndicator(
          onRefresh: () async => fetchCertificates(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              const Text('Dashboard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF172033))),
              const SizedBox(height: 4),
              const Text('Upload student credentials for your university and verify records.', style: TextStyle(color: Color(0xFF657184))),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth > 650 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: columns == 2 ? 1.55 : 1.8,
                  children: [
                    _statCard('Total Universities', '1', Icons.account_balance, const Color(0xFF1E6B8F)),
                    _statCard('Total Credentials', '${records.length}', Icons.workspace_premium, const Color(0xFFB07A16)),
                    _statCard('Verified Credentials', '$verified', Icons.verified, const Color(0xFF27805B)),
                    _statCard('Pending Actions', '${pending < 0 ? 0 : pending}', Icons.pending_actions, const Color(0xFF8A4B62)),
                  ],
                );
              }),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Expanded(child: Text('Recent Global Activity Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF172033)))),
                TextButton.icon(onPressed: onShowAllCertificates, icon: const Icon(Icons.open_in_new, size: 16), label: const Text('View all')),
              ]),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
                    : snapshot.hasError
                        ? Padding(padding: const EdgeInsets.all(20), child: Text('Unable to load activity: ${snapshot.error}'))
                        : records.isEmpty
                            ? const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No global credential activity yet.')))
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF0F3F7)),
                                  columns: const [
                                    DataColumn(label: Text('Credential')),
                                    DataColumn(label: Text('University')),
                                    DataColumn(label: Text('Activity')),
                                    DataColumn(label: Text('Status')),
                                  ],
                                  rows: records.take(8).map((record) => DataRow(cells: [
                                    DataCell(Text(record['student_name']?.toString() ?? 'Unknown')),
                                    DataCell(Text(record['university_code']?.toString() ?? 'UCU')),
                                    DataCell(Text(record['created_at']?.toString().split('T').first ?? 'Credential issued')),
                                    DataCell(_statusChip(record['status']?.toString() ?? 'Verified')),
                                  ])).toList(),
                                ),
                              ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/issue'), icon: const Icon(Icons.upload_file), label: const Text('Upload credentials'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/verify'), icon: const Icon(Icons.verified_outlined), label: const Text('Verify'))),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, color: color, size: 24),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF172033))),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF657184)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    final verified = status.toLowerCase() == 'verified';
    return Chip(
      label: Text(status, style: TextStyle(fontSize: 12, color: verified ? const Color(0xFF27805B) : const Color(0xFF8A6418))),
      backgroundColor: verified ? const Color(0xFFE7F5ED) : const Color(0xFFFFF3D8),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }

}
