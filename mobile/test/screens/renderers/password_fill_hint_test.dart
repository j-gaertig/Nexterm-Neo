import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/screens/renderers/password_fill_hint.dart';
import 'package:nexterm/utils/password_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHint(
    WidgetTester tester, {
    required List<PasswordIdentity> items,
    required int selectedIndex,
    ValueChanged<dynamic>? onFill,
    VoidCallback? onCycle,
    VoidCallback? onDismiss,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordFillHint(
            items: items,
            selectedIndex: selectedIndex,
            onFill: onFill ?? (_) {},
            onCycle: onCycle ?? () {},
            onDismiss: onDismiss ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows the selected identity and fills on tap', (tester) async {
    dynamic filledId;
    await pumpHint(
      tester,
      items: const [
        PasswordIdentity(id: 1, username: 'deploy'),
        PasswordIdentity(id: 2, username: 'root'),
      ],
      selectedIndex: 0,
      onFill: (id) => filledId = id,
    );

    expect(find.text('paste deploy password', findRichText: true),
        findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(filledId, 1);
  });

  testWidgets('falls back to the generic label without username',
      (tester) async {
    await pumpHint(
      tester,
      items: const [PasswordIdentity(id: 7)],
      selectedIndex: 0,
    );

    expect(find.text('paste password', findRichText: true), findsOneWidget);
    // Single identity: no cycle control.
    expect(find.text('1/1'), findsNothing);
  });

  testWidgets('cycle and dismiss callbacks fire', (tester) async {
    var cycled = 0;
    var dismissed = false;
    await pumpHint(
      tester,
      items: const [
        PasswordIdentity(id: 1, username: 'a'),
        PasswordIdentity(id: 2, username: 'b'),
      ],
      selectedIndex: 1,
      onCycle: () => cycled++,
      onDismiss: () => dismissed = true,
    );

    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(cycled, 1);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('renders nothing without identities', (tester) async {
    await pumpHint(tester, items: const [], selectedIndex: -1);
    expect(find.byType(FilledButton), findsNothing);
  });
}
