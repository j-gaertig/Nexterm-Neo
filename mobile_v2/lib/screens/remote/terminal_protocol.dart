/// Wire protocol helpers for the terminal WebSocket (`/ws/term`).
///
/// Layout mirrors the server implementation:
/// - `server/utils/sshEventHandlers.js` (`parseResizeMessage`)
/// - `server/hooks/ssh.js` (resize prefix, plain-text data frames)
/// - `server/middlewares/wsAuth.js` + `server/routes/term.js` (close codes)
///
/// All helpers are pure so they can be unit tested.
library;

/// Prefix of a resize frame: `\x01` followed by `cols,rows`
/// (for example `\x0180,30`).
const String terminalResizePrefix = '\x01';

/// Prefix of a TOTP second-factor prompt frame. The marker itself is never
/// rendered; the remainder is written to the terminal as plain output.
const String totpPromptMarker = '\x02';

/// Encode a terminal resize frame for the `/ws/term` socket.
String encodeTerminalResize(int cols, int rows) =>
    '$terminalResizePrefix$cols,$rows';

/// A decoded incoming terminal frame.
class TerminalFrame {
  const TerminalFrame({required this.text, required this.isTotpPrompt});

  /// Text to write to the terminal (marker already stripped).
  final String text;

  /// True when the frame carried the TOTP prompt marker.
  final bool isTotpPrompt;
}

/// Decode one incoming text frame of the `/ws/term` socket.
TerminalFrame decodeTerminalFrame(String data) {
  if (data.startsWith(totpPromptMarker)) {
    return TerminalFrame(
        text: data.substring(1), isTotpPrompt: true);
  }
  return TerminalFrame(text: data, isTotpPrompt: false);
}

/// Map a single typed character to its control code (`Ctrl` + key).
///
/// Returns null when the character has no control-code equivalent.
int? controlCodeFor(int code) {
  if ((code >= 0x40 && code <= 0x5f) ||
      (code >= 0x61 && code <= 0x7a)) {
    return code & 0x1f;
  }
  switch (code) {
    case 0x20:
    case 0x32:
      return 0x00;
    case 0x33:
      return 0x1b;
    case 0x34:
      return 0x1c;
    case 0x35:
      return 0x1d;
    case 0x36:
      return 0x1e;
    case 0x37:
      return 0x1f;
    case 0x38:
    case 0x3f:
      return 0x7f;
    default:
      return null;
  }
}

/// Apply the Ctrl modifier to typed text: the first character becomes its
/// control code, the rest passes through unchanged.
String applyControlModifier(String text) {
  if (text.isEmpty) return text;
  final runes = text.runes.toList(growable: false);
  final mapped = controlCodeFor(runes.first);
  if (mapped == null) return text;
  return String.fromCharCode(mapped) +
      String.fromCharCodes(runes.skip(1));
}

/// Human-readable message for a `/ws/term` close code.
///
/// Server close codes come from `server/middlewares/wsAuth.js` and
/// `server/routes/term.js`. Code 4017 carries the server-side failure
/// reason, so the raw reason is preferred there when present.
String terminalCloseMessage(int? code, String? reason) {
  final trimmed = (reason ?? '').trim();
  switch (code) {
    case null:
      return trimmed.isNotEmpty ? trimmed : 'Connection closed.';
    case 1000:
      return trimmed.isNotEmpty ? trimmed : 'Connection closed.';
    case 4001:
      return 'Authentication required. Please sign in again.';
    case 4003:
      return 'Access denied for this session.';
    case 4004:
      return 'Login session is no longer valid.';
    case 4005:
      return trimmed.isNotEmpty ? trimmed : 'Server not found.';
    case 4006:
      return 'Identity is not available for this server.';
    case 4007:
      return 'Remote session expired. Please reconnect.';
    case 4008:
      return 'A connection reason is required for this server.';
    case 4009:
      return trimmed.isNotEmpty
          ? trimmed
          : 'This connection type is not supported.';
    case 4013:
      return 'Shared session link is invalid.';
    case 4014:
      return 'Remote session is not connected yet. Try again.';
    case 4015:
      return 'Sharing is not supported for this connection.';
    case 4017:
      return trimmed.isNotEmpty ? trimmed : 'Connection failed.';
    default:
      return trimmed.isNotEmpty
          ? trimmed
          : 'Connection lost (code $code).';
  }
}
