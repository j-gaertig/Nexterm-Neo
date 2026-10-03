import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/password_prompt.dart';
import 'package:nexterm/utils/password_prompt_localizations.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isPasswordPrompt (parity with web passwordPrompt.js)', () {
    test('detects english prompts', () {
      expect(isPasswordPrompt('Password:'), isTrue);
      expect(isPasswordPrompt('password:'), isTrue);
      expect(isPasswordPrompt('Enter password:'), isTrue);
      expect(isPasswordPrompt('[sudo] password for deploy:'), isTrue);
      expect(isPasswordPrompt('Passphrase:'), isTrue);
    });

    test('detects prompts in other languages', () {
      expect(isPasswordPrompt('Passwort:'), isTrue);
      expect(isPasswordPrompt('Kennwort:'), isTrue);
      expect(isPasswordPrompt('Mot de passe :'), isTrue);
      expect(isPasswordPrompt('Contraseña:'), isTrue);
      expect(isPasswordPrompt('Пароль:'), isTrue);
      expect(isPasswordPrompt('密码:'), isTrue);
      expect(isPasswordPrompt('密码：'), isTrue);
      expect(isPasswordPrompt('パスワード:'), isTrue);
      expect(isPasswordPrompt('암호:'), isTrue);
    });

    test('rejects non-prompts', () {
      expect(isPasswordPrompt(null), isFalse);
      expect(isPasswordPrompt(''), isFalse);
      expect(isPasswordPrompt('   '), isFalse);
      expect(isPasswordPrompt('Password'), isFalse);
      expect(isPasswordPrompt('Enter username:'), isFalse);
      expect(isPasswordPrompt('Last login: yesterday'), isFalse);
      expect(isPasswordPrompt('My password is secret'), isFalse);
      // Shell sigils in the prefix must not match (typed commands).
      expect(isPasswordPrompt(r'$ password:'), isFalse);
      expect(isPasswordPrompt('# password:'), isFalse);
    });

    test('uses the last non-empty line', () {
      expect(isPasswordPrompt('Welcome back\nPassword:'), isTrue);
      expect(isPasswordPrompt('Password:\n'), isTrue);
      expect(isPasswordPrompt('Password:\n   \n'), isTrue);
    });

    test('ignores ansi noise like the web stripTerminalNoise', () {
      expect(isPasswordPrompt('\x1b[32mPassword:\x1b[0m'), isTrue);
      expect(
          isPasswordPrompt('\x1b]8;;https://example.com\x1b\\Password:\x07'),
          isTrue);
    });
  });

  group('updatePromptLine', () {
    test('accumulates chunks split across writes', () {
      var line = updatePromptLine('', 'Pass');
      line = updatePromptLine(line, 'word:');
      expect(line, 'Password:');
      expect(isPasswordPrompt(line), isTrue);
    });

    test('resets on newlines and keeps the last line', () {
      final line = updatePromptLine('Password:', '\r\n\$ ');
      expect(isPasswordPrompt(line), isFalse);
    });
  });

  group('stripTerminalNoise', () {
    test('removes csi, osc and c0 controls, keeps text', () {
      expect(stripTerminalNoise('\x1b[1;32mhi\x1b[0m'), 'hi');
      expect(stripTerminalNoise('a\u00a0b'), 'a b');
    });
  });

  group('readTerminalPromptLine', () {
    test('reads back without throwing', () {
      final terminal = Terminal(maxLines: 100);
      terminal.write('Password:');
      final line = readTerminalPromptLine(terminal);
      expect(line, isA<String>());
      // The streaming path (updatePromptLine) is authoritative on mobile;
      // the buffer read is best-effort, so only assert consistency when it
      // returns content.
      if (line.trim().isNotEmpty) {
        expect(isPasswordPrompt(line), isTrue);
      }
    });
  });

  group('passwordPromptStringsForTag', () {
    test('resolves locales like the web client', () {
      expect(passwordPromptStringsForTag('en').settingTitle,
          'Password input detection');
      expect(passwordPromptStringsForTag('de_DE').settingTitle,
          'Erkennung der Passworteingabe');
      expect(passwordPromptStringsForTag('de').paste, 'Passwort einfügen');
      expect(passwordPromptStringsForTag('pt-BR').settingTitle,
          'Detecção de digitação de senha');
      expect(passwordPromptStringsForTag('zh-CN').paste, '粘贴密码');
      expect(passwordPromptStringsForTag('zh-Hant-TW').paste, '貼上密碼');
      expect(passwordPromptStringsForTag('xx').settingTitle,
          'Password input detection');
      expect(passwordPromptStringsForTag(null).settingTitle,
          'Password input detection');
    });

    test('pasteFor interpolates the username', () {
      const strings = _enProbe;
      expect(strings.pasteFor('deploy'), contains('deploy'));
      expect(strings.pasteFor(''), strings.paste);
      expect(strings.pasteFor(null), strings.paste);
    });
  });
}

const _enProbe = PasswordPromptStrings(
  settingTitle: 'Password input detection',
  enabled: 'Enabled',
  disabled: 'Disabled',
  paste: 'paste password',
  pasteForTemplate: 'paste {{username}} password',
  cycle: 'Use the arrow keys to switch identity',
  pasteIdentityPassword: 'Paste Password',
);
