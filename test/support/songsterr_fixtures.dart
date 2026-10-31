// Synthetic music with the response shape observed live on 2026-09-26.
// Crucially, /api/meta tracks have NO partId: their original index is the ID.
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/features/search/domain/tab_source_provider.dart';

const songsterrResult = TabSearchResult(
  externalId: '19',
  title: 'Enter Sandman',
  artist: 'Metallica',
  instrument: InstrumentType.guitar,
  sourceName: 'Songsterr',
  sourceUrl: 'https://www.songsterr.com/a/wsa/song?id=19',
);

Map<String, dynamic> currentSongMetadata({bool multiple = true}) => {
  'songId': 19,
  'revisionId': 9115670,
  'image': 'v0-3-2-JzENNWgWFGiu9cC7',
  'title': 'Enter Sandman',
  'artist': 'Metallica',
  'tracks': [
    {
      'instrumentId': 41,
      'instrument': 'Viola',
      'name': 'Vocals',
      'tuning': [69, 62, 55, 48],
      'hash': 'vocals_fixture',
      'isVocalTrack': true,
    },
    {
      'instrumentId': 30,
      'instrument': 'Distortion Guitar',
      'name': 'Lead Guitar',
      'tuning': [64, 59, 55, 50, 45, 40],
      'hash': 'guitar_fixture',
      'isEmpty': false,
    },
    if (multiple)
      {
        'instrumentId': 33,
        'instrument': 'Electric Bass (finger)',
        'name': 'Bass',
        'tuning': [43, 38, 33, 28],
        'hash': 'bass_fixture',
        'isEmpty': false,
      },
    {
      'instrumentId': 1024,
      'instrument': 'Drums',
      'name': 'Drums',
      'tuning': [],
    },
  ],
};

Map<String, dynamic> currentTrackPayload({
  List<int> tuning = const [64, 59, 55, 50, 45, 40],
  int partId = 1,
}) => {
  'name': 'Lead Guitar',
  'songId': 19,
  'revisionId': 9115670,
  'partId': partId,
  'tuning': tuning,
  'strings': tuning.length,
  'instrumentId': 30,
  'instrument': 'Distortion Guitar',
  'version': 14,
  'capo': 0,
  'automations': {
    'tempo': [
      {'measure': 0, 'position': 0, 'bpm': 123, 'type': 4},
      {'measure': 1, 'position': 0, 'bpm': 100, 'type': 4},
    ],
  },
  'measures': [
    {
      'signature': [4, 4],
      'repeatStart': true,
      'voices': [
        {
          'beats': [
            {
              'duration': [1, 4],
              'type': 4,
              'notes': [
                {'string': tuning.length - 1, 'fret': 2},
              ],
            },
            {
              'duration': [3, 4],
              'type': 2,
              'dots': 1,
              'rest': true,
              'notes': [
                {'rest': true},
              ],
            },
          ],
        },
      ],
    },
    {
      'signature': [3, 4],
      'repeatEnd': 2,
      'voices': [
        {
          'beats': [
            {
              'duration': [3, 8],
              'type': 4,
              'dots': 1,
              'notes': [
                {'string': 0, 'fret': 5},
              ],
            },
            {
              'duration': [3, 8],
              'type': 4,
              'dots': 1,
              'notes': [
                {'rest': true},
              ],
            },
          ],
        },
      ],
    },
    {
      'voices': [
        {
          'beats': [
            for (var i = 0; i < 3; i++)
              {
                'duration': [1, 12],
                'type': 8,
                'tuplet': 3,
                'notes': [
                  {'string': 1, 'fret': i},
                ],
              },
            {
              'duration': [1, 2],
              'type': 2,
              'rest': true,
              'notes': [
                {'rest': true},
              ],
            },
          ],
        },
      ],
    },
  ],
};
