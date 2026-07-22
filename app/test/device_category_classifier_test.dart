import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/domain/device_category_classifier.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

NetworkDevice _named(String name) => NetworkDevice(
  id: name,
  displayName: name,
  category: DeviceCategory.unknown,
  ownershipStatus: OwnershipStatus.unconfirmed,
  ipAddresses: const ['192.168.0.2'],
  sources: const [DiscoverySource.router],
  firstSeenAt: DateTime(2026, 7, 18),
  lastSeenAt: DateTime(2026, 7, 18),
  identityConfidence: 0.7,
);

void main() {
  test('classifies router-provided device names', () {
    expect(inferDeviceCategory(_named('Samsung-Refrigerator')),
        DeviceCategory.iot);
    expect(inferDeviceCategory(_named('Samsung-Air-Purifier')),
        DeviceCategory.iot);
    expect(inferDeviceCategory(_named('Samsung-Jet-Bot-Vacuum-Cleaner')),
        DeviceCategory.iot);
    expect(inferDeviceCategory(_named('BID-AT200/IPTV/STB')),
        DeviceCategory.television);
    expect(inferDeviceCategory(_named('hyojeong-ui-Z-Flip7')),
        DeviceCategory.phone);
    expect(inferDeviceCategory(_named('SM-L505N')), DeviceCategory.phone);
    expect(inferDeviceCategory(_named('Tuya Smart Plug')), DeviceCategory.iot);
  });

  test('returns null for unrecognizable names', () {
    expect(inferDeviceCategory(_named('madwind99')), isNull);
    expect(inferDeviceCategory(_named('linar-thing')), isNull);
  });
}
