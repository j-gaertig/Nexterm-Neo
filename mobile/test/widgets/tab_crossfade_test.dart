import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/widgets/tab_crossfade.dart';

void main() {
  testWidgets('shows only the active page when idle', (tester) async {
    await _pumpCrossfade(tester, index: 1);

    expect(find.text('Page A'), findsNothing);
    expect(find.text('Page B'), findsOneWidget);
    expect(find.text('Page C'), findsNothing);
  });

  testWidgets('crossfades without a blank frame', (tester) async {
    await _pumpCrossfade(tester, index: 0);

    await _pumpCrossfade(tester, index: 1);
    var fade = _fadeFor(tester, 'Page B');
    expect(fade.opacity.value, 0.0);
    expect(find.text('Page A'), findsOneWidget);
    expect(find.text('Page B'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    fade = _fadeFor(tester, 'Page B');
    expect(fade.opacity.value, greaterThan(0.0));
    expect(fade.opacity.value, lessThan(1.0));
    expect(find.text('Page A'), findsOneWidget);
    expect(find.text('Page B'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    fade = _fadeFor(tester, 'Page B');
    expect(fade.opacity.value, 1.0);
    expect(find.text('Page A'), findsNothing);
    expect(find.text('Page B'), findsOneWidget);
  });

  testWidgets('keeps page state while switching away and back', (tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (context, value, _) => TabCrossfade(
            index: value,
            children: const [
              _CounterPage(),
              Center(child: Text('Page B')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('Count: 1'), findsOneWidget);

    index.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Page B'), findsOneWidget);

    index.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Count: 1'), findsOneWidget);
  });

  testWidgets('keeps page state when a page is inserted before it', (
    tester,
  ) async {
    final inserted = ValueNotifier<bool>(false);
    addTearDown(inserted.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: inserted,
          builder: (context, hasInsertedPage, _) => TabCrossfade(
            index: hasInsertedPage ? 1 : 0,
            children: [
              if (hasInsertedPage) const Center(child: Text('New Page')),
              const _CounterPage(key: ValueKey('counter-page')),
              const Center(child: Text('Page B')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('Count: 1'), findsOneWidget);

    inserted.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('New Page'), findsNothing);
    expect(find.text('Count: 1'), findsOneWidget);
  });

  testWidgets('switching back during a transition does not duplicate pages', (
    tester,
  ) async {
    const pages = [
      _CounterPage(),
      Center(child: Text('Page B')),
      Center(child: Text('Page C')),
    ];
    await _pumpCrossfade(tester, index: 0, children: pages);

    await _pumpCrossfade(tester, index: 1, children: pages);
    await tester.pump(const Duration(milliseconds: 80));
    await _pumpCrossfade(tester, index: 0, children: pages);
    await tester.pump();

    expect(find.byType(_CounterPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('reduced motion switches immediately', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: TabCrossfade(
            index: 0,
            children: [
              Center(child: Text('Page A')),
              Center(child: Text('Page B')),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: TabCrossfade(
            index: 1,
            children: [
              Center(child: Text('Page A')),
              Center(child: Text('Page B')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Page A'), findsNothing);
    expect(find.text('Page B'), findsOneWidget);
  });
}

FadeTransition _fadeFor(WidgetTester tester, String page) {
  return tester.widget<FadeTransition>(
    find
        .ancestor(of: find.text(page), matching: find.byType(FadeTransition))
        .first,
  );
}

Future<void> _pumpCrossfade(
  WidgetTester tester, {
  required int index,
  List<Widget> children = const [
    Center(child: Text('Page A')),
    Center(child: Text('Page B')),
    Center(child: Text('Page C')),
  ],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TabCrossfade(index: index, children: children),
    ),
  );
  await tester.pump();
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({super.key});

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Count: $_count'),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: const Text('Increment'),
          ),
        ],
      ),
    );
  }
}
