import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

void main() {
  test(
    'merges independent enrichment evidence into discovered devices',
    () async {
      final result = DiscoveryResult(
        context: const NetworkContext(
          interfaceName: 'Wi-Fi',
          interfaceIndex: 1,
          ipv4Address: '192.168.0.10',
          prefixLength: 24,
          gateway: '192.168.0.1',
          scannedNetwork: '192.168.0.0',
          scannedPrefixLength: 24,
          coverageLimited: false,
        ),
        devices: [
          NetworkDevice(
            id: 'ip:192.168.0.20',
            displayName: '확인되지 않은 장비',
            category: DeviceCategory.unknown,
            ownershipStatus: OwnershipStatus.unconfirmed,
            ipAddresses: const ['192.168.0.20'],
            sources: const [DiscoverySource.neighbor],
            firstSeenAt: DateTime(2026, 7, 15),
            lastSeenAt: DateTime(2026, 7, 15),
            identityConfidence: 0.6,
          ),
        ],
        limitations: const [],
        duration: Duration.zero,
      );
      const enricher = NetworkInformationEnricher(
        providers: [_FakeEnrichmentProvider(), _FailingEnrichmentProvider()],
      );

      final enriched = await enricher.enrich(
        result,
        cancellationToken: DiscoveryCancellationToken(),
      );

      final device = enriched.devices.single;
      expect(device.displayName, '거실 프린터');
      expect(device.vendor, 'Example Devices');
      expect(device.modelName, 'Printer 2000');
      expect(device.category, DeviceCategory.printer);
      expect(device.hostnames, contains('printer.local'));
      expect(device.sources, contains(DiscoverySource.mdns));
      expect(device.services.single.port, 631);
      expect(device.identityConfidence, closeTo(0.7, 0.001));
    },
  );
}

class _FakeEnrichmentProvider implements NetworkEnrichmentProvider {
  const _FakeEnrichmentProvider();

  @override
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    return const [
      DeviceEnrichment(
        ipAddress: '192.168.0.20',
        displayName: '거실 프린터',
        vendor: 'Example Devices',
        modelName: 'Printer 2000',
        category: DeviceCategory.printer,
        hostnames: ['printer.local'],
        services: [
          NetworkServiceObservation(
            protocol: 'ipp',
            port: 631,
            transport: NetworkTransport.tcp,
            source: DiscoverySource.mdns,
          ),
        ],
        sources: [DiscoverySource.mdns],
      ),
    ];
  }
}

class _FailingEnrichmentProvider implements NetworkEnrichmentProvider {
  const _FailingEnrichmentProvider();

  @override
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) {
    throw StateError('Test provider failure');
  }
}
