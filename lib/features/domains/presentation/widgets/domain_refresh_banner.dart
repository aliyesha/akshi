import 'package:akshi/core/formatters/date_time_formatter.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Explains that the visible domain list is the last committed snapshot.
class DomainRefreshBanner extends ConsumerWidget {
  const DomainRefreshBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refresh = ref.watch(domainRefreshProvider);
    if (!refresh.shouldShowStatus) return const SizedBox.shrink();

    if (refresh.hasUnresolvedFailure) {
      final failedAt = formatLocalDateTime(refresh.lastFailedAt!);
      return Semantics(
        liveRegion: true,
        label: 'The latest domain refresh could not finish.',
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Refresh could not finish',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'The attempt at $failedAt did not commit. Saved results '
                  'remain visible; try again when ready.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final count = refresh.total == 0
        ? 'Preparing checks'
        : '${refresh.completed} of ${refresh.total} checked';
    final title = refresh.isFinalizing
        ? 'Saving refreshed results'
        : 'Refreshing domains - $count';
    final previous = refresh.lastCompletedAt == null
        ? 'Showing saved results until every check finishes.'
        : 'Showing results saved ${formatLocalDateTime(refresh.lastCompletedAt!)}.';
    final progress = refresh.completed == 0 || refresh.isFinalizing
        ? null
        : refresh.fraction;

    return Semantics(
      liveRegion: true,
      label: '$title. $count. $previous',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                '$previous Editing and deletion are available when refresh completes.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
