import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// Converts low-level check failures into concise messages safe for the UI.
///
/// Platform resource names and exception types remain in diagnostic logs, not
/// in status banners.
String checkUserFacingError(Object error) {
  final value = error.toString().toLowerCase();
  if (error is TimeoutException) {
    return 'The check took too long. Try again when the connection is stable.';
  }
  if (error is SocketException ||
      value.contains('network') ||
      value.contains('failed host lookup')) {
    return 'Akshi could not reach the information source. Check the connection and try again.';
  }
  if (error is PlatformException) {
    return 'The device could not complete this check. Please try again.';
  }
  if (error is FormatException || error is ArgumentError) {
    return 'The returned information could not be understood. Please try again later.';
  }
  if (error is StateError) {
    return error.message;
  }
  return 'Akshi could not finish this check. Please try again.';
}

/// Converts failures from the transactional add/edit workflow for the UI.
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
