import 'dart:async';
import 'dart:typed_data';

/// Reads an HTTP response body within declared, streamed, and elapsed limits.
///
/// [contentLength] is null when the server did not declare a length. The actual
/// streamed bytes are always counted, so chunked and inaccurate responses are
/// held to the same boundary.
Future<Uint8List> readBoundedResponseBody(
  Stream<List<int>> body, {
  required int maximumBytes,
  required Duration timeout,
  required int? contentLength,
}) async {
  if (maximumBytes <= 0) {
    throw RangeError.value(maximumBytes, 'maximumBytes', 'Must be positive');
  }
  if (timeout.inMicroseconds <= 0) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
  }
  if (contentLength != null && contentLength < 0) {
    throw RangeError.value(
      contentLength,
      'contentLength',
      'Use null when the length is unknown',
    );
  }

  if (contentLength != null && contentLength > maximumBytes) {
    await cancelResponseBody(body);
    throw FormatException(
      'Response body exceeds the $maximumBytes-byte limit.',
    );
  }

  final bytes = BytesBuilder(copy: false);
  final completion = Completer<Uint8List>();
  var received = 0;

  final subscription = body.listen(
    (chunk) {
      if (completion.isCompleted) return;
      received += chunk.length;
      if (received > maximumBytes) {
        completion.completeError(
          FormatException(
            'Response body exceeds the $maximumBytes-byte limit.',
          ),
          StackTrace.current,
        );
        return;
      }
      bytes.add(chunk);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completion.isCompleted) {
        completion.completeError(error, stackTrace);
      }
    },
    onDone: () {
      if (!completion.isCompleted) {
        completion.complete(bytes.takeBytes());
      }
    },
  );
  final deadline = Timer(timeout, () {
    if (!completion.isCompleted) {
      completion.completeError(
        TimeoutException('Response body timed out.', timeout),
        StackTrace.current,
      );
    }
  });

  try {
    return await completion.future;
  } finally {
    deadline.cancel();
    await subscription.cancel();
  }
}

/// Cancels a response body that the caller intentionally does not consume.
Future<void> cancelResponseBody(Stream<List<int>> body) =>
    body.listen(null).cancel();
