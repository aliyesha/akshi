import 'dart:async';
import 'dart:collection';

/// A fair, dynamically sized concurrency window for external I/O.
///
/// Operations start immediately while fewer than [maximum] are active. Further
/// operations wait in FIFO order and receive a slot as soon as one finishes.
/// The gate never creates work to fill the window; it only caps work requested
/// by enabled monitor checks.
class AsyncConcurrencyGate {
  AsyncConcurrencyGate({required this.maximum}) {
    if (maximum < 1) {
      throw RangeError.range(maximum, 1, null, 'maximum');
    }
  }

  final int maximum;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  int get activeCount => _active;
  int get waitingCount => _waiters.length;

  Future<T> run<T>(Future<T> Function() operation) async {
    await _acquire();
    try {
      return await operation();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maximum) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
