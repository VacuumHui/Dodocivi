import 'package:flutter_test/flutter_test.dart';
import 'package:sdxl_collector/models/civitai_image.dart';

void main() {
  group('CivitaiImage', () {
    test('parses a valid public API item', () {
      final image = CivitaiImage.fromJson(<String, dynamic>{
        'id': 42,
        'url': 'https://image.civitai.com/example.jpeg',
        'width': 1024,
        'height': 768,
        'nsfw': false,
        'username': 'artist',
        'meta': <String, dynamic>{
          'prompt': 'cinematic lighthouse in a storm',
          'negativePrompt': 'blurry',
          'Model': 'Example XL',
          'steps': 30,
          'cfgScale': 7,
        },
      });

      expect(image.id, 42);
      expect(image.prompt, contains('lighthouse'));
      expect(image.modelName, 'Example XL');
      expect(image.aspectRatio, closeTo(4 / 3, 0.001));
    });

    test('rejects an item without a prompt', () {
      expect(
        () => CivitaiImage.fromJson(<String, dynamic>{
          'id': 42,
          'url': 'https://image.civitai.com/example.jpeg',
          'nsfw': false,
          'meta': <String, dynamic>{},
        }),
        throwsFormatException,
      );
    });

    test('rejects an explicitly NSFW item', () {
      expect(
        () => CivitaiImage.fromJson(<String, dynamic>{
          'id': 42,
          'url': 'https://image.civitai.com/example.jpeg',
          'nsfw': true,
          'meta': <String, dynamic>{'prompt': 'test'},
        }),
        throwsFormatException,
      );
    });

    test('rejects a non-safe nsfwLevel', () {
      expect(
        () => CivitaiImage.fromJson(<String, dynamic>{
          'id': 42,
          'url': 'https://image.civitai.com/example.jpeg',
          'nsfw': false,
          'nsfwLevel': 'Mature',
          'meta': <String, dynamic>{'prompt': 'test'},
        }),
        throwsFormatException,
      );
    });

    test('rejects a non-HTTP image URL', () {
      expect(
        () => CivitaiImage.fromJson(<String, dynamic>{
          'id': 42,
          'url': 'file:///tmp/example.jpeg',
          'nsfw': false,
          'meta': <String, dynamic>{'prompt': 'test'},
        }),
        throwsFormatException,
      );
    });
  });
}
