import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/models/instrument_type.dart';
import '../domain/tab_source_provider.dart';

/// The backend supplies search metadata. SongsterrProvider still downloads tabs.
class BackendTabSearchClient implements TabSearchProvider {
  BackendTabSearchClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
    bool? requireHttps,
  }) : _client = client ?? http.Client(),
       requireHttps = requireHttps ?? kReleaseMode;

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  final bool requireHttps;

  Uri _endpoint(String query) {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'https' && !(base.scheme == 'http' && !requireHttps)) ||
        base.userInfo.isNotEmpty ||
        base.query.isNotEmpty ||
        base.fragment.isNotEmpty ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw const TabProviderException(
        'Backend URL is invalid. Configure a valid HTTPS API origin.',
        kind: TabProviderErrorKind.network,
      );
    }
    return base.replace(
      path: '/api/v1/search/tabs',
      queryParameters: {'q': query},
    );
  }

  @override
  Future<List<TabSearchResult>> search(TabSearchQuery query) async {
    final endpoint = _endpoint(query.text.trim());
    http.Response response;
    try {
      final request = http.Request('GET', endpoint)..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
    } on TimeoutException {
      throw const TabProviderException(
        'Backend search timed out. Check your connection and retry.',
        kind: TabProviderErrorKind.timeout,
      );
    } on Object {
      throw const TabProviderException(
        'Could not connect to the search backend. Check your connection and retry.',
        kind: TabProviderErrorKind.network,
      );
    }
    if (response.statusCode != 200) {
      final message = switch (response.statusCode) {
        429 => 'Too many searches. Wait a minute and retry.',
        504 => 'Songsterr search timed out. Retry shortly.',
        502 => 'Songsterr search is temporarily unavailable. Retry shortly.',
        422 => 'Enter a song or artist (up to 120 characters).',
        _ =>
          'Backend search failed (HTTP ${response.statusCode}). Retry shortly.',
      };
      throw TabProviderException(message, kind: TabProviderErrorKind.http);
    }
    try {
      return parseResponse(response.body);
    } on FormatException {
      throw const TabProviderException(
        'Backend returned invalid search data. Retry shortly.',
        kind: TabProviderErrorKind.malformed,
      );
    }
  }

  static List<TabSearchResult> parseResponse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const FormatException('Invalid JSON');
    }
    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      throw const FormatException('Missing results');
    }
    return (decoded['results'] as List)
        .map((raw) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('Invalid result');
          }
          String requiredString(String key) {
            final value = raw[key];
            if (value is! String || value.trim().isEmpty) {
              throw FormatException('Missing $key');
            }
            return value;
          }

          final source = requiredString('source');
          final id = requiredString('source_id');
          final sourceUrl = requiredString('source_url');
          final instrumentName = requiredString('instrument');
          final url = Uri.tryParse(sourceUrl);
          if (source != 'Songsterr' ||
              !RegExp(r'^[0-9]+$').hasMatch(id) ||
              url == null ||
              url.scheme != 'https' ||
              url.host != 'www.songsterr.com' ||
              (instrumentName != 'guitar' && instrumentName != 'bass')) {
            throw const FormatException('Unsupported search result');
          }
          List<String>? tuning(Object? value) {
            if (value == null) return null;
            if (value is! List ||
                value.isEmpty ||
                value.any((note) => note is! String || note.isEmpty)) {
              throw const FormatException('Invalid tuning');
            }
            return List<String>.unmodifiable(value.cast<String>());
          }

          final rawArrangements = raw['available_arrangements'];
          if (rawArrangements is! List) {
            throw const FormatException('Missing arrangements');
          }
          final arrangements = rawArrangements
              .map((item) {
                if (item is! Map<String, dynamic> ||
                    (item['name'] != null && item['name'] is! String)) {
                  throw const FormatException('Invalid arrangement');
                }
                return TabArrangement(
                  name: item['name'] as String?,
                  tuning: tuning(item['tuning']),
                );
              })
              .toList(growable: false);
          final instrument = instrumentName == 'guitar'
              ? InstrumentType.guitar
              : InstrumentType.bass;
          final knownTuning = tuning(raw['tuning']);
          return TabSearchResult(
            externalId: id,
            title: requiredString('title'),
            artist: requiredString('artist'),
            sourceName: source,
            sourceUrl: sourceUrl,
            instrument: instrument,
            availableArrangements: arrangements,
            tuning: knownTuning,
            stringCount: knownTuning?.length,
            // The search API does not claim an arrangement file format.
            type: TabType.other,
          );
        })
        .toList(growable: false);
  }
}
