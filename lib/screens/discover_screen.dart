import 'package:flutter/material.dart';

import '../core/database/sqlite_tab_repository.dart';
import '../core/database/tab_repository.dart';
import '../core/models/instrument_type.dart';
import '../core/models/saved_tab.dart';
import '../features/artwork/album_art.dart';
import '../features/artwork/artwork_service.dart';
import '../features/search/application/tab_search_service.dart';
import '../features/search/data/backend_tab_search_client.dart';
import '../features/search/data/songsterr_provider.dart';
import '../features/search/domain/tab_source_provider.dart';
import '../features/tabs/tab_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    this.service,
    this.repository,
    this.artworkService,
  });
  final TabSearchService? service;
  final TabRepository? repository;
  final ArtworkService? artworkService;
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
  List<SavedTab> savedTabs = const [];

  Future<void> refreshArtwork() async {
    try {
      final tabs = await repository.findTabs();
      if (mounted) setState(() => savedTabs = tabs);
    } catch (_) {
      // Artwork is optional; a storage failure must not block discovery.
    }
  }

  SavedTab artworkFor(TabSearchResult result) {
    final matches = savedTabs
        .where(
          (tab) =>
              tab.source == result.sourceName &&
              tab.sourceId == result.externalId &&
              tab.artwork != null,
        )
        .toList();
    if (matches.isNotEmpty &&
        matches.every((tab) => tab.artwork == matches.first.artwork)) {
      return matches.first;
    }
    return SavedTab(
      title: result.title,
      artist: result.artist,
      source: result.sourceName,
      sourceUrl: result.sourceUrl,
      instrument: result.instrument,
      stringCount: 1,
      tuning: const [],
    );
  }

  @override
  void initState() {
    super.initState();
    refreshArtwork();
    if (repository is SqliteTabRepository) {
      SqliteTabRepository.changes.addListener(refreshArtwork);
    }
  }

  @override
  void dispose() {
    if (repository is SqliteTabRepository) {
      SqliteTabRepository.changes.removeListener(refreshArtwork);
    }
    query.dispose();
    if (widget.repository == null) repository.close();
    super.dispose();
  }

  Future<void> search() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (query.text.trim().isEmpty) return;
    refreshArtwork();
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
          builder: (_) => _PreviewScreen(
            tab: tab,
            repository: repository,
            artworkService: widget.artworkService,
          ),
        ),
      );
      await refreshArtwork();
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF54E8D5) : const Color(0xFF006C65);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        TextField(
          controller: query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => search(),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            labelText: 'Song or artist',
            hintText: 'Search songs, artists, or riffs',
            prefixIcon: Icon(Icons.search_rounded, color: accent),
            filled: true,
            fillColor: dark ? const Color(0xFF101D20) : Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final filter = DropdownButtonFormField<InstrumentType?>(
              isExpanded: true,
              initialValue: instrument,
              decoration: InputDecoration(
                labelText: 'Instrument',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Guitar and bass')),
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
            );
            final button = FilledButton.icon(
              onPressed: loading ? null : search,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: dark ? const Color(0xFF052723) : Colors.white,
                minimumSize: const Size(112, 56),
              ),
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            );
            if (constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [filter, const SizedBox(height: 10), button],
              );
            }
            return Row(
              children: [
                Expanded(child: filter),
                const SizedBox(width: 12),
                button,
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFD89635), size: 21),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Discover Tabs',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'FIND YOUR NEXT SONG',
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        if (loading) ...[
          LinearProgressIndicator(
            color: accent,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            failedResult == null
                ? 'Searching for tabs…'
                : 'Loading arrangement…',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
        ],
        if (error != null)
          _DiscoverMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load tabs',
            message: error!,
            action: TextButton(
              onPressed: () =>
                  failedResult == null ? search() : openResult(failedResult!),
              child: const Text('Retry'),
            ),
          )
        else if (response != null && response!.results.isEmpty && !loading)
          const _DiscoverMessage(
            icon: Icons.search_off,
            title: 'No results found.',
            message: 'Try another song or artist.',
          )
        else if (response == null && !loading)
          const _DiscoverMessage(
            icon: Icons.library_music_outlined,
            title: 'Find a song to play',
            message: 'Search for a song or artist to explore available tabs.',
          ),
        if (response != null &&
            response!.results.isNotEmpty &&
            response!.failures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Some providers are unavailable: ${response!.failures.map((f) => f.provider).join(', ')}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                TextButton(
                  onPressed: loading ? null : search,
                  child: const Text('Retry providers'),
                ),
              ],
            ),
          ),
        if (response != null)
          for (final result in response!.results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SongCard(
                result: result,
                artwork: artworkFor(result),
                accent: accent,
                onOpen: loading ? null : () => openResult(result),
              ),
            ),
      ],
    );
  }
}

class _DiscoverMessage extends StatelessWidget {
  const _DiscoverMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.result,
    required this.artwork,
    required this.accent,
    required this.onOpen,
  });
  final TabSearchResult result;
  final SavedTab artwork;
  final Color accent;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Material(
      color: dark ? const Color(0xFF101B1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: dark
              ? const Color(0xFF304247)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AlbumArt(tab: artwork, size: 70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.artist,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          result.instrument.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (result.tuning?.isNotEmpty == true)
                          Text(
                            result.tuning!.join(' '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            result.sourceName,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onOpen,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            side: BorderSide(color: accent),
                            minimumSize: const Size(48, 48),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewScreen extends StatefulWidget {
  const _PreviewScreen({
    required this.tab,
    required this.repository,
    this.artworkService,
  });
  final SavedTab tab;
  final TabRepository repository;
  final ArtworkService? artworkService;
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  late SavedTab shown = widget.tab;
  bool saving = false;
  bool saved = false;
  Future<void> save() async {
    setState(() => saving = true);
    try {
      final savedTab = await widget.repository.save(widget.tab);
      ArtworkService.scheduleAutomatic(
        widget.repository,
        savedTab,
        service: widget.artworkService,
      );
      if (mounted) {
        setState(() {
          saved = true;
          shown = savedTab;
        });
      }
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
          SnackBar(
            content: const Text('Could not save this tab. Please try again.'),
            action: SnackBarAction(label: 'Retry', onPressed: save),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TabDetailScreen(
      key: ValueKey('preview-${shown.id}'),
      tab: shown,
      repository: saved ? widget.repository : null,
      artworkService: widget.artworkService,
    ),
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
