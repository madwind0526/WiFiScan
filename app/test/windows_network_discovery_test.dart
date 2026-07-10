@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/infrastructure/windows_network_discovery_service.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

void main() {
  test(
    'discovers the active private network without logging identifiers',
    () async {
      final service = WindowsNetworkDiscoveryService(
        pingTimeoutMilliseconds: 100,
        maxConcurrentProbes: 32,
      );
      final token = DiscoveryCancellationToken();
      final stages = <DiscoveryStage>[];

      final result = await service.discover(
        cancellationToken: token,
        onProgress: (progress) => stages.add(progress.stage),
      );

      expect(result.context.ipv4Address, isNotEmpty);
      expect(result.context.gateway, isNotEmpty);
      expect(result.devices, isNotEmpty);
      expect(
        result.devices.any(
          (device) => device.sources.contains(DiscoverySource.localInterface),
        ),
        isTrue,
      );
      expect(stages, contains(DiscoveryStage.probing));
      expect(stages, contains(DiscoveryStage.complete));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
