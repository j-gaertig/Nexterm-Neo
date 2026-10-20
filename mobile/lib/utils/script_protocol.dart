import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Wire protocol of the server `ScriptLayer` (`server/lib/ScriptLayer.js`).
///
/// Every control message is a single line prefixed with `SCRIPT_MAGIC`
/// (`\x1F`), followed by a JSON object. The same WebSocket also carries raw
/// terminal output, and one WS frame may mix both — segments are split
/// recursively exactly like the web `ScriptRenderer.processMessage`.
const String scriptMagic = '\u001F';

enum ScriptPromptKind { input, password, select, confirm }

enum ScriptNoticeKind { warning, info, success }

sealed class ScriptEvent {
  const ScriptEvent();

  static ScriptEvent? parse(String raw) {
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      json = decoded;
    } catch (_) {
      return null;
    }
    final type = json['type'];
    if (type is! String) return null;
    switch (type) {
      case 'script_start':
        return ScriptStartEvent(name: (json['name'] ?? '').toString());
      case 'step':
        final number = (json['number'] as num?)?.toInt();
        if (number == null) return null;
        return ScriptStepEvent(number: number, description: (json['description'] ?? '').toString());
      case 'prompt':
        return _parsePrompt(json);
      case 'confirm':
        return ScriptPromptEvent(
          kind: ScriptPromptKind.confirm,
          variable: (json['variable'] ?? 'NEXTERM_CONFIRM_RESULT').toString(),
          prompt: (json['prompt'] ?? json['message'] ?? '').toString(),
        );
      case 'warning':
      case 'info':
      case 'success':
        return ScriptNoticeEvent(
          kind: switch (type) { 'warning' => ScriptNoticeKind.warning, 'info' => ScriptNoticeKind.info, _ => ScriptNoticeKind.success },
          message: (json['message'] ?? '').toString(),
        );
      case 'progress':
        final percentage = (json['percentage'] as num?)?.toInt();
        if (percentage == null) return null;
        return ScriptProgressEvent(percentage: percentage, message: (json['message'] ?? '').toString());
      case 'summary':
        return ScriptSummaryEvent(title: (json['title'] ?? '').toString(), data: _stringList(json['data']));
      case 'table':
        return ScriptTableEvent(title: (json['title'] ?? '').toString(), data: _stringList(json['data']));
      case 'msgbox':
        return ScriptMessageBoxEvent(title: (json['title'] ?? '').toString(), message: (json['message'] ?? '').toString());
      case 'script_end':
        final exitCode = (json['exitCode'] as num?)?.toInt() ?? 1;
        return ScriptEndEvent(exitCode: exitCode, success: json['success'] == true || exitCode == 0);
      case 'script_error':
        return const ScriptErrorEvent();
      default:
        // Unknown control types are dropped silently, like the web client's
        // switch default.
        return null;
    }
  }

  static ScriptEvent? _parsePrompt(Map<String, dynamic> json) {
    final inputType = (json['inputType'] as String?) ?? 'input';
    final kind = switch (inputType) {
      'password' => ScriptPromptKind.password,
      'select' => ScriptPromptKind.select,
      'confirm' => ScriptPromptKind.confirm,
      _ => ScriptPromptKind.input,
    };
    return ScriptPromptEvent(
      kind: kind,
      variable: (json['variable'] ?? '').toString(),
      prompt: (json['prompt'] ?? '').toString(),
      defaultValue: (json['default'] ?? '').toString(),
      options: _stringList(json['options']),
    );
  }

  static List<String> _stringList(dynamic data) {
    if (data is List) return data.map((e) => e?.toString() ?? '').toList();
    return const [];
  }
}

class ScriptStartEvent extends ScriptEvent {
  final String name;
  const ScriptStartEvent({required this.name});
}

class ScriptStepEvent extends ScriptEvent {
  /// 1-based step number as broadcast by the server.
  final int number;
  final String description;
  const ScriptStepEvent({required this.number, required this.description});
}

class ScriptPromptEvent extends ScriptEvent {
  final ScriptPromptKind kind;
  final String variable;
  final String prompt;
  final String defaultValue;
  final List<String> options;
  const ScriptPromptEvent({
    required this.kind,
    required this.variable,
    required this.prompt,
    this.defaultValue = '',
    this.options = const [],
  });
}

class ScriptNoticeEvent extends ScriptEvent {
  final ScriptNoticeKind kind;
  final String message;
  const ScriptNoticeEvent({required this.kind, required this.message});
}

class ScriptProgressEvent extends ScriptEvent {
  final int percentage;
  final String message;
  const ScriptProgressEvent({required this.percentage, required this.message});
}

class ScriptSummaryEvent extends ScriptEvent {
  final String title;
  /// Flat list of alternating key/value entries (web `parseDataToKeyValue`).
  final List<String> data;
  const ScriptSummaryEvent({required this.title, required this.data});
}

class ScriptTableEvent extends ScriptEvent {
  final String title;
  /// First entry holds the CSV headers, the rest are CSV row strings
  /// (web `parseDataToTable`).
  final List<String> data;
  const ScriptTableEvent({required this.title, required this.data});
}

class ScriptMessageBoxEvent extends ScriptEvent {
  final String title;
  final String message;
  const ScriptMessageBoxEvent({required this.title, required this.message});
}

class ScriptEndEvent extends ScriptEvent {
  final int exitCode;
  final bool success;
  const ScriptEndEvent({required this.exitCode, required this.success});
}

class ScriptErrorEvent extends ScriptEvent {
  const ScriptErrorEvent();
}

/// Streaming splitter between raw terminal output and `\x1F`-prefixed control
/// messages. Handles:
/// - pure terminal chunks (no magic),
/// - terminal data + control segments mixed within one frame,
/// - multiple control segments per frame,
/// - control JSON split across two frames (held in a bounded pending buffer).
class ScriptStreamParser {
  ScriptStreamParser({required this.onTerminalData, required this.onEvent});

  final void Function(String text) onTerminalData;
  final void Function(ScriptEvent event) onEvent;

  String _pending = '';

  /// Cap for the held-back segment so raw terminal output that happens to
  /// contain `\x1F` cannot buffer indefinitely.
  static const int _maxPendingLength = 64 * 1024;

  void processChunk(String data) {
    final wasHolding = _pending.isNotEmpty;
    final buffer = _pending + data;
    _pending = '';

    // `candidateStart` marks the beginning of an unconsumed JSON candidate
    // whose leading magic byte was already stripped (-1 = scan for magic,
    // -2 = fully consumed). Held-back pending bytes are always candidates.
    var candidateStart = wasHolding ? 0 : -1;

    var index = 0;
    while (index < buffer.length) {
      if (candidateStart >= 0) {
        final end = buffer.indexOf(scriptMagic, candidateStart);
        final segment =
            end < 0 ? buffer.substring(candidateStart) : buffer.substring(candidateStart, end);

        final event = ScriptEvent.parse(segment);
        final consumed = event != null || _isParseableJson(segment);
        if (event != null) onEvent(event);

        if (consumed) {
          if (end < 0) return;
          candidateStart = end + 1;
          index = end + 1;
          continue;
        }

        if (end < 0) {
          // No terminating magic — may be JSON split across frames. Hold it
          // back; unparseable junk (e.g. terminal output that contains
          // `\x1F`) gets bounded and later discarded.
          _pending = segment;
          if (_pending.length > _maxPendingLength) discardPending();
          return;
        }

        // Terminated but not valid JSON — not one of ours; drop it like the
        // web client (JSON.parse error → message silently dropped).
        candidateStart = end + 1;
        index = end + 1;
        continue;
      }

      final magicIndex = buffer.indexOf(scriptMagic, index);
      if (magicIndex < 0) {
        onTerminalData(buffer.substring(index));
        return;
      }
      if (magicIndex > index) {
        onTerminalData(buffer.substring(index, magicIndex));
      }
      candidateStart = magicIndex + 1;
      index = magicIndex + 1;
    }
  }

  /// Discards anything held back (call before tearing down). Keeping the
  /// terminal clean mirrors the web client, which drops unparseable control
  /// messages instead of rendering them.
  void discardPending() {
    _pending = '';
  }

  /// True when the candidate is valid JSON of any kind. The web client
  /// consumes every parseable JSON control message silently — even unknown
  /// types fall through its switch default without being rendered.
  bool _isParseableJson(String segment) {
    try {
      jsonDecode(segment);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True while an (in)complete JSON candidate is held back — used by tests.
  @visibleForTesting
  String get pendingBuffer => _pending;
}
