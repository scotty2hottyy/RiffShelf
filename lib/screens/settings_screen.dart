import 'package:flutter/cupertino.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/theme_provider.dart';
import '../features/artwork/artwork_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    ArtworkPreferences.getShowAllAlbumTypes();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              'Settings',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _SettingsTile(
            title: 'Light Mode',
            subtitle: 'Switch between light and dark themes',
            trailing: Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return Semantics(
                  label: 'Light mode',
                  child: Switch(
                    value: themeProvider.isLightMode,
                    onChanged: (value) {
                      themeProvider.setLightMode(value);
                    },
                    activeThumbColor: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Album Artwork',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _SettingsTile(
            title: 'Show all album types',
            subtitle: 'Include live albums, compilations, singles, and other releases',
            trailing: ValueListenableBuilder<bool>(
              valueListenable: ArtworkPreferences.showAllAlbumTypesNotifier,
              builder: (context, showAll, child) {
                return Semantics(
                  label: 'Show all album types',
                  child: SizedBox(
                    width: 51,
                    height: 31,
                    child: CupertinoSwitch(
                      value: showAll,
                      onChanged: (value) {
                        ArtworkPreferences.setShowAllAlbumTypes(value);
                      },
                      activeTrackColor: theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }
}
