import 'dart:io';

import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/infrastructure/windows_network_discovery_service.dart';

NetworkDiscoveryService createNetworkDiscoveryService() {
  if (Platform.isWindows) {
    return const WindowsNetworkDiscoveryService();
  }
  return const _UnsupportedNetworkDiscoveryService();
}

class _UnsupportedNetworkDiscoveryService implements NetworkDiscoveryService {
  const _UnsupportedNetworkDiscoveryService();

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) {
    throw const DiscoveryUnavailableException(
      '이 플랫폼의 네트워크 탐색 기능은 아직 준비되지 않았습니다.',
    );
  }
}
