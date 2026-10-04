import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/api_service.dart';

const String kGoogleWebClientId =
    '839744246515-npnpn8u8urse0emqmt6ag0fscdfdqmsm.apps.googleusercontent.com';

// The Android OAuth client is a separate Google Cloud credential.
// For Flutter Google Sign-In on Android, the backend validation token is usually
// checked against the web client ID used in serverClientId.
const String kGoogleAndroidClientId =
    '839744246515-j4fdm4gro5nsp1lo9ike43jfdnruecc3.apps.googleusercontent.com';

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
      clientId: kIsWeb ? kGoogleWebClientId : null,
      serverClientId: kIsWeb ? null : kGoogleWebClientId,
      scopes: const ['email', 'profile'],
    );
  }

  void _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    String? signedInEmail;

    try {
      await ApiService.logout();
      await _googleSignIn.signOut();

      final googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      String? idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null && accessToken == null) {
        throw 'Google Authentication failed. Missing Google token payload.';
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
      signedInEmail = email;
      final String role = authResult['role'] ?? 'student';
      final bool isRegisteredInCertificates =
          authResult['has_certificate'] ?? false;

      if (!mounted) return;
      if (authResult['access_frozen'] == true) {
        await _showFrozenAccessDialog(authResult);
        return;
      }

      // Check if user is Admin or has admin role from Laravel
      bool isAdmin = email == 'certitrust256@gmail.com' || role == 'admin';

      if (isAdmin) {
        if (!mounted) return;
        context.go('/dashboard');
        return;
      }

      if (!isRegisteredInCertificates) {
        if (mounted) {
          _showWarningDialog(
            'Google Account Warning',
            'This Google account ($email) is not registered to any certificate record in the system. Please use a registered student or admin account.',
          );
        }
        return;
      }

      if (!mounted) return;
      _showStudentIdVerificationDialog(email);
    } catch (e, stackTrace) {
      if (kIsWeb && e.toString().contains('popup_closed')) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (e is ApiRequestException) {
        final isAccountWarning =
            e.statusCode == 403 || e.statusCode == 401 || e.statusCode == 422;
        final lowerMessage = e.message.toLowerCase();
        final isUnregisteredAccount = isAccountWarning ||
            lowerMessage.contains('not registered') ||
            lowerMessage.contains('wrong account') ||
            lowerMessage.contains('not found') ||
            lowerMessage.contains('invalid google') ||
            lowerMessage.contains('authentication failed');

        if (isUnregisteredAccount) {
          await ApiService.logout();
          if (mounted) {
            _showWarningDialog(
              'Google Account Warning',
              signedInEmail == null
                  ? e.message
                  : 'Your Google account ($signedInEmail) is not registered in CertiTrust yet. Please sign in with a valid registered account.',
            );
          }
          return;
        }
      }

      debugPrint('Google sign-in failed: $e');
      debugPrint('$stackTrace');

      if (mounted) {
        _showErrorDialog(
          'Sign-In Failed',
          _signInErrorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showFrozenAccessDialog(
      Map<String, dynamic> authResult) async {
    final contact = authResult['freeze_contact'] is Map
        ? Map<String, dynamic>.from(authResult['freeze_contact'] as Map)
        : null;
    final contactName =
        contact?['name']?.toString() ?? 'the administrator who froze it';
    final message = authResult['message']?.toString() ??
        'Your account is frozen. Contact $contactName to resolve the issue.';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account access frozen'),
        content: Text(
          '$message\n\nYou can only use the support chat with $contactName until access is restored. Your conversation history will remain available.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Okay'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final contactId = contact?['id']?.toString();
    final location = contactId == null
        ? '/frozen-chat'
        : '/frozen-chat?with_user_id=${Uri.encodeQueryComponent(contactId)}';
    context.go(location);
  }

  String _signInErrorMessage(Object error) {
    if (error is ApiRequestException) {
      return 'The API rejected the sign-in request (${error.statusCode}).\n\n${error.message}';
    }
    return 'We could not complete Google sign-in.\n\n${error.toString()}\n\nAPI: ${ApiService.baseUrl}';
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
                final profile =
                    verificationResult['profile'] as Map<String, dynamic>? ??
                        {};
                final hasProfile = (profile['profile_image_url']
                            ?.toString()
                            .isNotEmpty ??
                        false) ||
                    (profile['profile_icon']?.toString().isNotEmpty ?? false);

                if (context.mounted) {
                  Navigator.pop(context);
                  if (hasProfile) {
                    context.go('/dashboard', extra: matchingCert);
                  } else {
                    await _showStudentProfileSetup(matchingCert);
                  }
                }
              } catch (err) {
                debugPrint('Error verifying Student ID: $err');
                if (context.mounted) {
                  if (err is ApiRequestException &&
                      (err.statusCode == 404 || err.statusCode == 422)) {
                    Navigator.of(context).pop();
                    _showWarningDialog(
                      'Student ID Warning',
                      err.message,
                    );
                  } else {
                    final message = err is ApiRequestException
                        ? err.message
                        : err.toString();
                    _showErrorDialog('Verification Error', message);
                  }
                }
              }
            },
            child: const Text('Verify & Proceed'),
          ),
        ],
      ),
    );
  }

  Future<void> _showStudentProfileSetup(dynamic matchingCertificate) async {
    PlatformFile? selectedPhoto;
    String? selectedIcon;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set up your profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose a profile photo or an avatar icon.'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    selected: selectedIcon == 'girl',
                    avatar: const Icon(Icons.face_3_rounded),
                    label: const Text('Girl'),
                    onSelected: (_) => setDialogState(() {
                      selectedIcon = 'girl';
                      selectedPhoto = null;
                    }),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    selected: selectedIcon == 'boy',
                    avatar: const Icon(Icons.face_rounded),
                    label: const Text('Boy'),
                    onSelected: (_) => setDialogState(() {
                      selectedIcon = 'boy';
                      selectedPhoto = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        if (result?.files.single.bytes != null) {
                          setDialogState(() {
                            selectedPhoto = result!.files.single;
                            selectedIcon = null;
                          });
                        }
                      },
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(selectedPhoto?.name ?? 'Choose from gallery'),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed:
                  saving || (selectedPhoto == null && selectedIcon == null)
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            await ApiService.updateProfile(
                              profileIcon: selectedIcon,
                              imageBytes: selectedPhoto?.bytes,
                              imageName: selectedPhoto?.name,
                            );
                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            this
                                .context
                                .go('/dashboard', extra: matchingCertificate);
                          } catch (error) {
                            setDialogState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Could not save profile: $error')),
                              );
                            }
                          }
                        },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save and continue'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWarningDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title,
            style: const TextStyle(
                color: Colors.orange, fontWeight: FontWeight.bold)),
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
