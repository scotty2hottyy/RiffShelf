import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/database/tab_repository.dart';
import '../../features/artwork/artwork_service.dart';
import 'tab_import_service.dart';

/// iCloud Documents are imported into the existing offline SQLite library.
/// No source files are deleted or uploaded to a server.
class ICloudTabFile {
  const ICloudTabFile({required this.name, required this.path});
  final String name;
  final String path;
}

abstract class ICloudFileSource {
  Future<List<ICloudTabFile>> list();
  Future<Uint8List> read(ICloudTabFile file);
}

class NativeICloudFileSource implements ICloudFileSource {
  const NativeICloudFileSource();
  static const _channel = MethodChannel('com.sonniersolution.riffshelf/icloud');

  @override
  Future<List<ICloudTabFile>> list() async {
    final entries = await _channel.invokeListMethod<Map>('list') ?? [];
    return [
      for (final entry in entries)
        if (entry['name'] is String && entry['path'] is String)
          ICloudTabFile(name: entry['name'] as String, path: entry['path'] as String),
    ];
  }

  @override
  Future<Uint8List> read(ICloudTabFile file) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'read',
      {'path': file.path},
    );
    if (bytes == null) throw const FormatException('iCloud file was empty.');
    return bytes;
  }
}

class ICloudImportReport {
  const ICloudImportReport({
    this.imported = 0,
    this.duplicates = 0,
    this.pending = 0,
    this.failed = 0,
  });
  final int imported;
  final int duplicates;
  final int pending;
  final int failed;

  String get description =>
      'iCloud: $imported imported, $duplicates already saved, '
      '$pending downloading, $failed failed';
}

class ICloudImportService {
  const ICloudImportService({required this.source});
  final ICloudFileSource source;

  /// Repeated scans are safe: import keys include file content and track index.
  /// All usable GP tracks are imported; percussion/empty tracks are skipped.
  Future<ICloudImportReport> sync(TabRepository repository) async {
    const importer = TabImportService();
    var imported = 0;
    var duplicates = 0;
    var pending = 0;
    var failed = 0;
    for (final file in await source.list()) {
      final extension = file.name.split('.').last.toLowerCase();
      if (!importer.supportsExtension(extension)) continue;
      Uint8List bytes;
      try {
        bytes = await source.read(file);
      } on PlatformException catch (error) {
        if (error.code == 'pending') {
          pending++;
        } else {
          failed++;
        }
        continue;
      } catch (_) {
        failed++;
        continue;
      }
      try {
        if (extension == 'txt') {
          final tab = importer.parseText(bytes, file.name);
          try {
            final saved = await repository.save(
              tab.copyWith(importKey: importer.importKey(bytes, 0)),
            );
            ArtworkService.scheduleAutomatic(repository, saved);
            imported++;
          } on DuplicateTabException {
            duplicates++;
          }
        } else {
          final document = importer.parseGuitarPro(bytes);
          for (final track in document.tracks) {
            try {
              final tab = importer.convertTrack(document, track.index, file.name);
              final saved = await repository.save(
                tab.copyWith(
                  importKey: importer.importKey(bytes, track.index),
                ),
              );
              ArtworkService.scheduleAutomatic(repository, saved);
              imported++;
            } on DuplicateTabException {
              duplicates++;
            } on FormatException {
              // Non-playable or percussion tracks are not user tabs.
            }
          }
        }
      } catch (_) {
        failed++;
      }
    }
    return ICloudImportReport(
      imported: imported,
      duplicates: duplicates,
      pending: pending,
      failed: failed,
    );
  }
}
