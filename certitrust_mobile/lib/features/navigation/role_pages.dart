import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../dashboard/widgets/diploma_preview.dart';

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
                          final diplomaUrl =
                              record['diploma_url'] ?? record['cert_image_url'];
                          return ListTile(
                            leading:
                                const Icon(Icons.verified, color: Colors.green),
                            title: Text(record['student_name']?.toString() ??
                                'Student'),
                            subtitle: Text(
                                '${record['degree'] ?? 'Credential'}\nID: ${record['student_id'] ?? 'N/A'}\n${record['student_email'] ?? record['email'] ?? ''}'),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (diplomaUrl != null &&
                                    diplomaUrl.toString().isNotEmpty)
                                  IconButton(
                                    tooltip: 'View diploma image',
                                    icon: const Icon(Icons.visibility_outlined),
                                    onPressed: () => showDiplomaPreview(
                                        context, diplomaUrl.toString()),
                                  ),
                                if (ApiService.authRole == 'admin' &&
                                    !ApiService.isSuperAdmin)
                                  IconButton(
                                    tooltip: 'Request deletion approval',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _requestDeletion(record),
                                  ),
                              ],
                            ),
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
  final _messagesScrollController = ScrollController();
  PlatformFile? _attachment;
  Map<String, dynamic>? _selectedContact;
  Map<String, dynamic>? _replyTo;
  final Map<String, double> _messageDragOffsets = {};
  List<Map<String, dynamic>> _items = [];
  String? _pendingInitialContactId;
  Object? _loadError;
  int _loadGeneration = 0;
  bool _isLoading = true;
  bool _hasLoaded = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _pendingInitialContactId = widget.initialContactId;
    _loadItems();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadItems();
    });
  }

  Future<void> _loadItems({
    bool showLoading = false,
    bool reportErrors = false,
  }) async {
    final generation = ++_loadGeneration;
    final selectedContact = _selectedContact;
    final search = _searchController.text;
    final wasAtBottom = !_messagesScrollController.hasClients ||
        _messagesScrollController.position.maxScrollExtent -
                _messagesScrollController.position.pixels <=
            120;
    if (showLoading && !_hasLoaded) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      List<Map<String, dynamic>> items;
      if (selectedContact != null) {
        items = await ApiService.getChatMessagesForStudent(
            selectedContact['id'].toString());
      } else {
        items = await ApiService.getChatContacts(search: search);
        final initialContactId = _pendingInitialContactId;
        _pendingInitialContactId = null;
        if (initialContactId != null) {
          final contact = items
              .where((item) => item['id'].toString() == initialContactId)
              .firstOrNull;
          if (contact != null) {
            _selectedContact = contact;
            items =
                await ApiService.getChatMessagesForStudent(initialContactId);
          }
        }
      }

      if (!mounted || generation != _loadGeneration) return;
      final previousLastMessageId =
          _items.isEmpty ? null : _items.last['id']?.toString();
      final nextLastMessageId =
          items.isEmpty ? null : items.last['id']?.toString();
      final shouldFollowNewMessages = _selectedContact != null &&
          (!_hasLoaded ||
              (items.length > _items.length &&
                  nextLastMessageId != previousLastMessageId &&
                  wasAtBottom));
      setState(() {
        _items = items;
        _isLoading = false;
        _hasLoaded = true;
        _loadError = null;
      });
      if (shouldFollowNewMessages) _scrollMessagesToLatest();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = error;
      });
      if (reportErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh this chat: $error')),
        );
      }
    }
  }

  Widget _loadErrorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load this chat.'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _loadItems(showLoading: true),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _refreshErrorBanner() => MaterialBanner(
        content:
            const Text('Could not refresh. Showing previously loaded data.'),
        actions: [
          TextButton(
            onPressed: () => _loadItems(reportErrors: true),
            child: const Text('Retry'),
          ),
        ],
      );

  void _scrollMessagesToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messagesScrollController.hasClients) return;
      _messagesScrollController.animateTo(
        _messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _openContact(Map<String, dynamic> contact) {
    setState(() {
      _selectedContact = contact;
      _items = [];
      _replyTo = null;
      _isLoading = true;
      _hasLoaded = false;
      _loadError = null;
    });
    _loadItems();
  }

  void _closeConversation() {
    setState(() {
      _selectedContact = null;
      _replyTo = null;
      _items = [];
      _isLoading = true;
      _hasLoaded = false;
      _loadError = null;
    });
    _loadItems();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.dispose();
    _searchController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  void _searchStudents(String value) {
    if (_selectedContact == null) {
      _loadItems(showLoading: true, reportErrors: true);
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
    });
    await _loadItems(reportErrors: true);
    _scrollMessagesToLatest();
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
    _loadItems(reportErrors: true);
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
    _loadItems(reportErrors: true);
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

  Widget _contactsBody() {
    if (_isLoading && !_hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && !_hasLoaded) return _loadErrorView();
    final contacts = _items;
    return Column(children: [
      if (_loadError != null) _refreshErrorBanner(),
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
                  final displayName = contact['name']?.toString() ?? 'Contact';
                  final imageUrl = contact['profile_image_url']?.toString();
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
                    onTap: () => _openContact(contact),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _messagesBody() {
    if (_isLoading && !_hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && !_hasLoaded) return _loadErrorView();
    final messages = _items;
    return Column(
      children: [
        if (_loadError != null) _refreshErrorBanner(),
        Expanded(
          child: ListView.builder(
            controller: _messagesScrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final attachmentUrl = message['attachment_url']?.toString();
              final senderEmail =
                  message['sender_email']?.toString().trim().toLowerCase();
              final currentEmail = ApiService.authEmail?.trim().toLowerCase();
              final own = currentEmail != null && senderEmail == currentEmail;
              final quoted = message['reply_to'] is Map
                  ? Map<String, dynamic>.from(message['reply_to'] as Map)
                  : null;
              final messageId = message['id']?.toString() ?? 'message-$index';
              final dragOffset = _messageDragOffsets[messageId] ?? 0.0;
              return GestureDetector(
                onHorizontalDragStart: (_) => setState(() {
                  _messageDragOffsets[messageId] = 0;
                }),
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _messageDragOffsets[messageId] =
                        ((_messageDragOffsets[messageId] ?? 0) +
                                details.delta.dx)
                            .clamp(0.0, 88.0)
                            .toDouble();
                  });
                },
                onHorizontalDragEnd: (_) {
                  final shouldReply =
                      (_messageDragOffsets[messageId] ?? 0) > 55;
                  setState(() {
                    _messageDragOffsets.remove(messageId);
                    if (shouldReply) _replyTo = message;
                  });
                  if (shouldReply) {
                    _controller.selection = TextSelection.collapsed(
                        offset: _controller.text.length);
                  }
                },
                key: ValueKey(messageId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(
                    alignment:
                        own ? Alignment.centerRight : Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      transform: Matrix4.translationValues(dragOffset, 0, 0),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: own
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(own ? 18 : 4),
                              bottomRight: Radius.circular(own ? 4 : 18),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        own
                                            ? 'You'
                                            : message['sender_name']
                                                    ?.toString() ??
                                                'User',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: own
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (message['is_report'] == true)
                                      const Icon(Icons.flag_outlined, size: 16),
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon:
                                          const Icon(Icons.more_vert, size: 18),
                                      onSelected: (value) async {
                                        if (value == 'delete_me') {
                                          await _deleteMessage(message);
                                        } else if (value == 'delete_everyone') {
                                          await _deleteMessage(message,
                                              forEveryone: true);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'delete_me',
                                          child: Text('Delete for me'),
                                        ),
                                        if (own)
                                          const PopupMenuItem(
                                            value: 'delete_everyone',
                                            child: Text('Delete for everyone'),
                                          ),
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
                                      color: own
                                          ? Colors.white.withAlpha(28)
                                          : Colors.black.withAlpha(15),
                                      border: Border(
                                        left: BorderSide(
                                          color: own
                                              ? Colors.white70
                                              : Colors.blue,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${quoted['sender_name'] ?? 'Message'}: ${quoted['message'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: own
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                if ((message['message']?.toString() ?? '')
                                    .isNotEmpty)
                                  Text(
                                    message['message'].toString(),
                                    style: TextStyle(
                                      color:
                                          own ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                if (attachmentUrl != null &&
                                    message['attachment_type'] == 'image')
                                  GestureDetector(
                                    onTap: () => showDialog<void>(
                                      context: context,
                                      builder: (dialogContext) => Dialog(
                                        insetPadding: const EdgeInsets.all(16),
                                        child: InteractiveViewer(
                                          child: SizedBox(
                                            width:
                                                MediaQuery.sizeOf(dialogContext)
                                                        .width *
                                                    0.9,
                                            height:
                                                MediaQuery.sizeOf(dialogContext)
                                                        .height *
                                                    0.8,
                                            child: Image.network(
                                              attachmentUrl,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 260,
                                        height: 320,
                                        child: Image.network(
                                          attachmentUrl,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.medium,
                                          loadingBuilder: (context, child,
                                              loadingProgress) {
                                            if (loadingProgress == null) {
                                              return child;
                                            }
                                            return const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            );
                                          },
                                          errorBuilder:
                                              (context, error, stack) =>
                                                  const Center(
                                            child: Text(
                                                'Image could not be loaded'),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (attachmentUrl != null &&
                                    message['attachment_type'] == 'video')
                                  Text('Video attachment: $attachmentUrl'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _selectedContact == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _selectedContact != null) _closeConversation();
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
                    onPressed: _closeConversation)
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
                  child: Row(
                    children: [
                      if (_attachment!.bytes != null &&
                          !['mp4', 'mov', 'webm']
                              .contains(_attachment!.extension?.toLowerCase()))
                        Image.memory(_attachment!.bytes!,
                            width: 64, height: 64, fit: BoxFit.contain)
                      else
                        const SizedBox(
                            width: 64,
                            height: 64,
                            child: Icon(Icons.video_file_outlined)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_attachment!.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        tooltip: 'Remove attachment',
                        onPressed: () => setState(() => _attachment = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
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
    final branchIndexes = isSuperAdmin
        ? const [0, 1, 3, 5]
        : isAdmin
            ? const [0, 1, 2, 3, 5]
            : const [0, 1, 3, 4, 6];
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
        if (index != currentIndex) {
          StatefulNavigationShell.of(context).goBranch(branchIndexes[index]);
        }
      },
    );
  }
}
