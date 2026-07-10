import 'package:flutter_test/flutter_test.dart';
import 'package:sdxl_collector/models/dataset_entry.dart';

void main() {
  test('export contains only training fields', () {
    final entry = DatasetEntry(
      instruction: DatasetEntry.defaultInstruction,
      input: 'маяк во время шторма',
      output: 'cinematic lighthouse, storm, dramatic lighting',
      imageId: 10,
      imageUrl: 'https://example.com/image.jpg',
      createdAt: DateTime.utc(2026, 7, 10),
    );

    expect(entry.toExportJson().keys, <String>[
      'instruction',
      'input',
      'output',
    ]);
    expect(entry.toStorageJson()['imageId'], 10);
  });

  test('legacy entry without metadata remains readable', () {
    final entry = DatasetEntry.fromJson(<String, dynamic>{
      'instruction': DatasetEntry.defaultInstruction,
      'input': 'идея',
      'output': 'prompt',
    });

    expect(entry.imageId, isNull);
    expect(entry.input, 'идея');
  });
}
