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
}
