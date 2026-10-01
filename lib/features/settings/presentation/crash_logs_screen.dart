import 'package:akshi/app/providers.dart';
import 'package:akshi/core/crash/crash_log.dart';
import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Displays diagnostics captured locally; nothing is uploaded automatically.
class CrashLogsScreen extends ConsumerWidget {
  const CrashLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(crashLogsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crash reports'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Delete all reports',
            onPressed: logs.value?.isEmpty ?? true
                ? null
                : () => _clear(context, ref),
            icon: const PhosphorIcon(PhosphorIconsRegular.trash),
          ),
        ],
      ),
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const Center(
          child: Text('Crash reports are unavailable on this device.'),
        ),
        data: (entries) => entries.isEmpty
            ? const _EmptyCrashLogs()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: entries.length,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _CrashLogTile(
                  log: entries[index],
                  onDelete: () async {
                    await ref
                        .read(crashLogStoreProvider)
                        .delete(entries[index].id);
                    ref.invalidate(crashLogsProvider);
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete crash reports?'),
        content: const Text(
          'This removes all diagnostics stored on this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(crashLogStoreProvider).clear();
    ref.invalidate(crashLogsProvider);
  }
}

class _CrashLogTile extends StatelessWidget {
  const _CrashLogTile({required this.log, required this.onDelete});

  final CrashLog log;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: const PhosphorIcon(PhosphorIconsDuotone.warningCircle),
      title: Text(log.errorType),
      subtitle: Text('${formatLocalDateTime(log.occurredAt)} · ${log.context}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: <Widget>[
        SelectableText(log.message),
        const SizedBox(height: 10),
        SelectableText(
          log.report,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: log.report));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Crash report copied')),
                  );
                }
              },
              icon: const PhosphorIcon(PhosphorIconsRegular.copy),
              label: const Text('Copy'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Delete report',
              onPressed: onDelete,
              icon: const PhosphorIcon(PhosphorIconsRegular.trash),
            ),
          ],
        ),
      ],
    ),
  );
}

class _EmptyCrashLogs extends StatelessWidget {
  const _EmptyCrashLogs();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        'No crash reports have been captured on this device.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}
