import 'package:flutter/material.dart';

import '../../core/widgets/certitrust_loading_indicator.dart';
import '../../services/api_service.dart';

class SuperAdminJunkScreen extends StatefulWidget {
  const SuperAdminJunkScreen({super.key});

  @override
  State<SuperAdminJunkScreen> createState() => _SuperAdminJunkScreenState();
}

class _SuperAdminJunkScreenState extends State<SuperAdminJunkScreen> {
  late Future<List<Map<String, dynamic>>> _items;
  final _searchController = TextEditingController();
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _items = ApiService.getJunkItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final nextItems = ApiService.getJunkItems();
    setState(() => _items = nextItems);
    await nextItems;
  }

  Future<void> _permanentlyDelete(Map<String, dynamic> item) async {
    final itemId = int.tryParse(item['id']?.toString() ?? '');
    if (itemId == null || itemId < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'This recycle-bin item has no valid ID and cannot be deleted.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final name = item['student_name']?.toString() ??
        item['student_email']?.toString() ??
        'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete this item?'),
        content: Text(
          'This permanently removes $name and its recycle-bin snapshot. This cannot be undone. Blockchain history is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Permanently delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final currentItems = await _items;
      await ApiService.permanentlyDeleteJunkItem(junkItemId: '$itemId');
      setState(() {
        _items = Future.value(currentItems
            .where(
                (candidate) => candidate['id']?.toString() != itemId.toString())
            .toList());
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name was permanently deleted from Junk.')),
        );
      }
    } catch (error) {
      if (mounted) {
        final message =
            error is ApiRequestException ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not permanently delete this item: $message'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  String _sourceLabel(String source) => switch (source) {
        'subadmin_removed' => 'Subadmin removed',
        'student_removal_approved' => 'Student removal approved',
        'credential_removal_approved' => 'Credential removal approved',
        'credential_revoked' => 'Credential revoked',
        _ => source.replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Junk / Recycle Bin'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _isDeleting ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CertiTrustLoadingIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not load Junk: ${snapshot.error}'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final items = snapshot.data ?? const [];
            final query = _searchController.text.trim().toLowerCase();
            final filtered = items.where((item) {
              if (query.isEmpty) return true;
              return [
                item['student_name'],
                item['student_email'],
                item['student_id'],
                item['university_code'],
                item['university_name'],
                item['record_type'],
                item['source'],
                item['deleted_by_email'],
              ].any((value) => value.toString().toLowerCase().contains(query));
            }).toList();

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Approved student removals and deleted subadmin records are kept here until you permanently delete them. Credential QR codes are marked removed; blockchain history remains immutable.',
                    style: TextStyle(color: Color(0xFF596579)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search Junk',
                      hintText: 'Name, email, ID or university',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(items.isEmpty
                            ? 'The recycle bin is empty.'
                            : 'No items match your search.'),
                      ),
                    )
                  else
                    ...filtered.map((item) {
                      final recordType =
                          item['record_type']?.toString() ?? 'student_account';
                      final isSubadmin = recordType == 'subadmin_account';
                      final payload = item['payload'] is Map
                          ? Map<String, dynamic>.from(item['payload'] as Map)
                          : const <String, dynamic>{};
                      final certificateRecords = payload['certificates'] is List
                          ? (payload['certificates'] as List).whereType<Map>()
                          : const <Map>[];
                      final certificateCodes = certificateRecords
                          .map((certificate) =>
                              certificate['certificate_code']?.toString())
                          .whereType<String>()
                          .where((code) => code.isNotEmpty)
                          .join(', ');
                      final name = item['student_name']?.toString() ??
                          item['student_email']?.toString() ??
                          switch (recordType) {
                            'student_account' => 'Student account',
                            'subadmin_account' => 'Subadmin account',
                            'credential_record' => 'Credential record',
                            _ => 'Archived record',
                          };
                      final university =
                          item['university_code']?.toString() ?? 'N/A';
                      final source = _sourceLabel(
                        item['source']?.toString() ?? 'removed',
                      );
                      final credentialCount =
                          item['credential_count']?.toString() ?? '0';
                      return Card(
                        child: ListTile(
                          leading: Icon(isSubadmin
                              ? Icons.admin_panel_settings_outlined
                              : Icons.person_remove_outlined),
                          title: Text(isSubadmin ? 'Subadmin: $name' : name),
                          subtitle: Text(
                            '${item['student_email'] ?? 'No email'}'
                            '${item['student_id'] == null ? '' : ' · ID: ${item['student_id']}'}\n'
                            '$university · $source · $credentialCount credential(s)'
                            '${certificateCodes.isEmpty ? '' : '\nCodes: $certificateCodes'}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Permanently delete',
                            color: Colors.red.shade700,
                            onPressed: _isDeleting
                                ? null
                                : () => _permanentlyDelete(item),
                            icon: const Icon(Icons.delete_forever_outlined),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      );
}
