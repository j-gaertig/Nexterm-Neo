import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/screens/active_sessions_screen.dart';

void main() {
  test('clamps the session pill using its measured size and safe areas', () {
    const pillSize = Size(220, 64);
    const screen = Size(320, 600);
    const padding = EdgeInsets.only(top: 47, bottom: 34);

    final topLeft = clampSessionPillOffset(
      const Offset(-20, -20),
      pillSize: pillSize,
      screen: screen,
      padding: padding,
    );
    expect(topLeft, const Offset(0, 51));

    final bottomRight = clampSessionPillOffset(
      const Offset(500, 900),
      pillSize: pillSize,
      screen: screen,
      padding: padding,
    );
    expect(bottomRight, const Offset(100, 502));
  });

  test('uses the safe left/right insets and tolerates oversized pills', () {
    const padding = EdgeInsets.fromLTRB(12, 0, 20, 0);

    final result = clampSessionPillOffset(
      const Offset(999, 999),
      pillSize: const Size(260, 30),
      screen: const Size(300, 100),
      padding: padding,
    );
    expect(result.dx, 20);
    expect(result.dy, 70);
  });
}
