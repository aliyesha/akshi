import 'dart:async';
import 'dart:io';

import 'package:akshi/core/services/bounded_response_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a GET request completed after timeout is aborted', () async {
    final client = _DelayedHttpClient();
    final operation = openHttpGetRequest(
      client,
      Uri.https('example.com', '/'),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(operation, throwsA(isA<TimeoutException>()));

    final request = _DelayedHttpRequest();
    client.complete(request);
    await Future<void>.delayed(Duration.zero);

    expect(request.wasAborted, isTrue);
  });

  test('a request with stalled response headers is aborted', () async {
    final request = _DelayedHttpRequest();

    await expectLater(
      sendHttpRequest(request, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );

    expect(request.wasAborted, isTrue);
  });
}

final class _DelayedHttpClient implements HttpClient {
  final _request = Completer<HttpClientRequest>();

  void complete(HttpClientRequest request) => _request.complete(request);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _request.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DelayedHttpRequest implements HttpClientRequest {
  final _response = Completer<HttpClientResponse>();
  var wasAborted = false;
  var _closeStarted = false;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() {
    _closeStarted = true;
    return _response.future;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    wasAborted = true;
    if (!_closeStarted || _response.isCompleted) return;
    _response.completeError(
      exception ?? const HttpException('Request aborted'),
      stackTrace ?? StackTrace.empty,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
