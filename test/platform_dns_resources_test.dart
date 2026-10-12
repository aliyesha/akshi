import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS waits past an intermediate CNAME for the requested RRset', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final recordClassGuard = appDelegate.indexOf(
      'guard recordClass == UInt16(kDNSServiceClass_IN)',
    );
    final requestedTypeBranch = appDelegate.indexOf(
      'if recordType != type',
      recordClassGuard,
    );
    final cnameGuard = appDelegate.indexOf(
      'guard recordType == UInt16(kDNSServiceType_CNAME)',
      requestedTypeBranch,
    );
    final emptyDataGuard = appDelegate.indexOf('guard let data', cnameGuard);

    expect(recordClassGuard, greaterThanOrEqualTo(0));
    expect(requestedTypeBranch, greaterThan(recordClassGuard));
    expect(cnameGuard, greaterThan(requestedTypeBranch));
    expect(emptyDataGuard, greaterThan(cnameGuard));
  });
}
