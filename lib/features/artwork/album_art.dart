import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../core/models/saved_tab.dart';

Map<String, dynamic>? artworkMetadata(SavedTab tab) {
  try {
    final value = jsonDecode(tab.artwork ?? 'null');
    return value is Map<String, dynamic> ? value : null;
  } catch (_) {
    return null;
  }
}

class AlbumArt extends StatelessWidget {
  const AlbumArt({super.key, required this.tab, required this.size});
  final SavedTab tab;
  final double size;

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final unit in '${tab.artist}|${tab.title}'.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1, hue, .48, .32).toColor(),
            HSLColor.fromAHSL(1, (hue + 65) % 360, .55, .58).toColor(),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.album_outlined,
        color: Colors.white70,
        size: size * .55,
      ),
    );
    final path = artworkMetadata(tab)?['local_path'];
    if (path is! String || path.isEmpty) return fallback;
    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: size <= 100 ? 250 : 500,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
