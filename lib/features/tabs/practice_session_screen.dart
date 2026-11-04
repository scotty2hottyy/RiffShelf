import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/models/saved_tab.dart';
import '../../core/models/tab_structure.dart';

/// A note flattened to its absolute position in the song timeline.
class _PracticeNote {
  const _PracticeNote({
    required this.beat,
    required this.stringNumber,
    required this.fret,
  });
  final double beat;
  final int stringNumber;
  final int fret;
}

/// A measure boundary flattened to its absolute position in the timeline.
class _MeasureMarker {
  const _MeasureMarker({required this.number, required this.beat});
  final int number;
  final double beat;
}

double _measureLength(TabMeasure measure) =>
    measure.numerator * 4 / measure.denominator;

List<_PracticeNote> _flattenNotes(SavedTab tab) {
  final notes = <_PracticeNote>[];
  var cursor = 0.0;
  for (final measure in tab.measures) {
    for (final beat in measure.beats) {
      if (beat.isRest) continue;
      for (final note in beat.notes) {
        notes.add(
          _PracticeNote(
            beat: cursor + beat.position,
            stringNumber: note.stringNumber,
            fret: note.fret,
          ),
        );
      }
    }
    cursor += _measureLength(measure);
  }
  return notes;
}

List<_MeasureMarker> _measureMarkers(SavedTab tab) {
  final markers = <_MeasureMarker>[];
  var cursor = 0.0;
  for (final measure in tab.measures) {
    markers.add(_MeasureMarker(number: measure.number, beat: cursor));
    cursor += _measureLength(measure);
  }
  return markers;
}

double _totalBeatsOf(SavedTab tab) =>
    tab.measures.fold(0.0, (sum, measure) => sum + _measureLength(measure));

/// Full-screen right-to-left scrolling practice mode: notes approach a fixed
/// playhead from the right (future) and drift past it to the left (already
/// played), while strings are laid out vertically - a 2D timeline of the tab.
class PracticeSessionScreen extends StatefulWidget {
  const PracticeSessionScreen({super.key, required this.tab});
  final SavedTab tab;

  @override
  State<PracticeSessionScreen> createState() => _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends State<PracticeSessionScreen>
    with SingleTickerProviderStateMixin {
  static const _playheadX = 36.0;
  static const _topPadding = 26.0;
  static const _baseStringSpacing = 30.0;
  static const _basePixelsPerBeat = 70.0;
  static const _endOfTrackPadBeats = 4.0;

  late final List<_PracticeNote> _notes = _flattenNotes(widget.tab);
  late final List<_MeasureMarker> _measures = _measureMarkers(widget.tab);
  late final double _totalBeats =
      _totalBeatsOf(widget.tab) + _endOfTrackPadBeats;

  final ValueNotifier<double> _elapsedBeats = ValueNotifier(0);
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _playing = false;
  late double _bpm = (widget.tab.bpm ?? 100).toDouble().clamp(20, 300);
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsedBeats.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    final next =
        _elapsedBeats.value + dt.inMicroseconds / 1e6 * (_bpm / 60);
    if (next >= _totalBeats) {
      _elapsedBeats.value = _totalBeats;
      _pause();
    } else {
      _elapsedBeats.value = next;
    }
  }

  void _play() {
    if (_playing || _notes.isEmpty) return;
    if (_elapsedBeats.value >= _totalBeats) {
      _elapsedBeats.value = 0;
    }
    _lastTick = Duration.zero;
    _ticker.start();
    setState(() => _playing = true);
  }

  void _pause() {
    if (!_playing) return;
    _ticker.stop();
    setState(() => _playing = false);
  }

  void _restart() {
    _ticker.stop();
    _elapsedBeats.value = 0;
    if (_playing) setState(() => _playing = false);
  }

  void _seekByPixels(double dx) {
    if (_playing) _pause();
    final pixelsPerBeat = _basePixelsPerBeat * _scale;
    _elapsedBeats.value = (_elapsedBeats.value - dx / pixelsPerBeat).clamp(
      0,
      _totalBeats,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final theme = Theme.of(context);
    final stringSpacing = _baseStringSpacing * _scale;
    final trackHeight = _topPadding * 2 + (tab.stringCount - 1) * stringSpacing;
    return Scaffold(
      appBar: AppBar(title: Text('Practice · ${tab.title}')),
      body: !tab.hasStructuredContent
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Practice mode needs structured tab data, which isn\'t '
                  'available for this tab.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _elapsedBeats,
                    builder: (context, elapsed, _) => Text(
                      'Measure ${_currentMeasureNumber(elapsed)} of '
                      '${tab.measures.isEmpty ? 0 : tab.measures.last.number}',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      height: trackHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StringLabelColumn(
                            tab: tab,
                            topPadding: _topPadding,
                            stringSpacing: stringSpacing,
                          ),
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('practice-track'),
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) =>
                                  _seekByPixels(details.delta.dx),
                              child: ClipRect(
                                child: ValueListenableBuilder<double>(
                                  valueListenable: _elapsedBeats,
                                  builder: (context, elapsed, _) =>
                                      LayoutBuilder(
                                        builder: (context, constraints) =>
                                            CustomPaint(
                                              size: Size(
                                                constraints.maxWidth,
                                                trackHeight,
                                              ),
                                              painter: _PracticeTrackPainter(
                                                stringCount: tab.stringCount,
                                                notes: _notes,
                                                measures: _measures,
                                                elapsedBeats: elapsed,
                                                pixelsPerBeat:
                                                    _basePixelsPerBeat *
                                                    _scale,
                                                playheadX: _playheadX,
                                                stringSpacing: stringSpacing,
                                                topPadding: _topPadding,
                                                colorScheme: theme.colorScheme,
                                              ),
                                            ),
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _PracticeControls(
                  playing: _playing,
                  bpm: _bpm,
                  scale: _scale,
                  onPlayPause: () => _playing ? _pause() : _play(),
                  onRestart: _restart,
                  onBpmChanged: (value) => setState(() => _bpm = value),
                  onScaleChanged: (value) => setState(() => _scale = value),
                ),
              ],
            ),
    );
  }

  int _currentMeasureNumber(double elapsed) {
    var current = widget.tab.measures.isEmpty
        ? 0
        : widget.tab.measures.first.number;
    for (final marker in _measures) {
      if (marker.beat <= elapsed) {
        current = marker.number;
      } else {
        break;
      }
    }
    return current;
  }
}

/// Fixed (non-scrolling) column of string/tuning labels, kept in sync with
/// [_PracticeTrackPainter]'s string spacing so labels line up with the lines.
class _StringLabelColumn extends StatelessWidget {
  const _StringLabelColumn({
    required this.tab,
    required this.topPadding,
    required this.stringSpacing,
  });
  final SavedTab tab;
  final double topPadding;
  final double stringSpacing;

  @override
  Widget build(BuildContext context) {
    final height = topPadding * 2 + (tab.stringCount - 1) * stringSpacing;
    return SizedBox(
      width: 28,
      height: height,
      child: Stack(
        children: [
          for (var i = 0; i < tab.stringCount; i++)
            Positioned(
              left: 0,
              top: topPadding + i * stringSpacing - 8,
              child: Text(
                tab.tuning.reversed.elementAt(i),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _PracticeTrackPainter extends CustomPainter {
  _PracticeTrackPainter({
    required this.stringCount,
    required this.notes,
    required this.measures,
    required this.elapsedBeats,
    required this.pixelsPerBeat,
    required this.playheadX,
    required this.stringSpacing,
    required this.topPadding,
    required this.colorScheme,
  });

  final int stringCount;
  final List<_PracticeNote> notes;
  final List<_MeasureMarker> measures;
  final double elapsedBeats;
  final double pixelsPerBeat;
  final double playheadX;
  final double stringSpacing;
  final double topPadding;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final stringPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;
    for (var s = 0; s < stringCount; s++) {
      final y = topPadding + s * stringSpacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stringPaint);
    }

    final measurePaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final marker in measures) {
      final x = playheadX + (marker.beat - elapsedBeats) * pixelsPerBeat;
      if (x < -40 || x > size.width + 40) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), measurePaint);
      textPainter.text = TextSpan(
        text: '${marker.number}',
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 3, 2));
    }

    final playheadPaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );

    const noteWidth = 26.0;
    const noteHeight = 20.0;
    final activeWindow = pixelsPerBeat * 0.18;
    for (final note in notes) {
      final x = playheadX + (note.beat - elapsedBeats) * pixelsPerBeat;
      if (x < -noteWidth || x > size.width + noteWidth) continue;
      final y = topPadding + (note.stringNumber - 1) * stringSpacing;
      final active = (x - playheadX).abs() <= activeWindow;
      final played = x < playheadX - activeWindow;

      final Color background;
      final Color foreground;
      if (active) {
        background = colorScheme.primary;
        foreground = colorScheme.onPrimary;
      } else if (played) {
        background = colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        );
        foreground = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
      } else {
        background = colorScheme.secondaryContainer;
        foreground = colorScheme.onSecondaryContainer;
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: noteWidth, height: noteHeight),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = background);

      textPainter.text = TextSpan(
        text: '${note.fret}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: foreground,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PracticeTrackPainter oldDelegate) =>
      oldDelegate.elapsedBeats != elapsedBeats ||
      oldDelegate.pixelsPerBeat != pixelsPerBeat ||
      oldDelegate.notes != notes ||
      oldDelegate.measures != measures;
}

class _PracticeControls extends StatelessWidget {
  const _PracticeControls({
    required this.playing,
    required this.bpm,
    required this.scale,
    required this.onPlayPause,
    required this.onRestart,
    required this.onBpmChanged,
    required this.onScaleChanged,
  });
  final bool playing;
  final double bpm;
  final double scale;
  final VoidCallback onPlayPause;
  final VoidCallback onRestart;
  final ValueChanged<double> onBpmChanged;
  final ValueChanged<double> onScaleChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Restart',
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay),
                ),
                IconButton.filled(
                  key: const ValueKey('practice-play-pause'),
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: onPlayPause,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.speed, size: 18),
                      Expanded(
                        child: Slider(
                          value: bpm,
                          min: 20,
                          max: 300,
                          divisions: 280,
                          label: '${bpm.round()} BPM',
                          onChanged: onBpmChanged,
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${bpm.round()} BPM',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.zoom_in, size: 18),
                Expanded(
                  child: Slider(
                    value: scale,
                    min: 0.6,
                    max: 1.8,
                    onChanged: onScaleChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
