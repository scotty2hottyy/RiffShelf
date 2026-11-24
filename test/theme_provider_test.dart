import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riffshelf/core/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to dark mode', () async {
    final provider = ThemeProvider();
    await provider.init();

    expect(provider.isLightMode, isFalse);
  });

  test('saves the choice so a new provider loads it', () async {
    final provider = ThemeProvider();
    await provider.init();
    await provider.setLightMode(true);

    final reloaded = ThemeProvider();
    await reloaded.init();

    expect(reloaded.isLightMode, isTrue);
  });

  test('can switch theme before init without throwing', () async {
    final provider = ThemeProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setLightMode(true);

    expect(provider.isLightMode, isTrue);
    expect(notifications, 1);
  });

  test('builds light and dark themes with matching brightness', () {
    final provider = ThemeProvider();

    expect(provider.getTheme(true).brightness, Brightness.light);
    expect(provider.getTheme(false).brightness, Brightness.dark);
  });
}
