import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class CertificateDeletionRequestsScreen extends StatefulWidget {
  const CertificateDeletionRequestsScreen({super.key});

  @override
  State<CertificateDeletionRequestsScreen> createState() =>
      _CertificateDeletionRequestsScreenState();
}

class _CertificateDeletionRequestsScreenState
    extends State<CertificateDeletionRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _requests;
  final _noteController = TextEditingController();
  bool _isReviewing = false;

  @override
  void initState() {
    super.initState();
    _requests = ApiService.getCertificateDeletionRequests();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final requests = ApiService.getCertificateDeletionRequests();
    setState(() => _requests = requests);
    await requests;
  }

  Future<void> _openConcern(Map<String, dynamic> request) async {
    _noteController.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Deletion request ${request['status']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detail('Student', request['student_name']),
                  _detail('Student ID', request['student_id']),
                  _detail('Google email', request['student_email']),
                  _detail('School', request['university_code']),
                  _detail('Degree', request['degree']),
                  _detail('Credential code', request['certificate_code']),
                  _detail('Requested by', request['requester_name']),
                  const Divider(height: 28),
                  const Text('Subadmin concern',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                      (request['reason']?.toString().trim().isNotEmpty ?? false)
                          ? request['reason'].toString()
                          : 'No reason was provided.'),
                  if (request['reviewer_note'] != null) ...[
                    const SizedBox(height: 12),
                    Text('Decision note: ${request['reviewer_note']}'),
                  ],
                  if (request['status'] == 'pending') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Decision note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                final requesterId = request['requested_by']?.toString();
                if (requesterId != null) {
                  context.push('/ansq?with_user_id=$requesterId');
                }
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Message subadmin'),
            ),
            if (request['status'] == 'pending') ...[
              TextButton(
                onPressed: _isReviewing
                    ? null
                    : () => _review(
                        request, 'rejected', dialogContext, setDialogState),
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: _isReviewing
                    ? null
                    : () => _review(
                        request, 'approved', dialogContext, setDialogState),
                child: _isReviewing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Approve deletion'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _review(
    Map<String, dynamic> request,
    String decision,
    BuildContext dialogContext,
    StateSetter setDialogState,
  ) async {
    setDialogState(() => _isReviewing = true);
    try {
      await ApiService.reviewCertificateDeletionRequest(
        requestId: request['id'].toString(),
        decision: decision,
        reviewerNote: _noteController.text,
      );
      if (!mounted) return;
      Navigator.pop(dialogContext);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(decision == 'approved'
              ? 'Credential deleted. The subadmin was notified in chat.'
              : 'Request rejected. The subadmin was notified in chat.'),
        ),
      );
      await _refresh();
    } catch (error) {
      setDialogState(() => _isReviewing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not review request: $error')),
        );
      }
    }
  }

  Widget _detail(String label, dynamic value) {
    if (value == null || value.toString().isEmpty)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text('$label: $value'),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Credential Deletion Requests')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _requests,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load requests: ${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            final requests = snapshot.data ?? const [];
            if (requests.isEmpty) {
              return const Center(child: Text('No deletion requests yet.'));
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final request = requests[index];
                  final pending = request['status'] == 'pending';
                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                          pending ? Icons.pending_actions : Icons.task_alt),
                    ),
                    title:
                        Text(request['student_name']?.toString() ?? 'Student'),
                    subtitle: Text(
                      'ID: ${request['student_id'] ?? 'N/A'} • ${request['university_code'] ?? 'N/A'}\n'
                      '${request['status'] ?? 'pending'} • Requested by ${request['requester_name'] ?? 'subadmin'}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Read concern and review request',
                      icon: const Icon(Icons.message_outlined),
                      onPressed: () => _openConcern(request),
                    ),
                    onTap: () => _openConcern(request),
                  );
                },
              ),
            );
          },
        ),
      );
}
