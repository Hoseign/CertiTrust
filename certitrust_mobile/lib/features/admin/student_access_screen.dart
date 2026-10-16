import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

class _StudentAccessScreenState extends State<StudentAccessScreen> {
  final _searchController = TextEditingController();
  late Future<Map<String, dynamic>> _studentsFuture;
  String? _selectedBatchYear;
  String? _selectedDegree;
  bool _isUpdating = false;

  static const _masteralFilter = '@type:Masteral';
  static const _doctoralFilter = '@type:Doctoral';
  static const _undergraduateFilter = '@type:Undergraduate';
  static const _multipleDegreesFilter = '@multiple-degrees';

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
    setState(() {
      _studentsFuture = refresh;
    });
    await refresh;
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
    final studentId = int.tryParse(student['id']?.toString() ?? '');
    if (studentId == null) return;
    final label = student['name']?.toString() ??
        student['email']?.toString() ??
        'this student';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove student account?'),
        content: Text(
          'Remove sign-in and frozen-access data for $label? Issued credentials will remain available for verification.',
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

    setState(() => _isUpdating = true);
    try {
      await ApiService.deleteStudentAccount(userId: studentId);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$label’s account was removed. Credentials were kept.'),
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
    final filter = _selectedDegree;
    if (filter == null) return true;
    final credentials = _credentialsFor(student);
    if (filter == _multipleDegreesFilter) return credentials.length > 1;
    if (filter.startsWith('@type:')) {
      final type = filter.substring('@type:'.length);
      return credentials.any((credential) =>
          credential['degree_type']?.toString() == type);
    }
    if (filter.startsWith('program:')) {
      final program = filter.substring('program:'.length);
      return credentials.any(
        (credential) => credential['degree']?.toString() == program,
      );
    }
    return true;
  }

  String _ordinal(int number) {
    if (number % 100 >= 11 && number % 100 <= 13) return '${number}th';
    return switch (number % 10) {
      1 => '${number}st',
      2 => '${number}nd',
      3 => '${number}rd',
      _ => '${number}th',
    };
  }

  String _studentSubtitle(Map<String, dynamic> student) {
    final credentials = _credentialsFor(student);
    return [
      student['email']?.toString() ?? 'No email',
      if (student['student_id'] != null)
        'Student ID: ${student['student_id']}',
      for (var index = 0; index < credentials.length; index++)
        '${_ordinal(int.tryParse(credentials[index]['degree_number']?.toString() ?? '') ?? index + 1)} degree: ${credentials[index]['degree'] ?? 'Degree not recorded'} (${credentials[index]['degree_type'] ?? 'Other'})',
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
              return const Center(child: CircularProgressIndicator());
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
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search students or credentials',
                    hintText:
                        'Name, Gmail, student ID, degree or certificate code',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (batchYears.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Student batch year',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All batches'),
                          selected: _selectedBatchYear == null,
                          onSelected: (_) =>
                              setState(() => _selectedBatchYear = null),
                        ),
                        const SizedBox(width: 8),
                        for (final year in batchYears) ...[
                          ChoiceChip(
                            label: Text(year),
                            selected: _selectedBatchYear == year,
                            onSelected: (_) =>
                                setState(() => _selectedBatchYear = year),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDegree,
                  decoration: const InputDecoration(
                    labelText: 'Filter by degree type or program',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('All degrees'),
                    ),
                    const DropdownMenuItem<String>(
                      value: _masteralFilter,
                      child: Text('Masteral'),
                    ),
                    const DropdownMenuItem<String>(
                      value: _doctoralFilter,
                      child: Text('Doctoral'),
                    ),
                    const DropdownMenuItem<String>(
                      value: _undergraduateFilter,
                      child: Text('Undergraduate'),
                    ),
                    const DropdownMenuItem<String>(
                      value: _multipleDegreesFilter,
                      child: Text('Multiple degrees'),
                    ),
                    if (degrees.isNotEmpty)
                      const DropdownMenuItem<String>(
                        value: '@programs',
                        enabled: false,
                        child: Text('Programs'),
                      ),
                    ...degrees.map((degree) => DropdownMenuItem<String>(
                          value: 'program:$degree',
                          child: Text(degree),
                        )),
                  ],
                  onChanged: (value) => setState(() => _selectedDegree = value),
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
                      subtitle: Text(_studentSubtitle(student)),
                      trailing: widget.superAdminView &&
                              student['is_frozen'] == true &&
                              student['can_manage_access'] == false
                          ? const Tooltip(
                              message:
                                  'Only the administrator who froze this student can unfreeze them.',
                              child: Icon(Icons.lock_outline),
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
                                    child: Text('Remove student account'),
                                  ),
                              ],
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
