import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/certitrust_loading_indicator.dart';
import '../../../services/api_service.dart';
import 'diploma_preview.dart';
import 'qr_code_dialog.dart';

class AllCertificatesModal extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> initialCertificates;
  final Future<List<Map<String, dynamic>>> Function() fetchCertificates;

  const AllCertificatesModal({
    super.key,
    required this.initialCertificates,
    required this.fetchCertificates,
  });

  @override
  State<AllCertificatesModal> createState() => _AllCertificatesModalState();
}

class _AllCertificatesModalState extends State<AllCertificatesModal> {
  late Future<List<Map<String, dynamic>>> _certificates;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _certificates = widget.initialCertificates;
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    final refresh = widget.fetchCertificates();
    setState(() {
      _certificates = refresh;
      _isRefreshing = true;
    });
    try {
      await refresh;
    } catch (error) {
      debugPrint('Unable to refresh recent credentials: $error');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _requestDeletion(Map<String, dynamic> credential) async {
    final id = credential['id']?.toString();
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This credential has no record ID.')),
      );
      return;
    }

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request credential deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student: ${credential['student_name'] ?? 'Student'}'),
            Text('Student ID: ${credential['student_id'] ?? 'N/A'}'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Explain why this credential should be deleted',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send),
            label: const Text('Send request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    try {
      await ApiService.requestCertificateDeletion(
        certificateId: id,
        reason: reasonController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request sent to the Super Admin for review.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send deletion request: $error')),
        );
      }
    } finally {
      reasonController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recent Issued Credentials',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh recent credentials',
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CertiTrustLoadingIndicator(size: 18),
                          )
                        : const Icon(Icons.refresh),
                    onPressed: _isRefreshing ? null : _refresh,
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _certificates,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(child: CertiTrustLoadingIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    final credentials = snapshot.data ?? [];
                    if (credentials.isEmpty) {
                      return const Center(
                          child: Text('No recent credentials found.'));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: credentials.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) => _RecentCredentialTile(
                        credential: credentials[index],
                        onRequestDeletion: _requestDeletion,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentCredentialTile extends StatefulWidget {
  final Map<String, dynamic> credential;
  final Future<void> Function(Map<String, dynamic>) onRequestDeletion;

  const _RecentCredentialTile({
    required this.credential,
    required this.onRequestDeletion,
  });

  @override
  State<_RecentCredentialTile> createState() => _RecentCredentialTileState();
}

class _RecentCredentialTileState extends State<_RecentCredentialTile> {
  bool _isExpanded = false;

  String _ordinal(int number) {
    if (number % 100 >= 11 && number % 100 <= 13) return '${number}th';
    return switch (number % 10) {
      1 => '${number}st',
      2 => '${number}nd',
      3 => '${number}rd',
      _ => '${number}th',
    };
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final credential = widget.credential;
    final verificationCode =
        (credential['cert_hash'] ?? credential['certificate_code'])?.toString();
    final diplomaUrl =
        (credential['diploma_url'] ?? credential['cert_image_url'])?.toString();
    final diplomaName =
        'Diploma_${(credential['student_id'] ?? credential['student_name'] ?? 'Student').toString().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.jpg';
    final degree =
        (credential['degree'] ?? credential['course_or_event'])?.toString() ??
            'N/A';
    final degreeNumber =
        int.tryParse(credential['degree_number']?.toString() ?? '') ?? 1;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        onExpansionChanged: (expanded) =>
            setState(() => _isExpanded = expanded),
        leading: const Icon(Icons.school, color: Colors.blue),
        title: Text(
          credential['student_name']?.toString() ?? 'Unknown student',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$degree • ID: ${credential['student_id'] ?? 'N/A'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Get QR Code',
              icon: const Icon(Icons.qr_code, color: Colors.teal),
              onPressed: () => showQRCodeDialog(context, credential),
            ),
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              semanticLabel:
                  _isExpanded ? 'Collapse details' : 'Expand details',
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _detail(
              'Student name', credential['student_name']?.toString() ?? 'N/A'),
          _detail('Student ID', credential['student_id']?.toString() ?? 'N/A'),
          _detail('Course / program', degree),
          _detail('Degree number', _ordinal(degreeNumber)),
          _detail(
              'University',
              credential['university_name']?.toString() ??
                  credential['university_code']?.toString() ??
                  'N/A'),
          _detail(
              'Gmail',
              (credential['student_email'] ?? credential['email'])
                      ?.toString() ??
                  'N/A'),
          _detail('Certificate code',
              credential['certificate_code']?.toString() ?? 'N/A'),
          _detail('Issue date', credential['issue_date']?.toString() ?? 'N/A'),
          _detail('Status', credential['status']?.toString() ?? 'Issued'),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: verificationCode == null || verificationCode.isEmpty
                    ? null
                    : () => context.go(
                        '/verify?hash=${Uri.encodeQueryComponent(verificationCode)}&request=${DateTime.now().microsecondsSinceEpoch}'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verify this record'),
              ),
              TextButton.icon(
                onPressed: diplomaUrl == null || diplomaUrl.isEmpty
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'No diploma image was attached to this credential.'),
                          ),
                        )
                    : () => showDiplomaPreview(
                          context,
                          diplomaUrl,
                          fileName: diplomaName,
                        ),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('View This Diploma'),
              ),
              TextButton.icon(
                onPressed: () => context.push('/issue', extra: credential),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add another degree'),
              ),
              TextButton.icon(
                onPressed: () => widget.onRequestDeletion(credential),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Request deletion'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
