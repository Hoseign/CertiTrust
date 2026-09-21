import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _universityCode = 'UCU';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _createAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ApiService.createAdminAccount(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        universityCode: _universityCode,
      );
      if (!mounted) return;
      _formKey.currentState!.reset();
      _nameController.clear();
      _emailController.clear();
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
      appBar: AppBar(title: const Text('Administrator Management')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Create University Administrator', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Register an administrator account for a university. The administrator can sign in with the registered Google account.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Administrator name', border: OutlineInputBorder()),
                validator: (value) => value == null || value.trim().isEmpty ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 14),
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
              DropdownButtonFormField<String>(
                initialValue: _universityCode,
                decoration: const InputDecoration(labelText: 'University scope', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'UCU', child: Text('Urdaneta City College')),
                  DropdownMenuItem(value: 'PSU', child: Text('Pangasinan State University')),
                ],
                onChanged: (value) => setState(() => _universityCode = value ?? 'UCU'),
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