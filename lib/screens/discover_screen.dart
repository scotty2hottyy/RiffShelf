import 'package:flutter/material.dart';

import '../core/database/sqlite_tab_repository.dart';
import '../core/database/tab_repository.dart';
import '../core/models/instrument_type.dart';
import '../core/models/saved_tab.dart';
import '../features/search/application/tab_search_service.dart';
import '../features/search/data/backend_tab_search_client.dart';
import '../features/search/data/songsterr_provider.dart';
import '../features/search/domain/tab_source_provider.dart';
import '../features/tabs/tab_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.service, this.repository});
  final TabSearchService? service;
  final TabRepository? repository;
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const apiBaseUrl = String.fromEnvironment('RIFFSHELF_API_BASE_URL');
  late final service =
      widget.service ??
      TabSearchService(
        [SongsterrProvider()],
        searchProvider: apiBaseUrl.trim().isEmpty
            ? null
            : BackendTabSearchClient(baseUrl: apiBaseUrl),
      );
  late final repository = widget.repository ?? SqliteTabRepository.local();
  final query = TextEditingController();
  InstrumentType? instrument;
  CombinedSearchResponse? response;
  bool loading = false;
  String? error;
  TabSearchResult? failedResult;
  int generation = 0;

  @override
  void dispose() {
    query.dispose();
    if (widget.repository == null) repository.close();
    super.dispose();
  }

  Future<void> search() async {
    if (query.text.trim().isEmpty) return;
    failedResult = null;
    final current = ++generation;
    setState(() {
      loading = true;
      error = null;
      response = null;
    });
    final result = await service.search(
      TabSearchQuery(text: query.text, instrument: instrument),
    );
    if (!mounted || current != generation) return;
    setState(() {
      loading = false;
      response = result;
      if (result.results.isEmpty && result.failures.isNotEmpty) {
        error = result.failures
            .map((f) => '${f.provider}: ${f.error}')
            .join('\n');
      }
    });
  }

  Future<void> openResult(TabSearchResult result) async {
    setState(() {
      loading = true;
      error = null;
      failedResult = result;
    });
    try {
      SavedTab tab;
      try {
        tab = await service.fetch(result);
      } on TabTrackSelectionException catch (selection) {
        if (!mounted) return;
        setState(() => loading = false);
        final track = await showDialog<TabTrackOption>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Choose an arrangement'),
            children: [
              for (final option in selection.options)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, option),
                  child: Text(
                    [
                      option.name,
                      option.instrument,
                      if (option.tuning.isNotEmpty) option.tuning.join(' '),
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        );
        if (track == null || !mounted) return;
        setState(() => loading = true);
        tab = await service.fetch(result, track);
      }
      if (!mounted) return;
      setState(() => loading = false);
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => _PreviewScreen(tab: tab, repository: repository),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is TabProviderException
              ? e.toString()
              : 'Could not load this arrangement. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => search(),
              decoration: const InputDecoration(
                labelText: 'Song or artist',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<InstrumentType?>(
                    isExpanded: true,
                    initialValue: instrument,
                    decoration: const InputDecoration(labelText: 'Instrument'),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Guitar and bass'),
                      ),
                      DropdownMenuItem(
                        value: InstrumentType.guitar,
                        child: Text('Guitar'),
                      ),
                      DropdownMenuItem(
                        value: InstrumentType.bass,
                        child: Text('Bass'),
                      ),
                    ],
                    onChanged: (value) => setState(() => instrument = value),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: loading ? null : search,
                  child: const Text('Search'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(error!),
              TextButton(
                onPressed: () =>
                    failedResult == null ? search() : openResult(failedResult!),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      if (response != null &&
          response!.results.isEmpty &&
          error == null &&
          !loading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No results found.'),
        ),
      if (response != null &&
          response!.results.isNotEmpty &&
          response!.failures.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Some providers are unavailable: ${response!.failures.map((f) => f.provider).join(', ')}',
          ),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: response?.results.length ?? 0,
          itemBuilder: (context, index) {
            final result = response!.results[index];
            return ListTile(
              title: Text(result.title),
              subtitle: Text(
                [
                  result.artist,
                  result.instrument.label,
                  result.sourceName,
                  if (result.tuning?.isNotEmpty == true)
                    result.tuning!.join(' '),
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: loading ? null : () => openResult(result),
            );
          },
        ),
      ),
    ],
  );
}

class _PreviewScreen extends StatefulWidget {
  const _PreviewScreen({required this.tab, required this.repository});
  final SavedTab tab;
  final TabRepository repository;
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  bool saving = false;
  bool saved = false;
  Future<void> save() async {
    setState(() => saving = true);
    try {
      await widget.repository.save(widget.tab);
      if (mounted) setState(() => saved = true);
    } on DuplicateTabException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This arrangement is already in your library.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this tab.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TabDetailScreen(tab: widget.tab),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: saving || saved ? null : save,
          icon: const Icon(Icons.download),
          label: Text(saved ? 'Saved to Library' : 'Save to Library'),
        ),
      ),
    ),
  );
}
