import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knee_master_test_app/src/ui/login_screen.dart';

void main() {
  testWidgets('login screen renders fields and sign in action', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onLogin: (_, __) async {},
          onSignUp: ({
            required email,
            required password,
            required displayName,
            required role,
          }) async {},
        ),
      ),
    );

    expect(find.text('Knee Rehab Monitor'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
