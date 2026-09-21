import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SuperAdminDashboardView extends StatelessWidget {
  final Future<Map<String, dynamic>> Function() fetchOverview;

  const SuperAdminDashboardView({
    super.key,
    required this.fetchOverview,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: fetchOverview(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final activity = List<Map<String, dynamic>>.from(data['activity'] ?? const []);
        final admins = List<Map<String, dynamic>>.from(data['admins'] ?? const []);
        final cards = [
          _OverviewCard('Total Universities', '${data['total_universities'] ?? 0}', Icons.account_balance, const Color(0xFF1E6B8F), 'Universities registered in the system.'),
          _OverviewCard('Total Credentials', '${data['total_credentials'] ?? 0}', Icons.workspace_premium, const Color(0xFFB07A16), 'Credentials uploaded by subadmins.'),
          _OverviewCard('Verified Credentials', '${data['verified_credentials'] ?? 0}', Icons.verified, const Color(0xFF27805B), 'Credentials currently marked verified.'),
          _OverviewCard('Subadmin Accounts', '${admins.length}', Icons.admin_panel_settings, const Color(0xFF8A4B62), 'Registered university administrators.'),
        ];

        return RefreshIndicator(
          onRefresh: () async => fetchOverview(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              const Text('Super Admin Dashboard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF172033))),
              const SizedBox(height: 4),
              const Text('Register subadmins and monitor global credential activity.', style: TextStyle(color: Color(0xFF657184))),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                Padding(padding: const EdgeInsets.all(16), child: Text('Unable to load global data: ${snapshot.error}'))
              else ...[
                GridView.builder(
                  itemCount: cards.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.55),
                  itemBuilder: (context, index) => _statCard(context, cards[index]),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/admin-management'),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Create subadmin account'),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Global Credential Logs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF172033))),
                const SizedBox(height: 8),
                _activityTable(context, activity),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(BuildContext context, _OverviewCard card) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(card.label),
            content: Text(card.description),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Icon(card.icon, color: card.color, size: 24),
            Text(card.value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF172033))),
            Text(card.label, style: const TextStyle(fontSize: 12, color: Color(0xFF657184)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _activityTable(BuildContext context, List<Map<String, dynamic>> activity) {
    if (activity.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No global credential activity yet.'))));
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Credential')),
            DataColumn(label: Text('University')),
            DataColumn(label: Text('Date and time')),
            DataColumn(label: Text('Status')),
          ],
          rows: activity.take(15).map((item) => DataRow(cells: [
            DataCell(Text(item['student_name']?.toString() ?? 'Unknown')),
            DataCell(Text(item['university_code']?.toString() ?? 'Unassigned')),
            DataCell(Text(_timestamp(item['created_at']?.toString()))),
            DataCell(Text(item['status']?.toString() ?? 'Pending')),
          ])).toList(),
        ),
      ),
    );
  }

  String _timestamp(String? value) {
    if (value == null || value.isEmpty) return 'No timestamp';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }
}

class _OverviewCard {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String description;

  const _OverviewCard(this.label, this.value, this.icon, this.color, this.description);
}
