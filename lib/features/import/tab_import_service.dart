import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/models/saved_tab.dart';
import 'ascii_tab_parser.dart';
import 'guitar_pro_importer.dart';

/// Turns files picked from the device into [SavedTab]s.
///
/// Supports Guitar Pro (GP3, GP4, GP5, GPX) and UTF-8 text tabs. Every
/// failure is reported as a [FormatException] with a message that can be
/// shown to the user.
class TabImportService {
  const TabImportService();

  /// Stable key for one track of one file, used to detect duplicate imports.
  String importKey(Uint8List bytes, int trackIndex) =>
      'sha256:${sha256.convert(bytes)}:track:$trackIndex';

  /// Whether files with [extension] can be imported. Case-insensitive.
  bool supportsExtension(String? extension) => const [
    'txt',
    'gp3',
    'gp4',
    'gp5',
    'gpx',
  ].contains(extension?.toLowerCase());

  /// Parses a Guitar Pro file so the user can choose a track.
  GuitarProDocument parseGuitarPro(Uint8List bytes) {
    try {
      final document = const GuitarProImporter().parse(bytes);
      if (document.tracks.isEmpty) {
        throw const FormatException('No tracks found');
      }
      return document;
    } catch (_) {
      throw const FormatException(
        'This Guitar Pro file is malformed or uses an unsupported variant.',
      );
    }
  }

  /// Converts track [index] of [document] into a tab. Rejects drum tracks
  /// and tracks without fretted notes.
  SavedTab convertTrack(GuitarProDocument document, int index, String name) {
    try {
      if (document.song.tracks[index].isPercussionTrack ||
          document.song.tracks[index].strings.isEmpty) {
        throw const FormatException(
          'This track is not a stringed tablature track.',
        );
      }
      final tab = const GuitarProImporter().convert(
        document,
        trackIndex: index,
        sourceUrl: name,
        sourceId: name,
      );
      if (tab.stringCount == 0 ||
          !tab.measures.any((m) => m.beats.any((b) => b.notes.isNotEmpty))) {
        throw const FormatException('This track has no playable tablature.');
      }
      return tab;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('This track cannot be imported.');
    }
  }

  /// Parses a plain-text ASCII tab, inferring instrument, string count,
  /// and tuning. Chord-only sheets are rejected.
  SavedTab parseText(Uint8List bytes, String name) {
    final String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      throw const FormatException('Text tabs must be encoded as UTF-8.');
    }
    final normalized = content.replaceAll('\r\n', '\n');
    if (content.trim().isEmpty ||
        AsciiTabParser.isMalformed(normalized) ||
        !AsciiTabParser.hasNotes(normalized)) {
      throw const FormatException(
        'This file does not contain usable tablature.',
      );
    }
    final inference = AsciiTabParser.infer(normalized);
    if (inference.type.name == 'chords') {
      throw const FormatException(
        'This file does not contain recognizable tablature.',
      );
    }
    return SavedTab(
      title: name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), ''),
      artist: '',
      source: 'Text import',
      sourceUrl: name,
      sourceId: name,
      instrument: inference.instrument,
      stringCount: inference.stringCount,
      tuning: inference.tuning,
      tabType: inference.type,
      asciiTab: content,
    );
  }
}
