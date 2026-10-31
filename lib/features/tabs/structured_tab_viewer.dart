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

  @override
  void didUpdateWidget(covariant StructuredTabViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeMeasure != widget.activeMeasure &&
        _controller.hasClients) {
      _controller.animateTo(
        (widget.activeMeasure * measureWidth * widget.scale).clamp(
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
  });
  final SavedTab tab;
  final int measureIndex;
  final int? activeBeat;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final measure = tab.measures[measureIndex];
    final width = _StructuredTabViewerState.measureWidth * scale;
    final spacing = 28.0 * scale;
    final height = 34 + tab.stringCount * spacing;
    return Semantics(
      label: 'Measure ${measure.number}, ${measure.beats.length} beats',
      child: Container(
        key: ValueKey('measure-${measure.number}'),
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        child: Stack(
          children: [
            Positioned(left: 8, top: 4, child: Text('${measure.number}')),
            for (
              var stringIndex = 0;
              stringIndex < tab.stringCount;
              stringIndex++
            ) ...[
              Positioned(
                top: 34 + stringIndex * spacing,
                left: 0,
                child: SizedBox(
                  key: ValueKey('string-${measure.number}-${stringIndex + 1}'),
                  width: width,
                  child: const Divider(height: 1, thickness: 1),
                ),
              ),
              Positioned(
                left: 5,
                top: 23 + stringIndex * spacing,
                child: Text(
                  tab.tuning.reversed.elementAt(stringIndex),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
            for (
              var beatIndex = 0;
              beatIndex < measure.beats.length;
              beatIndex++
            )
              ...measure.beats[beatIndex].notes.map((note) {
                final x =
                    30 +
                    (measure.beats[beatIndex].position /
                            (measure.numerator * 4 / measure.denominator)) *
                        (width - 45);
                return Positioned(
                  left: x.clamp(28, width - 24),
                  top: 22 + (note.stringNumber - 1) * spacing,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: activeBeat == beatIndex
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        '${note.fret}',
                        style: const TextStyle(fontFamily: 'monospace'),
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
