import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/infrastructure/windows_netbios_enrichment_provider.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

void main() {
  test('parses the workstation name from a NetBIOS name table', () {
    const output = '''
       NetBIOS Remote Machine Name Table

           Name               Type         Status
        ---------------------------------------------
        LIVINGROOM-PC  <00>  UNIQUE      Registered
        WORKGROUP      <00>  GROUP       Registered
        LIVINGROOM-PC  <20>  UNIQUE      Registered
    ''';

    final identity = WindowsNetbiosEnrichmentProvider.parseNetbiosNameTable(
      output,
    );

    expect(identity?.name, 'LIVINGROOM-PC');
    expect(identity?.hasServerService, isTrue);
  });

  test('adds a public NetBIOS name without exposing other targets', () async {
    final provider = WindowsNetbiosEnrichmentProvider(
      runner: (address, timeout) async => ProcessResult(
        1,
        0,
        'MEDIA-PC       <20>  UNIQUE      Registered',
        '',
      ),
    );

    final results = await provider.collect(
      targetAddresses: const {'192.168.0.20', '203.0.113.5'},
      cancellationToken: DiscoveryCancellationToken(),
    );

    expect(results, hasLength(1));
    expect(results.single.ipAddress, '192.168.0.20');
    expect(results.single.displayName, 'MEDIA-PC');
    expect(results.single.category, DeviceCategory.computer);
    expect(results.single.sources, [DiscoverySource.netbios]);
  });
}
