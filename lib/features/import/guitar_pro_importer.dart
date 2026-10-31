import 'dart:typed_data';

import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart' as gp;

import '../../core/models/instrument_type.dart';
import '../../core/models/saved_tab.dart';
import '../../core/models/tab_structure.dart';

class GuitarProTrackInfo {
  const GuitarProTrackInfo({
    required this.index,
    required this.name,
    required this.stringCount,
  });
  final int index;
  final String name;
  final int stringCount;
}

class GuitarProDocument {
  const GuitarProDocument(this.song);
  final gp.Song song;

  List<GuitarProTrackInfo> get tracks => [
    for (var index = 0; index < song.tracks.length; index++)
      GuitarProTrackInfo(
        index: index,
        name: song.tracks[index].name,
        stringCount: song.tracks[index].strings.length,
      ),
  ];
}

class GuitarProImporter {
  const GuitarProImporter();

  GuitarProDocument parse(Uint8List bytes) =>
      GuitarProDocument(gp.parseGp(bytes));

  SavedTab convert(
    GuitarProDocument document, {
    required int trackIndex,
    required String sourceUrl,
    String source = 'Guitar Pro import',
    String? sourceId,
  }) {
    final song = document.song;
    final track = song.tracks[trackIndex];
    final tuningMidi = track.strings.map((string) => string.value).toList();
    final tuning = tuningMidi.reversed.map(_midiName).toList();
    final measures = track.measures.map((measure) {
      final beats = <TabBeat>[];
      for (final voice in measure.voices) {
        for (final beat in voice.beats) {
          final duration =
              beat.duration.time.toDouble() / gp.Duration.quarterTime;
          final absoluteStart =
              beat.start?.toDouble() ?? measure.start.toDouble();
          final position =
              (absoluteStart - measure.start.toDouble()) /
              gp.Duration.quarterTime;
          beats.add(
            TabBeat(
              position: position < 0 ? 0 : position,
              duration: duration,
              isRest: beat.status == gp.BeatStatus.rest,
              notes: beat.notes
                  .where(
                    (note) =>
                        note.string > 0 && note.string <= track.strings.length,
                  )
                  .map(
                    (note) => TabNote(
                      stringNumber: note.string,
                      fret: note.value,
                      midiPitch: note.realValue,
                      duration: duration * note.durationPercent,
                    ),
                  )
                  .toList(),
            ),
          );
        }
      }
      beats.sort((a, b) => a.position.compareTo(b.position));
      if (beats.isEmpty) {
        beats.add(
          TabBeat(
            position: 0,
            duration:
                measure.timeSignature.numerator *
                4 /
                measure.timeSignature.denominator.value,
          ),
        );
      }
      return TabMeasure(
        number: measure.number,
        numerator: measure.timeSignature.numerator,
        denominator: measure.timeSignature.denominator.value,
        beats: beats,
      );
    }).toList();
    final instrument =
        (track.channel.instrument >= 32 && track.channel.instrument <= 39) ||
            tuning.length == 4
        ? InstrumentType.bass
        : InstrumentType.guitar;
    return SavedTab(
      title: song.title.isEmpty ? track.name : song.title,
      artist: song.artist,
      source: source,
      sourceUrl: sourceUrl,
      sourceId: sourceId,
      tabType: TabType.guitarPro,
      trackName: track.name,
      instrument: instrument,
      stringCount: tuning.length,
      tuning: tuning,
      capo: track.offset,
      bpm: song.tempo,
      measures: measures,
    );
  }

  static String _midiName(int midi) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }
}
