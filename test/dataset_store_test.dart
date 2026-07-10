import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdxl_collector/models/dataset_entry.dart';
import 'package:sdxl_collector/services/dataset_store.dart';

void main() {
  late Directory directory;
  late DatasetStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sdxl_collector_test_');
    store = DatasetStore(directoryProvider: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('migrates the legacy export and keeps export order stable', () async {
    final legacy = File('${directory.path}${Platform.pathSeparator}sdxl_dataset.json');
    await legacy.writeAsString(
      jsonEncode(<Map<String, String>>[
        <String, String>{
          'instruction': DatasetEntry.defaultInstruction,
          'input': 'первая идея',
          'output': 'first prompt',
        },
        <String, String>{
          'instruction': DatasetEntry.defaultInstruction,
          'input': 'вторая идея',
          'output': 'second prompt',
        },
      ]),
    );

    final entries = await store.readEntries();
    expect(entries.map((entry) => entry.input), <String>[
      'вторая идея',
      'первая идея',
    ]);

    final export = await store.createExportFile();
    final decoded = jsonDecode(await export!.readAsString()) as List<dynamic>;
    expect(
      decoded.map((entry) => (entry as Map<String, dynamic>)['input']),
      <String>['первая идея', 'вторая идея'],
    );
  });

  test('serializes concurrent writes without losing entries', () async {
    await Future.wait(
      List<Future<void>>.generate(12, (index) {
        return store.add(
          DatasetEntry(
            instruction: DatasetEntry.defaultInstruction,
            input: 'идея $index',
            output: 'prompt $index',
            imageId: index,
            imageUrl: 'https://example.com/$index.jpg',
            createdAt: DateTime.utc(2026, 7, 10, 12, index),
          ),
        );
      }),
    );

    final entries = await store.readEntries();
    expect(entries, hasLength(12));
    expect(entries.map((entry) => entry.imageId).toSet(), hasLength(12));

    final export = await store.createExportFile();
    final decoded = jsonDecode(await export!.readAsString()) as List<dynamic>;
    expect(decoded, hasLength(12));
  });

  test('rejects a duplicate image id', () async {
    DatasetEntry entry(int id) => DatasetEntry(
          instruction: DatasetEntry.defaultInstruction,
          input: 'идея',
          output: 'prompt',
          imageId: id,
          imageUrl: null,
          createdAt: DateTime.utc(2026, 7, 10),
        );

    await store.add(entry(5));
    await expectLater(store.add(entry(5)), throwsA(isA<DuplicateEntryException>()));
  });
}
