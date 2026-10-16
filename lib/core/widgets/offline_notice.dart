import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// A quiet page-level explanation shown while remote checks are unavailable.
///
/// The notice describes the device environment only. It deliberately does not
/// imply that any saved monitor observation has failed or changed.
class OfflineNotice extends StatelessWidget {
  const OfflineNotice({
    this.message = 'Saved results are unchanged. Checks are available when a connection returns.',
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhosphorIcon(
            PhosphorIconsDuotone.wifiSlash,
            size: 19,
            color: scheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Device offline',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gives one concise response to a user-initiated action that needs a network.
void showOfflineMessage(BuildContext context) {
  showAkshiNotice(
    context,
    title: 'Device offline',
    message: 'Connect to the internet and try again.',
    tone: AkshiNoticeTone.warning,
  );
}
