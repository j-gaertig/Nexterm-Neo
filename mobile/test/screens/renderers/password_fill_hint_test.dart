import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/screens/renderers/password_fill_hint.dart';
import 'package:nexterm/utils/app_icons.dart';
import 'package:nexterm/utils/password_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHint(
    WidgetTester tester, {
    required List<PasswordIdentity> items,
    required int selectedIndex,
    ValueChanged<dynamic>? onFill,
    VoidCallback? onCycle,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PasswordFillHint(
              items: items,
              selectedIndex: selectedIndex,
              onFill: onFill ?? (_) {},
              onCycle: onCycle ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a compact translucent key button and fills on tap', (
    tester,
  ) async {
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

    expect(find.byIcon(AppIcons.key), findsOneWidget);
    // The compact button has no label, counter or close affordance.
    expect(find.textContaining('password'), findsNothing);
    expect(find.text('1/2'), findsNothing);
    expect(find.byType(IconButton), findsNothing);

    final button = find.descendant(
      of: find.byType(PasswordFillHint),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(button), const Size.square(PasswordFillHint.size));

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(PasswordFillHint),
        matching: find.byType(Material),
      ),
    );
    expect(material.color!.a, lessThan(1.0));

    await tester.tap(button);
    await tester.pump();
    expect(filledId, 1);
  });

  testWidgets('announces the selected identity without visible text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHint(
      tester,
      items: const [PasswordIdentity(id: 7)],
      selectedIndex: 0,
    );

    expect(find.bySemanticsLabel('paste password'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('exposes the long-press gesture to accessibility services', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHint(
      tester,
      items: const [
        PasswordIdentity(id: 1, username: 'deploy'),
        PasswordIdentity(id: 2, username: 'root'),
      ],
      selectedIndex: 0,
    );

    final node = tester.getSemantics(find.byType(PasswordFillHint));
    expect(node.label, 'paste deploy password');
    expect(node.hint, 'Long press to switch identity');
    semantics.dispose();
  });

  testWidgets('long-press cycles identities when more than one is attached', (
    tester,
  ) async {
    var cycled = 0;
    await pumpHint(
      tester,
      items: const [
        PasswordIdentity(id: 1, username: 'a'),
        PasswordIdentity(id: 2, username: 'b'),
      ],
      selectedIndex: 1,
      onCycle: () => cycled++,
    );

    await tester.longPress(find.byIcon(AppIcons.key));
    await tester.pump();
    expect(cycled, 1);
  });

  testWidgets('long-press does nothing with a single identity', (tester) async {
    var cycled = 0;
    await pumpHint(
      tester,
      items: const [PasswordIdentity(id: 1, username: 'a')],
      selectedIndex: 0,
      onCycle: () => cycled++,
    );

    await tester.longPress(find.byIcon(AppIcons.key));
    await tester.pump();
    expect(cycled, 0);
  });

  testWidgets('renders nothing without identities', (tester) async {
    await pumpHint(tester, items: const [], selectedIndex: -1);
    expect(find.byIcon(AppIcons.key), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PasswordFillHint),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });
}
