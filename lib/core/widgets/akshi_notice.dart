import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum AkshiNoticeTone { info, success, warning, error }

void showAkshiNotice(
  BuildContext context, {
  required String title,
  required String message,
  AkshiNoticeTone tone = AkshiNoticeTone.info,
  Duration duration = const Duration(seconds: 6),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: _AkshiNotice(title: title, message: message, tone: tone),
      ),
    );
}

class _AkshiNotice extends StatelessWidget {
  const _AkshiNotice({
    required this.title,
    required this.message,
    required this.tone,
  });

  final String title;
  final String message;
  final AkshiNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = switch (tone) {
      AkshiNoticeTone.info => AkshiTheme.infoSurface(scheme),
      AkshiNoticeTone.success => AkshiTheme.successSurface(scheme),
      AkshiNoticeTone.warning => AkshiTheme.warningSurface(scheme),
      AkshiNoticeTone.error => AkshiTheme.errorSurface(scheme),
    };
    final icon = switch (tone) {
      AkshiNoticeTone.info => PhosphorIconsDuotone.info,
      AkshiNoticeTone.success => PhosphorIconsDuotone.checkCircle,
      AkshiNoticeTone.warning => PhosphorIconsDuotone.warningCircle,
      AkshiNoticeTone.error => PhosphorIconsDuotone.xCircle,
    };

    return Semantics(
      liveRegion: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: colors.background,
            elevation: 8,
            shadowColor: scheme.shadow.withValues(alpha: 0.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: PhosphorIcon(icon, color: colors.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: TextStyle(color: colors.foreground),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
