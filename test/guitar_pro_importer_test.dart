import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart' as gp;
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/features/import/guitar_pro_importer.dart';
import 'package:riffshelf/features/import/tab_import_service.dart';

void main() {
  test('selects the requested track from a multi-track document', () {
    final song = _songWithTrack(6);
    final second = _songWithTrack(7).tracks.single;
    song.tracks.add(second);
    final document = GuitarProDocument(song);
    expect(document.tracks.map((track) => track.stringCount), [6, 7]);
    final tab = const TabImportService().convertTrack(document, 1, 'song.gp5');
    expect(tab.stringCount, 7);
    expect(tab.measures.single.beats.single.notes.single.fret, 0);
  });
  test('converts Guitar Pro track and preserves timing, tuning, pitch, and metadata', () {
    final song = _songWithTrack(6);
    final tab = const GuitarProImporter().convert(
      GuitarProDocument(song),
      trackIndex: 0,
      sourceUrl: 'file:///song.gp5',
      sourceId: 'song.gp5',
    );
    expect(tab.title, 'Fixture Song');
    expect(tab.artist, 'Fixture Artist');
    expect(tab.bpm, 120);
    expect(tab.trackName, 'Lead Guitar');
    expect(tab.stringCount, 6);
    expect(tab.tuning, ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']);
    expect(tab.measures.single.numerator, 4);
    expect(tab.measures.single.denominator, 4);
    expect(tab.measures.single.beats.single.duration, 1);
    expect(tab.measures.single.beats.single.notes.single.midiPitch, 64);
  });

  test('preserves extended string instruments', () {
    final tab = const GuitarProImporter().convert(
      GuitarProDocument(_songWithTrack(7)),
      trackIndex: 0,
      sourceUrl: 'file:///seven.gp',
    );
    expect(tab.stringCount, 7);
    expect(tab.instrument, InstrumentType.guitar);
    expect(tab.tuning.first, 'B1');
  });
}

gp.Song _songWithTrack(int stringCount) {
  final song = gp.Song()
    ..title = 'Fixture Song'
    ..artist = 'Fixture Artist'
    ..tempo = 120;
  final standardHighToLow = stringCount == 7
      ? [64, 59, 55, 50, 45, 40, 35]
      : [64, 59, 55, 50, 45, 40];
  final track = gp.Track(song, name: 'Lead Guitar')
    ..strings = [
      for (var index = 0; index < standardHighToLow.length; index++)
        gp.GuitarString(index + 1, standardHighToLow[index]),
    ];
  final header = gp.MeasureHeader(number: 1, start: gp.Duration.quarterTime);
  final measure = gp.Measure(track, header);
  final beat = gp.Beat(
    measure.voices.first,
    start: header.start,
    duration: gp.Duration(value: gp.Duration.quarter),
    status: gp.BeatStatus.normal,
  );
  beat.notes.add(gp.Note(beat, string: 1, value: 0, type: gp.NoteType.normal));
  measure.voices.first.beats.add(beat);
  track.measures.add(measure);
  song.measureHeaders.add(header);
  song.tracks.add(track);
  return song;
}
