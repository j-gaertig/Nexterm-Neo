import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/screens/widgets/script/script_overlay.dart';

StepVisual _visualFor(int index,
    {required int currentStep, required List<String?> steps, required bool isCompleted, int? failedStep}) {
  if (failedStep != null && index == failedStep - 1) return StepVisual.error;
  if (failedStep != null && index > failedStep - 1) return StepVisual.skip;
  if (index < currentStep - 1) return StepVisual.success;
  if (index == currentStep - 1) {
    if (isCompleted && index == steps.length - 1) return StepVisual.success;
    return StepVisual.loading;
  }
  return StepVisual.pending;
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

ScriptOverlay _overlay({
  required int currentStep,
  required List<String?> steps,
  bool isCompleted = false,
  int? failedStep,
  int? currentProgress,
  String name = 'Deploy',
  VoidCallback? onClose,
}) {
  return ScriptOverlay(
    scriptName: name,
    steps: steps,
    failedStep: failedStep,
    isCompleted: isCompleted,
    currentStep: currentStep,
    currentProgress: currentProgress,
    visualForStep: (i) => _visualFor(i, currentStep: currentStep, steps: steps, isCompleted: isCompleted, failedStep: failedStep),
    onCancel: () {},
    onClose: onClose,
  );
}

void main() {
  testWidgets('running overlay shows script name and current step text', (tester) async {
    await tester.pumpWidget(_wrap(_overlay(
      currentStep: 2,
      steps: const ['Initializing...', 'Copying files', 'Restart service'],
    )));

    expect(find.text('Deploy'), findsOneWidget);
    expect(find.text('Copying files'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
    expect(find.text('Completed'), findsNothing);
  });

  testWidgets('failed overlay marks error and hides cancel', (tester) async {
    await tester.pumpWidget(_wrap(_overlay(
      currentStep: 2,
      steps: const ['Initializing...', 'Copying files'],
      isCompleted: true,
      failedStep: 2,
    )));

    expect(find.text('Error'), findsOneWidget);
    expect(find.byTooltip('Cancel script'), findsNothing);
  });

  testWidgets('completed overlay offers close session', (tester) async {
    var closed = false;
    await tester.pumpWidget(_wrap(_overlay(
      currentStep: 3,
      steps: const ['Initializing...', 'Copying files', 'Restart service'],
      isCompleted: true,
      onClose: () => closed = true,
    )));

    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.byTooltip('Close session'));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('expanding reveals the step list with per-step states', (tester) async {
    await tester.pumpWidget(_wrap(_overlay(
      currentStep: 2,
      steps: const ['Initializing...', 'Copying files', 'Restart service'],
    )));

    expect(find.text('Steps'), findsNothing);
    await tester.tap(find.text('Deploy'));
    // Deliberate fixed pumps: the running overlay contains an indeterminate
    // spinner that never settles, so pumpAndSettle would time out.
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Copying files'), findsNWidgets(2)); // main row + step list
  });

  testWidgets('hidden steps beyond 8 are summarized with a +n badge', (tester) async {
    final manySteps = List<String?>.generate(10, (i) => 'Step $i');
    await tester.pumpWidget(_wrap(_overlay(
      currentStep: 2,
      steps: manySteps,
    )));

    expect(find.text('+2'), findsOneWidget);
  });
}
