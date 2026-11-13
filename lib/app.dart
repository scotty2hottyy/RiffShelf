import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/theme_provider.dart';
import 'navigation/main_navigation.dart';

class RiffShelfApp extends StatelessWidget {
  const RiffShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'RiffShelf',
          debugShowCheckedModeBanner: false,
          restorationScopeId: 'riffshelf',
          theme: themeProvider.getTheme(themeProvider.isLightMode),
          home: const MainNavigation(),
        );
      },
    );
  }
}
