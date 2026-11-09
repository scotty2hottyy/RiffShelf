import 'package:flutter/material.dart';

import '../../core/models/saved_tab.dart';

class StructuredTabViewer extends StatefulWidget {
  const StructuredTabViewer({
    required this.tab,
    this.activeMeasure = 0,
    this.activeBeat = 0,
    this.scale = 1,
    super.key,
  });
  final SavedTab tab;
  final int activeMeasure;
  final int activeBeat;
  final double scale;

  @override
  State<StructuredTabViewer> createState() => _StructuredTabViewerState();
}

class _StructuredTabViewerState extends State<StructuredTabViewer> {
  static const measureWidth = 260.0;
  final _controller = ScrollController();

  double get _textScale => (MediaQuery.textScalerOf(context).scale(14) / 14)
      .clamp(1.0, double.infinity);
  double get _measureWidth => measureWidth * widget.scale * _textScale;

  @override
  void didUpdateWidget(covariant StructuredTabViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeMeasure != widget.activeMeasure &&
        _controller.hasClients) {
      _controller.animateTo(
        (widget.activeMeasure * _measureWidth).clamp(
          0,
          _controller.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: ValueKey('structured-${widget.tab.stringCount}-strings'),
    controller: _controller,
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < widget.tab.measures.length; index++)
          _MeasureView(
            tab: widget.tab,
            measureIndex: index,
            activeBeat: index == widget.activeMeasure
                ? widget.activeBeat
                : null,
            scale: widget.scale,
            textScale: _textScale,
          ),
      ],
    ),
  );
}

class _MeasureView extends StatelessWidget {
  const _MeasureView({
    required this.tab,
    required this.measureIndex,
    this.activeBeat,
    required this.scale,
    required this.textScale,
  });
  final SavedTab tab;
  final int measureIndex;
  final int? activeBeat;
  final double scale, textScale;

  @override
  Widget build(BuildContext context) {
    final measure = tab.measures[measureIndex];
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF54E8D5) : const Color(0xFF006C65);
    final unit = scale * textScale;
    final width = _StructuredTabViewerState.measureWidth * unit;
    final spacing = 36.0 * unit;
    final top = 48.0 * unit;
    final height = top + (tab.stringCount - 1) * spacing + 28 * unit;
    final noteWidth = 36.0 * unit;
    final start = 52.0 * unit;
    final end = width - 24 * unit;
    return Semantics(
      label: 'Measure ${measure.number}, ${measure.beats.length} beats',
      child: Container(
        key: ValueKey('measure-${measure.number}'),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: dark
              ? const Color(0xFF101B1E)
              : theme.colorScheme.surfaceContainerLow,
          border: Border(
            left: BorderSide(color: theme.colorScheme.outline, width: 1.3),
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 10 * unit,
              top: 7 * unit,
              child: Text(
                '${measure.number}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (
              var stringIndex = 0;
              stringIndex < tab.stringCount;
              stringIndex++
            ) ...[
              Positioned(
                top: top + stringIndex * spacing,
                left: 0,
                child: SizedBox(
                  key: ValueKey('string-${measure.number}-${stringIndex + 1}'),
                  width: width,
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              Positioned(
                left: 2 * unit,
                top: top + stringIndex * spacing - 14 * unit,
                child: SizedBox(
                  width: 36 * unit,
                  height: 28 * unit,
                  child: Center(
                    child: Text(
                      stringIndex < tab.tuning.length
                          ? tab.tuning.reversed.elementAt(stringIndex)
                          : '?',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize:
                            (theme.textTheme.labelMedium?.fontSize ?? 12) *
                            scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            for (
              var beatIndex = 0;
              beatIndex < measure.beats.length;
              beatIndex++
            )
              ...measure.beats[beatIndex].notes
                  .where((note) => note.stringNumber <= tab.stringCount)
                  .map((note) {
                    final x =
                        start +
                        (measure.beats[beatIndex].position /
                                (measure.numerator * 4 / measure.denominator)) *
                            (end - start);
                    final active = activeBeat == beatIndex;
                    return Positioned(
                      left: x.clamp(start, end) - noteWidth / 2,
                      top: top + (note.stringNumber - 1) * spacing - 15 * unit,
                      child: SizedBox(
                        width: noteWidth,
                        height: 30 * unit,
                        child: DecoratedBox(
                          key: ValueKey(
                            'note-$measureIndex-$beatIndex-${note.stringNumber}',
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? accent
                                : (dark
                                      ? const Color(0xFF15262A)
                                      : theme.colorScheme.surface),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: active
                                  ? accent
                                  : theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${note.fret}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize:
                                    (theme.textTheme.titleSmall?.fontSize ??
                                        14) *
                                    scale,
                                fontWeight: FontWeight.w700,
                                color: active
                                    ? (dark
                                          ? const Color(0xFF052723)
                                          : Colors.white)
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
          ],
        ),
      ),
    );
  }
}
