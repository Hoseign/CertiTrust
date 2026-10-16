import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  String? _selectedDegree;
  bool _isUpdating = false;
  bool _isRefreshing = false;
  bool _isAppActive = true;

  static const _masteralFilter = '@type:Masteral';
  static const _doctoralFilter = '@type:Doctoral';
  static const _multipleDegreesFilter = '@multiple-degrees';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _studentsFuture = ApiService.getUniversityStudents(
      universityCode: widget.universityCode,
    );
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
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
    final refresh = ApiService.getUniversityStudents(
      universityCode: widget.universityCode,
    );
    setState(() {
      _isRefreshing = true;
      _studentsFuture = refresh;
    });
    try {
      await refresh;
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
    if (filter.startsWith('@number:')) {
      final degreeNumber = int.tryParse(filter.substring('@number:'.length));
      return degreeNumber != null &&
          credentials.any(
            (credential) =>
                int.tryParse(
                  credential['degree_number']?.toString() ?? '',
                ) ==
                degreeNumber,
          );
    }
    if (filter.startsWith('@type:')) {
      final type = filter.substring('@type:'.length);
      return credentials
          .any((credential) => credential['degree_type']?.toString() == type);
    }
    if (filter.startsWith('program:')) {
      final program = filter.substring('program:'.length);
      return credentials.any(
        (credential) => credential['degree']?.toString() == program,
      );
    }
    return true;
  }

  String _degreeFilterLabel(String? filter) {
    if (filter == null) return 'All degrees';
    if (filter == _masteralFilter) return 'Masteral';
    if (filter == _doctoralFilter) return 'Doctoral';
    if (filter == _multipleDegreesFilter) return 'Multiple degrees';
    if (filter.startsWith('@number:')) {
      final number = int.tryParse(filter.substring('@number:'.length)) ?? 1;
      return '${_ordinal(number)} degree';
    }
    if (filter.startsWith('program:')) return filter.substring(8);
    return 'All degrees';
  }

  Future<void> _selectDegreeFilter(
    List<String> degrees,
    int highestDegreeNumber,
  ) async {
    final options = <(String, String)>[
      ('@all', 'All degrees'),
      (_masteralFilter, 'Masteral'),
      (_doctoralFilter, 'Doctoral'),
      (_multipleDegreesFilter, 'Multiple degrees'),
      for (var number = 1; number <= highestDegreeNumber; number++)
        ('@number:$number', '${_ordinal(number)} degree'),
      for (final degree in degrees) ('program:$degree', degree),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final visibleOptions = options
                .where((option) =>
                    option.$2.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search degree or program',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setSheetState(() => query = value.trim()),
                      ),
                    ),
                    Expanded(
                      child: visibleOptions.isEmpty
                          ? const Center(child: Text('No matching options.'))
                          : ListView.builder(
                              itemCount: visibleOptions.length,
                              itemBuilder: (context, index) {
                                final option = visibleOptions[index];
                                return ListTile(
                                  title: Text(option.$2),
                                  selected: _selectedDegree == option.$1 ||
                                      (_selectedDegree == null &&
                                          option.$1 == '@all'),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, option.$1),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedDegree = selected == '@all' ? null : selected);
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
            final highestDegreeNumber = students
                .expand((student) => _credentialsFor(student))
                .map((credential) =>
                    int.tryParse(
                        credential['degree_number']?.toString() ?? '') ??
                    1)
                .fold<int>(1,
                    (highest, number) => number > highest ? number : highest);
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
                InkWell(
                  onTap: () =>
                      _selectDegreeFilter(degrees, highestDegreeNumber),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Filter by degree or program',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(_degreeFilterLabel(_selectedDegree)),
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
                                        child: Text('Remove student account'),
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
