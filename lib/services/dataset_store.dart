import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sdxl_collector/models/dataset_entry.dart';

class DuplicateEntryException implements Exception {
  const DuplicateEntryException();
}

class DatasetStore {
  DatasetStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider =
            directoryProvider ?? getApplicationDocumentsDirectory;

  static const _storageFileName = 'sdxl_collector_entries.json';
  static const _legacyAndExportFileName = 'sdxl_dataset.json';

  final Future<Directory> Function() _directoryProvider;
  Future<void> _operationTail = Future<void>.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<File> _file(String name) async {
    final directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  Future<List<DatasetEntry>> readEntries() =>
      _synchronized(_readEntriesUnlocked);

  Future<List<DatasetEntry>> _readEntriesUnlocked() async {
    final storage = await _file(_storageFileName);
    if (await storage.exists()) return _readFile(storage);

    // Versions before 1.1 stored the training export directly. Import it once
    // so an APK update does not make the user's existing dataset disappear.
    final legacy = await _file(_legacyAndExportFileName);
    if (!await legacy.exists()) return <DatasetEntry>[];

    final legacyEntries = await _readFile(legacy);
    if (legacyEntries.isEmpty) return <DatasetEntry>[];

    final migrated = legacyEntries.reversed.toList(growable: false);
    await _writeEntriesUnlocked(migrated);
    return migrated;
  }

  Future<List<DatasetEntry>> _readFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <DatasetEntry>[];

      final entries = <DatasetEntry>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        try {
          entries.add(DatasetEntry.fromJson(Map<String, dynamic>.from(raw)));
        } on FormatException {
          // Preserve the rest of the dataset if one record is damaged.
        }
      }
      return entries;
    } on FileSystemException {
      rethrow;
    } on FormatException {
      return <DatasetEntry>[];
    }
  }

  Future<int> count() => _synchronized(() async {
        return (await _readEntriesUnlocked()).length;
      });

  Future<void> add(DatasetEntry entry) => _synchronized(() async {
        final entries = await _readEntriesUnlocked();
        if (entry.imageId != null &&
            entries.any((item) => item.imageId == entry.imageId)) {
          throw const DuplicateEntryException();
        }

        entries.insert(0, entry);
        await _writeEntriesUnlocked(entries);
      });

  Future<void> deleteAt(int index) => _synchronized(() async {
        final entries = await _readEntriesUnlocked();
        if (index < 0 || index >= entries.length) return;
        entries.removeAt(index);
        await _writeEntriesUnlocked(entries);
      });

  Future<void> clear() => _synchronized(() async {
        final storage = await _file(_storageFileName);
        if (await storage.exists()) await storage.delete();

        final export = await _file(_legacyAndExportFileName);
        if (await export.exists()) await export.delete();
      });

  Future<File?> createExportFile() => _synchronized(() async {
        final entries = await _readEntriesUnlocked();
        if (entries.isEmpty) return null;

        final export = await _file(_legacyAndExportFileName);
        final encoder = const JsonEncoder.withIndent('  ');
        await export.writeAsString(
          encoder.convert(
            entries.reversed.map((entry) => entry.toExportJson()).toList(),
          ),
          flush: true,
        );
        return export;
      });

  Future<void> _writeEntriesUnlocked(List<DatasetEntry> entries) async {
    final file = await _file(_storageFileName);
    final temporary = File('${file.path}.tmp');
    final encoder = const JsonEncoder.withIndent('  ');

    await temporary.writeAsString(
      encoder.convert(entries.map((entry) => entry.toStorageJson()).toList()),
      flush: true,
    );

    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
