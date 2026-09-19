import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    _googleSignIn = GoogleSignIn(
      clientId: kIsWeb
          ? '839744246515-npnpn8u8urse0emqmt6ag0fscdfdqmsm.apps.googleusercontent.com'
          : null,
      serverClientId: kIsWeb
          ? null
          : '839744246515-npnpn8u8urse0emqmt6ag0fscdfdqmsm.apps.googleusercontent.com',
      scopes: const ['email', 'profile'],
    );
  }

  void _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      await _googleSignIn.signOut();

      final googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      String? idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null && (!kIsWeb || accessToken == null)) {
        throw 'Google Authentication failed. Missing ID Token.';
      }

      // Send Google Token to Laravel Backend for verification & login check
      final authResult = await ApiService.loginWithGoogle(
        idToken: idToken,
        accessToken: accessToken ?? '',
      );

      if (authResult == null || !authResult.containsKey('email')) {
        throw 'Failed to authenticate with Laravel backend. Response: $authResult';
      }

      final email = authResult['email'].toString().trim().toLowerCase();
      final String role = authResult['role'] ?? 'student';
      final bool isRegisteredInCertificates =
          authResult['has_certificate'] ?? false;

      if (!mounted) return;

      // Check if user is Admin or has admin role from Laravel
      bool isAdmin = email == 'certitrust256@gmail.com' || role == 'admin';

      if (isAdmin) {
        context.go('/dashboard');
      } else {
        // LAYER 1 CHECK: Verify if Google Email exists in certificates table via Laravel
        if (!isRegisteredInCertificates) {
          _showErrorDialog(
            'Google Account Warning',
            'Your Google account ($email) is not registered to any certificate record in the system.',
          );
          return;
        }

        // LAYER 2 CHECK: Prompt for Student ID input for security validation
        if (!mounted) return;
        _showStudentIdVerificationDialog(email);
      }
    } catch (e, stackTrace) {
      if (kIsWeb && e.toString().contains('popup_closed')) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      debugPrint('================ GOOGLE SIGN-IN ERROR ================');
      debugPrint('$e');
      debugPrint('$stackTrace');
      debugPrint('======================================================');

      if (mounted) {
        _showErrorDialog(
          'Login Exception Details',
          'Error:\n$e\n\nStackTrace:\n$stackTrace',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStudentIdVerificationDialog(String userEmail) {
    final TextEditingController idController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Security Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logged in as: $userEmail'),
            const SizedBox(height: 12),
            const Text(
                'Please enter your official Student ID to complete security validation:'),
            const SizedBox(height: 16),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                border: OutlineInputBorder(),
                hintText: 'e.g., 20260001',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final studentIdInput = idController.text.trim();
              if (studentIdInput.isEmpty) return;

              try {
                // Call Laravel API to verify Student ID mapping against email
                final verificationResult =
                    await ApiService.verifyStudentIdMapping(
                  email: userEmail,
                  studentId: studentIdInput,
                );

                if (verificationResult == null ||
                    verificationResult['success'] != true) {
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _showErrorDialog(
                    'Student ID Warning',
                    verificationResult?['message'] ??
                        'The Student ID does not match database records.',
                  );
                  return;
                }

                final matchingCert = verificationResult['certificate'];

                if (context.mounted) {
                  Navigator.pop(context);
                  context.go('/dashboard', extra: matchingCert);
                }
              } catch (err) {
                debugPrint('Error verifying Student ID: $err');
                if (context.mounted) {
                  _showErrorDialog('Verification Error', '$err');
                }
              }
            },
            child: const Text('Verify & Proceed'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title,
            style: const TextStyle(
                color: Colors.red, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text(message, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('web/assets/images/certitrustlogo.png',
                    height: 96, fit: BoxFit.contain),
                const SizedBox(height: 16),
                Text(
                  'CertiTrust',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Text(
                  'Blockchain-anchored academic credential verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 48),

                // Unified Sign-In Button for Web and Mobile
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                  icon: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.login, color: Colors.white),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _isLoading ? 'Signing In...' : 'Sign in with Google',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.push('/verify?hash=preview'),
                  child: const Text('Public Certificate Verification'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
