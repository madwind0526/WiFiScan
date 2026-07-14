import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/infrastructure/tcp_service_probe_provider.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

void main() {
  test('records only open ports without sending service payloads', () async {
    final attempts = <String>[];
    final provider = TcpServiceProbeProvider(
      ports: const {23: 'telnet', 443: 'https', 9100: 'printer'},
      connector: (address, port, timeout) async {
        attempts.add('$address:$port');
        return port == 23 || port == 9100;
      },
    );

    final results = await provider.collect(
      targetAddresses: const {'192.168.0.40'},
      cancellationToken: DiscoveryCancellationToken(),
    );

    expect(attempts, hasLength(3));
    expect(results.single.category, DeviceCategory.printer);
    expect(
      results.single.services.map((service) => service.port),
      containsAll([23, 9100]),
    );
    expect(results.single.sources, contains(DiscoverySource.serviceProbe));
  });
}
