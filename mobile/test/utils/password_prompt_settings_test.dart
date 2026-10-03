import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/terminal_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('passwordPromptDetection defaults to true and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await TerminalSettings.load();
    // Same default as web `terminal.passwordPromptDetection`.
    expect(settings.passwordPromptDetection, isTrue);

    await settings.setPasswordPromptDetection(false);
    expect(settings.passwordPromptDetection, isFalse);

    final reloaded = await TerminalSettings.load();
    expect(reloaded.passwordPromptDetection, isFalse);

    settings.dispose();
    reloaded.dispose();
  });
}
