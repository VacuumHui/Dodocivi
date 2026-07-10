import 'package:flutter/material.dart';
import 'package:sdxl_collector/models/dataset_entry.dart';
import 'package:sdxl_collector/services/dataset_store.dart';

class DatasetSheet extends StatefulWidget {
  const DatasetSheet({required this.store, super.key});

  final DatasetStore store;

  @override
  State<DatasetSheet> createState() => _DatasetSheetState();
}

class _DatasetSheetState extends State<DatasetSheet> {
  late Future<List<DatasetEntry>> _entriesFuture;
  bool _changed = false;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _entriesFuture = widget.store.readEntries();
  }

  Future<void> _delete(int index) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await widget.store.deleteAt(index);
      if (!mounted) return;
      setState(() {
        _changed = true;
        _reload();
      });
    } catch (_) {
      if (mounted) _showError('Не удалось удалить пример.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _clear() async {
    if (_mutating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить датасет?'),
        content: const Text(
          'Все сохранённые пары будут удалены без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.store.clear();
      if (!mounted) return;
      setState(() {
        _changed = true;
        _reload();
      });
    } catch (_) {
      if (mounted) _showError('Не удалось очистить датасет.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Material(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: FutureBuilder<List<DatasetEntry>>(
            future: _entriesFuture,
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const <DatasetEntry>[];

              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Сохранённые примеры',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${entries.length} пар для обучения',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (_mutating)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 13),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (entries.isNotEmpty)
                          IconButton(
                            tooltip: 'Очистить датасет',
                            onPressed: _clear,
                            icon: const Icon(Icons.delete_sweep_outlined),
                          ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: _mutating
                              ? null
                              : () => Navigator.pop(context, _changed),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: switch (snapshot.connectionState) {
                      ConnectionState.waiting => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      _ when snapshot.hasError => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Не удалось прочитать локальный датасет.',
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ),
                      _ when entries.isEmpty => const _EmptyDataset(),
                      _ => ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return _DatasetEntryCard(
                              entry: entry,
                              onDelete:
                                  _mutating ? null : () => _delete(index),
                            );
                          },
                        ),
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyDataset extends StatelessWidget {
  const _EmptyDataset();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Датасет пока пуст',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Сохранённые пары появятся здесь.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatasetEntryCard extends StatelessWidget {
  const _DatasetEntryCard({required this.entry, required this.onDelete});

  final DatasetEntry entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.input,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.output,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Удалить пример',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
