import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _records;

  @override
  void initState() {
    super.initState();
    _records = ApiService.getCertificatesForCurrentUser();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> record, String query) {
    if (query.isEmpty) return true;
    return [
      record['student_name'],
      record['student_id'],
      record['student_email'],
      record['email'],
      record['degree'],
      record['certificate_code'],
      record['cert_hash'],
      record['university_code'],
    ].whereType<Object>().any((value) => value.toString().toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Certificate Records')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _records,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final query = _searchController.text.trim().toLowerCase();
            final records = (snapshot.data ?? const <Map<String, dynamic>>[])
                .where((record) => _matches(record, query))
                .toList();
            return Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search credentials',
                    hintText: 'Name, ID, email, degree, hash or code',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? const Center(child: Text('No matching certificate records.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final record = records[index];
                          return ListTile(
                            leading: const Icon(Icons.verified, color: Colors.green),
                            title: Text(record['student_name']?.toString() ?? 'Student'),
                            subtitle: Text('${record['degree'] ?? 'Credential'}\nID: ${record['student_id'] ?? 'N/A'}\n${record['student_email'] ?? record['email'] ?? ''}'),
                            isThreeLine: true,
                            onTap: () => context.push('/verify?hash=${record['cert_hash']}'),
                          );
                        },
                      ),
              ),
            ]);
          },
        ),
        bottomNavigationBar: _RoleNav(isAdmin: ApiService.authRole == 'admin'),
      );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 44)),
            const SizedBox(height: 16),
            Center(child: Text(ApiService.authEmail ?? 'Student', style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: 8),
            Center(child: Text('School: ${ApiService.authUniversity ?? 'Not assigned'}')),
          ],
        ),
        bottomNavigationBar: const _RoleNav(isAdmin: false),
      );
}

class ChatScreen extends StatefulWidget {
  final bool isAdmin;
  const ChatScreen({super.key, required this.isAdmin});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  PlatformFile? _attachment;
  Map<String, dynamic>? _selectedStudent;
  late Future<List<Map<String, dynamic>>> _items;
  late Future<List<Map<String, dynamic>>> _presence;

  @override
  void initState() {
    super.initState();
    _items = widget.isAdmin ? ApiService.getChatContacts() : ApiService.getChatMessages();
    _presence = ApiService.getChatPresence();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _searchStudents(String value) {
    if (widget.isAdmin && _selectedStudent == null) {
      setState(() => _items = ApiService.getChatContacts(search: value));
    }
  }

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();
    if (message.isEmpty && _attachment == null) return;
    final sent = await ApiService.sendChatMessage(message, recipientUserId: _selectedStudent?['id']?.toString(), fileBytes: _attachment?.bytes, fileName: _attachment?.name);
    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message could not be sent.')));
      return;
    }
    _controller.clear();
    setState(() {
      _attachment = null;
      _items = _selectedStudent == null ? ApiService.getChatMessages() : ApiService.getChatMessagesForStudent(_selectedStudent!['id'].toString());
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'mp4', 'mov', 'webm'], withData: true);
    if (result != null && result.files.single.bytes != null) setState(() => _attachment = result.files.single);
  }

  TextSpan _highlight(String value, String query) {
    if (query.isEmpty) return TextSpan(text: value);
    final start = value.toLowerCase().indexOf(query.toLowerCase());
    if (start < 0) return TextSpan(text: value);
    return TextSpan(children: [
      TextSpan(text: value.substring(0, start)),
      TextSpan(text: value.substring(start, start + query.length), style: const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Colors.yellow)),
      TextSpan(text: value.substring(start + query.length)),
    ]);
  }

  Widget _contactsBody() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final contacts = snapshot.data ?? const <Map<String, dynamic>>[];
          final query = _searchController.text.trim();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: TextField(controller: _searchController, onChanged: _searchStudents, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search students or credentials', border: OutlineInputBorder())),
            ),
            Expanded(
              child: contacts.isEmpty
                  ? const Center(child: Text('No matching students found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final field = contact['matched_field']?.toString();
                        final value = field == 'student_id' ? contact['student_id']?.toString() : field == 'email' ? contact['email']?.toString() : field == 'degree' ? contact['degree']?.toString() : field == 'certificate_code' ? contact['certificate_code']?.toString() : null;
                        final active = contact['is_active'] == true;
                        return ListTile(
                          leading: Stack(children: [const CircleAvatar(child: Icon(Icons.person)), if (active) Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))]),
                          title: Text(contact['name']?.toString() ?? 'Student'),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (value != null) RichText(text: _highlight(value, query)), Text(contact['last_seen_label']?.toString() ?? 'Last active: unknown', style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() { _selectedStudent = contact; _items = ApiService.getChatMessagesForStudent(contact['id'].toString()); }),
                        );
                      },
                    ),
            ),
          ]);
        },
      );

  Widget _messagesBody() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final messages = snapshot.data ?? const <Map<String, dynamic>>[];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final attachmentUrl = message['attachment_url']?.toString();
              final own = message['sender_email'] == ApiService.authEmail;
              return Align(alignment: own ? Alignment.centerRight : Alignment.centerLeft, child: Card(color: own ? Colors.blue.shade50 : Colors.grey.shade100, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message['sender_name']?.toString() ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)), if ((message['message']?.toString() ?? '').isNotEmpty) Text(message['message'].toString()), if (attachmentUrl != null && message['attachment_type'] == 'image') Image.network(attachmentUrl, width: 180, height: 180, fit: BoxFit.cover), if (attachmentUrl != null && message['attachment_type'] == 'video') Text('Video attachment: $attachmentUrl')]))));
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !widget.isAdmin || _selectedStudent == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && widget.isAdmin && _selectedStudent != null) setState(() { _selectedStudent = null; _items = ApiService.getChatContacts(); });
        },
        child: Scaffold(
          appBar: AppBar(
            title: widget.isAdmin && _selectedStudent != null
                ? Text('Chat: ${_selectedStudent!['name']}')
                : widget.isAdmin
                    ? const Text('AnsQ: Students')
                    : FutureBuilder<List<Map<String, dynamic>>>(
                        future: _presence,
                        builder: (context, snapshot) {
                          final admin = snapshot.data?.isNotEmpty == true ? snapshot.data!.first : null;
                          return Row(children: [
                            if (admin?['is_active'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.circle, color: Colors.green, size: 10)),
                            Text(admin?['name']?.toString() ?? 'AskQ: Chat With Admin'),
                          ]);
                        },
                      ),
            leading: widget.isAdmin && _selectedStudent != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() { _selectedStudent = null; _items = ApiService.getChatContacts(); })) : null,
          ),
          body: Column(children: [
            Expanded(child: widget.isAdmin && _selectedStudent == null ? _contactsBody() : _messagesBody()),
            if (!widget.isAdmin || _selectedStudent != null) ...[
              if (_attachment != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Align(alignment: Alignment.centerLeft, child: Text('Attached: ${_attachment!.name}'))),
              SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [IconButton(icon: const Icon(Icons.attach_file), tooltip: 'Attach image or video', onPressed: _pickAttachment), Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Type your message...', border: OutlineInputBorder()))), IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage)]))),
            ],
          ]),
          bottomNavigationBar: _RoleNav(isAdmin: widget.isAdmin),
        ),
      );
}

class _RoleNav extends StatelessWidget {
  final bool isAdmin;
  const _RoleNav({required this.isAdmin});

  @override
  Widget build(BuildContext context) => BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: isAdmin
            ? const [BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'), BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Records'), BottomNavigationBarItem(icon: Icon(Icons.upload), label: 'Upload'), BottomNavigationBarItem(icon: Icon(Icons.verified), label: 'Verify'), BottomNavigationBarItem(icon: Icon(Icons.help), label: 'AnsQ')]
            : const [BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'), BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Records'), BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Verify'), BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'), BottomNavigationBarItem(icon: Icon(Icons.help), label: 'AskQ')],
        onTap: (index) {
          final routes = isAdmin ? const ['/dashboard', '/records', '/issue', '/verify', '/ansq'] : const ['/dashboard', '/records', '/verify', '/profile', '/askq'];
          if (index != 0) context.push(routes[index]);
        },
      );
}
