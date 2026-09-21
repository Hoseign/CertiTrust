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
  final _universityController = TextEditingController(text: 'Urdaneta City University');
  String _universityCode = 'UCU';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _universityController.dispose();
    super.dispose();
  }

  Future<void> _createAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ApiService.createAdminAccount(
        email: _emailController.text.trim(),
        universityCode: _universityCode,
      );
      if (!mounted) return;
      _formKey.currentState!.reset();
      _emailController.clear();
      _universityController.text = 'Urdaneta City University';
      _universityCode = 'UCU';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Administrator account created.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
          const Text('Create Subadmin Account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Register an administrator account for a university. The administrator can sign in with the registered Google account.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Google account email', border: OutlineInputBorder()),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.contains('@') ? null : 'Enter a valid email.';
                },
              ),
              const SizedBox(height: 14),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _universityController.text),
                optionsBuilder: (textEditingValue) {
                  const universities = [
                    'Urdaneta City University',
                    'Pangasinan State University',
                  ];
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) return universities;
                  return universities.where((university) => university.toLowerCase().contains(query));
                },
                onSelected: (university) {
                  _universityController.text = university;
                  setState(() => _universityCode = university == 'Urdaneta City University' ? 'UCU' : 'PSU');
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  controller.text = _universityController.text;
                  controller.selection = TextSelection.collapsed(offset: controller.text.length);
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'University scope', hintText: 'Type a university name', border: OutlineInputBorder()),
                    onChanged: (value) {
                      _universityController.text = value;
                      if (value != 'Urdaneta City University' && value != 'Pangasinan State University') {
                        setState(() => _universityCode = '');
                      }
                    },
                    validator: (_) => _universityCode.isEmpty ? 'Select a matching university suggestion.' : null,
                  );
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _createAdmin,
                  icon: _isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person_add),
                  label: const Text('Create administrator account'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}