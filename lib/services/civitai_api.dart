import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sdxl_collector/models/civitai_image.dart';

class CivitaiPage {
  const CivitaiPage({required this.items, required this.nextPageToken});

  final List<CivitaiImage> items;

  /// Either a cursor from the current API or a full nextPage URL from the
  /// older page-based API.
  final String? nextPageToken;
}

class CivitaiApiException implements Exception {
  const CivitaiApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class CivitaiApi {
  CivitaiApi({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _endpoint = Uri.https('civitai.com', '/api/v1/images');
  final http.Client _client;

  Future<CivitaiPage> fetchImages({
    String? pageToken,
    int limit = 50,
  }) async {
    final uri = _buildRequestUri(pageToken: pageToken, limit: limit);

    late final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const <String, String>{
          'Accept': 'application/json',
          'User-Agent': 'SDXL-Collector/1.1',
        },
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const CivitaiApiException(
        'Civitai не ответил вовремя. Проверьте соединение и повторите попытку.',
      );
    } on http.ClientException catch (error) {
      throw CivitaiApiException('Ошибка сети: ${error.message}');
    }

    if (response.statusCode != 200) {
      final message = switch (response.statusCode) {
        429 => 'Civitai временно ограничил число запросов. Повторите позже.',
        >= 500 => 'Сервис Civitai временно недоступен.',
        401 || 403 => 'Civitai отклонил запрос к публичной ленте.',
        _ => 'Civitai вернул HTTP ${response.statusCode}.',
      };
      throw CivitaiApiException(message, statusCode: response.statusCode);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const CivitaiApiException('Civitai вернул некорректный JSON.');
    }

    if (decoded is! Map) {
      throw const CivitaiApiException('Неожиданный формат ответа Civitai.');
    }

    final data = Map<String, dynamic>.from(decoded);
    final rawItems = data['items'];
    final items = <CivitaiImage>[];

    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        try {
          items.add(CivitaiImage.fromJson(Map<String, dynamic>.from(rawItem)));
        } on FormatException {
          // Public API occasionally returns entries without usable prompts.
        }
      }
    }

    final rawMetadata = data['metadata'];
    final metadata = rawMetadata is Map
        ? Map<String, dynamic>.from(rawMetadata)
        : <String, dynamic>{};
    final nextCursor = _clean(metadata['nextCursor']);
    final nextPage = _clean(metadata['nextPage']);

    return CivitaiPage(
      items: items,
      nextPageToken: nextCursor ?? nextPage,
    );
  }

  Uri _buildRequestUri({required String? pageToken, required int limit}) {
    final safeLimit = limit.clamp(1, 100).toString();
    final parsedToken = Uri.tryParse(pageToken ?? '');

    if (parsedToken != null && parsedToken.hasAuthority) {
      if (parsedToken.host != _endpoint.host ||
          parsedToken.path != _endpoint.path) {
        throw const CivitaiApiException(
          'Civitai вернул небезопасную ссылку следующей страницы.',
        );
      }
      return parsedToken.replace(
        scheme: 'https',
        queryParameters: <String, String>{
          ...parsedToken.queryParameters,
          'limit': safeLimit,
          'nsfw': 'false',
        },
      );
    }

    return _endpoint.replace(
      queryParameters: <String, String>{
        'limit': safeLimit,
        'nsfw': 'false',
        'sort': 'Newest',
        if (pageToken != null && pageToken.isNotEmpty) 'cursor': pageToken,
      },
    );
  }

  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  void dispose() => _client.close();
}
