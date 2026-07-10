import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PromptCard extends StatefulWidget {
  const PromptCard({
    required this.prompt,
    this.negativePrompt,
    super.key,
  });

  final String prompt;
  final String? negativePrompt;

  @override
  State<PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<PromptCard> {
  bool _expanded = false;

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(text: widget.prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Промпт скопирован.')),
    );
  }

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
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Исходный SDXL-промпт',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Скопировать промпт',
                  onPressed: _copyPrompt,
                  icon: const Icon(Icons.copy_rounded, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: Alignment.topCenter,
              child: Text(
                widget.prompt,
                maxLines: _expanded ? null : 6,
                overflow: _expanded ? null : TextOverflow.fade,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.48,
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ),
            if (widget.prompt.length > 260)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  label: Text(_expanded ? 'Свернуть' : 'Показать полностью'),
                ),
              ),
            if (widget.negativePrompt != null) ...[
              const Divider(height: 28),
              Text(
                'Negative prompt',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.error,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.negativePrompt!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.4,
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
