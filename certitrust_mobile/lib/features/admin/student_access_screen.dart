import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/academic_degree.dart';
import '../../core/widgets/certitrust_loading_indicator.dart';
import '../../services/api_service.dart';

class StudentAccessScreen extends StatefulWidget {
  const StudentAccessScreen({
    super.key,
    this.universityCode,
    this.universityName,
    this.superAdminView = false,
  });

  final String? universityCode;
  final String? universityName;
  final bool superAdminView;

  @override
  State<StudentAccessScreen> createState() => _StudentAccessScreenState();
}

class _StudentAccessScreenState extends State<StudentAccessScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  late Future<Map<String, dynamic>> _studentsFuture;
  Timer? _refreshTimer;
  String? _selectedBatchYear;
  String _selectedAcademicLevel = '';
  String? _selectedProgram;
  int? _selectedDegreeNumber;
  bool _showMultipleDegrees = false;
  bool _isUpdating = false;
  bool _isRefreshing = false;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _studentsFuture = ApiService.getUniversityStudents(
      universityCode: widget.universityCode,
    );
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isAppActive && !_isUpdating) _refreshAutomatically();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;
    if (_isAppActive && !_isUpdating) _refreshAutomatically();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      final refresh = await ApiService.getUniversityStudents(
        universityCode: widget.universityCode,
      );
      if (mounted) {
        setState(() {
          _studentsFuture = Future.value(refresh);
        });
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _refreshAutomatically() async {
    try {
      await _reload();
    } catch (error) {
      debugPrint('Unable to refresh student access list: $error');
    }
  }

  Future<void> _setAllStudentsFrozen(bool frozen) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(frozen
            ? 'Freeze all student accounts?'
            : 'Unfreeze all student accounts?'),
        content: Text(
          frozen
              ? 'Students at ${ApiService.authUniversity ?? 'your university'} will not be able to use their accounts until access is restored. University administrators will remain unaffected.'
              : 'Restore student access for ${ApiService.authUniversity ?? 'your university'}? Individual freezes created by other administrators will remain in place.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(frozen ? 'Freeze all' : 'Unfreeze all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      await ApiService.updateAllStudentAccess(frozen: frozen);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(frozen
              ? 'All student accounts are frozen.'
              : 'All student account restrictions were cleared.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        final message = error is ApiRequestException ? error.message : '$error';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _setStudentFrozen(
      Map<String, dynamic> student, bool frozen) async {
    final studentId = int.tryParse(student['id']?.toString() ?? '');
    if (studentId == null) return;
    final label = student['name']?.toString() ??
        student['email']?.toString() ??
        'this student';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            frozen ? 'Freeze student account?' : 'Unfreeze student account?'),
        content:
            Text('${frozen ? 'Block' : 'Restore'} account access for $label?'),
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
      await ApiService.updateStudentAccess(userId: studentId, frozen: frozen);
      await _reload();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _deleteStudentAccount(Map<String, dynamic> student) async {
    if (widget.superAdminView) return;
    final studentId = int.tryParse(student['id']?.toString() ?? '');
    if (studentId == null) return;
    final label = student['name']?.toString() ??
        student['email']?.toString() ??
        'this student';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request student removal?'),
        content: Text(
          'Send a request to the Super Admin to remove $label? The student account remains active until approved. If approved, the account and credentials will move to Junk for permanent deletion. Blockchain history cannot be erased.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      final result = await ApiService.deleteStudentAccount(userId: studentId);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            result['message']?.toString() ??
                'Student removal request sent to the Super Admin.',
          ),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove student account: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  List<Map<String, dynamic>> _credentialsFor(Map<String, dynamic> student) {
    final credentials = student['credentials'];
    if (credentials is List) {
      return credentials
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const [];
  }

  bool _matchesDegreeFilter(Map<String, dynamic> student) {
    final credentials = _credentialsFor(student);
    if (_showMultipleDegrees && credentials.length < 2) return false;
    if (_selectedAcademicLevel.isEmpty &&
        _selectedProgram == null &&
        _selectedDegreeNumber == null) {
      return true;
    }
    return credentials.any((credential) {
      final degree = credential['degree']?.toString() ?? '';
      final degreeNumber =
          int.tryParse(credential['degree_number']?.toString() ?? '') ?? 1;
      final level = AcademicDegree.classify(
        degree,
        degreeNumber: degreeNumber,
      );
      return (_selectedAcademicLevel.isEmpty ||
              level == _selectedAcademicLevel) &&
          (_selectedProgram == null || degree == _selectedProgram) &&
          (_selectedDegreeNumber == null ||
              degreeNumber == _selectedDegreeNumber);
    });
  }

  String _credentialLevelLabel(Map<String, dynamic> credential) {
    final degree = credential['degree']?.toString() ?? '';
    final degreeNumber =
        int.tryParse(credential['degree_number']?.toString() ?? '') ?? 1;
    final level = AcademicDegree.classify(
      degree,
      degreeNumber: degreeNumber,
    );
    return AcademicDegree.levelOptions
        .firstWhere(
          (option) => option.$1 == level,
          orElse: () => ('other', 'Other'),
        )
        .$2;
  }

  String _studentSubtitle(Map<String, dynamic> student) {
    final credentials = _credentialsFor(student);
    return [
      student['email']?.toString() ?? 'No email',
      for (var index = 0; index < credentials.length; index++)
        'Credential #${int.tryParse(credentials[index]['degree_number']?.toString() ?? '') ?? index + 1}: ${credentials[index]['degree'] ?? 'Degree not recorded'} (${_credentialLevelLabel(credentials[index])})',
      if (credentials.length > 1) 'Multiple degrees: ${credentials.length}',
      'Batch: ${student['batch_year'] ?? 'Year unavailable'}',
      if (student['is_frozen'] == true)
        'Frozen by: ${student['freeze_owner_email'] ?? 'another administrator'}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to records',
            onPressed: () => context.pop(),
          ),
          title: Text(widget.superAdminView
              ? 'University Student Access'
              : 'Student Account Access'),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _studentsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CertiTrustLoadingIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          'Could not load student accounts: ${snapshot.error}'),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _reload, child: const Text('Retry')),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final students = (data['data'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            final batchYears = students
                .map((student) =>
                    student['batch_year']?.toString() ?? 'Year unavailable')
                .toSet()
                .toList()
              ..sort((a, b) {
                final yearA = int.tryParse(a) ?? -1;
                final yearB = int.tryParse(b) ?? -1;
                return yearB.compareTo(yearA);
              });
            final degrees = students
                .expand<String>(
                  (student) => _credentialsFor(student)
                      .map((credential) => credential['degree']?.toString())
                      .whereType<String>(),
                )
                .where((degree) => degree.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            final degreeNumbers = students
                .expand((student) => _credentialsFor(student))
                .map((credential) =>
                    int.tryParse(
                        credential['degree_number']?.toString() ?? '') ??
                    1)
                .toSet()
                .toList()
              ..sort();
            final query = _searchController.text.trim().toLowerCase();
            final visibleStudents = students.where((student) {
              final year =
                  student['batch_year']?.toString() ?? 'Year unavailable';
              final matchesBatch =
                  _selectedBatchYear == null || year == _selectedBatchYear;
              final matchesDegree = _matchesDegreeFilter(student);
              final searchableText = [
                student['name'],
                student['email'],
                student['student_id'],
                student['degree'],
                student['certificate_code'],
                student['credential_search'],
              ].whereType<Object>().join(' ').toLowerCase();
              return matchesBatch &&
                  matchesDegree &&
                  (query.isEmpty || searchableText.contains(query));
            }).toList();
            final allFrozen = data['university_students_frozen'] == true;
            final canManageAll = data['can_manage_university_freeze'] != false;
            final universityLabel = widget.universityName ??
                ApiService.authUniversity ??
                'University';
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '$universityLabel students',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.superAdminView
                      ? 'Search and filter student accounts at this university. Student freeze controls are available from each account menu.'
                      : 'Only student accounts can be frozen here. This never freezes your subadmin account.',
                  style: const TextStyle(color: Colors.grey),
                ),
                if (!widget.superAdminView) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isUpdating || (allFrozen && !canManageAll)
                        ? null
                        : () => _setAllStudentsFrozen(!allFrozen),
                    icon: Icon(allFrozen
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline),
                    label: Text(allFrozen
                        ? canManageAll
                            ? 'Unfreeze all students'
                            : 'Students frozen by another administrator'
                        : 'Freeze all students'),
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Search students or credentials',
                            hintText:
                                'Name, email, student ID, program, or certificate code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        ExpansionTile(
                          title: const Text('Filter student records'),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(0, 0, 0, 12),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.45,
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          'academic-level-$_selectedAcademicLevel'),
                                      initialValue: _selectedAcademicLevel,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Academic Level',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: '',
                                          child: Text('All Levels'),
                                        ),
                                        for (final level
                                            in AcademicDegree.levelOptions)
                                          DropdownMenuItem(
                                            value: level.$1,
                                            child: Text(level.$2),
                                          ),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _selectedAcademicLevel =
                                            value ?? '',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          'program-${_selectedProgram ?? ''}'),
                                      initialValue: _selectedProgram ?? '',
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Program / Degree Title',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: '',
                                          child: Text('All Programs'),
                                        ),
                                        for (final degree in degrees)
                                          DropdownMenuItem(
                                            value: degree,
                                            child: Text(
                                              degree,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _selectedProgram =
                                            value == null || value.isEmpty
                                                ? null
                                                : value,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          'batch-year-${_selectedBatchYear ?? ''}'),
                                      initialValue: _selectedBatchYear ?? '',
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Batch / Academic Year',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: '',
                                          child: Text('All Years'),
                                        ),
                                        for (final year in batchYears)
                                          DropdownMenuItem(
                                            value: year,
                                            child: Text(year),
                                          ),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _selectedBatchYear =
                                            value == null || value.isEmpty
                                                ? null
                                                : value,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          'degree-number-${_selectedDegreeNumber?.toString() ?? ''}'),
                                      initialValue:
                                          _selectedDegreeNumber?.toString() ??
                                              '',
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Degree Sequence',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: '',
                                          child: Text('All Degrees'),
                                        ),
                                        for (final number in degreeNumbers)
                                          DropdownMenuItem(
                                            value: number.toString(),
                                            child: Text('Credential #$number'),
                                          ),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _selectedDegreeNumber =
                                            value == null || value.isEmpty
                                                ? null
                                                : int.tryParse(value),
                                      ),
                                    ),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                          'Only students with multiple degrees'),
                                      value: _showMultipleDegrees,
                                      onChanged: (value) => setState(
                                          () => _showMultipleDegrees = value),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () => setState(() {
                                          _searchController.clear();
                                          _selectedAcademicLevel = '';
                                          _selectedProgram = null;
                                          _selectedBatchYear = null;
                                          _selectedDegreeNumber = null;
                                          _showMultipleDegrees = false;
                                        }),
                                        child: const Text('Reset filters'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (students.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'No student accounts have signed in for this university yet.'),
                    ),
                  ),
                if (students.isNotEmpty && visibleStudents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('No students match this search or batch.'),
                    ),
                  ),
                for (final student in visibleStudents)
                  Card(
                    child: ExpansionTile(
                      leading: Icon(
                        student['is_frozen'] == true
                            ? Icons.lock_outline
                            : Icons.school_outlined,
                        color: student['is_frozen'] == true
                            ? Colors.red
                            : Colors.teal,
                      ),
                      title: Text(student['name']?.toString() ?? 'Student'),
                      subtitle: Text(
                        'Student ID: ${student['student_id'] ?? 'Not recorded'}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(_studentSubtitle(student)),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: widget.superAdminView &&
                                  student['is_frozen'] == true &&
                                  student['can_manage_access'] == false
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Tooltip(
                                    message:
                                        'Only the administrator who froze this student can unfreeze them.',
                                    child: Icon(Icons.lock_outline),
                                  ),
                                )
                              : PopupMenuButton<String>(
                                  enabled: !_isUpdating,
                                  onSelected: (action) {
                                    if (action == 'toggle') {
                                      _setStudentFrozen(
                                        student,
                                        student['is_frozen'] != true,
                                      );
                                    } else if (action == 'delete') {
                                      _deleteStudentAccount(student);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(student['is_frozen'] == true
                                          ? 'Unfreeze'
                                          : 'Freeze'),
                                    ),
                                    if (!widget.superAdminView)
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Request student removal'),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
