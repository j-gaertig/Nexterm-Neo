import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/screen_lock_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('screen lock defaults to disabled and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ScreenLockSettings.load();
    expect(settings.enabled, isFalse);

    await settings.setEnabled(true);
    expect(settings.enabled, isTrue);
    expect((await ScreenLockSettings.load()).enabled, isTrue);

    await settings.setEnabled(false);
    expect(settings.enabled, isFalse);
    expect((await ScreenLockSettings.load()).enabled, isFalse);
  });
}
