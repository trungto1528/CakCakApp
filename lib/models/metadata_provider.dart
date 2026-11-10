import 'dart:convert';

import 'package:flutter/material.dart';

enum MetadataProvider {
  comick,
  mangaDex,
}

extension MetadataProviderDisplay on MetadataProvider {
  String get label {
    switch (this) {
      case MetadataProvider.comick:
        return 'Comick';
      case MetadataProvider.mangaDex:
        return 'MangaDex';
    }
  }

  String get value {
    switch (this) {
      case MetadataProvider.comick:
        return 'COMICK';
      case MetadataProvider.mangaDex:
        return 'MANGADEX';
    }
  }

  Color get badgeColor {
    switch (this) {
      case MetadataProvider.comick:
        return const Color(0xFFEF6C00);
      case MetadataProvider.mangaDex:
        return const Color(0xFF1976D2);
    }
  }

  static MetadataProvider? fromValue(String? value) {
    final normalized = (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    switch (normalized) {
      case 'comick':
      case 'ck':
        return MetadataProvider.comick;
      case 'mangadex':
      case 'md':
        return MetadataProvider.mangaDex;
      default:
        return null;
    }
  }
}

/// Thông tin metadata Chuẩn hoá từ một provider
/// để UI hiển thị đồng nhất và dễ dàng đổi/provider fallback.
class MetadataInfo {
  final MetadataProvider provider;
  final String providerId;
  final String title;
  final String englishTitle;
  final String japaneseTitle;
  final String synonyms;
  final Map<String, String> allTitles;
  final String cover;
  final String synopsis;
  final String authors;
  final String type;
  final String status;
  final List<String> genres;
  final String url;
  final Map<String, dynamic> raw;

  const MetadataInfo({
    required this.provider,
    required this.providerId,
    this.title = '',
    this.englishTitle = '',
    this.japaneseTitle = '',
    this.synonyms = '',
    this.allTitles = const {},
    this.cover = '',
    this.synopsis = '',
    this.authors = '',
    this.type = '',
    this.status = '',
    this.genres = const [],
    this.url = '',
    this.raw = const {},
  });

  factory MetadataInfo.fromMangaDex(Map<String, dynamic> raw) {
    return MetadataInfo.fromMetadata(
      raw,
      fallbackProvider: MetadataProvider.mangaDex,
    );
  }

  factory MetadataInfo.fromMetadata(
    Map<String, dynamic> raw, {
    MetadataProvider? fallbackProvider,
  }) {
    final provider = MetadataProviderDisplay.fromValue(
          _asString(
            raw['metadataProvider'] ??
                raw['provider'] ??
                raw['providerLabel'],
          ),
        ) ??
        fallbackProvider ??
        MetadataProvider.mangaDex;

    return MetadataInfo(
      provider: provider,
      providerId: _asString(
        raw['metadataId'] ??
            raw['providerId'] ??
            raw['mangaDexId'] ??
            raw['id'],
      ),
      title: _asString(raw['title']),
      englishTitle: _asString(raw['englishTitle']),
      japaneseTitle: _asString(raw['japaneseTitle']),
      synonyms: _asString(raw['synonyms']),
      allTitles: _asStringMap(raw['allTitles']),
      cover: _asString(raw['cover']),
      synopsis: _asString(raw['synopsis']),
      authors: _asString(raw['authors']),
      type: _asString(raw['type']),
      status: _asString(raw['status']),
      genres: _asStringList(raw['genres']),
      url: _asString(raw['url'] ?? raw['providerUrl']),
      raw: Map<String, dynamic>.from(raw),
    );
  }

  static String _asString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  static List<String> _asStringList(dynamic v) {
    if (v == null) return const [];
    if (v is List) {
      return v.whereType<String>().toList();
    }
    return const [];
  }

  static Map<String, String> _asStringMap(dynamic v) {
    if (v == null) return const {};
    if (v is Map) {
      final map = <String, String>{};
      v.forEach((k, val) {
        map[k.toString()] =
            val is List ? val.join(' | ') : val.toString();
      });
      return map;
    }
    if (v is String) {
      if (v.isEmpty) return const {};
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) {
          final map = <String, String>{};
          decoded.forEach((k, val) {
            map[k.toString()] =
                val is List ? val.join(' | ') : val.toString();
          });
          return map;
        }
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }
}
