import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/script_runtime.dart';
import 'package:nexterm/screens/renderers/script_execution_controller.dart';
import 'package:nexterm/utils/script_protocol.dart';

ScriptPromptEvent _prompt(String variable) => ScriptPromptEvent(
  kind: ScriptPromptKind.input,
  variable: variable,
  prompt: 'Value for $variable',
);

void main() {
  group('ScriptExecutionController', () {
    test('starts in connecting and becomes running once connected', () {
      final controller = ScriptExecutionController(scriptName: 'Deploy');
      addTearDown(controller.dispose);

      expect(controller.phase, ScriptExecutionPhase.connecting);
      expect(
        controller.toRuntimeState().status,
        ScriptSessionStatus.connecting,
      );

      controller.markConnected();
      expect(controller.phase, ScriptExecutionPhase.running);
      expect(controller.toRuntimeState().status, ScriptSessionStatus.running);
    });

    test('uses the script name from script_start', () {
      final controller = ScriptExecutionController(scriptName: 'Script');
      addTearDown(controller.dispose);

      controller.handleEvent(const ScriptStartEvent(name: 'Nightly update'));

      expect(controller.scriptName, 'Nightly update');
      expect(controller.phase, ScriptExecutionPhase.running);
    });

    test('tracks steps as 1-based and fills skipped placeholders', () {
      final controller = ScriptExecutionController(scriptName: 'Steps');
      addTearDown(controller.dispose);

      controller.handleEvent(
        const ScriptStepEvent(number: 3, description: 'Third step'),
      );

      expect(controller.stepCount, 3);
      expect(controller.currentStepNumber, 3);
      expect(controller.steps[0], 'Step 1');
      expect(controller.steps[1], 'Step 2');
      expect(controller.steps[2], 'Third step');
      expect(controller.currentStepText, 'Third step');

      controller.handleEvent(
        const ScriptStepEvent(number: 2, description: '  Second step  '),
      );
      expect(controller.steps[1], 'Second step');
      expect(controller.currentStepText, 'Second step');
    });

    test('ignores invalid step numbers and empty descriptions get labels', () {
      final controller = ScriptExecutionController(scriptName: 'Steps');
      addTearDown(controller.dispose);

      controller.handleEvent(
        const ScriptStepEvent(number: 0, description: 'invalid'),
      );
      expect(controller.stepCount, 0);

      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: '   '),
      );
      expect(controller.steps.single, 'Step 1');
    });

    test('progress is clamped and cleared when the next step starts', () {
      final controller = ScriptExecutionController(scriptName: 'Progress');
      addTearDown(controller.dispose);

      controller.handleEvent(
        const ScriptProgressEvent(percentage: 130, message: 'Almost'),
      );
      expect(controller.progressPercent, 100);
      expect(controller.progressMessage, 'Almost');

      controller.handleEvent(
        const ScriptProgressEvent(percentage: -10, message: 'Waiting'),
      );
      expect(controller.progressPercent, 0);

      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'Copy files'),
      );
      expect(controller.progressPercent, isNull);
      expect(controller.progressMessage, isEmpty);
    });

    test('queues prompts and only leaves waiting when all are answered', () {
      final controller = ScriptExecutionController(scriptName: 'Prompts');
      addTearDown(controller.dispose);
      controller.markConnected();

      controller.handleEvent(_prompt('FIRST'));
      controller.handleEvent(_prompt('SECOND'));

      expect(controller.isWaitingForInput, isTrue);
      expect(controller.phase, ScriptExecutionPhase.waitingForInput);
      expect(controller.pendingSheets, hasLength(2));
      expect(controller.toRuntimeState().needsInput, isTrue);

      final first = controller.pendingSheets.first;
      controller.removeSheet(first);
      expect(controller.pendingSheets.single.prompt?.variable, 'SECOND');
      expect(controller.phase, ScriptExecutionPhase.waitingForInput);

      controller.removeSheet(controller.pendingSheets.single);
      expect(controller.isWaitingForInput, isFalse);
      expect(controller.phase, ScriptExecutionPhase.running);
      expect(controller.toRuntimeState().needsInput, isFalse);
    });

    test('queues summary, table and message box dialogs', () {
      final controller = ScriptExecutionController(scriptName: 'Dialogs');
      addTearDown(controller.dispose);

      controller.handleEvent(
        const ScriptSummaryEvent(title: 'Summary', data: ['a', 'b']),
      );
      controller.handleEvent(
        const ScriptTableEvent(title: 'Table', data: ['h']),
      );
      controller.handleEvent(
        const ScriptMessageBoxEvent(title: 'Message', message: 'Hello'),
      );

      expect(controller.pendingSheets, hasLength(3));
      expect(controller.pendingSheets[0].isSummary, isTrue);
      expect(controller.pendingSheets[1].isTable, isTrue);
      expect(controller.pendingSheets[2].isMessageBox, isTrue);
      expect(controller.phase, ScriptExecutionPhase.waitingForInput);
    });

    test('successful end keeps informational sheets for the user', () {
      final controller = ScriptExecutionController(scriptName: 'Done');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'Work'),
      );
      controller.handleEvent(_prompt('UNUSED'));
      controller.handleEvent(
        const ScriptSummaryEvent(title: 'Summary', data: ['a', 'b']),
      );

      controller.handleEvent(const ScriptEndEvent(exitCode: 0, success: true));

      expect(controller.phase, ScriptExecutionPhase.completed);
      expect(controller.pendingSheets, hasLength(1));
      expect(controller.pendingSheets.single.isSummary, isTrue);
      expect(controller.toRuntimeState().needsInput, isFalse);
    });

    test('successful end completes and clears queued prompts', () {
      final controller = ScriptExecutionController(scriptName: 'Done');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'Work'),
      );
      controller.handleEvent(_prompt('UNUSED'));

      controller.handleEvent(const ScriptEndEvent(exitCode: 0, success: true));

      expect(controller.phase, ScriptExecutionPhase.completed);
      expect(controller.isTerminal, isTrue);
      expect(controller.pendingSheets, isEmpty);
      expect(controller.exitCode, 0);
      expect(controller.displayProgress, 100);
      expect(controller.errorMessage, isNull);
      expect(controller.failedStepIndex, isNull);
    });

    test('failed end marks the current step and reports the exit code', () {
      final controller = ScriptExecutionController(scriptName: 'Fail');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'One'),
      );
      controller.handleEvent(
        const ScriptStepEvent(number: 2, description: 'Two'),
      );
      controller.handleEvent(
        const ScriptProgressEvent(percentage: 40, message: 'Halfway'),
      );

      controller.handleEvent(
        const ScriptEndEvent(exitCode: 17, success: false),
      );

      expect(controller.phase, ScriptExecutionPhase.failed);
      expect(controller.failedStepIndex, 1);
      expect(controller.errorMessage, 'Script exited with code 17');
      expect(controller.progressPercent, 40);
      expect(controller.displayProgress, 40);
    });

    test('a script error marks failure even without an end event', () {
      final controller = ScriptExecutionController(scriptName: 'Error');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 2, description: 'Two'),
      );

      controller.handleEvent(const ScriptErrorEvent());

      expect(controller.phase, ScriptExecutionPhase.failed);
      expect(controller.failedStepIndex, 1);
      expect(controller.errorMessage, 'The script reported an error');
    });

    test('cancelling produces a stopped state instead of a failure', () {
      final controller = ScriptExecutionController(scriptName: 'Stop');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'One'),
      );
      controller.handleEvent(_prompt('WAITING'));

      controller.markCancelling();
      expect(controller.phase, ScriptExecutionPhase.cancelling);
      expect(controller.pendingSheets, isEmpty);

      controller.handleEvent(
        const ScriptEndEvent(exitCode: 130, success: false),
      );

      expect(controller.phase, ScriptExecutionPhase.cancelled);
      expect(controller.isCancelled, isTrue);
      expect(controller.errorMessage, isNull);
      expect(controller.failedStepIndex, isNull);
      expect(controller.toRuntimeState().status, ScriptSessionStatus.cancelled);
    });

    test('a late error does not turn a cancelled script into a failure', () {
      final controller = ScriptExecutionController(scriptName: 'Stop');
      addTearDown(controller.dispose);
      controller.markCancelling();
      controller.handleEvent(const ScriptErrorEvent());

      expect(controller.phase, ScriptExecutionPhase.cancelled);
    });

    test('terminal events are ignored after completion', () {
      final controller = ScriptExecutionController(scriptName: 'Done');
      addTearDown(controller.dispose);
      controller.handleEvent(const ScriptEndEvent(exitCode: 0, success: true));

      controller.handleEvent(const ScriptErrorEvent());
      controller.handleEvent(const ScriptEndEvent(exitCode: 1, success: false));

      expect(controller.phase, ScriptExecutionPhase.completed);
      expect(controller.errorMessage, isNull);
    });

    test('disconnect clears dialogs and preserves a useful message', () {
      final controller = ScriptExecutionController(scriptName: 'Lost');
      addTearDown(controller.dispose);
      controller.handleEvent(_prompt('WAITING'));

      controller.markDisconnected(message: ' Network dropped ');

      expect(controller.phase, ScriptExecutionPhase.disconnected);
      expect(controller.pendingSheets, isEmpty);
      expect(controller.errorMessage, 'Network dropped');
      expect(controller.isTerminal, isTrue);

      controller.markDisconnected(message: 'ignored?');
      expect(controller.errorMessage, 'Network dropped');
    });

    test('notices are bounded and keep the newest messages', () {
      final controller = ScriptExecutionController(scriptName: 'Notices');
      addTearDown(controller.dispose);

      for (var i = 0; i < ScriptExecutionController.maxNotices + 3; i++) {
        controller.handleEvent(
          ScriptNoticeEvent(kind: ScriptNoticeKind.info, message: 'notice $i'),
        );
      }

      expect(
        controller.notices,
        hasLength(ScriptExecutionController.maxNotices),
      );
      expect(controller.notices.first.message, 'notice 3');
      expect(
        controller.notices.last.message,
        'notice ${ScriptExecutionController.maxNotices + 2}',
      );
    });

    test('blank notices are ignored', () {
      final controller = ScriptExecutionController(scriptName: 'Notice');
      addTearDown(controller.dispose);

      controller.handleEvent(
        const ScriptNoticeEvent(kind: ScriptNoticeKind.warning, message: '   '),
      );

      expect(controller.notices, isEmpty);
    });

    test('runtime state mirrors step and progress information', () {
      final controller = ScriptExecutionController(scriptName: 'Runtime');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 2, description: 'Second'),
      );
      controller.handleEvent(
        const ScriptProgressEvent(percentage: 25, message: 'Working'),
      );
      controller.handleEvent(_prompt('WAITING'));

      final runtime = controller.toRuntimeState();

      expect(runtime.scriptName, 'Runtime');
      expect(runtime.status, ScriptSessionStatus.waitingForInput);
      expect(runtime.needsInput, isTrue);
      expect(runtime.currentStep, 'Second');
      expect(runtime.currentStepNumber, 2);
      expect(runtime.stepCount, 2);
      expect(runtime.progressPercent, 25);
      expect(runtime.progressMessage, 'Working');
    });

    test('cancel intent survives a reconnect and a replayed end', () {
      final controller = ScriptExecutionController(scriptName: 'Stop');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'One'),
      );
      controller.markCancelling();

      controller.resetForReconnect();

      expect(controller.cancelRequested, isTrue);
      expect(controller.phase, ScriptExecutionPhase.cancelling);
      expect(controller.canStop, isFalse);

      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'One'),
      );
      expect(controller.phase, ScriptExecutionPhase.cancelling);

      controller.handleEvent(
        const ScriptEndEvent(exitCode: 130, success: false),
      );
      expect(controller.phase, ScriptExecutionPhase.cancelled);
    });

    test('prompts replayed after cancel are ignored', () {
      final controller = ScriptExecutionController(scriptName: 'Stop');
      addTearDown(controller.dispose);
      controller.markCancelling();

      controller.handleEvent(_prompt('STALE'));

      expect(controller.pendingSheets, isEmpty);
      expect(controller.phase, ScriptExecutionPhase.cancelling);
    });

    test('resetForReconnect clears every piece of replayed state', () {
      final controller = ScriptExecutionController(scriptName: 'Reconnect');
      addTearDown(controller.dispose);
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'One'),
      );
      controller.handleEvent(
        const ScriptNoticeEvent(
          kind: ScriptNoticeKind.warning,
          message: 'Careful',
        ),
      );
      controller.handleEvent(
        const ScriptProgressEvent(percentage: 50, message: 'Half'),
      );
      controller.handleEvent(_prompt('WAITING'));
      controller.handleEvent(const ScriptEndEvent(exitCode: 1, success: false));

      controller.resetForReconnect();

      expect(controller.phase, ScriptExecutionPhase.connecting);
      expect(controller.steps, isEmpty);
      expect(controller.currentStepNumber, 0);
      expect(controller.stepCount, 0);
      expect(controller.failedStepIndex, isNull);
      expect(controller.progressPercent, isNull);
      expect(controller.progressMessage, isEmpty);
      expect(controller.errorMessage, isNull);
      expect(controller.exitCode, isNull);
      expect(controller.pendingSheets, isEmpty);
      expect(controller.notices, isEmpty);
    });

    test('notifies listeners on state changes', () {
      final controller = ScriptExecutionController(scriptName: 'Notify');
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.markConnected();
      controller.handleEvent(
        const ScriptStepEvent(number: 1, description: 'One'),
      );
      controller.handleEvent(
        const ScriptNoticeEvent(
          kind: ScriptNoticeKind.success,
          message: 'Done',
        ),
      );

      expect(notifications, 3);
    });
  });
}
