import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/dashboard/presentation/obsidian_mesh_graph.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

void main() {
  test('force layout is deterministic and remains inside its canvas', () {
    const engine = MeshGraphLayoutEngine();
    const ids = ['router', 'pc', 'phone', 'tv'];
    const edges = [
      MeshGraphEdge('router', 'pc'),
      MeshGraphEdge('router', 'phone'),
      MeshGraphEdge('router', 'tv'),
    ];
    const groups = {'router': 0, 'pc': 0, 'phone': 0, 'tv': 0};
    const size = Size(640, 480);

    final first = engine.calculate(
      nodeIds: ids,
      edges: edges,
      groups: groups,
      hubIds: const {'router'},
      size: size,
    );
    final second = engine.calculate(
      nodeIds: ids,
      edges: edges,
      groups: groups,
      hubIds: const {'router'},
      size: size,
    );

    expect(second.positions, first.positions);
    expect(first.positions.values.toSet(), hasLength(ids.length));
    for (final position in first.positions.values) {
      expect(position.dx, inInclusiveRange(58, size.width - 58));
      expect(position.dy, inInclusiveRange(58, size.height - 58));
    }
  });

  testWidgets('shows sphere legend and opens the tapped device', (
    tester,
  ) async {
    final devices = [
      _device('router', '거실 공유기', DeviceCategory.router, '192.168.0.1'),
      _device('pc', '내 PC', DeviceCategory.computer, '192.168.0.2'),
      _device('phone', '핸드폰', DeviceCategory.phone, '192.168.0.3'),
      _device('tv', '거실 TV', DeviceCategory.television, '192.168.0.4'),
      _device('appliance', '공기청정기', DeviceCategory.appliance, '192.168.0.5'),
      _device('other', '확인 필요', DeviceCategory.unknown, '192.168.0.6'),
    ];
    NetworkDevice? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 620,
              child: ObsidianMeshGraph(
                devices: devices,
                newDeviceIds: const {},
                gateway: '192.168.0.1',
                onDeviceTap: (device) => tapped = device,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('메시 그래프'), findsOneWidget);
    expect(find.text('Wi-Fi 공유기'), findsOneWidget);
    expect(find.text('PC'), findsOneWidget);
    expect(find.text('핸드폰'), findsWidgets);
    expect(find.text('모니터/TV'), findsOneWidget);
    expect(find.text('가전제품'), findsOneWidget);
    expect(find.text('기타'), findsOneWidget);
    expect(find.byKey(const ValueKey('mesh-zoom-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('mesh-fit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mesh-node-phone')));
    await tester.pump();
    expect(tapped?.id, 'phone');
  });
}

NetworkDevice _device(
  String id,
  String name,
  DeviceCategory category,
  String ip,
) {
  final now = DateTime(2026, 7, 15);
  return NetworkDevice(
    id: id,
    displayName: name,
    category: category,
    ownershipStatus: OwnershipStatus.confirmed,
    ipAddresses: [ip],
    sources: id == 'pc'
        ? const [DiscoverySource.localInterface]
        : const [DiscoverySource.subnet],
    firstSeenAt: now,
    lastSeenAt: now,
    identityConfidence: 0.9,
  );
}
