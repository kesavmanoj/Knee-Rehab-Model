import 'package:flutter_test/flutter_test.dart';

import 'package:knee_master_test_app/app.dart';

void main() {
  testWidgets('app shell renders main navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const KneeMasterTestApp());

    expect(find.text('Knee Rehab Monitor'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Debug'), findsOneWidget);
  });
}
