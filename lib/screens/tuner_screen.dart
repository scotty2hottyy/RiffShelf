import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/tuning.dart';
import '../core/models/instrument_type.dart';
import '../features/tuner/audio_input.dart';
import '../features/tuner/tuner_controller.dart';
import '../features/tuner/tuning_store.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({
    super.key,
    this.inputFactory,
    this.preset,
    this.settingsStore,
  });

  /// A fixed arrangement tuning; null keeps the standalone preset picker.
  final TuningPreset? preset;

  /// Overrides the microphone source (used by tests).
  final TunerAudioInput Function()? inputFactory;

  /// Overrides local tuner preferences (used by tests).
  final TunerSettingsStore? settingsStore;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver {
  late final TunerController _controller = TunerController(
    input: (widget.inputFactory ?? RecordAudioInput.new)(),
  )..preset = widget.preset ?? TunerPresets.guitarStandard;
  late final TunerSettingsStore _settingsStore =
      widget.settingsStore ?? LocalTunerSettingsStore();
  List<CustomTuning> _customTunings = [];
  String? _selectedId;
  bool _selectionTouched = false;
  Future<void> _saveQueue = Future<void>.value();

  String _builtInId(TuningPreset preset) =>
      'preset:${preset.instrument.name}:${preset.name}';

  Future<void> _loadSettings() async {
    if (widget.preset != null) return;
    try {
      final settings = await _settingsStore.load();
      if (!mounted) return;
      setState(() => _customTunings = settings.customTunings);
      if (_selectionTouched) return;
      for (final preset in TunerPresets.all) {
        if (_builtInId(preset) == settings.selectedId) {
          _controller.preset = preset;
          _selectedId = settings.selectedId;
          return;
        }
      }
      for (final custom in _customTunings) {
        if (custom.id == settings.selectedId) {
          _controller.preset = custom.preset;
          _selectedId = custom.id;
          return;
        }
      }
    } catch (_) {
      // The default tuning remains usable if local preferences are unavailable.
    }
  }

  void _saveSettings() {
    final settings = TunerSettings(
      customTunings: List.unmodifiable(_customTunings),
      selectedId: _selectedId,
    );
    _saveQueue = _saveQueue
        .then((_) => _settingsStore.save(settings))
        .catchError((Object _) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not save tuner settings.')),
            );
          }
        });
  }

  void _select(TuningPreset preset, String id) {
    _selectionTouched = true;
    _selectedId = id;
    _controller.preset = preset;
    _saveSettings();
  }

  Future<void> _editTuning([CustomTuning? existing]) async {
    final preset = await _showTuningDialog(
      context,
      existing?.preset ?? _controller.preset,
      editing: existing != null,
    );
    if (preset == null || !mounted) return;
    final custom = CustomTuning(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      preset: preset,
    );
    setState(() {
      if (existing != null) {
        _customTunings = [
          for (final item in _customTunings)
            item.id == existing.id ? custom : item,
        ];
      } else {
        _customTunings = [..._customTunings, custom];
      }
    });
    _select(preset, custom.id);
  }

  void _deleteTuning(CustomTuning custom) {
    setState(
      () => _customTunings = [
        for (final item in _customTunings)
          if (item.id != custom.id) item,
      ],
    );
    if (_selectedId == custom.id) {
      final fallback = custom.preset.instrument == InstrumentType.bass
          ? TunerPresets.bassStandard
          : TunerPresets.guitarStandard;
      _select(fallback, _builtInId(fallback));
    } else {
      _saveSettings();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The navigation keeps this screen alive while hidden; release the mic then.
    if (!TickerMode.valuesOf(context).enabled &&
        _controller.status != TunerStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.stop());
    }

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.preset == null)
                  _PresetPicker(
                    controller: _controller,
                    customTunings: _customTunings,
                    selectedId: _selectedId,
                    onSelect: _select,
                    onCreate: () => _editTuning(),
                    onEdit: _editTuning,
                    onDelete: _deleteTuning,
                    builtInId: _builtInId,
                  )
                else
                  Text(widget.preset!.name),
                const SizedBox(height: 20),
                _MeterCard(controller: _controller),
                const SizedBox(height: 16),
                _StatusMessage(controller: _controller),
                const SizedBox(height: 8),
                _ActionButton(controller: _controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({
    required this.controller,
    required this.customTunings,
    required this.selectedId,
    required this.onSelect,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.builtInId,
  });
  final TunerController controller;
  final List<CustomTuning> customTunings;
  final String? selectedId;
  final void Function(TuningPreset, String) onSelect;
  final VoidCallback onCreate;
  final void Function(CustomTuning) onEdit;
  final void Function(CustomTuning) onDelete;
  final String Function(TuningPreset) builtInId;

  @override
  Widget build(BuildContext context) {
    final instrument = controller.preset.instrument;
    final selectedCustom = [
      for (final item in customTunings)
        if (item.id == selectedId) item,
    ].firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final type in [InstrumentType.guitar, InstrumentType.bass])
              ChoiceChip(
                label: Text(type.label),
                selected: instrument == type,
                onSelected: (_) {
                  final preset = type == InstrumentType.guitar
                      ? TunerPresets.guitarStandard
                      : TunerPresets.bassStandard;
                  onSelect(preset, builtInId(preset));
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in TunerPresets.all)
              if (preset.instrument == instrument)
                ChoiceChip(
                  label: Text(preset.name),
                  selected: identical(preset, controller.preset),
                  onSelected: (_) => onSelect(preset, builtInId(preset)),
                ),
            for (final custom in customTunings)
              if (custom.preset.instrument == instrument)
                ChoiceChip(
                  label: Text(custom.preset.name),
                  selected: custom.id == selectedId,
                  onSelected: (_) => onSelect(custom.preset, custom.id),
                ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('New tuning'),
            ),
            if (selectedCustom != null) ...[
              TextButton.icon(
                onPressed: () => onEdit(selectedCustom),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit tuning'),
              ),
              TextButton.icon(
                onPressed: () => onDelete(selectedCustom),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete tuning'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

Future<TuningPreset?> _showTuningDialog(
  BuildContext context,
  TuningPreset initial, {
  bool editing = false,
}) async {
  final name = TextEditingController(
    text: editing ? initial.name : 'My tuning',
  );
  final notes = [
    for (final note in initial.notes) TextEditingController(text: note),
  ];
  var instrument = initial.instrument;
  var count = initial.stringCount;
  String? error;

  final result = await showDialog<TuningPreset>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final counts = instrument == InstrumentType.guitar
            ? [6, 7, 8, 9, 10, 11, 12]
            : [4, 5, 6];
        return AlertDialog(
          title: const Text('Custom tuning'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('tuning-name'),
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  DropdownButtonFormField<InstrumentType>(
                    key: const Key('tuning-instrument'),
                    initialValue: instrument,
                    decoration: const InputDecoration(labelText: 'Instrument'),
                    items: [
                      for (final type in [
                        InstrumentType.guitar,
                        InstrumentType.bass,
                      ])
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        instrument = value;
                        final defaults = value == InstrumentType.guitar
                            ? TunerPresets.guitarStandard.notes
                            : TunerPresets.bassStandard.notes;
                        count = defaults.length;
                        for (var i = 0; i < defaults.length; i++) {
                          if (i < notes.length) {
                            notes[i].text = defaults[i];
                          } else {
                            notes.add(TextEditingController(text: defaults[i]));
                          }
                        }
                        error = null;
                      });
                    },
                  ),
                  DropdownButtonFormField<int>(
                    key: ValueKey('tuning-count-${instrument.name}'),
                    initialValue: counts.contains(count) ? count : counts.first,
                    decoration: const InputDecoration(labelText: 'Strings'),
                    items: [
                      for (final value in counts)
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        count = value;
                        while (notes.length < count) {
                          notes.add(TextEditingController(text: 'E2'));
                        }
                        error = null;
                      });
                    },
                  ),
                  for (var index = 0; index < count; index++)
                    TextField(
                      key: Key('tuning-note-$index'),
                      controller: notes[index],
                      decoration: InputDecoration(
                        labelText: 'String ${index + 1} (low to high)',
                        hintText: 'E2',
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final values = [
                  for (var index = 0; index < count; index++)
                    notes[index].text.trim(),
                ];
                final validation = tuningValidationError(
                  name.text,
                  instrument,
                  values,
                );
                if (validation != null) {
                  setDialogState(() => error = validation);
                  return;
                }
                Navigator.pop(
                  context,
                  TuningPreset(
                    name: name.text.trim(),
                    instrument: instrument,
                    notes: List.unmodifiable(values),
                  ),
                );
              },
              child: const Text('Save tuning'),
            ),
          ],
        );
      },
    ),
  );
  return result;
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({required this.controller});
  final TunerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = controller.reading;
    final accent = theme.brightness == Brightness.dark
        ? const Color(0xFF54E8D5)
        : const Color(0xFF006C65);
    final color = reading == null
        ? theme.colorScheme.onSurfaceVariant
        : reading.inTune
        ? accent
        : reading.targetCents.abs() < 20
        ? Colors.amber
        : Colors.deepOrangeAccent;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF101B1E)
            : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            controller.selectedStringIndex == null
                ? reading?.targetNote ?? '--'
                : controller.preset.notes[controller.selectedStringIndex!],
            key: const Key('tuner-target-note'),
            style: theme.textTheme.displayLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            reading == null
                ? 'Play a string'
                : 'Detected ${reading.note.label} · '
                      '${reading.frequency.toStringAsFixed(1)} Hz · '
                      '${reading.targetCents >= 0 ? '+' : ''}'
                      '${reading.targetCents.toStringAsFixed(0)} cents',
            key: const Key('tuner-readout'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Semantics(
            label: 'Tuning scale, minus 20 to plus 20 cents',
            child: LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: (constraints.maxWidth * 0.60).clamp(145.0, 240.0),
                width: double.infinity,
                child: CustomPaint(
                  key: const Key('tuner-cents-dial'),
                  painter: CentsDialPainter(
                    cents: reading?.targetCents,
                    needleColor: color,
                    trackColor: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.35,
                    ),
                    inTuneColor: accent,
                    textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
                  ),
                ),
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('Flat', style: theme.textTheme.labelSmall),
              Text(
                reading == null
                    ? ''
                    : reading.inTune
                    ? 'In tune'
                    : reading.targetCents < 0
                    ? 'Flat'
                    : 'Sharp',
                key: const Key('tuner-intonation'),
                style: theme.textTheme.labelMedium?.copyWith(color: accent),
              ),
              Text('Sharp', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 20),
          if (controller.selectedStringIndex != null)
            TextButton(
              key: const Key('tuner-automatic'),
              onPressed: () => controller.selectString(null),
              child: const Text('Automatic detection'),
            ),
          const SizedBox(height: 12),
          Semantics(
            label:
                '${controller.preset.instrument.label} illustration, ${controller.preset.stringCount} strings',
            child: SizedBox(
              height: 112,
              width: double.infinity,
              child: CustomPaint(
                key: const Key('tuner-instrument-illustration'),
                painter: InstrumentStringPainter(
                  stringCount: controller.preset.notes.length,
                  isBass: controller.preset.instrument == InstrumentType.bass,
                  activeStrings: {
                    for (var i = 0; i < controller.preset.notes.length; i++)
                      if (controller.selectedStringIndex == i ||
                          (controller.selectedStringIndex == null &&
                              reading?.targetNote ==
                                  controller.preset.notes[i]))
                        i,
                  },
                  accent: accent,
                  outline: theme.colorScheme.onSurfaceVariant,
                  surface: theme.brightness == Brightness.dark
                      ? const Color(0xFF17292C)
                      : const Color(0xFFE2EEEA),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final notes = controller.preset.notes;
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (notes.length > 6 ||
                  textScale > 1.3 ||
                  (notes.length != 6 &&
                      notes.length * 54 - 8 > constraints.maxWidth)) {
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < notes.length; index++)
                      _StringBadge(
                        index: index,
                        note: notes[index],
                        active:
                            controller.selectedStringIndex == index ||
                            (controller.selectedStringIndex == null &&
                                reading?.targetNote == notes[index]),
                        color: accent,
                        onTap: () => controller.selectString(index),
                      ),
                  ],
                );
              }
              Widget row(List<String> rowNotes, int start, String key) => Row(
                key: Key(key),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < rowNotes.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    _StringBadge(
                      index: start + index,
                      note: rowNotes[index],
                      active:
                          controller.selectedStringIndex == start + index ||
                          (controller.selectedStringIndex == null &&
                              reading?.targetNote == rowNotes[index]),
                      color: accent,
                      onTap: () => controller.selectString(start + index),
                    ),
                  ],
                ],
              );
              if (notes.length == 6 && constraints.maxWidth < 316) {
                return Column(
                  children: [
                    row(notes.sublist(0, 3), 0, 'tuner-strings-first-row'),
                    const SizedBox(height: 8),
                    row(notes.sublist(3), 3, 'tuner-strings-second-row'),
                  ],
                );
              }
              return row(notes, 0, 'tuner-strings-single-row');
            },
          ),
        ],
      ),
    );
  }
}

class _StringBadge extends StatelessWidget {
  const _StringBadge({
    required this.index,
    required this.note,
    required this.active,
    required this.color,
    required this.onTap,
  });
  final int index;
  final String note;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('tuner-string-$index-$note'),
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width:
            46 *
            (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0),
        height:
            46 *
            (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color.withValues(alpha: 0.18) : null,
          border: Border.all(
            color: active ? color : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(note, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class CentsDialPainter extends CustomPainter {
  CentsDialPainter({
    required this.cents,
    required this.needleColor,
    required this.trackColor,
    required this.inTuneColor,
    this.textScale = 1,
  });
  final double? cents;
  final Color needleColor;
  final Color trackColor;
  final Color inTuneColor;
  final double textScale;

  /// Radians from straight up; values beyond the visible scale stop at its ends.
  static double angleForCents(double cents) =>
      cents.clamp(-20.0, 20.0) / 20 * math.pi / 2;

  static const markerValues = [-20, -10, 0, 10, 20];
  static const double inTuneStart = -math.pi / 8;
  static const double inTuneSweep = math.pi / 4;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height - 20);
    final radius = math.min(size.width / 2 - 28, size.height - 32);
    if (radius <= 0) return;
    final arc = Rect.fromCircle(center: pivot, radius: radius);
    canvas.drawArc(
      arc,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      arc,
      3 * math.pi / 2 + inTuneStart,
      inTuneSweep,
      false,
      Paint()
        ..color = inTuneColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    for (var tick = -20; tick <= 20; tick += 2) {
      final angle = angleForCents(tick.toDouble());
      final direction = Offset(math.sin(angle), -math.cos(angle));
      final length = tick == 0
          ? 14.0
          : tick % 10 == 0
          ? 12.0
          : 8.0;
      final paint = Paint()
        ..color = tick == 0 ? inTuneColor : trackColor
        ..strokeWidth = tick == 0 ? 3 : 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        pivot + direction * (radius - length - 7),
        pivot + direction * (radius - 7),
        paint,
      );
    }
    for (final tick in markerValues) {
      final angle = angleForCents(tick.toDouble());
      final point =
          pivot + Offset(math.sin(angle), -math.cos(angle)) * (radius - 28);
      final label = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(textScale),
        text: TextSpan(
          text: tick > 0 ? '+$tick' : '$tick',
          style: TextStyle(
            fontSize: 11,
            color: tick == 0 ? inTuneColor : needleColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      )..layout();
      label.paint(
        canvas,
        Offset(
          (point.dx - label.width / 2).clamp(
            0.0,
            math.max(0.0, size.width - label.width),
          ),
          (point.dy - label.height / 2).clamp(
            0.0,
            math.max(0.0, size.height - label.height),
          ),
        ),
      );
    }
    final value = cents;
    if (value == null || !value.isFinite) return;
    final angle = angleForCents(value);
    canvas.drawLine(
      pivot,
      pivot + Offset(math.sin(angle), -math.cos(angle)) * (radius - 25),
      Paint()
        ..color = needleColor
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 6, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(CentsDialPainter old) =>
      old.cents != cents ||
      old.needleColor != needleColor ||
      old.trackColor != trackColor ||
      old.inTuneColor != inTuneColor ||
      old.textScale != textScale;
}

/// Original vector instrument silhouette; indices follow the preset's low-to-high order.
class InstrumentStringPainter extends CustomPainter {
  InstrumentStringPainter({
    required this.stringCount,
    required this.isBass,
    required this.activeStrings,
    required this.accent,
    required this.outline,
    required this.surface,
  });
  final int stringCount;
  final bool isBass;
  final Set<int> activeStrings;
  final Color accent, outline, surface;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Path()
      ..moveTo(w * .30, h * .35)
      ..cubicTo(w * .24, h * .03, w * .04, h * .05, w * .04, h * .50)
      ..cubicTo(w * .04, h * .95, w * .24, h * .97, w * .30, h * .65)
      ..lineTo(w * .86, h * .65)
      ..lineTo(w * .95, h * .58)
      ..lineTo(w * .95, h * .42)
      ..lineTo(w * .86, h * .35)
      ..close();
    canvas.drawPath(body, Paint()..color = surface);
    canvas.drawPath(
      body,
      Paint()
        ..color = outline.withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      Offset(w * .18, h * .5),
      h * (isBass ? .11 : .14),
      Paint()..color = outline.withValues(alpha: .25),
    );
    for (var fret = 0; fret < 7; fret++) {
      final x = w * (.38 + fret * .065);
      canvas.drawLine(
        Offset(x, h * .35),
        Offset(x, h * .65),
        Paint()
          ..color = outline.withValues(alpha: .35)
          ..strokeWidth = 1,
      );
    }
    for (var i = 0; i < stringCount; i++) {
      final y =
          h * .39 + h * .22 * (stringCount <= 1 ? .5 : i / (stringCount - 1));
      final active = activeStrings.contains(i);
      canvas.drawLine(
        Offset(w * .13, y),
        Offset(w * .93, y),
        Paint()
          ..color = active ? accent : outline.withValues(alpha: .55)
          ..strokeWidth = active ? 2.5 : 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(InstrumentStringPainter old) =>
      old.stringCount != stringCount ||
      old.isBass != isBass ||
      old.accent != accent ||
      old.outline != outline ||
      old.surface != surface ||
      old.activeStrings.length != activeStrings.length ||
      !old.activeStrings.containsAll(activeStrings);
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.controller});
  final TunerController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final (icon, text) = switch (status) {
      TunerStatus.noMicrophone => (
        Icons.mic_off,
        'No microphone was found on this device. Connect a microphone or '
            'headset and try again.',
      ),
      TunerStatus.permissionDenied => (
        Icons.lock_outline,
        'Microphone access is turned off. Allow it for RiffShelf in your '
            'device settings, then try again.',
      ),
      TunerStatus.error => (
        Icons.error_outline,
        'The microphone could not be started. Please try again.',
      ),
      TunerStatus.idle => (
        Icons.mic_none,
        'Tap Start, then play one string at a time.',
      ),
      _ => (null, null),
    };
    if (icon == null || text == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isProblem = status != TunerStatus.idle;
    return Row(
      key: const Key('tuner-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: isProblem
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.controller});
  final TunerController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    if (status == TunerStatus.starting) {
      return const FilledButton(onPressed: null, child: Text('Starting…'));
    }
    if (status == TunerStatus.listening) {
      return OutlinedButton.icon(
        onPressed: controller.stop,
        icon: const Icon(Icons.stop),
        label: const Text('Stop'),
      );
    }
    final idle = status == TunerStatus.idle;
    return FilledButton.icon(
      onPressed: controller.start,
      icon: Icon(idle ? Icons.mic : Icons.refresh),
      label: Text(idle ? 'Start tuning' : 'Try again'),
    );
  }
}
