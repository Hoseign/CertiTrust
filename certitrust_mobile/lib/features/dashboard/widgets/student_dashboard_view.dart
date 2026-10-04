import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'qr_code_dialog.dart';
import 'diploma_preview.dart';

class StudentDashboardView extends StatefulWidget {
  final bool isLoadingCertificate;
  final List<Map<String, dynamic>> studentCertificates;

  const StudentDashboardView({
    super.key,
    required this.isLoadingCertificate,
    required this.studentCertificates,
  });

  @override
  State<StudentDashboardView> createState() => _StudentDashboardViewState();
}

class _StudentDashboardViewState extends State<StudentDashboardView> {
  int? _selectedDegreeNumber;
  bool _showMultipleDegrees = false;

  int _degreeNumber(Map<String, dynamic> certificate) =>
      int.tryParse(certificate['degree_number']?.toString() ?? '') ?? 1;

  String _ordinal(int number) {
    if (number % 100 >= 11 && number % 100 <= 13) return '${number}th';
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.isLoadingCertificate) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (widget.studentCertificates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 48, color: Colors.orange),
                SizedBox(height: 16),
                Text(
                  'No Certificate Found',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'No issued academic certificate is currently linked to your student account or email address. Please contact the registrar office if you believe this is an error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final degrees = widget.studentCertificates.map(_degreeNumber).toSet().toList()
      ..sort();
    final multipleAvailable = degrees.length > 1;
    if (_selectedDegreeNumber == null ||
        !degrees.contains(_selectedDegreeNumber)) {
      _selectedDegreeNumber = degrees.first;
    }
    if (!multipleAvailable) _showMultipleDegrees = false;

    final displayedCertificates = _showMultipleDegrees
        ? widget.studentCertificates
        : widget.studentCertificates
            .where((certificate) =>
                _degreeNumber(certificate) == _selectedDegreeNumber)
            .toList();

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your Degrees',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final degreeNumber in degrees)
                  ChoiceChip(
                    label: Text('Your ${_ordinal(degreeNumber)} Degree'),
                    selected:
                        !_showMultipleDegrees &&
                        _selectedDegreeNumber == degreeNumber,
                    onSelected: (_) => setState(() {
                      _showMultipleDegrees = false;
                      _selectedDegreeNumber = degreeNumber;
                    }),
                  ),
                if (multipleAvailable)
                  ChoiceChip(
                    avatar: const Icon(Icons.collections_bookmark_outlined),
                    label: const Text('Your Multiple Degrees'),
                    selected: _showMultipleDegrees,
                    onSelected: (_) => setState(() {
                      _showMultipleDegrees = true;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_showMultipleDegrees)
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'All ${degrees.length} of your degrees and diploma images',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            for (final certificate in displayedCertificates)
              _credentialCard(context, certificate, theme,
                  multipleView: _showMultipleDegrees),
          ],
        ),
      ),
    );
  }

  Widget _credentialCard(
    BuildContext context,
    Map<String, dynamic> certificate,
    ThemeData theme, {
    required bool multipleView,
  }) {
    final diplomaUrl = (certificate['diploma_url'] ??
            certificate['cert_image_url'] ??
            certificate['image_url'])
        ?.toString();
    final studentId = (certificate['student_id'] ?? 'Student')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final verificationHash = (certificate['cert_hash'] ??
            certificate['ipfs_hash'] ??
            certificate['hash'] ??
            certificate['certificate_code'])
        ?.toString();
    final degreeNumber = _degreeNumber(certificate);
    final status = certificate['status']?.toString() ?? 'Verified';

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    multipleView
                        ? 'Your ${_ordinal(degreeNumber)} Degree'
                        : 'Credential Status',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(status),
                  backgroundColor: Colors.green.shade50,
                  labelStyle:
                      const TextStyle(color: Colors.green, fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Divider(height: 28),
            _detailRow(
              'Student Name',
              certificate['student_name']?.toString() ??
                  certificate['name']?.toString() ??
                  'N/A',
            ),
            const SizedBox(height: 10),
            _detailRow('Student ID', certificate['student_id']?.toString() ?? 'N/A'),
            const SizedBox(height: 10),
            _detailRow(
              'Degree / Program',
              certificate['degree']?.toString() ??
                  certificate['program']?.toString() ??
                  'N/A',
            ),
            const SizedBox(height: 10),
            _detailRow(
              'Email',
              certificate['student_email']?.toString() ??
                  certificate['email']?.toString() ??
                  'N/A',
            ),
            const SizedBox(height: 10),
            _detailRow(
              'Issue Date',
              certificate['issue_date']?.toString() ??
                  certificate['created_at']?.toString() ??
                  'N/A',
            ),
            if (diplomaUrl != null && diplomaUrl.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Digital Diploma Copy:',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => showDiplomaPreview(
                  context,
                  diplomaUrl,
                  fileName: 'Diploma_$studentId-degree$degreeNumber.jpg',
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    color: Colors.grey.shade200,
                    child: Image.network(
                      diplomaUrl,
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
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onPressed: () => showQRCodeDialog(context, certificate),
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Get QR Code'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onPressed:
                      verificationHash == null || verificationHash.isEmpty
                          ? null
                          : () => context.push(
                              '/verify?hash=${Uri.encodeQueryComponent(verificationHash)}'),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Verify on Chain'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      );
}
