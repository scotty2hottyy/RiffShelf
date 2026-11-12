import 'package:material_ui/material_ui.dart';

import '../screens/discover_screen.dart';
import '../screens/library_screen.dart';
import '../screens/practice_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tuner_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with RestorationMixin {
  final RestorableInt _selectedIndex = RestorableInt(0);

  static const _destinations = <_NavigationDestination>[
    _NavigationDestination(
      label: 'Discover',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      screen: DiscoverScreen(),
    ),
    _NavigationDestination(
      label: 'Practice',
      icon: Icons.music_note_outlined,
      selectedIcon: Icons.music_note,
      screen: PracticeScreen(),
    ),
    _NavigationDestination(
      label: 'Tuner',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      screen: TunerScreen(),
    ),
    _NavigationDestination(
      label: 'Library',
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music,
      screen: LibraryScreen(),
    ),
    _NavigationDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      screen: SettingsScreen(),
    ),
  ];

  @override
  String? get restorationId => 'main_navigation';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_selectedIndex, 'selected_tab');
    if (_selectedIndex.value < 0 ||
        _selectedIndex.value >= _destinations.length) {
      _selectedIndex.value = 0;
    }
  }

  @override
  void dispose() {
    _selectedIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 20, title: const _BrandHeader()),
      body: IndexedStack(
        index: _selectedIndex.value,
        children: [for (final destination in _destinations) destination.screen],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex.value,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex.value = index);
        },
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: theme.colorScheme.primary,
            size: 23,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Riff'),
                    TextSpan(
                      text: 'Shelf',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'TABS  ·  PRACTICE  ·  PLAY MORE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.5,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavigationDestination {
  const _NavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}
