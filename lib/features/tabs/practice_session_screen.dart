import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/models/saved_tab.dart';
import '../../core/models/tab_structure.dart';
import '../tuner/audio_input.dart';
import '../tuner/pitch_detector.dart';
import '../tuner/tuner_controller.dart';
import 'note_matcher.dart';
import 'practice_progression_controller.dart';
import 'practice_timeline.dart';

const _minZoom = 0.6;
const _maxZoom = 1.8;

/// Full-screen right-to-left scrolling practice mode: notes approach a fixed
/// playhead from the right (future) and drift past it to the left (already
/// played), while strings are laid out vertically - a 2D timeline of the tab.
class PracticeSessionScreen extends StatefulWidget {
  const PracticeSessionScreen({
    super.key,
    required this.tab,
    this.inputFactory,
  });
  final TunerAudioInput Function()? inputFactory;
  final SavedTab tab;

  @override
  State<PracticeSessionScreen> createState() => _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends State<PracticeSessionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _playheadX = 36.0;
  static const _topPadding = 26.0;
  static const _baseStringSpacing = 30.0;
  static const _basePixelsPerBeat = 70.0;
  static const _endOfTrackPadBeats = 4.0;

  late final PracticeTimeline _timeline = PracticeTimeline.forScrolling(
    widget.tab,
  );
  late final double _totalBeats = _timeline.totalBeats + _endOfTrackPadBeats;

  final ValueNotifier<double> _elapsedBeats = ValueNotifier(0);
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _playing = false;
  bool _noteFollowing = false;
  TunerController? _microphone;
  Timer? _noteTimeout;
  String? _followFeedback;
  String? _recognizedNote;
  double? _followDragBeat;
  late final PracticeProgressionController _progression =
      PracticeProgressionController(
        _timeline,
        allowApproximateTiming: true,
        supportsPitch: (midi) {
          final hz = frequencyFromMidi(midi);
          return hz >= PitchDetector.defaultMinFrequency &&
              hz <= PitchDetector.defaultMaxFrequency;
        },
      );
  bool _looping = false;
  bool _metronome = false;
  final ValueNotifier<bool> _metronomeFlash = ValueNotifier(false);

  // "Speed" is a percentage of the tab's own authored tempo (or 100 BPM if
  // none was recorded), rather than a raw BPM value, so practicing slower
  // never requires knowing or fiddling with absolute tempo numbers.
  late final double _baseBpm = (widget.tab.bpm ?? 100).toDouble();
  double _speedPercent = 100;
  double get _bpm => _baseBpm * _speedPercent / 100;

  // The practice "section": a measure range to loop over. Defaults to the
  // whole song (first measure through the last).
  late RangeValues _sectionIndexRange = RangeValues(
    0,
    (_timeline.measures.length - 1).clamp(0, double.infinity).toDouble(),
  );
  double _scale = 1;

  int get _measureCount => _timeline.measures.length;

  bool get _isWholeSongSelected =>
      _measureCount == 0 ||
      (_sectionIndexRange.start <= 0 &&
          _sectionIndexRange.end >= _measureCount - 1);

  double get _loopStartBeat {
    if (_measureCount == 0) return 0;
    final index = _sectionIndexRange.start.round().clamp(0, _measureCount - 1);
    return _timeline.measures[index].startBeat;
  }

  double get _sectionEndBeat {
    if (_measureCount == 0) return _totalBeats;
    final index = _sectionIndexRange.end.round().clamp(0, _measureCount - 1);
    return index + 1 < _measureCount
        ? _timeline.measures[index + 1].startBeat
        : _timeline.totalBeats;
  }

  double get _loopEndBeat =>
      _sectionEndBeat +
      (!_looping && _isWholeSongSelected ? _endOfTrackPadBeats : 0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The native permission dialog can make the app temporarily inactive.
    if (_noteFollowing &&
        state == AppLifecycleState.inactive &&
        _microphone?.status == TunerStatus.starting) {
      return;
    }
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteTimeout?.cancel();
    _microphone?.removeListener(_onMicrophoneStatus);
    _microphone?.dispose();
    _ticker.dispose();
    _elapsedBeats.dispose();
    _metronomeFlash.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    final previous = _elapsedBeats.value;
    final loopStart = _loopStartBeat;
    final loopEnd = _loopEndBeat;
    final rawNext = previous + dt.inMicroseconds / 1e6 * (_bpm / 60);

    if (rawNext < loopEnd) {
      _fireMetronomeTicks(previous, rawNext);
      _elapsedBeats.value = rawNext;
      return;
    }

    // The end belongs to the next section, or to the loop's new first beat.
    // Excluding it here prevents two clicks at the same wrap boundary.
    _fireMetronomeTicks(previous, loopEnd, includeEnd: false);
    if (_looping && loopEnd > loopStart) {
      final regionLength = loopEnd - loopStart;
      final wrapped = loopStart + (rawNext - loopEnd) % regionLength;
      // The loop point is itself a beat boundary (a measure start); make
      // sure its click fires even though playback jumps straight past it.
      _fireMetronomeTicks(loopStart - 0.001, wrapped);
      _elapsedBeats.value = wrapped;
    } else {
      _elapsedBeats.value = loopEnd;
      _pause();
    }
  }

  void _fireMetronomeTicks(double from, double to, {bool includeEnd = true}) {
    if (!_metronome || to <= from) return;
    var beat = from.floor() + 1;
    while (includeEnd ? beat <= to : beat < to) {
      _clickMetronome(beat.toDouble());
      beat++;
    }
  }

  void _clickMetronome(double beat) {
    final isDownbeat = _timeline.measures.any(
      (marker) => (marker.startBeat - beat).abs() < 0.05,
    );
    SystemSound.play(
      isDownbeat ? SystemSoundType.alert : SystemSoundType.click,
    );
    HapticFeedback.selectionClick();
    _metronomeFlash.value = true;
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (mounted) _metronomeFlash.value = false;
    });
  }

  void _play() {
    if (_playing || _timeline.events.isEmpty) return;
    if (_noteFollowing) {
      _startFollowing();
      return;
    }
    final start = _loopStartBeat;
    final end = _loopEndBeat;
    if (_elapsedBeats.value < start || _elapsedBeats.value >= end) {
      _elapsedBeats.value = start;
    }
    _lastTick = Duration.zero;
    _ticker.start();
    setState(() => _playing = true);
  }

  void _pause() {
    if (!_playing) return;
    _ticker.stop();
    setState(() => _playing = false);
    if (_noteFollowing) {
      _noteTimeout?.cancel();
      _progression.clearEvidence();
      unawaited(_microphone?.stop());
    }
  }

  void _restart() {
    if (_noteFollowing) {
      _pause();
      _progression.restart();
      _elapsedBeats.value = _progression.positionBeats;
      setState(_clearFollowFeedback);
      return;
    }
    _ticker.stop();
    _elapsedBeats.value = _loopStartBeat;
    if (_playing) setState(() => _playing = false);
  }

  void _toggleLoop() {
    setState(() => _looping = !_looping);
    if (_noteFollowing) _progression.setLooping(_looping);
  }

  void _clearFollowFeedback() {
    _followFeedback = null;
    _recognizedNote = null;
  }

  void _setNoteFollowing(bool enabled) {
    _pause();
    final position = _elapsedBeats.value;
    setState(() {
      _noteFollowing = enabled;
      _clearFollowFeedback();
    });
    if (enabled) {
      _syncFollowSection();
      _progression.seek(
        position >= _sectionEndBeat ? _loopStartBeat : position,
      );
      _elapsedBeats.value = _progression.positionBeats;
    }
  }

  void _syncFollowSection() {
    _progression.setSection(
      startBeat: _loopStartBeat,
      endBeat: _sectionEndBeat,
    );
    _progression.setLooping(_looping);
  }

  void _startFollowing() {
    if (_progression.completed) _progression.restart();
    _elapsedBeats.value = _progression.positionBeats;
    if (_progression.completed) {
      setState(
        () => _followFeedback =
            'No supported notes in this section. Try timed practice.',
      );
      return;
    }
    final microphone = _microphone ??= TunerController(
      input: (widget.inputFactory ?? RecordAudioInput.new)(),
      onPitch: _observePitch,
    )..addListener(_onMicrophoneStatus);
    setState(() {
      _clearFollowFeedback();
      _playing = true;
    });
    unawaited(microphone.start());
  }

  void _onMicrophoneStatus() {
    if (!mounted || !_noteFollowing || !_playing) return;
    final status = _microphone!.status;
    final problem = switch (status) {
      TunerStatus.permissionDenied =>
        'Microphone access denied. Allow access in Settings and try again.',
      TunerStatus.noMicrophone =>
        'No microphone is available. Connect one or use timed practice.',
      TunerStatus.error =>
        'Microphone capture failed. Try again or use timed practice.',
      TunerStatus.idle => 'Microphone stopped. Press Play to resume.',
      _ => null,
    };
    if (problem != null) {
      _pause();
      setState(() => _followFeedback = problem);
      return;
    }
    if (status == TunerStatus.listening) _armNoteTimeout();
    setState(() {});
  }

  void _armNoteTimeout() {
    _noteTimeout?.cancel();
    _noteTimeout = Timer(const Duration(seconds: 20), () {
      if (!mounted || !_noteFollowing || !_playing) return;
      _pause();
      setState(
        () => _followFeedback =
            'No matching note heard. Press Play to try again.',
      );
    });
  }

  void _observePitch(PitchResult? pitch) {
    if (!mounted || !_noteFollowing || !_playing) return;
    final result = _progression.observe(pitch);
    if (result.matchedEvent case final matched?) {
      _elapsedBeats.value = result.positionBeats;
      final note = nearestNote(frequencyFromMidi(matched.expectedMidiPitch!))
          .label;
      setState(() {
        _recognizedNote = 'Recognized $note';
        _followFeedback = result.completed ? 'Section complete.' : null;
      });
      if (result.completed) {
        _pause();
      } else {
        _armNoteTimeout();
      }
    } else if (result.match?.status == NoteMatchStatus.notMatched &&
        _followFeedback != 'Waiting for the highlighted note.') {
      setState(() => _followFeedback = 'Waiting for the highlighted note.');
    }
  }

  Widget _followStatus() {
    final event = _progression.expectedEvent;
    final expected = event?.expectedMidiPitch;
    final status = _playing
        ? _microphone?.status == TunerStatus.listening
              ? 'Listening'
              : 'Starting microphone…'
        : expected == null && _followFeedback == null
        ? 'No supported single notes with known pitches in this section.'
        : 'Press Play to listen';
    final skipped = _progression.skippedPassages.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Semantics(
        liveRegion: true,
        child: Text(
          [
            status,
            if (expected != null)
              'Play ${nearestNote(frequencyFromMidi(expected)).label} (string ${event!.stringNumber}, fret ${event.fret})',
            ?_recognizedNote,
            ?_followFeedback,
            if (skipped > 0) '$skipped unsupported passages skipped.',
          ].join(' · '),
          key: const ValueKey('practice-follow-status'),
        ),
      ),
    );
  }

  void _toggleMetronome() => setState(() => _metronome = !_metronome);

  void _onSpeedChanged(double value) => setState(() => _speedPercent = value);

  void _onSectionChanged(RangeValues value) {
    _pause();
    setState(() => _sectionIndexRange = value);
    if (_noteFollowing) {
      _syncFollowSection();
      _elapsedBeats.value = _progression.positionBeats;
      setState(_clearFollowFeedback);
    } else {
      _elapsedBeats.value = _loopStartBeat;
    }
  }

  void _resetSection() => _onSectionChanged(
    RangeValues(0, (_measureCount - 1).clamp(0, double.infinity).toDouble()),
  );

  void _seekByPixels(double dx) {
    if (_playing) _pause();
    final pixelsPerBeat = _basePixelsPerBeat * _scale;
    final origin = _noteFollowing
        ? _followDragBeat ?? _elapsedBeats.value
        : _elapsedBeats.value;
    final target = (origin - dx / pixelsPerBeat).clamp(
      _loopStartBeat,
      _noteFollowing ? _sectionEndBeat : _loopEndBeat,
    );
    if (_noteFollowing) {
      _followDragBeat = target;
      _progression.seek(target);
      _elapsedBeats.value = _progression.positionBeats;
      setState(_clearFollowFeedback);
    } else {
      _elapsedBeats.value = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final theme = Theme.of(context);
    final textScale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      1.0,
      2.5,
    );
    final stringSpacing = _baseStringSpacing * _scale * textScale;
    final topPadding = _topPadding * textScale;
    final trackHeight = topPadding * 2 + (tab.stringCount - 1) * stringSpacing;
    return Scaffold(
      appBar: AppBar(title: Text('Practice · ${tab.title}')),
      body: _timeline.events.isEmpty
          ? _StaticPracticeTab(tab: tab)
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Semantics(
                          toggled: _noteFollowing,
                          child: Tooltip(
                            message: 'Note Following',
                            child: TextButton(
                              onPressed: () =>
                                  _setNoteFollowing(!_noteFollowing),
                              child: Text(
                                _noteFollowing
                                    ? 'Note by note ✓'
                                    : 'Note by note',
                              ),
                            ),
                          ),
                        ),
                        if (_noteFollowing) _followStatus(),
                        if (!_timeline.hasReliableTiming && !_noteFollowing)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Approximate timing for scrolling'),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ValueListenableBuilder<double>(
                                  valueListenable: _elapsedBeats,
                                  builder: (context, elapsed, _) => Text(
                                    'Measure ${_currentMeasureNumber(elapsed)} of '
                                    '${_timeline.measures.isEmpty ? 0 : _timeline.measures.last.number}',
                                    style: theme.textTheme.labelLarge,
                                  ),
                                ),
                              ),
                              if (!_noteFollowing && _metronome)
                                ValueListenableBuilder<bool>(
                                  key: const ValueKey(
                                    'practice-metronome-flash',
                                  ),
                                  valueListenable: _metronomeFlash,
                                  builder: (context, flashing, _) =>
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 80,
                                        ),
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: flashing
                                              ? theme.colorScheme.primary
                                              : theme
                                                    .colorScheme
                                                    .outlineVariant,
                                        ),
                                      ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: ValueListenableBuilder<double>(
                            valueListenable: _elapsedBeats,
                            builder: (context, elapsed, _) =>
                                LinearProgressIndicator(
                                  key: const ValueKey('practice-progress'),
                                  value: (elapsed / _totalBeats).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  minHeight: 5,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                          ),
                        ),
                        if (_measureCount > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            child: _SectionRangeControl(
                              range: _sectionIndexRange,
                              measureCount: _measureCount,
                              measureNumbers: _timeline.measures
                                  .map((marker) => marker.number)
                                  .toList(),
                              isWholeSong: _isWholeSongSelected,
                              onChanged: _onSectionChanged,
                              onReset: _resetSection,
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
                                    topPadding: topPadding,
                                    stringSpacing: stringSpacing,
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      key: const ValueKey('practice-track'),
                                      behavior: HitTestBehavior.opaque,
                                      onHorizontalDragStart: (_) =>
                                          _followDragBeat = null,
                                      onHorizontalDragUpdate: (details) =>
                                          _seekByPixels(details.delta.dx),
                                      child: ClipRect(
                                        child: ValueListenableBuilder<double>(
                                          valueListenable: _elapsedBeats,
                                          builder: (context, elapsed, _) => LayoutBuilder(
                                            builder: (context, constraints) => Stack(
                                              children: [
                                                CustomPaint(
                                                  size: Size(
                                                    constraints.maxWidth,
                                                    trackHeight,
                                                  ),
                                                  painter:
                                                      _PracticeTrackPainter(
                                                        stringCount:
                                                            tab.stringCount,
                                                        events:
                                                            _timeline.events,
                                                        measures:
                                                            _timeline.measures,
                                                        elapsedBeats: elapsed,
                                                        pixelsPerBeat:
                                                            _basePixelsPerBeat *
                                                            _scale,
                                                        playheadX: _playheadX,
                                                        stringSpacing:
                                                            stringSpacing,
                                                        topPadding: topPadding,
                                                        colorScheme:
                                                            theme.colorScheme,
                                                        textScale: textScale,
                                                        sectionStartBeat:
                                                            _isWholeSongSelected
                                                            ? null
                                                            : _loopStartBeat,
                                                        sectionEndBeat:
                                                            _isWholeSongSelected
                                                            ? null
                                                            : _sectionEndBeat,
                                                      ),
                                                ),
                                                Positioned(
                                                  left: _playheadX,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: IgnorePointer(
                                                    child: Container(
                                                      key: const ValueKey(
                                                        'practice-hit-line',
                                                      ),
                                                      width: 3,
                                                      color:
                                                          theme.brightness ==
                                                              Brightness.dark
                                                          ? const Color(
                                                              0xFF54E8D5,
                                                            )
                                                          : const Color(
                                                              0xFF006C65,
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              ],
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
                          noteFollowing: _noteFollowing,
                          playing: _playing,
                          looping: _looping,
                          metronome: _metronome,
                          speedPercent: _speedPercent,
                          effectiveBpm: _bpm,
                          scale: _scale,
                          onPlayPause: () => _playing ? _pause() : _play(),
                          onRestart: _restart,
                          onToggleLoop: _toggleLoop,
                          onToggleMetronome: _toggleMetronome,
                          onSpeedChanged: _onSpeedChanged,
                          onScaleChanged: (value) =>
                              // Slider endpoint arithmetic can slightly exceed
                              // its bounds (e.g. 1.8000000000000003).
                              setState(
                                () => _scale = value.clamp(_minZoom, _maxZoom),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  int _currentMeasureNumber(double elapsed) {
    var current = _timeline.measures.isEmpty
        ? 0
        : _timeline.measures.first.number;
    for (final marker in _timeline.measures) {
      if (marker.startBeat <= elapsed) {
        current = marker.number;
      } else {
        break;
      }
    }
    return current;
  }
}

/// Shows source notes without assigning playback positions to damaged timing.
class _StaticPracticeTab extends StatelessWidget {
  const _StaticPracticeTab({required this.tab});

  final SavedTab tab;

  String _measureText(int number, List<TabBeat> beats) {
    final lines = <String>['Measure $number'];
    for (var string = 1; string <= tab.stringCount; string++) {
      final label = tab.tuning.length == tab.stringCount
          ? tab.tuning[tab.stringCount - string]
          : 'String $string';
      final frets = [
        for (final beat in beats)
          beat.notes
              .where((note) => note.stringNumber == string && note.fret >= 0)
              .map((note) => note.fret)
              .join(',')
              .padRight(2, '-'),
      ].join('-');
      lines.add('$label|$frets');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final hasNotes = tab.measures.any(
      (measure) => measure.beats.any((beat) => beat.notes.isNotEmpty),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          hasNotes || tab.hasTextContent
              ? 'Timed practice is unavailable for this tab. Static tablature is shown below.'
              : 'Timed practice is unavailable for this tab.',
        ),
        const SizedBox(height: 16),
        if (tab.hasTextContent)
          SelectableText(
            tab.asciiTab,
            style: const TextStyle(fontFamily: 'monospace'),
          )
        else if (hasNotes)
          for (final measure in tab.measures)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText(
                _measureText(measure.number, measure.beats),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            )
        else
          const Text(
            'Practice mode needs structured tab data, which isn\'t available for this tab.',
          ),
      ],
    );
  }
}

/// A "practice a section" control: lets the player restrict (and loop) the
/// track to a contiguous range of measures instead of the whole song.
class _SectionRangeControl extends StatelessWidget {
  const _SectionRangeControl({
    required this.range,
    required this.measureCount,
    required this.measureNumbers,
    required this.isWholeSong,
    required this.onChanged,
    required this.onReset,
  });

  final RangeValues range;
  final int measureCount;
  final List<int> measureNumbers;
  final bool isWholeSong;
  final ValueChanged<RangeValues> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final startMeasure =
        measureNumbers[range.start.round().clamp(0, measureCount - 1)];
    final endMeasure =
        measureNumbers[range.end.round().clamp(0, measureCount - 1)];
    return Row(
      children: [
        const Icon(Icons.view_week_outlined, size: 18),
        Expanded(
          child: RangeSlider(
            key: const ValueKey('practice-section-slider'),
            values: range,
            min: 0,
            max: (measureCount - 1).toDouble(),
            divisions: measureCount - 1,
            labels: RangeLabels('$startMeasure', '$endMeasure'),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 92,
          child: Text(
            isWholeSong ? 'Whole song' : 'M$startMeasure–$endMeasure',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        IconButton(
          key: const ValueKey('practice-section-reset'),
          tooltip: 'Practice whole song',
          visualDensity: VisualDensity.compact,
          onPressed: isWholeSong ? null : onReset,
          icon: const Icon(Icons.clear, size: 18),
        ),
      ],
    );
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
    final factor = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      1.0,
      2.5,
    );
    final badgeSize = 26 * factor;
    return SizedBox(
      width: 34 * factor,
      height: height,
      child: Stack(
        children: [
          for (var i = 0; i < tab.stringCount; i++)
            Positioned(
              left: 0,
              top: topPadding + i * stringSpacing - badgeSize / 2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  i < tab.tuning.length
                      ? tab.tuning.reversed.elementAt(i)
                      : '?',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
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
    required this.events,
    required this.measures,
    required this.elapsedBeats,
    required this.pixelsPerBeat,
    required this.playheadX,
    required this.stringSpacing,
    required this.topPadding,
    required this.colorScheme,
    required this.textScale,
    this.sectionStartBeat,
    this.sectionEndBeat,
  });

  final int stringCount;
  final List<TimedNoteEvent> events;
  final List<MeasureMarker> measures;
  final double elapsedBeats;
  final double pixelsPerBeat;
  final double playheadX;
  final double stringSpacing;
  final double topPadding;
  final ColorScheme colorScheme;
  final double textScale;

  /// When set, highlights the selected practice section (a measure range)
  /// on the track, in beats, without the end-of-track padding.
  final double? sectionStartBeat;
  final double? sectionEndBeat;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colorScheme.surfaceContainerLow,
    );
    for (var s = 0; s < stringCount; s++) {
      if (s.isOdd) {
        final y = topPadding + s * stringSpacing;
        canvas.drawRect(
          Rect.fromLTWH(0, y - stringSpacing / 2, size.width, stringSpacing),
          Paint()..color = colorScheme.onSurface.withValues(alpha: .025),
        );
      }
    }
    final sectionStart = sectionStartBeat;
    final sectionEnd = sectionEndBeat;
    if (sectionStart != null && sectionEnd != null) {
      final left = playheadX + (sectionStart - elapsedBeats) * pixelsPerBeat;
      final right = playheadX + (sectionEnd - elapsedBeats) * pixelsPerBeat;
      final clampedLeft = left.clamp(0.0, size.width);
      final clampedRight = right.clamp(0.0, size.width);
      if (clampedRight > clampedLeft) {
        canvas.drawRect(
          Rect.fromLTRB(clampedLeft, 0, clampedRight, size.height),
          Paint()..color = colorScheme.tertiary.withValues(alpha: 0.08),
        );
      }
      final boundaryPaint = Paint()
        ..color = colorScheme.tertiary
        ..strokeWidth = 2;
      for (final x in [left, right]) {
        if (x >= -2 && x <= size.width + 2) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), boundaryPaint);
        }
      }
    }

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
      final x = playheadX + (marker.startBeat - elapsedBeats) * pixelsPerBeat;
      if (x < -40 || x > size.width + 40) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), measurePaint);
      textPainter.text = TextSpan(
        text: '${marker.number}',
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 3, 2));
    }

    final minNoteWidth = 22.0 * textScale;
    final noteHeight = 20.0 * textScale;
    for (final event in events) {
      final startX =
          playheadX + (event.startBeat - elapsedBeats) * pixelsPerBeat;
      final endX = playheadX + (event.endBeat - elapsedBeats) * pixelsPerBeat;
      if (endX < -minNoteWidth || startX > size.width + minNoteWidth) {
        continue;
      }
      final y = topPadding + (event.stringNumber - 1) * stringSpacing;

      // A note is "active" for as long as it's actually sounding (its
      // normalized duration), not just a fixed instant at the playhead.
      final active =
          elapsedBeats >= event.startBeat && elapsedBeats <= event.endBeat;
      final played = elapsedBeats > event.endBeat;

      final Color background;
      final Color foreground;
      if (active) {
        background = colorScheme.primary;
        foreground = colorScheme.onPrimary;
      } else if (played) {
        background = colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
        foreground = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
      } else {
        background = colorScheme.secondaryContainer;
        foreground = colorScheme.onSecondaryContainer;
      }

      final width = (endX - startX).clamp(minNoteWidth, double.infinity);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(startX, y - noteHeight / 2, width, noteHeight),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = background);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = (active ? colorScheme.primary : colorScheme.outlineVariant)
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 1.5 : 1,
      );

      textPainter.text = TextSpan(
        text: '${event.fret}',
        style: TextStyle(
          fontSize: 12 * textScale,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: foreground,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(startX + 4, y - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PracticeTrackPainter oldDelegate) =>
      oldDelegate.elapsedBeats != elapsedBeats ||
      oldDelegate.pixelsPerBeat != pixelsPerBeat ||
      oldDelegate.events != events ||
      oldDelegate.measures != measures ||
      oldDelegate.sectionStartBeat != sectionStartBeat ||
      oldDelegate.sectionEndBeat != sectionEndBeat ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.stringSpacing != stringSpacing ||
      oldDelegate.textScale != textScale;
}

class _PracticeControls extends StatelessWidget {
  const _PracticeControls({
    required this.noteFollowing,
    required this.playing,
    required this.looping,
    required this.metronome,
    required this.speedPercent,
    required this.effectiveBpm,
    required this.scale,
    required this.onPlayPause,
    required this.onRestart,
    required this.onToggleLoop,
    required this.onToggleMetronome,
    required this.onSpeedChanged,
    required this.onScaleChanged,
  });
  final bool noteFollowing;
  final bool playing;
  final bool looping;
  final bool metronome;
  final double speedPercent;
  final double effectiveBpm;
  final double scale;
  final VoidCallback onPlayPause;
  final VoidCallback onRestart;
  final VoidCallback onToggleLoop;
  final VoidCallback onToggleMetronome;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onScaleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.brightness == Brightness.dark
        ? const Color(0xFF54E8D5)
        : const Color(0xFF006C65);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Restart',
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay),
                ),
                IconButton.filled(
                  key: const ValueKey('practice-play-pause'),
                  tooltip: playing ? 'Pause' : 'Play',
                  style: IconButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF052723)
                        : Colors.white,
                  ),
                  onPressed: onPlayPause,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                Semantics(
                  toggled: looping,
                  child: IconButton(
                    key: const ValueKey('practice-loop-toggle'),
                    tooltip: looping ? 'Loop on' : 'Loop off',
                    onPressed: onToggleLoop,
                    icon: Icon(Icons.repeat, color: looping ? accent : null),
                  ),
                ),
                if (!noteFollowing)
                  Semantics(
                    toggled: metronome,
                    child: IconButton(
                      key: const ValueKey('practice-metronome-toggle'),
                      tooltip: metronome ? 'Metronome on' : 'Metronome off',
                      onPressed: onToggleMetronome,
                      icon: Icon(
                        Icons.av_timer,
                        color: metronome ? accent : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (!noteFollowing) ...[
              const SizedBox(height: 4),
              Text(
                '${speedPercent.round()}% · ${effectiveBpm.round()} BPM',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final speed in const [25, 50, 75, 100, 150])
                    Semantics(
                      button: true,
                      selected: speedPercent == speed,
                      label: '$speed% speed',
                      child: InkWell(
                        key: ValueKey('practice-speed-$speed'),
                        onTap: () => onSpeedChanged(speed.toDouble()),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width:
                              58 *
                              (MediaQuery.textScalerOf(context).scale(14) / 14)
                                  .clamp(1.0, 2.5),
                          constraints: const BoxConstraints(
                            minWidth: 50,
                            minHeight: 48,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: speedPercent == speed
                                ? accent.withValues(alpha: .15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: speedPercent == speed
                                  ? accent
                                  : Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                            ),
                          ),
                          child: Text(
                            '$speed%',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: speedPercent == speed ? accent : null,
                                  fontWeight: speedPercent == speed
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            Row(
              children: [
                const Icon(Icons.zoom_in, size: 18),
                Expanded(
                  child: Slider(
                    value: scale,
                    semanticFormatterCallback: (value) =>
                        'Zoom ${(value * 100).round()}%',
                    min: _minZoom,
                    max: _maxZoom,
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
