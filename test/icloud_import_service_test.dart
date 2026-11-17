import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/database/sqlite_tab_repository.dart';
import 'package:riffshelf/features/import/icloud_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Source implements ICloudFileSource {
  _Source(this.bytes);
  final Uint8List bytes;
  int reads = 0;

  @override
  Future<List<ICloudTabFile>> list() async => [
    const ICloudTabFile(name: 'my-tab.TXT', path: '/test/my-tab.TXT'),
  ];

  @override
  Future<Uint8List> read(ICloudTabFile file) async {
    reads++;
    return bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('iCloud importer keeps tabs offline and deduplicates repeated scans', () async {
    final source = _Source(Uint8List.fromList(utf8.encode(
      'G|--0--|\nD|--2--|\nA|-----|\nE|-----|\n',
    )));
    final repo = SqliteTabRepository(databaseFactoryFfi, inMemoryDatabasePath);
    try {
      final importer = ICloudImportService(source: source);
      final first = await importer.sync(repo);
      expect(first.imported, 1);
      expect(first.duplicates, 0);
      final saved = await repo.findTabs();
      expect(saved, hasLength(1));
      expect(saved.single.asciiTab, contains('G|--0--|'));
      final second = await importer.sync(repo);
      expect(second.imported, 0);
      expect(second.duplicates, 1);
      expect(await repo.findTabs(), hasLength(1));
      expect(source.reads, 2);
    } finally {
      await repo.close();
    }
  });
}
