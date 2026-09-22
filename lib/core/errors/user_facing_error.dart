import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// Converts low-level failures into concise messages safe to show in the UI.
///
/// Platform resource names, SQL statements, and exception class names are
/// deliberately omitted. Detailed diagnostics belong in crash logs, not in a
/// monitor form's error banner.
String userFacingError(Object error) {
  final value = error.toString().toLowerCase();
  if (value.contains('unique constraint failed') &&
      value.contains('monitors')) {
    return 'This domain is already saved in Akshi.';
  }
  if (error is DatabaseException || value.contains('database')) {
    return 'Akshi could not save the monitor on this device. Check storage and try again.';
  }
  if (error is TimeoutException) {
    return 'The check took too long. Your monitor was not saved; try again when the connection is stable.';
  }
  if (error is SocketException || value.contains('network')) {
    return 'Akshi could not reach the information source. Your monitor was not saved; try again when online.';
  }
  if (error is PlatformException) {
    return 'The device could not complete this check. Your monitor was not saved; try again.';
  }
  if (error is FormatException || error is ArgumentError) {
    return 'Some monitor details could not be understood. Check the values and try again.';
  }
  if (error is StateError) {
    return error.message;
  }
  return 'Akshi could not finish saving this monitor. Please try again.';
}
