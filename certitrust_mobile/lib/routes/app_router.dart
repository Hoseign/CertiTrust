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

      // If not logged in and trying to access protected pages, redirect to login
      if (!isLoggedIn &&
          !isLoggingIn &&
          !isVerifying &&
          !isScanning &&
          !isSplash) {
        return '/';
      }

      // Restore an existing Laravel session when the app is opened again.
      if (isLoggedIn && isLoggingIn) {
        return '/dashboard';
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
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/admin-management',
        builder: (context, state) => const AdminManagementScreen(),
      ),
      GoRoute(
        path: '/issue',
        builder: (context, state) => const IssueScreen(),
      ),
      GoRoute(
        path: '/verify',
        builder: (context, state) {
          final hash = state.uri.queryParameters['hash'];
          return VerifyScreen(certHash: hash);
        },
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
      GoRoute(
          path: '/records', builder: (context, state) => const RecordsScreen()),
      GoRoute(
          path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(
          path: '/ansq',
          builder: (context, state) => const ChatScreen(isAdmin: true)),
      GoRoute(
          path: '/askq',
          builder: (context, state) => const ChatScreen(isAdmin: false)),
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
