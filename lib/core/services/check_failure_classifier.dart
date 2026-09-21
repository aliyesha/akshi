import 'dart:async';
import 'dart:io';

import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

class CheckFailureClassifier {
  CheckFailureClassifier({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> get deviceIsOffline async {
    try {
      final states = await _connectivity.checkConnectivity();
      return states.isEmpty ||
          states.every((state) => state == ConnectivityResult.none);
    } on Object {
      return false;
    }
  }

  Future<CheckFailure> classify(
    Object error, {
    required DateTime occurredAt,
    required String source,
    bool tls = false,
  }) async {
    if (await deviceIsOffline) {
      return CheckFailure(
        kind: CheckFailureKind.offline,
        message: 'No network connection. Showing the last saved result.',
        occurredAt: occurredAt,
      );
    }
    if (error is TimeoutException) {
      return CheckFailure(
        kind: CheckFailureKind.timeout,
        message: '$source did not respond in time.',
        occurredAt: occurredAt,
      );
    }
    if (error is PlatformException && error.code == 'dns_error') {
      return CheckFailure(
        kind: CheckFailureKind.dns,
        message: 'The system DNS resolver could not complete this lookup.',
        occurredAt: occurredAt,
      );
    }
    if (error is SocketException) {
      final message = error.message.toLowerCase();
      final dns =
          message.contains('failed host lookup') ||
          message.contains('name or service not known') ||
          message.contains('nodename nor servname');
      return CheckFailure(
        kind: dns ? CheckFailureKind.dns : CheckFailureKind.internetUnavailable,
        message: dns
            ? '$source could not be resolved through DNS.'
            : 'Internet access appears unavailable or restricted.',
        occurredAt: occurredAt,
      );
    }
    if (error is FormatException) {
      return CheckFailure(
        kind: CheckFailureKind.invalidResponse,
        message: '$source returned information Akshi could not read.',
        occurredAt: occurredAt,
      );
    }
    if (tls || error is HandshakeException || error is TlsException) {
      return CheckFailure(
        kind: CheckFailureKind.tls,
        message: _cleanMessage(error, fallback: 'The TLS connection failed.'),
        occurredAt: occurredAt,
      );
    }
    return CheckFailure(
      kind: CheckFailureKind.sourceUnavailable,
      message: _cleanMessage(
        error,
        fallback: '$source is currently unavailable.',
      ),
      occurredAt: occurredAt,
    );
  }
}

String _cleanMessage(Object error, {required String fallback}) {
  final value = error
      .toString()
      .replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '')
      .trim();
  return value.isEmpty ? fallback : value;
}
