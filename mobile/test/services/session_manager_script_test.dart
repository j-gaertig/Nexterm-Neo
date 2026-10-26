import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/script_runtime.dart';
import 'package:nexterm/models/server.dart';
import 'package:nexterm/services/session_manager.dart';

Server _server() =>
    const Server(id: 1, name: 'web-01', ip: '10.0.0.1', identities: [1]);

AppSession _scriptSession({
  String id = 'session-1',
  String name = 'Deploy',
  ScriptRuntimeState? runtime,
}) => AppSession(
  sessionId: id,
  server: _server(),
  type: ConnectionType.terminal,
  scriptId: 42,
  scriptName: name,
  scriptRuntime: runtime ?? ScriptRuntimeState.initial(name),
);

ScriptRuntimeState _runtime(
  ScriptSessionStatus status, {
  String name = 'Deploy',
  int currentStep = 0,
  int stepCount = 0,
}) => ScriptRuntimeState(
  scriptName: name,
  status: status,
  currentStepNumber: currentStep,
  stepCount: stepCount,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSession script state', () {
    test('isScriptSession is based on scriptId', () {
      expect(_scriptSession().isScriptSession, isTrue);
      expect(
        AppSession(
          sessionId: 'terminal',
          server: _server(),
          type: ConnectionType.terminal,
        ).isScriptSession,
        isFalse,
      );
    });

    test('isScriptRunning only covers live states', () {
      for (final status in [
        ScriptSessionStatus.connecting,
        ScriptSessionStatus.running,
        ScriptSessionStatus.waitingForInput,
        ScriptSessionStatus.cancelling,
      ]) {
        expect(
          _scriptSession(runtime: _runtime(status)).isScriptRunning,
          isTrue,
          reason: '$status should be running',
        );
      }

      for (final status in [
        ScriptSessionStatus.cancelled,
        ScriptSessionStatus.completed,
        ScriptSessionStatus.failed,
        ScriptSessionStatus.disconnected,
      ]) {
        expect(
          _scriptSession(runtime: _runtime(status)).isScriptRunning,
          isFalse,
          reason: '$status should be terminal',
        );
      }
    });

    test('needsInput mirrors the mirrored runtime status', () {
      expect(_scriptSession().scriptNeedsInput, isFalse);
      expect(
        _scriptSession(
          runtime: _runtime(ScriptSessionStatus.waitingForInput),
        ).scriptNeedsInput,
        isTrue,
      );
    });
  });

  group('SessionManager script runtime mirror', () {
    test('tracks waiting scripts for the banner and badge', () {
      final manager = SessionManager();
      addTearDown(manager.dispose);
      manager.seedSessionForTesting(
        _scriptSession(
          id: 'waiting',
          name: 'Needs input',
          runtime: _runtime(ScriptSessionStatus.waitingForInput),
        ),
      );
      manager.seedSessionForTesting(
        _scriptSession(
          id: 'running',
          name: 'Busy',
          runtime: _runtime(ScriptSessionStatus.running),
        ),
        makeActive: false,
      );

      expect(manager.waitingInputCount, 1);
      expect(manager.attentionSessions.single.sessionId, 'waiting');

      manager.updateScriptRuntime(
        'waiting',
        _runtime(ScriptSessionStatus.running, currentStep: 2, stepCount: 3),
      );

      expect(manager.waitingInputCount, 0);
      expect(manager.attentionSessions, isEmpty);
    });

    test('updates the script name from controller state', () {
      final manager = SessionManager();
      addTearDown(manager.dispose);
      final session = _scriptSession();
      manager.seedSessionForTesting(session);

      manager.updateScriptRuntime(
        session.sessionId,
        _runtime(
          ScriptSessionStatus.running,
          name: 'Nightly deploy',
          currentStep: 1,
          stepCount: 2,
        ),
      );

      expect(session.scriptName, 'Nightly deploy');
      expect(session.scriptRuntime?.stepCount, 2);
    });

    test('value-equal runtime updates do not notify listeners', () {
      final manager = SessionManager();
      addTearDown(manager.dispose);
      final session = _scriptSession();
      manager.seedSessionForTesting(session);
      var notifications = 0;
      manager.addListener(() => notifications++);

      manager.updateScriptRuntime(
        session.sessionId,
        ScriptRuntimeState.initial('Deploy'),
      );
      expect(notifications, 0);

      manager.updateScriptRuntime(
        session.sessionId,
        _runtime(ScriptSessionStatus.running),
      );
      expect(notifications, 1);
    });

    test('unknown session ids are ignored safely', () {
      final manager = SessionManager();
      addTearDown(manager.dispose);

      manager.updateScriptRuntime(
        'missing',
        _runtime(ScriptSessionStatus.running),
      );

      expect(manager.waitingInputCount, 0);
    });
  });
}
