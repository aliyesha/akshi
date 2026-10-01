import 'package:flutter/services.dart';

/// Opens Akshi-owned HTTPS links through the host operating system.
abstract final class ExternalLinkService {
  static const MethodChannel _channel = MethodChannel(
    'com.aliyesha.akshi/external_links',
  );

  static Future<void> openHttps(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'A valid HTTPS URL is required');
    }
    final opened = await _channel.invokeMethod<bool>('open', <String, Object?>{
      'url': uri.toString(),
    });
    if (opened != true) {
      throw StateError('No application could open the link');
    }
  }
}
