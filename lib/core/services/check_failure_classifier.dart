import 'dart:async';
import 'dart:io';

import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/monitors/domain/check_activity.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

/// Converts low-level network failures into stable, user-facing check states.
///
/// Classification keeps the last successful observation meaningful when the
/// device is offline or a public source is temporarily unavailable.
class CheckFailureClassifier {
  CheckFailureClassifier({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Reports whether every connectivity result currently indicates no network.
  Future<bool> get deviceIsOffline async {
    try {
      final states = await _connectivity.checkConnectivity();
      return states.isEmpty ||
          states.every((state) => state == ConnectivityResult.none);
    } catch (error, stackTrace) {
      appLogger.error('service.connectivity.check.failed', error, stackTrace);
      return false;
    }
  }

  /// Classifies an error with source context and the time it occurred.
  ///
  /// TLS failures are kept distinct from DNS and general source failures so
  /// the UI can explain the appropriate recovery action.
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

/// Removes exception type noise while retaining a useful source message.
String _cleanMessage(Object error, {required String fallback}) {
  final value = error
      .toString()
      .replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '')
      .trim();
  return value.isEmpty ? fallback : value;
}
