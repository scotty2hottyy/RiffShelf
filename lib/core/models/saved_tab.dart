import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'instrument_type.dart';
import 'tab_structure.dart';
import 'tuning.dart';

@immutable
class SavedTab {
  const SavedTab({
    this.id,
    required this.title,
    required this.artist,
    required this.source,
    required this.sourceUrl,
    this.sourceId,
    this.importKey,
    this.tabType = TabType.tab,
    this.trackName,
    required this.instrument,
    required this.stringCount,
    required this.tuning,
    this.capo = 0,
    this.bpm,
    this.tags = const [],
    this.asciiTab = '',
    this.measures = const [],
    this.sourceData,
    this.classification = InstrumentClassification.other,
    this.isFavorite = false,
    this.albumArt,
  }) : assert(stringCount > 0),
       assert(capo >= 0);

  final int? id;
  final String title;
  final String artist;
  final String source;
  final String sourceUrl;
  final String? sourceId;

  /// Stable identity of the imported file and selected track, when available.
  final String? importKey;
  final TabType tabType;
  final String? trackName;
  final InstrumentType instrument;
  final int stringCount;
  final List<String> tuning;
  final int capo;
  final int? bpm;
  final List<String> tags;
  final String asciiTab;
  final List<TabMeasure> measures;
  final String? sourceData;
  final InstrumentClassification classification;
  final bool isFavorite;

  /// Optional artwork location or other artwork metadata.
  final String? albumArt;

  bool get hasStructuredContent =>
      measures.isNotEmpty &&
      measures.any(
        (measure) =>
            measure.beats.any((beat) => beat.isRest || beat.notes.isNotEmpty),
      );
  bool get hasTextContent => asciiTab.trim().isNotEmpty;
  bool get hasUsableContent => hasStructuredContent || hasTextContent;

  SavedTab copyWith({
    int? id,
    List<String>? tags,
    bool? isFavorite,
    String? importKey,
  }) => SavedTab(
    id: id ?? this.id,
    title: title,
    artist: artist,
    source: source,
    sourceUrl: sourceUrl,
    sourceId: sourceId,
    importKey: importKey ?? this.importKey,
    tabType: tabType,
    trackName: trackName,
    instrument: instrument,
    stringCount: stringCount,
    tuning: tuning,
    capo: capo,
    bpm: bpm,
    tags: tags ?? this.tags,
    asciiTab: asciiTab,
    measures: measures,
    sourceData: sourceData,
    classification: classification,
    isFavorite: isFavorite ?? this.isFavorite,
    albumArt: albumArt,
  );

  SavedTab copyWithSourceData(String? value) => SavedTab(
    id: id,
    title: title,
    artist: artist,
    source: source,
    sourceUrl: sourceUrl,
    sourceId: sourceId,
    importKey: importKey,
    tabType: tabType,
    trackName: trackName,
    instrument: instrument,
    stringCount: stringCount,
    tuning: tuning,
    capo: capo,
    bpm: bpm,
    tags: tags,
    asciiTab: asciiTab,
    measures: measures,
    sourceData: value,
    classification: classification,
    isFavorite: isFavorite,
    albumArt: albumArt,
  );

  SavedTab replaceExisting(SavedTab existing) => SavedTab(
    id: existing.id,
    title: title,
    artist: artist,
    source: source,
    sourceUrl: sourceUrl,
    sourceId: sourceId ?? existing.sourceId,
    importKey: importKey ?? existing.importKey,
    tabType: tabType,
    trackName: trackName,
    instrument: instrument,
    stringCount: stringCount,
    tuning: tuning,
    capo: capo,
    bpm: bpm,
    tags: existing.tags,
    asciiTab: asciiTab,
    measures: measures,
    sourceData: sourceData,
    classification: classification,
    isFavorite: isFavorite,
    albumArt: albumArt,
  );

  SavedTab withMetadata({
    required String title,
    required String artist,
    required InstrumentType instrument,
    required List<String> tuning,
    required int capo,
    required int? bpm,
    required List<String> tags,
    required String? trackName,
    InstrumentClassification? classification,
  }) => SavedTab(
    id: id,
    title: title,
    artist: artist,
    source: source,
    sourceUrl: sourceUrl,
    sourceId: sourceId,
    importKey: importKey,
    tabType: tabType,
    trackName: trackName,
    instrument: instrument,
    stringCount: tuning.length,
    tuning: tuning,
    capo: capo,
    bpm: bpm,
    tags: tags,
    asciiTab: asciiTab,
    measures: measures,
    sourceData: sourceData,
    classification: classification ?? this.classification,
    isFavorite: isFavorite,
    albumArt: albumArt,
  );

  Map<String, Object?> toDatabaseMap() => {
    if (id != null) 'id': id,
    'title': title,
    'artist': artist,
    'source': source,
    'source_url': sourceUrl,
    'source_id': sourceId,
    'import_key': importKey,
    'tab_type': tabType.name,
    'track_name': trackName,
    'instrument': instrument.name,
    'string_count': stringCount,
    'tuning': jsonEncode(tuning),
    'tuning_key': StandardTunings.keyFor(tuning),
    'capo': capo,
    'bpm': bpm,
    'tags': jsonEncode(tags),
    'ascii_tab': asciiTab,
    'structure': jsonEncode(
      measures.map((measure) => measure.toJson()).toList(),
    ),
    'source_data': sourceData,
    'classification': classification.name,
    'is_favorite': isFavorite ? 1 : 0,
    'album_art': albumArt,
  };

  factory SavedTab.fromDatabaseMap(Map<String, Object?> map) {
    final structure = jsonDecode(map['structure']! as String) as List<Object?>;
    return SavedTab(
      id: map['id'] as int?,
      title: map['title']! as String,
      artist: map['artist']! as String,
      source: map['source']! as String,
      sourceUrl: map['source_url']! as String,
      sourceId: map['source_id'] as String?,
      importKey: map['import_key'] as String?,
      tabType: TabType.fromValue(map['tab_type'] as String?),
      trackName: map['track_name'] as String?,
      instrument: InstrumentType.fromJson(map['instrument']! as String),
      stringCount: map['string_count']! as int,
      tuning: (jsonDecode(map['tuning']! as String) as List<Object?>)
          .cast<String>(),
      capo: map['capo']! as int,
      bpm: map['bpm'] as int?,
      tags: (jsonDecode(map['tags']! as String) as List<Object?>)
          .cast<String>(),
      asciiTab: map['ascii_tab']! as String,
      measures: structure
          .map((item) => TabMeasure.fromJson(item! as Map<String, Object?>))
          .toList(),
      sourceData: map['source_data'] as String?,
      classification: InstrumentClassification.values.firstWhere(
        (value) => value.name == map['classification'],
        orElse: () => InstrumentClassification.other,
      ),
      isFavorite: map['is_favorite'] == 1,
      albumArt: map['album_art'] as String?,
    );
  }
}
