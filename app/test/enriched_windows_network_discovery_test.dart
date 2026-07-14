@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/infrastructure/platform_network_discovery_service.dart';

void main() {
  test(
    'runs the complete Windows discovery and enrichment pipeline',
    () async {
      final stages = <DiscoveryStage>[];
      final result = await createNetworkDiscoveryService().discover(
        cancellationToken: DiscoveryCancellationToken(),
        onProgress: (progress) => stages.add(progress.stage),
      );

      expect(result.devices, isNotEmpty);
      expect(stages, contains(DiscoveryStage.probing));
      expect(stages.last, DiscoveryStage.complete);
      expect(
        result.limitations,
        contains('장비 이름과 서비스 정보는 장비가 공개적으로 응답한 범위만 표시합니다.'),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
