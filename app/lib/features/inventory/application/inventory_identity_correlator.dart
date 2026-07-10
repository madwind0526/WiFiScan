import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class CorrelatedInventory {
  const CorrelatedInventory({
    required this.devices,
    required this.newDevices,
    required this.disappearedDevices,
    required this.changedDevices,
  });

  final List<NetworkDevice> devices;
  final List<NetworkDevice> newDevices;
  final List<NetworkDevice> disappearedDevices;
  final List<NetworkDevice> changedDevices;
}

class InventoryIdentityCorrelator {
  const InventoryIdentityCorrelator();

  CorrelatedInventory correlate({
    required List<NetworkDevice> current,
    required InventorySnapshot? previous,
  }) {
    final previousByKey = <String, NetworkDevice>{};
    for (final device in previous?.devices ?? const <NetworkDevice>[]) {
      previousByKey[_identityKey(device)] = device;
    }

    final correlated = <NetworkDevice>[];
    final newDevices = <NetworkDevice>[];
    final changedDevices = <NetworkDevice>[];
    final matchedKeys = <String>{};

    for (final device in current) {
      final key = _identityKey(device);
      final oldDevice = previousByKey[key];
      final merged = device.copyWith(
        id: oldDevice?.id ?? key,
        firstSeenAt: oldDevice?.firstSeenAt ?? device.firstSeenAt,
      );
      correlated.add(merged);
      matchedKeys.add(key);
      if (oldDevice == null) {
        newDevices.add(merged);
      } else if (_fingerprint(oldDevice) != _fingerprint(merged)) {
        changedDevices.add(merged);
      }
    }

    final disappeared = previousByKey.entries
        .where((entry) => !matchedKeys.contains(entry.key))
        .map((entry) => entry.value)
        .toList(growable: false);

    return CorrelatedInventory(
      devices: correlated,
      newDevices: previous == null ? const [] : newDevices,
      disappearedDevices: previous == null ? const [] : disappeared,
      changedDevices: previous == null ? const [] : changedDevices,
    );
  }

  String identityKey(NetworkDevice device) => _identityKey(device);

  static String _identityKey(NetworkDevice device) {
    final mac = device.macAddress?.replaceAll(':', '').toLowerCase();
    if (mac != null && mac.length == 12) return 'mac:$mac';
    if (device.sources.contains(DiscoverySource.localInterface)) {
      return 'local-interface';
    }
    final address = device.ipAddresses.isEmpty
        ? device.id
        : device.ipAddresses.first;
    return 'ip:$address';
  }

  static String _fingerprint(NetworkDevice device) {
    final addresses = [...device.ipAddresses]..sort();
    final sources = device.sources.map((source) => source.name).toList()
      ..sort();
    return [
      device.displayName,
      device.category.name,
      device.ownershipStatus.name,
      addresses.join(','),
      device.macAddress ?? '',
      device.vendor ?? '',
      sources.join(','),
    ].join('|');
  }
}
