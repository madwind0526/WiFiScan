import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/security/application/security_risk_analyzer.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';

void main() {
  test('reports an unconfirmed device with evidence and guidance', () {
    final device = _device();
    final snapshot = _snapshot([device]);
    final report = const SecurityRiskAnalyzer().analyze(
      snapshot: snapshot,
      inventoryUpdate: InventoryUpdate(
        snapshot: snapshot,
        newDevices: [device],
        disappearedDevices: const [],
        changedDevices: const [],
        isBaseline: false,
      ),
    );

    expect(report.findings, hasLength(1));
    expect(report.findings.single.severity, FindingSeverity.warning);
    expect(report.findings.single.evidence, contains('192.168.0.40'));
    expect(report.findings.single.recommendedActions, isNotEmpty);
  });

  test('reports limited coverage without claiming the network is safe', () {
    final snapshot = _snapshot(const [], coverageLimited: true);
    final report = const SecurityRiskAnalyzer().analyze(
      snapshot: snapshot,
      inventoryUpdate: InventoryUpdate(
        snapshot: snapshot,
        newDevices: const [],
        disappearedDevices: const [],
        changedDevices: const [],
        isBaseline: true,
      ),
    );

    expect(report.findings, hasLength(1));
    expect(report.findings.single.title, '검색 범위가 제한되었습니다');
    expect(report.findings.single.severity, FindingSeverity.information);
  });
}

InventorySnapshot _snapshot(
  List<NetworkDevice> devices, {
  bool coverageLimited = false,
}) {
  return InventorySnapshot(
    scannedAt: DateTime(2026, 7, 11),
    networkKey: '192.168.0.0/24',
    context: NetworkContext(
      interfaceName: 'Wi-Fi',
      interfaceIndex: 1,
      ipv4Address: '192.168.0.30',
      prefixLength: 24,
      gateway: '192.168.0.1',
      scannedNetwork: '192.168.0.0',
      scannedPrefixLength: 24,
      coverageLimited: coverageLimited,
    ),
    devices: devices,
    limitations: const [],
  );
}

NetworkDevice _device() {
  return NetworkDevice(
    id: 'ip:192.168.0.40',
    displayName: '확인되지 않은 장비',
    category: DeviceCategory.unknown,
    ownershipStatus: OwnershipStatus.unconfirmed,
    ipAddresses: const ['192.168.0.40'],
    sources: const [DiscoverySource.neighbor],
    firstSeenAt: DateTime(2026, 7, 11),
    lastSeenAt: DateTime(2026, 7, 11),
    identityConfidence: 0.6,
  );
}
