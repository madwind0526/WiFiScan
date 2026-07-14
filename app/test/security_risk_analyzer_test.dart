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

  test('reports exposed plaintext services with observed-port evidence', () {
    final device = NetworkDevice(
      id: 'router',
      displayName: 'ipTIME 공유기',
      category: DeviceCategory.router,
      ownershipStatus: OwnershipStatus.confirmed,
      ipAddresses: const ['192.168.0.1'],
      sources: const [DiscoverySource.router, DiscoverySource.serviceProbe],
      firstSeenAt: DateTime(2026, 7, 15),
      lastSeenAt: DateTime(2026, 7, 15),
      identityConfidence: 0.9,
      modelName: 'A6004NS-M',
      services: const [
        NetworkServiceObservation(
          protocol: 'telnet',
          port: 23,
          transport: NetworkTransport.tcp,
          source: DiscoverySource.serviceProbe,
        ),
        NetworkServiceObservation(
          protocol: 'http',
          port: 80,
          transport: NetworkTransport.tcp,
          source: DiscoverySource.serviceProbe,
        ),
      ],
    );
    final snapshot = _snapshot([device]);

    final report = const SecurityRiskAnalyzer().analyze(
      snapshot: snapshot,
      inventoryUpdate: InventoryUpdate(
        snapshot: snapshot,
        newDevices: const [],
        disappearedDevices: const [],
        changedDevices: const [],
        isBaseline: false,
      ),
    );

    expect(
      report.findings.map((finding) => finding.title),
      containsAll([
        '평문 원격 접속 서비스 노출',
        'HTTPS 없이 웹 서비스가 열려 있습니다',
        'ipTIME A6004NS-M 펌웨어 확인 필요',
      ]),
    );
    expect(
      report.findings
          .firstWhere((finding) => finding.id.startsWith('plaintext-remote'))
          .evidence,
      contains('23/tcp'),
    );
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
