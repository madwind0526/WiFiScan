import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/app/wifi_scan_app.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';

void main() {
  testWidgets('shows the network security dashboard', (tester) async {
    await tester.pumpWidget(const WifiScanApp());

    expect(find.text('와이파이 보안 점검'), findsOneWidget);
    expect(find.text('탐지된 장비'), findsOneWidget);
    expect(find.text('미확인 장비'), findsOneWidget);
    expect(find.text('현재 네트워크 검색 시작'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('보안 경고'), 300);
    expect(find.text('보안 경고'), findsOneWidget);
  });

  testWidgets('shows discovered devices after a completed scan', (
    tester,
  ) async {
    await tester.pumpWidget(
      WifiScanApp(
        discoveryService: const _FakeDiscoveryService(),
        inventoryRepository: InventoryRepository(store: _MemorySnapshotStore()),
      ),
    );

    await tester.tap(find.text('현재 네트워크 검색 시작'));
    await tester.pumpAndSettle();

    expect(find.textContaining('검색이 완료되었습니다.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('이 Windows 컴퓨터'), 300);
    expect(find.text('이 Windows 컴퓨터'), findsOneWidget);
    expect(find.text('기본 게이트웨이'), findsOneWidget);
  });

  testWidgets('allows the user to stop an active scan', (tester) async {
    await tester.pumpWidget(
      const WifiScanApp(discoveryService: _SlowDiscoveryService()),
    );

    await tester.tap(find.text('현재 네트워크 검색 시작'));
    await tester.pump();
    expect(find.text('검색 중지 요청'), findsOneWidget);

    await tester.tap(find.text('검색 중지 요청'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('검색을 중지했습니다.'), findsOneWidget);
    expect(find.text('현재 네트워크 검색 시작'), findsOneWidget);
  });

  testWidgets('supports a small screen without layout exceptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const WifiScanApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('현재 네트워크 검색 시작'), 200);
    expect(find.text('현재 네트워크 검색 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeDiscoveryService implements NetworkDiscoveryService {
  const _FakeDiscoveryService();

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.probing,
        completed: 1,
        total: 1,
      ),
    );
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
      devices: [
        NetworkDevice(
          id: 'local:192.168.0.30',
          displayName: '이 Windows 컴퓨터',
          category: DeviceCategory.computer,
          ownershipStatus: OwnershipStatus.confirmed,
          ipAddresses: const ['192.168.0.30'],
          sources: const [DiscoverySource.localInterface],
          firstSeenAt: DateTime(2026, 7, 11),
          lastSeenAt: DateTime(2026, 7, 11),
          identityConfidence: 1,
        ),
        NetworkDevice(
          id: 'router:192.168.0.1',
          displayName: '기본 게이트웨이',
          category: DeviceCategory.router,
          ownershipStatus: OwnershipStatus.unconfirmed,
          ipAddresses: const ['192.168.0.1'],
          sources: const [DiscoverySource.router, DiscoverySource.neighbor],
          firstSeenAt: DateTime(2026, 7, 11),
          lastSeenAt: DateTime(2026, 7, 11),
          identityConfidence: 0.85,
        ),
      ],
      limitations: const ['테스트 검색 결과입니다.'],
      duration: Duration.zero,
    );
  }
}

class _SlowDiscoveryService implements NetworkDiscoveryService {
  const _SlowDiscoveryService();

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.probing,
        completed: 0,
        total: 1,
      ),
    );
    while (!cancellationToken.isCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw const DiscoveryCancelledException();
  }
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
