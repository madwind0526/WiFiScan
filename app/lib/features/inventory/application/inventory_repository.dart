import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/inventory/application/inventory_identity_correlator.dart';
import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

abstract interface class InventorySnapshotStore {
  Future<List<InventorySnapshot>> load();

  Future<void> save(List<InventorySnapshot> snapshots);
}

class FileInventorySnapshotStore implements InventorySnapshotStore {
  const FileInventorySnapshotStore({this.maxSnapshots = 30});

  final int maxSnapshots;

  @override
  Future<List<InventorySnapshot>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => InventorySnapshot.fromJson(item.cast<String, Object?>()),
          )
          .toList(growable: false);
    } on FormatException {
      throw const InventoryStorageException('로컬 장비 기록을 읽지 못했습니다.');
    } on FileSystemException {
      throw const InventoryStorageException('로컬 장비 기록에 접근하지 못했습니다.');
    }
  }

  @override
  Future<void> save(List<InventorySnapshot> snapshots) async {
    final file = await _file();
    try {
      await file.parent.create(recursive: true);
      final retained = snapshots.length <= maxSnapshots
          ? snapshots
          : snapshots.sublist(snapshots.length - maxSnapshots);
      await file.writeAsString(
        jsonEncode(retained.map((snapshot) => snapshot.toJson()).toList()),
        flush: true,
      );
    } on FileSystemException {
      throw const InventoryStorageException('로컬 장비 기록을 저장하지 못했습니다.');
    }
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}inventory_snapshots.json',
    );
  }
}

class InventoryStorageException implements Exception {
  const InventoryStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InventoryUpdate {
  const InventoryUpdate({
    required this.snapshot,
    required this.newDevices,
    required this.disappearedDevices,
    required this.changedDevices,
    required this.isBaseline,
  });

  final InventorySnapshot snapshot;
  final List<NetworkDevice> newDevices;
  final List<NetworkDevice> disappearedDevices;
  final List<NetworkDevice> changedDevices;
  final bool isBaseline;
}

class InventoryRepository {
  const InventoryRepository({
    required this.store,
    this.correlator = const InventoryIdentityCorrelator(),
  });

  final InventorySnapshotStore store;
  final InventoryIdentityCorrelator correlator;

  Future<InventoryUpdate> record(DiscoveryResult result) async {
    final snapshots = await store.load();
    final networkKey = result.context.scannedSubnet;
    InventorySnapshot? previous;
    for (final snapshot in snapshots.reversed) {
      if (snapshot.networkKey == networkKey) {
        previous = snapshot;
        break;
      }
    }

    final correlation = correlator.correlate(
      current: result.devices,
      previous: previous,
    );
    final snapshot = InventorySnapshot(
      scannedAt: DateTime.now(),
      networkKey: networkKey,
      context: result.context,
      devices: correlation.devices,
      limitations: result.limitations,
    );
    await store.save([...snapshots, snapshot]);

    return InventoryUpdate(
      snapshot: snapshot,
      newDevices: correlation.newDevices,
      disappearedDevices: correlation.disappearedDevices,
      changedDevices: correlation.changedDevices,
      isBaseline: previous == null,
    );
  }
}
