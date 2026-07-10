import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

void main() {
  test('uses the first scan as a baseline and detects later changes', () async {
    final repository = InventoryRepository(store: _MemorySnapshotStore());
    final firstScan = await repository.record(
      _result(
        devices: [
          _device(
            id: 'ip:192.168.0.2',
            ip: '192.168.0.2',
            mac: 'AA:BB:CC:DD:EE:02',
            seenAt: DateTime(2026, 7, 11, 10),
          ),
        ],
      ),
    );

    final secondScan = await repository.record(
      _result(
        devices: [
          _device(
            id: 'ip:192.168.0.3',
            ip: '192.168.0.3',
            mac: 'AA:BB:CC:DD:EE:02',
            seenAt: DateTime(2026, 7, 11, 11),
          ),
          _device(
            id: 'ip:192.168.0.4',
            ip: '192.168.0.4',
            mac: 'AA:BB:CC:DD:EE:04',
            seenAt: DateTime(2026, 7, 11, 11),
          ),
        ],
      ),
    );

    expect(firstScan.isBaseline, isTrue);
    expect(firstScan.newDevices, isEmpty);
    expect(secondScan.isBaseline, isFalse);
    expect(secondScan.newDevices, hasLength(1));
    expect(secondScan.changedDevices, hasLength(1));
    expect(secondScan.newDevices.single.macAddress, 'AA:BB:CC:DD:EE:04');
    expect(
      secondScan.changedDevices.single.firstSeenAt,
      DateTime(2026, 7, 11, 10),
    );
    expect(secondScan.changedDevices.single.ipAddresses, ['192.168.0.3']);
  });
}

DiscoveryResult _result({required List<NetworkDevice> devices}) {
  return DiscoveryResult(
    context: const NetworkContext(
      interfaceName: 'Wi-Fi',
      interfaceIndex: 1,
      ipv4Address: '192.168.0.30',
      prefixLength: 24,
      gateway: '192.168.0.1',
      scannedNetwork: '192.168.0.0',
      scannedPrefixLength: 24,
      coverageLimited: false,
    ),
    devices: devices,
    limitations: const [],
    duration: Duration.zero,
  );
}

NetworkDevice _device({
  required String id,
  required String ip,
  required String mac,
  required DateTime seenAt,
}) {
  return NetworkDevice(
    id: id,
    displayName: '테스트 장비',
    category: DeviceCategory.unknown,
    ownershipStatus: OwnershipStatus.unconfirmed,
    ipAddresses: [ip],
    sources: const [DiscoverySource.neighbor],
    firstSeenAt: seenAt,
    lastSeenAt: seenAt,
    identityConfidence: 0.8,
    macAddress: mac,
  );
}

class _MemorySnapshotStore implements InventorySnapshotStore {
  final List<InventorySnapshot> snapshots = [];

  @override
  Future<List<InventorySnapshot>> load() async => [...snapshots];

  @override
  Future<void> save(List<InventorySnapshot> value) async {
    snapshots
      ..clear()
      ..addAll(value);
  }
}
