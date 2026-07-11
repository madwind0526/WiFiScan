import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

class NetworkConnectionException implements Exception {
  const NetworkConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class NetworkConnectionService {
  Future<List<NetworkProfile>> discoverAvailableProfiles();

  Future<String?> currentSsid();

  Future<void> connect(NetworkProfile profile);

  Future<void> restore(String? ssid);
}
