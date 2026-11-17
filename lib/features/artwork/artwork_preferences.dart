import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages user preferences for album artwork lookups.
class ArtworkPreferences {
  static const String keyShowAllAlbumTypes = 'artwork_show_all_album_types';
  static final ValueNotifier<bool> showAllAlbumTypesNotifier =
      ValueNotifier<bool>(false);
  static SharedPreferences? _prefs;

  /// Returns whether to show all album types (default false = studio albums only).
  static bool get showAllAlbumTypes => showAllAlbumTypesNotifier.value;

  /// Initializes the preference from storage.
  static Future<void> init([SharedPreferences? preferences]) async {
    try {
      _prefs = preferences ?? await SharedPreferences.getInstance();
      showAllAlbumTypesNotifier.value =
          _prefs?.getBool(keyShowAllAlbumTypes) ?? false;
    } catch (_) {
      // In tests without mock preferences or storage errors, keep default.
    }
  }

  /// Returns whether to show all album types (default false = studio albums only).
  static Future<bool> getShowAllAlbumTypes([
    SharedPreferences? preferences,
  ]) async {
    if (preferences != null) {
      _prefs = preferences;
      final value = preferences.getBool(keyShowAllAlbumTypes) ?? false;
      showAllAlbumTypesNotifier.value = value;
      return value;
    }
    if (_prefs != null) {
      final value = _prefs!.getBool(keyShowAllAlbumTypes) ?? false;
      showAllAlbumTypesNotifier.value = value;
      return value;
    }
    return showAllAlbumTypesNotifier.value;
  }

  /// Persists the show all album types preference and notifies listeners.
  static Future<void> setShowAllAlbumTypes(
    bool value, [
    SharedPreferences? preferences,
  ]) async {
    showAllAlbumTypesNotifier.value = value;
    final prefs = preferences ?? _prefs;
    if (prefs != null) {
      await prefs.setBool(keyShowAllAlbumTypes, value);
    } else {
      try {
        _prefs = await SharedPreferences.getInstance();
        await _prefs?.setBool(keyShowAllAlbumTypes, value);
      } catch (_) {}
    }
  }

  @visibleForTesting
  static void setPreferencesForTesting(SharedPreferences? prefs) {
    _prefs = prefs;
    if (prefs != null) {
      showAllAlbumTypesNotifier.value =
          prefs.getBool(keyShowAllAlbumTypes) ?? false;
    } else {
      showAllAlbumTypesNotifier.value = false;
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _prefs = null;
    showAllAlbumTypesNotifier.value = false;
  }
}
