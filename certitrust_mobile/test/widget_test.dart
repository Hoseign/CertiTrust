// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';

import 'package:certitrust_mobile/main.dart';
import 'package:certitrust_mobile/features/admin/admin_management_screen.dart';
import 'package:certitrust_mobile/features/admin/student_access_screen.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/student_dashboard_view.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/admin_dashboard_view.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/all_certificates_modal.dart';
import 'package:certitrust_mobile/features/navigation/role_pages.dart';
import 'package:certitrust_mobile/services/api_service.dart';

void main() {
  testWidgets('CertiTrust app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const CertiTrustApp());
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(CertiTrustApp), findsOneWidget);
  });

  testWidgets('admin dashboard refreshes credentials and verification activity',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var credentialRequests = 0;
    var verificationRequests = 0;
    Future<List<Map<String, dynamic>>>? openedCredentials;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminDashboardView(
              fetchCertificates: () async {
                credentialRequests++;
                return [
                  {
                    'student_name': credentialRequests == 1
                        ? 'New Credential'
                        : 'Uploaded Later',
                    'student_id': 'UCU-2026-1',
                    'degree': 'BSIT',
                  }
                ];
              },
              fetchRecentVerifications: () async {
                verificationRequests++;
                return [
                  {
                    'student_name': 'Recently Verified',
                    'degree': 'BSIT',
                    'university_name': 'Urdaneta City University',
                    'status': 'Verified',
                  }
                ];
              },
              onViewRecentCredentials: (credentials) {
                openedCredentials = credentials;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent Verified'), findsOneWidget);
    expect(find.text('Recent Credentials'), findsOneWidget);
    expect(find.text('Recently Verified'), findsOneWidget);
    expect(find.text('Latest: New Credential • BSIT'), findsOneWidget);
    expect(credentialRequests, 1);
    expect(verificationRequests, 1);

    await tester.tap(find.text('Recent Credentials'));
    expect(await openedCredentials, hasLength(1));
    expect(credentialRequests, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(credentialRequests, 2);
    expect(verificationRequests, 2);
    expect(find.text('Latest: Uploaded Later • BSIT'), findsOneWidget);

    await tester.tap(find.text('Recent Credentials'));
    expect((await openedCredentials)?.first['student_name'], 'Uploaded Later');
    expect(credentialRequests, 2);
  });

  testWidgets('recent credential expands with actions and QR remains beside name',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final credential = {
      'id': 10,
      'student_name': 'UcuUser T. Student',
      'student_id': '20260001',
      'student_email': 'student@example.edu',
      'degree': 'BSIT',
      'degree_number': 1,
      'certificate_code': 'CERT-RECENT-10',
      'cert_hash': 'recent-credential-hash',
      'issue_date': '2026-06-01',
      'status': 'Verified',
      'university_code': 'UCU',
      'diploma_url': 'https://example.edu/diploma.jpg',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AllCertificatesModal(
                  initialCertificates: Future.value([credential]),
                  fetchCertificates: () async => [credential],
                ),
              ),
              child: const Text('Open recent credentials'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open recent credentials'));
    await tester.pumpAndSettle();

    expect(find.text('Recent Issued Credentials'), findsOneWidget);
    expect(find.text('UcuUser T. Student'), findsOneWidget);
    expect(find.byTooltip('Get QR Code'), findsOneWidget);
    await tester.tap(find.text('UcuUser T. Student'));
    await tester.pumpAndSettle();

    for (final action in [
      'Verify this record',
      'View This Diploma',
      'Add another degree',
      'Request deletion',
    ]) {
      expect(find.text(action), findsOneWidget);
    }
    expect(find.byTooltip('Get QR Code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple-degree selection offers one shared verification QR',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StudentDashboardView(
            isLoadingCertificate: false,
            studentCertificates: [
              {
                'degree_number': 1,
                'student_name': 'Alex Student',
                'student_id': 'UCU-1001',
                'degree': 'BSIT',
                'status': 'Verified',
                'cert_hash': 'first-degree-hash',
              },
              {
                'degree_number': 2,
                'student_name': 'Alex Student',
                'student_id': 'UCU-1001',
                'degree': 'BSA',
                'status': 'Verified',
                'cert_hash': 'second-degree-hash',
              },
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Your Multiple Degrees'));
    await tester.pumpAndSettle();

    expect(find.text('Get QR for all degrees'), findsOneWidget);
    expect(find.text('Verify all degrees'), findsOneWidget);
    expect(find.text('Get QR Code'), findsNothing);
    expect(find.text('Your 1st Degree'), findsWidgets);
    expect(find.text('Your 2nd Degree'), findsWidgets);

    await tester.tap(find.text('Get QR for all degrees'));
    await tester.pumpAndSettle();
    expect(find.text('All 2 Degrees'), findsOneWidget);
  });

  testWidgets('student record details expand without framework assertion',
      (WidgetTester tester) async {
    ApiService.authRole = 'student';
    final response = jsonEncode({
      'data': [
        {
          'id': 1,
          'student_name': 'Alex Student',
          'student_id': 'UCU-1001',
          'student_email': 'alex@example.edu',
          'degree': 'BSIT',
          'degree_number': 1,
          'certificate_code': 'CERT-RECORD-1',
          'cert_hash': 'record-hash',
          'issue_date': '2024-06-01',
          'status': 'Verified',
        },
      ],
    });

    await http.runWithClient(
      () async {
        final router = GoRouter(
          initialLocation: '/records',
          routes: [
            GoRoute(
              path: '/records',
              builder: (context, state) => const RecordsScreen(),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();

        expect(find.text('Student name'), findsOneWidget);
        expect(find.text('UCU-1001'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient(
        (_) async => http.Response(response, 200),
      ),
    );
  });

  testWidgets('empty conversation prompts to start chatting until first send',
      (WidgetTester tester) async {
    ApiService.authRole = 'admin';
    ApiService.authEmail = 'admin@example.edu';
    final router = GoRouter(
      initialLocation: '/ansq',
      routes: [
        GoRoute(
          path: '/ansq',
          builder: (context, state) => const ChatScreen(
            isAdmin: true,
            initialContactId: '7',
          ),
        ),
      ],
    );

    await http.runWithClient(
      () async {
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(find.text('No messages yet'), findsOneWidget);
        expect(
            find.text('Start chatting by sending a message.'), findsOneWidget);

        await tester.enterText(find.byType(TextField).last, 'Hello, student!');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();

        expect(find.text('No messages yet'), findsNothing);
        expect(find.text('Start chatting by sending a message.'), findsNothing);
        expect(find.text('Hello, student!'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/chat/contacts')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 7, 'name': 'UCU Student', 'role_label': 'Student'},
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/chat/messages')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/chat/messages')) {
          return http.Response(
            jsonEncode({
              'data': {
                'id': 88,
                'message': 'Hello, student!',
                'sender_email': 'admin@example.edu',
                'sender_name': 'Admin',
                'delivered_at': null,
              },
            }),
            201,
          );
        }
        return http.Response(
          jsonEncode({'message': 'Unexpected request'}),
          404,
        );
      }),
    );

    router.dispose();
    ApiService.authRole = null;
    ApiService.authEmail = null;
  });

  testWidgets('chat polling does not start overlapping contact requests',
      (WidgetTester tester) async {
    ApiService.authRole = 'admin';
    ApiService.authEmail = 'admin@example.edu';
    ApiService.authToken = 'test-token';
    final pendingContacts = Completer<http.Response>();
    var contactsRequests = 0;
    final router = GoRouter(
      initialLocation: '/ansq',
      routes: [
        GoRoute(
          path: '/ansq',
          builder: (context, state) => const ChatScreen(isAdmin: true),
        ),
      ],
    );

    await http.runWithClient(
      () async {
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));

        expect(contactsRequests, 1);
        pendingContacts.complete(http.Response(
          jsonEncode({
            'data': [
              {'id': 7, 'name': 'UCU Student', 'role_label': 'Student'},
            ],
          }),
          200,
        ));
        await tester.pumpAndSettle();

        expect(find.text('UCU Student'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/chat/contacts')) {
          contactsRequests++;
          return pendingContacts.future;
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/chat/messages')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response(
          jsonEncode({'message': 'Unexpected request'}),
          404,
        );
      }),
    );

    router.dispose();
    ApiService.authRole = null;
    ApiService.authEmail = null;
    ApiService.authToken = null;
  });

  testWidgets(
      'student access refresh updates state without Future callback error',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiService.authRole = 'admin';
    ApiService.authUniversity = 'UCU';
    ApiService.authToken = 'test-token';
    var studentFrozen = false;

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: StudentAccessScreen()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        final studentMenu = find.byType(PopupMenuButton<String>);
        await tester.ensureVisible(studentMenu);
        await tester.tap(studentMenu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Freeze'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Freeze account'));
        await tester.pumpAndSettle();

        expect(find.text('Ucu Student’s account is frozen.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/admin/students')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 22,
                  'name': 'Ucu Student',
                  'email': 'ucu-student@example.edu',
                  'is_frozen': studentFrozen,
                  'can_manage_access': true,
                },
              ],
              'university_students_frozen': false,
              'can_manage_university_freeze': true,
            }),
            200,
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path.endsWith('/admin/students/22/access')) {
          studentFrozen = jsonDecode(request.body)['frozen'] as bool? ?? false;
          return http.Response(
            jsonEncode({'message': 'Student account frozen.'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({'message': 'Unexpected request'}),
          404,
        );
      }),
    );

    ApiService.authToken = null;
    ApiService.authRole = null;
    ApiService.authUniversity = null;
  });

  testWidgets(
      'superadmin gets a student name and ID warning when an owner freeze remains',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiService.authRole = 'admin';
    ApiService.authEmail = 'certitrust256@gmail.com';
    ApiService.authToken = 'test-token';

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: AdminManagementScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Frozen students: 1'), findsOneWidget);
        await tester.tap(find.text('View frozen students (1)'));
        await tester.pumpAndSettle();
        expect(find.text('UCU Student'), findsOneWidget);
        expect(find.text('Student ID: UCU-12345'), findsOneWidget);
        final actionMenu = find.byType(PopupMenuButton<String>).last;
        await tester.ensureVisible(actionMenu);
        await tester.tap(actionMenu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore access for UCU'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Students only'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore selected'));
        await tester.pumpAndSettle();

        expect(find.text('You cannot unfreeze this student'), findsOneWidget);
        expect(
          find.text('- UCU Student (Student ID: UCU-12345)'),
          findsOneWidget,
        );
        expect(find.text('OK'), findsOneWidget);
      },
      () => MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/admin/subadmins')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 1,
                  'name': 'UCU Admin',
                  'email': 'ucu-admin@example.edu',
                  'university_code': 'UCU',
                  'access_frozen': false,
                  'frozen_students': [
                    {'name': 'UCU Student', 'student_id': 'UCU-12345'},
                  ],
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path.endsWith('/admin/universities/UCU/access')) {
          return http.Response(
            jsonEncode({
              'message':
                  'Only the administrator who froze student access for this university can restore it.',
              'scope': 'students',
              'frozen': false,
              'protected_students': [
                {'name': 'UCU Student', 'student_id': 'UCU-12345'},
              ],
            }),
            403,
          );
        }
        return http.Response(
          jsonEncode({'message': 'Unexpected request'}),
          404,
        );
      }),
    );

    ApiService.authRole = null;
    ApiService.authEmail = null;
    ApiService.authToken = null;
  });

  testWidgets(
      'subadmin records list only groups students with multiple degrees',
      (WidgetTester tester) async {
    ApiService.authRole = 'admin';
    ApiService.authEmail = 'ucu-admin@example.edu';
    final certificates = [
      {
        'id': 1,
        'student_name': 'Ucu Student',
        'student_id': 'UCU-1001',
        'student_email': 'student@example.edu',
        'degree': 'BSIT',
        'degree_number': 1,
        'cert_hash': 'degree-one-hash',
        'certificate_code': 'CERT-DEGREE-ONE',
        'status': 'Verified',
        'issue_date': '2024-06-01',
      },
      {
        'id': 2,
        'student_name': 'Ucu Student',
        'student_id': 'UCU-1001',
        'student_email': 'student@example.edu',
        'degree': 'BSA',
        'degree_number': 2,
        'cert_hash': 'degree-two-hash',
        'certificate_code': 'CERT-DEGREE-TWO',
        'status': 'Verified',
        'issue_date': '2026-06-01',
      },
      {
        'id': 3,
        'student_name': 'Single Degree Student',
        'student_id': 'UCU-1002',
        'student_email': 'single@example.edu',
        'degree': 'BSBA',
        'degree_number': 1,
        'cert_hash': 'single-degree-hash',
        'certificate_code': 'CERT-SINGLE',
        'status': 'Verified',
        'issue_date': '2025-06-01',
      },
    ];

    await http.runWithClient(
      () async {
        final router = GoRouter(
          initialLocation: '/records',
          routes: [
            GoRoute(
              path: '/records',
              builder: (context, state) => const RecordsScreen(),
            ),
            GoRoute(
              path: '/verify',
              builder: (context, state) => const Scaffold(body: Text('Verify')),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Students with multiple degrees (1)'));
        await tester.pumpAndSettle();

        expect(find.text('Ucu Student (2 credentials)'), findsOneWidget);
        expect(
            find.text('Single Degree Student (1 credentials)'), findsNothing);

        await tester.tap(find.text('Ucu Student (2 credentials)'));
        await tester.pumpAndSettle();
        expect(find.text('Show combined QR'), findsOneWidget);
        await tester.tap(find.text('Show combined QR'));
        await tester.pumpAndSettle();
        expect(find.text('All 2 Degrees'), findsOneWidget);
      },
      () => MockClient(
        (_) async => http.Response(jsonEncode({'data': certificates}), 200),
      ),
    );
  });

  testWidgets(
      'subadmin records filter by degree type, ordinal, multiple degrees, and issued program',
      (WidgetTester tester) async {
    ApiService.authRole = 'admin';
    ApiService.authEmail = 'subadmin@example.edu';
    final certificates = [
      {
        'id': 1,
        'student_name': 'Graduate Student',
        'student_id': 'PSU-1001',
        'student_email': 'graduate@example.edu',
        'degree': 'BSIT',
        'degree_number': 1,
        'cert_hash': 'graduate-bachelor-hash',
        'certificate_code': 'CERT-GRADUATE-1',
        'status': 'Verified',
        'issue_date': '2024-06-01',
      },
      {
        'id': 2,
        'student_name': 'Graduate Student',
        'student_id': 'PSU-1001',
        'student_email': 'graduate@example.edu',
        'degree': 'MSIT',
        'degree_number': 2,
        'cert_hash': 'graduate-master-hash',
        'certificate_code': 'CERT-GRADUATE-2',
        'status': 'Verified',
        'issue_date': '2026-06-01',
      },
      {
        'id': 3,
        'student_name': 'Graduate Student',
        'student_id': 'PSU-1001',
        'student_email': 'graduate@example.edu',
        'degree': 'PhD',
        'degree_number': 3,
        'cert_hash': 'graduate-doctoral-hash',
        'certificate_code': 'CERT-GRADUATE-3',
        'status': 'Verified',
        'issue_date': '2026-06-01',
      },
    ];

    await http.runWithClient(
      () async {
        final router = GoRouter(
          initialLocation: '/records',
          routes: [
            GoRoute(
              path: '/records',
              builder: (context, state) => const RecordsScreen(),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(find.text('Filter certificate records'), findsOneWidget);
        expect(find.text('Organize by degree'), findsNothing);
        expect(find.text('Masteral'), findsOneWidget);
        expect(find.text('Doctoral'), findsOneWidget);

        await tester.tap(find.text('Masteral'));
        await tester.pumpAndSettle();
        expect(find.text('No matching certificate records.'), findsNothing);

        await tester.ensureVisible(find.text('Doctoral'));
        await tester.tap(find.text('Doctoral'));
        await tester.pumpAndSettle();
        expect(find.text('No matching certificate records.'), findsNothing);

        await tester.ensureVisible(find.text('Multiple degrees (1 students)'));
        await tester.tap(find.text('Multiple degrees (1 students)'));
        await tester.pumpAndSettle();
        expect(find.text('No matching certificate records.'), findsNothing);

        await tester.ensureVisible(find.text('BSIT'));
        await tester.tap(find.text('BSIT'));
        await tester.pumpAndSettle();
        expect(find.text('No matching certificate records.'), findsNothing);

        router.dispose();
      },
      () => MockClient(
        (_) async => http.Response(jsonEncode({'data': certificates}), 200),
      ),
    );

    ApiService.authRole = null;
    ApiService.authEmail = null;
  });
}
