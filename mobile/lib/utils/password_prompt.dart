import 'package:xterm/xterm.dart';

// Port of `client/src/common/utils/passwordPrompt.js` (web).
//
// Detects password prompts in terminal output so the app can offer to fill
// the password of one of the server's stored identities. The keyword list,
// the prompt regex and the noise stripping are intentionally identical to the
// web implementation so detection behaves exactly the same on both platforms.

/// Keywords matched by the web client (case-insensitive, unicode aware).
const String passwordKeywords =
    'password|passwd|passwort|kennwort|passphrase|passcode|contraseña|contrasenya|mot de passe|senha|wachtwoord|parola|parool|hasło|heslo|jelszó|lösenord|salasana|пароль|密码|パスワード|암호';

/// Same shape as the web `PASSWORD_PROMPT_REGEX`:
/// optional `user@host:`-style prefix (without shell sigils), a keyword,
/// up to 80 non-colon chars, then a trailing `:` / fullwidth `：` / `?`.
final RegExp passwordPromptRegex = RegExp(
  '^(?:[^\$#%>\\r\\n]{0,120})?(?:$passwordKeywords)(?:[^:\uFF1A?\\r\\n]{0,80})?[:\uFF1A?]\\s*\$',
  caseSensitive: false,
  unicode: true,
);

/// Identity that can fill a password prompt (mirrors the web
/// `{ id, username }` items passed to `PasswordFillHint`).
class PasswordIdentity {
  final dynamic id;
  final String username;

  const PasswordIdentity({required this.id, this.username = ''});
}

/// Identity auth types that carry a password. Mirrors the web filter
/// `['password', 'both', 'password-only']` in `XtermRenderer.jsx`.
const Set<String> passwordIdentityTypes = {
  'password',
  'both',
  'password-only',
};

String _takeLast(String s, int n) {
  final runes = s.runes.toList(growable: false);
  if (runes.length <= n) return s;
  return String.fromCharCodes(runes.sublist(runes.length - n));
}

/// Minimal NFKC folding for the security-relevant fullwidth range.
/// The web version calls `String.normalize('NFKC')`; Dart has no such API,
/// so we fold fullwidth ASCII (U+FF01–U+FF5E) to ASCII and the ideographic
/// space (U+3000) to a regular space. This is an approximation: canonical
/// compositions outside this range (e.g. decomposed combining marks in
/// keywords) do not fold. Terminals emit precomposed UTF-8 in practice, and
/// the prompt regex additionally matches the fullwidth colon/question mark
/// explicitly, so behaviour stays equal for real-world output.
String _foldFullwidth(String s) {
  var needsFold = false;
  for (final rune in s.runes) {
    if ((rune >= 0xFF01 && rune <= 0xFF5E) || rune == 0x3000) {
      needsFold = true;
      break;
    }
  }
  if (!needsFold) return s;
  final out = StringBuffer();
  for (final rune in s.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      out.writeCharCode(0x20);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Removes terminal escape sequences and invisible characters.
/// Same order and same character classes as the web `stripTerminalNoise`.
String stripTerminalNoise(String? value) {
  if (value == null || value.isEmpty) return '';
  var s = _foldFullwidth(value);
  // OSC 8 hyperlinks.
  s = s.replaceAll(RegExp('\u001b\\]8;;.*?\u001b\\\\'), '');
  // Other OSC sequences.
  s = s.replaceAll(RegExp('\u001b\\][^\u0007\u001b]*(?:\u0007|\u001b\\\\)'), '');
  // CSI sequences.
  s = s.replaceAll(RegExp('\u001b\\[[0-?]*[ -/]*[@-~]'), '');
  // Charset selection.
  s = s.replaceAll(RegExp('\u001b[()][0-9A-B]'), '');
  // Single-char escape sequences.
  s = s.replaceAll(RegExp('\u001b[78=><A-Za-z]'), '');
  // C0 controls (keep \t \n \r, drop the rest incl. DEL).
  s = s.replaceAll(RegExp('[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]'), '');
  // Zero-width / bidi / soft hyphen / word joiners.
  s = s.replaceAll(
      RegExp('[\u200b-\u200f\u202a-\u202e\u2060\u2066-\u2069\u061c\ufeff\u00ad]'),
      '');
  // BMP private use area.
  s = s.replaceAll(RegExp('[\ue000-\uf8ff]'), '');
  // Supplementary private use planes (no regex escape, filter runes).
  if (s.runes.any((r) =>
      (r >= 0xF0000 && r <= 0xFFFFD) || (r >= 0x100000 && r <= 0x10FFFD))) {
    final buf = StringBuffer();
    for (final rune in s.runes) {
      if ((rune >= 0xF0000 && rune <= 0xFFFFD) ||
          (rune >= 0x100000 && rune <= 0x10FFFD)) {
        continue;
      }
      buf.writeCharCode(rune);
    }
    s = buf.toString();
  }
  // NBSP -> regular space.
  s = s.replaceAll('\u00a0', ' ');
  return s;
}

/// Accumulates streaming terminal output into the current prompt line.
/// Identical to the web `updatePromptLine`.
String updatePromptLine(String? prev, String chunk) {
  final cleaned = stripTerminalNoise(chunk);
  final combined = (prev ?? '') + cleaned;
  final parts = combined.split(RegExp(r'[\r\n]'));
  return _takeLast(parts.isEmpty ? '' : parts.last, 256);
}

/// Reads the logical (de-wrapped) line at the cursor from the terminal
/// buffer. Mirrors the web `readTerminalPromptLine`: looks back up to 3
/// lines, merges wrapped lines and strips terminal noise.
///
/// Uses the dart `xterm` buffer API (`absoluteCursorY` ~ `baseY + cursorY`,
/// `lines[i].isWrapped` / `getText()` ~ `getLine(y)` /
/// `translateToString(true)`).
String readTerminalPromptLine(Terminal terminal) {
  try {
    final lines = terminal.buffer.lines;
    if (lines.length == 0) return '';
    final cursor = terminal.buffer.absoluteCursorY;
    for (var d = 0; d < 3; d++) {
      var end = cursor - d;
      if (end >= lines.length) end = lines.length - 1;
      if (end < 0) continue;
      var start = end;
      while (start > 0) {
        BufferLine line;
        try {
          line = lines[start];
        } catch (_) {
          break;
        }
        if (!line.isWrapped) break;
        start -= 1;
      }
      final logical = StringBuffer();
      for (var y = start; y <= end; y++) {
        BufferLine line;
        try {
          line = lines[y];
        } catch (_) {
          break;
        }
        logical.write(line.getText());
      }
      if (logical.toString().trim().isEmpty) continue;
      return _takeLast(stripTerminalNoise(logical.toString()), 256);
    }
    return '';
  } catch (_) {
    return '';
  }
}

/// Returns true when [line] looks like a password prompt.
/// Identical to the web `isPasswordPrompt`.
bool isPasswordPrompt(String? line) {
  if (line == null || line.isEmpty) return false;
  final cleaned = stripTerminalNoise(line);
  if (cleaned.trim().isEmpty) return false;
  final rows = cleaned.split(RegExp(r'[\r\n]'));
  var target = '';
  for (var i = rows.length - 1; i >= 0; i--) {
    if (rows[i].trim().isNotEmpty) {
      target = rows[i];
      break;
    }
  }
  if (target.isEmpty) return false;
  target = _takeLast(target, 256);
  return passwordPromptRegex.hasMatch(target);
}
