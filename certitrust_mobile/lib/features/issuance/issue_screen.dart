import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  String get hash => sha256
      .convert(
          '${studentId.text}|${studentName.text}|${studentEmail.text}|${degree.text}'
              .codeUnits)
      .toString();

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
    final isAdmin = ApiService.authRole == 'admin' ||
        ApiService.authEmail == 'certitrust256@gmail.com';
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
    if (file?.bytes == null || file!.bytes!.isEmpty) return null;
    final name = file.name;
    try {
      await Supabase.instance.client.storage.from('diplomas').uploadBinary(
            name,
            file.bytes!,
            fileOptions: const FileOptions(upsert: true),
          );
      return Supabase.instance.client.storage
          .from('diplomas')
          .getPublicUrl(name);
    } on StorageException catch (error) {
      if (error.statusCode == '404') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Diploma bucket is not configured. Credential will be issued without a file preview.')),
          );
        }
        return null;
      }
      rethrow;
    }
  }

  Future<bool> _validateUniqueConstraints() async {
    final seenNames = <String, String>{}; // normalized name -> student ID
    final seenFileNames =
        <String, String>{}; // file name -> owner's student name
    final existingRecords = await ApiService.getCertificatesForCurrentUser();
    final existingIds = <String>{
      for (final record in existingRecords)
        record['student_id']?.toString().trim() ?? '',
    };
    final existingNames = <String, String>{
      for (final record in existingRecords)
        (record['student_name'] ?? record['recipient_name'] ?? '')
            .toString()
            .trim()
            .toLowerCase(): (record['student_id'] ?? '').toString(),
    };
    final existingFileOwners = <String, String>{};
    for (final record in existingRecords) {
      final url = record['diploma_url']?.toString() ?? '';
      if (url.isNotEmpty) {
        existingFileOwners[url.split('/').last] =
            (record['student_name'] ?? 'the previous student').toString();
      }
    }

    for (int i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      final nameTrimmed = draft.studentName.text.trim().toLowerCase();
      final studentIdTrimmed = draft.studentId.text.trim();
      final fileName = draft.diploma?.name;
      final studentDisplayName = draft.studentName.text.trim().isEmpty
          ? 'Student ${i + 1}'
          : draft.studentName.text.trim();

      if (existingIds.contains(studentIdTrimmed)) {
        _showWarning(
            'Student ID "$studentIdTrimmed" has already been uploaded.');
        return false;
      }
      if (existingNames.containsKey(nameTrimmed)) {
        final proceed = await _showConfirmationDialog(
          'Duplicate Name Detected',
          'The name "${draft.studentName.text.trim()}" is already used by student ID ${existingNames[nameTrimmed]}. Continue with a different Student ID?',
        );
        if (!proceed) return false;
      }

      // Rule 4: Check unique image file name across drafts
      if (fileName != null && fileName.isNotEmpty) {
        if (seenFileNames.containsKey(fileName)) {
          final originalOwner = seenFileNames[fileName];
          _showWarning(
              'Image file name "$fileName" has already been used by $originalOwner.');
          return false;
        }
        if (existingFileOwners.containsKey(fileName)) {
          _showWarning(
              'Image file name "$fileName" has already been used by ${existingFileOwners[fileName]}. Choose a unique file name.');
          return false;
        }
        seenFileNames[fileName] = studentDisplayName;
      }

      // Rule 3: Check duplicate names and IDs
      if (seenNames.containsKey(nameTrimmed)) {
        final existingId = seenNames[nameTrimmed];
        if (existingId == studentIdTrimmed) {
          _showWarning(
              'Student "${draft.studentName.text.trim()}" with ID "$studentIdTrimmed" is duplicated in this batch.');
          return false;
        } else {
          // Same name, different student ID -> Show warning prompt but let it pass via confirmation
          final proceed = await _showConfirmationDialog(
            'Duplicate Name Detected',
            'The name "${draft.studentName.text.trim()}" is already used by a student with ID "$existingId", but has a different Student ID ("$studentIdTrimmed"). Do you want to proceed?',
          );
          if (!proceed) return false;
        }
      } else {
        seenNames[nameTrimmed] = studentIdTrimmed;
      }
    }
    return true;
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  Future<bool> _showConfirmationDialog(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Proceed')),
            ],
          ),
        ) ??
        false;
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Records'),
          BottomNavigationBarItem(icon: Icon(Icons.upload), label: 'Upload'),
          BottomNavigationBarItem(icon: Icon(Icons.verified), label: 'Verify'),
          BottomNavigationBarItem(icon: Icon(Icons.help), label: 'AnsQ'),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.go('/records');
              break;
            case 2:
              break;
            case 3:
              context.go('/verify');
              break;
            case 4:
              context.go('/ansq');
              break;
          }
        },
      ),
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
                    child: SelectableText('SHA-256: ${draft.hash}',
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
