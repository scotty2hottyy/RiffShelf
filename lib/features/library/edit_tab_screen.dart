import 'package:flutter/material.dart';

import '../../core/database/tab_repository.dart';
import '../../core/models/instrument_type.dart';
import '../../core/models/saved_tab.dart';

class EditTabScreen extends StatefulWidget {
  const EditTabScreen({super.key, required this.tab, required this.repository});
  final SavedTab tab;
  final TabRepository repository;
  @override
  State<EditTabScreen> createState() => _EditTabScreenState();
}

class _EditTabScreenState extends State<EditTabScreen> {
  late final title = TextEditingController(text: widget.tab.title);
  late final artist = TextEditingController(text: widget.tab.artist);
  late final tuning = TextEditingController(text: widget.tab.tuning.join(' '));
  late final tags = TextEditingController(text: widget.tab.tags.join(', '));
  late InstrumentType instrument = widget.tab.instrument;
  late InstrumentClassification classification = widget.tab.classification;
  bool saving = false;
  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    tuning.dispose();
    tags.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final notes = tuning.text.trim().split(RegExp(r'[\s,]+'));
    final pattern = RegExp(
      r'^(?:[A-G](?:#|b)?-?\d*|\?)$',
      caseSensitive: false,
    );
    if (title.text.trim().isEmpty ||
        notes.length != widget.tab.stringCount ||
        !notes.every(pattern.hasMatch)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter a title and ${widget.tab.stringCount} tuning notes (use ? for unknown).',
          ),
        ),
      );
      return;
    }
    final uniqueTags = <String, String>{};
    for (final raw in tags.text.split(',')) {
      final value = raw.trim();
      if (value.isNotEmpty) {
        uniqueTags.putIfAbsent(value.toLowerCase(), () => value);
      }
    }
    setState(() => saving = true);
    try {
      await widget.repository.save(
        widget.tab.withMetadata(
          title: title.text.trim(),
          artist: artist.text.trim(),
          instrument: instrument,
          classification: classification,
          tuning: notes,
          capo: widget.tab.capo,
          bpm: widget.tab.bpm,
          tags: uniqueTags.values.toList(),
          trackName: widget.tab.trackName,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save changes.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit tab details')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        TextField(
          controller: artist,
          decoration: const InputDecoration(labelText: 'Artist'),
        ),
        DropdownButtonFormField<InstrumentType>(
          initialValue: instrument,
          decoration: const InputDecoration(labelText: 'Instrument'),
          items: InstrumentType.values
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(
                    v == InstrumentType.other ? 'Unknown / other' : v.label,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => instrument = v ?? instrument),
        ),
        DropdownButtonFormField<InstrumentClassification>(
          initialValue: classification,
          decoration: const InputDecoration(labelText: 'Classification'),
          items: const [
            DropdownMenuItem(
              value: InstrumentClassification.other,
              child: Text('Unknown / other'),
            ),
            DropdownMenuItem(
              value: InstrumentClassification.acoustic,
              child: Text('Acoustic'),
            ),
            DropdownMenuItem(
              value: InstrumentClassification.electric,
              child: Text('Electric'),
            ),
          ],
          onChanged: (v) =>
              setState(() => classification = v ?? classification),
        ),
        TextField(
          controller: tuning,
          decoration: InputDecoration(
            labelText: 'Tuning, low to high',
            helperText: '${widget.tab.stringCount} notes; use ? for unknown',
          ),
        ),
        TextField(
          controller: tags,
          decoration: const InputDecoration(
            labelText: 'Tags',
            helperText: 'Separate tags with commas',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Save changes'),
        ),
      ],
    ),
  );
}
