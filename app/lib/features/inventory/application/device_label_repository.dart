import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

/// A user-assigned label for a device: a chosen name and/or ownership state.
///
/// Persisted independently of scan snapshots so a name survives across scans
/// and disappearing/reappearing devices. Keyed by the device's stable
/// identity (MAC when available), so the label re-attaches even when the
/// device's IP changes.
class DeviceLabel {
  const DeviceLabel({this.name, this.ownershipStatus});

  final String? name;
  final OwnershipStatus? ownershipStatus;

  bool get isEmpty =>
      (name == null || name!.trim().isEmpty) && ownershipStatus == null;

  DeviceLabel copyWith({
    String? name,
    bool clearName = false,
    OwnershipStatus? ownershipStatus,
    bool clearOwnership = false,
  }) {
    return DeviceLabel(
      name: clearName ? null : (name ?? this.name),
      ownershipStatus: clearOwnership
          ? null
          : (ownershipStatus ?? this.ownershipStatus),
    );
  }

  Map<String, Object?> toJson() => {
    if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
    if (ownershipStatus != null) 'ownershipStatus': ownershipStatus!.name,
  };

  factory DeviceLabel.fromJson(Map<String, Object?> json) {
    final rawOwnership = json['ownershipStatus']?.toString();
    OwnershipStatus? ownership;
    for (final value in OwnershipStatus.values) {
      if (value.name == rawOwnership) {
        ownership = value;
        break;
      }
    }
    return DeviceLabel(
      name: json['name']?.toString(),
      ownershipStatus: ownership,
    );
  }
}

/// The stable key a label is stored under. Prefers the MAC address; falls back
/// to the first IP address when no MAC is known (a weaker, address-bound key).
String? deviceLabelKey(NetworkDevice device) {
  final mac = device.macAddress?.trim();
  if (mac != null && mac.isNotEmpty) return 'mac:${mac.toUpperCase()}';
  if (device.ipAddresses.isNotEmpty) {
    final ip = device.ipAddresses.first.trim();
    if (ip.isNotEmpty) return 'ip:$ip';
  }
  return null;
}

abstract interface class DeviceLabelStore {
  Future<Map<String, DeviceLabel>> load();

  Future<void> save(Map<String, DeviceLabel> labels);
}

class FileDeviceLabelStore implements DeviceLabelStore {
  const FileDeviceLabelStore();

  @override
  Future<Map<String, DeviceLabel>> load() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      final labels = <String, DeviceLabel>{};
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          final label = DeviceLabel.fromJson(value.cast<String, Object?>());
          if (!label.isEmpty) labels[key] = label;
        }
      });
      return labels;
    } on FormatException {
      return {};
    } on FileSystemException {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, DeviceLabel> labels) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final retained = {
      for (final entry in labels.entries)
        if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
    };
    await file.writeAsString(jsonEncode(retained), flush: true);
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}device_labels.json',
    );
  }
}

/// In-memory cache over a [DeviceLabelStore] that applies stored labels onto
/// freshly discovered devices and persists edits.
class DeviceLabelRepository {
  DeviceLabelRepository({DeviceLabelStore? store})
    : _store = store ?? const FileDeviceLabelStore();

  final DeviceLabelStore _store;
  Map<String, DeviceLabel>? _cache;

  Future<Map<String, DeviceLabel>> _labels() async {
    return _cache ??= await _store.load();
  }

  /// Loads labels into the cache. Call once before the first apply.
  Future<void> ensureLoaded() => _labels();

  /// Overlays the user's name and ownership onto [device].
  ///
  /// A user-chosen name always wins over automatic identification, so an
  /// assigned label survives even when a later scan finds new evidence.
  NetworkDevice apply(NetworkDevice device) {
    final key = deviceLabelKey(device);
    final label = key == null ? null : _cache?[key];
    if (label == null || label.isEmpty) return device;
    return device.copyWith(
      displayName: label.name != null && label.name!.trim().isNotEmpty
          ? label.name!.trim()
          : device.displayName,
      ownershipStatus: label.ownershipStatus ?? device.ownershipStatus,
    );
  }

  List<NetworkDevice> applyAll(Iterable<NetworkDevice> devices) =>
      [for (final device in devices) apply(device)];

  DeviceLabel labelFor(NetworkDevice device) {
    final key = deviceLabelKey(device);
    return (key == null ? null : _cache?[key]) ?? const DeviceLabel();
  }

  /// Persists an edited label for [device]. Passing an empty label removes it.
  Future<void> setLabel(NetworkDevice device, DeviceLabel label) async {
    final key = deviceLabelKey(device);
    if (key == null) return;
    final labels = {...await _labels()};
    if (label.isEmpty) {
      labels.remove(key);
    } else {
      labels[key] = label;
    }
    _cache = labels;
    await _store.save(labels);
  }
}
