import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Fixed absolute package imports to resolve path errors (pointing directly to /services/)
import 'package:certitrust_mobile/features/dashboard/widgets/qr_code_dialog.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/diploma_download.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/diploma_preview.dart';
import '../navigation/role_pages.dart';
import '../../services/api_service.dart';

class VerifyScreen extends StatefulWidget {
  final String? certHash;

  const VerifyScreen({super.key, this.certHash});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _hashController = TextEditingController();
  bool _isVerifying = false;
  bool _isDownloading = false;
  Map<String, dynamic>? _certResult;
  bool _hasSearched = false;
  int _verificationAttempt = 0;

  @override
  void initState() {
    super.initState();
    if (widget.certHash != null && widget.certHash!.isNotEmpty) {
      _hashController.text = widget.certHash!;
    }
  }

  @override
  void didUpdateWidget(covariant VerifyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.certHash != oldWidget.certHash) {
      _verificationAttempt++;
      _hashController.text = widget.certHash ?? '';
      _certResult = null;
      _hasSearched = false;
      _isVerifying = false;
    }
  }

  @override
  void dispose() {
    _hashController.dispose();
    super.dispose();
  }

  Future<void> _verifyHash(String hash) async {
    if (hash.trim().isEmpty) {
      return;
    }

    final attempt = ++_verificationAttempt;
    setState(() {
      _isVerifying = true;
      _hasSearched = true;
      _certResult = null;
    });

    try {
      final result = await ApiService.getCertificateByCode(hash.trim());

      if (mounted && attempt == _verificationAttempt) {
        setState(() {
          _certResult = result;
          _isVerifying = false;
        });
        if (result != null &&
            (result['multi_degree'] == true ||
                _isCertificateVerified(result))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && attempt == _verificationAttempt) {
              context.push('/verification-confirmation', extra: result);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error verifying hash: $e');
      if (mounted && attempt == _verificationAttempt) {
        setState(() {
          _certResult = null;
          _isVerifying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Verification failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _isCertificateVerified(Map<String, dynamic> certificate) {
    final degrees = certificate['certificates'];
    if (certificate['multi_degree'] == true && degrees is List) {
      return degrees.isNotEmpty &&
          degrees.every((degree) =>
              degree is Map<String, dynamic> &&
              _isSingleCertificateVerified(degree));
    }
    return _isSingleCertificateVerified(certificate);
  }

  bool _isSingleCertificateVerified(Map<String, dynamic> certificate) {
    final status = certificate['status']?.toString().trim().toLowerCase();
    return status == 'verified' || status == 'valid';
  }

  Future<void> _downloadDiploma(String imageUrl) async {
    setState(() => _isDownloading = true);
    try {
      final studentId = _certResult?['student_id']?.toString().replaceAll(
                RegExp(r'[^A-Za-z0-9_-]'),
                '_',
              ) ??
          'Student';
      await downloadDiplomaImage(
        imageUrl,
        fileName: 'Diploma_$studentId.jpg',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Diploma downloaded. Check your Downloads or gallery.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error downloading image: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate Verification'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: theme.colorScheme.primary.withAlpha(15),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                        color: theme.colorScheme.primary.withAlpha(50)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.gavel,
                            color: theme.colorScheme.primary, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            ApiService.authUniversity == null
                                ? 'Verify official academic credentials anchored on the Polygon blockchain.'
                                : 'Verify official ${ApiService.authUniversity} academic credentials anchored on the Polygon blockchain.',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _hashController,
                  decoration: InputDecoration(
                    labelText: 'Certificate or shared-degree code',
                    hintText: 'Enter a certificate code or scan its QR',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.camera_alt),
                          tooltip: 'Scan another QR code',
                          onPressed: () async {
                            final scanned =
                                await context.push<String>('/qr-scanner');
                            if (scanned != null && mounted) {
                              _hashController.text = scanned;
                              setState(() {
                                _certResult = null;
                                _hasSearched = false;
                              });
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Verify record',
                          onPressed: () => _verifyHash(_hashController.text),
                        ),
                      ],
                    ),
                  ),
                  onSubmitted: (value) => _verifyHash(value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isVerifying
                            ? null
                            : () => _verifyHash(_hashController.text),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Verify Record'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                if (_isVerifying)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_hasSearched && _certResult != null)
                  _buildResultCard(theme)
                else if (_hasSearched && _certResult == null)
                  const Card(
                    color: Colors.redAccent,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No record found matching this SHA-256 hash. The certificate may be invalid or forged.',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        isAdmin: ApiService.authRole == 'admin',
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final imageUrl = _certResult!['diploma_url'] ??
        _certResult!['cert_image_url'] ??
        _certResult!['image_url'];
    final certHash = _certResult!['cert_hash'] ?? _certResult!['hash'] ?? '';
    final studentId = _certResult!['student_id']?.toString().replaceAll(
              RegExp(r'[^A-Za-z0-9_-]'),
              '_',
            ) ??
        'Student';

    final isVerified = _isCertificateVerified(_certResult!);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isVerified ? Icons.verified : Icons.info_outline,
                  color: isVerified ? Colors.green : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  isVerified
                      ? 'AUTHENTIC CREDENTIAL'
                      : 'CREDENTIAL FOUND - NOT VERIFIED',
                  style: TextStyle(
                    color: isVerified
                        ? Colors.green.shade800
                        : Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildDetailRow(
                'Student Name', _certResult!['student_name'] ?? 'N/A'),
            _buildDetailRow('Degree/Program', _certResult!['degree'] ?? 'N/A'),
            _buildDetailRow('Issue Date', _certResult!['issue_date'] ?? 'N/A'),
            _buildDetailRow(
                'Verification Status', _certResult!['status'] ?? 'Verified'),
            if (imageUrl != null && imageUrl.toString().isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Credential Export Options:',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isDownloading
                          ? null
                          : () => _downloadDiploma(imageUrl),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Save Diploma'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showQRCodeDialog(context, _certResult!),
                      icon: const Icon(Icons.qr_code, size: 16),
                      label: const Text('Get QR Code'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showDiplomaPreview(
                    context,
                    imageUrl.toString(),
                    fileName: 'Diploma_$studentId.jpg',
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View attached diploma'),
                ),
              ),
              GestureDetector(
                onTap: () => showDiplomaPreview(
                  context,
                  imageUrl.toString(),
                  fileName: 'Diploma_$studentId.jpg',
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    color: Colors.grey.shade200,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                        child: Text('Could not load image preview'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SelectableText(
              'Hash: $certHash',
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
