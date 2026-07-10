import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sdxl_collector/services/civitai_api.dart';

void main() {
  test('parses items and the current cursor pagination token', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['nsfw'], 'false');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 7,
              'url': 'https://image.civitai.com/example.jpeg',
              'nsfw': false,
              'meta': <String, dynamic>{'prompt': 'cinematic city'},
            },
            <String, dynamic>{
              'id': 8,
              'url': 'https://image.civitai.com/broken.jpeg',
              'nsfw': false,
              'meta': <String, dynamic>{},
            },
          ],
          'metadata': <String, dynamic>{'nextCursor': 'cursor-2'},
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final api = CivitaiApi(client: client);
    addTearDown(api.dispose);

    final page = await api.fetchImages();

    expect(page.items, hasLength(1));
    expect(page.items.single.id, 7);
    expect(page.nextPageToken, 'cursor-2');
  });

  test('supports and normalizes legacy nextPage URLs', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      if (requestCount == 1) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'items': <dynamic>[],
            'metadata': <String, dynamic>{
              'nextPage': 'http://civitai.com/api/v1/images?page=2&limit=20',
            },
          }),
          200,
        );
      }

      expect(request.url.scheme, 'https');
      expect(request.url.host, 'civitai.com');
      expect(request.url.path, '/api/v1/images');
      expect(request.url.queryParameters['page'], '2');
      expect(request.url.queryParameters['limit'], '50');
      expect(request.url.queryParameters['nsfw'], 'false');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'items': <dynamic>[],
          'metadata': <String, dynamic>{},
        }),
        200,
      );
    });
    final api = CivitaiApi(client: client);
    addTearDown(api.dispose);

    final first = await api.fetchImages();
    await api.fetchImages(pageToken: first.nextPageToken);

    expect(requestCount, 2);
  });

  test('rejects an external nextPage URL', () async {
    final api = CivitaiApi(
      client: MockClient((request) async => http.Response('{}', 200)),
    );
    addTearDown(api.dispose);

    await expectLater(
      api.fetchImages(
        pageToken: 'https://example.com/api/v1/images?page=2',
      ),
      throwsA(isA<CivitaiApiException>()),
    );
  });
}
