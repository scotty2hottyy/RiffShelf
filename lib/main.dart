import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final themeProvider = ThemeProvider();
  await themeProvider.init();
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => themeProvider,
      child: const RiffShelfApp(),
    ),
  );
}
