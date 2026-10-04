import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../dashboard/widgets/diploma_preview.dart';
import '../dashboard/widgets/qr_code_dialog.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _records;
  int? _selectedDegreeNumber;
  bool _showMultipleDegreeOrganizer = false;
  String? _selectedMultiDegreeStudent;

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

  bool get _isSchoolAdmin =>
      ApiService.authRole == 'admin' && !ApiService.isSuperAdmin;

  int _degreeNumber(Map<String, dynamic> record) =>
      int.tryParse(record['degree_number']?.toString() ?? '') ?? 1;

  String? _studentGroupKey(Map<String, dynamic> record) {
    final university =
        (record['university_code'] ?? ApiService.authUniversity ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final studentId = record['student_id']?.toString().trim().toLowerCase();
    if (studentId != null && studentId.isNotEmpty) {
      return '$university:id:$studentId';
    }
    final email = (record['student_email'] ?? record['email'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (email != null && email.isNotEmpty) {
      return '$university:email:$email';
    }
    return null;
  }

  Map<String, List<Map<String, dynamic>>> _multipleDegreeGroups(
      List<Map<String, dynamic>> records) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final record in records) {
      final key = _studentGroupKey(record);
      if (key == null) continue;
      grouped.putIfAbsent(key, () => []).add(record);
    }
    return Map.fromEntries(
      grouped.entries.where((entry) =>
          entry.value.map(_degreeNumber).toSet().length >= 2),
    );
  }

  String _ordinal(int number) {
    if (number % 100 >= 11 && number % 100 <= 13) return '${number}th';
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }

  DateTime? _publishedAt(Map<String, dynamic> record) {
    final publishedAt =
        DateTime.tryParse(record['created_at']?.toString() ?? '');
    return publishedAt ??
        DateTime.tryParse(record['issue_date']?.toString() ?? '');
  }

  String _publishedLabel(Map<String, dynamic> record) {
    final publishedAt = _publishedAt(record);
    if (publishedAt == null) return 'N/A';
    final local = publishedAt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      );

  Widget _recordCard(BuildContext context, Map<String, dynamic> record) {
    final diplomaUrl = record['diploma_url'] ?? record['cert_image_url'];
    final diplomaFileName =
        'Diploma_${(record['student_id'] ?? record['student_name'] ?? 'Student').toString().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.jpg';
    final studentId = record['student_id']?.toString() ?? 'N/A';
    final email =
        (record['student_email'] ?? record['email'] ?? 'N/A').toString();
    final verificationCode =
        (record['cert_hash'] ?? record['certificate_code'])?.toString();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('credential-${record['id'] ?? verificationCode}'),
        initiallyExpanded: false,
        leading: const Icon(Icons.school_outlined),
        title: Text(
          record['student_name']?.toString() ?? 'Student',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _recordDetailRow(
              'Student name', record['student_name']?.toString() ?? 'N/A'),
          _recordDetailRow('Student ID', studentId),
          _recordDetailRow(
              'Course / program',
              record['degree']?.toString() ??
                  record['course_or_event']?.toString() ??
                  'N/A'),
          _recordDetailRow('Degree number', _ordinal(_degreeNumber(record))),
          _recordDetailRow('Gmail', email),
          _recordDetailRow('Certificate code',
              record['certificate_code']?.toString() ?? 'N/A'),
          _recordDetailRow(
              'Issue date', record['issue_date']?.toString() ?? 'N/A'),
          _recordDetailRow('Published', _publishedLabel(record)),
          _recordDetailRow('Status', record['status']?.toString() ?? 'Issued'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: verificationCode == null || verificationCode.isEmpty
                    ? null
                    : () => context.go(
                        '/verify?hash=${Uri.encodeQueryComponent(verificationCode)}'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verify this record'),
              ),
              TextButton.icon(
                onPressed: diplomaUrl == null || diplomaUrl.toString().isEmpty
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'No diploma image was attached to this credential.'),
                          ),
                        )
                    : () => showDiplomaPreview(
                          context,
                          diplomaUrl.toString(),
                          fileName: diplomaFileName,
                        ),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text(
                    _isSchoolAdmin ? 'View This Diploma' : 'View Your Diploma'),
              ),
              if (_isSchoolAdmin)
                TextButton.icon(
                  onPressed: () => context.push('/issue', extra: record),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add another degree'),
                ),
              if (_isSchoolAdmin)
                TextButton.icon(
                  onPressed: () => _requestDeletion(record),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Request deletion'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Certificate Records'),
          actions: [
            if (_isSchoolAdmin)
              IconButton(
                onPressed: () => context.push('/student-access'),
                icon: const Icon(Icons.manage_accounts_outlined),
                tooltip: 'Manage student account access',
              ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _records,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final query = _searchController.text.trim().toLowerCase();
            final allRecords = snapshot.data ?? const <Map<String, dynamic>>[];
            final searchedRecords =
                allRecords.where((record) => _matches(record, query)).toList();
            final Map<String, List<Map<String, dynamic>>> multipleDegreeGroups =
                _isSchoolAdmin ? _multipleDegreeGroups(allRecords) : {};
            if (_selectedMultiDegreeStudent != null &&
                !multipleDegreeGroups
                    .containsKey(_selectedMultiDegreeStudent)) {
              _selectedMultiDegreeStudent = null;
            }
            final degreeNumbers = allRecords.map(_degreeNumber).toSet().toList()
              ..sort();
            final visibleRecords =
                _isSchoolAdmin &&
                        !_showMultipleDegreeOrganizer &&
                        _selectedDegreeNumber != null
                    ? searchedRecords
                        .where((record) =>
                            _degreeNumber(record) == _selectedDegreeNumber)
                        .toList()
                    : searchedRecords;
            final content = <Widget>[];
            if (_isSchoolAdmin && multipleDegreeGroups.isNotEmpty) {
              content.add(_sectionHeader('Multiple degrees'));
              content.add(
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(
                          'Students with multiple degrees (${multipleDegreeGroups.length})'),
                      selected: _showMultipleDegreeOrganizer,
                      onSelected: (selected) => setState(() {
                        _showMultipleDegreeOrganizer = selected;
                        if (!selected) _selectedMultiDegreeStudent = null;
                      }),
                    ),
                    if (_showMultipleDegreeOrganizer)
                      for (final entry in multipleDegreeGroups.entries)
                        ChoiceChip(
                          label: Text(
                            '${entry.value.first['student_name'] ?? entry.value.first['recipient_name'] ?? 'Student'} '
                            '(${entry.value.map(_degreeNumber).toSet().length} degrees)',
                          ),
                          selected: _selectedMultiDegreeStudent == entry.key,
                          onSelected: (_) => setState(
                              () => _selectedMultiDegreeStudent = entry.key),
                        ),
                  ],
                ),
              );
              if (_showMultipleDegreeOrganizer &&
                  _selectedMultiDegreeStudent != null) {
                final selectedDegrees = multipleDegreeGroups[
                        _selectedMultiDegreeStudent]!
                    .toList()
                  ..sort((a, b) =>
                      _degreeNumber(a).compareTo(_degreeNumber(b)));
                final firstDegree = selectedDegrees.first;
                final qrHash =
                    (firstDegree['cert_hash'] ?? firstDegree['certificate_code'])
                        ?.toString();
                final multiDegreeCode = qrHash == null || qrHash.isEmpty
                    ? null
                    : 'CERTITRUST-MULTI:$qrHash';
                content.add(
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: multiDegreeCode == null
                                ? null
                                : () => showQRCodeDialog(
                                      context,
                                      firstDegree,
                                      code: multiDegreeCode,
                                      title:
                                          'All ${selectedDegrees.length} Degrees',
                                    ),
                            icon: const Icon(Icons.qr_code),
                            label: const Text('Show combined QR'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: multiDegreeCode == null
                                ? null
                                : () => context.push(
                                      '/verify?hash=${Uri.encodeQueryComponent(multiDegreeCode)}',
                                    ),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Verify all degrees'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                content.addAll(selectedDegrees.map(
                    (record) => _recordCard(context, record)));
              } else if (_showMultipleDegreeOrganizer) {
                content.add(const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Select a student to view their degrees and QR.'),
                ));
              }
            }
            if (_isSchoolAdmin && degreeNumbers.isNotEmpty) {
              content.add(_sectionHeader('Organize by degree'));
              content.add(
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All degrees'),
                        selected: !_showMultipleDegreeOrganizer &&
                            _selectedDegreeNumber == null,
                        onSelected: (_) => setState(() {
                          _showMultipleDegreeOrganizer = false;
                          _selectedMultiDegreeStudent = null;
                          _selectedDegreeNumber = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      for (final degreeNumber in degreeNumbers) ...[
                        ChoiceChip(
                          label: Text('${_ordinal(degreeNumber)} degree'),
                          selected: !_showMultipleDegreeOrganizer &&
                              _selectedDegreeNumber == degreeNumber,
                          onSelected: (_) => setState(() {
                            _showMultipleDegreeOrganizer = false;
                            _selectedMultiDegreeStudent = null;
                            _selectedDegreeNumber = degreeNumber;
                          }),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              );
            }
            if (!_showMultipleDegreeOrganizer && visibleRecords.isNotEmpty) {
              if (ApiService.authRole == 'student') {
                final studentDegrees =
                    visibleRecords.map(_degreeNumber).toSet().toList()..sort();
                for (final degreeNumber in studentDegrees) {
                  content.add(
                      _sectionHeader('Your ${_ordinal(degreeNumber)} Degree'));
                  content.addAll(visibleRecords
                      .where((record) => _degreeNumber(record) == degreeNumber)
                      .map((record) => _recordCard(context, record)));
                }
              } else {
                final years = visibleRecords
                    .map((record) =>
                        _publishedAt(record)?.year.toString() ??
                        'Year unavailable')
                    .toSet()
                    .toList()
                  ..sort((a, b) {
                    final yearA = int.tryParse(a) ?? -1;
                    final yearB = int.tryParse(b) ?? -1;
                    return yearB.compareTo(yearA);
                  });
                for (final year in years) {
                  content.add(_sectionHeader(year));
                  content.addAll(visibleRecords
                      .where((record) =>
                          (_publishedAt(record)?.year.toString() ??
                              'Year unavailable') ==
                          year)
                      .map((record) => _recordCard(context, record)));
                }
              }
            }
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
                child: _showMultipleDegreeOrganizer
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: content,
                      )
                    : visibleRecords.isEmpty
                        ? const Center(
                            child: Text('No matching certificate records.'))
                        : ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: content,
                          ),
              ),
            ]);
          },
        ),
        bottomNavigationBar:
            RoleBottomNavigationBar(isAdmin: ApiService.authRole == 'admin'),
      );

  Widget _recordDetailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
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
  final bool restrictedMode;
  const ChatScreen({
    super.key,
    required this.isAdmin,
    this.initialContactId,
    this.restrictedMode = false,
  });

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
        if (widget.restrictedMode) {
          final stillFrozen = await ApiService.refreshAccessState();
          if (!mounted) return;
          if (stillFrozen == false) {
            context.go('/dashboard');
            return;
          }
        }
        items = await ApiService.getChatMessagesForStudent(
            selectedContact['id'].toString());
        final unsentMessages = _items.where((message) =>
            message['_local_id'] != null &&
            (message['_delivery_status'] == 'sending' ||
                message['_delivery_status'] == 'failed'));
        items = [...items, ...unsentMessages];
      } else {
        items = await ApiService.getChatContacts(search: search);
        final initialContactId = _pendingInitialContactId;
        _pendingInitialContactId = null;
        if (initialContactId != null || widget.restrictedMode) {
          final contactById = initialContactId == null
              ? null
              : items
                  .where((item) => item['id'].toString() == initialContactId)
                  .firstOrNull;
          // The server returns only the authorized freezer contact, so the
          // current result is safe when locally cached contact data is stale.
          final contact =
              contactById ?? (widget.restrictedMode ? items.firstOrNull : null);
          if (contact != null) {
            _selectedContact = contact;
            items = await ApiService.getChatMessagesForStudent(
                contact['id'].toString());
          } else if (widget.restrictedMode) {
            throw Exception(
                'The administrator chat is unavailable. Contact CertiTrust support.');
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
              Text(widget.restrictedMode
                  ? 'Could not open the administrator chat: $_loadError'
                  : 'Could not load this chat.'),
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
    final contact = _selectedContact;
    if (contact == null) return;

    final attachment = _attachment;
    final replyToId = _replyTo?['id']?.toString();
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final pendingMessage = <String, dynamic>{
      '_local_id': localId,
      '_delivery_status': 'sending',
      '_local_attachment_bytes': attachment?.bytes,
      '_local_attachment_name': attachment?.name,
      '_local_reply_to_id': replyToId,
      '_is_own': true,
      'attachment_type': _isVideoAttachment(attachment?.extension)
          ? 'video'
          : attachment == null
              ? null
              : 'image',
      'message': message,
      'sender_email': ApiService.authEmail,
      'sender_name': 'You',
      'reply_to': _replyTo == null
          ? null
          : {
              'sender_name': _replyTo!['sender_name'],
              'message': _replyTo!['message'],
            },
      'is_report': false,
    };
    setState(() {
      _items = [..._items, pendingMessage];
      _controller.clear();
      _attachment = null;
      _replyTo = null;
    });
    _scrollMessagesToLatest();

    try {
      final sentMessage = await ApiService.sendChatMessage(
        message,
        recipientUserId: contact['id']?.toString(),
        fileBytes: attachment?.bytes,
        fileName: attachment?.name,
        replyToId: replyToId,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((item) {
          if (item['_local_id'] != localId) return item;
          return {
            ...sentMessage,
            '_delivery_status':
                sentMessage['delivered_at'] == null ? 'sent' : 'delivered',
          };
        }).toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = _items.map((item) {
          if (item['_local_id'] != localId) return item;
          return {...item, '_delivery_status': 'failed'};
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message failed to send: $error')),
      );
    }
  }

  Widget _buildDeliveryStatus(Map<String, dynamic> message) {
    final status = message['_delivery_status']?.toString() ??
        (message['delivered_at'] != null ? 'delivered' : 'sent');
    final isFailed = status == 'failed';
    final icon = switch (status) {
      'sending' => Icons.schedule,
      'delivered' => Icons.done_all,
      'failed' => Icons.error_outline,
      _ => Icons.check,
    };
    final label = switch (status) {
      'sending' => 'Sending',
      'delivered' => 'Delivered',
      'failed' => 'Failed',
      _ => 'Sent',
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          if (isFailed)
            TextButton(
              onPressed: () => _retryMessage(message),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  bool _isVideoAttachment(String? extension) =>
      const {'mp4', 'mov', 'webm'}.contains(extension?.toLowerCase());

  Future<void> _retryMessage(Map<String, dynamic> message) async {
    final localId = message['_local_id']?.toString();
    if (localId == null) return;
    setState(() {
      _items = _items
          .map((item) => item['_local_id'] == localId
              ? {...item, '_delivery_status': 'sending'}
              : item)
          .toList();
    });
    try {
      final bytes = message['_local_attachment_bytes'] as List<int>?;
      final sentMessage = await ApiService.sendChatMessage(
        message['message']?.toString() ?? '',
        recipientUserId: _selectedContact?['id']?.toString(),
        fileBytes: bytes,
        fileName: message['_local_attachment_name']?.toString(),
        replyToId: message['_local_reply_to_id']?.toString(),
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((item) {
          if (item['_local_id'] != localId) return item;
          return {
            ...sentMessage,
            '_delivery_status':
                sentMessage['delivered_at'] == null ? 'sent' : 'delivered',
          };
        }).toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((item) => item['_local_id'] == localId
                ? {...item, '_delivery_status': 'failed'}
                : item)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message failed to send: $error')),
      );
    }
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
      await ApiService.sendChatMessage(
        'Report about ${subadmin['name']} (${subadmin['email']}): $reason',
        recipientUserId: superAdmin['id'].toString(),
        isReport: true,
      );
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
              if (widget.isAdmin && profile['student_id'] != null) ...[
                Text('Student ID: ${profile['student_id']}'),
                const SizedBox(height: 8),
              ],
              Text('Email: ${profile['email']?.toString() ?? 'Not available'}'),
              const SizedBox(height: 8),
              Text('Role: ${profile['role_label']?.toString() ?? 'Contact'}'),
              const SizedBox(height: 8),
              Text(
                  'Status: ${profile['is_active'] == true ? 'Online' : 'Offline'}'),
              const SizedBox(height: 8),
              Text(profile['last_seen_label']?.toString() ??
                  'Last active: unknown'),
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
              final localAttachmentBytes =
                  message['_local_attachment_bytes'] as Uint8List?;
              final senderEmail =
                  message['sender_email']?.toString().trim().toLowerCase();
              final currentEmail = ApiService.authEmail?.trim().toLowerCase();
              final own = message['_is_own'] == true ||
                  (currentEmail != null && senderEmail == currentEmail);
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
                                    if (!widget.restrictedMode)
                                      PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.more_vert,
                                            size: 18),
                                        onSelected: (value) async {
                                          if (value == 'delete_me') {
                                            await _deleteMessage(message);
                                          } else if (value ==
                                              'delete_everyone') {
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
                                              child:
                                                  Text('Delete for everyone'),
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
                                if (localAttachmentBytes != null &&
                                    message['attachment_type'] == 'image')
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 260,
                                      height: 320,
                                      child: Image.memory(
                                        localAttachmentBytes,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  )
                                else if (attachmentUrl != null &&
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
                                if (own) _buildDeliveryStatus(message),
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

  Widget _restrictedChatUnavailable() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The administrator chat is unavailable. Contact CertiTrust support to restore access.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _loadItems(showLoading: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Future<void> _logoutRestrictedAccount() async {
    await ApiService.logout();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !widget.restrictedMode && _selectedContact == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!widget.restrictedMode && !didPop && _selectedContact != null) {
            _closeConversation();
          }
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
            leading: !widget.restrictedMode && _selectedContact != null
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _closeConversation)
                : null,
            actions: _selectedContact != null && !widget.restrictedMode
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
                : widget.restrictedMode
                    ? [
                        IconButton(
                          tooltip: 'Log out',
                          icon: const Icon(Icons.logout),
                          onPressed: _logoutRestrictedAccount,
                        ),
                      ]
                    : null,
          ),
          body: Column(children: [
            Expanded(
                child: _selectedContact == null
                    ? widget.restrictedMode
                        ? _isLoading && !_hasLoaded
                            ? const Center(child: CircularProgressIndicator())
                            : _loadError == null
                                ? _restrictedChatUnavailable()
                                : _loadErrorView()
                        : _contactsBody()
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
          bottomNavigationBar: widget.restrictedMode
              ? null
              : RoleBottomNavigationBar(isAdmin: widget.isAdmin),
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
