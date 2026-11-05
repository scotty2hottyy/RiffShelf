import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';
  bool _isLightMode = false;
  late SharedPreferences _prefs;

  bool get isLightMode => _isLightMode;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isLightMode = _prefs.getBool(_themeKey) ?? false;
    notifyListeners();
  }

  Future<void> setLightMode(bool lightMode) async {
    _isLightMode = lightMode;
    await _prefs.setBool(_themeKey, lightMode);
    notifyListeners();
  }

  ThemeData getTheme(bool isLight) {
    const accentColor = Color(0xFF54E8D5);
    const backgroundColor = Color(0xFF071013);
    const surfaceColor = Color(0xFF0D191D);

    if (isLight) {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.light,
        ).copyWith(
          primary: accentColor,
          secondary: const Color(0xFF8BF3E3),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAFAFA),
          foregroundColor: Color(0xFF1A1A1A),
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 76,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFFF5F5F5),
          indicatorColor: Color(0xFFE0F2F1),
          height: 76,
        ),
        useMaterial3: true,
      );
    } else {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accentColor,
          secondary: const Color(0xFF8BF3E3),
          surface: surfaceColor,
        ),
        scaffoldBackgroundColor: backgroundColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: backgroundColor,
          foregroundColor: Color(0xFFF3F8F7),
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 76,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF0A1518),
          indicatorColor: Color(0xFF173A3A),
          height: 76,
        ),
        useMaterial3: true,
      );
    }
  }
}
