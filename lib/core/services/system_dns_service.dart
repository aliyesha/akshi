import 'dart:async';

import 'package:flutter/services.dart';

enum DnsRecordType {
  txt(16),
  mx(15);

  const DnsRecordType(this.code);
  final int code;
}

class MxRecord {
  const MxRecord({required this.preference, required this.exchange});

  final int preference;
  final String exchange;
}

class SystemDnsService {
  const SystemDnsService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.akshi.monitor/dns');

  final MethodChannel _channel;

  Future<List<String>> txt(String name) async {
    final records = await _query(name, DnsRecordType.txt);
    return records.map(_decodeTxt).whereType<String>().toList(growable: false);
  }

  Future<List<MxRecord>> mx(String name) async {
    final records = await _query(name, DnsRecordType.mx);
    final result = records.map(_decodeMx).whereType<MxRecord>().toList();
    result.sort((left, right) => left.preference.compareTo(right.preference));
    return result;
  }

  Future<List<Uint8List>> _query(String name, DnsRecordType type) async {
    final response = await _channel
        .invokeMapMethod<String, Object?>('query', <String, Object?>{
          'name': name,
          'type': type.code,
        })
        .timeout(const Duration(seconds: 10));
    if (response == null) throw const FormatException('Empty DNS response');
    final records = response['records'];
    if (records is! List) throw const FormatException('Invalid DNS response');
    return records
        .whereType<Uint8List>()
        .map(Uint8List.fromList)
        .toList(growable: false);
  }
}

String? _decodeTxt(Uint8List data) {
  final buffer = StringBuffer();
  var offset = 0;
  while (offset < data.length) {
    final length = data[offset++];
    if (offset + length > data.length) return null;
    buffer.write(String.fromCharCodes(data.sublist(offset, offset + length)));
    offset += length;
  }
  return buffer.toString();
}

MxRecord? _decodeMx(Uint8List data) {
  if (data.length < 3) return null;
  final preference = (data[0] << 8) | data[1];
  final labels = <String>[];
  var offset = 2;
  while (offset < data.length) {
    final length = data[offset++];
    if (length == 0) break;
    if ((length & 0xC0) != 0 || offset + length > data.length) return null;
    labels.add(String.fromCharCodes(data.sublist(offset, offset + length)));
    offset += length;
  }
  return MxRecord(
    preference: preference,
    exchange: labels.isEmpty ? '.' : labels.join('.').toLowerCase(),
  );
}
