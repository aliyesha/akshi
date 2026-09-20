import 'package:material_ui/material_ui.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(LucideIcons.circle_alert, size: 48),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refresh_cw),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
