import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/utils/hash_util.dart';
import '../navigation/role_pages.dart';
import '../../services/api_service.dart';

class IssueScreen extends StatefulWidget {
  const IssueScreen({super.key, this.initialRecord});

  final Map<String, dynamic>? initialRecord;

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _CredentialDraft {
  final studentId = TextEditingController();
  final studentName = TextEditingController();
  final studentEmail = TextEditingController();
  final degree = TextEditingController();
  String school = ApiService.authUniversity ?? 'UCU';
  PlatformFile? diploma;
  bool isAdditionalDegree = false;
  int? degreeNumber;

  String get hash => HashUtil.generateCredentialHash(
        studentId: studentId.text,
        studentName: studentName.text,
        studentEmail: studentEmail.text,
        degree: degree.text,
        universityCode: school,
        documentBytes: diploma?.bytes,
      );

  void dispose() {
    studentId.dispose();
    studentName.dispose();
    studentEmail.dispose();
    degree.dispose();
  }
}

class _IssueScreenState extends State<IssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<_CredentialDraft> _drafts = [];
  bool _isLoadingAdminCheck = true;
  bool _isAdmin = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    if (record != null) {
      final draft = _CredentialDraft()
        ..studentId.text = record['student_id']?.toString() ?? ''
        ..studentName.text = (record['student_name'] ??
                record['recipient_name'] ??
                '')
            .toString()
        ..studentEmail.text =
            (record['student_email'] ?? record['email'] ?? '')
                .toString()
        ..school = record['university_code']?.toString() ??
            ApiService.authUniversity ??
            'UCU';
      _drafts.add(draft);
    }
    _verifyAdminAccess();
  }

  Future<void> _verifyAdminAccess() async {
    final isAdmin = ApiService.authRole == 'admin' && !ApiService.isSuperAdmin;
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
        _isLoadingAdminCheck = false;
      });
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDiploma(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _drafts[index].diploma = result.files.first);
    }
  }

  void _addDraft() => setState(() => _drafts.add(_CredentialDraft()));

  void _removeDraft(int index) {
    final draft = _drafts.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  Future<String?> _uploadDiploma(_CredentialDraft draft) async {
    final file = draft.diploma;
    if (file == null) return null;
    if (file.bytes == null || file.bytes!.isEmpty) {
      throw Exception('The selected diploma file could not be read.');
    }
    final uploaded = await ApiService.uploadDiploma(
      fileBytes: file.bytes!,
      fileName: file.name,
    );
    final url = uploaded['diploma_url']?.toString();
    if (url == null || url.isEmpty) {
      throw StateError('The backend did not return a diploma URL.');
    }
    return url;
  }

  Future<bool> _validateUniqueConstraints() async {
    final seenNames = <String, Set<String>>{};
    final seenStudentIds = <String, String>{};
    final seenFileNames = <String, String>{};
    final existingRecords = await ApiService.getCertificatesForCurrentUser();
    final existingNames = <String, Set<String>>{};
    final existingFileOwners = <String, String>{};
    for (final record in existingRecords) {
      final owner = _studentOwnerLabel(record);
      final name = (record['student_name'] ?? record['recipient_name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (name.isNotEmpty) {
        existingNames.putIfAbsent(name, () => <String>{}).add(owner);
      }

      final url =
          (record['diploma_file_name'] ?? record['diploma_url'])?.toString() ??
              '';
      if (url.isNotEmpty) {
        existingFileOwners.putIfAbsent(
            _normalizeDiplomaFileName(url), () => owner);
      }
    }

    for (int i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      final nameTrimmed = draft.studentName.text.trim().toLowerCase();
      final studentIdTrimmed = draft.studentId.text.trim();
      final normalizedStudentId = studentIdTrimmed.toLowerCase();
      final fileName = draft.diploma?.name;
      final studentDisplayName = draft.studentName.text.trim().isEmpty
          ? 'Student ${i + 1}'
          : draft.studentName.text.trim();
      final draftOwner = '$studentDisplayName (Student ID $studentIdTrimmed)';
      final previousIdOwner = seenStudentIds[normalizedStudentId];

      if (previousIdOwner != null) {
        _showWarning('Student ID "$studentIdTrimmed" already belongs to '
            '$previousIdOwner. Enter a unique Student ID.');
        return false;
      }
      final nameOwners = <String>{
        ...existingNames[nameTrimmed] ?? const <String>{},
        ...seenNames[nameTrimmed] ?? const <String>{},
      };
      if (nameOwners.isNotEmpty) {
        _showWarning(
            'The name "${draft.studentName.text.trim()}" already belongs to ${nameOwners.join(', ')}. Same-name students are allowed; issuance will continue.');
      }
      seenStudentIds[normalizedStudentId] = draftOwner;

      // Rule 4: Check unique image file name across drafts
      if (fileName != null && fileName.isNotEmpty) {
        final normalizedFileName = _normalizeDiplomaFileName(fileName);
        final previousFileOwner = existingFileOwners[normalizedFileName] ??
            seenFileNames[normalizedFileName];
        if (previousFileOwner != null) {
          _showWarning('Diploma image "$fileName" already belongs to '
              '$previousFileOwner. Choose another image file.');
          return false;
        }
        seenFileNames[normalizedFileName] = draftOwner;
      }

      seenNames.putIfAbsent(nameTrimmed, () => <String>{}).add(draftOwner);
    }
    return true;
  }

  String _studentOwnerLabel(Map<String, dynamic> record) {
    final name =
        (record['student_name'] ?? record['recipient_name'] ?? 'Student')
            .toString()
            .trim();
    final studentId = record['student_id']?.toString().trim() ?? '';
    return studentId.isEmpty ? name : '$name (Student ID $studentId)';
  }

  String _normalizeDiplomaFileName(String value) {
    final uri = Uri.tryParse(value);
    final fileName = uri?.hasScheme == true && uri?.hasAuthority == true
        ? uri!.pathSegments.last
        : value.replaceAll('\\', '/').split('/').last;
    return fileName.trim().toLowerCase();
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  Map<String, dynamic> _validationRecord(_CredentialDraft draft) => {
        'student_id': draft.studentId.text.trim(),
        'student_name': draft.studentName.text.trim(),
        'student_email': draft.studentEmail.text.trim().toLowerCase(),
        'diploma_file_name': draft.diploma?.name,
        'additional_degree': draft.isAdditionalDegree,
        'degree_number': draft.degreeNumber,
      };

  Future<bool> _confirmAdditionalDegree(
    Map<String, dynamic> candidate,
  ) async {
    final nextDegree = candidate['next_degree_number'] as int;
    final previousDegrees =
        List<Map<String, dynamic>>.from(candidate['existing_degrees'] as List);
    final previousText = previousDegrees
        .map((degree) =>
            '${_ordinal(degree['degree_number'] as int)}: ${degree['degree']}')
        .join('\n');
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text('Is this the student’s ${_ordinal(nextDegree)} degree?'),
            content: Text(
              '${candidate['student_name']} (ID ${candidate['student_id']}) already has:\n'
              '$previousText\n\n'
              'Issue "${_drafts[candidate['draft_index'] as int].degree.text.trim()}" as their ${_ordinal(nextDegree)} degree?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Issue ${_ordinal(nextDegree)} degree'),
              ),
            ],
          ),
        ) ??
        false;
  }

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

  Future<void> _issueBatch() async {
    if (_drafts.isEmpty) {
      _showWarning('Please add at least one student before issuing.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Run custom duplicate validations before proceeding
    final isValid = await _validateUniqueConstraints();
    if (!isValid) return;

    setState(() => _isProcessing = true);
    try {
      var activeDrafts = List<_CredentialDraft>.from(_drafts);
      var validation = await ApiService.validateBatchIssuance(
        activeDrafts.map(_validationRecord).toList(),
      );
      final candidates = List<Map<String, dynamic>>.from(
        validation['additional_degree_candidates'] as List? ?? const [],
      );
      final skippedDrafts = <_CredentialDraft>{};
      for (final candidate in candidates) {
        final index = candidate['draft_index'] as int;
        final draft = activeDrafts[index];
        final confirmed = await _confirmAdditionalDegree(candidate);
        if (!mounted) return;
        if (confirmed) {
          draft.isAdditionalDegree = true;
          draft.degreeNumber = candidate['next_degree_number'] as int;
        } else {
          skippedDrafts.add(draft);
        }
      }
      activeDrafts =
          activeDrafts.where((draft) => !skippedDrafts.contains(draft)).toList();
      if (activeDrafts.isEmpty) {
        _showWarning('No credentials were issued.');
        return;
      }
      validation = await ApiService.validateBatchIssuance(
        activeDrafts.map(_validationRecord).toList(),
      );
      final validationWarnings = List<String>.from(
        validation['warnings'] as List? ?? const [],
      );
      final records = <Map<String, dynamic>>[];
      for (final draft in activeDrafts) {
        records.add({
          'student_id': draft.studentId.text.trim(),
          'student_name': draft.studentName.text.trim(),
          'student_email': draft.studentEmail.text.trim().toLowerCase(),
          'degree': draft.degree.text.trim(),
          'university_code': draft.school,
          'issue_date': DateTime.now().toIso8601String().split('T').first,
          'cert_hash': draft.hash,
          'diploma_file_name': draft.diploma?.name,
          'diploma_url': await _uploadDiploma(draft),
          'additional_degree': draft.isAdditionalDegree,
          'degree_number': draft.degreeNumber ?? 1,
        });
      }
      final success = await ApiService.issueBatchCertificates(records);
      if (!success) throw Exception('The server rejected this batch.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              validationWarnings.isEmpty ? null : Colors.orange.shade800,
          content: Text(
            validationWarnings.isEmpty
                ? '${records.length} credential(s) issued successfully.'
                : '${records.length} credential(s) issued. ${validationWarnings.join(' ')}',
          ),
        ),
      );
      context.go('/dashboard');
    } catch (error) {
      if (mounted) {
        if (error is ApiRequestException &&
            (error.statusCode == 409 || error.statusCode == 422)) {
          _showWarning(error.message);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Issuance failed: $error'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label' : null;

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAdminCheck) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Issue Academic Credentials')),
        body: const Center(child: Text('Administrator access is required.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Issue Academic Credentials'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/dashboard')),
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text('Credential batch',
                            style: Theme.of(context).textTheme.headlineSmall)),
                    FilledButton.icon(
                        onPressed: _addDraft,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Add student')),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                    'Add students, review every credential and QR payload, then submit the batch once.'),
                const SizedBox(height: 20),
                if (_drafts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No students added yet. Click "Add student" above to start uploading.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ...List.generate(
                    _drafts.length, (index) => _buildDraftCard(index)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isProcessing ? null : _issueBatch,
                  icon: _isProcessing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                  label: Text(_isProcessing
                      ? 'Issuing credentials...'
                      : 'Review and issue ${_drafts.length} credential(s)'),
                  style:
                      FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const RoleBottomNavigationBar(isAdmin: true),
    );
  }

  Widget _buildDraftCard(int index) {
    final draft = _drafts[index];
    InputDecoration decoration(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Student ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  onPressed: () => _removeDraft(index),
                  icon: const Icon(Icons.delete_outline)),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _field(draft.studentId, decoration('Student ID', Icons.badge)),
                _field(
                    draft.studentName, decoration('Full name', Icons.person)),
                _field(draft.studentEmail,
                    decoration('Google/institutional email', Icons.email),
                    email: true),
                _field(
                    draft.degree, decoration('Degree / program', Icons.school)),
                _schoolField(draft),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _pickDiploma(index),
              icon: const Icon(Icons.attach_file),
              label: Text(draft.diploma?.name ?? 'Attach diploma (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: SelectableText(
                        'SHA-256 of ${draft.diploma?.bytes?.isNotEmpty == true ? 'document' : 'credential details'}: ${draft.hash}',
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace'))),
                QrImageView(data: draft.hash, size: 76),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, InputDecoration decoration,
      {bool email = false}) {
    return SizedBox(
      width: 430,
      child: TextFormField(
        controller: controller,
        keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
        decoration: decoration,
        validator: (value) {
          final required = _required(value, decoration.labelText ?? 'value');
          if (required != null) return required;
          if (email && !(value!.contains('@'))) return 'Enter a valid email';
          return null;
        },
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _schoolField(_CredentialDraft draft) {
    return SizedBox(
      width: 430,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'University/School',
          prefixIcon: Icon(Icons.account_balance),
          border: OutlineInputBorder(),
        ),
        child: Text(draft.school),
      ),
    );
  }
}
