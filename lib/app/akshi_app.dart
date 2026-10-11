import 'dart:async';

import 'package:akshi/app/app_lifecycle_coordinator.dart';
import 'package:akshi/app/app_router.dart';
import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/services/system_settings_service.dart';
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
  late final AppLifecycleCoordinator _lifecycle;
  StreamSubscription<String>? _notificationNavigation;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(notificationServiceProvider);
    _lifecycle = AppLifecycleCoordinator(
      initializeNotifications: notifications.initialize,
      attachNotificationNavigation: () {
        if (!mounted) return;
        _notificationNavigation ??= notifications.navigationRoutes.listen(
          _navigateFromNotification,
          onError: _notificationNavigationFailed,
        );
        final pendingRoute = notifications.takePendingRoute();
        if (pendingRoute != null) _navigateFromNotification(pendingRoute);
      },
      configureNotificationPermission: () async {
        final settings = await ref.read(settingsControllerProvider.future);
        if (!mounted) return;
        var permission =
            await SystemSettingsService.notificationPermissionStatus();
        if (!mounted) return;
        if (settings.remindersEnabled &&
            permission == NotificationPermissionStatus.notDetermined) {
          await notifications.requestPermission();
          if (!mounted) return;
          permission =
              await SystemSettingsService.notificationPermissionStatus();
          if (!mounted) return;
        }
        final publishedPermission = ref
            .read(reminderControllerProvider)
            .permission;
        if (settings.remindersEnabled && publishedPermission != permission) {
          await ref.read(reminderControllerProvider.notifier).reconcile();
        }
      },
      reconcileReminders: () async {
        await ref.read(reminderControllerProvider.notifier).reconcile();
      },
      refreshMonitors: () async {
        await ref
            .read(monitorControllerProvider.notifier)
            .refreshAll(force: false);
      },
      reportError: (event, error, stackTrace) {
        appLogger.error(event, error, stackTrace);
      },
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    final navigation = _notificationNavigation;
    if (navigation != null) {
      unawaited(_cancelNotificationNavigation(navigation));
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(deviceOfflineProvider);
    _refresh();
  }

  void _start() {
    unawaited(_runOwned('app.foreground.start', _lifecycle.start));
  }

  void _refresh() {
    unawaited(_runOwned('app.foreground.refresh', _lifecycle.refresh));
  }

  Future<void> _runOwned(String operation, Future<void> Function() task) async {
    appLogger.info('$operation.started');
    try {
      await task();
      appLogger.info('$operation.completed');
    } on Object catch (error, stackTrace) {
      // The coordinator contains task failures. This final owner protects the
      // frame/lifecycle callback if orchestration itself ever regresses.
      appLogger.error('$operation.failed', error, stackTrace);
    }
  }

  void _navigateFromNotification(String route) {
    try {
      appRouter.go(route);
    } on Object catch (error, stackTrace) {
      appLogger.error(
        'app.foreground.notifications.navigation.failed',
        error,
        stackTrace,
      );
    }
  }

  void _notificationNavigationFailed(Object error, StackTrace stackTrace) {
    appLogger.error(
      'app.foreground.notifications.stream.failed',
      error,
      stackTrace,
    );
  }

  Future<void> _cancelNotificationNavigation(
    StreamSubscription<String> navigation,
  ) async {
    try {
      await navigation.cancel();
    } on Object catch (error, stackTrace) {
      appLogger.error(
        'app.foreground.notifications.cancel.failed',
        error,
        stackTrace,
      );
    }
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
