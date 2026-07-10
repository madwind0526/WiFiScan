import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class InventorySnapshot {
  const InventorySnapshot({
    required this.scannedAt,
    required this.networkKey,
    required this.context,
    required this.devices,
    required this.limitations,
  });

  final DateTime scannedAt;
  final String networkKey;
  final NetworkContext context;
  final List<NetworkDevice> devices;
  final List<String> limitations;

  Map<String, Object?> toJson() {
    return {
      'scannedAt': scannedAt.toIso8601String(),
      'networkKey': networkKey,
      'context': context.toJson(),
      'devices': devices.map((device) => device.toJson()).toList(),
      'limitations': limitations,
    };
  }

  factory InventorySnapshot.fromJson(Map<String, Object?> json) {
    final rawContext = json['context'];
    final rawDevices = json['devices'];
    return InventorySnapshot(
      scannedAt:
          DateTime.tryParse(json['scannedAt']?.toString() ?? '') ??
          DateTime.now(),
      networkKey: json['networkKey']?.toString() ?? '',
      context: rawContext is Map
          ? NetworkContext.fromJson(rawContext.cast<String, Object?>())
          : const NetworkContext(
              interfaceName: '알 수 없음',
              interfaceIndex: -1,
              ipv4Address: '',
              prefixLength: 24,
              gateway: '',
              scannedNetwork: '',
              scannedPrefixLength: 24,
              coverageLimited: true,
            ),
      devices: rawDevices is List
          ? rawDevices
                .whereType<Map>()
                .map(
                  (item) =>
                      NetworkDevice.fromJson(item.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const [],
      limitations: _stringList(json['limitations']),
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}
