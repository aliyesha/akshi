import 'dart:async';

import 'package:akshi/app/app_router.dart';
import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/reminders/application/reminder_controller.dart';
import 'package:akshi/features/settings/application/settings_controller.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class AkshiApp extends ConsumerStatefulWidget {
  const AkshiApp({super.key});

  @override
  ConsumerState<AkshiApp> createState() => _AkshiAppState();
}

class _AkshiAppState extends ConsumerState<AkshiApp>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _notificationNavigation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _notificationNavigation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _start() async {
    appLogger.info('app.foreground.start.started');
    final notifications = ref.read(notificationServiceProvider);
    await notifications.initialize();
    if (!mounted) return;
    _notificationNavigation = notifications.navigationRoutes.listen(
      (route) => appRouter.go(route),
    );
    final pendingRoute = notifications.takePendingRoute();
    if (pendingRoute != null) appRouter.go(pendingRoute);
    _refresh();
    appLogger.info('app.foreground.start.completed');
  }

  void _refresh() {
    appLogger.info('app.foreground.refresh.started');
    unawaited(ref.read(reminderControllerProvider.notifier).reconcile());
    unawaited(ref.read(monitorControllerProvider.notifier).refreshAll());
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(settingsControllerProvider).value?.themeMode;
    final themeMode = switch (preference) {
      AkshiThemeMode.light => ThemeMode.light,
      AkshiThemeMode.dark => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'Akshi',
      debugShowCheckedModeBanner: false,
      theme: AkshiTheme.light,
      darkTheme: AkshiTheme.dark,
      themeMode: themeMode,
      builder: (context, child) => PhosphorDuotoneTheme(
        data: const PhosphorDuotoneThemeData(secondaryOpacity: .3),
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: appRouter,
    );
  }
}
