import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/terminal_settings.dart';

void main() {
  group('TerminalThemes', () {
    test('includes GitHub Dark Default and Night Owl', () {
      final ids = TerminalThemes.all.map((theme) => theme.id).toList();

      expect(ids, containsAll(['githubDarkDefault', 'nightOwl']));
      expect(ids.toSet(), hasLength(ids.length));

      final githubDarkDefault = TerminalThemes.getById('githubDarkDefault');
      expect(githubDarkDefault.name, 'GitHub Dark Default');
      expect(githubDarkDefault.background, const Color(0xFF0D1117));
      expect(githubDarkDefault.foreground, const Color(0xFFE6EDF3));

      final nightOwl = TerminalThemes.getById('nightOwl');
      expect(nightOwl.name, 'Night Owl');
      expect(nightOwl.background, const Color(0xFF011627));
      expect(nightOwl.foreground, const Color(0xFFD6DEEB));
    });
  });
}
