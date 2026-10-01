/// One asynchronous unit of startup or foreground work.
typedef AppLifecycleTask = Future<void> Function();

/// Reports a contained lifecycle failure without exposing it to the event loop.
typedef AppLifecycleErrorReporter = void Function(
  String event,
  Object error,
  StackTrace stackTrace,
);

/// Owns startup sequencing and independent foreground operations.
///
/// Reminder and monitor work share one coalesced data session behind separate
/// error boundaries. Notification maintenance owns another coalesced operation,
/// so a slow plugin cannot keep later data sessions from starting, while a
/// failed initialization remains retryable.
final class AppLifecycleCoordinator {
  factory AppLifecycleCoordinator({
    required AppLifecycleTask initializeNotifications,
    required void Function() attachNotificationNavigation,
    required AppLifecycleTask configureNotificationPermission,
    required AppLifecycleTask reconcileReminders,
    required AppLifecycleTask refreshMonitors,
    required AppLifecycleErrorReporter reportError,
  }) => AppLifecycleCoordinator._(
    initializeNotifications,
    attachNotificationNavigation,
    configureNotificationPermission,
    reconcileReminders,
    refreshMonitors,
    reportError,
  );

  AppLifecycleCoordinator._(
    this._initializeNotifications,
    this._attachNotificationNavigation,
    this._configureNotificationPermission,
    this._reconcileReminders,
    this._refreshMonitors,
    this._reportError,
  );

  final AppLifecycleTask _initializeNotifications;
  final void Function() _attachNotificationNavigation;
  final AppLifecycleTask _configureNotificationPermission;
  final AppLifecycleTask _reconcileReminders;
  final AppLifecycleTask _refreshMonitors;
  final AppLifecycleErrorReporter _reportError;

  Future<void>? _startupOperation;
  Future<void>? _foregroundOperation;
  Future<void>? _notificationOperation;
  var _notificationsReady = false;
  var _notificationNavigationAttached = false;
  var _disposed = false;

  /// Runs startup once and completes after initial data maintenance settles.
  Future<void> start() => _startupOperation ??= _runStartup();

  /// Runs one foreground data session, joining an active data session.
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final active = _foregroundOperation;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _runForegroundTasks().whenComplete(() {
      if (identical(_foregroundOperation, operation)) {
        _foregroundOperation = null;
      }
    });
    _foregroundOperation = operation;
    return operation;
  }

  /// Prevents new phases from starting after the owning widget is disposed.
  void dispose() {
    _disposed = true;
  }

  Future<void> _runStartup() async {
    if (_disposed) return;
    await refresh();
  }

  Future<void> _runForegroundTasks() async {
    _startNotificationMaintenance();
    await Future.wait([
      _runTask(
        'app.foreground.reminders.reconcile.failed',
        _reconcileReminders,
      ),
      _runTask('app.foreground.monitors.refresh.failed', _refreshMonitors),
    ]);
  }

  void _startNotificationMaintenance() {
    if (_disposed || _notificationOperation != null) return;

    late final Future<void> operation;
    operation = _maintainNotifications().whenComplete(() {
      if (identical(_notificationOperation, operation)) {
        _notificationOperation = null;
      }
    });
    _notificationOperation = operation;
  }

  Future<void> _maintainNotifications() async {
    if (!_notificationsReady) {
      final ready = await _runTask(
        'app.foreground.notifications.initialize.failed',
        _initializeNotifications,
      );
      if (_disposed) return;
      _notificationsReady = ready;
    }
    if (!_notificationsReady) return;

    if (!_notificationNavigationAttached) {
      _notificationNavigationAttached = _runCallback(
        'app.foreground.notifications.navigation.failed',
        _attachNotificationNavigation,
      );
    }
    await _runTask(
      'app.foreground.notifications.permission.failed',
      _configureNotificationPermission,
    );
  }

  Future<bool> _runTask(String event, AppLifecycleTask task) async {
    if (_disposed) return false;
    try {
      await task();
      return true;
    } on Object catch (error, stackTrace) {
      _report(event, error, stackTrace);
      return false;
    }
  }

  bool _runCallback(String event, void Function() callback) {
    if (_disposed) return false;
    try {
      callback();
      return true;
    } on Object catch (error, stackTrace) {
      _report(event, error, stackTrace);
      return false;
    }
  }

  void _report(String event, Object error, StackTrace stackTrace) {
    try {
      _reportError(event, error, stackTrace);
    } on Object {
      // Error reporting is the final boundary and must not create a new
      // unhandled asynchronous failure.
    }
  }
}
