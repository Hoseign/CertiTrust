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
  final _universityController =
      TextEditingController(text: 'Urdaneta City University');
  String? _emailError;
  String _universityCode = 'UCU';
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
    _universityController.text = 'Urdaneta City University';
    _universityCode = 'UCU';
    _editingId = null;
  }

  Future<void> _submitAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _emailError = null;
    });

    try {
      if (_editingId != null) {
        await ApiService.updateSubadminAccount(
          id: _editingId!,
          email: _emailController.text.trim(),
          name: _nameController.text.trim(),
          universityCode: _universityCode,
        );
      } else {
        await ApiService.bindSubadminAccount(
          email: _emailController.text.trim(),
          universityCode: _universityCode,
          name: _nameController.text.trim(),
        );
      }

      if (!mounted) return;
      _resetForm();
      await _loadAdmins();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_editingId == null
                ? 'Administrator account created.'
                : 'Administrator account updated.')),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Subadmin removed.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _unbindGoogle(Map<String, dynamic> admin) async {
    final id = admin['id'];
    if (id == null) return;
    try {
      await ApiService.unbindSubadminGoogle(int.parse(id.toString()));
      if (!mounted) return;
      await _loadAdmins();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google binding removed.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
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
          title: Text(frozen ? 'Freeze university access' : 'Restore university access'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                frozen
                    ? 'Choose which accounts at $universityCode to freeze. Student-only or combined freezing affects all current and future student accounts.'
                    : 'Choose which accounts at $universityCode to restore. Unfreezing students clears their individual freezes too.',
              ),
              const SizedBox(height: 12),
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
      await ApiService.updateUniversityAccess(
        universityCode: universityCode,
        scope: scope,
        frozen: frozen,
      );
      await _loadAdmins();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${frozen ? 'Frozen' : 'Restored'} ${_scopeLabel(scope)} access for $universityCode.',
          ),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update university access: $error')));
      }
    }
  }

  String _scopeLabel(String scope) => switch (scope) {
        'students' => 'student',
        'both' => 'subadmin and student',
        _ => 'subadmin',
      };

  void _startEdit(Map<String, dynamic> admin) {
    final universityName = admin['university_code'] == 'UCU'
        ? 'Urdaneta City University'
        : 'Pangasinan State University';
    setState(() {
      _editingId = int.parse(admin['id'].toString());
      _emailController.text = admin['email']?.toString() ?? '';
      _nameController.text = admin['name']?.toString() ?? '';
      _universityController.text = universityName;
      _universityCode = admin['university_code']?.toString() ?? 'UCU';
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
              Autocomplete<String>(
                initialValue:
                    TextEditingValue(text: _universityController.text),
                optionsBuilder: (textEditingValue) {
                  const universities = [
                    'Urdaneta City University',
                    'Pangasinan State University'
                  ];
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) return universities;
                  return universities.where(
                      (university) => university.toLowerCase().contains(query));
                },
                onSelected: (university) {
                  _universityController.text = university;
                  setState(() => _universityCode =
                      university == 'Urdaneta City University' ? 'UCU' : 'PSU');
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  controller.text = _universityController.text;
                  controller.selection =
                      TextSelection.collapsed(offset: controller.text.length);
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                        labelText: 'University scope',
                        hintText: 'Type a university name',
                        border: OutlineInputBorder()),
                    onChanged: (value) {
                      _universityController.text = value;
                      if (value != 'Urdaneta City University' &&
                          value != 'Pangasinan State University') {
                        setState(() => _universityCode = '');
                      }
                    },
                    validator: (_) => _universityCode.isEmpty
                        ? 'Select a matching university suggestion.'
                        : null,
                  );
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
            ..._admins.map((admin) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title:
                        Text(admin['name']?.toString() ?? 'University Admin'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(admin['email']?.toString() ?? 'No email'),
                        const SizedBox(height: 4),
                        Text(
                            'University: ${admin['university_code'] ?? 'Unassigned'}'),
                        const SizedBox(height: 4),
                        Text(
                          admin['access_frozen'] == true
                              ? 'Subadmin access: Frozen'
                              : 'Subadmin access: Active',
                          style: TextStyle(
                            color: admin['access_frozen'] == true
                                ? Colors.red
                                : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') _startEdit(admin);
                        if (value == 'unbind') await _unbindGoogle(admin);
                        if (value == 'delete') await _deleteAdmin(admin);
                        if (value == 'freeze') {
                          await _manageUniversityAccess(admin, true);
                        }
                        if (value == 'unfreeze') {
                          await _manageUniversityAccess(admin, false);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'freeze',
                          child: Text('Freeze access for ${admin['university_code']}'),
                        ),
                        PopupMenuItem(
                          value: 'unfreeze',
                          child: Text('Restore access for ${admin['university_code']}'),
                        ),
                        const PopupMenuItem(
                            value: 'unbind',
                            child: Text('Remove Google binding')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
