import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/navigation_bar_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('floating navigation is the default and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await NavigationBarSettings.load();
    expect(settings.useFloating, isTrue);

    await settings.setUseFloating(false);
    expect(settings.useFloating, isFalse);
    expect((await NavigationBarSettings.load()).useFloating, isFalse);

    await settings.setUseFloating(true);
    expect(settings.useFloating, isTrue);
    expect((await NavigationBarSettings.load()).useFloating, isTrue);
  });

  test('unknown stored values fall back to the floating bar', () async {
    SharedPreferences.setMockInitialValues({'navigation_bar_style': 'unknown'});

    final settings = await NavigationBarSettings.load();

    expect(settings.style, NavigationBarStyle.floating);
  });
}
