import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/widgets/certitrust_loading_indicator.dart';
import '../../core/utils/hash_util.dart';
import '../../core/utils/academic_degree.dart';
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
  String school = ApiService.authUniversity ?? '';
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
  static const _recordsBranchIndex = 1;
  final _formKey = GlobalKey<FormState>();
  final List<_CredentialDraft> _drafts = [];
  static const _degreeSuggestions = AcademicDegree.programSuggestions;
  bool _isLoadingAdminCheck = true;
  bool _isAdmin = false;
  bool _isProcessing = false;
  List<Map<String, dynamic>> _universities = [];
  String? _selectedUniversityCode;
  String? _universityLoadError;
  bool get _isSuperAdmin => ApiService.isSuperAdmin;
  String? get _issuanceUniversityCode =>
      _isSuperAdmin ? _selectedUniversityCode : ApiService.authUniversity;

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    if (record != null) {
      final draft = _CredentialDraft()
        ..studentId.text = record['student_id']?.toString() ?? ''
        ..studentName.text =
            (record['student_name'] ?? record['recipient_name'] ?? '')
                .toString()
        ..studentEmail.text =
            (record['student_email'] ?? record['email'] ?? '').toString()
        ..school = record['university_code']?.toString() ??
            ApiService.authUniversity ??
            'UCU';
      _drafts.add(draft);
    }
    _verifyAdminAccess();
  }

  Future<void> _verifyAdminAccess() async {
    final isAdmin = ApiService.authRole == 'admin';
    if (mounted) {
      setState(() {
        _isLoadingAdminCheck = true;
        _universityLoadError = null;
      });
    }
    if (isAdmin && _isSuperAdmin) {
      try {
        final universities = await ApiService.getUniversities();
        if (universities.isEmpty) {
          throw StateError(
              'No registered universities are available for issuing.');
        }
        final requestedCode =
            widget.initialRecord?['university_code']?.toString();
        final preferredCode = universities.any(
          (university) => university['code']?.toString() == requestedCode,
        )
            ? requestedCode
            : universities.first['code']?.toString();
        if (preferredCode == null || preferredCode.isEmpty) {
          throw StateError('A university could not be selected for issuance.');
        }
        if (mounted) {
          setState(() {
            _isAdmin = true;
            _universities = universities;
            _selectedUniversityCode = preferredCode;
            for (final draft in _drafts) {
              draft.school = preferredCode;
            }
            _isLoadingAdminCheck = false;
          });
        }
        return;
      } catch (error) {
        if (mounted) {
          setState(() {
            _isAdmin = true;
            _universityLoadError = error.toString();
            _isLoadingAdminCheck = false;
          });
        }
        return;
      }
    }
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

  void _addDraft() {
    final draft = _CredentialDraft()..school = _issuanceUniversityCode ?? '';
    setState(() => _drafts.add(draft));
  }

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
      universityCode: _issuanceUniversityCode,
    );
    final url = uploaded['diploma_url']?.toString();
    if (url == null || url.isEmpty) {
      throw StateError('The backend did not return a diploma URL.');
    }
    return url;
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Map<String, dynamic> _validationRecord(_CredentialDraft draft) => {
        'student_id': draft.studentId.text.trim(),
        'student_name': draft.studentName.text.trim(),
        'student_email': draft.studentEmail.text.trim().toLowerCase(),
        'degree': draft.degree.text.trim(),
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
    final isCrossUniversity = previousDegrees.any(
      (degree) =>
          degree['university_code']?.toString() != _issuanceUniversityCode,
    );
    final draft = _drafts[candidate['draft_index'] as int];
    final previousText = previousDegrees
        .map((degree) =>
            '${_ordinal(degree['degree_number'] as int)}: ${degree['degree']}'
            '${degree['university_code'] == null ? '' : ' — ${degree['university_code']}'}')
        .join('\n');
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(isCrossUniversity
                ? 'Link credentials across universities?'
                : 'Is this the student’s ${_ordinal(nextDegree)} degree?'),
            content: Text(
              'A record with the same student name and email has these credentials:\n'
              '$previousText\n\n'
              'If this is the same student, issue "${draft.degree.text.trim()}" '
              'from ${_issuanceUniversityCode ?? 'this university'} as degree '
              '${_ordinal(nextDegree)}. Previous university records will not be changed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Confirm ${_ordinal(nextDegree)} degree'),
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

    setState(() => _isProcessing = true);
    try {
      var activeDrafts = List<_CredentialDraft>.from(_drafts);
      var validation = await ApiService.validateBatchIssuance(
        activeDrafts.map(_validationRecord).toList(),
        universityCode: _issuanceUniversityCode,
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
      activeDrafts = activeDrafts
          .where((draft) => !skippedDrafts.contains(draft))
          .toList();
      if (activeDrafts.isEmpty) {
        _showWarning('No credentials were issued.');
        return;
      }
      if (candidates.isNotEmpty) {
        validation = await ApiService.validateBatchIssuance(
          activeDrafts.map(_validationRecord).toList(),
          universityCode: _issuanceUniversityCode,
        );
      }
      final validationWarnings = List<String>.from(
        validation['warnings'] as List? ?? const [],
      );
      final records = await Future.wait(activeDrafts.map((draft) async {
        return {
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
        };
      }));
      final result = await ApiService.issueBatchCertificates(records);
      final issued = result['data'] is List
          ? (result['data'] as List).whereType<Map>().toList()
          : const <Map>[];
      final blockchainPending = issued.any(
        (record) => record['blockchain_status'] == 'pending',
      );
      final issueMessage = blockchainPending
          ? '${records.length} credential(s) issued. Blockchain anchoring is processing in the background.'
          : '${records.length} credential(s) issued successfully.';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              validationWarnings.isEmpty ? null : Colors.orange.shade800,
          content: Text(
            validationWarnings.isEmpty
                ? issueMessage
                : '$issueMessage ${validationWarnings.join(' ')}',
          ),
        ),
      );
      StatefulNavigationShell.of(context).goBranch(
        _recordsBranchIndex,
        initialLocation: true,
      );
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
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8)),
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
      return const Scaffold(
        body: Center(child: CertiTrustLoadingIndicator()),
      );
    }
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Issue Academic Credentials')),
        body: const Center(child: Text('Administrator access is required.')),
      );
    }
    if (_universityLoadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Issue Academic Credentials')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load universities: $_universityLoadError'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _verifyAdminAccess,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
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
                if (_isSuperAdmin) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUniversityCode,
                    decoration: const InputDecoration(
                      labelText: 'University/School',
                      prefixIcon: Icon(Icons.account_balance),
                      border: OutlineInputBorder(),
                    ),
                    items: _universities
                        .map((university) {
                          final code = university['code']?.toString() ?? '';
                          final name =
                              university['university_name']?.toString() ?? code;
                          return DropdownMenuItem(
                            value: code,
                            child: Text('$name ($code)'),
                          );
                        })
                        .where((item) => item.value?.isNotEmpty == true)
                        .toList(),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Select a university'
                        : null,
                    onChanged: (code) {
                      if (code == null) return;
                      setState(() {
                        _selectedUniversityCode = code;
                        for (final draft in _drafts) {
                          draft.school = code;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ],
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
                          child: CertiTrustLoadingIndicator(size: 18))
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
                _degreeField(draft),
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

  Widget _degreeField(_CredentialDraft draft) {
    return SizedBox(
      width: 430,
      child: Autocomplete<String>(
        key: ObjectKey(draft),
        initialValue: TextEditingValue(text: draft.degree.text),
        optionsBuilder: (value) {
          final query = _normalizeDegreeSearch(value.text);
          if (query.isEmpty) return _degreeSuggestions;
          return _degreeSuggestions.where(
            (degree) => _normalizeDegreeSearch(degree).contains(query),
          );
        },
        onSelected: (degree) {
          draft.degree.text = degree;
          setState(() {});
        },
        fieldViewBuilder: (
          context,
          controller,
          focusNode,
          onFieldSubmitted,
        ) =>
            TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Degree / program',
            prefixIcon: Icon(Icons.school),
            suffixIcon: Icon(Icons.search),
            helperText:
                'Search by full name or acronym; custom programs are allowed.',
            border: OutlineInputBorder(),
          ),
          onTapOutside: (_) => focusNode.unfocus(),
          validator: (value) => _required(value, 'degree or program'),
          onChanged: (value) {
            draft.degree.text = value;
            setState(() {});
          },
          onFieldSubmitted: (_) => onFieldSubmitted(),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 240,
                maxWidth: 430,
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: options
                    .map((degree) => ListTile(
                          title: Text(degree),
                          onTap: () => onSelected(degree),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeDegreeSearch(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

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
