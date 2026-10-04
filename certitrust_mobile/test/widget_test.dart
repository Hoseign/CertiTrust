// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';

import 'package:certitrust_mobile/main.dart';
import 'package:certitrust_mobile/features/admin/student_access_screen.dart';
import 'package:certitrust_mobile/features/dashboard/widgets/student_dashboard_view.dart';
import 'package:certitrust_mobile/features/navigation/role_pages.dart';
import 'package:certitrust_mobile/services/api_service.dart';

void main() {
  testWidgets('CertiTrust app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const CertiTrustApp());
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(CertiTrustApp), findsOneWidget);
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

  testWidgets('student access refresh updates state without Future callback error',
      (WidgetTester tester) async {
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
          studentFrozen =
              jsonDecode(request.body)['frozen'] as bool? ?? false;
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

  testWidgets('subadmin records list only groups students with multiple degrees',
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
              builder: (context, state) =>
                  const Scaffold(body: Text('Verify')),
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Students with multiple degrees (1)'));
        await tester.pumpAndSettle();

        expect(find.text('Ucu Student (2 degrees)'), findsOneWidget);
        expect(find.text('Single Degree Student (1 degrees)'), findsNothing);

        await tester.tap(find.text('Ucu Student (2 degrees)'));
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
}
