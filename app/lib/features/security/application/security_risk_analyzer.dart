import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';

class SecurityAnalysis {
  const SecurityAnalysis({required this.findings});

  final List<SecurityFinding> findings;
}

class SecurityRiskAnalyzer {
  const SecurityRiskAnalyzer();

  SecurityAnalysis analyze({
    required InventorySnapshot snapshot,
    required InventoryUpdate inventoryUpdate,
  }) {
    final findings = <SecurityFinding>[];
    final newDeviceIds = inventoryUpdate.newDevices
        .map((device) => device.id)
        .toSet();

    for (final device in snapshot.devices) {
      if (device.ownershipStatus == OwnershipStatus.unconfirmed) {
        final isNew = newDeviceIds.contains(device.id);
        findings.add(
          SecurityFinding(
            id: 'unconfirmed:${device.id}',
            title: isNew ? '새로 탐지된 장비 확인 필요' : '소유자 확인이 필요한 장비',
            description: isNew
                ? '${device.displayName}가 이전 기준선에 없었습니다.'
                : '${device.displayName}의 소유자와 사용 목적이 확인되지 않았습니다.',
            evidence: _evidenceFor(device),
            severity: FindingSeverity.warning,
            confidence: device.identityConfidence.clamp(0.0, 1.0).toDouble(),
            recommendedActions: const [
              '장비의 소유자와 사용 목적을 확인하세요.',
              '모르는 장비라면 공유기 접속 목록에서 차단을 검토하세요.',
            ],
            remediationMode: RemediationMode.guidanceOnly,
            deviceId: device.id,
          ),
        );
      }
    }

    if (snapshot.context.coverageLimited) {
      findings.add(
        const SecurityFinding(
          id: 'coverage:limited',
          title: '검색 범위가 제한되었습니다',
          description: '현재 네트워크가 넓어 일부 주소만 탐색했습니다.',
          evidence: '능동 탐색은 최대 /24 범위로 제한됩니다.',
          severity: FindingSeverity.information,
          confidence: 1,
          recommendedActions: [
            '다른 VLAN이나 게스트망을 별도로 점검하세요.',
            '공유기의 전체 접속 목록과 결과를 비교하세요.',
          ],
          remediationMode: RemediationMode.guidanceOnly,
        ),
      );
    }

    return SecurityAnalysis(findings: findings);
  }

  static String _evidenceFor(NetworkDevice device) {
    final sources = device.sources.map((source) => source.name).join(', ');
    final addresses = device.ipAddresses.join(', ');
    return '관측 출처: $sources · 주소: $addresses · 식별 신뢰도: '
        '${(device.identityConfidence * 100).round()}%';
  }
}
