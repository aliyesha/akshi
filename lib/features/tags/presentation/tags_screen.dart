import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/tags/application/tag_controller.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const PhosphorIcon(PhosphorIconsRegular.plus),
        label: const Text('Create tag'),
      ),
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (items) => items.isEmpty
            ? const _EmptyTags()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final tag = items[index];
                  return Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      title: Align(
                        alignment: Alignment.centerLeft,
                        child: TagPill(tag: tag),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => action == 'edit'
                            ? _edit(context, ref, tag)
                            : _delete(context, ref, tag),
                        itemBuilder: (context) =>
                            const <PopupMenuEntry<String>>[
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final draft = await showTagEditor(context);
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
      ref.invalidate(monitorControllerProvider);
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
    await ref.read(tagControllerProvider.notifier).delete(tag.id);
    ref.invalidate(monitorControllerProvider);
  }

  void _showError(BuildContext context, Object error) {
    final duplicate = error.toString().contains('UNIQUE constraint failed');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          duplicate ? 'A tag with that name already exists.' : '$error',
        ),
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
