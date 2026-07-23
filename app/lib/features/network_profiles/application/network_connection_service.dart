import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

class NetworkConnectionException implements Exception {
  const NetworkConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum WifiBand {
  ghz24('2.4G'),
  ghz5('5.0G'),
  ghz6('6.0G'),
  unknown('');

  const WifiBand(this.label);

  final String label;
}

abstract interface class NetworkConnectionService {
  Future<List<NetworkProfile>> discoverAvailableProfiles();

  /// Wi-Fi passphrases the operating system already has saved, keyed by SSID.
  ///
  /// Only platforms that expose the user's own saved credentials return
  /// anything. Android deliberately does not: saved passphrases live in
  /// system-only storage and its API redacts them, so it returns an empty map
  /// and the user imports networks another way.
  Future<Map<String, String>> savedPasswords();

  Future<String?> currentSsid();

  /// Reads the radio band of the currently connected interface.
  ///
  /// Band cannot be derived reliably from an SSID name, so it is measured from
  /// the live connection while a scan is running. Returns [WifiBand.unknown]
  /// when the platform cannot report it.
  Future<WifiBand> currentBand();

  Future<void> connect(NetworkProfile profile);

  Future<void> restore(String? ssid);
}
