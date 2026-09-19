import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

// Fixed absolute package imports to resolve path errors (pointing directly to /services/)
import 'package:certitrust_mobile/features/dashboard/widgets/qr_code_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.certHash != null && widget.certHash!.isNotEmpty) {
      _hashController.text = widget.certHash!;
      _verifyHash(widget.certHash!);
    }
  }

  @override
  void dispose() {
    _hashController.dispose();
    super.dispose();
  }

  void _verifyHash(String hash) async {
    if (hash.trim().isEmpty) {
      return;
    }

    setState(() {
      _isVerifying = true;
      _hasSearched = true;
      _certResult = null;
    });

    try {
      final result = await ApiService.getCertificateByCode(hash.trim());

      if (mounted) {
        setState(() {
          _certResult = result;
          _isVerifying = false;
        });
        if (result != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.push('/verification-confirmation', extra: result);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error verifying hash: $e');
      if (mounted) {
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

  Future<void> _downloadDiploma(String imageUrl) async {
    setState(() => _isDownloading = true);
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final result = await ImageGallerySaverPlus.saveImage(
          response.bodyBytes,
          quality: 100,
          name:
              "${ApiService.authUniversity ?? 'CertiTrust'}_Diploma_${DateTime.now().millisecondsSinceEpoch}",
        );

        if (mounted) {
          final isSuccess = result != null &&
              (result['isSuccess'] == true || result['filePath'] != null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isSuccess
                  ? 'Diploma saved successfully to your gallery!'
                  : 'Failed to save diploma image.'),
              backgroundColor: isSuccess ? Colors.green : Colors.red,
            ),
          );
        }
      } else {
        throw Exception('Failed to download image');
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
                    labelText: 'SHA-256 Certificate Hash',
                    hintText: 'Enter 64-character hash string or scan QR',
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
                              _verifyHash(scanned);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.search),
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
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final imageUrl = _certResult!['diploma_url'] ??
        _certResult!['cert_image_url'] ??
        _certResult!['image_url'];
    final certHash = _certResult!['cert_hash'] ?? _certResult!['hash'] ?? '';

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
                const Icon(Icons.verified, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                Text(
                  'AUTHENTIC CREDENTIAL',
                  style: TextStyle(
                    color: Colors.green.shade800,
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
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppBar(
                            title: const Text('Digital Diploma Copy'),
                            automaticallyImplyLeading: false,
                            actions: [
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          Flexible(
                            child: InteractiveViewer(
                              child: Image.network(imageUrl),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    color: Colors.grey.shade200,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
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
