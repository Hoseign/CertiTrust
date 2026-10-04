import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/issuance/issue_screen.dart';
import '../features/qr_scanner/verify_screen.dart';
import '../features/qr_scanner/qr_scanner_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/navigation/role_pages.dart';
import '../features/admin/admin_management_screen.dart';
import '../features/admin/student_access_screen.dart';
import '../features/admin/certificate_deletion_requests_screen.dart';
import '../features/qr_scanner/verification_confirmation_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoggedIn = ApiService.isAuthenticated;

      final isLoggingIn = state.uri.path == '/';
      final isSplash = state.uri.path == '/splash';
      final isVerifying = state.uri.path.startsWith('/verify');
      final isScanning = state.uri.path == '/qr-scanner';
      final isVerificationResult =
          state.uri.path == '/verification-confirmation';
      final freezeContactId = ApiService.frozenByContact?['id']?.toString();
      final frozenChatLocation = freezeContactId == null
          ? '/frozen-chat'
          : '/frozen-chat?with_user_id=${Uri.encodeQueryComponent(freezeContactId)}';

      if (isLoggedIn && ApiService.isAccessFrozen) {
        if (state.uri.path != '/frozen-chat' && !isSplash) {
          return frozenChatLocation;
        }
      }

      // If not logged in and trying to access protected pages, redirect to login
      if (!isLoggedIn &&
          !isLoggingIn &&
          !isVerifying &&
          !isScanning &&
          !isVerificationResult &&
          !isSplash) {
        return '/';
      }

      // Restore an existing Laravel session when the app is opened again.
      if (isLoggedIn && isLoggingIn) {
        return ApiService.isAccessFrozen ? frozenChatLocation : '/dashboard';
      }
      if (isLoggedIn && isSplash && ApiService.isAccessFrozen) {
        return frozenChatLocation;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/admin-management',
        builder: (context, state) => const AdminManagementScreen(),
      ),
      GoRoute(
        path: '/student-access',
        builder: (context, state) => const StudentAccessScreen(),
      ),
      GoRoute(
        path: '/frozen-chat',
        builder: (context, state) => ChatScreen(
          isAdmin: ApiService.authRole == 'admin',
          initialContactId: state.uri.queryParameters['with_user_id'],
          restrictedMode: true,
        ),
      ),
      GoRoute(
        path: '/deletion-requests',
        builder: (context, state) => const CertificateDeletionRequestsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => navigationShell,
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/records',
                builder: (context, state) => const RecordsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/issue',
                builder: (context, state) => IssueScreen(
                  initialRecord: state.extra is Map<String, dynamic>
                      ? state.extra as Map<String, dynamic>
                      : null,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/verify',
                builder: (context, state) => VerifyScreen(
                  certHash: state.uri.queryParameters['hash'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ansq',
                builder: (context, state) => ChatScreen(
                  isAdmin: true,
                  initialContactId: state.uri.queryParameters['with_user_id'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/askq',
                builder: (context, state) => ChatScreen(
                  isAdmin: false,
                  initialContactId: state.uri.queryParameters['with_user_id'],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/qr-scanner',
        builder: (context, state) => const QrScannerScreen(),
      ),
      GoRoute(
        path: '/verification-confirmation',
        builder: (context, state) => VerificationConfirmationScreen(
          certificate: state.extra as Map<String, dynamic>? ?? const {},
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No route defined for ${state.uri.path}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    ),
  );
}
