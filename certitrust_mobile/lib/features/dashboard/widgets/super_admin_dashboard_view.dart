import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/certitrust_loading_indicator.dart';

class SuperAdminDashboardView extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() fetchOverview;

  const SuperAdminDashboardView({
    super.key,
    required this.fetchOverview,
  });

  @override
  State<SuperAdminDashboardView> createState() =>
      _SuperAdminDashboardViewState();
}

class _SuperAdminDashboardViewState extends State<SuperAdminDashboardView>
    with WidgetsBindingObserver {
  late Future<Map<String, dynamic>> _overview;
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _overview = widget.fetchOverview();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isAppActive) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;
    if (_isAppActive) _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    final refresh = widget.fetchOverview();
    setState(() {
      _overview = refresh;
      _isRefreshing = true;
    });
    try {
      await refresh;
    } catch (error) {
      debugPrint('Unable to refresh super admin dashboard: $error');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _overview,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final activity =
            List<Map<String, dynamic>>.from(data['activity'] ?? const []);
        final admins =
            List<Map<String, dynamic>>.from(data['admins'] ?? const []);
        final universities =
            List<Map<String, dynamic>>.from(data['universities'] ?? const []);
        final history =
            List<Map<String, dynamic>>.from(data['history'] ?? const []);
        final credentialBatches = List<Map<String, dynamic>>.from(
          data['credential_batches'] ?? const [],
        );

        final cards = [
          _OverviewCard(
            label: 'Total Universities',
            value: '${universities.length}',
            icon: Icons.account_balance,
            color: const Color(0xFF1E6B8F),
            description: 'Universities registered in the system.',
            details: universities,
            emptyMessage: 'No universities registered yet.',
            detailTitle: (item) =>
                (item['name'] ?? item['code'] ?? 'University').toString(),
            detailSubtitle: (item) => 'Code: ${item['code'] ?? 'N/A'}',
          ),
          _OverviewCard(
            label: 'Total Credentials',
            value: '${data['total_credentials'] ?? 0}',
            icon: Icons.workspace_premium,
            color: const Color(0xFFB07A16),
            description: 'Credentials uploaded by subadmins.',
            details: activity,
            credentialBatches: credentialBatches,
            verifiedBreakdown: false,
            emptyMessage: 'No global credential activity yet.',
            detailTitle: (item) => (item['student_name'] ??
                    item['recipient_name'] ??
                    'Unknown credential')
                .toString(),
            detailSubtitle: (item) =>
                'Status: ${item['status'] ?? 'Pending'} • ${item['university_code'] ?? 'Unassigned'}',
          ),
          _OverviewCard(
            label: 'Verified Credentials',
            value: '${data['verified_credentials'] ?? 0}',
            icon: Icons.verified,
            color: const Color(0xFF27805B),
            description: 'Credentials currently marked verified.',
            details: activity
                .where((item) =>
                    (item['status'] ?? '').toString().toLowerCase() ==
                    'verified')
                .toList(),
            credentialBatches: credentialBatches,
            verifiedBreakdown: true,
            emptyMessage: 'No verified credentials yet.',
            detailTitle: (item) => (item['student_name'] ??
                    item['recipient_name'] ??
                    'Unknown credential')
                .toString(),
            detailSubtitle: (item) =>
                'University: ${item['university_code'] ?? 'Unassigned'}',
          ),
          _OverviewCard(
            label: 'Subadmin Accounts',
            value: '${admins.length}',
            icon: Icons.admin_panel_settings,
            color: const Color(0xFF8A4B62),
            description: 'Registered university administrators.',
            details: admins,
            emptyMessage: 'No subadmin accounts registered yet.',
            detailTitle: (item) =>
                (item['name'] ?? item['email'] ?? 'University Admin')
                    .toString(),
            detailSubtitle: (item) =>
                '${item['email'] ?? 'No email'} • ${item['university_code'] ?? 'No university'}',
          ),
        ];

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              const Text('Super Admin Dashboard',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF172033))),
              const SizedBox(height: 4),
              const Text(
                  'Register subadmins and monitor global credential activity.',
                  style: TextStyle(color: Color(0xFF657184))),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CertiTrustLoadingIndicator()))
              else if (snapshot.hasError)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child:
                        Text('Unable to load global data: ${snapshot.error}'))
              else ...[
                GridView.builder(
                  itemCount: cards.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.55),
                  itemBuilder: (context, index) =>
                      _statCard(context, cards[index]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/admin-management'),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Create subadmin account'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/admin-management/access'),
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Freeze or unfreeze access'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/deletion-requests'),
                    icon: const Icon(Icons.pending_actions),
                    label: const Text('Credential deletion requests'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showHistoryDialog(context, history),
                    icon: const Icon(Icons.history),
                    label: const Text('Action history'),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Global Credential Logs',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF172033))),
                const SizedBox(height: 8),
                _activityTable(context, activity),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showHistoryDialog(
      BuildContext context, List<Map<String, dynamic>> history) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Super Admin Action History'),
          content: SizedBox(
            width: double.maxFinite,
            child: history.isEmpty
                ? const Text('No subadmin actions have been recorded yet.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final action = (item['action'] ?? 'action').toString();
                      final university =
                          (item['university_code'] ?? 'N/A').toString();
                      final target =
                          (item['target_email'] ?? 'No email').toString();
                      final date = _timestamp(item['created_at']?.toString());
                      final label = _formatAction(action);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(label),
                        subtitle: Text('$target • $university\n$date',
                            style: const TextStyle(fontSize: 12)),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _statCard(BuildContext context, _OverviewCard card) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: card.credentialBatches != null
            ? () => _showCredentialBreakdown(context, card)
            : () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) {
                    final items = card.details;

                    return AlertDialog(
                      title: Text(card.label),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: items.isEmpty
                            ? Text(card.emptyMessage)
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(card.detailTitle(item)),
                                    subtitle: Text(card.detailSubtitle(item)),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    );
                  },
                ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(card.icon, color: card.color, size: 24),
                Text(card.value,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF172033))),
                Text(card.label,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF657184)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
        ),
      ),
    );
  }

  void _showCredentialBreakdown(BuildContext context, _OverviewCard card) {
    final batches = card.credentialBatches!;
    final countKey =
        card.verifiedBreakdown == true ? 'verified_count' : 'total_count';
    final overallLabel = card.verifiedBreakdown == true
        ? 'Entire verified credentials'
        : 'Entire credentials';
    final visibleBatches =
        batches.where((batch) => (batch[countKey] as num? ?? 0) > 0).toList();
    String? selectedYear;
    const overall = '@overall';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selected = selectedYear == null || selectedYear == overall
              ? null
              : visibleBatches.firstWhere(
                  (batch) => batch['batch_year'].toString() == selectedYear,
                );
          final selectedOverall = selectedYear == overall;
          final universities = selectedOverall
              ? card.credentialBatches!
                  .expand((batch) => List<Map<String, dynamic>>.from(
                      batch['universities'] ?? const []))
                  .fold<Map<String, Map<String, dynamic>>>(
                    {},
                    (totals, university) {
                      final code = university['code']?.toString() ?? '';
                      final total = totals.putIfAbsent(
                          code,
                          () => {
                                'code': code,
                                'name': university['name'],
                                'display_name': university['display_name'],
                                'total_count': 0,
                                'verified_count': 0,
                              });
                      total['total_count'] = (total['total_count'] as int) +
                          ((university['total_count'] as num?)?.toInt() ?? 0);
                      total['verified_count'] = (total['verified_count']
                              as int) +
                          ((university['verified_count'] as num?)?.toInt() ??
                              0);
                      return totals;
                    },
                  )
                  .values
                  .where(
                      (university) => (university[countKey] as num? ?? 0) > 0)
                  .toList()
              : selected == null
                  ? const <Map<String, dynamic>>[]
                  : List<Map<String, dynamic>>.from(
                      selected['universities'] ?? const [],
                    )
                      .where((university) =>
                          (university[countKey] as num? ?? 0) > 0)
                      .toList();

          return AlertDialog(
            title: Row(
              children: [
                if (selected != null || selectedOverall)
                  IconButton(
                    tooltip: 'Back to batches',
                    onPressed: () => setDialogState(() => selectedYear = null),
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    selected == null && !selectedOverall
                        ? card.label
                        : selectedOverall
                            ? overallLabel
                            : '${card.label} • $selectedYear',
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: selected == null && !selectedOverall
                  ? visibleBatches.isEmpty
                      ? const Text('No credential batches are available yet.')
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: visibleBatches.length + 1,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(overallLabel),
                                subtitle:
                                    const Text('View totals by university'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(card.value),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => setDialogState(
                                    () => selectedYear = overall),
                              );
                            }
                            final batch = visibleBatches[index - 1];
                            final year = batch['batch_year'].toString();
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Batch $year'),
                              subtitle: const Text('View by university'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${batch[countKey] ?? 0}'),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () =>
                                  setDialogState(() => selectedYear = year),
                            );
                          },
                        )
                  : universities.isEmpty
                      ? const Text(
                          'No universities have credentials in this batch.')
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: universities.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final university = universities[index];
                            final name = university['name']?.toString() ??
                                university['code']?.toString() ??
                                'University';
                            final displayName =
                                university['display_name']?.toString();
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(name),
                              subtitle: Text(
                                displayName == null || displayName == name
                                    ? 'Batch $selectedYear'
                                    : '$displayName • Batch $selectedYear',
                              ),
                              trailing: Text('${university[countKey] ?? 0}'),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _activityTable(
      BuildContext context, List<Map<String, dynamic>> activity) {
    if (activity.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(28),
              child:
                  Center(child: Text('No global credential activity yet.'))));
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
          rows: activity
              .take(15)
              .map((item) => DataRow(cells: [
                    DataCell(
                        Text(item['student_name']?.toString() ?? 'Unknown')),
                    DataCell(Text(
                        item['university_code']?.toString() ?? 'Unassigned')),
                    DataCell(Text(_timestamp(item['created_at']?.toString()))),
                    DataCell(Text(item['status']?.toString() ?? 'Pending')),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  String _formatAction(String action) {
    switch (action) {
      case 'created_subadmin':
        return 'Created subadmin';
      case 'updated_subadmin':
        return 'Updated subadmin';
      case 'deleted_subadmin':
        return 'Deleted subadmin';
      case 'removed_google_binding':
        return 'Removed Google binding';
      default:
        return action
            .replaceAll('_', ' ')
            .replaceFirst(action[0], action[0].toUpperCase());
    }
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
  final List<Map<String, dynamic>> details;
  final List<Map<String, dynamic>>? credentialBatches;
  final bool? verifiedBreakdown;
  final String emptyMessage;
  final String Function(Map<String, dynamic>) detailTitle;
  final String Function(Map<String, dynamic>) detailSubtitle;

  const _OverviewCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.description,
    required this.details,
    this.credentialBatches,
    this.verifiedBreakdown,
    required this.emptyMessage,
    required this.detailTitle,
    required this.detailSubtitle,
  });
}
