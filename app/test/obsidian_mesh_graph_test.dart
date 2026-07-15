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

  test('multiple networks share one circular graph boundary', () {
    const engine = MeshGraphLayoutEngine();
    const ids = ['gw-a', 'a1', 'a2', 'gw-b', 'b1', 'b2'];
    const groups = {'gw-a': 0, 'a1': 0, 'a2': 0, 'gw-b': 1, 'b1': 1, 'b2': 1};
    const size = Size(700, 700);
    final layout = engine.calculate(
      nodeIds: ids,
      edges: const [
        MeshGraphEdge('gw-a', 'a1'),
        MeshGraphEdge('gw-a', 'a2'),
        MeshGraphEdge('gw-b', 'b1'),
        MeshGraphEdge('gw-b', 'b2'),
        MeshGraphEdge(
          'gw-a',
          'gw-b',
          preferredDistance: 120,
          springStrength: 3,
        ),
      ],
      groups: groups,
      hubIds: const {'gw-a', 'gw-b'},
      size: size,
    );
    final center = size.center(Offset.zero);
    for (final position in layout.positions.values) {
      expect((position - center).distance, lessThanOrEqualTo(280.001));
    }
    Offset centroid(int group) {
      final points = [
        for (final entry in layout.positions.entries)
          if (groups[entry.key] == group) entry.value,
      ];
      return Offset(
        points.map((point) => point.dx).reduce((a, b) => a + b) / points.length,
        points.map((point) => point.dy).reduce((a, b) => a + b) / points.length,
      );
    }

    final groupDistance = (centroid(0) - centroid(1)).distance;
    expect(groupDistance, greaterThan(55));
    expect(groupDistance, lessThan(190));
  });

  testWidgets('shows solid circle legend and opens the tapped device', (
    tester,
  ) async {
    final devices = [
      _device('router', '거실 공유기', DeviceCategory.router, '192.168.0.1'),
      _device('pc', '내 PC', DeviceCategory.computer, '192.168.0.2'),
      _device('phone', '핸드폰', DeviceCategory.phone, '192.168.0.3'),
      _device('tv', '거실 TV', DeviceCategory.television, '192.168.0.4'),
      _device('appliance', '스마트공기청정기', DeviceCategory.appliance, '192.168.0.5'),
      _device('other', '확인되지 않은 장비', DeviceCategory.unknown, '192.168.0.6'),
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

    expect(find.text('Mesh'), findsOneWidget);
    expect(find.text('WiFi'), findsOneWidget);
    expect(find.text('PC'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('스마트공기청정기'), findsNothing);
    expect(find.text('스마트공기...'), findsOneWidget);
    expect(find.text('범례'), findsNothing);
    expect(find.text('확인되지 않은 장비'), findsNothing);
    final labelRight = tester.getTopRight(find.text('WiFi')).dx;
    for (final label in ['PC', 'Phone', 'TV', 'Home']) {
      expect(tester.getTopRight(find.text(label)).dx, closeTo(labelRight, 0.1));
    }
    expect(
      tester.getCenter(find.byKey(const ValueKey('legend-circle-router'))).dx,
      greaterThan(labelRight),
    );
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
