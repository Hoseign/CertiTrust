library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/api_service.dart';

// TODO: Import your Laravel API service provider
// import '../../services/api_service.dart';

import 'widgets/admin_dashboard_view.dart';
import 'widgets/super_admin_dashboard_view.dart';
import 'widgets/student_dashboard_view.dart';
import 'widgets/all_certificates_modal.dart';

class DashboardScreen extends StatefulWidget {
  final Object? extra;
  const DashboardScreen({super.key, this.extra});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  bool _isLoadingRole = true;
  Map<String, dynamic>? _studentCertificate;
  bool _isLoadingCertificate = false;

  @override
  void initState() {
    super.initState();
    if (widget.extra is Map<String, dynamic>) {
      _studentCertificate = widget.extra as Map<String, dynamic>;
      _isLoadingCertificate = false;
    }
    _checkUserRoleAndFetchData();
  }

  Future<void> _checkUserRoleAndFetchData() async {
    try {
        final isAdminUser = ApiService.authRole == 'admin' || ApiService.isSuperAdmin;

      if (!isAdminUser) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
            _isSuperAdmin = false;
            _isLoadingRole = false;
            if (_studentCertificate == null) {
              _isLoadingCertificate = true;
            }
          });
        }

        final certData = _studentCertificate ??
            await ApiService.getStudentCertificate(email: ApiService.authEmail);

        if (mounted) {
          setState(() {
            _studentCertificate = certData;
            _isLoadingCertificate = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAdmin = true;
            _isSuperAdmin = ApiService.isSuperAdmin;
            _isLoadingRole = false;
          });
        }
      }
    } catch (e) {
      debugPrint(
          'Error checking user role and fetching data from Laravel backend: $e');
      if (mounted) {
        setState(() {
          _isLoadingRole = false;
          _isLoadingCertificate = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLiveCertificates() async {
    return ApiService.getCertificatesForCurrentUser();
  }

  void _showAllCertificatesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          AllCertificatesModal(fetchCertificates: _fetchLiveCertificates),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingRole) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isAdmin) {
      return _isSuperAdmin
          ? _buildSuperAdminScaffold(context)
          : _buildSubadminScaffold(context, theme);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('CertiTrust Dashboard'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [_logoutButton(context)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: theme.colorScheme.primary.withAlpha(26),
                      child: Icon(Icons.school,
                          size: 36, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAdmin
                                ? 'Welcome to ${ApiService.authUniversity ?? 'CertiTrust'} (Admin)'
                                : 'Welcome, Student',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isAdmin
                                ? 'Manage and verify blockchain-anchored academic credentials.'
                                : 'View and verify your official academic credentials.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            StudentDashboardView(
              isLoadingCertificate: _isLoadingCertificate,
              studentCertificate: _studentCertificate,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        items: _isAdmin
            ? const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.folder), label: 'Records'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.upload), label: 'Upload'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.verified), label: 'Verify'),
                BottomNavigationBarItem(icon: Icon(Icons.help), label: 'AnsQ'),
              ]
            : const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.folder), label: 'Records'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.qr_code_scanner), label: 'Verify'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.person), label: 'Profile'),
                BottomNavigationBarItem(icon: Icon(Icons.help), label: 'AskQ'),
              ],
        onTap: (index) {
          final destination = _isAdmin
              ? const ['/dashboard', '/records', '/issue', '/verify', '/ansq']
              : const [
                  '/dashboard',
                  '/records',
                  '/verify',
                  '/profile',
                  '/askq'
                ];
          context.go(destination[index]);
        },
      ),
    );
  }

  Widget _buildSuperAdminScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: _adminAppBar(context, title: 'Super Admin'),
      drawer: _superAdminDrawer(context),
      body: SuperAdminDashboardView(fetchOverview: ApiService.getSuperAdminOverview),
    );
  }

  Widget _buildSubadminScaffold(BuildContext context, ThemeData theme) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('University Admin'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        actions: [
          ValueListenableBuilder<ConnectionSnapshot>(
            valueListenable: ApiService.connectionStatus,
            builder: (context, snapshot, _) => InkWell(
              onTap: () => _showConnectionDiagnostics(context),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: snapshot.isOperational ? Colors.green : Colors.red),
                    const SizedBox(width: 6),
                    Text(snapshot.isOperational ? 'Operational' : 'Offline', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          _logoutButton(context),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE8ECF2)))),
            child: Row(
              children: [
                const Icon(Icons.account_circle_outlined, size: 20, color: Color(0xFF657184)),
                const SizedBox(width: 8),
                Expanded(child: Text(ApiService.authEmail ?? 'University Admin', overflow: TextOverflow.ellipsis)),
                Text(ApiService.authUniversity ?? 'No university scope', style: const TextStyle(color: Color(0xFF657184))),
              ],
            ),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF003366)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Icon(Icons.verified_user, color: Colors.white, size: 34),
                  SizedBox(height: 10),
                  Text('CertiTrust', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('University Admin Console', style: TextStyle(color: Colors.white70)),
                ]),
              ),
              _drawerItem(context, Icons.dashboard_outlined, 'Dashboard', '/dashboard'),
              _drawerItem(context, Icons.upload_file, 'Upload Credentials', '/issue'),
              _drawerItem(context, Icons.verified_outlined, 'Verify Credential', '/verify'),
            ],
          ),
        ),
      ),
      body: AdminDashboardView(
        fetchCertificates: _fetchLiveCertificates,
        onShowAllCertificates: _showAllCertificatesModal,
      ),
    );
  }

  PreferredSizeWidget _adminAppBar(BuildContext context, {required String title}) {
    return AppBar(
      title: Text(title),
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF172033),
      elevation: 0,
      actions: [
        ValueListenableBuilder<ConnectionSnapshot>(
          valueListenable: ApiService.connectionStatus,
          builder: (context, snapshot, _) => InkWell(
            onTap: () => _showConnectionDiagnostics(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Icon(Icons.circle, size: 10, color: snapshot.isOperational ? Colors.green : Colors.red),
                const SizedBox(width: 6),
                Text(snapshot.isOperational ? 'Operational' : 'Offline', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
        _logoutButton(context),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE8ECF2)))),
          child: Row(children: [
            const Icon(Icons.account_circle_outlined, size: 20, color: Color(0xFF657184)),
            const SizedBox(width: 8),
            Expanded(child: Text(ApiService.authEmail ?? 'certitrust256@gmail.com', overflow: TextOverflow.ellipsis)),
            const Text('Global scope', style: TextStyle(color: Color(0xFF657184))),
          ]),
        ),
      ),
    );
  }

  Widget _superAdminDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF003366)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Icon(Icons.verified_user, color: Colors.white, size: 34),
              SizedBox(height: 10),
              Text('CertiTrust', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text('Super Admin Console', style: TextStyle(color: Colors.white70)),
            ]),
          ),
          _drawerItem(context, Icons.dashboard_outlined, 'Dashboard', '/dashboard'),
          _drawerItem(context, Icons.person_add_alt_1, 'Create Subadmin Account', '/admin-management'),
          _drawerItem(context, Icons.manage_search, 'Global Credential Logs', '/dashboard'),
        ]),
      ),
    );
  }

  Widget _drawerItem(BuildContext context, IconData icon, String label, String? route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        if (route != null && route != '/dashboard') context.go(route);
        if (route == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('System settings are coming soon.')));
        }
      },
    );
  }

  Widget _logoutButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Sign Out',
      onPressed: () async {
        await Supabase.instance.client.auth.signOut();
        await ApiService.logout();
        if (context.mounted) context.go('/');
      },
    );
  }

  void _showConnectionDiagnostics(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => ValueListenableBuilder<ConnectionSnapshot>(
        valueListenable: ApiService.connectionStatus,
        builder: (context, snapshot, _) => AlertDialog(
          title: Row(children: [
            Icon(snapshot.isOperational ? Icons.check_circle : Icons.error, color: snapshot.isOperational ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            const Text('System Status'),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(snapshot.isOperational ? 'Operational' : 'Offline', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Uptime: ${snapshot.uptimePercentage.toStringAsFixed(0)}%'),
                if (snapshot.currentError != null) ...[
                  const SizedBox(height: 12),
                  Text(snapshot.currentError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 18),
                const Text('Failure and recovery log', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (snapshot.events.isEmpty) const Text('No connection events recorded.'),
                ...snapshot.events.map((event) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(event.state == ApiConnectionState.operational ? Icons.check : Icons.warning, color: event.state == ApiConnectionState.operational ? Colors.green : Colors.red),
                  title: Text(event.message),
                  subtitle: Text(_formatTimestamp(event.timestamp)),
                )),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => ApiService.checkConnection(), child: const Text('Check now')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
