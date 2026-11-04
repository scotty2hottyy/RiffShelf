import 'package:flutter/material.dart';

import '../core/models/tuning.dart';
import '../features/tuner/audio_input.dart';
import '../features/tuner/tuner_controller.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key, this.inputFactory, this.preset});

  /// A fixed arrangement tuning; null keeps the standalone preset picker.
  final TuningPreset? preset;

  /// Overrides the microphone source (used by tests).
  final TunerAudioInput Function()? inputFactory;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver {
  late final TunerController _controller = TunerController(
    input: (widget.inputFactory ?? RecordAudioInput.new)(),
  )..preset = widget.preset ?? TunerPresets.guitarStandard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
                  _PresetPicker(controller: _controller)
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
  const _PresetPicker({required this.controller});
  final TunerController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in TunerPresets.all)
          ChoiceChip(
            label: Text(preset.name),
            selected: identical(preset, controller.preset),
            onSelected: (_) => controller.preset = preset,
          ),
      ],
    );
  }
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({required this.controller});
  final TunerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = controller.reading;
    final accent = theme.colorScheme.primary;
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            reading?.targetNote ?? '--',
            key: const Key('tuner-target-note'),
            style: theme.textTheme.displayLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            reading == null
                ? 'Play a string'
                : '${reading.frequency.toStringAsFixed(1)} Hz · '
                      '${reading.targetCents >= 0 ? '+' : ''}'
                      '${reading.targetCents.toStringAsFixed(0)} cents',
            key: const Key('tuner-readout'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(
              painter: _CentsPainter(
                cents: reading?.targetCents,
                color: color,
                trackColor: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.35,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Flat', style: theme.textTheme.labelSmall),
              Text(
                reading?.inTune == true ? 'In tune' : '',
                style: theme.textTheme.labelMedium?.copyWith(color: accent),
              ),
              Text('Sharp', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final notes = controller.preset.notes;
              if (notes.length > 6) {
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final note in notes)
                      _StringBadge(
                        note: note,
                        active: reading?.targetNote == note,
                        color: color,
                      ),
                  ],
                );
              }
              Widget row(List<String> rowNotes, String key) => Row(
                key: Key(key),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < rowNotes.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    _StringBadge(
                      note: rowNotes[index],
                      active: reading?.targetNote == rowNotes[index],
                      color: color,
                    ),
                  ],
                ],
              );
              if (notes.length == 6 && constraints.maxWidth < 316) {
                return Column(
                  children: [
                    row(notes.sublist(0, 3), 'tuner-strings-first-row'),
                    const SizedBox(height: 8),
                    row(notes.sublist(3), 'tuner-strings-second-row'),
                  ],
                );
              }
              return row(notes, 'tuner-strings-single-row');
            },
          ),
        ],
      ),
    );
  }
}

class _StringBadge extends StatelessWidget {
  const _StringBadge({
    required this.note,
    required this.active,
    required this.color,
  });
  final String note;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color.withValues(alpha: 0.18) : null,
        border: Border.all(
          color: active ? color : Theme.of(context).dividerColor,
        ),
      ),
      child: Text(note, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _CentsPainter extends CustomPainter {
  _CentsPainter({
    required this.cents,
    required this.color,
    required this.trackColor,
  });
  final double? cents;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = trackColor
      ..strokeWidth = 2;
    final midY = size.height / 2;
    final halfWidth = size.width / 2 - 4;
    for (var i = -5; i <= 5; i++) {
      final x = size.width / 2 + i * halfWidth / 5;
      final h = i == 0 ? 22.0 : (i.isEven ? 12.0 : 7.0);
      canvas.drawLine(Offset(x, midY - h), Offset(x, midY + h), track);
    }
    final value = cents;
    if (value == null) return;
    final x = size.width / 2 + (value.clamp(-50.0, 50.0) / 50) * halfWidth;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CentsPainter old) =>
      old.cents != cents || old.color != color;
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
