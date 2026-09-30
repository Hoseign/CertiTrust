import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
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

  Future<void> _requestDeletion(Map<String, dynamic> record) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request credential deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student: ${record['student_name'] ?? 'Student'}'),
            Text('Student ID: ${record['student_id'] ?? 'N/A'}'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Explain why this credential should be deleted',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send),
            label: const Text('Send request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    try {
      await ApiService.requestCertificateDeletion(
        certificateId: record['id'].toString(),
        reason: reasonController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request sent to the Super Admin for review.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send deletion request: $error')),
        );
      }
    } finally {
      reasonController.dispose();
    }
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
    ]
        .whereType<Object>()
        .any((value) => value.toString().toLowerCase().contains(query));
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
                    ? const Center(
                        child: Text('No matching certificate records.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final record = records[index];
                          return ListTile(
                            leading:
                                const Icon(Icons.verified, color: Colors.green),
                            title: Text(record['student_name']?.toString() ??
                                'Student'),
                            subtitle: Text(
                                '${record['degree'] ?? 'Credential'}\nID: ${record['student_id'] ?? 'N/A'}\n${record['student_email'] ?? record['email'] ?? ''}'),
                            isThreeLine: true,
                            trailing: ApiService.authRole == 'admin' &&
                                    !ApiService.isSuperAdmin
                                ? IconButton(
                                    tooltip: 'Request deletion approval',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _requestDeletion(record),
                                  )
                                : null,
                            onTap: () => context
                                .push('/verify?hash=${record['cert_hash']}'),
                          );
                        },
                      ),
              ),
            ]);
          },
        ),
        bottomNavigationBar:
            RoleBottomNavigationBar(isAdmin: ApiService.authRole == 'admin'),
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSaving = false;

  String? get _defaultLogo {
    if (ApiService.isSuperAdmin) return 'web/assets/images/certitrustlogo.png';
    if (ApiService.authRole == 'admin') {
      return ApiService.authUniversity == 'PSU'
          ? 'web/assets/images/PSU_LOGO.png'
          : ApiService.authUniversity == 'UCU'
              ? 'web/assets/images/UCU_LOGO.png'
              : null;
    }
    return null;
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null || !mounted) return;
    await _saveProfile(imageBytes: file!.bytes, imageName: file.name);
  }

  Future<void> _saveProfile(
      {String? icon, List<int>? imageBytes, String? imageName}) async {
    setState(() => _isSaving = true);
    try {
      await ApiService.updateProfile(
        profileIcon: icon,
        imageBytes: imageBytes,
        imageName: imageName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated.')),
        );
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update profile: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiService.authProfileImageUrl;
    final defaultLogo = _defaultLogo;
    final ImageProvider? avatarImage = imageUrl != null && imageUrl.isNotEmpty
        ? NetworkImage(imageUrl)
        : defaultLogo != null
            ? AssetImage(defaultLogo)
            : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundImage: avatarImage,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: avatarImage == null
                  ? Icon(
                      ApiService.authProfileIcon == 'girl'
                          ? Icons.face_3_rounded
                          : ApiService.authProfileIcon == 'boy'
                              ? Icons.face_rounded
                              : Icons.person,
                      size: 48,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(ApiService.authEmail ?? 'Account',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 8),
          Center(
              child: Text('School: ${ApiService.authUniversity ?? 'Global'}')),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _pickPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose photo from gallery'),
          ),
          if (ApiService.authRole != 'admin') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _isSaving ? null : () => _saveProfile(icon: 'girl'),
                    icon: const Icon(Icons.face_3_rounded),
                    label: const Text('Girl avatar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _isSaving ? null : () => _saveProfile(icon: 'boy'),
                    icon: const Icon(Icons.face_rounded),
                    label: const Text('Boy avatar'),
                  ),
                ),
              ],
            ),
          ],
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        isAdmin: ApiService.authRole == 'admin',
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final bool isAdmin;
  final String? initialContactId;
  const ChatScreen({super.key, required this.isAdmin, this.initialContactId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  PlatformFile? _attachment;
  Map<String, dynamic>? _selectedContact;
  Map<String, dynamic>? _replyTo;
  double _horizontalDrag = 0;
  late Future<List<Map<String, dynamic>>> _items;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _items = widget.initialContactId == null
        ? ApiService.getChatContacts()
        : _loadInitialConversation(widget.initialContactId!);
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        _items = _selectedContact == null
            ? ApiService.getChatContacts(search: _searchController.text)
            : ApiService.getChatMessagesForStudent(
                _selectedContact!['id'].toString());
      });
    });
  }

  Future<List<Map<String, dynamic>>> _loadInitialConversation(
      String contactId) async {
    final contacts = await ApiService.getChatContacts();
    for (final contact in contacts) {
      if (contact['id'].toString() == contactId) {
        _selectedContact = contact;
        final messages = await ApiService.getChatMessagesForStudent(contactId);
        if (mounted) {
          setState(() => _items = Future.value(messages));
        }
        return messages;
      }
    }
    return contacts;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _searchStudents(String value) {
    if (_selectedContact == null) {
      setState(() => _items = ApiService.getChatContacts(search: value));
    }
  }

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();
    if (message.isEmpty && _attachment == null) return;
    final sent = await ApiService.sendChatMessage(message,
        recipientUserId: _selectedContact?['id']?.toString(),
        fileBytes: _attachment?.bytes,
        fileName: _attachment?.name,
        replyToId: _replyTo?['id']?.toString());
    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message could not be sent.')));
      return;
    }
    _controller.clear();
    setState(() {
      _attachment = null;
      _replyTo = null;
      _items = ApiService.getChatMessagesForStudent(
          _selectedContact!['id'].toString());
    });
  }

  Future<void> _reportSubadmin() async {
    final subadmin = _selectedContact;
    if (subadmin == null) return;
    final reasonController = TextEditingController();
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report school administrator'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Describe your concern',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send),
            label: const Text('Send to Super Admin'),
          ),
        ],
      ),
    );
    if (shouldSend != true || !mounted) {
      reasonController.dispose();
      return;
    }

    try {
      final contacts = await ApiService.getChatContacts();
      final superAdmin = contacts
          .where((contact) => contact['role_label'] == 'Report to Super Admin')
          .firstOrNull;
      if (superAdmin == null)
        throw Exception('Super Admin contact is unavailable.');
      final reason = reasonController.text.trim();
      if (reason.isEmpty) throw Exception('Enter a concern before sending.');
      final sent = await ApiService.sendChatMessage(
        'Report about ${subadmin['name']} (${subadmin['email']}): $reason',
        recipientUserId: superAdmin['id'].toString(),
        isReport: true,
      );
      if (!sent) throw Exception('The report could not be delivered.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your report was sent to the Super Admin.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send report: $error')),
        );
      }
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'mp4', 'mov', 'webm'],
        withData: true);
    if (result != null && result.files.single.bytes != null)
      setState(() => _attachment = result.files.single);
  }

  Future<void> _deleteMessage(Map<String, dynamic> message,
      {bool forEveryone = false}) async {
    final id = message['id'];
    if (id == null) return;
    final ok = await ApiService.deleteChatMessage(int.parse(id.toString()),
        forEveryone: forEveryone);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This message could not be deleted.')));
      return;
    }
    setState(() {
      _items = ApiService.getChatMessagesForStudent(
          _selectedContact!['id'].toString());
    });
  }

  Future<void> _clearConversation({bool forEveryone = false}) async {
    if (_selectedContact == null) return;
    final ok = await ApiService.clearChatConversation(
        _selectedContact!['id'].toString(),
        forEveryone: forEveryone);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The conversation could not be cleared.')));
      return;
    }
    setState(() {
      _items = ApiService.getChatMessagesForStudent(
          _selectedContact!['id'].toString());
    });
  }

  void _showUserProfile(Map<String, dynamic>? profile) {
    if (profile == null) return;
    final name = profile['name']?.toString() ?? 'Profile';
    final imageUrl = profile['profile_image_url']?.toString();
    final imageAsset = profile['profile_logo']?.toString();
    final ImageProvider? avatarImage = imageUrl != null && imageUrl.isNotEmpty
        ? NetworkImage(imageUrl)
        : imageAsset != null && imageAsset.isNotEmpty
            ? AssetImage(imageAsset)
            : null;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Icon(profile['profile_icon'] == 'girl'
                          ? Icons.face_3_rounded
                          : profile['profile_icon'] == 'boy'
                              ? Icons.face_rounded
                              : Icons.person)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('Email: ${profile['email']?.toString() ?? 'Not available'}'),
              const SizedBox(height: 8),
              Text('Role: ${profile['role_label']?.toString() ?? 'Contact'}'),
              const SizedBox(height: 8),
              Text(
                  'Status: ${profile['is_active'] == true ? 'Online' : 'Offline'}'),
              const SizedBox(height: 8),
              Text(profile['last_seen_label']?.toString() ??
                  'Last active: unknown'),
              if (profile['student_id'] != null) ...[
                const SizedBox(height: 8),
                Text('Student ID: ${profile['student_id']}'),
              ],
              if (profile['degree'] != null) ...[
                const SizedBox(height: 8),
                Text('Degree: ${profile['degree']}'),
              ],
              if (profile['university_code'] != null) ...[
                const SizedBox(height: 8),
                Text('School: ${profile['university_code']}'),
              ],
              if (profile['issue_date'] != null) ...[
                const SizedBox(height: 8),
                Text('Issued: ${profile['issue_date']}'),
              ],
              if (profile['certificate_code'] != null) ...[
                const SizedBox(height: 8),
                Text('Credential code: ${profile['certificate_code']}'),
              ],
              if (profile['cert_hash'] != null) ...[
                const SizedBox(height: 8),
                SelectableText('SHA-256: ${profile['cert_hash']}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  Widget _contactsBody() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final contacts = snapshot.data ?? const <Map<String, dynamic>>[];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: TextField(
                  controller: _searchController,
                  onChanged: _searchStudents,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search people or credentials',
                      border: OutlineInputBorder())),
            ),
            Expanded(
              child: contacts.isEmpty
                  ? const Center(child: Text('No matching contacts found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final active = contact['is_active'] == true;
                        final displayName =
                            contact['name']?.toString() ?? 'Contact';
                        final imageUrl =
                            contact['profile_image_url']?.toString();
                        final imageAsset = contact['profile_logo']?.toString();
                        final ImageProvider? avatarImage =
                            imageUrl != null && imageUrl.isNotEmpty
                                ? NetworkImage(imageUrl)
                                : imageAsset != null && imageAsset.isNotEmpty
                                    ? AssetImage(imageAsset)
                                    : null;
                        return ListTile(
                          leading: Stack(children: [
                            CircleAvatar(
                              backgroundImage: avatarImage,
                              child: avatarImage == null
                                  ? Icon(contact['profile_icon'] == 'girl'
                                      ? Icons.face_3_rounded
                                      : contact['profile_icon'] == 'boy'
                                          ? Icons.face_rounded
                                          : Icons.person)
                                  : null,
                            ),
                            if (active)
                              Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2))))
                          ]),
                          title: Text(displayName),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(contact['role_label']?.toString() ?? ''),
                                if (contact['student_id'] != null)
                                  Text('Student ID: ${contact['student_id']}'),
                                Text(
                                    contact['last_seen_label']?.toString() ??
                                        'Last active: unknown',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey))
                              ]),
                          trailing: IconButton(
                            tooltip: 'View profile and credential details',
                            icon: const Icon(Icons.more_horiz),
                            onPressed: () => _showUserProfile(contact),
                          ),
                          onTap: () => setState(() {
                            _selectedContact = contact;
                            _items = ApiService.getChatMessagesForStudent(
                                contact['id'].toString());
                            _replyTo = null;
                          }),
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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final messages = snapshot.data ?? const <Map<String, dynamic>>[];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final attachmentUrl = message['attachment_url']?.toString();
              final own = message['sender_email'] == ApiService.authEmail;
              final quoted = message['reply_to'] is Map
                  ? Map<String, dynamic>.from(message['reply_to'] as Map)
                  : null;
              return GestureDetector(
                onHorizontalDragUpdate: (details) {
                  _horizontalDrag += details.delta.dx;
                },
                onHorizontalDragEnd: (_) {
                  if (_horizontalDrag.abs() > 55 && mounted) {
                    setState(() => _replyTo = message);
                  }
                  _horizontalDrag = 0;
                },
                child: Align(
                  alignment: own ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Card(
                      color: own ? Colors.blue.shade50 : Colors.grey.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    message['sender_name']?.toString() ??
                                        'User',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (message['is_report'] == true)
                                  const Icon(Icons.flag_outlined, size: 16),
                                if (own)
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.more_vert, size: 18),
                                    onSelected: (value) async {
                                      if (value == 'delete_me')
                                        await _deleteMessage(message);
                                      if (value == 'delete_everyone') {
                                        await _deleteMessage(message,
                                            forEveryone: true);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                          value: 'delete_me',
                                          child: Text('Delete for me')),
                                      PopupMenuItem(
                                          value: 'delete_everyone',
                                          child: Text('Delete for everyone')),
                                    ],
                                  ),
                              ],
                            ),
                            if (quoted != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(15),
                                  border: const Border(
                                      left: BorderSide(
                                          color: Colors.blue, width: 3)),
                                ),
                                child: Text(
                                  '${quoted['sender_name'] ?? 'Message'}: ${quoted['message'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if ((message['message']?.toString() ?? '')
                                .isNotEmpty)
                              Text(message['message'].toString()),
                            if (attachmentUrl != null &&
                                message['attachment_type'] == 'image')
                              Image.network(attachmentUrl,
                                  width: 180, height: 180, fit: BoxFit.cover),
                            if (attachmentUrl != null &&
                                message['attachment_type'] == 'video')
                              Text('Video attachment: $attachmentUrl'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _selectedContact == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _selectedContact != null)
            setState(() {
              _selectedContact = null;
              _items =
                  ApiService.getChatContacts(search: _searchController.text);
            });
        },
        child: Scaffold(
          appBar: AppBar(
            title: _selectedContact != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedContact!['is_active'] == true)
                            const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.circle,
                                    color: Colors.green, size: 10)),
                          Flexible(
                              child: Text(
                                  _selectedContact!['name']?.toString() ??
                                      'Chat')),
                        ],
                      ),
                      Text(
                        _selectedContact!['last_seen_label']?.toString() ??
                            'Last active: unknown',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.normal),
                      ),
                    ],
                  )
                : const Text('Messages'),
            leading: _selectedContact != null
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() {
                          _selectedContact = null;
                          _replyTo = null;
                          _items = ApiService.getChatContacts(
                              search: _searchController.text);
                        }))
                : null,
            actions: _selectedContact != null
                ? [
                    if (!widget.isAdmin &&
                        _selectedContact!['role_label'] ==
                            'School administrator')
                      IconButton(
                        tooltip: 'Report this administrator to Super Admin',
                        icon: const Icon(Icons.flag_outlined),
                        onPressed: _reportSubadmin,
                      ),
                    IconButton(
                      tooltip: 'View contact details',
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () => _showUserProfile(_selectedContact),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'delete_me') await _clearConversation();
                        if (value == 'delete_everyone')
                          await _clearConversation(forEveryone: true);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                            value: 'delete_me',
                            child: Text('Delete chat for me')),
                        PopupMenuItem(
                            value: 'delete_everyone',
                            child: Text('Delete chat for everyone')),
                      ],
                    ),
                  ]
                : null,
          ),
          body: Column(children: [
            Expanded(
                child: _selectedContact == null
                    ? _contactsBody()
                    : _messagesBody()),
            if (_selectedContact != null) ...[
              if (_replyTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(15),
                      border: const Border(
                          left: BorderSide(color: Colors.blue, width: 3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Replying to ${_replyTo!['sender_name'] ?? 'message'}: ${_replyTo!['message'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel reply',
                          onPressed: () => setState(() => _replyTo = null),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_attachment != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Attached: ${_attachment!.name}'))),
              SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        IconButton(
                            icon: const Icon(Icons.attach_file),
                            tooltip: 'Attach image or video',
                            onPressed: _pickAttachment),
                        Expanded(
                            child: TextField(
                                controller: _controller,
                                decoration: const InputDecoration(
                                    hintText: 'Type your message...',
                                    border: OutlineInputBorder()))),
                        IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: _sendMessage)
                      ]))),
            ],
          ]),
          bottomNavigationBar: RoleBottomNavigationBar(isAdmin: widget.isAdmin),
        ),
      );
}

class RoleBottomNavigationBar extends StatelessWidget {
  final bool isAdmin;
  const RoleBottomNavigationBar({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = isAdmin && ApiService.isSuperAdmin;
    final routes = isSuperAdmin
        ? const ['/dashboard', '/records', '/verify', '/ansq']
        : isAdmin
            ? const ['/dashboard', '/records', '/issue', '/verify', '/ansq']
            : const ['/dashboard', '/records', '/verify', '/profile', '/askq'];
    final currentIndex = routes.indexOf(GoRouterState.of(context).uri.path);

    if (currentIndex < 0) return const SizedBox.shrink();

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      items: isSuperAdmin
          ? const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.folder), label: 'Records'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.verified), label: 'Verify'),
              BottomNavigationBarItem(icon: Icon(Icons.help), label: 'AnsQ'),
            ]
          : isAdmin
              ? const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.home), label: 'Home'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.folder), label: 'Records'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.upload), label: 'Upload'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.verified), label: 'Verify'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.help), label: 'AnsQ'),
                ]
              : const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.home), label: 'Home'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.folder), label: 'Records'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.qr_code_scanner), label: 'Verify'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.person), label: 'Profile'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.help), label: 'AskQ'),
                ],
      onTap: (index) {
        if (index != currentIndex) context.go(routes[index]);
      },
    );
  }
}
