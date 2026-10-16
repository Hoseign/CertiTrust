import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminDashboardView extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() fetchCertificates;
  final Future<List<Map<String, dynamic>>> Function()
      fetchRecentVerifications;
  final void Function(Future<List<Map<String, dynamic>>> credentials)
      onViewRecentCredentials;

  const AdminDashboardView({
    super.key,
    required this.fetchCertificates,
    required this.fetchRecentVerifications,
    required this.onViewRecentCredentials,
  });

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView>
    with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> _recentCredentials;
  late Future<List<Map<String, dynamic>>> _recentVerifications;
  List<Map<String, dynamic>> _cachedCredentials = [];
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recentCredentials = widget.fetchCertificates();
    _recentVerifications = widget.fetchRecentVerifications();
    _rememberCredentials(_recentCredentials);
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
    final certificates = widget.fetchCertificates();
    final verifications = widget.fetchRecentVerifications();
    setState(() {
      _isRefreshing = true;
      _recentCredentials = certificates;
      _recentVerifications = verifications;
    });
    try {
      final results = await Future.wait([certificates, verifications]);
      if (mounted) {
        setState(() {
          _cachedCredentials = List<Map<String, dynamic>>.from(results.first);
        });
      }
    } catch (error) {
      debugPrint('Unable to refresh dashboard activity: $error');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _rememberCredentials(
      Future<List<Map<String, dynamic>>> credentials) async {
    try {
      final latest = await credentials;
      if (mounted) setState(() => _cachedCredentials = latest);
    } catch (error) {
      debugPrint('Unable to load recent credentials: $error');
    }
  }

  String get _recentCredentialsSubtitle {
    if (_cachedCredentials.isEmpty) {
      return 'Newly issued credentials appear here';
    }
    final latest = _cachedCredentials.first;
    final student = latest['student_name']?.toString() ?? 'Student';
    final degree = (latest['degree'] ?? latest['course_or_event'])?.toString();
    return degree == null || degree.isEmpty
        ? 'Latest: $student'
        : 'Latest: $student • $degree';
  }

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
                subtitle: _recentCredentialsSubtitle,
                icon: Icons.history,
                color: Colors.amber.shade800,
                onTap: () =>
                    widget.onViewRecentCredentials(_recentCredentials)),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: Text('Recent Verified',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              tooltip: 'Refresh dashboard activity',
              onPressed: _isRefreshing ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _recentVerifications,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        'Error loading recent verifications: ${snapshot.error}'));
              }
              final verifications = snapshot.data ?? [];
              if (verifications.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                        child: Text(
                            'No credentials have been verified yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey))));
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: verifications.length > 5 ? 5 : verifications.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = verifications[index];
                  final status = item['status'] ?? 'Verified';
                  final verifiedAt = DateTime.tryParse(
                    item['verified_at']?.toString() ?? '',
                  );
                  final timestamp = verifiedAt == null
                      ? 'Recently verified'
                      : verifiedAt.toLocal().toString().substring(0, 16);
                  return ListTile(
                    leading: const Icon(Icons.verified, color: Colors.green),
                    title: Text(
                      item['student_name']?.toString() ??
                          item['recipient_name']?.toString() ??
                          'Unknown student',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item['degree'] ?? item['course_or_event'] ?? 'Credential'}'
                      ' • ${item['university_name'] ?? item['university_code'] ?? ''}'
                      '\n$status • $timestamp',
                    ),
                    isThreeLine: true,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

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
                          fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ])),
          ]),
        ),
      ),
    );
  }
}
