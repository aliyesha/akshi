import 'dart:async';
import 'dart:io';
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

  // The stream, size check, and deadline race to settle one result. Every
  // callback checks isCompleted because a queued stream event can still run
  // after another terminal path has won that race.
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
      if (completion.isCompleted) return;
      if (contentLength != null && received != contentLength) {
        completion.completeError(
          FormatException(
            'Response body ended after $received of $contentLength bytes.',
          ),
          StackTrace.current,
        );
        return;
      }
      completion.complete(bytes.takeBytes());
    },
  );
  // Future.timeout would stop only the caller's wait. Owning the Timer here
  // lets finally cancel both the deadline and the response subscription.
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

/// Returns the expected streamed length only when Dart is not decompressing.
///
/// A compressed response declares the compressed byte count while its stream
/// contains decompressed bytes, so those two lengths must not be compared.
int? expectedResponseBodyLength(HttpClientResponse response) =>
    response.compressionState !=
            HttpClientResponseCompressionState.decompressed &&
        response.contentLength >= 0
    ? response.contentLength
    : null;
