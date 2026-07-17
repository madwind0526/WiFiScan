import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/inventory/application/device_label_repository.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class _MemoryLabelStore implements DeviceLabelStore {
  Map<String, DeviceLabel> data = {};

  @override
  Future<Map<String, DeviceLabel>> load() async => {...data};

  @override
  Future<void> save(Map<String, DeviceLabel> labels) async {
    data = {...labels};
  }
}

NetworkDevice _device({
  String id = 'd',
  String displayName = '확인되지 않은 장비',
  String? mac = '88:36:6C:C1:D6:84',
  List<String> ips = const ['192.168.0.40'],
  OwnershipStatus ownership = OwnershipStatus.unconfirmed,
}) {
  return NetworkDevice(
    id: id,
    displayName: displayName,
    category: DeviceCategory.unknown,
    ownershipStatus: ownership,
    ipAddresses: ips,
    sources: const [DiscoverySource.neighbor],
    firstSeenAt: DateTime(2026, 7, 17),
    lastSeenAt: DateTime(2026, 7, 17),
    identityConfidence: 0.85,
    macAddress: mac,
  );
}

void main() {
  test('applies a saved name and ownership onto a device', () async {
    final store = _MemoryLabelStore();
    final repo = DeviceLabelRepository(store: store);
    await repo.ensureLoaded();

    await repo.setLabel(
      _device(),
      const DeviceLabel(
        name: '거실 스마트플러그',
        ownershipStatus: OwnershipStatus.confirmed,
      ),
    );

    final applied = repo.apply(_device(displayName: 'Espressif'));
    expect(applied.displayName, '거실 스마트플러그');
    expect(applied.ownershipStatus, OwnershipStatus.confirmed);
  });

  test('re-attaches a label by MAC even when the IP changes', () async {
    final store = _MemoryLabelStore();
    final repo = DeviceLabelRepository(store: store);
    await repo.ensureLoaded();
    await repo.setLabel(_device(), const DeviceLabel(name: '내 노트북'));

    final moved = repo.apply(_device(ips: const ['192.168.0.99']));
    expect(moved.displayName, '내 노트북');
  });

  test('falls back to an IP key when the device has no MAC', () async {
    final store = _MemoryLabelStore();
    final repo = DeviceLabelRepository(store: store);
    await repo.ensureLoaded();
    await repo.setLabel(
      _device(mac: null),
      const DeviceLabel(name: 'IP 기반 장비'),
    );

    expect(repo.apply(_device(mac: null)).displayName, 'IP 기반 장비');
  });

  test('clearing a label reverts to the automatic name and persists', () async {
    final store = _MemoryLabelStore();
    final repo = DeviceLabelRepository(store: store);
    await repo.ensureLoaded();
    await repo.setLabel(_device(), const DeviceLabel(name: '임시 이름'));
    await repo.setLabel(_device(), const DeviceLabel());

    expect(repo.apply(_device(displayName: 'Apple')).displayName, 'Apple');
    expect(store.data, isEmpty);
  });

  test('a reloaded repository re-applies persisted labels', () async {
    final store = _MemoryLabelStore();
    final first = DeviceLabelRepository(store: store);
    await first.ensureLoaded();
    await first.setLabel(_device(), const DeviceLabel(name: '안방 TV'));

    final reloaded = DeviceLabelRepository(store: store);
    await reloaded.ensureLoaded();
    expect(reloaded.apply(_device()).displayName, '안방 TV');
  });
}
