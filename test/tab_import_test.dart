import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/features/import/tab_import_service.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const importer = TabImportService();
  test('rejects unsupported extensions', () {
    expect(importer.supportsExtension('pdf'), isFalse);
    expect(importer.supportsExtension(null), isFalse);
    expect(importer.supportsExtension('GP5'), isTrue);
  });
  for (final extension in ['gp3', 'gp4', 'gp5']) {
    test('imports $extension sample with playable notes', () {
      final bytes = File('test/fixtures/Chords.$extension').readAsBytesSync();
      final document = importer.parseGuitarPro(bytes);
      final tab = importer.convertTrack(document, 0, 'Chords.$extension');
      expect(tab.hasStructuredContent, isTrue);
      expect(
        tab.measures.expand((m) => m.beats).expand((b) => b.notes),
        isNotEmpty,
      );
      expect(tab.tuning.length, tab.stringCount);
    });
  }
  test('imports a GPX score and rejects its percussion track', () {
    final document = importer.parseGuitarPro(
      File('test/fixtures/synthetic.gpx').readAsBytesSync(),
    );
    expect(document.tracks.length, 2);
    final tab = importer.convertTrack(document, 0, 'synthetic.gpx');
    expect(tab.title, 'GPX Song');
    expect(tab.bpm, 90);
    expect(tab.measures.single.beats.single.notes.single.fret, 3);
    expect(
      () => importer.convertTrack(document, 1, 'synthetic.gpx'),
      throwsFormatException,
    );
  });
  test('rejects malformed data and preserves ASCII through SQLite', () async {
    expect(
      () => importer.parseGuitarPro(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => importer.parseText(
        Uint8List.fromList(utf8.encode('E|--0--|')),
        'bad.txt',
      ),
      throwsFormatException,
    );
    const content =
        '  Song\r\nG|--0--|\r\nD|-----|\r\nA|--2--|\r\nE|-----|\r\n';
    final tab = importer.parseText(
      Uint8List.fromList(utf8.encode(content)),
      'song.txt',
    );
    expect(tab.asciiTab, content);
    expect(tab.stringCount, 4);
    sqfliteFfiInit();
    final repo = SqliteTabRepository(databaseFactoryFfi, inMemoryDatabasePath);
    final saved = await repo.save(tab);
    expect((await repo.getById(saved.id!))!.asciiTab, content);
    await repo.close();
  });
}
