const tlsPortMinimum = 1;
const tlsPortMaximum = 65535;

bool isValidTlsPort(int port) =>
    port >= tlsPortMinimum && port <= tlsPortMaximum;

String? validateTlsPort(String? input) {
  final port = int.tryParse(input?.trim() ?? '');
  if (port == null || !isValidTlsPort(port)) {
    return 'Enter a port from $tlsPortMinimum to $tlsPortMaximum';
  }
  return null;
}

/// Throws at application boundaries so non-UI callers cannot persist an
/// endpoint that the socket APIs can never address.
int requireValidTlsPort(int port) {
  if (!isValidTlsPort(port)) {
    throw RangeError.range(
      port,
      tlsPortMinimum,
      tlsPortMaximum,
      'tlsPort',
    );
  }
  return port;
}
