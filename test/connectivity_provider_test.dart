import 'dart:async';

import 'package:akshi/app/providers.dart';
import 'package:akshi/core/services/check_failure_classifier.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live offline state clears when a network transport returns', () async {
    final connectivity = _FakeConnectivitySource(const <ConnectivityResult>[
      ConnectivityResult.none,
    ]);
    final container = ProviderContainer(
      overrides: [connectivitySourceProvider.overrideWithValue(connectivity)],
    );
    final online = Completer<void>();
    final seen = <bool>[];
    final subscription = container.listen(
      deviceOfflineProvider,
      (_, next) => next.whenData((offline) {
        seen.add(offline);
        if (!offline && !online.isCompleted) online.complete();
      }),
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await connectivity.close();
    });

    expect(await container.read(deviceOfflineProvider.future), isTrue);

    await connectivity.listening.timeout(const Duration(seconds: 1));
    connectivity.emit(const <ConnectivityResult>[ConnectivityResult.wifi]);
    await online.future.timeout(const Duration(seconds: 1));

    expect(container.read(deviceOfflineProvider).value, isFalse);
    expect(seen, <bool>[true, false]);
  });

  test('only no transports is offline', () {
    expect(connectivityIsOffline(const <ConnectivityResult>[]), isTrue);
    expect(
      connectivityIsOffline(const <ConnectivityResult>[
        ConnectivityResult.none,
      ]),
      isTrue,
    );
    expect(
      connectivityIsOffline(const <ConnectivityResult>[
        ConnectivityResult.wifi,
        ConnectivityResult.none,
      ]),
      isFalse,
    );
  });
}

final class _FakeConnectivitySource implements ConnectivitySource {
  _FakeConnectivitySource(this.current) {
    _changes = StreamController<List<ConnectivityResult>>.broadcast(
      onListen: _markListening,
    );
  }

  List<ConnectivityResult> current;
  final _listening = Completer<void>();
  late final StreamController<List<ConnectivityResult>> _changes;

  Future<void> get listening => _listening.future;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  void emit(List<ConnectivityResult> states) {
    current = states;
    _changes.add(states);
  }

  Future<void> close() => _changes.close();

  void _markListening() {
    if (!_listening.isCompleted) _listening.complete();
  }
}
