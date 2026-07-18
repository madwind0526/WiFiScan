/// A DHCP lease entry read from the router's admin pages: the router's own
/// view of a device it assigned an address to.
///
/// This is the authoritative source for a device's hostname, which endpoint
/// scans (mDNS/SSDP) often cannot obtain. Populated only via an authenticated,
/// read-only query using credentials the user supplies.
class RouterDhcpClient {
  const RouterDhcpClient({
    required this.ipAddress,
    this.macAddress,
    this.hostname,
  });

  final String ipAddress;
  final String? macAddress;
  final String? hostname;

  /// Normalized MAC (`AA:BB:CC:DD:EE:FF`) for correlation with scan results,
  /// or null when the entry carried no usable MAC.
  String? get normalizedMac {
    final raw = macAddress;
    if (raw == null) return null;
    final compact = raw.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
    if (compact.length != 12) return null;
    return [
      for (var i = 0; i < 6; i++) compact.substring(i * 2, i * 2 + 2),
    ].join(':');
  }
}

/// Credentials for a user-owned router's admin interface. Sourced from the OS
/// secure store or a local environment variable — never guessed.
class RouterCredentials {
  const RouterCredentials({
    required this.host,
    required this.username,
    required this.password,
  });

  final String host;
  final String username;
  final String password;

  bool get isComplete => host.isNotEmpty && password.isNotEmpty;
}

/// Raised when a router admin query cannot complete. Carries a user-facing,
/// Korean message; never includes the password.
class RouterQueryException implements Exception {
  const RouterQueryException(this.message);

  final String message;

  @override
  String toString() => message;
}
