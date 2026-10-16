import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _universityController = TextEditingController();
  final _branchController = TextEditingController();
  final _universityCodeController = TextEditingController();
  String? _emailError;
  int? _editingId;
  bool _isSubmitting = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _admins = [];

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _universityController.dispose();
    _branchController.dispose();
    _universityCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() => _isLoading = true);
    try {
      final admins = await ApiService.getSubadmins();
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _emailController.clear();
    _emailError = null;
    _nameController.clear();
    _universityController.clear();
    _branchController.clear();
    _universityCodeController.clear();
    _editingId = null;
  }

  String _initials(String value) {
    final words = value
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) =>
            word.isNotEmpty &&
            !const {'of', 'the', 'and', 'branch', 'campus'}
                .contains(word.toLowerCase()))
        .toList();
    if (words.isEmpty) return '';
    return words.map((word) => word[0].toUpperCase()).join();
  }

  String _generatedUniversityCode(String university, String branch) {
    final universityInitials = _initials(university);
    final branchInitials = _initials(branch);
    final code = (universityInitials + branchInitials)
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return code.length > 10 ? code.substring(0, 10) : code;
  }

  void _updateGeneratedCode() {
    _universityCodeController.text = _generatedUniversityCode(
      _universityController.text,
      _branchController.text,
    );
  }

  Future<void> _submitAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _emailError = null;
    });

    try {
      final editing = _editingId != null;
      if (_editingId != null) {
        await ApiService.updateSubadminAccount(
          id: _editingId!,
          email: _emailController.text.trim(),
          name: _nameController.text.trim(),
          universityCode: _universityCodeController.text.trim().toUpperCase(),
          universityName: _universityController.text.trim(),
          displayName: _universityCodeController.text.trim().toUpperCase(),
          branchCampus: _branchController.text,
        );
      } else {
        await ApiService.bindSubadminAccount(
          email: _emailController.text.trim(),
          universityCode: _universityCodeController.text.trim().toUpperCase(),
          universityName: _universityController.text.trim(),
          displayName: _universityCodeController.text.trim().toUpperCase(),
          branchCampus: _branchController.text,
          name: _nameController.text.trim(),
        );
      }

      if (!mounted) return;
      _resetForm();
      await _loadAdmins();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(editing
                ? 'Administrator account updated.'
                : 'Administrator account created.')),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is ApiRequestException && error.statusCode == 422) {
        final message = error.message.toLowerCase();
        if (message.contains('email') &&
            (message.contains('already') || message.contains('used'))) {
          setState(() => _emailError =
              'This email is already in use. Enter another email address.');
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteAdmin(Map<String, dynamic> admin) async {
    final id = admin['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove subadmin'),
        content: Text(
            'Remove ${admin['name'] ?? admin['email']} from ${admin['university_code']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteSubadminAccount(int.parse(id.toString()));
      if (!mounted) return;
      await _loadAdmins();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Subadmin removed.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _changeGoogleAccount(Map<String, dynamic> admin) async {
    final id = admin['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Google account?'),
        content: Text(
          'The current Google account (${admin['email']}) will be replaced and its active sessions will be signed out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final emailController = TextEditingController();
    final replacementEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter replacement Google email'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Google account email',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, emailController.text.trim()),
            child: const Text('Change account'),
          ),
        ],
      ),
    );
    emailController.dispose();
    if (replacementEmail == null || replacementEmail.isEmpty || !mounted) {
      return;
    }
    if (replacementEmail.toLowerCase() ==
        admin['email']?.toString().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a different Google account email.')),
      );
      return;
    }
    try {
      await ApiService.updateSubadminAccount(
        id: int.parse(id.toString()),
        email: replacementEmail,
      );
      if (!mounted) return;
      await _loadAdmins();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google account updated.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteStudentAccount(
    Map student,
    String universityCode,
  ) async {
    final id = int.tryParse(student['id']?.toString() ?? '');
    if (id == null) return;
    final email = student['email']?.toString() ?? 'this student';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove frozen student account?'),
        content: Text(
          'Remove sign-in and frozen-access data for $email at $universityCode? Issued credentials will remain available for verification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.deleteStudentAccount(userId: id);
      await _loadAdmins();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$email’s account was removed. Credentials were kept.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove student account: $error')),
        );
      }
    }
  }

  Future<void> _manageUniversityAccess(
      Map<String, dynamic> admin, bool frozen) async {
    final universityCode = admin['university_code']?.toString();
    if (universityCode == null || universityCode.isEmpty) return;
    var selectedScope = 'admin';
    final scope = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(frozen
              ? 'Freeze university access'
              : 'Restore university access'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                frozen
                    ? 'Choose which accounts at $universityCode to freeze. Student-only or combined freezing affects all current and future student accounts.'
                    : 'Choose which accounts at $universityCode to restore. Student accounts frozen individually by a university subadmin will remain frozen.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [
                    ('admin', 'Subadmin only'),
                    ('students', 'Students only'),
                    ('both', 'Subadmin and students'),
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: selectedScope == option.$1,
                      onSelected: (_) =>
                          setDialogState(() => selectedScope = option.$1),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedScope),
              child: Text(frozen ? 'Freeze selected' : 'Restore selected'),
            ),
          ],
        ),
      ),
    );
    if (scope == null || !mounted) return;

    try {
      final result = await ApiService.updateUniversityAccess(
        universityCode: universityCode,
        scope: scope,
        frozen: frozen,
      );
      await _loadAdmins();
      final protectedStudents = result['protected_students'];
      if (!frozen &&
          protectedStudents is List &&
          protectedStudents.isNotEmpty &&
          mounted) {
        await _showProtectedStudentWarning(protectedStudents);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${frozen ? 'Frozen' : 'Restored'} ${_scopeLabel(scope)} access for $universityCode.',
          ),
        ));
      }
    } catch (error) {
      final protectedStudents = error is ApiRequestException
          ? error.details['protected_students']
          : null;
      if (!frozen &&
          protectedStudents is List &&
          protectedStudents.isNotEmpty &&
          mounted) {
        await _showProtectedStudentWarning(protectedStudents);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not update university access: $error')));
      }
    }
  }

  Future<void> _showProtectedStudentWarning(List<dynamic> students) async {
    final studentDetails = students.whereType<Map>().map((student) {
      final name = student['name']?.toString() ?? 'Student';
      final studentId = student['student_id']?.toString() ?? 'Not recorded';
      return '$name (Student ID: $studentId)';
    }).toList();
    if (studentDetails.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('You cannot unfreeze this student'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You do not have authority to unfreeze the following student(s). '
                'Only the administrator who froze each account can restore access:',
              ),
              const SizedBox(height: 12),
              for (final student in studentDetails)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('- $student'),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _scopeLabel(String scope) => switch (scope) {
        'students' => 'student',
        'both' => 'subadmin and student',
        _ => 'subadmin',
      };

  void _startEdit(Map<String, dynamic> admin) {
    setState(() {
      _editingId = int.parse(admin['id'].toString());
      _emailController.text = admin['email']?.toString() ?? '';
      _nameController.text = admin['name']?.toString() ?? '';
      _universityController.text = admin['university_name']?.toString() ?? '';
      _branchController.text = admin['branch_campus']?.toString() ?? '';
      _universityCodeController.text =
          admin['university_code']?.toString() ?? '';
    });
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Super Admin Dashboard',
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text('Administrator Management'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Subadmin Accounts',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Bind, update, or remove university administrators across the system.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Display name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Google account email',
                  border: const OutlineInputBorder(),
                  errorText: _emailError,
                ),
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.contains('@') ? null : 'Enter a valid email.';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _universityController,
                decoration: const InputDecoration(
                  labelText: 'University name',
                  hintText: 'e.g. University of Cebu',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(_updateGeneratedCode),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the full university name.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _branchController,
                decoration: const InputDecoration(
                  labelText: 'Branch campus (optional)',
                  hintText: 'e.g. Bayambang Campus',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(_updateGeneratedCode),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _universityCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Display name / university short code',
                  hintText: 'Generated from the university name',
                  helperText: 'Editable; use 1–10 letters or numbers.',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final normalized = value.toUpperCase();
                  if (normalized != value) {
                    _universityCodeController.value =
                        _universityCodeController.value.copyWith(
                      text: normalized,
                      selection:
                          TextSelection.collapsed(offset: normalized.length),
                    );
                  }
                },
                validator: (value) {
                  final code = value?.trim() ?? '';
                  return RegExp(r'^[A-Z0-9]{1,10}$').hasMatch(code)
                      ? null
                      : 'Use 1–10 letters or numbers.';
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitAdmin,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          _editingId == null ? Icons.person_add : Icons.save),
                  label: Text(_editingId == null
                      ? 'Create administrator account'
                      : 'Update administrator account'),
                ),
              ),
              if (_editingId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    onPressed: _resetForm,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel edit'),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 28),
          const Text('Registered Subadmins',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator()))
          else if (_admins.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No subadmin accounts registered yet.')))
          else
            ..._admins.map((admin) {
              final frozenStudents = (admin['frozen_students'] as List? ?? [])
                  .whereType<Map>()
                  .toList();
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(admin['name']?.toString() ?? 'University Admin'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(admin['email']?.toString() ?? 'No email'),
                      const SizedBox(height: 4),
                      Text(
                        'University: ${admin['university_name'] ?? 'University'}'
                        ' (${admin['display_name'] ?? admin['university_code'] ?? 'Unassigned'})'
                        '${admin['branch_campus'] == null || admin['branch_campus'].toString().isEmpty ? '' : ' • ${admin['branch_campus']}'}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        admin['access_frozen'] == true
                            ? 'Subadmin access: Not active (frozen)'
                            : 'Subadmin access: Active',
                        style: TextStyle(
                          color: admin['access_frozen'] == true
                              ? Colors.red
                              : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            frozenStudents.isEmpty
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                            size: 18,
                            color: frozenStudents.isEmpty
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            frozenStudents.isEmpty
                                ? 'Frozen students: None'
                                : 'Frozen students: ${frozenStudents.length}',
                            style: TextStyle(
                              color: frozenStudents.isEmpty
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') _startEdit(admin);
                      if (value == 'change-google') {
                        await _changeGoogleAccount(admin);
                      }
                      if (value == 'delete') await _deleteAdmin(admin);
                      if (value == 'freeze') {
                        await _manageUniversityAccess(admin, true);
                      }
                      if (value == 'unfreeze') {
                        await _manageUniversityAccess(admin, false);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'freeze',
                        child: Text(
                            'Freeze access for ${admin['university_code']}'),
                      ),
                      PopupMenuItem(
                        value: 'unfreeze',
                        child: Text(
                            'Restore access for ${admin['university_code']}'),
                      ),
                      const PopupMenuItem(
                          value: 'change-google',
                          child: Text('Change Google account')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  children: [
                    _UniversityStudentManager(
                      universityCode:
                          admin['university_code']?.toString() ?? '',
                      onChanged: _loadAdmins,
                      onDelete: (student) => _deleteStudentAccount(
                        student,
                        admin['university_code']?.toString() ?? '',
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _UniversityStudentManager extends StatefulWidget {
  const _UniversityStudentManager({
    required this.universityCode,
    required this.onChanged,
    required this.onDelete,
  });

  final String universityCode;
  final Future<void> Function() onChanged;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  @override
  State<_UniversityStudentManager> createState() =>
      _UniversityStudentManagerState();
}

class _UniversityStudentManagerState extends State<_UniversityStudentManager> {
  final _searchController = TextEditingController();
  late Future<Map<String, dynamic>> _studentsFuture;
  String? _selectedYear;
  String? _selectedDegree;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _studentsFuture = ApiService.getUniversityStudents(
      universityCode: widget.universityCode,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final refresh = ApiService.getUniversityStudents(
      universityCode: widget.universityCode,
    );
    setState(() => _studentsFuture = refresh);
    await refresh;
  }

  Future<void> _toggleAccess(
    Map<String, dynamic> student,
    bool frozen,
  ) async {
    final id = int.tryParse(student['id']?.toString() ?? '');
    if (id == null) return;
    final label = student['name']?.toString() ?? 'this student';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            frozen ? 'Freeze student account?' : 'Unfreeze student account?'),
        content: Text(
          '${frozen ? 'Block' : 'Restore'} account access for $label?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(frozen ? 'Freeze account' : 'Unfreeze account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isUpdating = true);
    try {
      await ApiService.updateStudentAccess(userId: id, frozen: frozen);
      await _reload();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(frozen
              ? '$label’s account is frozen.'
              : '$label’s account access was restored.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        final message = error is ApiRequestException ? error.message : '$error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.universityCode.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('This subadmin does not have a university scope assigned.'),
      );
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _studentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Could not load university students: ${snapshot.error}'),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }

        final students = (snapshot.data?['data'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final years = students
            .map((student) =>
                student['batch_year']?.toString() ?? 'Year unavailable')
            .toSet()
            .toList()
          ..sort((a, b) =>
              (int.tryParse(b) ?? -1).compareTo(int.tryParse(a) ?? -1));
        final degrees = students
            .expand<String>((student) {
              final studentDegrees = student['degrees'];
              if (studentDegrees is List) {
                return studentDegrees.whereType<String>();
              }
              final degree = student['degree']?.toString();
              return degree == null ? const <String>[] : [degree];
            })
            .where((degree) => degree.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final query = _searchController.text.trim().toLowerCase();
        final visibleStudents = students.where((student) {
          final year = student['batch_year']?.toString() ?? 'Year unavailable';
          final matchesYear = _selectedYear == null || year == _selectedYear;
          final studentDegrees = student['degrees'] is List
              ? (student['degrees'] as List).map((degree) => degree.toString())
              : [student['degree']?.toString() ?? ''];
          final matchesDegree = _selectedDegree == null ||
              studentDegrees.contains(_selectedDegree);
          final searchable = [
            student['name'],
            student['email'],
            student['student_id'],
            student['degree'],
            student['credential_search'],
            student['certificate_code'],
          ].whereType<Object>().join(' ').toLowerCase();
          return matchesYear &&
              matchesDegree &&
              (query.isEmpty || searchable.contains(query));
        }).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search students or credentials',
                  hintText: 'Name, Gmail, student ID, or degree',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedYear,
                      decoration: const InputDecoration(
                        labelText: 'Batch year',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All batches'),
                        ),
                        ...years.map((year) => DropdownMenuItem<String>(
                              value: year,
                              child: Text(year),
                            )),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedYear = value),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedDegree,
                      decoration: const InputDecoration(
                        labelText: 'Degree',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All degrees'),
                        ),
                        ...degrees.map((degree) => DropdownMenuItem<String>(
                              value: degree,
                              child: Text(
                                degree,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedDegree = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${visibleStudents.length} student account${visibleStudents.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (students.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No student accounts have signed in yet.'),
                ),
              if (students.isNotEmpty && visibleStudents.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No students match these filters.'),
                ),
              for (final student in visibleStudents)
                Card(
                  child: ListTile(
                    leading: Icon(
                      student['is_frozen'] == true
                          ? Icons.lock_outline
                          : Icons.school_outlined,
                      color: student['is_frozen'] == true
                          ? Colors.red
                          : Colors.teal,
                    ),
                    title: Text(student['name']?.toString() ?? 'Student'),
                    subtitle: Text([
                      student['email']?.toString() ?? 'No email',
                      if (student['student_id'] != null)
                        'Student ID: ${student['student_id']}',
                      student['degrees'] is List &&
                              (student['degrees'] as List).isNotEmpty
                          ? (student['degrees'] as List).join(', ')
                          : student['degree']?.toString() ??
                              'Degree not recorded',
                      'Batch: ${student['batch_year'] ?? 'Year unavailable'}',
                      if (student['is_frozen'] == true)
                        'Frozen by: ${student['freeze_owner_email'] ?? 'another administrator'}',
                    ].join('\n')),
                    trailing: PopupMenuButton<String>(
                      enabled: !_isUpdating,
                      onSelected: (action) {
                        if (action == 'toggle') {
                          _toggleAccess(
                            student,
                            student['is_frozen'] != true,
                          );
                        } else if (action == 'delete') {
                          widget.onDelete(student).then((_) => _reload());
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(student['is_frozen'] == true
                              ? 'Unfreeze'
                              : 'Freeze'),
                        ),
                        if (student['is_frozen'] == true)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Remove student account'),
                          ),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
