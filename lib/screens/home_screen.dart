import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sdxl_collector/models/civitai_image.dart';
import 'package:sdxl_collector/models/dataset_entry.dart';
import 'package:sdxl_collector/services/civitai_api.dart';
import 'package:sdxl_collector/services/dataset_store.dart';
import 'package:sdxl_collector/widgets/dataset_sheet.dart';
import 'package:sdxl_collector/widgets/prompt_card.dart';
import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CivitaiApi _api = CivitaiApi();
  final DatasetStore _store = DatasetStore();
  final TextEditingController _ideaController = TextEditingController();
  final FocusNode _ideaFocus = FocusNode();

  final List<CivitaiImage> _images = <CivitaiImage>[];
  final Set<int> _knownImageIds = <int>{};
  final Set<int> _savedImageIds = <int>{};

  int _currentIndex = 0;
  int _savedCount = 0;
  String? _nextPageToken;
  String? _errorMessage;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _actionBusy = false;
  Future<bool>? _loadMoreFuture;

  CivitaiImage? get _currentImage =>
      _currentIndex >= 0 && _currentIndex < _images.length
          ? _images[_currentIndex]
          : null;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _refreshSavedState();
    if (!mounted) return;
    await _loadFirstPage();
  }

  @override
  void dispose() {
    _api.dispose();
    _ideaController.dispose();
    _ideaFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshSavedState() async {
    try {
      final entries = await _store.readEntries();
      if (!mounted) return;
      setState(() {
        _savedCount = entries.length;
        _savedImageIds
          ..clear()
          ..addAll(
            entries.map((entry) => entry.imageId).whereType<int>(),
          );
      });
    } on FileSystemException {
      if (!mounted) return;
      _showMessage('Не удалось прочитать локальное хранилище.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Локальное хранилище недоступно.');
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _initialLoading = true;
      _errorMessage = null;
      _currentIndex = 0;
      _images.clear();
      _knownImageIds.clear();
      _nextPageToken = null;
    });

    try {
      final page = await _fetchPageWithUsableItems();
      if (!mounted) return;
      setState(() {
        _appendUnique(page.items);
        _nextPageToken = page.nextPageToken;
        _initialLoading = false;
      });
      _prefetchUpcoming();
    } on CivitaiApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _initialLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Не удалось загрузить изображения.';
        _initialLoading = false;
      });
    }
  }

  Future<CivitaiPage> _fetchPageWithUsableItems({String? pageToken}) async {
    var currentPageToken = pageToken;
    late CivitaiPage page;

    for (var attempt = 0; attempt < 4; attempt++) {
      page = await _api.fetchImages(pageToken: currentPageToken);
      if (page.items.isNotEmpty ||
          page.nextPageToken == null ||
          page.nextPageToken == currentPageToken) {
        return page;
      }
      currentPageToken = page.nextPageToken;
    }

    return page;
  }

  Future<bool> _loadMore() async {
    final activeOperation = _loadMoreFuture;
    if (activeOperation != null) return activeOperation;

    final cursor = _nextPageToken;
    if (cursor == null) return false;

    final operation = _performLoadMore(cursor);
    _loadMoreFuture = operation;
    try {
      return await operation;
    } finally {
      if (identical(_loadMoreFuture, operation)) {
        _loadMoreFuture = null;
      }
    }
  }

  Future<bool> _performLoadMore(String cursor) async {
    setState(() => _loadingMore = true);
    try {
      var currentToken = cursor;
      var nextToken = cursor;
      var exhausted = false;
      var newItems = <CivitaiImage>[];

      for (var attempt = 0; attempt < 4; attempt++) {
        final page = await _fetchPageWithUsableItems(pageToken: currentToken);
        nextToken = page.nextPageToken ?? '';
        newItems = page.items
            .where(
              (item) =>
                  !_knownImageIds.contains(item.id) &&
                  !_savedImageIds.contains(item.id),
            )
            .toList(growable: false);

        exhausted = page.nextPageToken == null ||
            page.nextPageToken == currentToken;
        if (newItems.isNotEmpty || exhausted) break;
        currentToken = page.nextPageToken!;
      }

      if (!mounted) return false;
      setState(() {
        _appendUnique(newItems);
        _nextPageToken = exhausted || nextToken.isEmpty ? null : nextToken;
      });
      if (newItems.isNotEmpty) _prefetchUpcoming();
      return newItems.isNotEmpty;
    } on CivitaiApiException catch (error) {
      if (mounted) _showMessage(error.message);
      return false;
    } catch (_) {
      if (mounted) _showMessage('Не удалось загрузить следующую страницу.');
      return false;
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _appendUnique(List<CivitaiImage> items) {
    for (final item in items) {
      if (!_savedImageIds.contains(item.id) && _knownImageIds.add(item.id)) {
        _images.add(item);
      }
    }
  }

  void _prefetchUpcoming() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final end = (_currentIndex + 3).clamp(0, _images.length);
      for (var index = _currentIndex + 1; index < end; index++) {
        unawaited(
          precacheImage(
            NetworkImage(_images[index].imageUri.toString()),
            context,
            onError: (_, __) {},
          ),
        );
      }
    });
  }

  Future<void> _advance() async {
    _ideaController.clear();
    _ideaFocus.unfocus();

    final nextIndex = _currentIndex + 1;
    if (nextIndex < _images.length) {
      setState(() => _currentIndex = nextIndex);
      _prefetchUpcoming();
      if (_images.length - _currentIndex <= 5) {
        unawaited(_loadMore());
      }
      return;
    }

    if (_nextPageToken != null) {
      final loaded = await _loadMore();
      if (loaded && mounted && nextIndex < _images.length) {
        setState(() => _currentIndex = nextIndex);
        _prefetchUpcoming();
        return;
      }
      if (!loaded) return;
    }

    if (mounted) setState(() => _currentIndex = _images.length);
  }

  Future<void> _skipCurrent() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _advance();
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _saveCurrent() async {
    final image = _currentImage;
    final idea = _ideaController.text.trim();
    if (image == null || _actionBusy) return;

    if (idea.isEmpty) {
      _showMessage('Введите краткое описание изображения.');
      _ideaFocus.requestFocus();
      return;
    }

    setState(() => _actionBusy = true);
    try {
      await _store.add(
        DatasetEntry(
          instruction: DatasetEntry.defaultInstruction,
          input: idea,
          output: image.prompt,
          imageId: image.id,
          imageUrl: image.imageUri.toString(),
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _savedCount += 1;
        _savedImageIds.add(image.id);
      });
      _showMessage('Пример сохранён.');
      await _advance();
    } on DuplicateEntryException {
      if (mounted) {
        _showMessage('Этот пример уже есть в датасете.');
      }
    } on FileSystemException {
      if (mounted) {
        _showMessage('Не удалось записать датасет в память устройства.');
      }
    } catch (_) {
      if (mounted) _showMessage('Не удалось сохранить пример.');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _exportDataset() async {
    try {
      final file = await _store.createExportFile();
      if (!mounted) return;
      if (file == null) {
        _showMessage('Датасет пуст. Сначала сохраните хотя бы один пример.');
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          title: 'SDXL Collector dataset',
          subject: 'Датасет SDXL',
          text: 'JSON-датасет из SDXL Collector',
          files: <XFile>[
            XFile(file.path, name: 'sdxl_dataset.json', mimeType: 'application/json'),
          ],
        ),
      );
    } on FileSystemException {
      if (mounted) _showMessage('Не удалось подготовить файл для экспорта.');
    } catch (_) {
      if (mounted) _showMessage('Системное меню экспорта недоступно.');
    }
  }

  Future<void> _showDataset() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => DatasetSheet(store: _store),
    );
    await _refreshSavedState();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentImage;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SDXL Collector',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Сбор пар «идея → промпт»',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          _SavedCounter(count: _savedCount, onTap: _showDataset),
          IconButton(
            tooltip: 'Экспортировать JSON',
            onPressed: _exportDataset,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch ((_initialLoading, _errorMessage, current)) {
          (true, _, _) => const _LoadingView(),
          (false, final String error, null) => _ErrorView(
              message: error,
              onRetry: _loadFirstPage,
            ),
          (false, _, null) => _FinishedView(
              savedCount: _savedCount,
              onReload: _loadFirstPage,
              onExport: _exportDataset,
            ),
          _ => _CollectorBody(
              image: current!,
              currentIndex: _currentIndex,
              loadedCount: _images.length,
              loadingMore: _loadingMore,
              ideaController: _ideaController,
              ideaFocus: _ideaFocus,
            ),
        },
      ),
      bottomNavigationBar: current == null
          ? null
          : _ActionBar(
              busy: _actionBusy,
              ideaController: _ideaController,
              onSkip: _skipCurrent,
              onSave: _saveCurrent,
            ),
    );
  }
}

class _SavedCounter extends StatelessWidget {
  const _SavedCounter({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ActionChip(
        tooltip: 'Открыть датасет',
        onPressed: onTap,
        avatar: Icon(Icons.dataset_outlined, size: 18, color: colors.primary),
        label: Text('$count'),
      ),
    );
  }
}

class _CollectorBody extends StatelessWidget {
  const _CollectorBody({
    required this.image,
    required this.currentIndex,
    required this.loadedCount,
    required this.loadingMore,
    required this.ideaController,
    required this.ideaFocus,
  });

  final CivitaiImage image;
  final int currentIndex;
  final int loadedCount;
  final bool loadingMore;
  final TextEditingController ideaController;
  final FocusNode ideaFocus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 11,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: _ImagePanel(image: image),
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  flex: 10,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProgressHeader(
                          currentIndex: currentIndex,
                          loadedCount: loadedCount,
                          loadingMore: loadingMore,
                        ),
                        const SizedBox(height: 14),
                        PromptCard(
                          key: ValueKey<int>(image.id),
                          prompt: image.prompt,
                          negativePrompt: image.negativePrompt,
                        ),
                        const SizedBox(height: 14),
                        _IdeaInput(
                          controller: ideaController,
                          focusNode: ideaFocus,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _ProgressHeader(
              currentIndex: currentIndex,
              loadedCount: loadedCount,
              loadingMore: loadingMore,
            ),
            const SizedBox(height: 14),
            _ImagePanel(image: image),
            const SizedBox(height: 16),
            PromptCard(
              key: ValueKey<int>(image.id),
              prompt: image.prompt,
              negativePrompt: image.negativePrompt,
            ),
            const SizedBox(height: 14),
            _IdeaInput(
              controller: ideaController,
              focusNode: ideaFocus,
            ),
          ],
        );
      },
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.currentIndex,
    required this.loadedCount,
    required this.loadingMore,
  });

  final int currentIndex;
  final int loadedCount;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Карточка ${currentIndex + 1} из $loadedCount',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: loadedCount == 0 ? 0 : (currentIndex + 1) / loadedCount,
                minHeight: 5,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
          ),
        ),
        if (loadingMore) ...[
          const SizedBox(width: 14),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
        ],
      ],
    );
  }
}

class _ImagePanel extends StatelessWidget {
  const _ImagePanel({required this.image});

  final CivitaiImage image;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chips = <Widget>[
      if (image.width != null && image.height != null)
        _MetaChip(
          icon: Icons.aspect_ratio_rounded,
          text: '${image.width} × ${image.height}',
        ),
      if (image.modelName != null)
        _MetaChip(icon: Icons.memory_rounded, text: image.modelName!),
      if (image.username != null)
        _MetaChip(icon: Icons.person_outline_rounded, text: image.username!),
      if (image.steps != null)
        _MetaChip(icon: Icons.tune_rounded, text: '${image.steps} steps'),
      if (image.sampler != null)
        _MetaChip(icon: Icons.blur_on_rounded, text: image.sampler!),
      if (image.cfgScale != null)
        _MetaChip(
          icon: Icons.speed_rounded,
          text: 'CFG ${image.cfgScale!.toStringAsFixed(1)}',
        ),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: Card(
        key: ValueKey<int>(image.id),
        color: colors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: image.aspectRatio,
              child: Image.network(
                image.imageUri.toString(),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  final expected = progress.expectedTotalBytes;
                  return ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: expected == null || expected <= 0
                            ? null
                            : progress.cumulativeBytesLoaded / expected,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 10),
                        const Text('Изображение недоступно'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(spacing: 8, runSpacing: 8, children: chips),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _IdeaInput extends StatelessWidget {
  const _IdeaInput({
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Краткая идея',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              'Опишите изображение своими словами. Эта фраза станет input.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 3,
              maxLines: 6,
              maxLength: 400,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Например: одинокий маяк во время шторма…',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.ideaController,
    required this.onSkip,
    required this.onSave,
  });

  final bool busy;
  final TextEditingController ideaController;
  final VoidCallback onSkip;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.96),
      elevation: 16,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSkip,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Пропустить'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: ideaController,
                builder: (context, value, _) {
                  final canSave = value.text.trim().isNotEmpty;
                  return FilledButton.icon(
                    onPressed: busy || !canSave ? null : onSave,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_task_rounded),
                    label: Text(busy ? 'Сохранение…' : 'Сохранить пример'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text('Загружаю изображения и промпты…'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: colors.error),
            const SizedBox(height: 18),
            Text(
              'Не удалось загрузить ленту',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedView extends StatelessWidget {
  const _FinishedView({
    required this.savedCount,
    required this.onReload,
    required this.onExport,
  });

  final int savedCount;
  final VoidCallback onReload;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded, size: 68, color: colors.primary),
            const SizedBox(height: 18),
            Text(
              'Текущая лента обработана',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'В датасете: $savedCount примеров',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Новая лента'),
                ),
                FilledButton.icon(
                  onPressed: savedCount == 0 ? null : onExport,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Экспорт JSON'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
