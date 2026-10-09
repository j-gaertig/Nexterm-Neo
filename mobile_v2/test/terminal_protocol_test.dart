import 'package:flutter_test/flutter_test.dart';

import 'package:nexterm_v2/screens/remote/terminal_protocol.dart';

void main() {
  test('encodeTerminalResize uses the 0x01 prefix and cols,rows shape',
      () {
    expect(encodeTerminalResize(80, 30), '\x0180,30');
    expect(encodeTerminalResize(120, 40), '\x01120,40');
  });

  test('decodeTerminalFrame passes plain output through', () {
    const input = '\x1b[32mroot@host\x1b[0m:~# ';
    final frame = decodeTerminalFrame(input);
    expect(frame.text, input);
    expect(frame.isTotpPrompt, isFalse);
  });

  test('decodeTerminalFrame strips the TOTP marker', () {
    final frame = decodeTerminalFrame('\x02Enter TOTP code: ');
    expect(frame.text, 'Enter TOTP code: ');
    expect(frame.isTotpPrompt, isTrue);
  });

  test('applyControlModifier maps letters to control codes', () {
    expect(applyControlModifier('c'), '\x03');
    expect(applyControlModifier('C'), '\x03');
    expect(applyControlModifier('['), '\x1b');
    expect(applyControlModifier(''), isEmpty);
  });

  test('terminalCloseMessage explains known close codes', () {
    expect(terminalCloseMessage(4007, ''), contains('expired'));
    expect(terminalCloseMessage(4014, ''), contains('not connected'));
    expect(terminalCloseMessage(4003, ''), contains('denied'));
    expect(terminalCloseMessage(1000, ''), 'Connection closed.');
    expect(terminalCloseMessage(null, ''), 'Connection closed.');
    expect(terminalCloseMessage(4999, ''), contains('4999'));
  });

  test('terminalCloseMessage prefers the server reason for 4017', () {
    expect(terminalCloseMessage(4017, 'SSH auth failed'),
        'SSH auth failed');
    expect(terminalCloseMessage(4005, 'Custom reason'), 'Custom reason');
  });
}
