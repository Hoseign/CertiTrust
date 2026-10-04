import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class StudentAccessScreen extends StatefulWidget {
  const StudentAccessScreen({super.key});

  @override
  State<StudentAccessScreen> createState() => _StudentAccessScreenState();
}

class _StudentAccessScreenState extends State<StudentAccessScreen> {
  late Future<Map<String, dynamic>> _studentsFuture;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _studentsFuture = ApiService.getUniversityStudents();
  }

  Future<void> _reload() async {
    setState(() => _studentsFuture = ApiService.getUniversityStudents());
    await _studentsFuture;
  }

  Future<void> _setAllStudentsFrozen(bool frozen) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(frozen ? 'Freeze all student accounts?' : 'Unfreeze all student accounts?'),
        content: Text(
          frozen
              ? 'Students at ${ApiService.authUniversity ?? 'your university'} will not be able to use their accounts until access is restored. University administrators will remain unaffected.'
              : 'Restore student access for ${ApiService.authUniversity ?? 'your university'}? This will clear individual student freezes too.',
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update access: $error')));
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
        title: Text(frozen ? 'Freeze student account?' : 'Unfreeze student account?'),
        content: Text(
            '${frozen ? 'Block' : 'Restore'} account access for $label?'),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update access: $error')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to records',
            onPressed: () => context.pop(),
          ),
          title: const Text('Student Account Access'),
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
                      Text('Could not load student accounts: ${snapshot.error}'),
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
            final allFrozen = data['university_students_frozen'] == true;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '${ApiService.authUniversity ?? 'University'} students',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Only student accounts can be frozen here. This never freezes your subadmin account.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isUpdating
                      ? null
                      : () => _setAllStudentsFrozen(!allFrozen),
                  icon: Icon(allFrozen
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline),
                  label: Text(allFrozen
                      ? 'Unfreeze all students'
                      : 'Freeze all students'),
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
                for (final student in students)
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
                      subtitle:
                          Text(student['email']?.toString() ?? 'No email'),
                      trailing: TextButton(
                        onPressed: _isUpdating
                            ? null
                            : () => _setStudentFrozen(
                                  student,
                                  student['is_frozen'] != true,
                                ),
                        child: Text(student['is_frozen'] == true
                            ? 'Unfreeze'
                            : 'Freeze'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
