import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/script_protocol.dart';

void main() {
  (List<String>, List<ScriptEvent>, ScriptStreamParser) makeParser() {
    final terminal = <String>[];
    final events = <ScriptEvent>[];
    final parser = ScriptStreamParser(
      onTerminalData: terminal.add,
      onEvent: events.add,
    );
    return (terminal, events, parser);
  }

  group('ScriptStreamParser', () {
    test('passes pure terminal chunks through unchanged', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('hello world\r\n');

      expect(terminal, ['hello world\r\n']);
      expect(events, isEmpty);
      expect(parser.pendingBuffer, isEmpty);
    });

    test('parses a single control frame', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic{"type":"script_start","name":"deploy.sh"}');

      expect(terminal, isEmpty);
      expect(events, hasLength(1));
      final start = events.single as ScriptStartEvent;
      expect(start.name, 'deploy.sh');
    });

    test('handles terminal data before a control segment in one frame', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk(
          'before$scriptMagic{"type":"progress","percentage":42,"message":"copying"}');

      expect(terminal, ['before']);
      expect(events, hasLength(1));
      final progress = events.single as ScriptProgressEvent;
      expect(progress.percentage, 42);
      expect(progress.message, 'copying');
    });

    test('handles multiple control segments in one frame', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic{"type":"step","number":1,"description":"c,d"}'
          '$scriptMagic{"type":"info","message":"thinking"}');

      expect(terminal, isEmpty);
      expect(events, hasLength(2));
      expect((events[0] as ScriptStepEvent).description, 'c,d');
      expect((events[1] as ScriptNoticeEvent).message, 'thinking');
    });

    test('reassembles control JSON split across two chunks', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic{"type":"step","number":1,"descrip');
      expect(terminal, isEmpty);
      expect(events, isEmpty);
      expect(parser.pendingBuffer, isNotEmpty);

      parser.processChunk('tion":"installing packages"}');
      expect(terminal, isEmpty);
      expect(events, hasLength(1));
      expect((events.single as ScriptStepEvent).description, 'installing packages');
      expect(parser.pendingBuffer, isEmpty);
    });

    test('drops delimited non-JSON segments, keeps following events', () {
      // Frame: `magic` + garbage + `magic` + valid event — the web client
      // fails JSON.parse on the garbage and drops it silently.
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic"garbage"$scriptMagic{"type":"success","message":"done"}');

      expect(terminal, isEmpty);
      expect(events, hasLength(1));
      expect(events.single, isA<ScriptNoticeEvent>());
      expect(parser.pendingBuffer, isEmpty);
    });

    test('drops unknown control types silently', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic{"type":"totally_new","payload":1}');

      expect(terminal, isEmpty);
      expect(events, isEmpty);
      expect(parser.pendingBuffer, isEmpty);
    });

    test('held-back candidate does not leak into the next event', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic{"type":"prompt","inputType":"pas');
      parser.processChunk('sword","variable":"PW","prompt":"pw?"}');
      parser.processChunk('$scriptMagic{"type":"progress","percentage":10,"message":""}');

      expect(events, hasLength(2));
      expect((events[0] as ScriptPromptEvent).variable, 'PW');
      expect((events[1] as ScriptProgressEvent).percentage, 10);
      expect(terminal, isEmpty);
    });

    test('discards unparseable held-back candidates on discardPending', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic>>> raw stuff');
      expect(parser.pendingBuffer, '>>> raw stuff');

      parser.discardPending();
      expect(parser.pendingBuffer, isEmpty);
      expect(terminal, isEmpty);
      expect(events, isEmpty);
    });

    test('discards oversized held-back candidates (64 KB cap)', () {
      final (terminal, events, parser) = makeParser();

      parser.processChunk('$scriptMagic${'x' * (64 * 1024 + 1)}');

      expect(parser.pendingBuffer, isEmpty);
      expect(terminal, isEmpty);
      expect(events, isEmpty);
    });
  });

  group('ScriptEvent.parse (parity with web handleControlMessage)', () {
    test('parses prompt kinds', () {
      final input = ScriptEvent.parse(
              '{"type":"prompt","inputType":"input","variable":"VAR1","prompt":"who?","default":"root"}')
          as ScriptPromptEvent;
      expect(input.kind, ScriptPromptKind.input);
      expect(input.variable, 'VAR1');
      expect(input.defaultValue, 'root');

      final password = ScriptEvent.parse(
              '{"type":"prompt","inputType":"password","variable":"SUDO_PASSWORD","prompt":"[sudo] password for x"}')
          as ScriptPromptEvent;
      expect(password.kind, ScriptPromptKind.password);

      final select = ScriptEvent.parse(
              '{"type":"prompt","inputType":"select","variable":"OPT","prompt":"pick","options":["a","b"]}')
          as ScriptPromptEvent;
      expect(select.kind, ScriptPromptKind.select);
      expect(select.options, ['a', 'b']);
    });

    test('parses confirm dialogs', () {
      final confirm = ScriptEvent.parse(
              '{"type":"confirm","variable":"NEXTERM_CONFIRM_RESULT","prompt":"Continue?"}')
          as ScriptPromptEvent;
      expect(confirm.kind, ScriptPromptKind.confirm);
      expect(confirm.variable, 'NEXTERM_CONFIRM_RESULT');
      expect(confirm.prompt, 'Continue?');
    });

    test('parses summary and table payloads', () {
      final summary = ScriptEvent.parse(
              '{"type":"summary","title":"Report","data":["ip","1.2.3.4","user","root"]}')
          as ScriptSummaryEvent;
      expect(summary.title, 'Report');
      expect(summary.data, ['ip', '1.2.3.4', 'user', 'root']);

      final table = ScriptEvent.parse(
              '{"type":"table","title":"Disks","data":["name,size","sda,20G"]}')
          as ScriptTableEvent;
      expect(table.title, 'Disks');
      expect(table.data, ['name,size', 'sda,20G']);
    });

    test('parses script_end with exit code semantics', () {
      final success = ScriptEvent.parse('{"type":"script_end","exitCode":0,"success":true}')
          as ScriptEndEvent;
      expect(success.exitCode, 0);
      expect(success.success, isTrue);

      final failure = ScriptEvent.parse('{"type":"script_end","exitCode":2,"success":false}')
          as ScriptEndEvent;
      expect(failure.exitCode, 2);
      expect(failure.success, isFalse);

      // Missing `success` flag falls back to the exit code.
      final inferred = ScriptEvent.parse('{"type":"script_end","exitCode":0}') as ScriptEndEvent;
      expect(inferred.success, isTrue);
    });

    test('returns null for invalid JSON', () {
      expect(ScriptEvent.parse('{not json'), isNull);
      expect(ScriptEvent.parse('null'), isNull);
      expect(ScriptEvent.parse('[]'), isNull);
      expect(ScriptEvent.parse('{"name":"no type"}'), isNull);
    });
  });
}
