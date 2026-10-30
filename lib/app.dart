import 'package:flutter/material.dart';

import 'navigation/main_navigation.dart';

class RiffShelfApp extends StatelessWidget {
  const RiffShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF071013);
    const surface = Color(0xFF0D191D);
    const accent = Color(0xFF54E8D5);

    return MaterialApp(
      title: 'RiffShelf',
      restorationScopeId: 'riffshelf',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: accent,
              brightness: Brightness.dark,
            ).copyWith(
              primary: accent,
              secondary: const Color(0xFF8BF3E3),
              surface: surface,
            ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
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
      ),
      home: const MainNavigation(),
    );
  }
}
