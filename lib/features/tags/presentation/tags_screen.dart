import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:akshi/core/widgets/async_error_view.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/presentation/widgets/monitor_refresh_banner.dart';
import 'package:akshi/features/tags/application/tag_controller.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:akshi/features/tags/domain/tag_policy.dart';
import 'package:akshi/features/tags/presentation/tag_editor_sheet.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagControllerProvider);
    final refresh = ref.watch(monitorRefreshProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton:
          !refresh.isRunning &&
              tags.value != null &&
              TagPolicy.canCreate(tags.value!.length)
          ? FloatingActionButton(
              tooltip: 'Create tag',
              onPressed: () => _create(context, ref, tags.value!.length),
              child: const PhosphorIcon(PhosphorIconsRegular.plus),
            )
          : null,
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          appLogger.error('ui.tags.load.failed', error, stack);
          return AsyncErrorView(
            onRetry: () => ref.invalidate(tagControllerProvider),
          );
        },
        data: (items) => Column(
          children: <Widget>[
            if (refresh.shouldShowStatus)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: MonitorRefreshBanner(),
              ),
            _TagCapacity(count: items.length),
            Expanded(
              child: items.isEmpty
                  ? const _EmptyTags()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tag = items[index];
                        return Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 7,
                            ),
                            title: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  PhosphorIcon(
                                    PhosphorIconsDuotone.tag,
                                    size: 20,
                                    color: Color(tag.colorArgb),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(child: TagPill(tag: tag)),
                                ],
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              enabled: !refresh.isRunning,
                              onSelected: (action) => action == 'edit'
                                  ? _edit(context, ref, tag)
                                  : _delete(context, ref, tag),
                              itemBuilder: (context) =>
                                  const <PopupMenuEntry<String>>[
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: <Widget>[
                                          PhosphorIcon(
                                            PhosphorIconsRegular.pencilSimple,
                                            size: 19,
                                          ),
                                          SizedBox(width: 10),
                                          Text('Edit'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: <Widget>[
                                          PhosphorIcon(
                                            PhosphorIconsRegular.trash,
                                            size: 19,
                                          ),
                                          SizedBox(width: 10),
                                          Text('Delete'),
                                        ],
                                      ),
                                    ),
                                  ],
                            ),
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

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    int currentCount,
  ) async {
    final draft = await showTagEditor(context, currentCount: currentCount);
    if (draft == null || !context.mounted) return;
    try {
      await ref
          .read(tagControllerProvider.notifier)
          .create(name: draft.name, colorArgb: draft.colorArgb);
    } catch (error, stackTrace) {
      appLogger.error('ui.tags.create.failed', error, stackTrace);
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    MonitorTag tag,
  ) async {
    final draft = await showTagEditor(context, tag: tag);
    if (draft == null || !context.mounted) return;
    try {
      await ref
          .read(tagControllerProvider.notifier)
          .updateTag(
            tag.copyWith(name: draft.name, colorArgb: draft.colorArgb),
          );
    } catch (error, stackTrace) {
      appLogger.error('ui.tags.update.failed', error, stackTrace);
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MonitorTag tag,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${tag.name}”?'),
        content: const Text(
          'The tag will be removed from every monitor. No monitor will be deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(tagControllerProvider.notifier).delete(tag.id);
    } catch (error, stackTrace) {
      appLogger.error('ui.tags.delete.failed', error, stackTrace);
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    final message = switch (error) {
      MonitorRefreshInProgressException() =>
        'Wait for the monitor refresh to finish.',
      TagLimitReachedException() =>
        'You already have ${TagPolicy.maxCount} tags. Delete one before creating another.',
      _ when error.toString().contains('UNIQUE constraint failed') =>
        'A tag with that name already exists.',
      _ => 'Akshi could not update tags on this device. Please try again.',
    };
    showAkshiNotice(
      context,
      title: 'Could not update tags',
      message: message,
      tone: AkshiNoticeTone.error,
    );
  }
}

class _TagCapacity extends StatelessWidget {
  const _TagCapacity({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final remaining = TagPolicy.remaining(count);
    final atLimit = remaining == 0;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: atLimit
            ? scheme.tertiaryContainer.withValues(alpha: .62)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhosphorIcon(
            atLimit ? PhosphorIconsDuotone.info : PhosphorIconsDuotone.tag,
            color: atLimit ? scheme.onTertiaryContainer : scheme.primary,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$count of ${TagPolicy.maxCount} tags used',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  atLimit
                      ? 'Reuse an existing tag, or delete one below before creating another.'
                      : '$remaining ${remaining == 1 ? 'tag' : 'tags'} remaining.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTags extends StatelessWidget {
  const _EmptyTags();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PhosphorIcon(
            PhosphorIconsDuotone.tag,
            size: 58,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text('No tags yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          const Text(
            'Create tags for clients, environments, or any grouping that fits your work.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
