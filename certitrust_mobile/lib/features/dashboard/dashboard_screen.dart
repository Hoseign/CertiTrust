library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/api_service.dart';

// TODO: Import your Laravel API service provider
// import '../../services/api_service.dart';

import 'widgets/admin_dashboard_view.dart';
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
      final isAdminUser = ApiService.authRole == 'admin' ||
          ApiService.authEmail == 'certitrust256@gmail.com' ||
          ApiService.authEmail == 'randygonzales2024@gmail.com';

      if (!isAdminUser) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
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

    return Scaffold(
      backgroundColor: _isAdmin ? theme.scaffoldBackgroundColor : Colors.white,
      appBar: AppBar(
        title: const Text('CertiTrust Dashboard'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              await ApiService.logout();
              if (context.mounted) {
                context.go('/');
              }
            },
          ),
        ],
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
            if (!_isAdmin)
              StudentDashboardView(
                isLoadingCertificate: _isLoadingCertificate,
                studentCertificate: _studentCertificate,
              )
            else
              AdminDashboardView(
                fetchCertificates: _fetchLiveCertificates,
                onShowAllCertificates: _showAllCertificatesModal,
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
          if (index != 0) context.go(destination[index]);
        },
      ),
    );
  }
}
