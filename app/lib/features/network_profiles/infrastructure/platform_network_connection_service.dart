import 'dart:io';

import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/android_network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/windows_network_connection_service.dart';

NetworkConnectionService createNetworkConnectionService() {
  if (Platform.isWindows) return const WindowsNetworkConnectionService();
  if (Platform.isAndroid) return const AndroidNetworkConnectionService();
  return const _UnsupportedNetworkConnectionService();
}

class _UnsupportedNetworkConnectionService implements NetworkConnectionService {
  const _UnsupportedNetworkConnectionService();

  @override
  Future<List<NetworkProfile>> discoverAvailableProfiles() async => const [];

  @override
  Future<Map<String, String>> savedPasswords() async => const {};

  @override
  Future<String?> currentSsid() async => null;

  @override
  Future<WifiBand> currentBand() async => WifiBand.unknown;

  @override
  Future<void> connect(NetworkProfile profile) async {
    throw const NetworkConnectionException(
      '이 기기에서는 앱이 Wi-Fi를 자동 전환할 수 없습니다. 시스템 Wi-Fi 화면에서 연결한 뒤 다시 검색하세요.',
    );
  }

  @override
  Future<void> restore(String? ssid) async {}
}
