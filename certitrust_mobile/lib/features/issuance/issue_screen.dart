import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/hash_util.dart';
import '../navigation/role_pages.dart';
import '../../services/api_service.dart';

class IssueScreen extends StatefulWidget {
  const IssueScreen({super.key});

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
    final name = file.name;
    try {
      await Supabase.instance.client.storage.from('diplomas').uploadBinary(
            name,
            file.bytes!,
            fileOptions: const FileOptions(upsert: false),
          );
      return Supabase.instance.client.storage
          .from('diplomas')
          .getPublicUrl(name);
    } on StorageException catch (error) {
      if (error.statusCode == '404') {
        throw Exception(
            'The diploma could not be uploaded because the Supabase diplomas bucket was not found. Configure the bucket and try issuing again.');
      }
      throw Exception('The selected diploma could not be uploaded: '
          '${error.message}');
    }
  }

  Future<bool> _validateUniqueConstraints() async {
    final seenNames = <String, Set<String>>{};
    final seenStudentIds = <String, String>{};
    final seenFileNames = <String, String>{};
    final existingRecords = await ApiService.getCertificatesForCurrentUser();
    final existingStudentIds = <String, String>{};
    final existingNames = <String, Set<String>>{};
    final existingFileOwners = <String, String>{};
    for (final record in existingRecords) {
      final owner = _studentOwnerLabel(record);
      final studentId = (record['student_id']?.toString() ?? '').trim();
      if (studentId.isNotEmpty) {
        existingStudentIds.putIfAbsent(studentId.toLowerCase(), () => owner);
      }

      final name = (record['student_name'] ?? record['recipient_name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (name.isNotEmpty) {
        existingNames.putIfAbsent(name, () => <String>{}).add(owner);
      }

      final url = (record['diploma_file_name'] ?? record['diploma_url'])
              ?.toString() ??
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
      final previousIdOwner = existingStudentIds[normalizedStudentId] ??
          seenStudentIds[normalizedStudentId];

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
      await ApiService.checkDiplomaFileNames(
        _drafts
            .map((draft) => draft.diploma?.name ?? '')
            .where((name) => name.isNotEmpty)
            .toList(),
      );
      final records = <Map<String, dynamic>>[];
      for (final draft in _drafts) {
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
        });
      }
      final success = await ApiService.issueBatchCertificates(records);
      if (!success) throw Exception('The server rejected this batch.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${records.length} credential(s) issued successfully.')),
      );
      context.go('/dashboard');
    } catch (error) {
      if (mounted) {
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
