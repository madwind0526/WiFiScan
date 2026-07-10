import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/dashboard/domain/network_overview.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';

void main() {
  test('summarizes unconfirmed devices and security findings', () {
    final now = DateTime(2026, 7, 10);
    final overview = NetworkOverview(
      devices: [
        NetworkDevice(
          id: 'device-1',
          displayName: '확인되지 않은 장비',
          category: DeviceCategory.unknown,
          ownershipStatus: OwnershipStatus.unconfirmed,
          ipAddresses: const ['192.0.2.10'],
          sources: const [DiscoverySource.subnet],
          firstSeenAt: now,
          lastSeenAt: now,
          identityConfidence: 0.4,
        ),
      ],
      findings: const [
        SecurityFinding(
          id: 'finding-1',
          title: '확인이 필요한 장비',
          description: '소유 여부를 확인해야 합니다.',
          evidence: '새 장비가 처음 관측되었습니다.',
          severity: FindingSeverity.warning,
          confidence: 0.8,
          recommendedActions: ['장비 소유 여부 확인'],
          remediationMode: RemediationMode.guidanceOnly,
        ),
        SecurityFinding(
          id: 'finding-2',
          title: '긴급 확인 필요',
          description: '관리 화면에서 즉시 확인해야 합니다.',
          evidence: '기준선과 다른 서비스가 관측되었습니다.',
          severity: FindingSeverity.critical,
          confidence: 0.7,
          recommendedActions: ['장비 네트워크 격리'],
          remediationMode: RemediationMode.guidanceOnly,
        ),
      ],
      lastScannedAt: now,
    );

    expect(overview.devices, hasLength(1));
    expect(overview.unconfirmedDeviceCount, 1);
    expect(overview.warningCount, 1);
    expect(overview.criticalCount, 1);
  });
}
