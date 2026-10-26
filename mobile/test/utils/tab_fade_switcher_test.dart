import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/tab_fade_switcher.dart';

void main() {
  testWidgets('applies the tab change when the fade is cancelled', (
    tester,
  ) async {
    final switcher = TabFadeSwitcher(vsync: tester);

    var applied = false;
    switcher.switchTab(apply: () => applied = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(switcher.isSwitching, isTrue);

    // Sessions publish runtime updates while connecting. Those updates used to
    // reset page opacity, cancel the fade future and leave the session hidden.
    (switcher.opacity as AnimationController).value = 1.0;
    await tester.pump();

    expect(applied, isTrue);
    expect(switcher.isSwitching, isFalse);
    switcher.dispose();
  });

  testWidgets('ignores session updates during an in-flight fade', (
    tester,
  ) async {
    final switcher = TabFadeSwitcher(vsync: tester);

    var applied = false;
    switcher.switchTab(apply: () => applied = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    switcher.resetFadeIfIdle();
    await tester.pump();
    expect(switcher.isSwitching, isTrue);
    expect(applied, isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    expect(applied, isTrue);
    switcher.dispose();
  });

  testWidgets('does not switch to a tab that is no longer available', (
    tester,
  ) async {
    final switcher = TabFadeSwitcher(vsync: tester);

    var applied = false;
    switcher.switchTab(canApply: () => false, apply: () => applied = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(applied, isFalse);
    expect(switcher.opacity.value, 1.0);
    expect(switcher.isSwitching, isFalse);
    switcher.dispose();
  });
}
