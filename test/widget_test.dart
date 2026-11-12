import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safecampus_app/screens/login_screen.dart';

void main() {
  testWidgets('app loads the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('SafeCampus Login'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Sign in as'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('registration action follows the selected login role', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text("Don't have an account?"), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);

    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
    expect(find.text('New staff member?'), findsOneWidget);
    expect(find.text('Register Staff'), findsOneWidget);

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(find.text('System manager?'), findsOneWidget);
    expect(find.text('Request Access'), findsOneWidget);

    await tester.ensureVisible(find.text('Request Access'));
    await tester.tap(find.text('Request Access'));
    await tester.pumpAndSettle();
    expect(find.text('Request System Manager Access'), findsOneWidget);
    expect(find.text('9-digit staff number'), findsNothing);
    expect(find.text('REQUEST ADMIN ACCESS'), findsOneWidget);
  });
}
